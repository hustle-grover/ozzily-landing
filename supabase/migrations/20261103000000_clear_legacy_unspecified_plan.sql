-- users.plan is the billing column that apply_payment_event() owns: it stays null
-- until a payment sets it. The old Make signup flow wrote the literal string
-- 'unspecified', which is a signup *preference*, not a billing plan. Preference now
-- lives in users.preferred_plan; this clears the legacy pollution.
--
-- 'unspecified' means no preference was expressed, so preferred_plan is deliberately
-- NOT backfilled -- inventing a preference would be worse than recording none.
--
-- Guarded: only rows with no payment history can be touched, so this can never
-- erase a plan that a real payment established.
do $$
declare
  v_updated int;
begin
  update public.users u
     set plan = null,
         updated_at = now()
   where u.plan = 'unspecified'
     and not exists (select 1 from public.payments p where p.user_id = u.id);

  get diagnostics v_updated = row_count;
  raise notice 'cleared legacy plan on % row(s)', v_updated;

  if exists (select 1 from public.users where plan = 'unspecified') then
    raise exception 'legacy plan=unspecified rows remain that have payment history; inspect manually';
  end if;
end $$;
