-- Two unrelated hardening changes, applied together because both must land before
-- the first real signup and the first real charge.
--
-- 1. A GLOBAL daily cap on verification starts. The per-phone and per-IP limits bound
--    one attacker; they do nothing against a distributed burst, where every request
--    looks like a different first-time visitor. Each start costs roughly $0.05 of
--    Verify plus an SMS, so without a global ceiling the worst case is unbounded.
--
-- 2. payments now records Paddle's tax, fee and earnings alongside grand_total.
--    Storing only the gross means we can never answer "what did we actually keep",
--    and Paddle is the merchant of record so the tax figure is the one that matters
--    for reconciliation.

-- ================================================ 1. global cap on verification starts
--
-- The cap is a constant here on purpose: a single source of truth that one
-- create-or-replace can change, rather than a signature change needing a PostgREST
-- schema reload. 200 starts/day bounds worst-case spend at roughly $13.
--
-- The trade is real and deliberate: once tripped, NOBODY can sign up until the window
-- rolls. That is the correct direction to fail -- a day of lost signups is recoverable,
-- an unbounded bill is not -- which is exactly why the caller alerts at 80% rather
-- than waiting for the ceiling.
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
  v_global_day  int;
  v_id          bigint;
  v_reason      text := null;
  c_global_cap  constant int := 200;
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

  -- Counted for both actions so the figure can be reported, but only enforced on
  -- 'start'. Capping 'confirm' would strand people who already hold a valid code and
  -- have already cost us the money.
  select count(*) into v_global_day
    from public.verification_attempts
   where action = 'start'
     and created_at > now() - interval '24 hours';

  if p_action = 'start' then
    -- A real person needs one code, occasionally two. Three in an hour is already
    -- generous; each one is a paid SMS plus a Verify charge.
    if v_phone_hour > 3 then v_reason := 'phone_hourly';
    elsif v_phone_day > 5 then v_reason := 'phone_daily';
    elsif v_ip_hour  > 10 then v_reason := 'ip_hourly';
    elsif v_ip_day   > 20 then v_reason := 'ip_daily';
    elsif v_global_day > c_global_cap then v_reason := 'global_daily';
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
    return jsonb_build_object('allowed', false, 'reason', v_reason, 'attempt_id', v_id,
                              'global_used', v_global_day, 'global_cap', c_global_cap);
  end if;

  -- global_used/global_cap are returned on the success path too, so the caller can
  -- warn while signups are still working rather than only once they have stopped.
  return jsonb_build_object('allowed', true, 'attempt_id', v_id,
                            'global_used', v_global_day, 'global_cap', c_global_cap);
end $fn$;

-- ----------------------------------------------------------- verification_health()
-- One honest query. The lesson from checkin_delivery_health() is that a health check
-- which can return green during the outage it exists to catch is worse than none, so
-- `healthy` is false whenever signups are actually impaired -- not merely when a
-- counter looks tidy.
create or replace function public.verification_health()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_starts        int;
  v_cap           constant int := 200;
  v_blocked       int;
  v_global_block  int;
  v_confirm_ok    int;
  v_confirm_bad   int;
  v_healthy       boolean;
  -- Appended values are cast to text explicitly. `v_reasons || 'some string'` makes
  -- Postgres parse the right-hand side as an ARRAY LITERAL and raise 22P02 -- which
  -- fires only once there is a problem to report, so the happy path passes and the
  -- check dies precisely during the outage it exists to catch. Caught in testing.
  v_reasons       text[] := array[]::text[];
begin
  select count(*) filter (where action = 'start'),
         count(*) filter (where action = 'start' and outcome = 'blocked'),
         count(*) filter (where action = 'confirm' and outcome = 'approved'),
         count(*) filter (where action = 'confirm' and outcome = 'denied')
    into v_starts, v_blocked, v_confirm_ok, v_confirm_bad
    from public.verification_attempts
   where created_at > now() - interval '24 hours';

  select count(*) into v_global_block
    from public.verification_attempts
   where action = 'start' and outcome = 'blocked'
     and created_at > now() - interval '24 hours';

  if v_starts > v_cap then
    v_reasons := v_reasons || 'global daily cap reached: signups are being refused'::text;
  elsif v_starts >= (v_cap * 0.8)::int then
    v_reasons := v_reasons || 'global daily starts above 80% of cap'::text;
  end if;

  -- A high refusal rate on a low-traffic product means either an attack or a broken
  -- gate. Either way it is not healthy, and either way someone should look.
  if v_starts >= 20 and v_blocked::numeric / greatest(v_starts, 1) > 0.5 then
    v_reasons := v_reasons || 'more than half of starts are being blocked'::text;
  end if;

  if (v_confirm_ok + v_confirm_bad) >= 20
     and v_confirm_bad::numeric / greatest(v_confirm_ok + v_confirm_bad, 1) > 0.8 then
    v_reasons := v_reasons || 'more than 80% of code confirmations are failing'::text;
  end if;

  v_healthy := (coalesce(array_length(v_reasons, 1), 0) = 0);

  return jsonb_build_object(
    'healthy', v_healthy,
    'window', '24h',
    'starts', v_starts,
    'global_cap', v_cap,
    'pct_of_cap', round((v_starts::numeric / v_cap) * 100, 1),
    'starts_blocked', v_blocked,
    'confirms_approved', v_confirm_ok,
    'confirms_denied', v_confirm_bad,
    'problems', to_jsonb(v_reasons)
  );
end $fn$;

-- ================================================== 2. payments: tax, fee, earnings
--
-- Nullable on purpose. Paddle populates fee and earnings only once a transaction has
-- settled, so a completed-but-unsettled event legitimately has neither -- and 0 would
-- be a lie, not a default.
alter table public.payments
  add column if not exists tax_cents      integer,
  add column if not exists fee_cents      integer,
  add column if not exists earnings_cents integer;

comment on column public.payments.tax_cents is
  'Paddle details.totals.tax. Paddle is merchant of record, so this is the tax Paddle collected and remits, not a liability of ours.';
comment on column public.payments.fee_cents is
  'Paddle details.totals.fee. Null until the transaction settles.';
comment on column public.payments.earnings_cents is
  'Paddle details.totals.earnings -- what actually reaches us. Null until settled.';

-- apply_payment_event gains three params. Adding arguments changes the signature, so
-- the old one must be dropped and PostgREST's schema cache reloaded, or the AI Brain
-- pattern repeats: the database has the new function, PostgREST keeps serving the old
-- shape, the call fails to resolve and the route exits silently.
drop function if exists public.apply_payment_event(
  text, text, text, text, text, text, text, text, text, text, text, text, text);

create or replace function public.apply_payment_event(
  p_event_id                 text,
  p_event_type               text,
  p_occurred_at              text default null,
  p_user_id                  text default null,
  p_provider_customer_id     text default null,
  p_provider_subscription_id text default null,
  p_provider_transaction_id  text default null,
  p_amount_cents             text default null,
  p_currency                 text default null,
  p_plan                     text default null,
  p_failure_reason           text default null,
  p_paddle_status            text default null,
  p_next_billed_at           text default null,
  p_tax_cents                text default null,
  p_fee_cents                text default null,
  p_earnings_cents           text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid        uuid;
  v_event      text := lower(btrim(coalesce(p_event_type,'')));
  v_eid        text := nullif(btrim(coalesce(p_event_id,'')),'');
  v_occurred   timestamptz := nullif(btrim(coalesce(p_occurred_at,'')),'')::timestamptz;
  v_next       timestamptz := nullif(btrim(coalesce(p_next_billed_at,'')),'')::timestamptz;
  v_pstatus    text := lower(btrim(coalesce(p_paddle_status,'')));
  v_last       timestamptz;
  v_sub_status text;
  v_source     text;
  v_pay_status text;
  v_amount     integer := nullif(btrim(coalesce(p_amount_cents,'')),'')::integer;
  v_tax        integer := nullif(btrim(coalesce(p_tax_cents,'')),'')::integer;
  v_fee        integer := nullif(btrim(coalesce(p_fee_cents,'')),'')::integer;
  v_earn       integer := nullif(btrim(coalesce(p_earnings_cents,'')),'')::integer;
  v_plan       text := lower(nullif(btrim(coalesce(p_plan,'')),''));
  v_inserted   boolean := false;
  v_applied    boolean := false;
  v_skipped    text;
  v_actual     text;
  v_trial_end  timestamptz;
begin
  if v_eid is null then
    return jsonb_build_object('ok', false, 'error', 'missing event id');
  end if;

  -- Resolve the user. custom_data.user_id on the checkout is the primary link:
  -- Ozzily never collects an email, so the Paddle customer cannot be matched that way.
  v_uid := nullif(btrim(coalesce(p_user_id,'')),'')::uuid;

  if v_uid is null and nullif(btrim(coalesce(p_provider_subscription_id,'')),'') is not null then
    select id into v_uid from public.users
     where provider_subscription_id = btrim(p_provider_subscription_id) limit 1;
  end if;

  if v_uid is null and nullif(btrim(coalesce(p_provider_customer_id,'')),'') is not null then
    select id into v_uid from public.users
     where provider_customer_id = btrim(p_provider_customer_id) limit 1;
  end if;

  if v_uid is null or not exists (select 1 from public.users where id = v_uid) then
    return jsonb_build_object('ok', false, 'error', 'user not resolved',
                              'event_id', v_eid, 'event_type', v_event);
  end if;

  -- Status resolution, in priority order.
  -- 1. Paddle's own data.status is authoritative when supplied. Paddle spells the
  --    cancelled state 'canceled' with one l; ours uses two.
  v_sub_status := case v_pstatus
                    when 'trialing' then 'trial'
                    when 'active'   then 'active'
                    when 'past_due' then 'past_due'
                    when 'paused'   then 'paused'
                    when 'canceled' then 'cancelled'
                    else null
                  end;
  if v_sub_status is not null then
    v_source := 'paddle data.status';
  end if;

  -- 2. Fall back to the event name. Note subscription.updated is deliberately absent:
  --    it carries no implied status, so without data.status there is nothing to apply.
  if v_sub_status is null then
    v_sub_status := case
      when v_event in ('subscription.activated','subscription.created',
                       'subscription.resumed','transaction.completed')    then 'active'
      when v_event = 'subscription.trialing'                             then 'trial'
      when v_event in ('subscription.canceled','subscription.cancelled')  then 'cancelled'
      when v_event in ('subscription.past_due','transaction.payment_failed') then 'past_due'
      when v_event = 'subscription.paused'                               then 'paused'
      else null
    end;
    if v_sub_status is not null then
      v_source := 'event name';
    end if;
  end if;

  v_pay_status := case
    when v_event = 'transaction.completed'      then 'succeeded'
    when v_event = 'transaction.payment_failed' then 'failed'
    when v_event = 'adjustment.updated'         then 'refunded'
    else null
  end;

  -- Record money events. UNIQUE provider_event_id makes a Paddle retry a no-op rather
  -- than a duplicate charge record.
  if v_pay_status is not null then
    insert into public.payments
      (user_id, provider, provider_event_id, provider_transaction_id,
       amount_cents, currency, status, plan, failure_reason,
       tax_cents, fee_cents, earnings_cents)
    values
      (v_uid, 'paddle', v_eid, nullif(btrim(coalesce(p_provider_transaction_id,'')),''),
       coalesce(v_amount, 0), coalesce(nullif(lower(btrim(coalesce(p_currency,''))),''), 'usd'),
       v_pay_status,
       case when v_plan in ('monthly','annual') then v_plan else null end,
       nullif(btrim(coalesce(p_failure_reason,'')),''),
       v_tax, v_fee, v_earn)
    on conflict (provider_event_id) do nothing;

    v_inserted := found;
  end if;

  -- Provider ids are facts, not state, so always keep them.
  update public.users u set
    provider_customer_id     = coalesce(nullif(btrim(coalesce(p_provider_customer_id,'')),''),
                                        u.provider_customer_id),
    provider_subscription_id = coalesce(nullif(btrim(coalesce(p_provider_subscription_id,'')),''),
                                        u.provider_subscription_id),
    updated_at               = now()
   where u.id = v_uid;

  -- Apply the status change only if this event is newer than the last one applied.
  if v_sub_status is null then
    v_skipped := case
      when v_event = 'subscription.updated'
        then 'subscription.updated carried no data.status, so no status could be applied'
      else 'event type carries no subscription status change'
    end;
  else
    select last_billing_event_at into v_last from public.users where id = v_uid;

    if v_occurred is not null and v_last is not null and v_occurred <= v_last then
      v_skipped := 'event is not newer than the last applied event (retry, or out-of-order delivery)';
    else
      -- When Paddle says the subscription is trialing, Paddle owns the trial and
      -- next_billed_at is the real charge date. Never overwrite a known trial_end
      -- with null if the event omits it.
      v_trial_end := case when v_sub_status = 'trial' then v_next else null end;

      update public.users u set
        subscription_status   = v_sub_status,
        plan                  = case when v_plan in ('monthly','annual') then v_plan else u.plan end,
        trial_end             = coalesce(v_trial_end, u.trial_end),
        last_billing_event_at = coalesce(v_occurred, now()),
        updated_at            = now()
       where u.id = v_uid;
      v_applied := true;
    end if;
  end if;

  -- Read the row back so the caller is told what IS, never what was intended.
  select subscription_status into v_actual from public.users where id = v_uid;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_uid,
    'event_type', v_event,
    'payment_recorded', v_inserted,
    'status_change_applied', v_applied,
    'mapped_status', coalesce(v_sub_status, '(none)'),
    'status_source', coalesce(v_source, '(none)'),
    'subscription_status', v_actual,
    'trial_end_set', v_trial_end,
    'skipped_reason', v_skipped
  );
end $fn$;

-- ------------------------------------------------------------------------- grants
revoke all on function public.verification_health() from public, anon, authenticated;
revoke all on function public.verify_rate_check(text, text, text) from public, anon, authenticated;
revoke all on function public.apply_payment_event(
  text, text, text, text, text, text, text, text, text, text, text, text, text,
  text, text, text) from public, anon, authenticated;

grant execute on function public.verification_health() to service_role;
grant execute on function public.verify_rate_check(text, text, text) to service_role;
grant execute on function public.apply_payment_event(
  text, text, text, text, text, text, text, text, text, text, text, text, text,
  text, text, text) to service_role;

-- apply_payment_event's argument list changed, so PostgREST cannot resolve the call
-- until its cache reloads.
notify pgrst, 'reload schema';
