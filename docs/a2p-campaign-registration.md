# A2P 10DLC Campaign registration — submission pack

**Status 2026-10-20: ✅ CAMPAIGN APPROVED** (approved 2026-10-17, submitted 2026-10-15).

| | |
|---|---|
| Campaign SID | `CMe88b63cbe17c94262d71aa04f4809c0f` |
| Brand Registration SID | `BNaba4888535a2aa7d4c640f9c2b73846a` |
| Messaging Service SID | `MG8e48aec3657726f814310fd9ba406db1` |
| Use case | LOW_VOLUME |

> ⛔ **Approved does not mean sending.** Twilio's approval email is explicit: *"You can begin sending messages on this Campaign by **adding phone numbers to the linked messaging service**."* Until +1 415 969 2088 is in the sender pool of `MG8e48aec…`, US-bound messages still return `30034`.
>
> ⛔ **The Twilio account is currently SUSPENDED** for low balance (2026-10-20); a support ticket is open. All sending stopped on 2026-10-15 — see the restore checklist at the end of this file.

The Campaign is approved, so the regulatory gate is cleared. What remains is operational:
the account is suspended, and the number still has to be added to the Campaign's Messaging
Service sender pool. Both are covered in the restore checklist below.

---

## ⚠️ Before you submit: GLP-1 is a named rejection category

Twilio has rejection codes aimed squarely at this product's subject matter:

| Code | Meaning | Resubmittable? |
|---|---|---|
| [`30565`](https://www.twilio.com/docs/api/errors/30565) | *"Promotional messaging for prescription drugs or **GLP-1 products** is not permitted… Only informational use cases are permitted."* | Yes — strip promotional content and resubmit |
| [`30941`](https://www.twilio.com/docs/api/errors/30941) | *"Prescription drug or controlled substance content detected"* | **No — "not eligible for resubmission"** |
| [`30883`](https://www.twilio.com/docs/api/errors/30883) | Content violation found during manual vetting | No — appeal only |

`30941` is the dangerous one: a careless submission can **permanently burn the campaign**.

**Two rules follow from this, and they pull in opposite directions. Both matter.**

1. **No drug brand names in the campaign or in any message.** A sample that reads *"what
   medication are you on? Reply: 1) Ozempic 2) Wegovy…"* invites `30941` even though Ozzily
   sells nothing. ✅ Already done — see "Production state" below.
2. **Do not hide the audience either.** The site's `<title>` is *"Ozzily — Your GLP-1 SMS
   companion"* and the hero says *"Built for GLP-1 journeys"*. A campaign description that
   never mentions GLP-1 while the website leads with it reads as **misrepresentation**, which
   is worse than disclosure and lands in the same non-resubmittable bucket.

The description below therefore **names the audience plainly and rebuts the promotional
concern head-on**. Twilio's own rule is that *informational* use cases are permitted; Ozzily
is informational coaching, so say so rather than dodging.

---

## Production state — what the reviewer will find if they check

| Claim in this pack | Status |
|---|---|
| No drug names in any outbound message | ✅ Welcome text and onboarding changed 2026-10-15; prompt rule 8 forbids Ozzily naming a medication even if the user does |
| Welcome text matches sample 1 verbatim | ✅ Shipped to both Make modules (SendSMS body **and** the logged copy) |
| Frequency claim matches the code | ✅ `get_due_checkins()` caps at 4 beats (`intense`); default `steady` is 3 |
| Consent audit trail | ✅ `consent_at` + `consent_text = 'sms_opt_in_v2'` (bumped when the checkbox wording changed) |
| No affiliate or promotional links | ✅ Verified: `affiliate_clicks` 0 rows, no affiliate reference in the system prompt, **zero outbound messages have ever contained a link** |

---

## Field-by-field

### Use case

**Low Volume Mixed** — matches the registered Low Volume Standard Brand. Recurring check-ins
plus conversational replies.

### Campaign description

> Ozzily, a product of Massive Impact Media Private Limited, is an opt-in, informational SMS
> coaching service for adults working on nutrition and strength, including many who use GLP-1
> weight-management medication prescribed by their own clinician. After a user submits their
> mobile number on ozzily.com and ticks a dedicated SMS consent box, we send up to four short
> scheduled check-ins a day about protein intake, resistance training and hydration, and we
> reply conversationally when the user texts us about meals or workouts. Targets are
> personalised from information the user provides during a short SMS onboarding.
>
> Ozzily does not sell, prescribe, promote, advertise or recommend any medication or health
> product. It operates no pharmacy and no mail-order service, carries no promotional or
> marketing content of any kind, and provides no medical, clinical or dosing advice. Anything
> medical is directed back to the user's own prescriber. All message content concerns food,
> protein, exercise and hydration habits. The website carries a trademark and non-affiliation
> disclaimer stating that Ozzily is independent of, and not endorsed by, any pharmaceutical
> manufacturer.

### Message flow / opt-in description

*(The field most campaigns are rejected on. Describe the real flow exactly — no contradictions.)*

> Consent is collected on our website at https://ozzily.com. The visitor enters their mobile
> number in the signup form and must tick a dedicated checkbox reading: "I agree to receive
> recurring automated text messages from Ozzily (daily coaching check-ins and account/billing
> texts) at this number." Directly beneath it the form displays: "Up to 4 scheduled msgs/day,
> plus replies and occasional account or billing texts. Msg & data rates may apply. Reply STOP
> to cancel, HELP for help. Consent is not a condition of purchase." with links to our Terms
> (https://ozzily.com/terms.html) and Privacy Policy (https://ozzily.com/privacy.html).
>
> The checkbox is not pre-ticked and is not bundled with any other agreement. It must be
> ticked to submit the signup form and receive texts, and no part of the site beyond SMS
> signup requires it. Consent is stored server-side with a timestamp and a consent-version
> string, giving a per-user audit trail. Immediately after opt-in the user receives a
> confirmation message identifying the sender, stating message frequency, "Msg & data rates
> may apply", and "Reply STOP to cancel, HELP for help."

**Opt-in type:** Web form · **Opt-in keywords:** START, UNSTOP
**Opt-in confirmation message:** sample 1 below.

### Sample messages

*(All five are the exact text production sends. Samples 2–5 are verbatim messages pulled from
the `messages` table.)*

**1 — Opt-in confirmation / onboarding**

> Hey! I'm Ozzily 👋 I'll help you hold on to your strength while you work on your weight.
> First up — roughly what do you weigh? Reply with a number (e.g. 180 lb or 82 kg) and I'll
> set your daily protein target.
>
> Ozzily sends up to 4 texts a day. Msg & data rates may apply. Reply STOP to cancel, HELP for
> help.

**2 — Morning check-in**

> 80g on the board today. Think of it less as a goal, more as fuel for whatever lift you've
> got planned — your muscles will use every gram of it.

**3 — Conversational reply after a user texts in a meal**

> 3 eggs + a shake, nice fuel 🥚 That's roughly 43g. You're at 91/80g today — goal smashed!
> Great day for protein.

**4 — Midday nudge**

> Plenty of day left to hit 80g. A couple hard-boiled eggs or some turkey slices now would get
> the ball rolling without much effort.

**5 — Evening recap**

> 139g against an 80g goal — that's a strong finish. Muscle's getting what it needs today.
> Rest easy tonight, friend.

Every sample concerns food, protein and training. **No drug names, no promotional language, no
claims about medication or health outcomes, no links.**

### HELP / STOP

> ⚠️ **Confirm before submitting.** Twilio handles STOP/HELP automatically for 10DLC unless
> **Advanced Opt-Out** is enabled on the Messaging Service. If it is *not* enabled, Twilio
> sends its own default wording and the copy below is not what subscribers actually receive —
> a registered sample that never gets sent is a mismatch. Either enable Advanced Opt-Out with
> this exact copy, or register Twilio's defaults instead. Check:
> **Messaging → Services → [your service] → Opt-Out Management.**

**HELP keywords:** HELP, INFO

> Ozzily — daily SMS coaching for protein and strength. Questions: hello@ozzily.com. Msg &
> data rates may apply. Reply STOP to unsubscribe.

**STOP keywords:** STOP, STOPALL, UNSUBSCRIBE, CANCEL, END, QUIT

> You're unsubscribed from Ozzily. No more messages will be sent. Reply START to rejoin.

### Content attributes

| Question | Answer | Why |
|---|---|---|
| Embedded links? | **Yes** | ozzily.com appears in terms/consent context, and Stripe billing links arrive with Milestone D. No message contains a link today — declaring Yes now is safe; declaring No and later sending one is not. |
| Embedded phone numbers? | No | |
| Age-gated content? | No | 18+ requirement is an eligibility term, not age-gated content |
| Direct lending / loan arrangement? | No | |
| Affiliate marketing? | **No** | Verified against production, not assumed — see "Production state" |

---

## Site-side requirements — status

Twilio checks the website against its documented rejection reasons (`30810`, `30922`), and the
Campaign form additionally requires the privacy policy to be titled "Privacy Policy", describe
what is collected and how it is used, **contain a specific verbatim sentence**, and name the
registered Brand.

- [x] Page titled **Privacy Policy** at `/privacy.html`
- [x] Registered Brand name **Massive Impact Media Private Limited** appears on it
- [x] Verbatim statement present: *"We do not sell or share your SMS opt-in data or personal
      information with third parties for marketing purposes."* — the earlier wording ("We do
      not sell your personal information") did **not** satisfy the literal requirement
- [x] Follow-up sentence: *"Mobile phone numbers and SMS consent are never shared with third
      parties or affiliates for their marketing or promotional use."*
- [x] Terms of Service live at `/terms.html`, with a dedicated **§6 SMS Terms** block
- [x] Legal entity in the site footer, plus a trademark / non-affiliation disclaimer
- [x] SMS consent checkbox is **not pre-ticked**, not bundled, and **required to submit**
      (`consent: false` initial state; `onSubmit` returns early if unticked)
- [x] Frequency + "msg & data rates may apply" + STOP/HELP shown at the point of consent
- [x] Frequency wording identical across the checkbox, terms §6 and privacy §5
- [x] Welcome message carries identity, frequency, rates and STOP/HELP
- [x] Consent audit trail (`consent_at`, `consent_text = 'sms_opt_in_v2'`)

### Known residual risk — your call

The homepage FAQ answers *"Which medications does Ozzily support?"* by naming Ozempic, Wegovy,
Mounjaro, Zepbound **and compounded semaglutide and tirzepatide**. Decision so far: leave it,
because it describes the audience rather than promoting a product, and removing it would hurt
clarity for real users.

Worth knowing: **compounded GLP-1s are the most scrutinised corner of this category**, since
compounding pharmacies and telehealth resellers are what the rules were written for. If the
campaign is rejected on content, that phrase is the first thing to revisit — not the terms
page, and not the footer disclaimer, which is *protective* because it explicitly disclaims
affiliation with the manufacturers.

---

## Restore checklist — do these in order when the account is reinstated

1. **Top up the balance and enable auto-recharge.** The suspension is what stopped all
   sending on 2026-10-15; without auto-recharge it will recur. Campaign registration fees
   drew the balance down right after submission.
2. **Add +1 415 969 2088 to the sender pool** of Messaging Service
   `MG8e48aec3657726f814310fd9ba406db1`. Twilio's approval email states this explicitly —
   an approved Campaign with no number attached still returns `30034`.
3. **Set the inbound webhook on the Messaging Service**, not just the number. Now that the
   number sits in a Messaging Service, Twilio routes inbound via
   **Messaging Service → Integration**. Point it at
   `https://hook.us2.make.com/ddlsy3q3kseacijjnowye2emc5h691el` (HTTP POST). The webhook
   configured on the number alone will be ignored.
4. **Confirm Advanced Opt-Out** (Messaging → Services → Opt-Out Management). If it is off,
   Twilio sends its own STOP/HELP wording rather than the copy registered in this pack.
5. **Verify delivery resumes** — this is now a single query, not guesswork:
   ```sql
   select * from public.checkin_delivery_health();
   ```
   `healthy = true` means beats are being claimed *and* delivered. Anything else prints why.
6. **Prove inbound** — have a US contact text +1 415 969 2088, then:
   ```sql
   select count(*) filter (where twilio_sid ~ '^SM[0-9a-f]{32}$') as real_sids
   from public.messages where direction = 'inbound';
   ```
   This has been `0` for the life of the project. A non-zero result is the first proof that
   a real handset can reach the AI Brain.
7. **Send one US-bound reply** and confirm it is not blocked with `30034`. Campaign approval
   and sender-pool membership are different things; only a delivered message proves both.
