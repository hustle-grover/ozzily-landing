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
//   PADDLE_WEBHOOK_SECRET        notification destination signing secret (ntfset_...)
//   SUPABASE_URL                 injected by the platform
//   SUPABASE_SERVICE_ROLE_KEY    injected by the platform
//   PADDLE_PRICE_ID_MONTHLY      optional, to label a payment's plan
//   PADDLE_PRICE_ID_ANNUAL       optional
//   PADDLE_MAX_SKEW_SECONDS      optional, default 300

const SECRET = Deno.env.get("PADDLE_WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PRICE_MONTHLY = Deno.env.get("PADDLE_PRICE_ID_MONTHLY") ?? "";
const PRICE_ANNUAL = Deno.env.get("PADDLE_PRICE_ID_ANNUAL") ?? "";
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

async function verify(rawBody: string, header: string): Promise<{ ok: true } | { ok: false; why: string }> {
  if (!SECRET) return { ok: false, why: "PADDLE_WEBHOOK_SECRET is not set on this function" };
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

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  // Exactly what Paddle signed: the timestamp, a colon, then the raw body.
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(`${parsed.ts}:${rawBody}`));

  if (!timingSafeEqual(toHex(mac), parsed.h1.toLowerCase())) {
    return { ok: false, why: "signature mismatch" };
  }
  return { ok: true };
}

function planForPriceId(priceId: string | null): string | null {
  if (!priceId) return null;
  if (PRICE_MONTHLY && priceId === PRICE_MONTHLY) return "monthly";
  if (PRICE_ANNUAL && priceId === PRICE_ANNUAL) return "annual";
  return null;
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

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  // Read the body as text FIRST. Nothing may parse it before the HMAC is checked.
  const raw = await req.text();
  const sigHeader = req.headers.get("paddle-signature") ?? "";

  const verdict = await verify(raw, sigHeader);
  if (!verdict.ok) {
    // 401 and no detail to the caller; the reason goes to the function log only.
    console.warn(JSON.stringify({ at: "paddle-webhook", rejected: verdict.why, bytes: raw.length }));
    return new Response("unauthorized", { status: 401 });
  }

  let ev: Record<string, unknown>;
  try {
    ev = JSON.parse(raw);
  } catch {
    console.warn(JSON.stringify({ at: "paddle-webhook", error: "verified but unparseable body" }));
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
  const totals = (details.totals ?? {}) as Record<string, unknown>;
  const eventType = String(ev.event_type ?? "");
  const isTransaction = eventType.startsWith("transaction.");

  // data.id is the transaction id on transaction.* events and the subscription id on
  // subscription.* events, so they must not be read from the same place.
  const subscriptionId = isTransaction
    ? (data.subscription_id as string | null) ?? null
    : (data.id as string | null) ?? null;
  const transactionId = isTransaction ? (data.id as string | null) ?? null : null;

  const body = {
    p_event_id: String(ev.event_id ?? ""),
    p_event_type: eventType,
    p_occurred_at: (ev.occurred_at as string | null) ?? null,
    p_user_id: (custom.user_id as string | null) ?? null,
    p_provider_customer_id: (data.customer_id as string | null) ?? null,
    p_provider_subscription_id: subscriptionId,
    p_provider_transaction_id: transactionId,
    p_amount_cents: (totals.grand_total as string | null) ?? null,
    p_currency: (data.currency_code as string | null) ?? null,
    p_plan: planForPriceId(firstPriceId(data)),
    p_failure_reason: null,
    p_paddle_status: (data.status as string | null) ?? null,
    p_next_billed_at: (data.next_billed_at as string | null) ?? null,
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
    console.error(JSON.stringify({
      at: "paddle-webhook", event_id: body.p_event_id, event_type: eventType,
      rpc_status: rpc.status, rpc_body: result,
    }));
    // Non-2xx tells Paddle to retry, which is what we want for a transient DB fault.
    return new Response("rpc failed", { status: 500 });
  }

  console.log(JSON.stringify({
    at: "paddle-webhook", event_id: body.p_event_id, event_type: eventType, result,
  }));

  return new Response(result, {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
