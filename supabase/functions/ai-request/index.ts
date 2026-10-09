// Ozzily — AI Brain request builder.
//
// NOT YET WIRED IN. The AI Brain scenario still calls the build_ai_request RPC
// directly; see ROADMAP.md "Vision transport". This exists because Twilio hands
// us an MMS *URL* and the Anthropic Messages API rejects `source.type: "url"` —
// it only accepts base64 bytes, so something has to fetch and encode the image.
// Doing it here keeps Make at 9 operations with a single code path for every
// message (a Router branch would duplicate the whole downstream pipeline, and
// an always-on download module would cost an extra operation on every text).
//
// Blocker: Make's Supabase module gets a gateway-level 403 calling
// /functions/v1/* with the same connection that works fine for /rest/v1/*, and
// Make's API cannot show a module's request or response body to diagnose it.
//
// Contract: same shape in and out as the PostgREST RPC it wraps, so the Make
// module's `body[1].user_id` / `body[1].request_json` mappings stay unchanged.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Optional. Twilio media URLs are unauthenticated unless the account has
// "Media HTTP Auth" switched on; if it is, set these two as function secrets
// and the fetch below retries with Basic auth.
const TWILIO_ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID");
const TWILIO_AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN");

// Anthropic caps images at 5MB *encoded*; base64 inflates by 4/3.
const MAX_IMAGE_BYTES = 3_500_000;
const FETCH_TIMEOUT_MS = 8_000;

// Only ever fetch from Twilio. Without this the function would be an open
// proxy for whatever URL turned up in the webhook payload.
const ALLOWED_MEDIA_HOSTS = [
  "api.twilio.com",
  "media.twiliocdn.com",
  "mcs.us1.twilio.com",
];

function hostAllowed(raw: string): boolean {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return false;
  }
  if (u.protocol !== "https:") return false;
  return ALLOWED_MEDIA_HOSTS.some(
    (h) => u.hostname === h || u.hostname.endsWith("." + h),
  );
}

/**
 * verify_jwt only proves the caller holds *some* key signed by this project —
 * and the anon key is meant to be public. Without this check anyone could
 * call the function and read back a user's id, their recent message history
 * and the entire system prompt. Only the service role may build a request.
 *
 * Both headers are checked because callers are inconsistent about which one
 * carries the key: Make's Supabase module sends `apikey`, while a plain fetch
 * sends `Authorization: Bearer`. The presented key is matched against this
 * project's own service-role key, which works whether that key is a legacy
 * JWT or a new-style `sb_secret_` string; the role-claim check is a fallback
 * for JWTs minted with a different secret rotation.
 */
function isServiceRole(req: Request): boolean {
  const candidates = [
    (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim(),
    (req.headers.get("apikey") ?? "").trim(),
  ].filter((t) => t !== "");

  return candidates.some(
    (token) => timingSafeEqual(token, SERVICE_ROLE_KEY) ||
      roleOf(token) === "service_role",
  );
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function roleOf(token: string): string | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const pad = "=".repeat((4 - (parts[1].length % 4)) % 4);
    const json = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/") + pad);
    const role = JSON.parse(json).role;
    return typeof role === "string" ? role : null;
  } catch {
    return null;
  }
}

function toBase64(bytes: Uint8Array): string {
  // Chunked — a single String.fromCharCode spread blows the stack on
  // megabyte-sized photos.
  let bin = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    bin += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(bin);
}

/**
 * Fetch Twilio media and return it base64-encoded. Returns null on any
 * failure: a photo we cannot read must not take the whole turn down, and
 * build_ai_request degrades gracefully when p_media_b64 is absent.
 */
async function fetchMediaAsBase64(
  url: string,
): Promise<{ b64: string; mediaType: string } | null> {
  if (!hostAllowed(url)) {
    console.warn("media host not allowed", { url });
    return null;
  }

  const attempt = async (withAuth: boolean): Promise<Response | null> => {
    const headers: Record<string, string> = {};
    if (withAuth && TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN) {
      headers.Authorization =
        "Basic " + btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`);
    }
    try {
      return await fetch(url, {
        headers,
        redirect: "follow",
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      });
    } catch (e) {
      console.warn("media fetch threw", { withAuth, error: String(e) });
      return null;
    }
  };

  let res = await attempt(false);
  if (
    res && (res.status === 401 || res.status === 403) &&
    TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN
  ) {
    console.log("media fetch unauthorized, retrying with Basic auth");
    res = await attempt(true);
  }
  if (!res || !res.ok) {
    console.warn("media fetch failed", { status: res?.status ?? "none" });
    return null;
  }

  const buf = new Uint8Array(await res.arrayBuffer());
  if (buf.length === 0 || buf.length > MAX_IMAGE_BYTES) {
    console.warn("media size rejected", { bytes: buf.length });
    return null;
  }

  // Trust the response's own content type over Twilio's webhook field.
  const ct = (res.headers.get("content-type") ?? "").split(";")[0].trim();
  const mediaType = ct.startsWith("image/") ? ct : "";
  if (!mediaType) {
    console.warn("media is not an image", { contentType: ct });
    return null;
  }

  return { b64: toBase64(buf), mediaType };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (!isServiceRole(req)) {
    return new Response(JSON.stringify({ error: "forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const str = (v: unknown) =>
    typeof v === "string" && v.trim() !== "" ? v.trim() : null;

  // Accept both the RPC's p_* names and bare names, so the Make module can
  // keep sending exactly what it already sends.
  const phone = str(payload.p_phone) ?? str(payload.phone);
  const body = str(payload.p_body) ?? str(payload.body);
  const mediaUrl = str(payload.p_media_url) ?? str(payload.media_url);
  const mediaType = str(payload.p_media_type) ?? str(payload.media_type);

  if (!phone) {
    return new Response(JSON.stringify({ error: "phone is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  let mediaB64: string | null = null;
  let resolvedType = mediaType;
  if (mediaUrl) {
    const media = await fetchMediaAsBase64(mediaUrl);
    if (media) {
      mediaB64 = media.b64;
      resolvedType = media.mediaType;
      console.log("media encoded", { bytes: media.b64.length, resolvedType });
    }
    // On failure we still pass p_media_url through: build_ai_request then
    // emits the "photo not viewable" marker rather than silently dropping it.
  }

  const rpc = await fetch(`${SUPABASE_URL}/rest/v1/rpc/build_ai_request`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({
      p_phone: phone,
      p_body: body,
      p_media_url: mediaUrl,
      p_media_type: resolvedType,
      p_media_b64: mediaB64,
    }),
  });

  const text = await rpc.text();
  return new Response(text, {
    status: rpc.status,
    headers: { "Content-Type": "application/json" },
  });
});
