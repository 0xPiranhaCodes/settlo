import assert from "node:assert/strict";
import { createHandler, MSG91_FLOW_URL, sign } from "./handler.ts";

const KEY = new TextEncoder().encode("test-hook-secret-key-0123456789");
const SECRET = `v1,whsec_${btoa(String.fromCharCode(...KEY))}`;
const NOW = 1_762_000_000_000;
const PHONE = "919876543210";
const OTP = "482913";
const ENV: Record<string, string> = {
  SEND_SMS_HOOK_SECRET: SECRET,
  MSG91_AUTH_KEY: "msg91-auth-key",
  MSG91_TEMPLATE_ID: "tmpl-123",
  MSG91_SENDER_ID: "STTLO",
};

type Call = { url: string; init: RequestInit };

function setup(respond: (call: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const logs: string[] = [];
  const handler = createHandler({
    env: (name) => ENV[name],
    fetch: (input, init) => {
      const call = { url: String(input), init: init ?? {} };
      calls.push(call);
      return Promise.resolve(respond(call));
    },
    log: (m) => logs.push(m),
    now: () => NOW,
  });
  return { handler, calls, logs };
}

async function hookRequest(opts: { key?: Uint8Array<ArrayBuffer>; body?: string } = {}): Promise<Request> {
  const body = opts.body ?? JSON.stringify({ user: { id: "u1", phone: PHONE }, sms: { otp: OTP } });
  const id = "msg_1";
  const timestamp = String(Math.floor(NOW / 1000));
  const sig = await sign(opts.key ?? KEY, `${id}.${timestamp}.${body}`);
  return new Request("http://localhost/send-sms", {
    method: "POST",
    headers: {
      "webhook-id": id,
      "webhook-timestamp": timestamp,
      "webhook-signature": `v1,${sig}`,
    },
    body,
  });
}

const ok = () => Response.json({ type: "success", message: "3763646c3058373530393938" });

function assertMasked(logs: string[]) {
  for (const line of logs) {
    assert.ok(!line.includes(PHONE), `phone leaked: ${line}`);
    assert.ok(!line.includes(OTP), `otp leaked: ${line}`);
  }
}

Deno.test("valid signature sends the OTP through MSG91", async () => {
  const { handler, calls, logs } = setup(ok);
  const res = await handler(await hookRequest());

  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, MSG91_FLOW_URL);
  assert.equal(new Headers(calls[0].init.headers).get("authkey"), "msg91-auth-key");
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), {
    template_id: "tmpl-123",
    sender: "STTLO",
    short_url: "0",
    recipients: [{ mobiles: PHONE, otp: OTP }],
  });
  assert.ok(calls[0].init.signal, "MSG91 call must carry a timeout signal");
  assert.ok(logs.some((l) => l.includes("********3210")));
  assertMasked(logs);
});

Deno.test("bad signature is rejected with 401 and never calls MSG91", async () => {
  const { handler, calls } = setup(ok);
  const res = await handler(await hookRequest({ key: new TextEncoder().encode("wrong-key") }));

  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: { http_code: 401, message: "Invalid signature" } });
  assert.equal(calls.length, 0);
});

Deno.test("tampered body is rejected with 401", async () => {
  const { handler, calls } = setup(ok);
  const signed = await hookRequest();
  const tampered = new Request(signed.url, {
    method: "POST",
    headers: signed.headers,
    body: JSON.stringify({ user: { phone: "919999999999" }, sms: { otp: OTP } }),
  });

  assert.equal((await handler(tampered)).status, 401);
  assert.equal(calls.length, 0);
});

Deno.test("stale timestamp is rejected with 401", async () => {
  const { calls } = setup(ok);
  const later = createHandler({
    env: (name) => ENV[name],
    fetch: () => Promise.reject(new Error("must not be called")),
    log: () => {},
    now: () => NOW + 10 * 60_000,
  });

  assert.equal((await later(await hookRequest())).status, 401);
  assert.equal(calls.length, 0);
});

Deno.test("MSG91 error surfaces as a hook error, once, with masked logs", async () => {
  const { handler, calls, logs } = setup(() =>
    Response.json({ type: "error", message: `Invalid mobile ${PHONE} for otp ${OTP}` })
  );
  const res = await handler(await hookRequest());

  assert.equal(res.status, 500);
  assert.deepEqual(await res.json(), { error: { http_code: 500, message: "Failed to send SMS" } });
  assert.equal(calls.length, 1, "no retries");
  assert.ok(logs.some((l) => l.includes("MSG91 rejected")));
  assertMasked(logs);
});

Deno.test("MSG91 HTTP failure surfaces as a hook error", async () => {
  const { handler, calls } = setup(() => new Response("bad gateway", { status: 502 }));
  const res = await handler(await hookRequest());

  assert.equal(res.status, 500);
  assert.equal(calls.length, 1);
});

Deno.test("MSG91 timeout surfaces as a hook error without retry", async () => {
  const { handler, calls, logs } = setup(() => {
    throw new DOMException("signal timed out", "TimeoutError");
  });
  const res = await handler(await hookRequest());

  assert.equal(res.status, 500);
  assert.equal(calls.length, 1);
  assert.ok(logs.some((l) => l.includes("timeout")));
  assertMasked(logs);
});

Deno.test("missing config fails closed", async () => {
  const handler = createHandler({ env: () => undefined, fetch, log: () => {}, now: () => NOW });
  assert.equal((await handler(await hookRequest())).status, 500);
});
