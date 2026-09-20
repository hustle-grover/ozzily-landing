# Ozzily — Product Roadmap & Reconciled Plan

**Owner:** Pankaj Grover (Massive Impact Media Private Limited)
**Maintained by:** Claude Code
**Last updated:** 2026-09-19
**Supersedes:** `ProteinPolice_PRD.md` / `ProteinPolice_Report_PRD.docx` (v1.0, Aug 11 2026) — kept only as historical reference. Where this file and the old PRD disagree, **this file wins.**

> This is the living execution plan. It reconciles the original ProteinPolice PRD with every decision made since (name, tone, stack), folds in 2026 research, and sets the milestone order. It is intentionally opinionated.

> ### ⛔ CURRENT BLOCKER (2026-09-19): Make.com active-scenario cap
> The Make plan allows only **2 active scenarios at once**. The product needs **4–5 running concurrently** (Signup + AI Brain + Login + Daily Check-ins + Billing). Both current slots are taken by the two live flows, so **Login is built and proven but cannot stay active**, and Daily Check-ins / Billing can't go live either. **Upgrading the Make plan is a hard prerequisite for Milestone B onward.** Verified 2026-09-19: activating Login failed with "Maximum number of active scenarios has been exceeded"; a one-off test required temporarily swapping Signup Flow out.

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

### Milestone C — Vision / photo verification (Session 2.3)
- Extend Scenario 2's Claude call with an image block for inbound MMS (media_url already logged).
- Protein-from-photo + workout-photo confirmation, streak update.
- **Done when:** a meal photo returns a protein estimate and updates the daily total live.
- **Why third:** delighter, not a gate. Claude is already multimodal — low integration cost, but B moves the metric more.

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

1. **⛔ Make.com active-scenario cap (BLOCKER)** — plan allows 2 active scenarios; product needs 4–5. Blocks Login staying live and all of Milestone B+. Fix: upgrade the Make plan. See the blocker callout at the top.
2. **A2P campaign approval latency** — external dependency; start now, it blocks everything downstream.
2. **AI giving medical-adjacent advice** — mitigated by hard prompt guardrails + prescriber-deferral; audit the system prompt each change.
3. **Cost per active user** — proactive daily texts multiply Twilio + Claude spend; watch COGS as volume grows (PRD modeled $5–9/user/mo).
4. **Competitive parity** — app incumbents (Noom, GLP AI) are well-funded; Ozzily wins on channel + voice, not feature checklists. Don't drift into "app with more features."
5. **US-only pricing story** — international signups break the unit economics; keep US-first (landing already validates this way).

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
