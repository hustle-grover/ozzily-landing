# A2P 10DLC Campaign registration — submission draft

**Status 2026-10-15:** Compliance profile ✅ · Messaging Service ✅ · Brand ✅ ·
**Campaign ⛔ NOT STARTED.**

Without an approved Campaign, Twilio blocks every US-bound message with
[`30034`](https://www.twilio.com/docs/api/errors/30034) — welcome SMS, daily check-ins and AI
replies alike. Inbound is *not* A2P-gated, so inbound testing can proceed in parallel.

---

## ⚠️ Read this first: GLP-1 is a named rejection category

Twilio has rejection codes aimed squarely at this product's subject matter:

| Code | Meaning | Resubmittable? |
|---|---|---|
| [`30565`](https://www.twilio.com/docs/api/errors/30565) | *"Promotional messaging for prescription drugs or **GLP-1 products** is not permitted… Only informational use cases are permitted."* | Yes — strip promotional content and resubmit |
| [`30941`](https://www.twilio.com/docs/api/errors/30941) | *"Prescription drug or controlled substance content detected"* | **No — "not eligible for resubmission"** |
| [`30883`](https://www.twilio.com/docs/api/errors/30883) | Content violation found during manual vetting | No — appeal only |

`30941` is the dangerous one: a careless submission can **permanently burn the campaign**.

**Ozzily is not what those rules target.** It sells no medication, operates no pharmacy,
recommends no drug, and gives no dosing or medical advice. It is a nutrition and exercise
coaching service whose subscribers happen to be under their own prescriber's care. But a
reviewer skimming a sample message that reads *"what medication are you on? Reply: 1) Ozempic
2) Wegovy 3) Mounjaro 4) Zepbound"* can easily mis-file it.

**Therefore: no drug brand names anywhere in the campaign — and, because registered samples
must match production, none in the live onboarding message either.** See the next section.

---

## Required product change before submitting

The current welcome SMS names four drugs. Registering a sanitised version while production
sends brand names is a mismatch risk and pointless if traffic is ever audited. Change
production first.

**Proposed replacement welcome message** — drops the drug names, keeps every required
compliance element, and collects the body weight that ROADMAP §4 needs for the
body-weight-based protein target (1.2–2.0 g/kg), which onboarding has never asked for:

> Hey! I'm Ozzily 👋 I'll help you hold on to your strength while you work on your weight.
> First up — roughly what do you weigh? Reply with a number (e.g. 180 lb or 82 kg) and I'll
> set your daily protein target.
>
> Ozzily sends a few texts a day. Msg & data rates may apply. Reply STOP to cancel, HELP for
> help.

Touches the Signup Flow welcome text, `ai_brain_system_prompt()`, and the onboarding state
machine. **Trade-off:** the `medication` field stops being collected at signup, and the system
prompt's side-effect protocol currently references it. Decide whether that protocol still
needs the drug name, or whether it can key off symptoms the user reports instead.

---

## Field-by-field

### Use case

**Low Volume Mixed** — matches the registered Low Volume Standard Brand. Recurring check-ins
plus conversational replies.

### Campaign description

*(Leads with what the service is, then rebuts the `30941` / `30565` triggers explicitly.)*

> Ozzily is an opt-in SMS coaching service for adults working on nutrition and strength. After
> a user submits their mobile number on ozzily.com and ticks a dedicated SMS consent box, we
> send a few short texts a day about daily protein intake, resistance training and hydration,
> and we reply conversationally when the user texts us about meals or workouts. Targets are
> personalised from goals the user sets during a short SMS onboarding.
>
> Ozzily does not sell, prescribe, promote, advertise or recommend any medication or health
> product. It operates no pharmacy and no mail-order service, carries no promotional or
> marketing content of any kind, and provides no medical, clinical or dosing advice.
> Subscribers are adults already under the care of their own clinician, and Ozzily directs
> anything medical back to that prescriber. All message content concerns food, protein,
> exercise and hydration habits.

### Message flow / opt-in description

*(The field most campaigns are rejected on. Describes the real flow exactly.)*

> Consent is collected on our website at https://ozzily.com. The visitor enters their mobile
> number in the signup form and must tick a dedicated, unchecked, optional checkbox reading:
> "Sure, text me! I'm happy to get daily texts from Ozzily at this number." Directly beneath
> it the form displays: "Frequency varies · msg & data rates may apply · text STOP or HELP
> anytime." with links to our Terms (https://ozzily.com/terms.html) and Privacy Policy
> (https://ozzily.com/privacy.html).
>
> The checkbox is not pre-ticked, is not bundled with any other agreement, and is not required
> to use the rest of the site. The form cannot be submitted unless it is ticked. Consent is
> stored server-side with a timestamp and a consent-version string, giving a per-user audit
> trail. Immediately after opt-in the user receives a confirmation message identifying the
> sender, stating message frequency, "Msg & data rates may apply", and "Reply STOP to cancel,
> HELP for help."

**Opt-in type:** Web form · **Opt-in keywords:** START, UNSTOP
**Opt-in confirmation message:** sample 1 below.

### Sample messages

*(Samples 2–5 are verbatim production messages. Sample 1 is the proposed replacement welcome
text above — ship it to production before submitting.)*

**1 — Opt-in confirmation / onboarding**

> Hey! I'm Ozzily 👋 I'll help you hold on to your strength while you work on your weight.
> First up — roughly what do you weigh? Reply with a number (e.g. 180 lb or 82 kg) and I'll
> set your daily protein target.
>
> Ozzily sends a few texts a day. Msg & data rates may apply. Reply STOP to cancel, HELP for
> help.

**2 — Morning check-in**

> 80g on the board today. Think of it less as a goal, more as fuel for whatever lift you've
> got planned — your muscles will use every gram of it.

**3 — Conversational reply after a user texts in a meal**

> Paneer tikka + curd sounds great — roughly 20g protein there. That puts you at 20/80g, 60g
> to go. A scoop of dal or a glass of milk later would help close the gap 😊

**4 — Midday nudge**

> Tip: keep a block of cheese or jerky in your bag — zero prep, instant protein. 80g is the
> target, still at 0, so an easy grab-and-go start works great.

**5 — Evening recap**

> Ended at 0 of 80g. Quick tip for tomorrow: keep a protein shake or Greek yogurt somewhere
> visible — out of sight usually means out of mind. Small fix, real difference.

Every sample is about food, protein and training. **No drug names, no promotional language,
no claims about medication or outcomes.**

### HELP / STOP

**HELP keywords:** HELP, INFO

> Ozzily — daily SMS coaching for protein and strength. Questions: hello@ozzily.com. Msg &
> data rates may apply. Reply STOP to unsubscribe.

**STOP keywords:** STOP, STOPALL, UNSUBSCRIBE, CANCEL, END, QUIT

> You're unsubscribed from Ozzily. No more messages will be sent. Reply START to rejoin.

### Content attributes

| Question | Answer |
|---|---|
| Embedded links? | **Yes** — ozzily.com, later Stripe billing links |
| Embedded phone numbers? | No |
| Age-gated content? | No |
| Direct lending / loan arrangement? | No |
| Affiliate marketing? | No |

---

## Site-side requirements — status

Twilio checks the website against its documented rejection reasons (`30810`, `30922`), and the
Campaign form states the privacy policy must be titled "Privacy Policy", describe what is
collected and how it is used, **contain a specific verbatim sentence**, and name the registered
Brand.

- [x] Page titled **Privacy Policy** at `/privacy.html`
- [x] Registered Brand name **Massive Impact Media Private Limited** appears on it
- [x] Verbatim statement added 2026-10-15: *"We do not sell or share your SMS opt-in data or
      personal information with third parties for marketing purposes."* — the previous wording
      ("We do not sell your personal information") did **not** satisfy the literal requirement
- [x] Terms of Service live at `/terms.html`
- [x] Legal entity in the site footer
- [x] Dedicated, unchecked, optional SMS consent checkbox — not bundled, not required
- [x] Frequency + "msg & data rates may apply" + STOP/HELP shown at point of consent
- [x] Welcome message carries identity, frequency, rates and STOP/HELP
- [x] Consent audit trail (`consent_at`, `consent_text = 'sms_opt_in_v1'`)
- [x] **Welcome message updated to drop drug brand names** — shipped 2026-10-15. Onboarding now asks body weight and derives the protein target (weight_kg x 1.6); the medication question is gone entirely, and a new prompt rule forbids Ozzily from naming any medication in a reply even if the user does

---

## After approval — verify, don't assume

1. Confirm the Campaign reaches **approved**, not merely *submitted*.
2. Confirm **+1 415 969 2088 is in the sender pool** of the Messaging Service attached to the
   approved Campaign. A number outside the pool stays unregistered and still returns `30034`.
3. **Re-check the inbound webhook.** The number is attached to a Messaging Service, so Twilio
   routes inbound via **Messaging Service → Integration**, *not* the number's own "A MESSAGE
   COMES IN" field, which is where it was configured. Point the Messaging Service at
   `https://hook.us2.make.com/ddlsy3q3kseacijjnowye2emc5h691el` (HTTP POST) as well.
4. Have a US contact text +1 415 969 2088, then check for the first genuine Twilio SID:

```sql
select count(*) filter (where twilio_sid ~ '^SM[0-9a-f]{32}$') as real_sids
from public.messages where direction = 'inbound';
```
