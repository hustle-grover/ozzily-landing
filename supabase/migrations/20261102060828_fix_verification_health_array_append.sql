-- v_reasons || 'some text' makes Postgres parse the right-hand side as an ARRAY
-- LITERAL, so the function raised 22P02 the instant it had a problem to report.
-- The happy path never appended anything, so it passed. Cast each element to text.
--
-- This is the checkin_delivery_health lesson again, one level deeper: it is not
-- enough for a health check to report the failure, it has to SURVIVE it.
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
  v_confirm_ok    int;
  v_confirm_bad   int;
  v_healthy       boolean;
  v_reasons       text[] := array[]::text[];
begin
  select count(*) filter (where action = 'start'),
         count(*) filter (where action = 'start' and outcome = 'blocked'),
         count(*) filter (where action = 'confirm' and outcome = 'approved'),
         count(*) filter (where action = 'confirm' and outcome = 'denied')
    into v_starts, v_blocked, v_confirm_ok, v_confirm_bad
    from public.verification_attempts
   where created_at > now() - interval '24 hours';

  if v_starts > v_cap then
    v_reasons := v_reasons || 'global daily cap reached: signups are being refused'::text;
  elsif v_starts >= (v_cap * 0.8)::int then
    v_reasons := v_reasons || 'global daily starts above 80% of cap'::text;
  end if;

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

revoke all on function public.verification_health() from public, anon, authenticated;
grant execute on function public.verification_health() to service_role;
