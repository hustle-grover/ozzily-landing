// Paddle billing webhook receiver.
//
// WHY THIS IS NOT A MAKE SCENARIO
// Paddle signs `${ts}:${raw_request_body}` with HMAC-SHA256. The signature is over the
// RAW REQUEST BYTES. Make's webhook parses the JSON and re-serializes it, so no Make
// module ever sees the bytes Paddle signed -- key order and whitespace differ and the
// HMAC can never match. An Edge Function reads the body as text before anything parses
// it, which is the only place verification can be done correctly. It is also testable:
// a synthetic correctly-signed request must be accepted and a tampered one rejected.
//
// THE SIGNATURE IS THE AUTHENTICATION. This function runs with verify_jwt = false,
// because Paddle does not send a Supabase JWT. Nothing downstream of the HMAC check may
// assume the caller is trusted, and nothing above it may touch the database.
//
// Secrets come from the environment and are never committed:
//   PADDLE_WEBHOOK_SECRET          LIVE notification destination signing secret (ntfset_...)
//   PADDLE_WEBHOOK_SECRET_SANDBOX  optional, SANDBOX destination secret, for the cutover only
//   SUPABASE_URL                   injected by the platform
//   SUPABASE_SERVICE_ROLE_KEY      injected by the platform
//   PADDLE_PRICE_ID_MONTHLY        LIVE monthly price id, to label a payment's plan
//   PADDLE_PRICE_ID_ANNUAL         LIVE annual price id
//   PADDLE_PRICE_ID_MONTHLY_SANDBOX  SANDBOX monthly price id, for the cutover only
//   PADDLE_PRICE_ID_ANNUAL_SANDBOX   SANDBOX annual price id, for the cutover only
//   PADDLE_MAX_SKEW_SECONDS        optional, default 300
//
// PRICE IDS ARE PER ENVIRONMENT, AND THE PAIR IS CHOSEN BY THE MATCHED SECRET.
// A sandbox price id never appears in a live event and vice versa, so one shared pair
// cannot label both: whichever environment the pair belongs to, the other one's events
// match nothing, `p_plan` arrives null, and `users.plan` is never labelled even after a
// successful payment -- monthly and annual subscribers become indistinguishable with
// nothing erroring anywhere. Selecting the pair by `verdict.env` -- derived from the
// SIGNATURE, not the payload -- keeps both environments labelled correctly during the
// overlap. A union match over all four ids was rejected: the environment is already
// known, and known from the most trustworthy fact in the request, so a union would
// throw that away and could label a live event from a sandbox price id, hiding the
// very misconfiguration that produced it.
//
// REMOVE THE _SANDBOX PRICE IDS IN THE SAME CLEANUP AS PADDLE_WEBHOOK_SECRET_SANDBOX.
//
// TWO SECRETS, AND WHY THE MATCH IS THE ENVIRONMENT TAG
// Sandbox and live are separate Paddle systems with separate destinations and separate
// signing secrets, so a single secret means every event from the other environment
// returns 401. Accepting both keeps sandbox testable across the cutover. The secret that
// matched is then the only trustworthy environment label available, because it comes
// from the signature rather than from the payload -- and the payload cannot be trusted
// to say which environment it came from. `apply_payment_event` receives that label and
// refuses to apply a sandbox event to any user not in `payment_test_users`. This matters
// because pay.html still opens sandbox checkout on *.vercel.app and Paddle test cards
// work for anybody, so a sandbox checkout carrying a real uid would otherwise activate
// a real account for free.
//
// REMOVE PADDLE_WEBHOOK_SECRET_SANDBOX ONCE LIVE IS PROVEN. The overlap is days, not
// a permanent configuration.

type PaddleEnv = "live" | "sandbox";

const SECRET = Deno.env.get("PADDLE_WEBHOOK_SECRET") ?? "";
const SECRET_SANDBOX = Deno.env.get("PADDLE_WEBHOOK_SECRET_SANDBOX") ?? "";

// SANDBOX IS TRIED FIRST, AND THE ORDER IS A SAFETY PROPERTY, NOT A PREFERENCE.
// The guard in `apply_payment_event` keys on the `sandbox` label, so mislabelling a
// sandbox event as `live` is precisely the free-activation path this whole change
// exists to close, while mislabelling in the other direction only refuses an event.
// Ambiguity must therefore resolve to `sandbox`, the fail-safe reading.
const SIGNING_KEYS: ReadonlyArray<{ env: PaddleEnv; secret: string }> = [
  { env: "sandbox", secret: SECRET_SANDBOX },
  { env: "live", secret: SECRET },
].filter((k) => k.secret !== "") as ReadonlyArray<{ env: PaddleEnv; secret: string }>;

// Ordering alone is not enough: two identical secrets mean the environment label is
// unknowable, and a label that cannot be trusted must not be sent. Refuse outright
// rather than guess, since guessing wrong in one direction activates real accounts.
const SECRETS_AMBIGUOUS = SECRET !== "" && SECRET === SECRET_SANDBOX;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PRICE_IDS: Record<PaddleEnv, { monthly: string; annual: string }> = {
  live: {
    monthly: Deno.env.get("PADDLE_PRICE_ID_MONTHLY") ?? "",
    annual: Deno.env.get("PADDLE_PRICE_ID_ANNUAL") ?? "",
  },
  sandbox: {
    monthly: Deno.env.get("PADDLE_PRICE_ID_MONTHLY_SANDBOX") ?? "",
    annual: Deno.env.get("PADDLE_PRICE_ID_ANNUAL_SANDBOX") ?? "",
  },
};
const MAX_SKEW = Number(Deno.env.get("PADDLE_MAX_SKEW_SECONDS") ?? "300");

const encoder = new TextEncoder();

/** Constant-time comparison. A length-dependent or early-exit compare leaks the MAC. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function toHex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Paddle-Signature looks like `ts=1700000000;h1=<hex>`. */
function parseSignatureHeader(header: string): { ts: string; h1: string } | null {
  let ts = "";
  let h1 = "";
  for (const part of header.split(";")) {
    const idx = part.indexOf("=");
    if (idx === -1) continue;
    const k = part.slice(0, idx).trim();
    const v = part.slice(idx + 1).trim();
    if (k === "ts") ts = v;
    else if (k === "h1") h1 = v;
  }
  return ts && h1 ? { ts, h1 } : null;
}

async function verify(
  rawBody: string,
  header: string,
): Promise<{ ok: true; env: PaddleEnv } | { ok: false; why: string }> {
  if (SIGNING_KEYS.length === 0) {
    return { ok: false, why: "no Paddle signing secret is set on this function" };
  }
  if (SECRETS_AMBIGUOUS) {
    return {
      ok: false,
      why: "PADDLE_WEBHOOK_SECRET and PADDLE_WEBHOOK_SECRET_SANDBOX are identical, so the environment cannot be determined",
    };
  }
  if (!header) return { ok: false, why: "missing Paddle-Signature header" };

  const parsed = parseSignatureHeader(header);
  if (!parsed) return { ok: false, why: "malformed Paddle-Signature header" };

  const tsNum = Number(parsed.ts);
  if (!Number.isFinite(tsNum)) return { ok: false, why: "non-numeric ts" };

  // Reject stale signatures so a captured request cannot be replayed indefinitely.
  const ageSeconds = Math.abs(Date.now() / 1000 - tsNum);
  if (ageSeconds > MAX_SKEW) {
    return { ok: false, why: `signature timestamp is ${Math.round(ageSeconds)}s old, limit ${MAX_SKEW}s` };
  }

  // Exactly what Paddle signed: the timestamp, a colon, then the raw body.
  const signed = encoder.encode(`${parsed.ts}:${rawBody}`);
  const presented = parsed.h1.toLowerCase();

  // Every configured key is tried, and the comparison stays constant-time per key. The
  // loop does not exit early on a match, so the number of HMACs computed is the same
  // whichever key matched and nothing about which environment signed it leaks by timing.
  let matched: PaddleEnv | null = null;
  for (const { env, secret } of SIGNING_KEYS) {
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const mac = await crypto.subtle.sign("HMAC", key, signed);
    if (timingSafeEqual(toHex(mac), presented) && matched === null) matched = env;
  }

  if (matched === null) return { ok: false, why: "signature mismatch" };
  return { ok: true, env: matched };
}

/**
 * Label the plan from the price id, using the price pair for the environment that signed.
 *
 * Returns WHY it could not label, not just null. An unlabelled plan is the documented
 * silent failure here: nothing errors, the payment records fine, and `users.plan` simply
 * stays null forever. The three causes are indistinguishable from a null -- no price id
 * in the payload, no ids configured for this environment, or an id that matches neither
 * -- and only the middle one is a misconfiguration we can fix, so it has to be reported
 * separately rather than lumped in with the other two.
 */
function planForPriceId(
  priceId: string | null,
  env: PaddleEnv,
): { plan: string | null; why: string | null } {
  const pair = PRICE_IDS[env];
  if (!priceId) return { plan: null, why: "payload carried no price id" };
  if (!pair.monthly && !pair.annual) {
    return { plan: null, why: `no ${env} price ids are configured on this function` };
  }
  if (pair.monthly && priceId === pair.monthly) return { plan: "monthly", why: null };
  if (pair.annual && priceId === pair.annual) return { plan: "annual", why: null };
  return { plan: null, why: `price id matches neither configured ${env} price` };
}

/** Pull the first price id out of either a transaction or a subscription payload. */
function firstPriceId(data: Record<string, unknown>): string | null {
  const items = data?.items;
  if (!Array.isArray(items) || items.length === 0) return null;
  const first = items[0] as Record<string, unknown>;
  const price = first?.price as Record<string, unknown> | undefined;
  const direct = first?.price_id;
  if (typeof direct === "string") return direct;
  if (price && typeof price.id === "string") return price.id;
  return null;
}

/**
 * The decline reason for a failed payment, from `data.payments[].error_code`.
 *
 * Paddle sorts `payments` newest-first, so the most recent attempt comes first. This
 * takes the first entry that actually carries a code rather than strictly payments[0],
 * because a later attempt can sit in `action_required` with a null error_code while the
 * real decline reason is on the attempt behind it. A null here is an honest "Paddle did
 * not tell us", which is why it is not coerced to a string like "unknown".
 */
function failureReason(data: Record<string, unknown>): string | null {
  const payments = data?.payments;
  if (!Array.isArray(payments)) return null;
  for (const attempt of payments as Record<string, unknown>[]) {
    const code = attempt?.error_code;
    if (typeof code === "string" && code.trim() !== "") return code.trim();
  }
  return null;
}

/**
 * ONE STRUCTURED LINE PER REQUEST, the same shape on every path.
 *
 * Field-by-field on purpose. The previous version logged the RPC's whole `result`
 * document on three of the four paths, so every event put its entire return value
 * into the log. Nothing emitted here is a body and nothing is a secret: the ids are
 * Paddle's own object ids, the reasons are strings this codebase wrote, and the raw
 * request, the signature header, the payload and the service-role key never reach a
 * log line at all.
 *
 * `outcome` is the single field to alert on. `skipped_reason` and
 * `payment_skipped_reason` are never merged: the first is about the SUBSCRIPTION
 * status, the second about whether a payments row was written, and a correctly
 * ignored refund populates only the second.
 */
type Outcome =
  | "method_not_allowed"
  | "unauthorized"
  | "unparseable_body"
  | "rpc_error"
  | "live_event_refused"
  | "refused"
  | "applied";

interface RpcFields {
  ok: boolean | null;
  user_id: string | null;
  payment_recorded: boolean | null;
  status_change_applied: boolean | null;
  subscription_status: string | null;
  skipped_reason: string | null;
  payment_skipped_reason: string | null;
  // WHICH resolution path found the user. A fallback that fires silently hides the
  // breakage it compensates for: `payments.provider_transaction_id` means the users
  // row is missing its provider ids, which is worth noticing while the purchase is
  // still recent rather than at the next refund.
  resolved_by: string | null;
}

/**
 * The scalar fields we report, pulled out of apply_payment_event's return document.
 *
 * Every field stays null when absent or the wrong type, and an unparseable result
 * leaves all of them null -- which the live-refusal check below treats as a failure,
 * because an unreadable answer is not a yes.
 */
function rpcFields(result: string): RpcFields {
  const out: RpcFields = {
    ok: null,
    user_id: null,
    payment_recorded: null,
    status_change_applied: null,
    subscription_status: null,
    skipped_reason: null,
    payment_skipped_reason: null,
    resolved_by: null,
  };
  let p: Record<string, unknown>;
  try {
    p = JSON.parse(result) as Record<string, unknown>;
  } catch {
    return out;
  }
  if (typeof p?.ok === "boolean") out.ok = p.ok;
  if (typeof p?.user_id === "string") out.user_id = p.user_id;
  if (typeof p?.payment_recorded === "boolean") out.payment_recorded = p.payment_recorded;
  if (typeof p?.status_change_applied === "boolean") {
    out.status_change_applied = p.status_change_applied;
  }
  if (typeof p?.subscription_status === "string") out.subscription_status = p.subscription_status;
  if (typeof p?.skipped_reason === "string") out.skipped_reason = p.skipped_reason;
  if (typeof p?.payment_skipped_reason === "string") {
    out.payment_skipped_reason = p.payment_skipped_reason;
  }
  if (typeof p?.resolved_by === "string") out.resolved_by = p.resolved_by;
  return out;
}

function logRequest(
  level: "log" | "warn" | "error",
  fields: {
    outcome: Outcome;
    http: number;
    event_id?: string | null;
    event_type?: string | null;
    environment?: string | null;
    rpc_status?: number | null;
    reason?: string | null;
    plan_lookup?: string | null;
  } & Partial<RpcFields>,
): void {
  const line: Record<string, unknown> = { at: "paddle-webhook" };
  for (const [k, v] of Object.entries(fields)) {
    if (v !== undefined) line[k] = v;
  }
  const s = JSON.stringify(line);
  if (level === "error") console.error(s);
  else if (level === "warn") console.warn(s);
  else console.log(s);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    logRequest("warn", { outcome: "method_not_allowed", http: 405 });
    return new Response("method not allowed", { status: 405 });
  }

  // Read the body as text FIRST. Nothing may parse it before the HMAC is checked.
  const raw = await req.text();
  const sigHeader = req.headers.get("paddle-signature") ?? "";

  const verdict = await verify(raw, sigHeader);
  if (!verdict.ok) {
    // 401 and no detail to the caller; the reason goes to the function log only.
    logRequest("warn", {
      outcome: "unauthorized", http: 401, reason: verdict.why,
    });
    return new Response("unauthorized", { status: 401 });
  }

  let ev: Record<string, unknown>;
  try {
    ev = JSON.parse(raw);
  } catch {
    logRequest("warn", {
      outcome: "unparseable_body", http: 200,
      reason: "signature valid but body is not JSON",
    });
    // Signature was valid, so this is Paddle's payload. Accept it so Paddle stops
    // retrying something we will never be able to parse, and record it.
    return new Response(JSON.stringify({ ok: false, error: "unparseable body" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const data = (ev.data ?? {}) as Record<string, unknown>;
  const custom = (data.custom_data ?? {}) as Record<string, unknown>;
  const details = (data.details ?? {}) as Record<string, unknown>;
  const eventType = String(ev.event_type ?? "");
  const isTransaction = eventType.startsWith("transaction.");
  const isAdjustment = eventType.startsWith("adjustment.");

  // An adjustment carries its totals at `data.totals`; a transaction nests them under
  // `data.details.totals`. Reading the transaction path for an adjustment yields an
  // empty object, so every amount arrives null and the refund is recorded as 0 -- a
  // row that looks successfully written and states something false.
  const totals = (isAdjustment ? data.totals ?? {} : details.totals ?? {}) as Record<
    string,
    unknown
  >;

  // `data.id` means a different thing per event family, so it must not be read from
  // the same place: the transaction id on transaction.*, the subscription id on
  // subscription.*, and the ADJUSTMENT id on adjustment.* -- where the transaction and
  // subscription it refers to are separate fields. Passing an adjustment id as the
  // subscription id (the old behaviour) resolves no user, so the refund was lost.
  const subscriptionId = isTransaction || isAdjustment
    ? (data.subscription_id as string | null) ?? null
    : (data.id as string | null) ?? null;
  const transactionId = isTransaction
    ? (data.id as string | null) ?? null
    : isAdjustment
    ? (data.transaction_id as string | null) ?? null
    : null;

  // Resolved against the price pair for the environment whose secret matched.
  const planLookup = planForPriceId(firstPriceId(data), verdict.env);

  const body = {
    p_event_id: String(ev.event_id ?? ""),
    p_event_type: eventType,
    p_occurred_at: (ev.occurred_at as string | null) ?? null,
    p_user_id: (custom.user_id as string | null) ?? null,
    p_provider_customer_id: (data.customer_id as string | null) ?? null,
    p_provider_subscription_id: subscriptionId,
    p_provider_transaction_id: transactionId,
    // The gross field is named differently per family: a transaction's totals carry
    // `grand_total`, an adjustment's carry `total`. There is no `grand_total` on an
    // adjustment at all, so reading only that one leaves a refund recorded as 0 --
    // the same silent-zero failure as reading the wrong totals object.
    p_amount_cents:
      ((isAdjustment ? totals.total : totals.grand_total) as string | null) ?? null,
    p_currency: (data.currency_code as string | null) ?? null,
    p_plan: planLookup.plan,
    p_failure_reason: failureReason(data),
    // `data.status` on an adjustment is the ADJUSTMENT's status (pending_approval,
    // approved, rejected, reversed), not a subscription status. Feeding it to the
    // subscription-status mapper would be handing that mapper a value it must never
    // see, so adjustments send null here and carry their own status separately.
    p_paddle_status: isAdjustment ? null : (data.status as string | null) ?? null,
    p_next_billed_at: (data.next_billed_at as string | null) ?? null,
    // Gross alone cannot answer "what did we actually keep". Paddle is the merchant
    // of record, so `tax` is what Paddle collected and remits, and `earnings` is what
    // reaches us. All three in fact arrive at purchase time rather than at settlement
    // (proven by the first real checkout), but they stay null when absent rather than
    // being coerced to 0 -- a zero fee would be a false statement, not a missing one.
    p_tax_cents: (totals.tax as string | null) ?? null,
    p_fee_cents: (totals.fee as string | null) ?? null,
    p_earnings_cents: (totals.earnings as string | null) ?? null,
    // Derived from the signing secret that matched, never from the payload. The RPC
    // fails closed on any other value and refuses to apply a sandbox event to a user
    // outside `payment_test_users`.
    p_environment: verdict.env,
    // The RPC decides whether an adjustment is money that moved, and it needs the
    // adjustment's own status and action to do it -- the event name cannot say, since
    // adjustment.created fires while a refund is still pending_approval. The id is a
    // second idempotency key: created and updated for one adjustment carry different
    // event ids, so provider_event_id alone cannot stop a refund being counted twice.
    p_adjustment_id: isAdjustment ? (data.id as string | null) ?? null : null,
    p_adjustment_action: isAdjustment ? (data.action as string | null) ?? null : null,
    p_adjustment_status: isAdjustment ? (data.status as string | null) ?? null : null,
  };

  const rpc = await fetch(`${SUPABASE_URL}/rest/v1/rpc/apply_payment_event`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(body),
  });

  const result = await rpc.text();

  if (!rpc.ok) {
    logRequest("error", {
      outcome: "rpc_error", http: 500,
      event_id: body.p_event_id, event_type: eventType, environment: verdict.env,
      rpc_status: rpc.status,
    });
    // Non-2xx tells Paddle to retry, which is what we want for a transient DB fault.
    return new Response("rpc failed", { status: 500 });
  }

  // A LIVE EVENT THE RPC REFUSED MUST BE LOUD.
  //
  // This deliberately reverses the earlier rule that a verified-but-unusable event
  // always answers 2xx. That rule was written to avoid an infinite retry loop for an
  // event that will never resolve -- but it also means a real, paid, unattributable
  // transaction disappears with nothing but a log line. Paddle's retries are finite,
  // so the cost of answering non-2xx is bounded, and the payoff is that the event
  // lands in the destination's failed-event list where it cannot be missed.
  //
  // Sandbox keeps the old behaviour: its refusals are the guard working as designed,
  // and they are already recorded in payment_events_refused.
  //
  // `rpcOk === null` means the result could not be parsed, which is counted as a
  // failure for live rather than as success -- an unreadable answer is not a yes.
  const fields = rpcFields(result);
  const rpcOk = fields.ok;

  if (verdict.env === "live" && rpcOk !== true) {
    logRequest("error", {
      outcome: "live_event_refused", http: 500,
      event_id: body.p_event_id, event_type: eventType, environment: verdict.env,
      plan_lookup: planLookup.why,
      ...fields,
    });
    return new Response(result, {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  logRequest(rpcOk === true ? "log" : "warn", {
    outcome: rpcOk === true ? "applied" : "refused", http: 200,
    event_id: body.p_event_id, event_type: eventType, environment: verdict.env,
    plan_lookup: planLookup.why,
    ...fields,
  });

  return new Response(result, {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
