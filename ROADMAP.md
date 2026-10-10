# Ozzily — Product Roadmap & Reconciled Plan

**Owner:** Pankaj Grover (Massive Impact Media Private Limited)
**Maintained by:** Claude Code
**Last updated:** 2026-10-10
**Supersedes:** `ProteinPolice_PRD.md` / `ProteinPolice_Report_PRD.docx` (v1.0, Aug 11 2026) — kept only as historical reference. Where this file and the old PRD disagree, **this file wins.**

> This is the living execution plan. It reconciles the original ProteinPolice PRD with every decision made since (name, tone, stack), folds in 2026 research, and sets the milestone order. It is intentionally opinionated.

> ### ⛔ CURRENT BLOCKER (2026-10-10): inbound is unprovable from India — a US/Canada sender is required
> **Settled with evidence from Twilio's own Monitor → Logs on 2026-10-10.** Every row in the message log is `Outbound API`. There is **not one inbound message, ever**. Twilio never received the test texts, so the webhook was never the cause — it is correctly configured, and no webhook change can fix this.
> Three facts from the logs:
> 1. **Outbound to India works.** The AI Brain's reply (`SMd4f7163278f04982593efe50b370446b`) was *Delivered* to +91 9255435752 via the carrier network. So Ozzily can text Pankaj; he just cannot text back.
> 2. **Inbound from +91 never reaches Twilio.** Consistent with Twilio's statement that a +1 number ["may be able to receive some incoming SMS messages from numbers outside of the +1 dialing code. However, this is not guaranteed to work in all cases, or at all times."](https://help.twilio.com/articles/360045489294) For this carrier pair it simply does not.
> 3. **Twilio substitutes the sender ID on international delivery.** The 2026-10-09 messages went out from **+590391…**, not +1 415 969 2088 — exactly the behaviour Twilio warns about for international SMS. A reply therefore goes to a number Ozzily does not own, which is an independent reason inbound can never work from India.
> **Consequence:** the inbound half of the product — the AI Brain, the entire conversational loop — cannot be verified from Pankaj's own phone by any configuration change. It needs a **US/Canada sender**: a friend with a US number, a second US Twilio number messaging the main one, or the first US beta tester. Everything downstream of the webhook is proven and green; only the first hop is untested.

> ### ✅ RESOLVED (2026-10-09): Make.com active-scenario cap
> Confirmed via the Make API: the org is on **Pro** — `productName: "Pro"`, 10,000 operations/month (387 used this cycle), `activeScenarios: 3`, and **no active-scenario limit in the license**. The old "2 active scenarios" ceiling was the Free plan. Signup Flow, AI Brain and Daily Check-ins all run concurrently today, and more can be added; the practical bound is the operations budget, not a scenario count. Login (id 6333754) is still inactive but is also `isinvalid: true` — it needs repair, not just reactivating.

---

## 1. What Ozzily is (one paragraph)

Ozzily is an **SMS-first, no-app AI companion for GLP-1 users** (Ozempic, Wegovy, Mounjaro, Zepbound). It texts users every day to protect **lean muscle mass** — driving adequate protein, resistance training, and hydration — so the weight they lose on the medication is fat, not muscle. The voice is a **warm companion** (Tomo.ai-style), never clinical, never a "police." The phone number is the identity; there is no app or dashboard. $29/mo or $249/yr, 3-day free trial, cancel by text.

**Hard rule (non-negotiable):** Ozzily never gives medical advice or discusses medication/dosing. It always defers to the user's prescriber.

---

## 2. What changed from the original PRD — and what I'm deprecating

The Aug-11 PRD was a strong v1.0, but it was written for a different product (ProteinPolice, aggressive tone, OpenAI/Framer stack). Reconciliation:

| Dimension | Old PRD | Now (authoritative) |
|---|---|---|
| Name | ProteinPolice | **Ozzily** |
| Voice | Aggressive, "demand proof," "police" | **Warm companion, supportive** |
| Landing | Framer + Tally/Typeform | Claude Design → GitHub → Vercel (native form) |
| AI brain | OpenAI GPT-4o | **Anthropic Claude Sonnet** (Make HTTP module) |
| Orchestration | Voiceflow + Make | **Make.com only** |
| Protein target | Flat 100g default | **Body-weight-based 1.2–2.0 g/kg/day** (see §4) |
| Tables | 5 | 6 (added `scheduled_messages`) |
| Twilio | +1 415 980 6160 (personal trial) | **+1 415 969 2088**, Massive Impact Media account |

### Deprecated / rewritten features (removed from scope)

These PRD features are **off-brand or non-compliant** with warm-companion Ozzily + the no-medical-advice rule. Cutting or reframing:

- **CUT — "Commitment contracts" (AI charges you if you fail; donates to a charity you hate).** Pure punishment/loss-aversion. Directly contradicts the companion positioning. Not building.
- **REFRAME — Side-effect "affiliate" flows** (auto-send Magnesium Citrate / supplement links for constipation, nausea). Selling supplements as a response to symptoms edges into medical advice + conflicted incentives. Reframe to: acknowledge the symptom warmly, give general lifestyle comfort (hydration, smaller meals), and **nudge to the prescriber** — no product links tied to symptoms. Affiliate revenue, if ever pursued, stays away from anything symptom-triggered.
- **REWRITE — All aggressive SMS templates** ("demand," "I'm sending you…"). The landing page already models the correct voice; every template inherits that tone.

---

## 3. Market & positioning (research-grounded, Sep 2026)

- **Market is large and compounding.** ~10M US GLP-1 users in 2025; the share of US adults on GLP-1s for weight loss more than doubled to **12.4% by June 2026**; ~25M projected by 2030. The thesis is stronger than the PRD assumed.
- **Muscle-loss problem is real and addressable.** GLP-1s reduce fat more than lean mass, but lean-mass loss is meaningful without intervention. 2025 evidence: **protein 1.2–2.0 g/kg/day + resistance training** preserves muscle (a 200-adult cohort: −13% weight, only −3% muscle).
- **The competitive claim has changed.** App-based competitors now cover this space: **GLP AI, Noom GLP-1 Companion, Shotsy, MeAgain, WeightWatchers**. The PRD's "no one combines these features" is no longer true.
- **Ozzily's real moat (sharpened positioning):**
  1. **SMS-first, zero-app** — ~98% SMS open rate vs chronic app fatigue. Competitors are all apps.
  2. **Proactive daily texts** — Ozzily initiates; trackers wait to be opened.
  3. **Warm companion voice** — differentiated from both clinical telehealth and nagging trackers.
  4. **GLP-1-specific muscle focus** with a science-based, per-body-weight protein target.
- **Engagement is the value driver.** Digital coaching + daily logging is associated with materially better weight-loss outcomes (up to ~53% better at month 4 in digital-therapeutic data). This is why **proactive check-ins (not vision) are the highest-leverage build** (see §6).

Sources: ACE Fitness (Jun 2025), MDPI Metabolites 16(6):364, Forbes Health GLP-1 Statistics 2026, JPMorgan 2026 obesity-drug outlook, Twilio A2P 10DLC guidance, Medscape GLP-1 apps 2026.

---

## 4. Research-driven product upgrades (new, decided)

1. **Body-weight-based protein target.** Onboarding captures weight (lb/kg); target = **1.6 g/kg/day default** (mid-range of 1.2–2.0), adjustable. Falls back to 100–120g if weight is declined. This is more effective *and* a differentiator vs a flat number. Requires: onboarding question + a `weight_kg` (or `weight_lb`) column + target-calc logic in the AI prompt.
2. **Resistance-training emphasis.** Movement guidance centers **multi-joint resistance work 3–4×/week** (squat/hinge/press), not generic "exercise." Cardio is secondary for muscle preservation.
3. **Hydration stays**, framed as comfort/side-effect support, never medical.
4. **Consent-grade onboarding** (see §7): the welcome SMS doubles as the compliant confirmation message.
5. **Weekly "wins" summary** — a Sunday recap (streak, protein average, lifts) as a retention beat. Cheap, high-affinity.

---

## 5. Complete structural workflow

### 5a. Current (verified working, Sep 19 2026)

```
ACQUISITION
  ozzily.com landing → phone form
      └─POST→ Make webhook (hook 2778543)  { phone, source, plan, page_url }

SCENARIO 1 · "Ozzily Signup Flow"          [webhook → Supabase → Twilio]
  webhook → create user (status=trial) → welcome SMS (asks medication 1–4)

SCENARIO 2 · "Ozzily AI Brain – Inbound SMS"   [Twilio in → … → Twilio out]
  Twilio inbound webhook
    → Supabase find user
    → Supabase RPC get_recent_transcript   (memory as flat string)
    → Supabase RPC daily protein total
    → build JSON → HTTP → Claude Sonnet
    → parse { reply, user_updates, message_kind }
    → Supabase PATCH users (user_updates verbatim)
    → Supabase log message
    → Twilio SendSMS reply
  Covers: onboarding state machine (+ numeric shorthand), free-form chat, protein math

DATA MODEL (Supabase, RLS locked, service_role only)
  users · messages · streaks · payments · affiliate_clicks · scheduled_messages
  fns: get_recent_transcript · daily-protein-sum · onboarded_at trigger
```

### 5b. Target (what "done for beta" looks like)

Everything above **plus**:

```
SCENARIO 3 · "Ozzily Daily Check-ins"      [scheduler → Supabase → Twilio]   ← NOT BUILT
  cron (per intensity + wake_time) → find due users → warm proactive SMS
  beats: morning goal-set · midday protein nudge · evening lift check · night recap · weekly wins

SCENARIO 2 (extended) · Vision              ← NOT BUILT (2.3)
  inbound MMS media_url → same Claude call + image block → protein-from-photo

SCENARIO 4 · "Ozzily Billing"              [Stripe ↔ Supabase ↔ Twilio]      ← NOT BUILT
  day-3 trial-end SMS w/ Stripe link · webhook activates · dunning · cancel-by-text
```

**The structural gap that matters most:** today Ozzily is almost entirely **reactive** (answers inbound, sends one welcome). The product it sells — *"texts you every day"* — is **proactive**, and that (Scenario 3) is not built. `scheduled_messages` exists; the cron doesn't.

---

## 6. Milestone plan (milestone-gated, one deliverable at a time)

Order optimized for "shortest path to a compliant, real beta," which is **not** the PRD's order.

### Milestone A — Unblock sending (compliance) 🚦
- A2P 10DLC **Campaign** registration submitted & approved (Brand already submitted).
- Landing consent upgraded to the 2026 standard (§7).
- Welcome SMS becomes a compliant confirmation message (frequency + STOP/HELP + rates).
- **Done when:** carrier-approved campaign + consent artifacts match the opt-in URL.
- **Why first:** carriers block 100% of unregistered/non-compliant A2P. Nothing scales without this.

### Milestone B — Make Ozzily proactive (Scenario 3) ⭐
- Build the daily check-in cron in Make against `scheduled_messages` + `wake_time` + `intensity_level`.
- Beats: morning / midday / evening / night recap, respecting chill/steady/intense.
- Warm templates, per-user protein target injected.
- **Done when:** a test user receives correctly-timed daily texts end-to-end for 2 days.
- **Why second:** this is the actual product. Highest engagement leverage per the research.

### Milestone C — Vision / photo verification (Session 2.3) — ⚠️ AWAITING ONE MMS TEST
- Extend Scenario 2's Claude call with an image block for inbound MMS (media_url already logged).
- Protein-from-photo + workout-photo confirmation, streak update.
- **Done when:** a meal photo returns a protein estimate and updates the daily total live.
- **Why third:** delighter, not a gate. Claude is already multimodal — low integration cost, but B moves the metric more.

**Shipped:**
- Request construction moved into SQL: `ai_brain_system_prompt()` + `build_ai_request(p_phone, p_body, p_media_url, p_media_type, p_media_b64)`. One source of truth for the 7.6k-char prompt instead of duplicating it per Make branch; the AI Brain holds at 9 operations.
- Vision itself is **proven working** — a hardcoded base64 image came back correctly described by Sonnet 5.
- A `## Photos` section was added to the system prompt.
- Graceful degradation: when a photo arrives but its bytes are unavailable, the prompt carries an explicit marker telling Ozzily *not* to claim it saw the image, and to warmly ask the user to describe it. Photos therefore never error — they just are not read yet.
- `supabase/functions/ai-request/` written, deployed and locked to the service role. It fetches Twilio media, base64-encodes it and forwards to the RPC. Host-allowlisted to Twilio, 3.5MB cap, optional Twilio Basic-auth retry.

**✅ Transport solved.** Anthropic rejects `source.type: "url"`, so image bytes must be fetched and encoded; the `ai-request` edge function does that and the AI Brain calls it through the ordinary Supabase connection at **9 operations** — no Router, no extra op. Verified end-to-end on text 2026-10-09.

**⛔ Cannot be finished yet, for two reasons** (risks 1 and 3): the Twilio inbound webhook is not wired, so no photo reaches the pipeline at all; and Twilio supports MMS only in the US/Canada, so the +91 test number can never deliver one. Needs the webhook fixed **and** a US/Canada handset. Until then photos take the graceful-degradation path rather than being read — which is safe, just not the feature.

### Milestone D — Billing & trial lifecycle (Sessions 3.1/3.2, Scenario 4)
- Stripe subscription ($29/mo, $249/yr), day-3 trial-end SMS w/ link, webhook activation, dunning, cancel-by-text.
- Wire the landing `plan` field through Scenario 1 → Supabase so plan intent is captured at signup.
- **Done when:** a trial converts to paid and a cancel-by-text stops billing, both verified.

### Milestone E — Beta (Week 4)
- End-to-end stress test, recruit 10–20 users (Reddit r/ozempic etc.), soft launch, lightweight analytics.

### Cross-cutting cleanups (do alongside, small)
- Warm-rewrite all inherited PRD templates.
- Add `weight_kg`/`weight_lb` + protein-target logic (§4).
- Instrument North-Star + activation metrics (§9).

---

## 7. Compliance (A2P 10DLC / TCPA, 2026 standard)

This is a live gate, not paperwork. 2026 requirements:

- **Dedicated, unchecked, optional SMS-consent checkbox** at the point the number is entered — not bundled, not pre-checked, not required to submit. *(Upgrade from the current disclosure-text; disclosure text is the weaker option under the Jan-27-2026 FCC one-to-one rule.)*
- **Opt-in disclosure + privacy statement** visible near the submit control (already present: consent line + Terms/Privacy links).
- **Immediate confirmation SMS** on opt-in: identity + message frequency + "Msg & data rates may apply" + "Reply HELP for help, STOP to cancel."
- **STOP/HELP** handled by the SMS flow; **opt-out instructions at least once per month**.
- Legal entity (Massive Impact Media Private Limited) disclosed on site ✅; Privacy + Terms live ✅.

**Decision:** move the landing form to a real checkbox before beta. Until A2P Campaign is approved, keep sends to test numbers only.

---

## 8. Open risks

1. **⛔ No viable inbound test path (BLOCKER)** — see the callout at the top. The Twilio webhook is correctly configured; the obstacle is that the only test handset is a +91 number, which Twilio does not guarantee can reach a +1 long code at all, and which can never send MMS to one. Needs a US/Canada sender (friend, a second Twilio number, or the first beta tester) before any inbound claim can be trusted.
2. **A2P campaign approval latency** — external dependency; start now, it blocks everything downstream.
3. **MMS is US/Canada only, so photos cannot be tested from an Indian number** — Twilio documents that it supports MMS only in the US and Canada, and error [`30011`](https://www.twilio.com/docs/api/errors/30011) covers the inbound case explicitly ("your Twilio phone number was sent an MMS in a region where Twilio does not support incoming MMS"). Testing vision therefore needs a **US/Canada handset**, not the +91 test number. Recruit one US tester before calling Milestone C done. Ozzily's graceful-degradation path already covers this safely in the meantime.
4. **AI giving medical-adjacent advice** — mitigated by hard prompt guardrails + prescriber-deferral; audit the system prompt each change.
5. **Cost per active user** — proactive daily texts multiply Twilio + Claude spend; watch COGS as volume grows (PRD modeled $5–9/user/mo). Make itself is now bounded by 10,000 ops/month on Pro; the AI Brain costs 9 ops per inbound message, so ~1,100 messages/month before that ceiling binds.
6. **Competitive parity** — app incumbents (Noom, GLP AI) are well-funded; Ozzily wins on channel + voice, not feature checklists. Don't drift into "app with more features."
7. **US-only pricing story** — international signups break the unit economics; keep US-first (landing already validates this way).
8. **Supabase free tier pauses** — the Signup Flow failed on 2026-10-08 with `521` / `ENOTFOUND` against `/rest/v1/users`, which is the project being unavailable, not a logic bug. A paused project silently kills every scenario. Upgrade to Pro before beta.
9. ~~**Signup Flow can fire with no phone number**~~ — **resolved 2026-10-09.** Module 2 now filters on `{{1.phone}}` matching `^\+[1-9][0-9]{7,14}$`, and modules 3–4 have `onerror → Ignore`. An empty payload exits at 1 operation with status 1. The `21604` errors on 2026-09-24 and 2026-10-08 both predate that edit.
10. **Twilio media auth for MMS is unverified** — the `ai-request` function fetches Twilio media unauthenticated and retries with Basic auth only if `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` are set as function secrets. Unknown until a real MMS arrives (see risk 3). If photos come back as the "couldn't view it" fallback, set those two secrets.
11. ~~**Login scenario is invalid**~~ — **resolved 2026-10-09.** Root cause was the webhook having no learned data structure, so `{{1.phone}}` resolved to nothing and SendSMS threw `21604`, which tripped `maxErrors` and jammed the hook queue. Fixed by running learn mode with a representative payload, then hardening: a "has a phone number" filter on module 2 and `onerror → Ignore` on the Supabase lookup. Verified — real payload sends (3 ops, status 1), empty payload exits cleanly (1 op, status 1). Active.
12. **Intermittent Supabase `401 JWT issued at future` from Make** — seen on Signup 2026-09-08 and Login 2026-10-09, two runs in the same second where one succeeded and one failed. Looks like clock skew between Make's workers and Supabase auth, not a config error. Every Supabase module in every scenario should carry `onerror → Ignore` (or a real fallback) so a transient 401 cannot trip `maxErrors` and jam a hook queue. All three live scenarios now do.
13. **Stale unparseable payloads can sit in a hook queue forever** — Login's hook still holds a 1-byte item from 2026-09-20 that Make cannot deserialize or discard. It is inert now that the scenario filters empty payloads, but it occupies a queue slot. Clear it from the Make UI if the queue ever matters.
14. **International SMS cost makes non-US users unviable — hard numbers now exist.** The 2026-10-10 log shows a single 2-segment reply to +91 costing **$0.1664** (~$0.083/segment). Four daily check-ins plus AI replies at 2–3 segments each lands around **$20–40/month for one Indian user**, against $29/mo pricing — negative margin before Claude and Make costs. US A2P 10DLC SMS is roughly an order of magnitude cheaper. This is now the strongest evidence for the existing US-only decision (risk 7); treat non-US signups as something to actively refuse, not merely discourage.
15. **Twilio account balance is low** — $11.10 as of 2026-10-10. At international rates that is a few dozen messages. Top up or enable auto-recharge before any sustained testing, and especially before beta.

**Resolved:**
- ~~Make.com active-scenario cap~~ — org is on **Pro**; no active-scenario limit. See the resolved callout at the top.
- ~~Twilio geo permissions (error `21408`)~~ — enabled. A replay to `+1608903XXXX` succeeded on 2026-09-08T10:41:31Z (status 1). Later failures on that flow were `21604`/`521`, unrelated causes. Do not re-raise this.
- ~~Vision transport gateway 403~~ — not a gateway restriction. Make's Supabase module sends the key in the `apikey` header, not `Authorization: Bearer`; the function's guard only read the latter. Fixed, and the AI Brain now calls `/functions/v1/ai-request` at 9 operations.

---

## 9. Metrics

- **North Star:** Weekly Active Users engaging with ≥5 check-ins/week.
- **Activation:** % completing onboarding (target >80%).
- **Engagement:** daily response rate (target >70%).
- **Retention:** M1 >60%, M6 >30%.
- **Revenue:** trial→paid conversion; MRR; ARPU.
- Instrument submit→signup on the landing page (currently unmeasured).

---

## 10. Changelog

- **2026-09-19** — Roadmap created. Reconciled ProteinPolice PRD → Ozzily. Added body-weight protein target, sharpened SMS-first/proactive positioning, upgraded compliance to 2026 checkbox standard, cut commitment-contracts + symptom-affiliate features, re-ordered milestones (compliance → proactive check-ins → vision → billing). Landing page changes shipped same day: SMS consent language + plan attribution.
- **2026-09-19** — Shipped the SMS consent checkbox (2026-standard gate). Built `login.html` (Tomo-style "Welcome back.", SMS-native, no consent checkbox) + added "Log in" to nav. Built + tested the **Make "Ozzily Login"** scenario (id 6333754): webhook → Supabase phone lookup → router → welcome-back vs sign-up-nudge SMS; end-to-end verified with a live SMS delivered. **Discovered the Make active-scenario cap blocker** (see §8 / top callout) — Login left inactive because both slots are used by Signup Flow + AI Brain. **Scenario inventory: 3 built (Signup, AI Brain, Login), ~2 to build (Daily Check-ins, Billing); vision is an extension of AI Brain, not a new scenario.**
- **2026-10-09** — Milestone C (vision) partially landed. Moved Anthropic request construction into Postgres (`ai_brain_system_prompt()`, `build_ai_request(...)`) so the system prompt lives in one place and the AI Brain stays at 9 ops. **Proved vision works** with a base64 image, and **proved `source.type: "url"` is rejected** by the Messages API — that, not the images, was the real cause of the 400s. Added graceful photo degradation so an unreadable photo can never break a turn. Built and deployed the `ai-request` edge function (service-role-only, Twilio host allowlist, size cap) to do the fetch-and-encode. **Transport remains blocked:** Make's Supabase module 403s on `/functions/v1/*` (risk 6). Pipeline left on the verified RPC path and re-tested green end-to-end. Security hardening alongside: pinned `search_path` on 5 functions and revoked public EXECUTE on the `set_timezone_from_phone` trigger function — security advisors are now clean apart from the intentional RLS lockdown.
- **2026-10-09 (later)** — Milestone C transport **unblocked**. The earlier "gateway-level 403 on `/functions/v1/*`" diagnosis was wrong: Make's Supabase module sends the key in the `apikey` header, not `Authorization: Bearer`, and the function's guard only read the latter. Worse, the deploy that fixed the guard landed *after* the failing test, so the retest never happened. Module 3 now calls `/functions/v1/ai-request` and the AI Brain runs green at **9 operations** — verified twice live. Also **corrected the Twilio geo-permission risk**: it was fixed on 2026-09-08 (a replay to `+1608903XXXX` succeeded, status 1); the later Signup failures were `21604` (webhook with no phone number) and Supabase `521`/`ENOTFOUND` (free-tier unavailability), now tracked as separate risks 7 and 8. Risk list renumbered — it had two entries numbered 2 — and risk 1 corrected to note that **3** scenarios are active today, not the 2 the cap was believed to allow. Vision's last mile is now a single real MMS to confirm Twilio media is fetchable.
- **2026-10-09 (end of session)** — Found the real blocker while checking a meal photo that never arrived: **the Twilio inbound webhook has never been wired to the Make hook.** Zero of 43 inbound `messages` rows carry a genuine Twilio SID; every "successful" inbound test in this repo's history was a synthetic POST at the hook URL, which only ever exercised the pipeline *downstream* of the webhook. The photo produced no Make execution and left the hook queue at 0. Promoted to the top-of-file blocker — it gates the whole product. Separately confirmed from Twilio's docs that **MMS is US/Canada only** (inbound error `30011`), so the +91 test number can never deliver a photo; vision needs a US/Canada tester. **Make.com cap resolved:** org is on Pro — 10,000 ops/month, 3 scenarios active, no active-scenario limit in the license — so the long-standing scenario-cap blocker is retired and Login can be revived once repaired (it is currently `isinvalid`). Risk list rebuilt around what is actually true, with a Resolved section so retired claims cannot be re-raised.
- **2026-10-09 (Login repair)** — **Login scenario fixed and live.** Root cause was not the scenario cap: the webhook had no learned data structure, so `{{1.phone}}` resolved to empty and Twilio threw `21604`, which tripped `maxErrors`, deactivated the scenario and jammed its hook queue. Fixed with Make's learn mode plus two guards — a "has a phone number" filter on the Supabase lookup and `onerror → Ignore` on it. Verified: a real payload sends (3 ops, status 1), an empty payload exits cleanly at 1 op instead of erroring. Also found **Signup Flow's `21604` was already fixed** at 02:06 the same day (E.164 regex filter + onerror handlers), so that risk was closed before it was written down. New risks recorded: intermittent Supabase `401 JWT issued at future` from Make (clock skew — every Supabase module now has an error handler), and stale unparseable hook-queue payloads that Make can neither process nor drain.
- **2026-10-10** — Twilio inbound webhook confirmed **correctly configured** (+1 415 969 2088 → the AI Brain hook, HTTP POST), so yesterday's "not wired" blocker was wrong about the cause though right about the symptom. The real obstacle is the **test device**: the only phone available is a +91 number, and Twilio does not guarantee a +1 long code can receive SMS from outside the +1 dialing code, nor accept MMS from anywhere outside US/Canada (`30011`). Inbound therefore remains completely unproven — zero genuine Twilio SIDs to date — and cannot be proven from Pankaj's own handset. Blocker rewritten around getting a US/Canada sender, with a second Twilio number (sending an MMS with a `MediaUrl`) called out as the only way to test vision without a physical US phone.
- **2026-10-10 (settled with Twilio logs)** — The inbound question is closed, with evidence rather than inference. Twilio's Monitor → Logs shows **every row as `Outbound API` and not a single inbound message, ever**. The webhook was correctly configured all along; Twilio simply never receives texts from the +91 handset. Three findings: outbound to India *works* (the AI Brain's reply was Delivered via carrier network); inbound from +91 never arrives, matching Twilio's "not guaranteed" language for +1 numbers receiving outside +1; and **Twilio substitutes the sender ID on international delivery** — the 2026-10-09 messages went out from `+590391…` rather than +1 415 969 2088, so a reply would go to a number Ozzily does not own. That last one is an independent reason inbound can never work from India. Blocker rewritten accordingly: everything downstream of the webhook is proven green, and only the first hop is untested, which now strictly requires a US/Canada sender. Two new risks recorded from the same log: international SMS costs **$0.1664 for one 2-segment reply** (~$20–40/month for a single Indian user against $29/mo pricing, which hardens the US-only decision from a preference into a requirement), and the Twilio balance is down to **$11.10**. Corrected a claim from earlier in the session: the 1-byte payloads on the hook were *not* Pankaj's texts reaching Make, they were noise against the public hook URL.
