-- Launch week: the global daily cap on verification starts drops 200 -> 100.
--
-- This is the whole change. One function, three lines, because the cap was
-- single-sourced on 2026-11-12 -- verify_rate_check() (which enforces it) and
-- verification_health() (which reports on it) both read this function, so neither
-- has to be touched and neither can disagree with the other.
--
-- 100 starts is roughly $6.50 of Twilio Verify at worst. Tripping it refuses signup
-- for EVERYONE until the 24h window rolls, which is a deliberate self-inflicted
-- outage: a lost day is recoverable and an unbounded bill is not. That is also why
-- the warning fires at 70% of it, while signups still work, rather than at the
-- ceiling.
--
-- Raise it back when launch week ends, here and nowhere else.
create or replace function public.verify_global_daily_cap()
returns int
language sql
immutable
security definer
set search_path = public, pg_temp
as $function$ select 100 $function$;
