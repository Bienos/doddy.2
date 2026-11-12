import assert from "node:assert/strict";
import { test } from "node:test";
import { handleTokenRequest } from "../src/handler.js";

const USER_ID = "opaque-account-id";
const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev",
  DODDY_SESSION_SIGNING_KEY: "server-only-session-key-for-tests-000000000000000",
  ELEVENLABS_API_KEY: "elevenlabs-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
};

function store({ allowed = true, limit = undefined } = {}) {
  const calls = [];
  return {
    calls,
    async hitLimits(userId, perUserLimit, globalLimit, now, perUserDailyLimit) {
      calls.push({ userId, perUserLimit, globalLimit, now, perUserDailyLimit });
      return { allowed, limit, retryAfterSeconds: 120 };
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
  assert.deepEqual(authStore.calls[0], { userId: USER_ID, perUserLimit: 30, globalLimit: 100, now: 100_000, perUserDailyLimit: 150 });
});

test("an account's daily cap defaults to 150, can be set, and a bad value fails closed before any provider request (ADR-712)", async () => {
  const set = store();
  await run(request(null), { authStore: set, environment: { ...ENV, DODDY_TOKENS_PER_DAY: "40", DODDY_TOKENS_PER_HOUR: "5" } });
  assert.deepEqual([set.calls[0].perUserDailyLimit, set.calls[0].perUserLimit], [40, 5]);
  for (const bad of ["many", "0", "-3", "1.5", "10001", "1e2"]) {
    const authStore = store();
    const { response, body, calls } = await run(request(null), { authStore, environment: { ...ENV, DODDY_TOKENS_PER_DAY: bad } });
    assert.equal(response.status, 500, bad);
    assert.deepEqual(body, { error: "server_not_configured" });
    assert.equal(calls.length, 0);
    assert.equal(authStore.calls.length, 0, "nothing is counted against anyone");
  }
});

test("a refusal says which limit it was in the log, as a fixed word, and sets Retry-After", async () => {
  for (const limit of ["user_hour", "user_day", "global"]) {
    const { response, body, logs, calls } = await run(request({ provider: "elevenlabs" }), {
      authStore: store({ allowed: false, limit }),
    });
    assert.equal(response.status, 429);
    assert.deepEqual(body, { error: "rate_limited" }, "the app sees the same answer for all three");
    assert.equal(response.headers.get("retry-after"), "120");
    assert.equal(logs[0].limit, limit);
    assert.equal(calls.length, 0, "no provider request is made");
    assert.ok(!JSON.stringify(logs).includes(USER_ID));
  }
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

// Owner decision, 9 Nov 2026: ElevenLabs is the only voice. An app build from before that asks for
// OpenAI and gets a plain 400, whatever the server's settings and whether or not the session is valid.
test("a request for OpenAI is refused and sends nothing upstream, counts no limit, and needs no OpenAI setting", async () => {
  for (const body of [{ provider: "openai" }, { provider: "openai", model: "gpt-realtime-2.1-mini" }]) {
    for (const environment of [ENV, { ...ENV, OPENAI_API_KEY: "left-over-key", OPENAI_OPEN_ACCESS: "1" }]) {
      const authStore = store();
      const { response, body: reply, calls, logs } = await run(request(body), { environment, authStore });
      assert.equal(response.status, 400);
      assert.deepEqual(reply, { error: "unknown_provider" });
      assert.equal(calls.length, 0);
      assert.equal(authStore.calls.length, 0, "nothing is counted against anyone");
      assert.ok(!JSON.stringify(logs).includes("left-over-key"));
    }
  }
});

test("a request for the removed Picovoice key is refused and sends nothing upstream (ADR-549)", async () => {
  const { response, calls } = await run(request({ provider: "picovoice" }));
  assert.equal(response.status, 400);
  assert.equal(calls.length, 0);
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

test("ElevenLabs without a voice session is refused, even with a leftover OPENAI_OPEN_ACCESS setting", async () => {
  const eleven = await run(request(null, ""), {
    environment: { ...ENV, OPENAI_OPEN_ACCESS: "1" }, authenticateSession: async () => null,
  });
  assert.equal(eleven.response.status, 401);
  assert.deepEqual(eleven.body, { error: "session_expired" });
  assert.equal(eleven.calls.length, 0);
});

// Owner, 12 Nov 2026 (decision 2026-11-12-translator-agent): translating talks to its own agent, which has no tools.
const TRANSLATOR_ID = "agent_8901m787fgppedy9kkvg7memny34";

test("a translator request gets a token for the translator-only agent, by default with no setting on Vercel", async () => {
  const { response, body, calls, logs } = await run(request({ agent: "translator" }));
  assert.equal(response.status, 200);
  assert.deepEqual(body, { token: "provider-credential" });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=${TRANSLATOR_ID}`);
  assert.equal(calls[0].init.headers["xi-api-key"], "elevenlabs-server-secret");
  // The log says which kind, never an id, a token or a credential.
  assert.equal(logs.at(-1).agent, "translator");
  const logged = JSON.stringify(logs);
  for (const secret of ["provider-credential", "doddysession", "elevenlabs-server-secret", USER_ID, TRANSLATOR_ID, "agent_test"]) {
    assert.ok(!logged.includes(secret), `log leaked ${secret}`);
  }
});

test("ELEVENLABS_TRANSLATOR_AGENT_ID overrides the translator agent, and a request without a body still gets the main agent", async () => {
  const environment = { ...ENV, ELEVENLABS_TRANSLATOR_AGENT_ID: "agent_translator_test" };
  const translator = await run(request({ agent: "translator", provider: "elevenlabs" }), { environment });
  assert.equal(translator.calls[0].url, "https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=agent_translator_test");
  for (const body of [null, {}, { agent: "main" }, { provider: "elevenlabs" }]) {
    const main = await run(request(body), { environment });
    assert.equal(main.response.status, 200);
    assert.equal(main.calls[0].url, "https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=agent_test");
    assert.equal(main.logs.at(-1).agent, "main");
  }
});

test("an unknown agent is refused before anything is counted or sent", async () => {
  for (const agent of ["other", "", "Translator", 7, {}, ["translator"], "agent_test", TRANSLATOR_ID]) {
    const { response, body, calls } = await run(request({ agent }));
    assert.equal(response.status, 400, JSON.stringify(agent));
    assert.deepEqual(body, { error: "unknown_agent" });
    assert.equal(calls.length, 0);
  }
});

test("a translator request counts against the same limits as any other, and a missing key still fails closed", async () => {
  const limited = await run(request({ agent: "translator" }), { limits: { allowed: false, limit: "user_hour" } });
  assert.equal(limited.response.status, 429);
  assert.equal(limited.calls.length, 0);
  const spent = store();
  await run(request({ agent: "translator" }), { authStore: spent });
  assert.equal(spent.calls.length, 1);
  assert.equal(spent.calls[0].userId, USER_ID);
  const noKey = await run(request({ agent: "translator" }), { environment: { ...ENV, ELEVENLABS_API_KEY: "" } });
  assert.equal(noKey.response.status, 500);
  assert.deepEqual(noKey.body, { error: "server_not_configured" });
  assert.equal(noKey.calls.length, 0);
});

test("the translator agent works even where the main agent's id is not set, and the main one still fails closed", async () => {
  const { ELEVENLABS_AGENT_ID, ...withoutMain } = ENV;
  assert.ok(ELEVENLABS_AGENT_ID);
  assert.equal((await run(request({ agent: "translator" }), { environment: withoutMain })).response.status, 200);
  const main = await run(request(null), { environment: withoutMain });
  assert.equal(main.response.status, 500);
  assert.equal(main.calls.length, 0);
});

test("the translator agent also needs a Doddy account session", async () => {
  const { response, body, calls } = await run(request({ agent: "translator" }, ""), { authenticateSession: async () => null });
  assert.equal(response.status, 401);
  assert.deepEqual(body, { error: "session_expired" });
  assert.equal(calls.length, 0);
});
