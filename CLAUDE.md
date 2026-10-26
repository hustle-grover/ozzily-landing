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

- **A Make webhook must "learn" its payload shape before `{{1.field}}` resolves.** If a
  hook has no learned data structure, every mapping from it silently evaluates to empty —
  which surfaces far downstream as a confusing error (for Login it was Twilio `21604`,
  "a 'To' phone number is required"). Fix with `hooks_learn_start` → POST one
  representative payload → `hooks_learn_stop`, then re-test. Suspect this whenever a
  mapping that *looks* correct yields nothing.
- **A failing instant scenario jams its hook queue, and the jam outlives the fix.** Three
  consecutive errors trip `maxErrors`, Make deactivates the scenario, and queued payloads
  pile up behind the failure ("fix the error or clear the queue"). After fixing, reactivate
  and let the queue drain — and prefer a guard filter that makes bad payloads exit
  cleanly over deleting queue items. A payload too malformed for Make to deserialize
  (e.g. 1 byte) can sit in the queue permanently and cannot be drained at all.
- **Put `onerror → Ignore` on every Supabase module in every scenario.** Make intermittently
  gets `401 JWT issued at future` from Supabase — clock skew, not misconfiguration. Two
  runs in the same second can split one success / one failure. Without a handler, that
  transient 401 trips `maxErrors` and jams the queue, turning a blip into an outage.

- **Twilio posts `application/x-www-form-urlencoded`, not JSON — teach the hook with a
  form-encoded payload.** The AI Brain hook had only ever learned the JSON shape from
  `curl` tests, so when real Twilio traffic arrived every mapping (`{{1.From}}`,
  `{{1.Body}}`, `{{1.MediaUrl0}}`) resolved empty and the run died three modules later.
  Make stored each real delivery as a **1-byte** queue item, which is the tell: a genuine
  Twilio POST is hundreds of bytes, so a 1-byte stored payload means Make received
  something it could not map to a learned structure. When simulating Twilio, always send
  `--data-urlencode` form fields (`From`, `To`, `Body`, `NumMedia`, `MediaUrl0`,
  `MediaContentType0`, `MessageSid`, …), never JSON — a JSON test will pass while real
  traffic silently fails.
- **Use a synthetic, non-matching `MessageSid` in tests** (e.g. `SMsynthetic-…`), never
  `SM` + 32 hex. A realistic-looking fake SID would pass the "is this real traffic?"
  query above and destroy the one signal that distinguishes genuine handset messages
  from test posts.

- **Inbound SMS from the +91 test number does not reach Twilio at all — confirmed twice.**
  Twilio's Monitor → Logs shows every message in the account as `Outbound API`, with zero
  inbound rows ever. Outbound to India works (Delivered via carrier), but a +1 long code
  receiving from outside +1 is ["not guaranteed to work in all cases, or at all
  times"](https://help.twilio.com/articles/360045489294), and Twilio also **substitutes the
  sender ID** on international delivery (messages went out from `+590391…`, not the Twilio
  number), so a reply would be addressed to a number we do not own. The conversational loop
  therefore cannot be tested from Pankaj's phone by any configuration change — it needs a
  US/Canada sender.
- **Check the Notion Builder OS before diagnosing anything infrastructural.** The finding
  above was *already recorded in the Daily Log on 2026-09-14*, confirmed via a Twilio support
  ticket, but it existed only in Notion and not in this file — so it was rediscovered from
  scratch a month later at the cost of a long debugging session. Search the Builder OS
  (Projects / Daily Log / Credentials Vault) first, and when something is learned there,
  mirror it into this file. A finding that lives in only one system gets re-learned.

- **A2P 10DLC gates *outbound* to US numbers, and the Campaign was never created.** Brand
  registration is not enough. Without an **approved Campaign** with the number in the
  attached Messaging Service's sender pool, Twilio blocks every US-bound message with
  [`30034`](https://www.twilio.com/docs/api/errors/30034) — welcome SMS, daily check-ins and
  AI replies alike. Confirmed "Not started" in the Console on 2026-10-15. It hid for weeks
  because the only test recipient was an Indian number, which is not A2P-governed: **outbound
  appearing to work for Pankaj was never evidence that it works for customers.** Inbound is
  *not* A2P-gated, so inbound testing and Campaign approval are independent tasks.
  Submission draft with real production data: `docs/a2p-campaign-registration.md`.
- **A number attached to a Messaging Service takes its inbound webhook from the Messaging
  Service, not the number.** Ozzily's number is in a Messaging Service (that setup step shows
  Complete), but the "A MESSAGE COMES IN" webhook was configured on the *number*. Set it on
  **Messaging Service → Integration** too, or inbound silently goes nowhere once real traffic
  starts. Verify this before concluding anything about inbound.
- **Twilio's international sender-ID substitution is visible on the handset.** Check-ins to
  the +91 number arrive from **`59039149`**, not +1 415 969 2088 — so a reply is addressed to
  a number we do not own and vanishes. `59039149` is short-code-shaped, and Twilio long codes
  cannot receive from short codes by default, making replies structurally undeliverable. If a
  tester says "I replied and nothing happened", have them read the sender number off the
  message first; it is a ten-second check that beats any amount of log archaeology.
- **The old `+1 415 980 6160` cannot be used for testing.** It sits on a separate *trial*
  account, which cannot register A2P 10DLC and can only send to verified numbers (`21608`).
  A trial account is a dead end for any US-bound test.

- **After changing a Postgres function's signature, reload PostgREST's schema cache.**
  Adding `p_weight_kg` to `apply_ai_turn` meant dropping and recreating it with a new arg
  list. The database had the new function immediately, but PostgREST kept serving its cached
  schema and could not resolve the call — so the AI Brain ran 7 operations instead of 9 and
  the turn was silently swallowed by the module's `onerror → Ignore`. Nothing errored
  visibly; the message simply never got logged. Fix:
  ```sql
  notify pgrst, 'reload schema';
  ```
  Suspect this whenever a Make scenario starts exiting early right after a function change,
  and note that the `onerror` guards which keep the queue healthy also hide this failure —
  compare the operation count against a known-good run to spot it.

- **`onerror → Ignore` turns a total outage into a silent one.** The daily check-in cron
  kept reporting SUCCESS for five days while delivering nothing: Twilio was failing (account
  suspended for low balance), the `Ignore` guard swallowed it, the route ended before the
  logging step, and `scheduled_messages.status` already said `'sent'` because it was written
  at *claim* time, not delivery time. Every signal we had said healthy. The tell was the
  **operation count — 7 instead of 8**; compare against a known-good run. Fixed by claiming
  as `'pending'` and letting a trigger on `messages` flip it to `'sent'` only when the
  outbound message is genuinely logged, plus `checkin_delivery_health()` as one honest query.
  **Rule: never let a status field be written by the step that *starts* an action — only by
  the step that *confirms* it.**
- **A health check that can report green during a known outage is worse than none.** The
  first version of `checkin_delivery_health()` only counted stuck `pending` rows, so once the
  dead beats were correctly marked `failed` it cheerfully returned `healthy = true` with
  6 claimed and 0 delivered. Always test a health check *against the failure it exists to
  catch*, not just against the happy path.
- **An approved A2P Campaign does not mean you can send.** Twilio's own approval email says
  sending begins "by adding phone numbers to the linked messaging service". An approved
  Campaign with an empty sender pool still returns `30034`. Approval, sender-pool membership
  and a funded account are three separate gates; only a delivered message proves all three.
- **Twilio suspends the whole account for low balance, not just the failing send.** Campaign
  registration fees drew the balance down immediately after submission and took every flow
  down with it — including non-US traffic, which is otherwise unaffected by A2P. Keep
  auto-recharge on; a prepaid balance is a single point of failure for the entire product.

- **An `onerror` handler that can itself fail will disable the scenario.** The AI Brain's
  parse-step fallback was a `twilio:SendSMS` with no handler of its own. With the Twilio
  account suspended, a single bad LLM response triggered the fallback, the fallback failed
  with `20003`, and that counted as a scenario error — three of those and Make disabled the
  engine and started queueing. Every fallback module now has its own nested
  `onerror → Ignore`. **Rule: the last module in any error path must be unfailable.**
- **Streaks are computed, never incremented.** `upsert_streak_day()` recomputes the day's
  protein total from the message log and upserts one row per user per *local* date, then
  `recalculate_streak()` counts consecutive `day_complete` days. Because nothing increments,
  replays, duplicate webhooks and same-day follow-up messages are all safe — verified: a
  second message the same day moved the total 90g → 102g while the streak correctly stayed
  at 1. The original `recalculate_streak()` used **UTC** for "today", the same bug class as
  the old protein-total function; it now uses the user's timezone.

- **The em dash is the single most expensive character in the product.** SMS bills per
  160-character GSM-7 segment, but **one** character outside the GSM-7 alphabet forces the
  whole message into UCS-2 at **70 characters per segment**. Measured on 72 real outbound
  messages: **74% were UCS-2**, costing 163 segments where plain text would have cost 95 —
  **42% of all SMS spend wasted**. The cause was not mainly emoji: the em dash `—` appeared
  in **40 of 72 messages** (emoji in far fewer), and it is invisible, adds nothing a hyphen
  does not, and Claude writes it by default. Curly quotes `'` `"` and the ellipsis `…` are
  the same trap. Both system prompts now carry an explicit plain-ASCII billing rule.
  Verified: a typical reply dropped from 2 segments to 1. Check any new prompt with:
  ```sql
  select body from public.messages
   where direction='outbound' and body ~ '[^\x01-\x7F]' order by created_at desc limit 20;
  ```
- **Destination dominates everything else.** India is roughly **$0.083/segment** against
  roughly **$0.0079** for US A2P — about **10x**. Every outbound message in the project's
  history went to the +91 test number, so 163 segments cost ~$13.50 instead of ~$1.30. One
  Indian test user on 3 check-ins a day is **~$17/month**; the same user on a US number with
  plain text is **~$0.92/month**. Test against a US number wherever possible, and never leave
  automated daily check-ins pointed at an international number.
- **Prompt changes must be applied in both places.** The drug-name ban added to
  `ai_brain_system_prompt()` on 2026-10-15 was missed in the **daily check-in prompt**, which
  lives in the Make scenario rather than the database and still named all four drugs and
  injected `Medication:` into its context. There are two prompts; a rule that matters belongs
  in both. Grep the Make blueprint, not just the SQL, when auditing prompt policy.

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

- **Ban the em dash deterministically, not just in the prompt.** Asking the model for plain
  ASCII lowers the rate but cannot guarantee it, and every slip roughly doubles that message's
  cost. The character census over all UCS-2 traffic was unambiguous: em dash U+2014 x40 and
  en dash U+2013 x2 were the *only* punctuation offenders -- no curly quotes, no ellipsis, no
  nbsp -- the rest was emoji (24 across 11 kinds), which is a deliberate product choice. So the
  send path now wraps every outbound body in a literal two-step replace:
  ```
  {{replace(replace(<body>; "—"; "-"); "–"; "-")}}
  ```
  applied in both the Twilio module and the matching log module of both scenarios, so the DB
  records what was actually sent. Prompt rules stay as a second line of defence; emoji are left
  to the prompt on purpose. Census query:
  ```sql
  with chars as (select regexp_split_to_table(regexp_replace(body,'[\x01-\x7F]','','g'),'') ch
                   from public.messages where direction='outbound' and body ~ '[^\x01-\x7F]')
  select ch, to_hex(ascii(ch)) codepoint, count(*) from chars group by ch order by 3 desc;
  ```
- **Hardcoded fallback strings are outbound messages too, and they were the worst offenders.**
  The AI Brain's error fallback read `"Oops — my brain glitched for a sec 😅 ..."` -- an em dash
  *and* an emoji in a 74-character string, i.e. 2 UCS-2 segments every time an error fired. A
  prompt rule can never reach a string that lives in the blueprint. Audit literal `body:` values
  in the Make blueprint whenever auditing encoding, not just the prompts.
- **An order-of-modules choice decides what you can test when a dependency is down.** The AI
  Brain writes to the DB (module 8) *before* sending (module 9), so its reply is observable even
  with Twilio suspended -- which is how the sanitizer got verified. The check-in scenario is the
  reverse (send, then log) because that ordering is what makes `scheduled_messages.status` honest.
  The cost is that its send path cannot be verified while Twilio is down: a failed send ends the
  route via `onerror -> Ignore` and nothing reaches the log. Do not "fix" this by moving the log
  earlier -- that re-introduces the silent-outage bug. Verify it on the first live beat instead,
  and use the operation count (8, not 7) as the tell.
- **A check-in trigger that returns 3 operations means nothing was due, not that it failed.**
  Webhook + `get_due_checkins` + feeder = 3, then the route ends because the feeder got an empty
  array. Expect this whenever a beat for that local date is already claimed. 7-8 operations is a
  real send; 3 is a no-op; 7 where 8 was expected is the silent-failure signature.

- **`message_kind` must describe the row it sits on, and a `*_photo` kind is a claim that
  needs checking.** Three bugs compounded here. (1) `apply_ai_turn()` wrote the model's
  classification onto the **outbound** reply and hardcoded the **inbound** row to
  `freeform`/`onboarding` -- so `meal_photo` always landed on a message that by definition
  carries no media, while the rows actually holding `media_url` and `detected_protein_g` were
  all `freeform`. The inbound row is the one carrying the content facts, so it is the row the
  classification belongs on. (2) Nothing verified a photo existed, so a text-described meal was
  logged `meal_photo`; the fix **demotes only** (`meal_photo` -> `meal_log`, `workout_photo` ->
  `workout_log`) and never promotes, because media does not imply a meal -- an inbound photo
  asking "what colour is this square?" is not a `meal_photo`. (3) The prompt offered the model
  `midday_checkin` / `evening_checkin` / `recap`, and `mark_checkin_delivered()` fires on
  outbound beat kinds -- so a reply labelled `recap` would flip a **pending**
  `scheduled_messages` row to `'sent'` with nothing sent. Model-supplied labels are now
  whitelisted against a conversational set that excludes all four beats.
  **Rule: never let a model-chosen value reach a field that a trigger treats as proof.**
- **Check a label against the evidence column, not just the enum.** A `CHECK` constraint
  accepted `meal_photo` happily because the enum is per-value, not relational. The query that
  actually finds this class of bug compares the label against the fact it asserts:
  ```sql
  select message_kind, direction, count(*),
         count(*) filter (where media_url is not null) as with_media
    from public.messages group by 1,2 order by 1,2;
  ```
  A `*_photo` row with `with_media = 0` is a lie by construction.
- **Rewrite a long prompt by asserted substring replacement, never by retranscribing it.**
  `ai_brain_system_prompt()` is ~80 lines; retyping it to change one line risks silent drift.
  Read the function's own output, `replace()` the exact substrings, `raise exception` if any
  target is not found verbatim or the result is unchanged, then `create or replace` from the
  result. A `replace()` that misses is a silent no-op, which is the failure mode to guard.
- **`create or replace function` preserves the existing ACL**, so it will happily carry a
  `PUBLIC` grant forward. `ai_brain_system_prompt()` had `proacl = {=X/postgres,...}` -- the
  leading `=X` is PUBLIC -- making the whole system prompt readable by `anon` over
  `/rest/v1/rpc/`. Every other function was correctly locked down; this one was missed because
  the default grant is invisible unless you look for it. Audit with:
  ```sql
  select p.proname, p.proacl::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and (p.proacl is null or has_function_privilege('anon', p.oid, 'EXECUTE'));
  ```
  An empty result is the only acceptable answer. Note `get_advisors` did **not** flag this.
- **The schema snapshot lives in `supabase/schema/` — regenerate it after any DB change.**
  Tables, all 18 function bodies (including the system prompt), triggers and the EXECUTE
  grants are committed there, so a prompt or function change is now reviewable in a diff.
  Supabase is still the source of truth; these files are generated by `generate.sql` and
  each query returns an md5 to verify the written file. Two traps: `length()` returns
  *characters* not bytes (one em dash in `checkin_delivery_health` makes the file 2 bytes
  larger than reported, so compare md5 not size), and the files must stay LF-only, which
  `.gitattributes` pins. `02_functions.sql` **redacts** the check-in hook URL, because the
  repo is public.
- **The migration history is not a faithful replay of the database.** Ten migrations from
  2026-09-05 to 09-16, then a five-week gap: `apply_ai_turn`, `get_due_checkins`,
  `upsert_streak_day`, `mark_checkin_delivered`, `scheduled_messages` and `users.weight_kg`
  were all applied as ad hoc `execute_sql` rather than migrations. Replaying the history
  would not reproduce production. Use `apply_migration` for every future change so the gap
  stops growing, and mirror the result into `supabase/schema/`.
- **This repository is PUBLIC, and it had no `.gitignore` at all** until 2026-10-24, despite
  this file asserting that secrets live in a "gitignored" `.env`. Nothing had leaked (no
  `.env` existed on disk and none was tracked), but the stated protection was not real.
  A `.gitignore` now covers `.env*`, keys and build noise. The signup, login and inbound
  Make hook URLs are already committed in `index.html`, `login.html` and the A2P doc — the
  first two unavoidably, since the browser posts to them — so treat those endpoints as
  public and guard on payload shape, never on the URL being secret.

- **The reply cap must be 160, not a round number near it.** A GSM-7 SMS holds exactly
  **160** characters in one segment; past that the message becomes multipart at **153** per
  segment, so a 161-character message costs precisely double a 160-character one. The cap was
  set to 200 on 2026-10-24, which sits on the wrong side of that cliff and guaranteed 2
  segments for any reply over 160. Measured on ASCII-clean outbound traffic: **26% exceeded
  160 characters**, costing 29 segments where 23 would have done -- a further **21% overspend
  on top of the UCS-2 fix**, from a cap that looked like a tightening. Both prompts now say
  160 and explain why, since a bare number reads as style guidance and gets rounded up.
  Encoding and length are two independent segment multipliers; fixing one proves nothing
  about the other. Check with:
  ```sql
  select count(*) filter (where length(body) > 160) as over_160, count(*) as total
    from public.messages
   where direction='outbound' and body is not null and body !~ '[^\x01-\x7F]';
  ```

- **Payments go through Paddle, a merchant of record — and the reason is tax, not fees.**
  Stripe is not unavailable to an Indian company, it is *invite-only*. The decisive factor is
  that **SaaS is taxable in 20+ US states**, so selling a 29/month subscription direct to US
  consumers accrues economic nexus. Razorpay (~3% + GST) and PayPal both leave that liability
  with us; Paddle (~5% + 50c) becomes the legal seller of record and handles it, pays USD to
  an Indian bank, and needs no US entity. The premium is under 1/month per subscriber.
  GST/FEMA export-of-services treatment is a question for the CA, and Paddle's India payout
  specifics are not on an official Paddle page — confirm both before launch.
- **A Paddle user is linked by `custom_data.user_id` on the checkout, never by email.**
  Ozzily collects only a phone number at signup, so there is no email to match a Paddle
  customer against. `apply_payment_event()` resolves in that order: `user_id`, then
  `provider_subscription_id`, then `provider_customer_id`, and returns `ok:false` rather than
  inventing an orphan row (`payments.user_id` is NOT NULL with an FK). It returns instead of
  raising, so the scenario can alert without tripping `maxErrors`.
- **Paddle retries webhooks and can deliver out of order, so two separate guards are needed.**
  `provider_event_id` is UNIQUE and is the idempotency key, which makes a retry a no-op rather
  than a duplicate charge record. Separately, status changes are gated on `occurred_at` being
  newer than `users.last_billing_event_at`, so a replayed `subscription.canceled` cannot
  overwrite a later `subscription.resumed`. Verified against both failures rather than the
  happy path: a stale cancel left the user `active`, and a replayed payment produced one row.
- **The same "reports an intention, not an outcome" bug reappeared in my own new code.**
  `apply_payment_event()` first returned the status it had *mapped from the event* rather than
  the status *actually applied*, so a correctly-ignored out-of-order cancel reported
  `subscription_status: cancelled` while the user remained `active`. It now reads the row back
  after writing and returns `status_change_applied` plus a `skipped_reason`. This is the third
  instance of the class in this project, after `scheduled_messages.status` and the
  `message_kind` label. **Any function that reports what it did must read back what is true.**
- **The welcome SMS was the worst encoding offender in the product and had never been audited**,
  because it is a hardcoded string in the Signup Flow blueprint rather than a prompt. It
  carried a wave emoji *and* an em dash in 308 characters — **5 UCS-2 segments where 3 would
  do** — on the one message every single user receives. It is **all-or-nothing**: removing only
  the em dash saves nothing while the emoji still forces UCS-2. Rewritten to plain ASCII and
  trimmed to 302 characters, which crosses the 306 boundary into **2 segments, down from 5**.
  All four compliance elements were preserved (frequency, rates, STOP, HELP), so the registered
  A2P sample still matches in substance. Check any rewrite against both length and compliance,
  not just encoding.
- **Check the execution record before believing a failure rate, including one you stated
  yourself.** The AI Brain's JSON parse step was carried for days as "2 of 4 test messages
  failed" — a watch item written into this file. The actual record shows **one** ParseJSON
  error in the scenario's entire history (2026-10-20 05:31), and the very next event that same
  second is the Twilio `20003` suspension warning: that was the *unfailable-fallback* bug, not
  a parser problem, and every run since has been 9 operations SUCCESS. `executions_list` gives
  `operations`, `displayStatus` and `error.causeModule` per run, which is the cheapest honest
  answer available — use it before escalating a brittleness into a defect.
- **The parse step now extracts the first `{` to the last `}` as well as stripping fences.**
  The mapper is
  `replace(replace(replace(replace(join(map(5.content;"text");""); "```json";""); "```";""); "/^[^{]*/";""); "/[^}]*$/";"")`
  — the two regex passes are **additive on top of** the fence stripping on purpose, so that if
  Make's regex syntax ever fails to match, the result silently degrades to the previous
  behaviour instead of regressing. It tolerates a prose preamble, trailing commentary, and any
  fence variant. Verified non-regressive (9 ops, reply logged, `meal_log` + protein on the
  inbound row); the robustness gain is reasoned rather than proven, since a malformed model
  response cannot be forced on demand.
