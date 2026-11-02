// Verify-first signup. Owns the WHOLE signup flow: nothing exists until the person
// proves they control the number.
//
// WHY THIS REPLACES THE MAKE SIGNUP SCENARIO RATHER THAN SITTING IN FRONT OF IT
// The Make signup hook URL is public -- it is in index.html, because the browser posts
// to it. Putting verification in front of the PAGE therefore fixes nothing: anyone can
// POST straight to the hook and create an unverified user with a fabricated consent
// record. The scenario (6171131) is switched off and this function is the only path in.
//
// WHY verify_jwt = false
// This is a public endpoint by design, called from the landing page by people who have
// no session yet. Requiring the anon key would add nothing -- the anon key is public.
// The protection is: a country gate, our own per-phone and per-IP limits recorded
// BEFORE any paid call, optional Turnstile, and Twilio Verify itself.
//
// Secrets, all from the environment, never committed:
//   TWILIO_ACCOUNT_SID          AC...   (identifies the account in the Messages URL)
//   TWILIO_API_KEY_SID          SK...   (HTTP Basic username -- an API key, not the
//   TWILIO_API_KEY_SECRET               auth token, so it can be rotated on its own)
//   TWILIO_VERIFY_SERVICE_SID   VA...
//   TWILIO_FROM_NUMBER          +1...   (the welcome SMS sender; Verify uses its own)
//   SUPABASE_URL                        injected by the platform
//   SUPABASE_SERVICE_ROLE_KEY           injected by the platform
//   TURNSTILE_SECRET            optional -- when unset, the check is skipped
//   SIGNUP_ALLOWED_PREFIXES     optional, default "+1"
//   SIGNUP_TEST_PHONES          optional, comma-separated E.164 exempt from the gate
//   IP_HASH_SALT                optional, falls back to the service role key

const ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID") ?? "";
const API_KEY_SID = Deno.env.get("TWILIO_API_KEY_SID") ?? "";
const API_KEY_SECRET = Deno.env.get("TWILIO_API_KEY_SECRET") ?? "";
const VERIFY_SID = Deno.env.get("TWILIO_VERIFY_SERVICE_SID") ?? "";
const FROM_NUMBER = Deno.env.get("TWILIO_FROM_NUMBER") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const TURNSTILE_SECRET = Deno.env.get("TURNSTILE_SECRET") ?? "";
const IP_HASH_SALT = Deno.env.get("IP_HASH_SALT") || SERVICE_ROLE_KEY;

const ALLOWED_PREFIXES = (Deno.env.get("SIGNUP_ALLOWED_PREFIXES") ?? "+1")
  .split(",").map((s) => s.trim()).filter(Boolean);

const TEST_PHONES = new Set(
  (Deno.env.get("SIGNUP_TEST_PHONES") ?? "")
    .split(",").map((s) => s.trim()).filter(Boolean),
);

// Only these origins may call this from a browser. A wildcard would let any page
// drive our signup flow.
const ALLOWED_ORIGINS = new Set([
  "https://ozzily.com",
  "https://www.ozzily.com",
]);

const E164 = /^\+[1-9][0-9]{7,14}$/;

// The one message every user receives. PLAIN ASCII AND LENGTH ARE BOTH DELIBERATE:
// a single non-GSM-7 character (an em dash, a curly quote, an emoji) forces the whole
// message to UCS-2 at 70 characters per segment. This text is 302 characters of ASCII
// = 2 segments; the old version with a wave emoji and an em dash cost 5. It also
// carries all four A2P compliance elements (frequency, rates, STOP, HELP), so the
// registered campaign sample still matches in substance. Do not edit casually.
const WELCOME =
  "Hey! I'm Ozzily. I'll help you hold on to your strength while you work on your weight. " +
  "First up - roughly what do you weigh? Reply with a number (180 lb or 82 kg) and I'll set your daily protein target.\n\n" +
  "Ozzily sends up to 4 texts a day. Msg & data rates may apply. Reply STOP to cancel, HELP for help.";

// ----------------------------------------------------------------------- helpers

function corsHeaders(origin: string | null): Record<string, string> {
  const allow = origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://ozzily.com";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The address itself is never stored; we only ever need to count per client. */
async function hashIp(req: Request): Promise<string | null> {
  const fwd = req.headers.get("x-forwarded-for") ?? "";
  const ip = fwd.split(",")[0].trim() || req.headers.get("cf-connecting-ip") || "";
  if (!ip) return null;
  return await sha256Hex(`${IP_HASH_SALT}:${ip}`);
}

function twilioAuthHeader(): string {
  return "Basic " + btoa(`${API_KEY_SID}:${API_KEY_SECRET}`);
}

async function rpc(fn: string, body: Record<string, unknown>): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(body),
  });
}

/** Normalise what the browser sent. The page does this too; never trust it. */
function toE164(raw: string): string | null {
  const trimmed = (raw ?? "").trim();
  const digits = trimmed.replace(/\D/g, "");
  if (trimmed.startsWith("+")) {
    const candidate = "+" + digits;
    return E164.test(candidate) ? candidate : null;
  }
  const ten = digits.length === 11 && digits.startsWith("1") ? digits.slice(1) : digits;
  if (ten.length === 10) return "+1" + ten;
  return null;
}

function countryAllowed(phone: string): boolean {
  if (TEST_PHONES.has(phone)) return true;
  return ALLOWED_PREFIXES.some((p) => phone.startsWith(p));
}

async function turnstileOk(token: string, ip: string | null): Promise<boolean> {
  if (!TURNSTILE_SECRET) return true; // not configured yet; limits still apply
  if (!token) return false;
  const form = new URLSearchParams({ secret: TURNSTILE_SECRET, response: token });
  if (ip) form.set("remoteip", ip);
  try {
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
    const out = await res.json();
    return out?.success === true;
  } catch {
    return false; // fail closed: a broken check must not become an open door
  }
}

function missingConfig(): string[] {
  const need: Array<[string, string]> = [
    ["TWILIO_ACCOUNT_SID", ACCOUNT_SID],
    ["TWILIO_API_KEY_SID", API_KEY_SID],
    ["TWILIO_API_KEY_SECRET", API_KEY_SECRET],
    ["TWILIO_VERIFY_SERVICE_SID", VERIFY_SID],
    ["TWILIO_FROM_NUMBER", FROM_NUMBER],
    ["SUPABASE_URL", SUPABASE_URL],
    ["SUPABASE_SERVICE_ROLE_KEY", SERVICE_ROLE_KEY],
  ];
  return need.filter(([, v]) => !v).map(([k]) => k);
}

// ------------------------------------------------------------------------ actions

async function handleStart(
  payload: Record<string, unknown>,
  req: Request,
  origin: string | null,
): Promise<Response> {
  const phone = toE164(String(payload.phone ?? ""));
  if (!phone) {
    return json({ ok: false, error: "bad_phone" }, 400, origin);
  }
  if (payload.consent !== true) {
    // Consent is collected before the code is sent, and recorded only after the code
    // is confirmed. Both halves are required.
    return json({ ok: false, error: "consent_required" }, 400, origin);
  }
  if (!countryAllowed(phone)) {
    return json({ ok: false, error: "country_not_supported" }, 400, origin);
  }

  const ipHash = await hashIp(req);
  const rawIp = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;

  if (!await turnstileOk(String(payload.turnstile_token ?? ""), rawIp)) {
    return json({ ok: false, error: "challenge_failed" }, 403, origin);
  }

  // Rate check BEFORE the Twilio call: Verify's own limits only engage once the
  // request has reached Twilio, by which point it has already been billed.
  const gate = await rpc("verify_rate_check", {
    p_phone: phone, p_ip_hash: ipHash, p_action: "start",
  });
  const verdict = await gate.json().catch(() => null);
  if (!gate.ok || !verdict?.allowed) {
    console.warn(JSON.stringify({ at: "signup-verify.start", blocked: verdict?.reason ?? "rate_rpc_failed" }));
    return json({ ok: false, error: "too_many_attempts" }, 429, origin);
  }
  const attemptId = verdict.attempt_id as number;

  const form = new URLSearchParams({ To: phone, Channel: "sms" });
  const res = await fetch(
    `https://verify.twilio.com/v2/Services/${VERIFY_SID}/Verifications`,
    {
      method: "POST",
      headers: {
        Authorization: twilioAuthHeader(),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
    },
  );

  if (!res.ok) {
    const detail = await res.text();
    console.error(JSON.stringify({
      at: "signup-verify.start", twilio_status: res.status, twilio_body: detail,
    }));
    await rpc("verify_mark_outcome", { p_attempt_id: attemptId, p_outcome: "denied" });
    // Twilio 60200 = invalid To; 60203 = max send attempts for this number.
    const status = res.status === 429 ? 429 : 502;
    return json({ ok: false, error: "send_failed" }, status, origin);
  }

  return json({ ok: true, sent: true }, 200, origin);
}

async function handleConfirm(
  payload: Record<string, unknown>,
  req: Request,
  origin: string | null,
): Promise<Response> {
  const phone = toE164(String(payload.phone ?? ""));
  const code = String(payload.code ?? "").replace(/\D/g, "");
  if (!phone || code.length < 4 || code.length > 10) {
    return json({ ok: false, error: "bad_input" }, 400, origin);
  }
  if (payload.consent !== true) {
    return json({ ok: false, error: "consent_required" }, 400, origin);
  }
  if (!countryAllowed(phone)) {
    return json({ ok: false, error: "country_not_supported" }, 400, origin);
  }

  const ipHash = await hashIp(req);
  const gate = await rpc("verify_rate_check", {
    p_phone: phone, p_ip_hash: ipHash, p_action: "confirm",
  });
  const verdict = await gate.json().catch(() => null);
  if (!gate.ok || !verdict?.allowed) {
    return json({ ok: false, error: "too_many_attempts" }, 429, origin);
  }
  const attemptId = verdict.attempt_id as number;

  const form = new URLSearchParams({ To: phone, Code: code });
  const res = await fetch(
    `https://verify.twilio.com/v2/Services/${VERIFY_SID}/VerificationCheck`,
    {
      method: "POST",
      headers: {
        Authorization: twilioAuthHeader(),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
    },
  );

  // A 404 here means there is no pending verification for that number -- expired, or
  // already consumed. That is a wrong-code outcome to the caller, not a server fault.
  const checkBody = await res.json().catch(() => ({}));
  const approved = res.ok && checkBody?.status === "approved";

  if (!approved) {
    console.warn(JSON.stringify({
      at: "signup-verify.confirm", twilio_status: res.status,
      verify_status: checkBody?.status ?? null,
    }));
    await rpc("verify_mark_outcome", { p_attempt_id: attemptId, p_outcome: "denied" });
    return json({ ok: false, error: "code_incorrect" }, 400, origin);
  }

  await rpc("verify_mark_outcome", { p_attempt_id: attemptId, p_outcome: "approved" });

  // OWNERSHIP IS NOW PROVEN. Only past this line may a users row or an SMS exist.
  const planRaw = String(payload.plan ?? "").toLowerCase();
  const plan = planRaw === "monthly" || planRaw === "annual" ? planRaw : null;

  const userRes = await rpc("create_verified_user", {
    p_phone: phone,
    p_preferred_plan: plan,
    p_consent_text: String(payload.consent_text ?? "sms_opt_in_v2"),
  });
  const user = await userRes.json().catch(() => null);

  if (!userRes.ok || !user?.ok) {
    console.error(JSON.stringify({
      at: "signup-verify.confirm", stage: "create_user",
      status: userRes.status, body: user,
    }));
    return json({ ok: false, error: "signup_failed" }, 500, origin);
  }

  // A returning signup must not be welcomed as though they were new, and must not be
  // sent the onboarding question they already answered.
  if (!user.is_new) {
    console.log(JSON.stringify({
      at: "signup-verify.confirm", returning: true,
      user_id: user.user_id, status: user.subscription_status,
    }));
    return json({
      ok: true,
      verified: true,
      returning: true,
      subscription_status: user.subscription_status,
    }, 200, origin);
  }

  const smsForm = new URLSearchParams({
    To: phone, From: FROM_NUMBER, Body: WELCOME,
  });
  const smsRes = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${ACCOUNT_SID}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: twilioAuthHeader(),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: smsForm.toString(),
    },
  );
  const smsBody = await smsRes.json().catch(() => ({}));

  if (!smsRes.ok) {
    // The user exists and is verified, so this is not a signup failure. Report it
    // honestly rather than claiming a text was sent: the page tells them we will be
    // in touch, and nothing is logged as delivered that was not.
    console.error(JSON.stringify({
      at: "signup-verify.confirm", stage: "welcome_sms",
      status: smsRes.status, code: smsBody?.code ?? null, body: smsBody?.message ?? null,
    }));
    return json({ ok: true, verified: true, welcome_sent: false }, 200, origin);
  }

  // Log only after Twilio confirms, with the real SID -- never at the point of
  // intending to send. A status written by the step that STARTS an action is how the
  // check-in cron reported five healthy days while delivering nothing.
  await rpc("log_outbound_sms", {
    p_user_id: user.user_id,
    p_body: WELCOME,
    p_kind: "onboarding",
    p_twilio_sid: smsBody?.sid ?? null,
  });

  return json({ ok: true, verified: true, welcome_sent: true }, 200, origin);
}

// ------------------------------------------------------------------------- server

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405, origin);
  }

  const missing = missingConfig();
  if (missing.length > 0) {
    // Fail closed and say so in the log, never pass the request through unverified.
    console.error(JSON.stringify({ at: "signup-verify", missing_env: missing }));
    return json({ ok: false, error: "not_configured" }, 503, origin);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: "bad_json" }, 400, origin);
  }

  const action = String(payload.action ?? "");
  if (action === "start") return await handleStart(payload, req, origin);
  if (action === "confirm") return await handleConfirm(payload, req, origin);
  return json({ ok: false, error: "unknown_action" }, 400, origin);
});
