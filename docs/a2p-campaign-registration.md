# A2P 10DLC Campaign registration — copy-paste submission draft

**Status as of 2026-10-15:** Compliance profile ✅ · Messaging Service ✅ · Brand ✅ ·
**Campaign ⛔ NOT STARTED.**

**Why this is the top blocker.** A2P 10DLC governs *outbound* messages **to US numbers**.
Without an approved Campaign, Twilio blocks every one of them with
[`30034`](https://www.twilio.com/docs/api/errors/30034). That means no welcome SMS, no daily
check-ins and no AI replies to any US user — the entire target market. It has stayed
invisible only because the sole test recipient is an Indian number, which is not
A2P-governed.

Inbound is *not* affected, so a US tester's message will still arrive and log even before
approval. Only Ozzily's reply is blocked.

Console path: **Messaging → Regulatory Compliance → A2P 10DLC → Campaigns → Create**.

---

## Field-by-field

### Use case
**Low Volume Mixed** — correct for the Low Volume Standard Brand already registered.
Ozzily sends a mix of conversational coaching replies and recurring daily check-ins.

### Campaign description
> Ozzily is an opt-in SMS coaching companion for adults using GLP-1 medications. After a
> user submits their mobile number on ozzily.com and ticks a dedicated SMS consent box, we
> send a daily series of short check-in texts about protein intake, resistance training and
> hydration, and we reply conversationally when the user texts us back about their meals or
> workouts. Messages are personalised to the goals the user sets during a short SMS
> onboarding. Ozzily never provides medical advice and never discusses medication or dosing;
> it defers to the user's prescriber for anything clinical.

### Message flow / opt-in description
*(This is the field most campaigns are rejected on. Describe the real flow exactly.)*

> Consent is collected on our website at https://ozzily.com. The visitor enters their mobile
> number in the signup form and must tick a dedicated, unchecked, optional checkbox reading:
> "Sure, text me! I'm happy to get daily texts from Ozzily at this number." Directly beneath
> the checkbox the form displays: "Frequency varies · msg & data rates may apply · text STOP
> or HELP anytime." alongside links to our Terms (https://ozzily.com/terms.html) and Privacy
> Policy (https://ozzily.com/privacy.html).
>
> The checkbox is not pre-ticked, is not bundled with any other agreement, and is not
> required to use the rest of the site. The form cannot be submitted unless it is ticked.
> Consent is stored server-side with a timestamp and a consent-version string, giving a
> per-user audit trail. Immediately after opt-in the user receives a confirmation message
> identifying the sender, stating message frequency, "Msg & data rates may apply", and
> "Reply STOP to cancel, HELP for help."

**Opt-in type:** Web form
**Opt-in keywords:** START, UNSTOP
**Opt-in confirmation message:** the welcome message below (sample 1).

### Sample messages
*(All verbatim production messages.)*

**1 — Opt-in confirmation / onboarding**
> Hey! I'm Ozzily 👋 Excited to help you keep your strength through this whole journey.
> First things first — what medication are you on? Reply: 1) Ozempic  2) Wegovy
> 3) Mounjaro  4) Zepbound
>
> Ozzily sends a few texts a day. Msg & data rates may apply. Reply STOP to cancel, HELP
> for help.

**2 — Morning check-in**
> 80g on the board today. Think of it less as a goal, more as fuel for whatever lift you've
> got planned — your muscles will use every gram of it.

**3 — Conversational reply after a user texts in a meal**
> Paneer tikka + curd sounds great — roughly 20g protein there. That puts you at 20/80g,
> 60g to go. A scoop of dal or a glass of milk later would help close the gap 😊

**4 — Midday nudge**
> Tip: keep a block of cheese or jerky in your bag — zero prep, instant protein. 80g's the
> target, still at 0, so an easy grab-and-go start works great.

**5 — Evening recap**
> Ended at 0 of 80g. Quick tip for tomorrow: keep a protein shake or Greek yogurt somewhere
> visible — out of sight usually means out of mind. Small fix, real difference.

### HELP / STOP
**HELP keywords:** HELP, INFO
**HELP reply:**
> Ozzily — daily SMS coaching for protein and strength. Questions: hello@ozzily.com. Msg &
> data rates may apply. Reply STOP to unsubscribe.

**STOP keywords:** STOP, STOPALL, UNSUBSCRIBE, CANCEL, END, QUIT
**STOP reply:**
> You're unsubscribed from Ozzily. No more messages will be sent. Reply START to rejoin.

### Content attributes
| Question | Answer | Note |
|---|---|---|
| Embedded links? | **Yes** | ozzily.com and, later, Stripe billing links |
| Embedded phone numbers? | No | |
| Age-gated content? | No | |
| Direct lending / loan arrangement? | No | |
| Affiliate marketing? | No | symptom-affiliate links were cut from scope |

---

## Pre-submission checklist — already satisfied

Twilio's documented rejection reasons (`30810`, `30922`) check the website for legal entity
disclosure and a visible opt-in policy. All of this already shipped:

- [x] Legal entity **Massive Impact Media Private Limited** in the site footer
- [x] Privacy Policy live at `/privacy.html`
- [x] Terms of Service live at `/terms.html`
- [x] Dedicated, unchecked, optional SMS consent checkbox (not bundled, not required)
- [x] Frequency + "msg & data rates may apply" + STOP/HELP shown at point of consent
- [x] Welcome message carries identity, frequency, rates and STOP/HELP
- [x] Per-user consent audit trail (`consent_at`, `consent_text = 'sms_opt_in_v1'`)

---

## After approval — verify, don't assume

1. Confirm the Campaign reaches **approved**, not just *submitted*.
2. Confirm **+1 415 969 2088 is in the Messaging Service's sender pool** attached to the
   approved Campaign. A number outside the pool stays unregistered and still returns `30034`.
3. **Re-check the inbound webhook.** The number is attached to a Messaging Service, and when
   that is the case Twilio routes inbound via the **Messaging Service → Integration** tab,
   *not* the number's own "A MESSAGE COMES IN" field. The webhook configured earlier was set
   on the number. Point the Messaging Service at
   `https://hook.us2.make.com/ddlsy3q3kseacijjnowye2emc5h691el` (HTTP POST) as well.
4. Have a US contact text +1 415 969 2088, then check for the first genuine Twilio SID:
   ```sql
   select count(*) filter (where twilio_sid ~ '^SM[0-9a-f]{32}$') as real_sids
   from public.messages where direction = 'inbound';
   ```
