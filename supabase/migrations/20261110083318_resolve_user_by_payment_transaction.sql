-- A FOURTH RESOLUTION FALLBACK: resolve the user from the PURCHASE we already recorded.
--
-- WHY THIS EXISTS. An adjustment payload carries no custom_data, so `custom_data.user_id`
-- -- the primary and most trustworthy path -- is absent on EVERY refund. Resolution then
-- falls entirely to provider_subscription_id / provider_customer_id on the users row,
-- which the purchase webhook is responsible for writing back. If that write-back did not
-- happen, a live refund returns ok:false, the webhook answers 500, Paddle retries until
-- it gives up, and no retry can ever fix it because the missing ids are on OUR row. The
-- recovery was a documented manual procedure: find the user via
-- payments.provider_transaction_id, backfill the ids by hand, replay the event.
--
-- That procedure proves the information was already in the database. So this does it
-- automatically: an adjustment's transaction_id is identical to the purchase
-- transaction's id, and the purchase row resolved correctly at the time via
-- custom_data.user_id. Any refund whose purchase was recorded is now resolvable.
--
-- WHAT IT DELIBERATELY DOES NOT DO. It does not invent a user. If no payments row
-- carries that transaction id, the purchase itself was never recorded and the event is
-- still refused -- which is correct, because an unrecorded purchase is a separate and
-- louder problem than an unattributable refund.
--
-- Built by ASSERTED SUBSTRING REPLACEMENT on the function's own definition, never by
-- retranscribing 200 lines to change twelve of them. Every replace() must change the
-- text or this migration raises: a replace() that misses is a silent no-op, which is
-- the failure mode this project has been bitten by before.

-- The new path is a lookup, so give it an index. Not UNIQUE: one transaction legitimately
-- has a purchase row AND a refund row sharing the same provider_transaction_id.
create index if not exists payments_provider_transaction_idx
  on public.payments (provider_transaction_id)
  where provider_transaction_id is not null;

do $mig$
declare
  v_def  text;
  v_orig text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'apply_payment_event';

  if v_def is null then
    raise exception 'apply_payment_event not found';
  end if;
  v_orig := v_def;

  -- (1) A variable to record WHICH path resolved the user.
  --
  -- Not cosmetic. The whole point of a fallback is that it fires when something upstream
  -- failed, so a fallback that fires silently hides the breakage it is compensating for.
  -- A live refund resolving via payments.provider_transaction_id means the users row is
  -- missing its provider ids -- worth seeing in the log, not worth guessing at later.
  v_def := replace(v_def,
    '  v_pay_skipped text;',
    '  v_pay_skipped text;
  v_resolved    text;');
  if v_def = v_orig then
    raise exception 'declare-block anchor (v_pay_skipped) not found verbatim';
  end if;
  v_orig := v_def;

  -- (2) The resolution ladder, with the fourth rung added and each rung labelled.
  v_def := replace(v_def,
'  v_uid := nullif(btrim(coalesce(p_user_id,'''')),'''')::uuid;

  if v_uid is null and nullif(btrim(coalesce(p_provider_subscription_id,'''')),'''') is not null then
    select id into v_uid from public.users
     where provider_subscription_id = btrim(p_provider_subscription_id) limit 1;
  end if;

  if v_uid is null and nullif(btrim(coalesce(p_provider_customer_id,'''')),'''') is not null then
    select id into v_uid from public.users
     where provider_customer_id = btrim(p_provider_customer_id) limit 1;
  end if;
',
'  v_uid := nullif(btrim(coalesce(p_user_id,'''')),'''')::uuid;
  if v_uid is not null then
    v_resolved := ''custom_data.user_id'';
  end if;

  if v_uid is null and nullif(btrim(coalesce(p_provider_subscription_id,'''')),'''') is not null then
    select id into v_uid from public.users
     where provider_subscription_id = btrim(p_provider_subscription_id) limit 1;
    if v_uid is not null then
      v_resolved := ''users.provider_subscription_id'';
    end if;
  end if;

  if v_uid is null and nullif(btrim(coalesce(p_provider_customer_id,'''')),'''') is not null then
    select id into v_uid from public.users
     where provider_customer_id = btrim(p_provider_customer_id) limit 1;
    if v_uid is not null then
      v_resolved := ''users.provider_customer_id'';
    end if;
  end if;

  -- FOURTH FALLBACK: the user the PURCHASE resolved to.
  --
  -- An adjustment carries no custom_data, so user_id is absent on every refund. Its
  -- transaction_id is the original transaction''s id, and that purchase row was
  -- attributed via custom_data.user_id when it was written. So this recovers a refund
  -- whose users row lost (or never got) its provider ids.
  --
  -- `environment` is matched, not ignored. Transaction ids do not collide across
  -- environments in practice, but attributing a LIVE refund to a user found through a
  -- SANDBOX payment row would be a cross-environment write, and the column is NOT NULL
  -- so the match costs nothing. The sandbox allowlist guard below is a second line of
  -- defence, not a substitute: it only constrains sandbox events.
  --
  -- The ordering is deterministic because one transaction can hold both a purchase and a
  -- refund row: prefer the succeeded purchase, then the oldest. Both carry the same
  -- user_id in every case this can construct, so the ordering is about being repeatable
  -- rather than about choosing between different answers.
  if v_uid is null and nullif(btrim(coalesce(p_provider_transaction_id,'''')),'''') is not null then
    select p.user_id into v_uid
      from public.payments p
     where p.provider_transaction_id = btrim(p_provider_transaction_id)
       and p.environment = v_env
     order by (p.status = ''succeeded'') desc, p.created_at asc
     limit 1;
    if v_uid is not null then
      v_resolved := ''payments.provider_transaction_id'';
    end if;
  end if;
');
  if v_def = v_orig then
    raise exception 'resolution-ladder anchor not found verbatim';
  end if;
  v_orig := v_def;

  -- (3) The refusal reason must name all four paths it actually tried. A reason that
  -- lists three when four were attempted sends the next reader looking in the wrong place.
  v_def := replace(v_def,
    '''user not resolved from custom_data.user_id, provider_subscription_id or provider_customer_id''',
    '''user not resolved from custom_data.user_id, users.provider_subscription_id, users.provider_customer_id or payments.provider_transaction_id''');
  if v_def = v_orig then
    raise exception 'refusal-reason anchor not found verbatim';
  end if;
  v_orig := v_def;

  -- (4) Report the path in the return value. This function's rule is that it reports what
  -- it DID, not what it intended -- the same rule that produced status_change_applied.
  v_def := replace(v_def,
    '    ''payment_skipped_reason'', v_pay_skipped',
    '    ''payment_skipped_reason'', v_pay_skipped,
    ''resolved_by'', coalesce(v_resolved, ''(none)'')');
  if v_def = v_orig then
    raise exception 'return-document anchor (payment_skipped_reason) not found verbatim';
  end if;

  execute v_def;
end $mig$;

-- create or replace preserves the existing ACL, which is how a PUBLIC grant once carried
-- forward onto ai_brain_system_prompt() and made the whole system prompt readable by
-- anon. Re-assert the intended grants rather than trusting what was inherited.
revoke all on function public.apply_payment_event(
  text, text, text, text, text, text, text, text, text, text, text, text, text,
  text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.apply_payment_event(
  text, text, text, text, text, text, text, text, text, text, text, text, text,
  text, text, text, text, text, text, text) to service_role;
