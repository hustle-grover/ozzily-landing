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
- AI: Anthropic Claude Sonnet 5 for the AI Brain (see the model note below).
- Payments: Paddle as merchant of record (data layer and webhook built).

## On the horizon (pick up here)

1. Wire the four landing page CTAs to the Make.com webhook for phone number capture.
2. Build out the Make.com automation scenarios (onboarding, vision AI photo
   verification, trial expiration, scheduled check-ins).
3. Engineer the Claude system prompt (warm/supportive tone, not the old
   aggressive ProteinPolice tone — strict on no medical/dosing advice).
4. Finish Paddle billing (3-day trial over SMS → $29/month).

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
  select count(*) filter (where twilio_sid ~ '^SM[0-9a-f]{32}$'
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

Supabase `service_role` key, Twilio SID/auth token, and Paddle keys live in a local
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
- **`create or replace function` preserves nothing about the body's QUOTING, and how you
  re-create it decides the size of the snapshot diff.** Changing one line of
  `ai_brain_system_prompt()` on 2026-11-09, the body was first rebuilt with dollar-quoting
  (`as $function$ select $tag$...$tag$::text $function$`), which is attractive because it
  removes the need to double every apostrophe in 9.6KB of prose. It worked and the prompt text
  came out byte-identical -- but `pg_get_functiondef()` then returns the body in that *new*
  shape, so the regenerated snapshot differed from the committed one across the **whole
  ninety-line function** instead of the one line that actually changed. Rebuilding with
  `quote_literal(v_text)` reproduces the original `as $function$ select '...'::text $function$`
  form exactly and the diff collapses to a single line. **Rule: when rewriting a function whose
  definition is committed, reproduce the original quoting style, not merely the original
  semantics.** A ninety-line diff of a file nobody can read is a review nobody performs, and
  that is precisely where an unintended change hides. Check before writing the file by
  comparing the element's `md5(pg_get_functiondef(oid) || E';\n')` against the database, which
  is also what catches a transcription slip of one character.
- **The schema snapshot lives in `supabase/schema/` — regenerate it after any DB change.**
  Tables, all 24 function bodies (including the system prompt), triggers and the EXECUTE
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

- **Make cannot verify a webhook signature, and Paddle's destination must be an Edge
  Function.** Paddle signs `ts + ":" + raw_request_body` with HMAC-SHA256 over the **raw
  bytes**. Make's gateway webhook parses the JSON and re-serializes it, so no Make module
  ever sees the bytes that were signed — key order and whitespace differ and the HMAC can
  never match. Make *does* have HMAC (`sha256(text; key)`), so the temptation is real, but
  the payload it would hash is not the payload Paddle signed. The receiver is therefore
  `supabase/functions/paddle-webhook`, which reads `await req.text()` before anything
  parses it. The Make hook that was created first (id 2997965) is **not** Paddle's
  destination; it is reserved for the outbound "payment received" SMS. This generalises:
  **any provider that signs a raw body cannot be verified inside Make.**
- **`verify_jwt = false` is correct for a provider webhook, because the signature is the
  authentication.** Paddle sends no Supabase JWT, so requiring one would reject every real
  event. The HMAC replaces it. The rule from the `ai-request` function still holds in the
  other direction: `verify_jwt` alone was never authorization either.
- **Fail closed when the signing secret is missing.** `paddle-webhook` rejects with 401 when
  `PADDLE_WEBHOOK_SECRET` is unset, rather than passing events through unverified. Verified
  live: unsigned, malformed-header and wrong-signature requests all return 401, and a GET
  returns 405.
- **A signature check needs a replay window, and the timestamp must be inside the signed
  payload.** Rejecting a stale `ts` (300s default) stops a captured request being replayed
  forever, and because `ts` is part of what is signed, an attacker cannot refresh it to dodge
  the window — rewriting `ts` breaks `h1`. Proven both ways. **Note the test that first
  appeared to show a bypass was wrong:** it generated the old and new timestamps in the same
  second, so the signature legitimately matched. Re-run with a genuinely old `ts` before
  believing either a pass or a failure.
- **Return 2xx for a verified-but-unusable event, non-2xx only for a transient fault.**
  Paddle retries on non-2xx. An event whose user cannot be resolved will never resolve, so it
  returns 200 and is logged; a failed RPC returns 500 so Paddle retries. Getting this backwards
  gives either an infinite retry loop or silently dropped payments.
- **The trial model is Option A: the 3-day trial runs over SMS, not in Paddle.** Paddle's own
  trial collects the card at checkout, which contradicts four published claims of "no card
  required" (twice in `terms.html`, twice in `index.html`) on a live, A2P-registered site. So
  both Paddle prices carry **no trial**, `/pay` is texted on day 4, and Paddle charges
  immediately at checkout. **If a trial is ever added to a Paddle price, remove the SMS trial
  in the same change** — otherwise the customer gets six free days and the first charge lands
  on day 7, which is the kind of mismatch that only surfaces as a wrong charge date weeks later.
- **`/pay` refuses a checkout it cannot attribute.** `pay.html` opens Paddle only with a valid
  uuid `uid`, which becomes `custom_data.user_id`. Signup collects no email, so that is the
  only link between a Paddle customer and an Ozzily user — an unlinkable payment charges
  someone we cannot match, which is worse than no payment. `_ptxn` is exempt because that
  transaction already carries its own `custom_data`.

- **A `+` in a URL query string means SPACE, so an E.164 phone lookup must be `%2B`-encoded.**
  The Login scenario queried `/rest/v1/users?phone=eq.{{1.phone}}` with `+919255435752`, so
  PostgREST searched for `" 919255435752"` and **never matched**. The "Found" branch
  therefore essentially never fired from the day it was built. Fixed with
  `phone=eq.{{replace(1.phone; "+"; "%2B")}}`. **Audited 2026-11-01: this was the only
  occurrence.** Every other phone lookup in the system puts the value in a POST body or an
  RPC parameter, where JSON encoding handles it — Signup (`/rest/v1/users?on_conflict=phone`,
  phone in the body; `on_conflict` is a column name, not a value), the AI Brain
  (`/functions/v1/ai-request` and `/rest/v1/rpc/apply_ai_turn`, both bodies), Check-ins
  (`/rest/v1/rpc/get_due_checkins`, empty body), and both Edge Functions (`p_phone` in JSON).
  **The rule: never interpolate a phone number into a URL. Use a POST body or an RPC
  parameter.** `pay.html` puts a uuid in a query string, which is safe only because a uuid
  contains no `+`.
- **Testing only the path you expect to break will certify a broken fix.** The leak fix was
  verified with an unknown number (2 ops, no SMS — correct) and looked done. Testing the
  *known* number showed 2 ops as well: a legitimate user got nothing, because of the `+` bug
  above. **Always test the success path and the refusal path.** For a Make scenario the
  operation count is the cheapest discriminator: Login is 3 ops for a real send and 2 for a
  correct no-op.
- **An "enumeration leak" was the wrong diagnosis; the real fault was an open SMS relay.**
  Both old Login branches texted *the submitted number*, never the requester, so nothing
  leaked to an attacker. What was actually there: the "not signed up" branch texted
  *"Start your free 3-day trial at ozzily.com"* — a **promotional** message — to any number
  typed into a public form, with no consent, billed to us, on a campaign registered as
  informational. Combined with the `+` bug, **every** login attempt took that branch, so the
  spam went to real customers too. Route deleted: unknown numbers now receive nothing.
  **Diagnose from the blueprint, not from the documentation describing it.**
- **A publicly triggerable "send a text to this user" endpoint is an abuse vector even when
  it only texts known users.** After the fix, anyone who knows a customer's number can still
  make us text them repeatedly, at our cost. There is no rate limit on the Login hook. This
  is why the page should be switched off until Verify ships rather than merely corrected.
- **Signup has the same missing-ownership problem that Login had.** Nothing proves the
  submitter owns the number: type a stranger's number into ozzily.com and they receive the
  welcome SMS, *and* a `users` row is written recording `consent_at`/`consent_text` as though
  they consented. That is a false consent record in the A2P audit trail. Twilio Verify at
  signup — verify the code first, then create the row and send the welcome — closes it.
  **FIXED 2026-11-02** by the `signup-verify` Edge Function; see the entries below.

- **A public webhook URL means verification in front of the *page* fixes nothing.** The Make
  signup hook URL is committed in `index.html`, unavoidably, because the browser posts to it.
  Adding an OTP step to the page would have left the hook reachable, so anyone could still
  POST straight at it and create an unverified user with a fabricated consent record. The
  fix only works because `signup-verify` owns the whole flow **and** scenario 6171131 is
  deactivated — the same pairing the Login fix needed. **Rule: when a page stops being the
  only caller of an endpoint, the endpoint is the thing that must change, not the page.**
  Order matters on deploy: ship the page first, then switch the scenario off, or the live
  form posts into a deactivated hook and every signup queues instead of working.
- **Twilio Verify is exempt from A2P 10DLC for verification use cases**, confirmed in two
  places in Twilio's docs (the A2P overview, and the `30034` error page's own remediation).
  So OTPs cannot be blocked by `30034` and do not consume the registered campaign. Inbound
  is likewise not A2P-gated, so OTP, campaign approval and inbound are three independent
  concerns.
- **Verify and Messaging have SEPARATE geo permissions, and only Verify has a safe list.**
  Verify: Console → Verify → Settings → Geo permissions, with a safe list that bypasses geo
  **and** Fraud Guard's "monitor all traffic" option. Messaging: Console → Messaging →
  Settings → Geo Permissions, **not changeable via API** by Twilio's own design, and with no
  safe list. Consequence for testing: the +91 number can receive an OTP with India disabled
  globally (safe list), but the welcome SMS still needs India temporarily enabled in
  *Messaging*. Configuring one and assuming the other followed is the trap.
- **Rate limits must sit in front of the paid call, not behind it.** Verify's own per-phone
  limits only engage once a request has reached Twilio, by which point it has already cost
  ~$0.05. `verify_rate_check()` therefore runs before the Twilio call and **inserts its row
  before counting** — counting first lets two concurrent requests both read "2 so far" and
  both proceed, so the limit is beatable by racing. Verified: 4 rapid starts, the 4th
  blocked. Cheap-refusal gates (E.164, consent, country) run before even that, so garbage
  never reaches the ledger.
- **The IP is stored only as a salted SHA-256.** The limit needs to count per client; it
  never needs the address. Nothing in the system can reverse `verification_attempts.ip_hash`.
- **`create_verified_user()` reads the row back and returns `is_new` from `xmax = 0`.** That
  is the fourth instance of the report-an-intention bug class in this project, after
  `scheduled_messages.status`, the `message_kind` label and `apply_payment_event()` — so it
  was built in from the start rather than discovered in production. `is_new` decides whether
  the welcome SMS fires, so it has to come from the write, not from an assumption.
- **A verified signup is the only thing allowed to clear `sms_opted_out`.** Proving ownership
  with the consent box ticked *is* a genuine re-opt-in, so the upsert resets it. But the
  first `consent_at` is preserved with `coalesce`, because the audit trail cares when consent
  was first given, and a returning signup must not restart the trial either. Verified both.
- **`users.plan` was being polluted with a preference.** The old Make flow wrote the literal
  string `'unspecified'` into the billing column `apply_payment_event()` owns. Signup
  preference now lives in `users.preferred_plan`; `plan` stays null until a payment sets it.
  Legacy rows still carry `'unspecified'` and have not been cleaned.
- **Test the refusal path and the success path, and assert on what must NOT exist.** The
  central check here is not "a valid code works" but "a wrong code creates nothing": a
  `confirm` with a bogus code returned `code_incorrect` and left **zero** `users` rows and
  **zero** `messages` rows. That assertion is the feature. Eight refusal cases were also run
  against the live function, and the fact that none returned `503` is what proved all seven
  required secrets were actually set.
- **Patch a generated snapshot by asserted substring insertion, never by retranscribing it.**
  Re-pulling 60KB of `02_functions.sql` through context to add four functions is wasteful and
  the md5 makes splicing safe: insert at the generator's own `order by proname, oid`
  positions, then compare md5 against the database. A mismatch of exactly **one character**
  turned out to be a double-escaped backslash in the `'^\+[1-9]...'` regex — found in minutes
  by diffing the md5 of each element against `md5(pg_get_functiondef(oid) || ';\n')` rather
  than eyeballing. **Add a guard that refuses to write if the redaction placeholder is
  missing or a live `https://hook.` URL is present**, since this repo is public and the
  generator's job is to keep that URL out of it. Note the grants block is built from
  `pg_get_function_identity_arguments`, which includes parameter **names**
  (`p_event_id text, ...`), not bare types — matching on types alone finds nothing.

- **`hooks_update` cannot disable a Make hook, and says "Hook has been updated" anyway.**
  `enabled` is not writable through that endpoint: the call requires `headers`, `method`
  and `stringify` in `data`, accepts `enabled: false` alongside them, reports success, and
  leaves `enabled: true`. Verified by re-reading the hook afterwards. Make's API has
  separate `/hooks/{id}/enable` and `/disable` endpoints that the MCP server does not
  expose, so **disabling a hook is a Make UI action**. Another silent no-op that only a
  read-back catches — never trust a Make API success message for a field you did not
  then re-read.
- **A2P 10DLC covers US destinations only, so the approved campaign says nothing about
  Canada.** Twilio: the regulation *"applies only to messaging sent from 10DLC numbers to
  receiving numbers in the US."* Canadian recipients are governed by Canadian carriers
  instead. Decision 2026-11-02: **US only.** The trap is that Canada shares the `+1`
  country code, so `SIGNUP_ALLOWED_PREFIXES="+1"` cannot express "US only" — it takes a
  NANP **area code** list. `signup-verify` carries 53 Canadian area codes behind
  `SIGNUP_BLOCK_CA` (default on), and the list was checked both ways: no US area code is
  in it, and the known Canadian ones are. Getting that list wrong silently blocks real
  customers, so test it in both directions, not just that Canada is refused.
- **`text[] || 'some literal'` raises 22P02, and only once there is something to report.**
  Postgres parses the right-hand side as an array literal. `verification_health()` passed
  every happy-path test and then threw the instant a problem existed — i.e. it would have
  died precisely during the outage it exists to catch. Cast explicitly: `|| 'text'::text`.
  This is the third turn of the same screw after `checkin_delivery_health()`: it is not
  enough for a health check to *report* a failure, it has to **survive** one. Test it
  against the failure.
- **The global daily cap is a deliberate self-inflicted outage, so it must warn early.**
  Per-phone and per-IP limits bound one attacker and do nothing against a distributed
  burst, where every request looks like a different first-time visitor. The global cap
  (200 starts/24h, ~$13 worst case) fixes that, but when it trips **nobody** can sign up.
  Verified: with the cap exceeded, a brand-new phone and IP is refused `global_daily`.
  That is the right direction to fail — a lost day is recoverable, an unbounded bill is
  not — which is exactly why `signup-verify` alerts at **80%**, while signups still work,
  and not only at the ceiling. `VERIFY_ALERT_WEBHOOK_URL` is the delivery channel and the
  alert path is unfailable by construction.
- **Switching a backend off makes the page in front of it lie.** `login.html` still read
  *"Pop in the number you text Ozzily from and we'll send a text straight back"* after the
  Login scenario was deactivated, so a returning user was promised a text that could never
  arrive — while the success panel below it correctly said there was nothing to log into.
  Two bits of copy on one page disagreeing is the tell. **When a flow is disabled, audit
  the copy that described it in the same change.** Also: `/login` 404'd because only
  `/pay` had a `vercel.json` rewrite; the nav link worked solely because it points at
  `login.html` with the extension.
- **`terms.html` does not disclose Paddle as merchant of record.** Paddle is the legal
  seller, issues the receipt, appears on the card statement and remits the tax, and none
  of that is stated anywhere on the site. That is a consumer-disclosure gap rather than a
  copy preference, and it needs the exact legal entity name from the Paddle dashboard
  rather than a guess. Raised 2026-11-02, drafted, not yet applied.
- **`payments` now stores `tax_cents`, `fee_cents` and `earnings_cents`.** Gross alone
  cannot answer "what did we keep". All three are **nullable on purpose**: Paddle fills
  `fee` and `earnings` only once a transaction settles, so 0 would be a false statement
  rather than a missing one. Verified both ways — a settled event reconciles
  (`grand_total = earnings + fee + tax`, 2900 = 2473 + 195 + 232) and an unsettled one
  stores `tax` with `fee`/`earnings` null — and the `provider_event_id` idempotency guard
  still makes a replay a no-op after the signature change.
- **`tax`, `fee` and `earnings` all arrive at PURCHASE time, not at settlement.** The
  bullet above says Paddle fills `fee` and `earnings` only once a transaction settles.
  The first real sandbox checkout (2026-11-05) disproved that: the
  `transaction.completed` event carried all three immediately and reconciled on the spot
  -- **2900 = 2263 earnings + 195 fee + 442 tax**. So a `payments` row is complete from
  the moment it is written, and "what did we keep" is answerable without waiting or
  backfilling. Compare with the earlier simulated figures, 2900 = 2473 + 195 + 232: the
  **fee was identical (195) and only the tax moved**, because tax is jurisdictional and
  the simulation used a different one. Keeping the three columns **nullable is still
  correct** -- it costs nothing and a null is an honest "not told" where a 0 would be a
  false statement -- but do not design anything around the assumption that they are
  absent at first. Verify on the live account rather than carrying this over: sandbox is
  a separate system, and nothing about live payouts is proven by it.
- **The two failure mappings have never been exercised, in any environment.**
  `apply_payment_event()` maps `transaction.payment_failed` to a `failed` payment row
  plus `past_due`, and `adjustment.updated` to `refunded`. Every test so far has been a
  success path -- purchase, activation, cancellation -- so both remain untested, which by
  this project's own rule ("test the refusal path and the success path") means untested
  in the direction that matters. `transaction.payment_failed` is also the only path that
  writes `failure_reason`, and the webhook hardcoded `p_failure_reason: null` -- so that
  column could not populate at all, a bug visible only by reading the function and the
  webhook together. **Both fixed 2026-11-05:** the reason now comes from
  `data.payments[].error_code`, taking the first attempt that carries a code rather than
  strictly `payments[0]`, because a newer attempt can sit in `action_required` with a null
  code while the real decline reason is on the attempt behind it. A null is left as an
  honest "Paddle did not tell us" rather than coerced to "unknown". Verified against the
  live function: a `transaction.payment_failed` wrote `failed` + `insufficient_funds`.
  **Still true: neither failure event has been exercised by a REAL Paddle event** -- only
  by direct RPC calls and signed synthetic requests. A dunning failure that silently does
  nothing is a customer who keeps service without paying.

- **A pricing claim has to be audited on every page that shows a price, not the two you were
  asked about.** The tax-inclusive copy was scoped to `index.html` and `terms.html`, but
  `grep -o '\$29\|\$249'` across all five pages found `pay.html` carrying bare `$29` / `$249` --
  the actual checkout page, where a tax statement matters most, and the one page where it named
  Paddle only as "secure checkout" with no merchant-of-record disclosure. Shipping the two
  approved pages alone would have left the checkout silent on tax while the pricing page
  promised it, which is worse than either state. Audit by grepping the *claim's subject* (the
  price) across every page, not by editing the files named in the request.
- **Paddle is the merchant of record and that was disclosed nowhere.** It issues the receipt,
  appears on the card statement, and collects and remits sales tax or VAT. The named entity is
  **Paddle.com Market Limited**, confirmed from the dashboard on 2026-11-03 and now stated in
  `terms.html`, `pay.html` and `privacy.html`. The GST/FEMA export-of-services side is still a
  question for the CA.
- **Do not introduce a heading level a page's CSS does not define.** `terms.html` styles `h1`
  and `h2` only, so the new `<h3>` rendered as an unstyled browser default (bigger, wrong face)
  next to the styled `h2`s. `grep -n 'h3' terms.html` returned exactly one hit -- the line just
  added -- which is the tell. Rewritten as the page's existing `<p><strong>lead-in:</strong>`
  pattern, verified identical to the surrounding `li` text (16px, same colour, weight 700).
  Check a new tag against the stylesheet before assuming it inherits anything.

- **`privacy.html` still named Stripe as the payment processor, three weeks after the switch to
  Paddle.** Naming the entity in `terms.html` was the prompt to grep the whole site, and the
  privacy policy turned out to misidentify the company that actually receives customer payment
  data -- in the "Who we share it with" list *and* in the data table ("Payment status: from
  Stripe"). A wrong processor in a privacy policy is a worse defect than the missing
  merchant-of-record disclosure that started this, because it is an affirmative false statement
  rather than an omission. **When a vendor changes, grep for the old vendor's name across every
  page, not just the file you are editing.** `grep -rn -i 'stripe' --include=*.html .` now
  returns nothing.
- **A new processor purpose needs a privacy-policy line even when the processor is unchanged.**
  Twilio was already disclosed as delivering texts, but Twilio Verify sends the signup OTP,
  which is a different purpose for the same vendor. The entry now says so. Shipping a new flow
  means re-reading the privacy policy, not only the terms.

- **A site-wide stale-vendor audit found a public page contradicting the live pricing copy.**
  `Ozzily Landing.dc.html` was a frozen duplicate of the landing page from the very first
  `Add files via upload` commit -- its only commit, against 13 later commits to `index.html` --
  and because `vercel.json` sets `outputDirectory: "."`, **every file in the repo is publicly
  served**. It answered 200 at `/Ozzily%20Landing.dc.html` carrying the pre-fix
  `$29/mo. Cancel by text` with no tax disclosure, with no `robots.txt` to keep crawlers off it.
  Deleted. **Rule: in a repo served from its own root, an orphan file is a live URL.** Check
  `git log --oneline -- <file>` before assuming a stray export is harmless: one upload commit
  and no edits is the signature of an abandoned duplicate.
- **Both legal pages said "Last updated: October 2026" after a material November change.** The
  merchant-of-record disclosure, the tax-inclusive prices and the Stripe-to-Paddle processor
  correction all landed on 2026-11-03 without the date moving. A stale date on a changed legal
  document is its own misrepresentation. Bump it in the same commit as any substantive edit.
- **Separate the historical references from the stale ones before "fixing" either.** The sweep
  still reports Stripe, OpenAI, GPT-4o, Framer, Razorpay, ProteinPolice and the dead
  `+1 415 980 6160` in `CLAUDE.md` and `ROADMAP.md`, and every one of those is correct: they sit
  in "previously called", "rejected", the PRD reconciliation table's *old* column, or a dated log
  entry. Deleting them would destroy the decision record. The test is not whether a vendor name
  appears, it is **whether the sentence asserts present tense.** Only four did, all in
  `CLAUDE.md`'s own build-state section -- which claimed GPT-4o and "Stripe (setup pending)"
  while the same file 350 lines later said to stay on Claude Sonnet 5 and documented the Paddle
  build. My own operating context was the most out-of-date document in the repo.
- **`CLAUDE.md` was corrupted: a block had been pasted inside a fenced code block.** The
  "How Pankaj wants this worked" and "Secrets" sections appeared **twice**, the second copy
  spliced into the middle of the real-SID query in the webhook-test learning, which split
  `'^SM[0-9a-f]{32}$') as real_sids` across 17 intervening lines and silently ate the `$'`
  (an unquoted heredoc append is the likely culprit -- this is why appends to this file go
  through a quoted heredoc or Python, never a bare `>>` with `$`). Both the duplicate and the
  broken query are fixed; fences verified balanced at 18, nine pairs. **Check `grep -n '^## '`
  for repeated headings after any append**, and prefer `io.open(..., newline='')` + an asserted
  `replace()` over appending blind.
- **`.image-slots.state.json` is a live dependency, not build cruft.** 318KB of base64 webp at
  the repo root looks deletable; `image-slot.js` loads it by that exact basename to persist the
  mascot images across reloads, and its four slot ids match `index.html`. Verified it holds no
  credentials (the `eyJ`-looking hits were case-insensitive matches inside the image bytes, not
  JWTs -- a real one needs exact case and three dot-separated segments). Confirm what loads a
  file before calling it cruft.

- **Do not `Disallow` a page whose `noindex` you are relying on.** `pay.html` already carries
  `<meta name="robots" content="noindex, nofollow">`, and the obvious instinct was to also
  disallow `/pay` in `robots.txt`. That combination is self-defeating: a disallowed URL is never
  fetched, so the crawler never reads the `noindex`, and the bare URL can still be indexed by
  reference from inbound links. Allowing the fetch is what makes the `noindex` effective.
  `robots.txt` therefore allows everything and the exclusion lives in the page. Same reason
  `.image-slots.state.json` is left crawlable: it carries the mascot images the landing page
  renders, and blocking a needed subresource degrades how renderers see the page.
- **A sitemap must list URLs the server actually serves, which is not the same as the files.**
  `/terms` and `/privacy` return **404** -- only `/pay` and `/login` have `vercel.json`
  rewrites -- so the sitemap lists `/terms.html` and `/privacy.html`. Meanwhile `/login` *and*
  `/login.html`, and `/` *and* `/index.html`, all return 200, so publishing a sitemap without
  canonicals would have advertised one of each duplicate pair while leaving the other equally
  indexable. Added `rel="canonical"` to all four indexable pages, pointing at the clean URL
  (`/login`, not `/login.html`). **Curl every path before putting it in a sitemap** -- priority
  and changefreq are ignored by Google and were left out, but `lastmod` is used, so it is taken
  from `git log -1 --format=%cs` per file rather than invented.
- **`index.html` was missing `lang="en"` while all four other pages had it.** WCAG 3.1.1, on the
  one page that matters most, in a project whose notes claim the landing page is
  accessibility-hardened to AA. It surfaced only because adding the canonical put me in the
  `<html>` tag of every page at once, which is the general lesson: a sweep that touches the same
  construct across every file is the cheapest time to spot the file that differs.

- **Search Console: property created, verification deferred (2026-11-03).** `robots.txt` and
  `sitemap.xml` are live, and that is the part that actually matters -- Google discovers a
  sitemap from the `Sitemap:` line in `robots.txt` on its own, so **submission is not required
  for indexing**. What Search Console adds is *reporting*: which URLs are indexed, which were
  excluded and why. Useful, not blocking.
  State to resume from, on `kiwi.furnishings@gmail.com`:
  - A **URL-prefix** property `https://ozzily.com/` exists and is **unverified**. The welcome
    screen shows "Already started? Finish verification", so it resumes in one click.
  - Verification file Google issued: **`googled3f9b48761e7a854.html`**, whose body is the single
    line `google-site-verification: googled3f9b48761e7a854.html`. Not a secret -- it is designed
    to be served publicly, and it only proves ownership when served *from ozzily.com*, which
    nobody else can do. Drop it at the repo root (`outputDirectory: "."` serves it), push, then
    click VERIFY, then submit `sitemap.xml`.
  - **A domain property (`sc-domain:ozzily.com`) was not an option for me.** It needs a DNS TXT
    record, and `get_domain_config` shows nameservers `dns1/dns2.registrar-servers.com` with
    `serviceType: "external"` -- DNS is at **Namecheap**, not Vercel, so the Vercel DNS tools
    cannot reach it. A domain property would cover www, http and all subdomains rather than just
    the apex; it needs a Namecheap TXT record. URL-prefix on the apex is adequate here only
    because www 308-redirects to apex, so no content lives anywhere else.

- **Paddle was NOT live: the production checkout was running sandbox (found 2026-11-03).**
  `/pay` on ozzily.com served `PADDLE_ENV = "sandbox"` with a `test_` client token and sandbox
  `pri_...` ids. **A sandbox checkout on the live domain is the dangerous failure mode**, not an
  inert one: it renders, it completes, it takes no money, and the customer believes they have
  paid. The existing guard only caught an unfilled `PASTE_` placeholder, which a real sandbox
  token sails straight past -- a guard against the placeholder is not a guard against the wrong
  *environment*. Config is now a sandbox/production pair selected on `location.hostname`, so the
  sandbox token cannot load on the apex by construction, and the guard refuses on an empty
  production block. Verified by extracting the real block from the file and running it against
  four hostnames rather than retyping it: apex and www refuse, `localhost` and `*.vercel.app`
  still open sandbox so preview stays testable. Confirmed live.
- **Evidence beats the dashboard when the dashboard is unreachable.** I could not sign in to
  Paddle (entering credentials is off-limits), but the question "is Paddle set up" was already
  answered conclusively by the system: sandbox token on prod, **0 rows in `payments`**, 0
  `preferred_plan`, 0 `billing` rows in `scheduled_messages`, and **no billing scenario in Make
  at all** -- `scenarios_list` shows only AI Brain and Daily Check-ins active, with Signup and
  Login correctly inactive. Scenario 4 was never built, so nothing calls `get_billing_due()`.
  Don't block on an inaccessible console when the integration's own state is readable.
- **Do not build-and-activate the billing beat before production Paddle exists.** The day-4 SMS
  is easy to build and would have been actively harmful: it would text real users a link to a
  sandbox checkout. The sequencing is production prices and token first, then the scenario.
- **`scheduled_messages` has no `kind` column -- it is `message_kind`.** Cost one failed query;
  noted because the billing beat work will touch this table and `mark_checkin_delivered()`
  keys off that column. `users` has no `trial_ends_at` either.

## Read the Notion Credentials Vault first (re-learned 2026-11-03)

I diagnosed the Paddle state from the repo and the live site, and only checked the vault when
told to. The diagnosis was right, but the vault answered in one read what cost several tool
calls, and it carried facts not derivable from the code at all. **This is the second time the
"check the Builder OS first" rule has been violated in this project.** The vault is at
`Pankaj's Builder OS / Credentials Vault`.

What it holds that the repo cannot: live secret values, the Paddle seller id and account email,
the Twilio Messaging Service SID, Make connection and key ids, and the decision record with
dates. **Never copy a secret value from it into this repo** -- the repo is public. Referring to
a credential by name is fine; its value is not.

- **A2P 10DLC is FULLY APPROVED as of 2026-10-25, and only the vault knew.** All three gates are
  closed: Campaign approved and Verified, the number present in the Messaging Service sender
  pool, and the account funded. Advanced Opt-Out is on with the registered STOP/START/HELP copy,
  and the Messaging Service defers inbound to the Make URL. This file still said "Not started"
  as of 2026-10-15, which would lead a future session to believe **US outbound is still blocked
  when it is not**. The remaining blocker is only the *inbound* leg: no genuine Twilio SID has
  ever reached the AI Brain, which needs a US or Canada handset.
- **The sandbox state of Paddle is deliberate, not an accident.** The vault records
  `Environment: sandbox` with "swap for the `live_` token at launch". The hostname guard added
  on 2026-11-03 is still correct -- a sandbox checkout must never serve on the apex -- but it
  was closing a *known* gap rather than catching a mistake. Check the vault before calling
  something a defect.
- **`PADDLE_PRICE_ID_MONTHLY` and `PADDLE_PRICE_ID_ANNUAL` are optional secrets with a silent
  failure mode.** `planForPriceId()` returns null when they are unset, so `p_plan` is null and
  `users.plan` is **never labelled even after a successful payment** -- monthly and annual
  subscribers become indistinguishable. Nothing errors. Set both when the production prices
  exist, in the same change as `PADDLE_WEBHOOK_SECRET`.
- **Price ids differ per environment, so the cutover must ADD `_SANDBOX` twins, never
  overwrite the plain pair.** Decided 2026-11-04: keep `PADDLE_PRICE_ID_MONTHLY` /
  `PADDLE_PRICE_ID_ANNUAL` as the **live** values and add
  `PADDLE_PRICE_ID_MONTHLY_SANDBOX` / `PADDLE_PRICE_ID_ANNUAL_SANDBOX`, selected by the
  signature-derived `verdict.env` -- the same pattern as `PADDLE_WEBHOOK_SECRET_SANDBOX`,
  and deleted in the same cleanup. **The hazard: overwriting the plain pair with the live
  ids without adding the `_SANDBOX` variables makes every sandbox event match nothing, so
  `plan` goes null with no error anywhere** -- the identical silent shape to the unset-secret
  gap above. A comma-separated list was rejected: the environment is already known, and known
  from the *signature* rather than the payload, so a union match throws away the most
  trustworthy fact in the request and would label a live event `monthly` off a sandbox price
  id, hiding the misconfiguration that produced it. Separate variables make that case
  `plan = null`, which is visible. During the sandbox-only window the plain pair deliberately
  holds the **sandbox** ids, because deployed `planForPriceId()` is not yet environment-aware.
- **A 401 from `paddle-webhook` does not distinguish "no secret set" from "wrong signature".**
  Both fail closed, which is correct, and both look identical from outside, so only a request
  signed with the real secret settles it. **Settled for sandbox on 2026-10-29 and no probe is
  needed:** Paddle's simulated `subscription.created` returned 401, then 200 once the secret
  was corrected, and a real sandbox checkout then wrote a `payments` row. The Credentials Vault
  records this. The same ambiguity returns unresolved for **live**, which has its own
  destination and its own signing secret.
- **`PADDLE_WEBHOOK_SECRET` is a single value, so one deployment cannot verify both sandbox and
  live.** `verify()` HMACs against exactly one `SECRET`; sandbox and live are separate Paddle
  systems with separate destinations and separate secrets, so whichever one is set, the other
  environment's events all return 401. To keep sandbox testable across the cutover the function
  must accept a **list** of secrets and succeed if any matches. The secret that matched is then
  the only trustworthy environment tag available -- it is derived from the signature rather than
  from the payload -- which matters because a sandbox-signed event would otherwise write sandbox
  ids into the live `payments` table through the same `apply_payment_event()`. Keep the overlap
  to days and drop the sandbox secret once live is proven.
- **A refund will almost certainly NOT be recorded, which matters because reversing a live test
  purchase is the plan.** `apply_payment_event()` maps only `adjustment.updated` to `refunded`;
  `adjustment.created` falls to `else null`, so no `payments` row is written and the event is a
  verified no-op. Worse, `paddle-webhook` computes `isTransaction` from the `transaction.`
  prefix, so on any `adjustment.*` event `data.id` -- the adjustment id -- is passed as
  `p_provider_subscription_id`. It fails safe (no match means `ok:false`, never a
  mis-attribution) but the refund is lost. **FIXED 2026-11-05** (migration
  `20261105073039`, webhook v12) -- and the fix found three more bugs in the same path,
  none of which the original diagnosis predicted:
  - **An adjustment's totals live at `data.totals`, not `data.details.totals`**, and its
    gross field is **`total`**, not `grand_total` -- there is no `grand_total` on an
    adjustment at all. Either mistake alone records the refund as **0**: a row that looks
    successfully written and states something false. My first attempt at the fix still
    read `grand_total` and was caught only by a test asserting the amount, not by review.
  - **An adjustment payload carries no `custom_data`**, so `custom_data.user_id` -- the
    primary resolution path -- is simply absent on every refund. Resolution falls entirely
    to `provider_subscription_id`/`provider_customer_id` on the `users` row, which means
    the purchase webhook writing those ids back is **load-bearing for refunds**. Clearing
    them on a test user makes a subsequent refund resolve nobody.
  - **Mapping must key on the adjustment's own `status` and `action`, never the event
    name.** `adjustment.created` fires while a refund is still `pending_approval`, and that
    status can go on to `rejected`, so mapping the event name (the obvious reading of this
    gap) records refunds that never happened -- the same class of error as a status written
    by the step that *starts* an action. Only `approved` writes a row. The three `*_reverse`
    actions move money back **towards** us and are declined explicitly, since recording one
    as a refund would double-count a loss.
  Also: `adjustment.created` and `adjustment.updated` for one adjustment carry **different
  event ids**, so `provider_event_id` cannot see a refund is already recorded -- hence
  `payments.provider_adjustment_id` UNIQUE as a second idempotency key, with the insert
  wrapped so a concurrent duplicate hits the constraint instead of double-counting. And
  `chargeback` is now its own `payments.status` value rather than being collapsed into
  `refunded`, which would misreport a dispute as a voluntary refund.
- **Nothing configured in Paddle sandbox carries over to live.** The live account is a separate
  system, so every sandbox setting has to be made again there: both prices **tax inclusive**,
  `ozzily.com/pay` as the **default payment link**, **no trial** on either price, the
  notification destination (with its own signing secret, and the same event list), and the
  event subscriptions. A setting that exists only in sandbox reads as "already done" in the
  dashboard you are not looking at.
  **The event list is 12, not 10, as of 2026-11-06.** The sandbox destination was not
  subscribed to `adjustment.created` or `adjustment.updated` at all, so no refund event
  could ever have arrived however correct the receiver was -- the subscription list is a
  third independent gate after the signing secret and the code, and a refund fix is
  untestable without it. Both were added to sandbox on 2026-11-06 and **must be added to
  the live destination too**; a receiver that handles an event it is not sent is
  indistinguishable from a broken one.
- **A refund row REPEATS the original's tax, fee and earnings, and the sign lives in
  `status`, not in the number. Summing any money column without the sign double-counts.**
  Paddle's adjustment carries its own `totals`, and for a full refund those mirror the
  original transaction -- so the refunded row stores tax 442, fee 195, earnings 2263
  exactly as the purchase did. They are the amounts being *reversed*, stored positive.
  Measured on the one purchase-and-full-refund pair, which nets to zero:
  `sum(amount_cents)` = **5800** and `sum(earnings_cents)` = **4526**, both pure fiction.
  Every revenue query must sign by status and exclude the non-movements:
  ```sql
  sum(case when status = 'succeeded'                     then  earnings_cents
           when status in ('refunded','chargeback')      then -earnings_cents
           else 0 end)  -- 'failed' and 'pending' moved no money; never add them
  ```
  Verified: that form returns 0 for gross, earnings and fee on the same two rows. Pair a
  refund to its purchase on `provider_transaction_id`, which is identical on both;
  `provider_adjustment_id` is non-null only on the refund. A partial refund works the
  same way, because its adjustment totals are the partial amounts.
  **Open question, do not assume either way: whether Paddle actually returns its 195c
  fee on a refund.** The adjustment *reports* a fee, but reporting it is not the same as
  crediting it. If Paddle keeps the fee, netting it to zero overstates recovery and the
  true cost of a refunded sale is the fee. Settle it against a live payout statement,
  not against this column.
- **A live refund for a user whose provider ids are null returns 500 and retries
  forever-until-exhausted, and retrying can never fix it.** An adjustment carries no
  `custom_data`, so `user_id` is absent and resolution falls to
  `provider_subscription_id` then `provider_customer_id` on the `users` row. If both are
  null, `apply_payment_event` returns `ok:false`, the webhook logs
  `outcome: live_event_refused` and answers 500 so Paddle retries and the event lands in
  the destination's failed-event list rather than vanishing. That is the design working:
  it makes the event visible. But nothing will repair itself, because the missing ids are
  on our row, so a human must act:
  1. Find the user from the original purchase: `select user_id from public.payments where
     provider_transaction_id = '<the adjustment's transaction_id>'`. That row resolved at
     purchase time via `custom_data.user_id`, so it is the reliable link.
  2. Backfill `users.provider_subscription_id` / `provider_customer_id` from the Paddle
     objects.
  3. Replay the event from the Paddle destination's failed-event list. It now resolves.
  4. If there is no `payments` row either, the purchase was never recorded: match the
     Paddle customer to `users.phone` by hand in the dashboard, backfill, then replay.
  **The durable fix is a fourth resolution fallback** -- resolve by
  `payments.provider_transaction_id` when the users row has no ids -- which would make any
  refund resolvable whenever its purchase was recorded. Not built; recommended before live.
  **This makes the purchase webhook writing those ids back load-bearing for refunds**, so
  a purchase that fails to write them silently arms this failure for every later refund.
- **A live API key is not needed at all now that cancellation is a manual Paddle action.** The
  reason this bullet once gave -- "the site promises cancel by text, which needs write access to
  subscriptions" -- expired on 2026-11-09, when every page was changed to name
  `hello@ozzily.com` as the cancellation path. Cancelling is done by hand in the Paddle
  dashboard (see the runbook below), which needs no key. So the key stays uncreated for a
  stronger reason than before: nothing uses it. Revisit only if self-serve cancellation is
  automated, and then scope the key to subscription writes.
- **Make hook 2997965 is reserved for the OUTBOUND "payment received" SMS and is idle by
  design.** Paddle does not point at it and must not: signature verification needs raw bytes
  that Make destroys by parsing. Do not "fix" the idle hook.
- **Doc drift found by reconciling the vault against the snapshot:** the vault says 6 tables and
  20 functions; the committed snapshot has **7 tables** (`verification_attempts`) and **25
  functions**, and lists three Edge Functions where the vault names two (`signup-verify` is
  missing). The vault also still lists the Signup and Login scenarios as Active when both are
  now off, and carries capturing `details.totals.tax/fee/earnings` as an open item although it
  shipped on 2026-11-02. **Mirroring is a two-way obligation**: this file was stale on A2P, the
  vault is stale on the schema. Reconcile both whenever either changes.

- **"Text cancel" pointed customers at a channel that silently swallowed the request.**
  `CANCEL` is one of the registered A2P STOP keywords -- the set is `STOP, STOPALL,
  UNSUBSCRIBE, CANCEL, END, QUIT` in `docs/a2p-campaign-registration.md` -- so Twilio's
  opt-out handler intercepts it *before* the inbound webhook fires. The AI Brain never sees
  the message, nobody is notified, and the subscription keeps billing. So the old copy did
  not merely name the wrong channel: it named one that absorbs the request while the card
  keeps being charged, which is strictly worse than naming no channel at all. It was live on
  four pages (`index.html`, `terms.html`, `privacy.html` and `pay.html` -- the last being the
  checkout page itself) and was fixed on 2026-11-09, when every page was changed to name
  `hello@ozzily.com`. **Rule: before instructing a customer to text a keyword, check it is not
  a carrier opt-out keyword.** The overlap is invisible in testing because the message is
  swallowed upstream of everything we instrument -- there is no error, no row and no log.
  Note the registered sentence "Reply STOP to cancel, HELP for help" is still correct and must
  not be edited: in A2P convention "cancel" means cancel the *messages*, which is what STOP
  does. The falsehood was only ever the implication that it stops the money.
- **To test a prompt change without texting anyone, build a throwaway Make scenario with no
  Twilio module.** The Anthropic key is on no developer machine and is **not** a Supabase
  secret either -- it lives in Make's HTTP connection (auth id 222879) -- so a Supabase Edge
  Function probe dies with `ANTHROPIC_API_KEY is not set`, and the only path to the model runs
  through Make, where both production scenarios end in `twilio:SendSMS`. What works: webhook
  -> `supabase:makeAnApiCall` on `/rest/v1/rpc/ai_brain_system_prompt` -> `http` module reusing
  connection 222879 -> write the reply into a temp table, because the Make API cannot show
  per-module I/O. Teach the hook first (`hooks_learn_start`, POST one representative payload,
  `hooks_learn_stop`) or every `{{1.field}}` resolves empty. Delete the scenario, the hook and
  the table afterwards. Used on 2026-11-09 to confirm the billing line sends customers to
  `hello@ozzily.com` without promising a refund. Two traps worth knowing: the **Supabase MCP
  server cannot delete an Edge Function, only replace it**, so a probe deployed there must be
  tombstoned and removed by hand (`supabase functions delete <name>`); and a probe needs its
  own authentication, which can be a single-use random token planted in a temp table and read
  by the function with its own service key -- that way no long-lived credential is ever handled
  outside the project.

## Support runbook: refunds and cancellations (2026-11-09)

`refunds.html` promises a full refund on request within 30 days of a charge, and names email as
the only route. Nothing is automated, so the whole promise rests on this sequence being followed
by hand. **Do the steps in this order** -- the order is not cosmetic.

1. **Refund the transaction in Paddle.** Find the transaction and issue a full refund. **On the
   live account a refund is not immediate: it is created `pending_approval` and Paddle has to
   approve it.** Sandbox approves instantly, so the live behaviour will look broken by
   comparison -- it is not. Until it is approved, no money has moved and
   `apply_payment_event()` deliberately records nothing, because it maps on the adjustment's
   **status**, not on the event name. A `payments` row with `status = 'refunded'` appears only
   once Paddle flips the adjustment to `approved`.
2. **Then cancel the subscription in Paddle, as a separate action.** A refund does **not** cancel
   the subscription. Refunding and stopping there leaves the customer refunded and still
   subscribed, so the next billing cycle charges them again -- the exact outcome the policy
   promises to prevent. `refunds.html` states "A refund also ends your subscription", which is
   a promise about what *we* do, not a description of what Paddle does on its own.
3. **Then confirm by email.** Reply on the customer's own thread. There is no email address on
   the `users` row -- signup collects only a phone number -- so that inbound thread is the only
   way to reach them in writing. Say what was refunded and that the subscription is cancelled.

Notes that decide whether any of this gets recorded:

- **The refund only lands in `payments` if the live notification destination subscribes to
  `adjustment.created` AND `adjustment.updated`.** Both were added to sandbox on 2026-11-06 and
  are part of the 12-event live list. Without them the refund is invisible to our side forever;
  Paddle will not backfill.
- **If the user's `provider_customer_id` and `provider_subscription_id` are null**, the webhook
  cannot attribute the event and returns `ok:false` by design. The recovery procedure is the one
  recorded above under the live-refund entry -- resolve the user by hand and set the ids before
  re-sending the event from Paddle.
- **Do not reach for a Paddle API key to do any of this.** All three steps are dashboard actions.

**Cancel by email is the launch path, deliberately, and it is a manual one.** Every page now
names `hello@ozzily.com`; nothing self-serve exists. That is an accepted launch cost, not an
oversight -- it is a handful of emails at this volume, and it beats shipping an unverified
automated path. The scaling answer is the **Paddle customer portal**, a hosted page where the
customer cancels or updates their card themselves. It is **to be planned, not built**, and it
is blocked on one thing that is not engineering: **legal advice on auto-renewal rules**. US
state automatic-renewal laws (California's ARL is the strictest) generally require clear
pre-purchase disclosure of the renewal, and several require an easy online cancellation
mechanism for a subscription bought online -- which an email-only path arguably is not. Ozzily
sells `$29/month` and `$249/year` recurring subscriptions to US consumers, so this applies to
us. Two consequences:

- **Ask the CA/counsel whether email-only cancellation is sufficient for US consumers before
  launch**, in the same conversation as the GST/FEMA export-of-services question. If it is not,
  the portal stops being a scaling nicety and becomes a launch blocker.
- **`terms.html` and `refunds.html` must already say the plan renews automatically until
  cancelled** -- they do, as of 2026-11-09. Do not let that wording be trimmed for brevity; the
  disclosure is the part the statutes actually mandate.

Do not build the portal before that advice lands: a self-serve cancel button that bypasses the
manual runbook also bypasses step 2 above, and a customer who cancels in the portal after a
refund was issued is a different state from one who was cancelled by hand.
