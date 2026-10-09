# Ozzily — Project Context for Claude Code

## What this is

Ozzily (`ozzily.com`) is an SMS-first AI companion app for GLP-1 medication users
(Ozempic, Wegovy, Mounjaro, Zepbound). It texts users daily to keep them on top of
protein intake and resistance training, so they don't lose lean muscle mass while
losing weight on the medication.

**Positioning: warm and companion-feel, like Tomo.ai — NOT clinical, NOT aggressive.**
Brand identity: cute mascot, warm marigold/plum palette. Deliberately avoiding
generic AI-startup-template aesthetics.

### Name history (do not resurrect these)
- Previously called **ProteinPolice** — rejected for aggressive tone and a bad `.co` domain.
- Also rejected: Zempick ("-ick" sound), Ozzudo (syllable count / judo association).
- Any old docs, PRDs, or exports referencing "ProteinPolice" are historical —
  the product logic in them is still mostly valid, but replace the name and tone
  (aggressive → warm/supportive) wherever it shows up.

## Current build state (Week 1 foundation complete)

- Landing page built and accessibility-hardened: WCAG AA contrast, mobile hamburger
  nav, pricing disclosure copy.
- Deployed to Vercel from GitHub repo `hustle-grover/ozzily-landing`, live at
  `ozzily.com` (apex is primary, `www` 308-redirects to apex).
- Supabase backend: project ID `siblqlstyccysqryggtr` (us-east-1). Six tables:
  `users`, `messages`, `streaks`, `payments`, `affiliate_clicks`, `scheduled_messages`.
  RLS enabled on all tables with zero permissive policies — full lockdown. All
  access is server-side via Make.com using the `service_role` key; the `anon` key
  is deliberately unused.
- Twilio number `+1 415 969 2088` — 415 area code chosen to match Tomo.ai's
  positioning. Runs on the **Massive Impact Media Private Limited** account.
  Switched Sep 2026 from the old personal-trial number `+1 415 980 6160` (that
  number is dead — required a real registered business for A2P 10DLC). Account
  SID, auth token, and phone-number SID live in the Notion Credentials Vault —
  never in this repo.
- Notion Builder OS set up (Projects, Credentials Vault, Daily Log, Ideas Pipeline,
  Resources & Tools) — this is the centralized system across all of Pankaj's
  projects; prefer keeping cross-project tracking there over per-repo docs.

## Infrastructure & tooling

- GitHub org: `hustle-grover`. Vercel team (Hobby plan): `team_vjD4PWRmCP6Tuup31FFFAE7E`.
- Automation currently lives in **Make.com** (webhook + scenario based) — not in
  this repo's code. If a task involves "wiring a CTA to Make.com," the repo-side
  work is just making sure the form POSTs to the right webhook URL; the scenario
  logic itself is configured in Make's UI, not here.
- AI: GPT-4o (system prompt engineering in progress).
- Payments: Stripe (setup pending).

## On the horizon (pick up here)

1. Wire the four landing page CTAs to the Make.com webhook for phone number capture.
2. Build out the Make.com automation scenarios (onboarding, vision AI photo
   verification, trial expiration, scheduled check-ins).
3. Engineer the GPT-4o system prompt (warm/supportive tone, not the old
   aggressive ProteinPolice tone — strict on no medical/dosing advice).
4. Set up Stripe billing (3-day trial → $29/month).

## Hard-won technical learnings

- Supabase function security: `revoke all on function from anon, authenticated`
  alone is **not enough** — Postgres grants EXECUTE to PUBLIC by default. Correct
  pattern:
  ```sql
  revoke all on function <name> from public, anon, authenticated;
  grant execute on function <name> to service_role;
  ```
- Use `get_advisors` for iterative security hardening after any migration.
- Ship over tooling overhead: the landing page was deployed as a straight HTML/
  Vercel prototype rather than building it in Framer — bias toward shipping.
- **Claude `/v1/messages` can return a leading `thinking` content block** (Sonnet 5
  started doing this Sep 2026, breaking the AI Brain with zero config changes). The
  response `content` becomes `[thinking, text]`, and Make's `map(content;"text")`
  keeps the empty thinking slot — so a fixed index grabs the wrong/empty element.
  **Never extract a fixed content index; always `join(map(7.content; "text"); "")`**
  to concatenate all text blocks (the empty thinking slot adds nothing). Symptom was
  `Source is not valid JSON` / `Missing value of required parameter 'json'` at the
  Parse JSON step, which auto-disabled the whole scenario.
- **The Make API cannot show per-module input/output** — only the Make UI can. To
  debug a scenario remotely, capture the raw value (e.g. `{{6.data}}`) into a temp
  Supabase table and read it back, or ask for the failing module's bundle from the UI.
- **Give the AI Brain an error-fallback.** A single bad/changed LLM response used to
  crash the run and trip Make's error limit, disabling the engine. The parse step now
  has an `onerror` → Twilio SendSMS fallback ("mind sending that again?") so one bad
  message can't take the whole scenario down.
- **Stay on Claude Sonnet 5 for the AI Brain**, not Haiku. Haiku 4.5 made digit-copying
  errors on the protein math (the reason for the original Sonnet upgrade). Parser/
  plumbing fixes are model-agnostic, so a model swap won't fix bugs — only trade math
  reliability for cost. Revisit Haiku only if cost bites at scale, and re-test arithmetic.

- **Anthropic vision needs base64 bytes — a URL is rejected.** `/v1/messages` refuses
  an image block with `source.type: "url"` (plain `400 Bad Request`, no useful body);
  only `source.type: "base64"` works. Proven both ways with a hardcoded 1×1 PNG. So any
  MMS flow must fetch Twilio's media and encode it before the Claude call. When bytes
  aren't available, `build_ai_request` emits a text marker telling Ozzily not to pretend
  it saw the photo — never silently drop the attachment.
- **Do not install the Supabase `http` (pgsql-http) extension.** Its functions are
  granted `EXECUTE` to `PUBLIC` *by `supabase_admin`*, and `postgres` cannot revoke a
  grant it didn't make (`set role supabase_admin` is denied too). The usual
  `revoke ... from public, anon, authenticated` silently no-ops, leaving a permanent
  un-revokable SSRF primitive. Use an Edge Function for outbound HTTP instead.
- **`verify_jwt` on an Edge Function is not authorization.** It only proves the caller
  holds *some* key signed by the project — and the anon key is public. Any function that
  returns user data or the system prompt must additionally check the presented key is the
  service role, reading both the `Authorization` and `apikey` headers.
- **Make's Supabase module authenticates with the `apikey` header, not
  `Authorization: Bearer`.** An Edge Function that checks only `Authorization`
  will reject Make with a 403 that looks exactly like a gateway refusal. Read
  both headers. This cost an hour of misdiagnosis — the AI Brain now calls
  `/functions/v1/ai-request` through the ordinary Supabase connection with no
  extra operation, so there is no gateway restriction on `/functions/v1/*`.
- **When an Edge Function 403s, check the deploy timestamp against the test
  timestamp before concluding anything.** A fix deployed *after* the failing
  test, or probed within ~15s of deploying, reads as "still broken."
- **Make disables a scenario after `maxErrors` (3) consecutive failures.** It comes back
  as `isActive: false, isinvalid: true` and silently stops answering the webhook. After
  any run of failed experiments, re-check `scenarios_get` and call `scenarios_activate` —
  and expect queued webhook payloads to replay all at once on reactivation.
- **Debug scaffolding goes in a temp table, then gets dropped.** Since Make can't show
  module I/O, a throwaway `public._fn_debug` row written from an Edge Function (header
  *shapes* and role claims only, never key material) is the way to see what a caller
  actually sent. Drop the table when done.
- **Keep trigger functions out of the REST API.** `security definer` trigger functions
  still land on `/rest/v1/rpc/<name>` for `anon`; `get_advisors` flags this. Revoke as
  with any other function. Also pin `search_path` (`alter function ... set search_path =
  public, pg_temp`) or every function shows up as `function_search_path_mutable`.

- **A webhook test is not an end-to-end test.** Every inbound test in this project's
  history was a `curl` POST straight at the Make hook URL, which proves the pipeline
  works *after* the webhook and says nothing about whether Twilio can reach it. As of
  2026-10-09, zero of 43 inbound `messages` rows carried a genuine Twilio SID
  (`SM` + 32 hex) — so no real handset had ever reached the AI Brain. Check for real
  SIDs before believing a flow is live:
  ```sql
  select count(*) filter (where twilio_sid ~ '^SM[0-9a-f]{32}

- **Execute directly.** Create schemas, deploy, update Notion, etc. — don't just
  hand back step-by-step instructions to run manually.
- **Push back when there's a better path.** He wants honest, direct opinions over
  hedged advice, including disagreement with the original plan.
- Iterate through accessibility/quality audit passes before calling a component done.
- Keep credentials and project tracking centralized in Notion — not scattered in
  ad hoc per-project notes.
- Descriptive, organized file names by default.
- Milestone-gated style: one clear deliverable at a time, verified before moving on.

## Secrets

Supabase `service_role` key, Twilio SID/auth token, and Stripe keys live in a local
`.env` (gitignored) — never in this file, never committed.
) as real_sids
  from public.messages where direction = 'inbound';
  ```
- **Twilio supports MMS only in the US and Canada.** Inbound MMS to the US long code
  from anywhere else fails with error `30011`, so the +91 test number can never be used
  to test vision — that needs a US/Canada handset. Plan photo testing around a US tester
  rather than burning time on why the photo "didn't arrive."

## How Pankaj wants this worked

- **Execute directly.** Create schemas, deploy, update Notion, etc. — don't just
  hand back step-by-step instructions to run manually.
- **Push back when there's a better path.** He wants honest, direct opinions over
  hedged advice, including disagreement with the original plan.
- Iterate through accessibility/quality audit passes before calling a component done.
- Keep credentials and project tracking centralized in Notion — not scattered in
  ad hoc per-project notes.
- Descriptive, organized file names by default.
- Milestone-gated style: one clear deliverable at a time, verified before moving on.

## Secrets

Supabase `service_role` key, Twilio SID/auth token, and Stripe keys live in a local
`.env` (gitignored) — never in this file, never committed.
