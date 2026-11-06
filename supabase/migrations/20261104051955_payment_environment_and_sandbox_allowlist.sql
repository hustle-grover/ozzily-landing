-- Separate sandbox payment events from live ones, and stop a sandbox event ever
-- touching a real user.
--
-- Why this exists. `paddle-webhook` is about to accept TWO signing secrets so that
-- sandbox stays testable across the live cutover. The secret that matched is the only
-- trustworthy environment tag available, because it is derived from the signature
-- rather than from the payload -- but on its own it only labels the row. The real
-- hazard is that `pay.html` still opens SANDBOX checkout on *.vercel.app, and Paddle
-- test cards work for anybody, so a sandbox checkout carrying a REAL uid would
-- otherwise activate a real account for free, through this very function.
--
-- So: a sandbox event is applied only to an explicitly allowlisted test user. For any
-- other user it writes nothing at all -- no payment row, no provider ids, no status --
-- and reports why. An EMPTY allowlist therefore means no sandbox event can apply to
-- anyone, which is the state to leave this in at launch.

begin;

-- 1. Tag every payment row with the environment that produced it.
--    `payments` is empty (verified: 0 rows), so defaulting to live invents nothing.
alter table public.payments
  add column environment text not null default 'live'
    constraint payments_environment_check check (environment in ('live','sandbox'));

comment on column public.payments.environment is
  'Which Paddle environment signed the event that created this row, derived from the webhook signing secret that matched -- never from the payload.';

-- 2. The allowlist. Deliberately a table rather than a flag on `users`: it can be
--    emptied in one statement, and an empty allowlist is a hard guarantee that no
--    sandbox event applies to anyone.
create table if not exists public.payment_test_users (
  user_id  uuid primary key references public.users(id) on delete cascade,
  note     text,
  added_at timestamptz not null default now()
);

comment on table public.payment_test_users is
  'Users that sandbox Paddle events may be applied to. Empty this before launch.';

-- Same lockdown as every other table: RLS on, zero policies, service_role only.
alter table public.payment_test_users enable row level security;
revoke all on table public.payment_test_users from public, anon, authenticated;
grant select, insert, update, delete on table public.payment_test_users to service_role;

-- 2b. A queryable record of every refusal.
--
--     A refusal that exists only as a `raise warning` is a refusal nobody will ever
--     find: Postgres logs roll over and are not queryable from the app. These rows are
--     the evidence that the guard fired, and they are also the only record of events
--     dropped during the migrate-then-deploy window, when the not-yet-updated webhook
--     sends no environment at all.
create table if not exists public.payment_events_refused (
  id            uuid primary key default gen_random_uuid(),
  event_id      text not null unique,
  event_type    text,
  environment   text,
  user_id       uuid references public.users(id) on delete set null,
  reason        text not null,
  created_at    timestamptz not null default now()
);

comment on table public.payment_events_refused is
  'Paddle events that verified but were deliberately not applied, with the reason. Written by apply_payment_event.';

create index if not exists payment_events_refused_created_at_idx
  on public.payment_events_refused (created_at desc);

alter table public.payment_events_refused enable row level security;
revoke all on table public.payment_events_refused from public, anon, authenticated;
grant select, insert, update, delete on table public.payment_events_refused to service_role;

-- 3. Replace apply_payment_event with an environment-aware version.
--
--    The old signature MUST be dropped explicitly. Adding a defaulted parameter
--    creates an OVERLOAD, not a replacement: the old 16-argument function would stay
--    callable and would apply events with no environment guard at all. That is a
--    silent bypass of everything above, so dropping it is the load-bearing line here.
drop function if exists public.apply_payment_event(
  text, text, text, text, text, text, text, text,
  text, text, text, text, text, text, text, text
);

create or replace function public.apply_payment_event(
  p_event_id text,
  p_event_type text,
  p_occurred_at text default null,
  p_user_id text default null,
  p_provider_customer_id text default null,
  p_provider_subscription_id text default null,
  p_provider_transaction_id text default null,
  p_amount_cents text default null,
  p_currency text default null,
  p_plan text default null,
  p_failure_reason text default null,
  p_paddle_status text default null,
  p_next_billed_at text default null,
  p_tax_cents text default null,
  p_fee_cents text default null,
  p_earnings_cents text default null,
  -- DEFAULTS TO NULL, DELIBERATELY. A default of 'live' would mean the currently
  -- deployed webhook -- which does not pass this argument -- had every event treated
  -- as live and walked straight past the guard during the window between this
  -- migration and the function deploy. Null fails the check below instead.
  p_environment text default null
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
  v_env        text := lower(btrim(coalesce(p_environment,'')));
  v_inserted   boolean := false;
  v_applied    boolean := false;
  v_skipped    text;
  v_actual     text;
  v_trial_end  timestamptz;
begin
  if v_eid is null then
    return jsonb_build_object('ok', false, 'error', 'missing event id');
  end if;

  -- Fail closed on a missing or unrecognised environment rather than guessing live. A
  -- caller that cannot say which secret matched is a caller that must not apply
  -- anything. An empty string lands here too, which is what the not-yet-updated
  -- webhook produces, so the deploy window refuses rather than applies.
  if v_env not in ('live','sandbox') then
    insert into public.payment_events_refused
      (event_id, event_type, environment, user_id, reason)
    values (v_eid, v_event, nullif(v_env,''), null,
            'missing or unrecognised environment; caller did not say which signing secret matched')
    on conflict (event_id) do nothing;

    raise warning 'apply_payment_event: refused event % (%) for unrecognised environment %',
                  v_eid, v_event, coalesce(nullif(v_env,''), '(none)');
    return jsonb_build_object('ok', false, 'error', 'unrecognised environment',
                              'environment', coalesce(nullif(v_env,''), '(none)'),
                              'event_id', v_eid);
  end if;

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
    -- Recorded for BOTH environments, not just live. A ledger that covers only some
    -- refusal kinds answers "did the guard fire" but not "what did we drop", and an
    -- unattributable live payment is the single most expensive thing to lose silently.
    insert into public.payment_events_refused
      (event_id, event_type, environment, user_id, reason)
    values (v_eid, v_event, v_env, null,
            'user not resolved from custom_data.user_id, provider_subscription_id or provider_customer_id')
    on conflict (event_id) do nothing;

    raise warning 'apply_payment_event: refused % event % (%): user not resolved',
                  v_env, v_eid, v_event;
    return jsonb_build_object('ok', false, 'error', 'user not resolved',
                              'event_id', v_eid, 'event_type', v_event,
                              'environment', v_env);
  end if;

  -- THE GUARD. A sandbox event may only touch an allowlisted test user. This sits
  -- ahead of every write below, including the provider-id update, because a sandbox
  -- customer id written onto a real user would corrupt the live resolution path for
  -- every later event.
  --
  -- Returns ok:true so the caller answers 2xx and Paddle stops retrying: a sandbox
  -- event aimed at a real user will never become applicable. The refusal is recorded
  -- in payment_events_refused, in the Postgres log, and in the return value.
  if v_env = 'sandbox'
     and not exists (select 1 from public.payment_test_users t where t.user_id = v_uid) then
    insert into public.payment_events_refused
      (event_id, event_type, environment, user_id, reason)
    values (v_eid, v_event, v_env, v_uid,
            'sandbox event for a user that is not in payment_test_users')
    on conflict (event_id) do nothing;

    raise warning 'apply_payment_event: refused sandbox event % (%) for non-test user %',
                  v_eid, v_event, v_uid;
    return jsonb_build_object(
      'ok', true,
      'user_id', v_uid,
      'event_type', v_event,
      'environment', v_env,
      'payment_recorded', false,
      'status_change_applied', false,
      'skipped_reason', 'sandbox event for a user that is not in payment_test_users; nothing was written'
    );
  end if;

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

  if v_pay_status is not null then
    insert into public.payments
      (user_id, provider, provider_event_id, provider_transaction_id,
       amount_cents, currency, status, plan, failure_reason,
       tax_cents, fee_cents, earnings_cents, environment)
    values
      (v_uid, 'paddle', v_eid, nullif(btrim(coalesce(p_provider_transaction_id,'')),''),
       coalesce(v_amount, 0), coalesce(nullif(lower(btrim(coalesce(p_currency,''))),''), 'usd'),
       v_pay_status,
       case when v_plan in ('monthly','annual') then v_plan else null end,
       nullif(btrim(coalesce(p_failure_reason,'')),''),
       v_tax, v_fee, v_earn, v_env)
    on conflict (provider_event_id) do nothing;

    v_inserted := found;
  end if;

  update public.users u set
    provider_customer_id     = coalesce(nullif(btrim(coalesce(p_provider_customer_id,'')),''),
                                        u.provider_customer_id),
    provider_subscription_id = coalesce(nullif(btrim(coalesce(p_provider_subscription_id,'')),''),
                                        u.provider_subscription_id),
    updated_at               = now()
   where u.id = v_uid;

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

  select subscription_status into v_actual from public.users where id = v_uid;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_uid,
    'event_type', v_event,
    'environment', v_env,
    'payment_recorded', v_inserted,
    'status_change_applied', v_applied,
    'mapped_status', coalesce(v_sub_status, '(none)'),
    'status_source', coalesce(v_source, '(none)'),
    'subscription_status', v_actual,
    'trial_end_set', v_trial_end,
    'skipped_reason', v_skipped
  );
end $function$;

-- 4. A fresh CREATE gets a default PUBLIC EXECUTE grant, which is how the system
--    prompt once became readable by anon. Revoke before granting.
revoke all on function public.apply_payment_event(
  text, text, text, text, text, text, text, text,
  text, text, text, text, text, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.apply_payment_event(
  text, text, text, text, text, text, text, text,
  text, text, text, text, text, text, text, text, text
) to service_role;

-- 5. Assert the things that fail silently.
do $$
begin
  -- The old 16-arg overload must be gone, or it is an unguarded path into the same writes.
  if exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'apply_payment_event'
       and p.pronargs = 16
  ) then
    raise exception 'the 16-argument apply_payment_event still exists: it bypasses the environment guard';
  end if;

  if (select count(*) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'apply_payment_event') <> 1 then
    raise exception 'expected exactly one apply_payment_event overload';
  end if;

  -- EXECUTE must be gone for anon AND authenticated AND PUBLIC. PUBLIC is not a role,
  -- so has_function_privilege cannot see it: its ACL entry has an empty grantee and
  -- shows up as `=X/owner`, which is exactly the grant that once left the AI Brain
  -- system prompt readable over /rest/v1/rpc/. Match it in the ACL text.
  if has_function_privilege('anon',
       'public.apply_payment_event(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)',
       'EXECUTE') then
    raise exception 'anon can still EXECUTE apply_payment_event';
  end if;

  if has_function_privilege('authenticated',
       'public.apply_payment_event(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)',
       'EXECUTE') then
    raise exception 'authenticated can still EXECUTE apply_payment_event';
  end if;

  if exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'apply_payment_event'
       and p.proacl::text ~ '[{,]=X/'
  ) then
    raise exception 'PUBLIC still has EXECUTE on apply_payment_event';
  end if;

  -- The positive half. A typo in the revoke/grant pair would leave the webhook unable
  -- to call the function at all, which the negative assertions above would happily pass.
  if not has_function_privilege('service_role',
       'public.apply_payment_event(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)',
       'EXECUTE') then
    raise exception 'service_role cannot EXECUTE apply_payment_event; the webhook would break';
  end if;

  -- RLS on both new tables. `enable row level security` with zero policies is the
  -- project's lockdown pattern, and a missing one is invisible until something reads.
  if not (select relrowsecurity from pg_class where oid = 'public.payment_test_users'::regclass) then
    raise exception 'RLS is not enabled on payment_test_users';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.payment_events_refused'::regclass) then
    raise exception 'RLS is not enabled on payment_events_refused';
  end if;

  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('payment_test_users','payment_events_refused')
  ) then
    raise exception 'unexpected RLS policy on a locked-down table';
  end if;

  if exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'public'
       and table_name in ('payment_test_users','payment_events_refused')
       and grantee in ('PUBLIC','anon','authenticated')
  ) then
    raise exception 'anon, authenticated or PUBLIC still has a table grant on a locked-down table';
  end if;
end $$;

-- 6. PostgREST caches the schema, so after a signature change the RPC cannot be
--    resolved until it is told to reload. Without this the webhook silently stops
--    applying events while nothing visibly errors.
notify pgrst, 'reload schema';

commit;
