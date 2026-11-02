-- Verify-first signup: prove phone ownership BEFORE a users row or a welcome SMS exists.
--
-- WHY THIS EXISTS
-- Until now anyone could type a stranger's number into ozzily.com and that stranger
-- received the welcome SMS, while a users row recorded consent_at / consent_text as
-- though they had agreed. That is a false consent record in the A2P audit trail. The
-- fix is to defer BOTH the row and the SMS until Twilio Verify approves a code sent to
-- that number.
--
-- Our own rate limits sit IN FRONT of Twilio's, because Verify's limits only engage
-- once a request has reached Twilio and already cost money (~$0.05 per verification).

-- --------------------------------------------------------------- preferred_plan
-- The landing page collects a plan preference at signup. The old flow wrote it into
-- users.plan as the literal string 'unspecified', which is the BILLING plan column
-- that apply_payment_event() owns -- a preference must never sit in a column that
-- billing treats as fact. Preference gets its own column; plan stays null until a
-- payment sets it.
alter table public.users
  add column if not exists preferred_plan text;

do $mig$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'users_preferred_plan_check'
  ) then
    alter table public.users
      add constraint users_preferred_plan_check
      check (preferred_plan is null or preferred_plan in ('monthly', 'annual'));
  end if;
end $mig$;

-- ---------------------------------------------------------- verification_attempts
-- One row per attempt, written BEFORE the Twilio call so the count is honest even if
-- the call fails. The IP is stored only as a salted hash: we need to count per IP,
-- we never need to know the address.
create table if not exists public.verification_attempts (
  id          bigserial primary key,
  phone       text not null,
  ip_hash     text,
  action      text not null check (action in ('start', 'confirm')),
  outcome     text not null default 'requested'
              check (outcome in ('requested', 'blocked', 'approved', 'denied')),
  created_at  timestamptz not null default now()
);

create index if not exists verification_attempts_phone_idx
  on public.verification_attempts (phone, created_at desc);

create index if not exists verification_attempts_ip_idx
  on public.verification_attempts (ip_hash, created_at desc)
  where ip_hash is not null;

-- Zero policies, as with every other table here: all access is service_role only.
alter table public.verification_attempts enable row level security;

-- -------------------------------------------------------------- verify_rate_check
-- Records the attempt and returns whether it may proceed.
--
-- INSERT FIRST, THEN COUNT. Counting before inserting lets two concurrent requests
-- both read "2 so far" and both proceed. Inserting first means each caller counts its
-- own row, so the limit cannot be exceeded by racing.
create or replace function public.verify_rate_check(
  p_phone   text,
  p_ip_hash text,
  p_action  text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_phone_hour  int;
  v_phone_day   int;
  v_ip_hour     int;
  v_ip_day      int;
  v_id          bigint;
  v_reason      text := null;
begin
  if p_action not in ('start', 'confirm') then
    return jsonb_build_object('allowed', false, 'reason', 'bad_action');
  end if;

  insert into public.verification_attempts (phone, ip_hash, action)
  values (p_phone, p_ip_hash, p_action)
  returning id into v_id;

  select count(*) into v_phone_hour
    from public.verification_attempts
   where phone = p_phone and action = p_action
     and created_at > now() - interval '1 hour';

  select count(*) into v_phone_day
    from public.verification_attempts
   where phone = p_phone and action = p_action
     and created_at > now() - interval '24 hours';

  if p_ip_hash is not null then
    select count(*) into v_ip_hour
      from public.verification_attempts
     where ip_hash = p_ip_hash
       and created_at > now() - interval '1 hour';

    select count(*) into v_ip_day
      from public.verification_attempts
     where ip_hash = p_ip_hash
       and created_at > now() - interval '24 hours';
  else
    v_ip_hour := 0;
    v_ip_day  := 0;
  end if;

  if p_action = 'start' then
    -- A real person needs one code, occasionally two. Three in an hour is already
    -- generous; each one is a paid SMS plus a Verify charge.
    if v_phone_hour > 3 then v_reason := 'phone_hourly';
    elsif v_phone_day > 5 then v_reason := 'phone_daily';
    elsif v_ip_hour  > 10 then v_reason := 'ip_hourly';
    elsif v_ip_day   > 20 then v_reason := 'ip_daily';
    end if;
  else
    -- Guessing a 6-digit code needs far more than this to be worth trying, and
    -- Twilio caps checks per verification independently.
    if v_phone_hour > 8 then v_reason := 'phone_hourly';
    elsif v_ip_hour > 25 then v_reason := 'ip_hourly';
    end if;
  end if;

  if v_reason is not null then
    update public.verification_attempts set outcome = 'blocked' where id = v_id;
    return jsonb_build_object('allowed', false, 'reason', v_reason, 'attempt_id', v_id);
  end if;

  return jsonb_build_object('allowed', true, 'attempt_id', v_id);
end $fn$;

-- ------------------------------------------------------------ verify_mark_outcome
create or replace function public.verify_mark_outcome(
  p_attempt_id bigint,
  p_outcome    text
) returns void
language sql
security definer
set search_path = public, pg_temp
as $fn$
  update public.verification_attempts
     set outcome = p_outcome
   where id = p_attempt_id
     and p_outcome in ('requested', 'blocked', 'approved', 'denied');
$fn$;

-- ------------------------------------------------------------ create_verified_user
-- Called ONLY after Twilio Verify has approved a code for this phone.
--
-- Returns what is TRUE after the write, not what was intended -- the same rule that
-- apply_payment_event() and scheduled_messages.status had to learn. is_new decides
-- whether the caller sends the welcome SMS or something else, so it must come from
-- the row, not from a guess.
create or replace function public.create_verified_user(
  p_phone          text,
  p_preferred_plan text default null,
  p_consent_text   text default 'sms_opt_in_v2'
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_id      uuid;
  v_new     boolean;
  v_status  text;
  v_step    text;
  v_plan    text;
begin
  if p_phone !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_phone');
  end if;

  v_plan := case when p_preferred_plan in ('monthly', 'annual')
                 then p_preferred_plan else null end;

  insert into public.users (phone, preferred_plan, consent_at, consent_text)
  values (p_phone, v_plan, now(), coalesce(p_consent_text, 'sms_opt_in_v2'))
  on conflict (phone) do update
    set preferred_plan = coalesce(excluded.preferred_plan, public.users.preferred_plan),
        -- The FIRST consent is the one that matters for the audit trail; a later
        -- signup must not overwrite when it was given.
        consent_at     = coalesce(public.users.consent_at, excluded.consent_at),
        consent_text   = coalesce(public.users.consent_text, excluded.consent_text),
        -- A verified signup with the consent box ticked is a genuine re-opt-in, so
        -- it clears an earlier STOP. Nothing else in the system may do that.
        sms_opted_out  = false,
        opted_out_at   = case when public.users.sms_opted_out then null
                              else public.users.opted_out_at end,
        updated_at     = now()
  returning id, (xmax = 0), subscription_status, onboarding_step
       into v_id, v_new, v_status, v_step;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_id,
    'is_new', v_new,
    'subscription_status', v_status,
    'onboarding_step', v_step
  );
end $fn$;

-- ------------------------------------------------------------- log_outbound_sms
create or replace function public.log_outbound_sms(
  p_user_id    uuid,
  p_body       text,
  p_kind       text default 'onboarding',
  p_twilio_sid text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_id uuid;
begin
  insert into public.messages (user_id, direction, body, message_kind, twilio_sid)
  values (p_user_id, 'outbound', p_body, p_kind, p_twilio_sid)
  returning id into v_id;
  return v_id;
end $fn$;

-- ------------------------------------------------------------------------ grants
-- Postgres grants EXECUTE to PUBLIC by default, and create-or-replace carries an
-- existing ACL forward -- which is how ai_brain_system_prompt() ended up readable by
-- anon over /rest/v1/rpc/. Revoke explicitly, every time.
revoke all on function public.verify_rate_check(text, text, text)      from public, anon, authenticated;
revoke all on function public.verify_mark_outcome(bigint, text)        from public, anon, authenticated;
revoke all on function public.create_verified_user(text, text, text)   from public, anon, authenticated;
revoke all on function public.log_outbound_sms(uuid, text, text, text) from public, anon, authenticated;

grant execute on function public.verify_rate_check(text, text, text)      to service_role;
grant execute on function public.verify_mark_outcome(bigint, text)        to service_role;
grant execute on function public.create_verified_user(text, text, text)   to service_role;
grant execute on function public.log_outbound_sms(uuid, text, text, text) to service_role;

-- New function signatures are invisible to PostgREST until its schema cache reloads.
notify pgrst, 'reload schema';
