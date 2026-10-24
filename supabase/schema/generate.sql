-- Regenerates the schema snapshot in this directory from the live database.
--
-- Run each query below against the Supabase project and write its single text
-- column to the matching file. Every query also returns an md5 so the written
-- file can be verified: md5sum <file> must equal it.
--
-- NOTE on verification: the queries return length() in CHARACTERS, not bytes.
-- 02_functions.sql contains one em dash (in checkin_delivery_health's detail
-- text), which is 3 bytes for 1 character, so the file is 2 bytes larger than
-- the reported length. Compare md5, not size.
--
-- NOTE on redaction: 02_functions.sql replaces the check-in hook URL inside
-- trigger_checkins_if_due() with the placeholder <MAKE_CHECKIN_HOOK_URL>,
-- because this repository is public. The generator below applies the same
-- replacement so the md5 matches the committed file.


-- ========================================================== 01_tables.sql
with cols as (
  select c.relname as tbl,
         string_agg(format('  %-24s %s%s%s', a.attname,
                  format_type(a.atttypid, a.atttypmod),
                  case when a.attnotnull then ' not null' else '' end,
                  case when ad.adbin is not null then ' default ' || pg_get_expr(ad.adbin, ad.adrelid) else '' end),
           E',\n' order by a.attnum) as d
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
    left join pg_attrdef ad on ad.adrelid=c.oid and ad.adnum=a.attnum
   where n.nspname='public' and c.relkind='r' group by c.relname
),
t_blk as (select string_agg(format(E'create table public.%I (\n%s\n);', tbl, d), E'\n\n' order by tbl) as s from cols),
c_blk as (select string_agg(format('alter table public.%I add constraint %I %s;', c.relname, co.conname, pg_get_constraintdef(co.oid)), E'\n' order by c.relname, co.contype desc, co.conname) as s
            from pg_constraint co join pg_class c on c.oid=co.conrelid
            join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'),
i_blk as (select string_agg(pg_get_indexdef(i.indexrelid)||';', E'\n' order by c.relname, ic.relname) as s
            from pg_index i join pg_class c on c.oid=i.indrelid
            join pg_class ic on ic.oid=i.indexrelid
            join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and not i.indisprimary
             and not exists (select 1 from pg_constraint co where co.conindid=i.indexrelid)),
r_blk as (select string_agg(format('alter table public.%I enable row level security;', c.relname), E'\n' order by c.relname) as s
            from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relkind='r' and c.relrowsecurity),
f as (
  select concat(
    E'-- Ozzily database schema: tables, constraints, indexes, RLS.\n',
    E'-- GENERATED SNAPSHOT of live Supabase project siblqlstyccysqryggtr.\n',
    E'-- Do not edit by hand. Regenerate with generate.sql; see README.md.\n\n',
    E'-- ---------------------------------------------------------------- tables\n\n',
    (select s from t_blk),
    E'\n\n-- ----------------------------------------------------------- constraints\n\n',
    (select s from c_blk),
    E'\n\n-- --------------------------------------------------------------- indexes\n\n',
    (select s from i_blk),
    E'\n\n-- ------------------------------------------------------------------- RLS\n',
    E'-- Full lockdown: RLS on with zero permissive policies. All access is\n',
    E'-- server-side via the service_role key; the anon key is deliberately unused.\n\n',
    (select s from r_blk), E'\n') as c
)
select md5(c) as md5, length(c) as chars, c as content from f;


-- ======================================================= 02_functions.sql
with defs as (
  select string_agg(pg_get_functiondef(p.oid) || E';\n', E'\n' order by p.proname, p.oid) as s
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prokind='f'
),
grants as (
  select string_agg(
           format(E'revoke all on function public.%I(%s) from public, anon, authenticated;\ngrant execute on function public.%I(%s) to service_role;',
                  p.proname, pg_get_function_identity_arguments(p.oid),
                  p.proname, pg_get_function_identity_arguments(p.oid)),
           E'\n' order by p.proname, p.oid) as s
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prokind='f'
),
f as (
  select concat(
    E'-- Ozzily database schema: functions and their EXECUTE grants.\n',
    E'-- GENERATED SNAPSHOT of live Supabase project siblqlstyccysqryggtr.\n',
    E'-- Do not edit by hand. Regenerate with generate.sql; see README.md.\n',
    E'--\n',
    E'-- REDACTED: the check-in trigger hook URL is replaced with a placeholder,\n',
    E'-- because this repository is public. The real value is in the Notion\n',
    E'-- Credentials Vault. Restore it before applying this file anywhere.\n\n',
    E'-- ------------------------------------------------------------- functions\n\n',
    (select s from defs),
    E'\n-- ---------------------------------------------------------------- grants\n',
    E'-- Postgres grants EXECUTE to PUBLIC by default, and create-or-replace keeps the\n',
    E'-- existing ACL, so revoking from anon/authenticated alone is NOT enough -- PUBLIC\n',
    E'-- is the grant that matters. Verify with the audit query in README.md.\n\n',
    (select s from grants), E'\n') as c
)
-- Substitute <HOOK_URL> below with the real check-in hook URL from the Notion
-- Credentials Vault. The replacement is what keeps the live URL out of this
-- public repository, and applying it here is what makes the md5 match the
-- committed 02_functions.sql.
select md5(replace(c, '<HOOK_URL>', '<MAKE_CHECKIN_HOOK_URL>'))    as md5,
       length(replace(c, '<HOOK_URL>', '<MAKE_CHECKIN_HOOK_URL>')) as chars,
       replace(c, '<HOOK_URL>', '<MAKE_CHECKIN_HOOK_URL>')         as content
  from f;


-- ======================================================== 03_triggers.sql
with trg as (select string_agg(pg_get_triggerdef(t.oid)||';', E'\n' order by c.relname, t.tgname) as s
          from pg_trigger t join pg_class c on c.oid=t.tgrelid
          join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and not t.tgisinternal),
f as (
  select concat(
    E'-- Ozzily database schema: triggers.\n',
    E'-- GENERATED SNAPSHOT of live Supabase project siblqlstyccysqryggtr.\n',
    E'-- Do not edit by hand. Regenerate with generate.sql; see README.md.\n',
    E'-- Trigger functions live in 02_functions.sql and must be created first.\n\n',
    (select s from trg), E'\n') as c
)
select md5(c) as md5, length(c) as chars, c as content from f;


-- ============================================== security audit (must be empty)
-- Any row here is a function callable by the public anon key over /rest/v1/rpc/.
select p.proname, p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f'
   and (p.proacl is null or has_function_privilege('anon', p.oid, 'EXECUTE'));


-- ======================================== label-vs-evidence audit (messages)
-- A *_photo row with with_media = 0 is a lie by construction.
select message_kind, direction, count(*) as rows,
       count(*) filter (where media_url is not null) as with_media
  from public.messages group by 1,2 order by 1,2;
