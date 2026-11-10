# Paddle live cutover runbook

Status: **not started.** Prepared 2026-11-10. Nothing live has been changed.

Live and sandbox are two entirely separate Paddle systems. Nothing configured in sandbox
carries over, so every setting below has to be made again in the live account — and a
setting that exists only in sandbox reads as "already done" in the dashboard you are not
looking at. That is the single biggest trap in this whole exercise.

**The order is not cosmetic.** Each step below closes a window in which a real customer
could pay and have it go unrecorded. Specifically:

- The webhook must hold the live signing secret **before** `pay.html` can take a live
  payment. Reverse those two and a real purchase returns 401, Paddle retries, and the
  event ends up in the failed-event list instead of the database.
- The four price-id secrets must be set **before** the new webhook deploys. Reverse those
  and every payment records correctly but `users.plan` stays null, with nothing erroring
  anywhere — the documented silent failure.

---

## Part A — what you do in the Paddle **live** dashboard

### A1. Catalog: two products, two prices

Catalog > Products. Create the monthly and annual prices.

| | monthly | annual |
|---|---|---|
| Amount | 29.00 USD | 249.00 USD |
| Billing period | 1 month, recurring | 1 year, recurring |
| Trial | **none** | **none** |
| Tax | **inclusive** | **inclusive** |

Two of these are load-bearing promises, not preferences:

- **No trial.** The 3-day trial runs over SMS and `/pay` is texted on day 4. A Paddle
  trial collects the card at checkout, which contradicts four published "no card
  required" claims (twice in `terms.html`, twice in `index.html`). If a Paddle trial is
  ever added, the SMS trial must be removed in the same change — otherwise the customer
  gets six free days and the first charge lands on day 7.
- **Tax inclusive.** `index.html`, `terms.html` and `pay.html` all state the price
  includes tax. Exclusive pricing would make all three pages false at checkout.

Then copy both `pri_...` ids out. **They are different from the sandbox ids.**

### A2. Default payment link

Checkout > Checkout settings > Default payment link: `https://ozzily.com/pay`

Needed so a Paddle-hosted link (an invoice, a dunning email, a `_ptxn` recovery link)
lands on our page rather than nowhere.

### A3. Client-side token

Developer tools > Authentication > Client-side tokens. Create one and copy it.

It begins **`live_`**. It is public by design — Paddle.js exposes it in the browser — so
it goes in `pay.html` in the repo. The **API key** is a different thing and must never
appear there; we are not creating one at all (see the note at the end).

### A4. Notification destination, subscribed to all 12 events

Developer tools > Notifications > New destination.

- URL: `https://siblqlstyccysqryggtr.supabase.co/functions/v1/paddle-webhook`
- Type: webhook / standard (not a platform destination — those cannot receive simulations)

Subscribe to exactly these 12. This list is **derived from the mapping inside
`apply_payment_event`**, not remembered — every one of them changes something, and
anything outside the list is an event we would answer but not act on:

```
subscription.activated     transaction.completed
subscription.created       transaction.payment_failed
subscription.trialing
subscription.updated       adjustment.created
subscription.past_due      adjustment.updated
subscription.paused
subscription.resumed
subscription.canceled
```

`adjustment.created` **and** `adjustment.updated` are both required and are easy to miss:
the sandbox destination was not subscribed to either until 2026-11-06, which meant no
refund event could ever have arrived however correct the receiver was. The subscription
list is a third independent gate, after the signing secret and the code.

Then copy the destination's **signing secret** (`ntfset_...`). Send it to me — or paste it
into Supabase yourself; I never need to see its value, only to know it is set.

---

## Part B — what I do, in order, as you hand me each piece

### B1. After A1 — set the four price-id secrets

```
PADDLE_PRICE_ID_MONTHLY          = <live monthly pri_...>
PADDLE_PRICE_ID_ANNUAL           = <live annual pri_...>
PADDLE_PRICE_ID_MONTHLY_SANDBOX  = pri_01m632mtgmf8n9tcdshyhp8gr7
PADDLE_PRICE_ID_ANNUAL_SANDBOX   = pri_01m632prc3s7s6538jh5d2237s
```

The plain pair becomes **live**; the sandbox ids move to the `_SANDBOX` twins. Today the
plain pair holds the sandbox ids, because the deployed code is not yet environment-aware.
Both must be set in this one step: setting only the plain pair makes every sandbox event
match nothing, which is the identical silent shape to setting neither.

### B2. After A4 — set the live signing secret

```
PADDLE_WEBHOOK_SECRET          = <live ntfset_...>
PADDLE_WEBHOOK_SECRET_SANDBOX  = (unchanged, still set)
```

Both are kept for days, not permanently. One deployment cannot verify two environments
from a single secret, so the function accepts either and uses **which one matched** as the
environment tag — derived from the signature rather than from the payload, which is the
only trustworthy source for it.

### B3. Deploy the webhook

**Already done on 2026-11-10** (commit `78d970b`):

- The migration is **applied** — the fourth resolution fallback via
  `payments.provider_transaction_id`, plus the supporting index. Both its paths were
  proven against the live function inside a rolled-back `DO` block, and
  `supabase/schema/` is mirrored (element md5 verified against the database).
- The webhook's environment-aware price pair, `plan_lookup` and `resolved_by` are
  **committed but NOT deployed**.

So the only thing left here is the deploy itself, and it is deliberately sequenced after
B1: deploying before the four price-id secrets are set would leave both environments
unlabelled, because the plain pair still holds the **sandbox** ids that the currently
deployed (non-environment-aware) code expects.

**`supabase/functions/paddle-webhook/index.ts` in the repo is therefore ahead of what is
deployed until this step runs.** Do not read the repo as a description of production in
the meantime.

### B4. After A3 — fill the `pay.html` production block and push

```js
production: {
  token:  "live_...",
  prices: { monthly: "pri_...", annual: "pri_..." }
}
```

`pay.html` refuses to open checkout unless the token's prefix matches the block it sits
in, so a sandbox token pasted here fails closed rather than rendering a checkout that
takes no money. Verified against 11 hostname/token combinations.

**This is the step that makes the site able to take real money.** It goes after B2, never
before.

### B5. After the live tests pass — cleanup

In this order:

1. `delete from public.payment_test_users;` — empties the sandbox allowlist, so from then
   on *any* sandbox event is refused outright. One row is in there now
   (`+919255435752`).
2. Remove `PADDLE_WEBHOOK_SECRET_SANDBOX`, `PADDLE_PRICE_ID_MONTHLY_SANDBOX`,
   `PADDLE_PRICE_ID_ANNUAL_SANDBOX`. After this, a sandbox event returns 401 — which is
   correct, because there is no longer any reason for one to arrive.
3. Remove `SIGNUP_TEST_PHONES`. **This ends your ability to sign up from your own +91
   number** — it is the exemption that lets a non-US number past the US-only gate. Do it
   last, and only once you no longer need to test signup from your own phone.

---

## Part C — the live tests, in this order

Each step is a prerequisite for the next. Do not skip ahead: step 1 is the only one that
costs nothing, and it is the one that catches a wrong signing secret.

### C1. Paddle simulation — proves the signature verifies

Developer tools > Notifications > Simulations. Send a `transaction.completed` to the live
destination.

**Expected result: HTTP 500**, with a body saying `"error": "user not resolved"`.

That is a pass, not a failure. A simulated event carries no real `custom_data.user_id`,
so the user genuinely cannot be resolved, and a refused *live* event deliberately answers
non-2xx so it lands in the failed-event list rather than disappearing. What this test
proves is that the request got **past** the HMAC check and reached the database.

- A **401** means the signing secret is wrong. This is the one thing a 401 cannot
  distinguish — "no secret set" and "wrong signature" both fail closed and look
  identical from outside — so only a correctly-signed request settles it, which is
  exactly what this simulation is.
- A **200** would mean the simulated event somehow resolved a real user. Stop and
  investigate before taking any money.

### C2. A real small purchase — proves the whole path

Use your own phone's `users` row and the real `/pay` link with its `uid`. Pay with a real
card. It will be **$29 and genuinely charged** — there is no live test mode.

- There is no `payment_test_users` guard on live events. The guard constrains sandbox
  only, by design, so this will really activate the account.
- The refund in C4 should return the $29, but **it is an open question whether Paddle
  returns its ~$1.95 fee.** The adjustment *reports* a fee, but reporting it is not the
  same as crediting it. Settle that against the payout statement, not against our
  `fee_cents` column. Budget for the sale costing ~$2 even after refund.

I then check, and this is the full pass condition — not just "a row exists":

```sql
select status, environment, plan, amount_cents, tax_cents, fee_cents, earnings_cents,
       amount_cents = earnings_cents + fee_cents + tax_cents as reconciles
  from public.payments order by created_at desc limit 1;

select subscription_status, plan, provider_customer_id is not null as has_cust,
       provider_subscription_id is not null as has_sub
  from public.users where id = '<your uid>';
```

- `plan` must be `monthly`, not null. A null here means B1 was wrong, and it is the
  specific thing that cannot be noticed later without this check.
- `has_cust` and `has_sub` must both be true. **The purchase writing these back is
  load-bearing for the refund in C4** — without them an adjustment has nothing to
  resolve against except the new fourth fallback.
- `reconciles` must be true.

### C3. Cancel — proves the subscription path

Cancel the subscription in the Paddle dashboard. Expect `subscription.canceled` to arrive
and `users.subscription_status` to become `cancelled`.

### C4. Refund — proves the path that has never run live

Issue a full refund on the C2 transaction.

**On live, a refund is created `pending_approval` and Paddle has to approve it.** Sandbox
approves instantly, so live will look broken by comparison — it is not. Until approval,
no money has moved and `apply_payment_event` deliberately records nothing, because it maps
on the adjustment's own **status**, not on the event name.

Expected once approved:

```sql
select status, amount_cents, provider_adjustment_id is not null as is_adj
  from public.payments order by created_at desc limit 2;
```

A second row with `status = 'refunded'`. Note it **repeats** the original's tax, fee and
earnings as positive numbers — the sign lives in `status`, not in the number — so any
revenue query must sign by status or it double-counts.

This is the first time either failure mapping has run against a real Paddle event in any
environment. `transaction.payment_failed` → `failed` + `past_due` remains untested even
after this; it needs a declining card, which is worth doing in sandbox before C4 rather
than discovering it during a real dunning cycle.

---

## Notes

- **No live API key is created, and nothing needs one.** All of Part A is dashboard work.
  Cancellation is a manual dashboard action (see the support runbook in `CLAUDE.md`), so
  the reason this key once seemed necessary — "the site promises cancel by text" — expired
  on 2026-11-09 when every page was changed to name `hello@ozzily.com`.
- **Make hook 2997965 is not Paddle's destination and must not be pointed at it.** Make
  cannot verify a signature over raw bytes, because its gateway parses and re-serializes
  the JSON. The hook is reserved for the outbound "payment received" SMS and is idle by
  design.
- **The billing beat (day-4 SMS) is still not built**, and must not be built and activated
  before Part A is complete: it would text real users a link to a sandbox checkout.
