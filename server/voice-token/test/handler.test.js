import assert from "node:assert/strict";
import { test } from "node:test";
import { handleTokenRequest } from "../src/handler.js";

const USER_ID = "opaque-account-id";
const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev",
  DODDY_SESSION_SIGNING_KEY: "server-only-session-key-for-tests-000000000000000",
  ELEVENLABS_API_KEY: "elevenlabs-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
  OPENAI_API_KEY: "openai-server-secret",
  PICOVOICE_ACCESS_KEY: "owner-picovoice-secret",
};

function store({ allowed = true } = {}) {
  const calls = [];
  return {
    calls,
    async hitLimits(userId, perUserLimit, globalLimit, now) {
      calls.push({ userId, perUserLimit, globalLimit, now });
      return { allowed, retryAfterSeconds: 120 };
    },
    async getSession() { return { userId: USER_ID, sessionId: "session-1" }; },
  };
}

function request(body, token = "doddysession") {
  return new Request("https://example.test/api/voice-token", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}

async function run(req, options = {}) {
  const logs = [];
  const calls = [];
  const upstream = options.upstream;
  const fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (upstream instanceof Error) throw upstream;
    return upstream ?? Response.json({ token: "provider-credential" });
  };
  const response = await handleTokenRequest(req, options.environment ?? ENV, {
    fetch, log: (entry) => logs.push(entry), now: options.now ?? (() => 100_000),
    authStore: options.authStore ?? store(options.limits),
    authenticateSession: options.authenticateSession ?? (async () => ({ userId: USER_ID, sessionId: "session-1" })),
  });
  return { response, body: await response.json(), logs, calls };
}

test("valid DODDY session exchanges only a short-lived provider credential and never logs secrets", async () => {
  const { response, body, logs, calls } = await run(request(null));
  assert.equal(response.status, 200);
  assert.deepEqual(body, { token: "provider-credential" });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(calls[0].url, "https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=agent_test");
  assert.equal(calls[0].init.headers["xi-api-key"], "elevenlabs-server-secret");
  const logged = JSON.stringify(logs);
  for (const secret of ["provider-credential", "doddysession", "elevenlabs-server-secret", USER_ID]) {
    assert.ok(!logged.includes(secret), `log leaked ${secret}`);
  }
  assert.match(logged, /"provider":"elevenlabs"/);
});

test("missing, invalid, or revoked sessions are refused before a provider request", async () => {
  for (const session of [null, false]) {
    const { response, body, calls } = await run(request(null), {
      authenticateSession: async () => session,
    });
    assert.equal(response.status, 401);
    assert.deepEqual(body, { error: "session_expired" });
    assert.equal(calls.length, 0);
  }
});

test("shared per-user and global rate limits stop provider requests", async () => {
  const authStore = store({ allowed: false });
  const { response, body, calls } = await run(request(null), { authStore });
  assert.equal(response.status, 429);
  assert.deepEqual(body, { error: "rate_limited" });
  assert.equal(response.headers.get("retry-after"), "120");
  assert.equal(calls.length, 0);
  assert.deepEqual(authStore.calls[0], { userId: USER_ID, perUserLimit: 30, globalLimit: 100, now: 100_000 });
});

test("missing provider configuration and shared storage fail closed", async () => {
  const missingProvider = await run(request(null), { environment: { ...ENV, ELEVENLABS_API_KEY: "" } });
  assert.equal(missingProvider.response.status, 500);
  assert.deepEqual(missingProvider.body, { error: "server_not_configured" });
  assert.equal(missingProvider.calls.length, 0);
  const storeUnavailable = await run(request(null), {
    authStore: { async hitLimits() { throw new Error("store unreachable"); } },
  });
  assert.equal(storeUnavailable.response.status, 503);
  assert.deepEqual(storeUnavailable.body, { error: "server_not_configured" });
  assert.equal(storeUnavailable.calls.length, 0);
});

test("upstream failures map to useful errors without leaking provider response bodies", async () => {
  const cases = [
    [new Response("provider details", { status: 429 }), 503, "voice_busy"],
    [new Response("private provider body", { status: 401 }), 502, "upstream_failed"],
    [Response.json({}), 502, "upstream_bad_response"],
    [Object.assign(new Error("timeout"), { name: "TimeoutError" }), 504, "upstream_timeout"],
    [new TypeError("network failed"), 502, "upstream_unreachable"],
  ];
  for (const [upstream, status, error] of cases) {
    const { response, body, logs } = await run(request(null), { upstream });
    assert.equal(response.status, status, error);
    assert.deepEqual(body, { error });
    assert.ok(!JSON.stringify(logs).includes("private provider body"));
  }
});

test("OpenAI grant is short-lived and restricted to the model allowlist", async () => {
  const upstream = Response.json({ value: "openai-short-secret", session: { model: "gpt-realtime-2.1-mini" } });
  const { response, body, calls, logs } = await run(request({ provider: "openai", model: "gpt-realtime-2.1-mini" }), { upstream });
  assert.equal(response.status, 200);
  assert.deepEqual(body, { token: "openai-short-secret", provider: "openai", model: "gpt-realtime-2.1-mini" });
  assert.equal(calls[0].url, "https://api.openai.com/v1/realtime/client_secrets");
  assert.equal(calls[0].init.headers.authorization, "Bearer openai-server-secret");
  const sent = JSON.parse(calls[0].init.body);
  assert.deepEqual(sent.expires_after, { anchor: "created_at", seconds: 120 });
  assert.equal(sent.session.instructions, undefined);
  assert.equal(sent.session.tools, undefined);
  assert.ok(!JSON.stringify(logs).includes("openai-short-secret"));
  const bad = await run(request({ provider: "openai", model: "gpt-4o" }));
  assert.equal(bad.response.status, 400);
  assert.equal(bad.calls.length, 0);
});

test("Picovoice key requires the same authenticated session and is never logged", async () => {
  const { response, body, calls, logs } = await run(request({ provider: "picovoice" }));
  assert.equal(response.status, 200);
  assert.deepEqual(body, { accessKey: "owner-picovoice-secret" });
  assert.equal(calls.length, 0);
  assert.ok(!JSON.stringify(logs).includes("owner-picovoice-secret"));
  const unauthenticated = await run(request({ provider: "picovoice" }), { authenticateSession: async () => null });
  assert.equal(unauthenticated.response.status, 401);
});

test("only POST and bounded valid provider requests are accepted", async () => {
  const get = await run(new Request("https://example.test/api/voice-token", { method: "GET" }));
  assert.equal(get.response.status, 405);
  assert.equal(get.response.headers.get("allow"), "POST");
  const unknown = await run(request({ provider: "other" }));
  assert.equal(unknown.response.status, 400);
  const malformed = await run(new Request("https://example.test/api/voice-token", { method: "POST", body: "{" }));
  assert.equal(malformed.response.status, 400);
  const oversized = await run(new Request("https://example.test/api/voice-token", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ padding: "x".repeat(5_000) }),
  }));
  assert.equal(oversized.response.status, 400);
  assert.equal(oversized.calls.length, 0);
});
