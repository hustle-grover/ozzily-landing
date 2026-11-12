-- One number, two definitions. The global daily verification cap was the constant 200
-- in BOTH verify_rate_check() (c_global_cap, which ENFORCES it) and
-- verification_health() (v_cap, which REPORTS on it). Nothing tied them together, so
-- raising one would leave the other stating a cap that is not the cap -- and the one
-- that drifts silently is the health check, which would then report "62% of cap"
-- against a ceiling nobody is enforcing, or "cap reached" while signups still flow.
--
-- That is the same failure class this project has already hit twice: the drug-name ban
-- applied to one prompt and not the other, and scheduled_messages.status written by the
-- step that STARTS an action. A monitor that can be wrong about the thing it monitors is
-- worse than no monitor, because it is believed.
--
-- So: one function holds the number, and both callers read it. Changing the cap becomes
-- a three-line CREATE OR REPLACE instead of an edit that has to be remembered in two
-- places. (A one-row config table was considered and rejected: it buys runtime edits
-- without a migration, at the cost of a new table, its RLS, and a second thing that can
-- disagree with the snapshot. The cap is changed at launch and then rarely.)
--
-- The rewrites below are ASSERTED SUBSTRING REPLACEMENTS on each function's own
-- pg_get_functiondef() output, re-executed verbatim. Nothing is retranscribed, the
-- original $function$ quoting is reproduced exactly (so the schema snapshot diff stays
-- one hunk per function), and a replace() that fails to match raises instead of
-- silently no-opping.

-- ---------------------------------------------------------------- the single source
create or replace function public.verify_global_daily_cap()
returns int
language sql
immutable
security definer
set search_path = public, pg_temp
as $function$ select 200 $function$;

comment on function public.verify_global_daily_cap() is
  'The one definition of the global 24h cap on verification starts. Read by '
  'verify_rate_check() (which enforces it) and verification_health() (which reports '
  'on it). Change it here and nowhere else. ~200 starts is roughly $13 of Twilio '
  'Verify at worst, and tripping it refuses signup for EVERYONE -- which is why '
  'signup-verify alerts at 80%, not at the ceiling.';

-- create or replace preserves the existing ACL, and for a NEW function the default
-- grant is EXECUTE to PUBLIC -- the =X trap that left ai_brain_system_prompt() readable
-- by anon over /rest/v1/rpc/. Revoke before anything can reach it.
revoke all on function public.verify_global_daily_cap() from public, anon, authenticated;
grant execute on function public.verify_global_daily_cap() to service_role;

-- --------------------------------------------------------------- patch both callers
do $mig$
declare
  v_def text;
  v_new text;
begin
  -- ----------------------------------------------- verify_rate_check: the enforcer
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'verify_rate_check';
  if v_def is null then
    raise exception 'verify_rate_check not found';
  end if;

  v_new := replace(
    v_def,
    '  c_global_cap  constant int := 200;',
    '  c_global_cap  int := public.verify_global_daily_cap();');
  if v_new = v_def then
    raise exception 'verify_rate_check: cap declaration not found verbatim';
  end if;
  execute v_new;

  -- ------------------------------------------- verification_health: the reporter
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'verification_health';
  if v_def is null then
    raise exception 'verification_health not found';
  end if;

  -- v_cap is referenced before the first statement that could assign it, so the
  -- default expression is the only correct place for it -- declaring it bare and
  -- assigning after begin would work here too, but the default keeps the diff to
  -- exactly one line, which is the line a reviewer needs to see.
  v_new := replace(
    v_def,
    '  v_cap           constant int := 200;',
    '  v_cap           int := public.verify_global_daily_cap();');
  if v_new = v_def then
    raise exception 'verification_health: cap declaration not found verbatim';
  end if;
  execute v_new;
end $mig$;

-- ------------------------------------------------------------------------ proof
-- Both must report the same number, and it must be the one the source function gives.
-- This is the assertion the whole migration exists to make true, so it runs here
-- rather than being left as a manual check.
do $chk$
declare
  v_src    int := public.verify_global_daily_cap();
  v_health int := (public.verification_health() ->> 'global_cap')::int;
  v_gate   int := (public.verify_rate_check('+10000000000', null, 'start') ->> 'global_cap')::int;
begin
  if v_health <> v_src or v_gate <> v_src then
    raise exception 'cap disagreement: source=%, health=%, gate=%', v_src, v_health, v_gate;
  end if;
  -- verify_rate_check INSERTS before counting (deliberately -- counting first is
  -- beatable by racing), so the probe above left a row. Remove it: it is not a real
  -- attempt and it would count against the very cap being checked.
  delete from public.verification_attempts where phone = '+10000000000';
  raise notice 'cap single-sourced at % (health and gate agree)', v_src;
end $chk$;
