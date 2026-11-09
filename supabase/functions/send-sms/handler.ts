// Supabase Send-SMS auth hook: verifies the Standard Webhooks signature GoTrue puts on every
// call, then sends the OTP through MSG91's flow API (DLT-registered template). See
// supabase/README.md for the env vars and how to enable the hook on the hosted project.

export type Env = (name: string) => string | undefined;
export type Log = (message: string) => void;

export interface Deps {
  env: Env;
  fetch: typeof fetch;
  log: Log;
  now: () => number; // ms since epoch
}

export const MSG91_FLOW_URL = "https://control.msg91.com/api/v5/flow";
// GoTrue gives an HTTP hook a few seconds; give up first so the user gets a clean error. We never
// retry, and never answer 429/503 (the codes GoTrue itself retries), so one OTP request makes at
// most one MSG91 call.
export const MSG91_TIMEOUT_MS = 4000;
// Standard Webhooks replay window.
const TIMESTAMP_TOLERANCE_S = 5 * 60;

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== "POST") return hookError(405, "Method not allowed");

    const secret = deps.env("SEND_SMS_HOOK_SECRET");
    const authKey = deps.env("MSG91_AUTH_KEY");
    const templateId = deps.env("MSG91_TEMPLATE_ID");
    const senderId = deps.env("MSG91_SENDER_ID");
    if (!secret || !authKey || !templateId || !senderId) {
      deps.log("send-sms: missing SEND_SMS_HOOK_SECRET or MSG91_* env");
      return hookError(500, "SMS hook is not configured");
    }

    const body = await req.text();
    if (!(await verifySignature(secret, req.headers, body, deps.now()))) {
      deps.log("send-sms: rejected request with invalid webhook signature");
      return hookError(401, "Invalid signature");
    }

    let phone: string, otp: string;
    try {
      const payload = JSON.parse(body);
      phone = String(payload?.user?.phone ?? "").replace(/^\+/, "");
      otp = String(payload?.sms?.otp ?? "");
    } catch {
      return hookError(400, "Invalid payload");
    }
    if (!/^\d{8,15}$/.test(phone) || !/^\d{4,10}$/.test(otp)) {
      return hookError(400, "Invalid payload");
    }

    let res: Response;
    try {
      res = await deps.fetch(MSG91_FLOW_URL, {
        method: "POST",
        headers: { authkey: authKey, "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({
          template_id: templateId,
          sender: senderId,
          short_url: "0",
          recipients: [{ mobiles: phone, otp }],
        }),
        signal: AbortSignal.timeout(MSG91_TIMEOUT_MS),
      });
    } catch (e) {
      const reason = e instanceof DOMException && e.name === "TimeoutError" ? "timeout" : "network error";
      deps.log(`send-sms: MSG91 ${reason} for ${maskPhone(phone)}`);
      return hookError(500, "Failed to send SMS");
    }

    // MSG91 can answer 200 with {"type":"error"}, so check both.
    const result = await res.json().catch(() => null);
    if (!res.ok || result?.type !== "success") {
      const detail = redactDigits(String(result?.message ?? "")).slice(0, 200);
      deps.log(`send-sms: MSG91 rejected ${maskPhone(phone)} (HTTP ${res.status}): ${detail}`);
      return hookError(500, "Failed to send SMS");
    }

    deps.log(`send-sms: sent OTP to ${maskPhone(phone)}`);
    return new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  };
}

// Shape GoTrue reads from a failing hook; `message` reaches the client, so keep it generic.
function hookError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: { http_code: status, message } }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function maskPhone(phone: string): string {
  return phone.length <= 4 ? "****" : `${"*".repeat(phone.length - 4)}${phone.slice(-4)}`;
}

// Provider messages can echo the number or code; drop every run of 4+ digits.
function redactDigits(text: string): string {
  return text.replace(/\d{4,}/g, "****");
}

// https://www.standardwebhooks.com/: secret is "v1,whsec_<base64 key>", signature is
// base64(HMAC-SHA256(key, "<id>.<timestamp>.<body>")), header lists "v1,<sig>" entries.
export async function verifySignature(
  secret: string,
  headers: Headers,
  body: string,
  nowMs: number,
): Promise<boolean> {
  const id = headers.get("webhook-id");
  const timestamp = headers.get("webhook-timestamp");
  const signatures = headers.get("webhook-signature");
  if (!id || !timestamp || !signatures || !/^\d+$/.test(timestamp)) return false;
  if (Math.abs(nowMs / 1000 - Number(timestamp)) > TIMESTAMP_TOLERANCE_S) return false;

  let key: Uint8Array<ArrayBuffer>;
  try {
    key = base64Decode(secret.replace(/^v1,/, "").replace(/^whsec_/, ""));
  } catch {
    return false;
  }
  const expected = await sign(key, `${id}.${timestamp}.${body}`);
  return signatures.split(" ").some((entry) => {
    const [version, sig] = entry.split(",", 2);
    return version === "v1" && sig !== undefined && timingSafeEqual(sig, expected);
  });
}

export async function sign(key: Uint8Array<ArrayBuffer>, content: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(content));
  return btoa(String.fromCharCode(...new Uint8Array(mac)));
}

function base64Decode(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
