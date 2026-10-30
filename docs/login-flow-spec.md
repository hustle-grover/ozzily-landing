# Login flow — observation spec

**Purpose.** Inform an original Ozzily phone-login design. This records *patterns and
behaviour* observed on a competitor's public login page, in my own words. It contains no
copy, markup, CSS, JavaScript, images, fonts or logos taken from them.

**Date of observation:** 2026-10-30. **Target:** the public `/login` page of tomo.ai,
visited as an ordinary unauthenticated visitor.

Every finding is labelled **SEEN** (directly observed), **INFERRED** (reasoned from what
was observed), or **UNKNOWN** (not observable within the agreed limits).

---

## 1. Method, and what was deliberately not done

**Done:** loaded the public marketing page, followed the single visible login link, and
read the resulting page's rendered structure and layout.

**Not done, by design:**

- **No phone number was submitted.** Not once.
- No call to any authentication or API endpoint.
- No automation of their login, no retry loops, no attempt to observe or probe any limit.
- No saving of their JS, CSS, copy, images, fonts or logos. Screenshots were used to
  read layout during the session and are **not** committed to this repository.

### Tooling note

REA was specified for this work. **REA was unreachable this session** (connection
timeout; no `rea` tools available), so observation was done with an ordinary browser.

That turned out not to matter, and REA would have been the wrong instrument anyway. Its
web capabilities that go beyond plain browsing — recovering JavaScript sources, exporting
scripts, tracing runtime semantics, inspecting network captures — are precisely the
activities the brief prohibits. The permitted subset of REA for this task reduces to
"render a public page and look at it", which is what a browser does. **Recommendation:
do not reach for REA for competitor UX observation.** It is built for artifact-level
reverse engineering, and nearly all of that is out of scope here by your own rules.

### A contradiction in the brief that blocks part of the request

The brief asks for the **code screen**, and also forbids calling their auth endpoints and
submitting phone numbers repeatedly.

These cannot both hold. The code screen exists only *after* a phone number is submitted,
and submitting one **is** a call to their authentication endpoint — it causes them to send
an SMS, at their cost, to whatever number is given. Submitting a number I do not control
would also mean sending an unsolicited message to a stranger.

So the code screen is recorded below as **UNKNOWN**. It is not guessed at, and nothing in
section 4 is presented as observed when it was not. Resolving this needs a decision from
you (section 7, Q1).

---

## 2. Screen sequence

| # | Screen | Status |
|---|---|---|
| 1 | Marketing home, with a single `Login` link in the navigation | **SEEN** |
| 2 | Phone-entry screen at `/login` | **SEEN** |
| 3 | Code-entry screen | **UNKNOWN** — unreachable without submitting a number |
| 4 | Post-authentication destination | **UNKNOWN** |

An **email** login path is offered as an alternative on screen 2 — **SEEN**. Not relevant
to Ozzily, which holds no email addresses, but worth noting as a deliberate escape hatch
for users whose number has changed.

---

## 3. Screen 2 — phone entry (the one screen fully observed)

### Layout — SEEN

Two-column split on desktop. Left column holds a narrow, vertically centred login card:
small brand mark, short heading, one line of explanatory text, then a single input row,
then a secondary text link beneath it. Right column is a full-bleed illustration carrying
all the visual warmth; the form side is near-monochrome and almost empty.

The whole screen renders roughly 100 characters of visible text. It is extremely spare —
no navigation, no footer, no legal links, no marketing.

### The input row — SEEN

A single horizontal row containing three controls:

1. **Country selector** — a button, not a `<select>`, showing a flag glyph. Defaulted to
   **US** on an unauthenticated visit.
2. **Phone field** — `type="tel"`, `autocomplete="tel"`, with a short informal
   placeholder. No `maxlength`, no `pattern`, no `inputmode` attribute.
3. **Submit** — a small circular icon button at the right end of the row, **rendered in a
   disabled state** on load.

### Behaviour — SEEN unless noted

- Submit is **disabled until the field is considered valid** (observed disabled with the
  field empty). The exact validity rule is **INFERRED** as a length/format check, since no
  `pattern` attribute is present, so it is implemented in script.
- There is **no `<form>` element**. The screen is script-controlled, so submission happens
  via a handler rather than a native form post — **SEEN**.
- **No CAPTCHA of any kind on this screen.** No reCAPTCHA, Turnstile or hCaptcha markup
  present anywhere in the document — **SEEN**. Whether a challenge appears *after*
  submission, or whether protection is purely server-side rate limiting, is **UNKNOWN**.
- No consent checkbox and no terms/privacy links on the login screen — **SEEN**. Consistent
  with login being a returning-user action, with consent captured at signup instead.

### Copy and tone — described, not reproduced

Heading is a short, warm, two-word greeting ending in a full stop. The supporting line
tells the user *which identifier to use*, phrased in terms of how they already interact
with the product rather than in account terminology. Tone is lowercase-leaning, friendly
and non-technical. Placeholder text is informal and abbreviated rather than instructional.

**Pattern worth adopting (not wording):** telling the user *which* identifier to enter,
in terms of their existing relationship with the product, removes the main failure mode of
phone login — people entering a different number from the one on the account.

---

## 4. Screen 3 — code entry — UNKNOWN

Not observed. Not inferred. The following were explicitly requested and **cannot be
reported**: code length, input style (single field vs per-digit boxes), auto-advance and
paste behaviour, auto-submit on completion, resend timer duration and placement, resend
throttling, error-state wording and styling, lockout behaviour after repeated failures,
and any post-submission challenge.

Everything in this section stays blank until the question in section 7 is settled.

---

## 5. Finding that matters more than anything above

**Ozzily's existing `login.html` already contains their copy, close to verbatim.**

| | |
|---|---|
| `login.html:96` | heading is identical to the heading on their login screen |
| `login.html:97` | supporting line is the same sentence with the brand name swapped and "or email" dropped |

`ROADMAP.md`'s 2026-09-19 entry records this as deliberate — the login page was built
"Tomo-style". That predates this brief.

This directly conflicted with the Phase 2 goal of an **original** login "in our own design,
tone and wording", and with the Phase 1 rule about not keeping their copy.

The underlying *pattern* — greet a returning user, then say which identifier to use — is a
generic UX convention and is fine to use. The sentences are not.

### RESOLVED 2026-10-30

Both lines rewritten. The new wording is derived from **our own** established voice rather
than paraphrased from theirs: the welcome SMS already opens "Hey! I'm Ozzily", so the
greeting now echoes our own copy. The supporting line keeps the useful *pattern* (name the
identifier) and adds what the page actually does.

The JS strings were checked at the same time and are original — they match the error
phrasing already used in `index.html`.

---

## 6. What transfers to Ozzily, as patterns

Ordered by how much they are worth, all **INFERRED** as applicable to our context:

1. **Keep the login screen almost empty.** One input row, one sentence, nothing else.
2. **Disable submit until the number parses.** Cheaper and kinder than an error after the
   fact, and it reduces pointless SMS sends — which for Ozzily is direct money.
3. **Name the identifier.** "The number you text Ozzily from" prevents the most common
   failure, in our own words.
4. **Country selector as a button, defaulting sensibly.** Ozzily is US/Canada-only for
   A2P reasons, so our selector should be *narrower* than theirs, not a world list.
5. **An escape hatch for a changed number.** Theirs is email. Ozzily has no email, so this
   is an open design problem for us, not something to copy — see Q3.

Deliberately **not** carried over: their visual treatment, illustration, layout proportions,
colour, type, and all wording.

---

## 7. Open questions before Phase 2

**Q1 — the code screen. DECIDED 2026-10-30: option (a).** The code screen stays UNKNOWN.
Ozzily's own will be designed from the standard OTP pattern against the constraints we
actually build to, not from theirs. **No further observation of the competitor will be
done, and no phone number was ever submitted to them.** Section 4 stays blank permanently;
it is not a gap to be filled later.

The rejected options are recorded so the decision is not silently revisited: (b) you
observe it yourself, (c) you explicitly authorise one submission with a number you control.

**Q2 — is further observation worth it at all?** Answered by Q1: no. Everything still
missing is a generic OTP pattern, best specified from first principles against Supabase
phone auth and Twilio Verify. Our constraints differ from theirs in a way that matters:
**every SMS is real money to Ozzily**, which argues for tighter resend throttling and a
much narrower country list than a venture-funded consumer app would choose.

**Q3 — changed-number recovery.** Ozzily holds no email, so a user whose number changed
has no self-service route in. Options: support via the `HELP` SMS path we already have,
or collect an optional recovery email at signup. This is an Ozzily product decision with
no competitor input needed.

---

## 8. Status

Phase 1 observation is **closed**. Option (a) chosen, so no further observation will take
place. The one actionable finding (section 5) is fixed.

Nothing was built. The only code change arising from Phase 1 is the two-line copy rewrite
in `login.html`.

### Carried into Phase 2 — a security issue found while fixing the copy

The current `login.html` is **not** an authenticated login. It posts to the "Ozzily Login"
Make scenario (id 6333754), which looks the number up and texts either a welcome-back
message or a sign-up nudge. There is no session and no code.

That branch **leaks account existence**: the reply tells an unauthenticated sender whether
a given phone number is registered. Anyone can enumerate numbers against it. Phase 2's rule
— unknown numbers get a generic "if this number has an account, we sent a code" — exists
precisely to prevent this, so the scenario's two-branch router has to go at the same time.

Not fixed here: it is scenario logic, not copy, and it is Phase 2 work.
