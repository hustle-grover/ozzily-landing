# Database schema snapshot

The live database is Supabase project `siblqlstyccysqryggtr` (us-east-1). This
directory is a **generated snapshot** of its `public` schema, so that function
bodies, constraints and the system prompt can be reviewed in a diff and tracked
in git. It is documentation, not a deployment artifact.

| File | Contents |
|---|---|
| `01_tables.sql` | tables, constraints, indexes, RLS |
| `02_functions.sql` | all 18 functions and their EXECUTE grants |
| `03_triggers.sql` | the 5 triggers |
| `generate.sql` | the queries that reproduce all of the above, plus two audits |

## Supabase is the source of truth, not this directory

Changes are applied to the database as Supabase migrations and then mirrored
here by regenerating. Never edit these files and expect anything to change.

**The migration history is not a faithful replay.** There are 10 migrations
from 2026-09-05 to 09-16, then a five-week gap to 2026-10-24. Everything built
in between — `apply_ai_turn`, `get_due_checkins`, `upsert_streak_day`,
`mark_checkin_delivered`, the `scheduled_messages` table, `users.weight_kg` —
was applied with ad hoc SQL rather than a migration. So replaying the migration
history would **not** reproduce the live database, which is exactly why this
snapshot exists. Use migrations for all future changes so the gap does not grow.

## Regenerating

Run each query in `generate.sql` and write its `content` column to the matching
file. Each query also returns an `md5`; verify with `md5sum <file>`.

Two gotchas when verifying:

- `length()` returns **characters, not bytes**. `02_functions.sql` contains one
  em dash (in `checkin_delivery_health`'s detail text), 3 bytes for 1 character,
  so the file is 2 bytes larger than the reported length. Compare md5, not size.
- These files must stay LF-only or the md5 will not match. `.gitattributes`
  pins `*.sql` to `eol=lf`.

## Redaction

`02_functions.sql` replaces the check-in hook URL inside
`trigger_checkins_if_due()` with `<MAKE_CHECKIN_HOOK_URL>`, because **this
repository is public**. The real value lives in the Notion Credentials Vault
and must be restored before applying the file anywhere.

Note that the signup, login and inbound hook URLs *are* already public in
`index.html`, `login.html` and `docs/a2p-campaign-registration.md`. The first
two are unavoidable — the browser posts to them — but it means any of those
endpoints can be hit by anyone who reads the repo, so treat them as public and
guard on payload shape rather than on the URL being secret.

## Two audits worth running after any change

**No function may be callable by the public anon key.** An empty result is the
only acceptable answer. `get_advisors` does **not** cover this — it missed a
`PUBLIC` EXECUTE grant on `ai_brain_system_prompt()` that exposed the whole
system prompt over `/rest/v1/rpc/`.

```sql
select p.proname, p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f'
   and (p.proacl is null or has_function_privilege('anon', p.oid, 'EXECUTE'));
```

**No message may claim a photo it does not have.** A `*_photo` row with
`with_media = 0` is a lie by construction.

```sql
select message_kind, direction, count(*) as rows,
       count(*) filter (where media_url is not null) as with_media
  from public.messages group by 1,2 order by 1,2;
```

## RLS

Every table has RLS enabled with **zero** permissive policies — full lockdown.
All access is server-side through Make.com with the `service_role` key; the
`anon` key is deliberately unused. `get_advisors` reports this as
`rls_enabled_no_policy` (INFO) on all six tables, which is expected and not a
finding.
