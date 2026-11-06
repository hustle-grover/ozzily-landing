-- Fix the adjustment refund gap and the unpopulatable failure_reason column.
--
-- Built by ASSERTED SUBSTRING REPLACEMENT on the function's own definition, never by
-- retranscribing 150 lines to change five of them. Every replace() must change the
-- text or the migration raises, because a replace() that misses is a silent no-op --
-- the failure mode this project has been bitten by before.

-- ---------------------------------------------------------------- schema additions

-- A second idempotency key, independent of provider_event_id. adjustment.created and
-- adjustment.updated for the SAME adjustment carry DIFFERENT event ids, so the
-- existing guard cannot see that a refund is already recorded. Nullable, so only
-- adjustment rows occupy it; UNIQUE, so a replay cannot double-count a refund.
alter table public.payments
  add column if not exists provider_adjustment_id text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payments_provider_adjustment_id_key') then
    alter table public.payments
      add constraint payments_provider_adjustment_id_key UNIQUE (provider_adjustment_id);
  end if;
end $$;

-- A chargeback is money out, but it is NOT a refund: different cause, different
-- dispute handling, and it can later be reversed. Collapsing it into 'refunded' would
-- misreport it, so it gets its own value rather than the nearest available lie.
alter table public.payments drop constraint payments_status_check;
alter table public.payments add constraint payments_status_check
  CHECK ((status = ANY (ARRAY['succeeded'::text, 'failed'::text, 'refunded'::text,
                              'chargeback'::text, 'pending'::text])));

-- ------------------------------------------------------- rewrite apply_payment_event

do $mig$
declare
  src    text;
  out    text;
  n_hdr  int;
begin
  select pg_get_functiondef(p.oid) into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'apply_payment_event'
     and pg_get_function_identity_arguments(p.oid) like '%p_environment text';

  if src is null then
    raise exception 'apply_payment_event with a p_environment parameter was not found';
  end if;
  out := src;

  ---------------------------------------------------------------- 1. signature
  out := replace(out,
    'p_environment text DEFAULT NULL::text)',
    'p_environment text DEFAULT NULL::text, p_adjustment_id text DEFAULT NULL::text, p_adjustment_action text DEFAULT NULL::text, p_adjustment_status text DEFAULT NULL::text)');
  if out = src then raise exception 'edit 1 (signature) matched nothing'; end if;

  ---------------------------------------------------------------- 2. declarations
  -- v_adj_action/v_adj_status are coalesced to '' rather than left NULL on purpose:
  -- `null <> 'approved'` is NULL, which plpgsql treats as false, so a missing status
  -- would fall through and be handled as though it were approved.
  n_hdr := length(out);
  out := replace(out,
E'  v_trial_end  timestamptz;\n',
E'  v_trial_end  timestamptz;\n'
|| E'  v_adj_id      text := nullif(btrim(coalesce(p_adjustment_id,\'\')),\'\');\n'
|| E'  v_adj_action  text := lower(btrim(coalesce(p_adjustment_action,\'\')));\n'
|| E'  v_adj_status  text := lower(btrim(coalesce(p_adjustment_status,\'\')));\n'
|| E'  v_pay_skipped text;\n');
  if length(out) = n_hdr then raise exception 'edit 2 (declarations) matched nothing'; end if;

  ---------------------------------------------------------------- 3. payment mapping
  n_hdr := length(out);
  out := replace(out,
E'  v_pay_status := case\n'
|| E'    when v_event = \'transaction.completed\'      then \'succeeded\'\n'
|| E'    when v_event = \'transaction.payment_failed\' then \'failed\'\n'
|| E'    when v_event = \'adjustment.updated\'         then \'refunded\'\n'
|| E'    else null\n'
|| E'  end;\n',
E'  -- ADJUSTMENTS MAP ON THE ADJUSTMENT\'S OWN STATUS AND ACTION, NEVER ON THE EVENT\n'
|| E'  -- NAME. `adjustment.created` fires while a refund is still `pending_approval`,\n'
|| E'  -- and that status can go on to `rejected`, so treating the event name as proof\n'
|| E'  -- would record refunds that never happened -- the same class of error as a status\n'
|| E'  -- written by the step that STARTS an action instead of the step that confirms it.\n'
|| E'  -- Only `approved` is money that actually moved.\n'
|| E'  --\n'
|| E'  -- The `*_reverse` actions (chargeback_reverse, chargeback_warning_reverse,\n'
|| E'  -- credit_reverse) move money back TOWARDS us. Recording one as a refund would\n'
|| E'  -- double-count a loss, so they are deliberately not recorded and say why.\n'
|| E'  if v_event like \'adjustment.%\' then\n'
|| E'    if v_adj_status <> \'approved\' then\n'
|| E'      v_pay_skipped := format(\'adjustment status is %s, not approved; no payment row written\',\n'
|| E'                              coalesce(nullif(v_adj_status,\'\'), \'(none)\'));\n'
|| E'    elsif v_adj_action = \'refund\' then\n'
|| E'      v_pay_status := \'refunded\';\n'
|| E'    elsif v_adj_action = \'chargeback\' then\n'
|| E'      v_pay_status := \'chargeback\';\n'
|| E'    else\n'
|| E'      v_pay_skipped := format(\'adjustment action %s is approved but is not money leaving us; no payment row written\',\n'
|| E'                              coalesce(nullif(v_adj_action,\'\'), \'(none)\'));\n'
|| E'    end if;\n'
|| E'  else\n'
|| E'    v_pay_status := case\n'
|| E'      when v_event = \'transaction.completed\'      then \'succeeded\'\n'
|| E'      when v_event = \'transaction.payment_failed\' then \'failed\'\n'
|| E'      else null\n'
|| E'    end;\n'
|| E'  end if;\n');
  if length(out) = n_hdr then raise exception 'edit 3 (payment mapping) matched nothing'; end if;

  ---------------------------------------------------------------- 4. the insert
  n_hdr := length(out);
  out := replace(out,
E'    insert into public.payments\n'
|| E'      (user_id, provider, provider_event_id, provider_transaction_id,\n'
|| E'       amount_cents, currency, status, plan, failure_reason,\n'
|| E'       tax_cents, fee_cents, earnings_cents, environment)\n'
|| E'    values\n'
|| E'      (v_uid, \'paddle\', v_eid, nullif(btrim(coalesce(p_provider_transaction_id,\'\')),\'\'),\n'
|| E'       coalesce(v_amount, 0), coalesce(nullif(lower(btrim(coalesce(p_currency,\'\'))),\'\'), \'usd\'),\n'
|| E'       v_pay_status,\n'
|| E'       case when v_plan in (\'monthly\',\'annual\') then v_plan else null end,\n'
|| E'       nullif(btrim(coalesce(p_failure_reason,\'\')),\'\'),\n'
|| E'       v_tax, v_fee, v_earn, v_env)\n'
|| E'    on conflict (provider_event_id) do nothing;\n'
|| E'\n'
|| E'    v_inserted := found;\n',
E'    begin\n'
|| E'      insert into public.payments\n'
|| E'        (user_id, provider, provider_event_id, provider_transaction_id,\n'
|| E'         provider_adjustment_id,\n'
|| E'         amount_cents, currency, status, plan, failure_reason,\n'
|| E'         tax_cents, fee_cents, earnings_cents, environment)\n'
|| E'      values\n'
|| E'        (v_uid, \'paddle\', v_eid, nullif(btrim(coalesce(p_provider_transaction_id,\'\')),\'\'),\n'
|| E'         v_adj_id,\n'
|| E'         coalesce(v_amount, 0), coalesce(nullif(lower(btrim(coalesce(p_currency,\'\'))),\'\'), \'usd\'),\n'
|| E'         v_pay_status,\n'
|| E'         case when v_plan in (\'monthly\',\'annual\') then v_plan else null end,\n'
|| E'         nullif(btrim(coalesce(p_failure_reason,\'\')),\'\'),\n'
|| E'         v_tax, v_fee, v_earn, v_env)\n'
|| E'      on conflict (provider_event_id) do nothing;\n'
|| E'\n'
|| E'      v_inserted := found;\n'
|| E'    exception when unique_violation then\n'
|| E'      -- provider_adjustment_id is UNIQUE, so a second approved event for the same\n'
|| E'      -- adjustment -- which carries a DIFFERENT event id, and so is invisible to the\n'
|| E'      -- provider_event_id guard -- lands here instead of double-recording the refund.\n'
|| E'      v_inserted := false;\n'
|| E'      v_pay_skipped := \'this adjustment is already recorded under a different event id\';\n'
|| E'    end;\n');
  if length(out) = n_hdr then raise exception 'edit 4 (insert) matched nothing'; end if;

  ---------------------------------------------------------------- 5. return value
  -- Separate from skipped_reason, which is about the SUBSCRIPTION status. A refund
  -- that was deliberately not recorded has to say so somewhere a caller can read.
  n_hdr := length(out);
  out := replace(out,
E'    \'skipped_reason\', v_skipped\n',
E'    \'skipped_reason\', v_skipped,\n'
|| E'    \'payment_skipped_reason\', v_pay_skipped\n');
  if length(out) = n_hdr then raise exception 'edit 5 (return value) matched nothing'; end if;

  ---------------------------------------------------------------- guards
  if out ~ 'when v_event = ''adjustment\.updated''' then
    raise exception 'the old event-name refund mapping survived the rewrite';
  end if;
  if position('provider_adjustment_id' in out) = 0 then
    raise exception 'the new adjustment column never made it into the insert';
  end if;

  -- Adding defaulted parameters creates an OVERLOAD rather than replacing anything,
  -- and the old 17-arg function would stay callable and bypass every new guard.
  drop function if exists public.apply_payment_event(
    text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text);

  execute out;
end $mig$;

-- Postgres grants EXECUTE to PUBLIC by default, and the new signature is a new
-- function with a fresh default ACL.
revoke all on function public.apply_payment_event(
  p_event_id text, p_event_type text, p_occurred_at text, p_user_id text,
  p_provider_customer_id text, p_provider_subscription_id text,
  p_provider_transaction_id text, p_amount_cents text, p_currency text, p_plan text,
  p_failure_reason text, p_paddle_status text, p_next_billed_at text, p_tax_cents text,
  p_fee_cents text, p_earnings_cents text, p_environment text, p_adjustment_id text,
  p_adjustment_action text, p_adjustment_status text) from public, anon, authenticated;
grant execute on function public.apply_payment_event(
  p_event_id text, p_event_type text, p_occurred_at text, p_user_id text,
  p_provider_customer_id text, p_provider_subscription_id text,
  p_provider_transaction_id text, p_amount_cents text, p_currency text, p_plan text,
  p_failure_reason text, p_paddle_status text, p_next_billed_at text, p_tax_cents text,
  p_fee_cents text, p_earnings_cents text, p_environment text, p_adjustment_id text,
  p_adjustment_action text, p_adjustment_status text) to service_role;

-- The database has the new signature immediately, but PostgREST keeps serving its
-- cached schema and cannot resolve the call -- which shows up as the scenario exiting
-- early with nothing logged, not as an error.
notify pgrst, 'reload schema';
