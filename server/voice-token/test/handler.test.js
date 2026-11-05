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
    const { response, body, logs, calls } = await run(request({ provider: "openai", model: "gpt-realtime-2.1-mini" }), {
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

// ADR-712: the app's voice picker offers both models in every build, so both stay allowed by default;
// the owner can narrow the list without a code change.
test("the OpenAI model allowlist: both models by default, and OPENAI_ALLOWED_MODELS replaces the list", async () => {
  const upstream = () => Response.json({ value: "openai-short-secret", session: {} });
  for (const model of ["gpt-realtime-2.1", "gpt-realtime-2.1-mini"]) {
    const { response } = await run(request({ provider: "openai", model }), { upstream: upstream() });
    assert.equal(response.status, 200, model);
  }
  const mini = { ...ENV, OPENAI_ALLOWED_MODELS: " gpt-realtime-2.1-mini " };
  const allowed = await run(request({ provider: "openai", model: "gpt-realtime-2.1-mini" }), { environment: mini, upstream: upstream() });
  assert.equal(allowed.response.status, 200);
  const pricier = await run(request({ provider: "openai", model: "gpt-realtime-2.1" }), { environment: mini });
  assert.equal(pricier.response.status, 400);
  assert.deepEqual(pricier.body, { error: "unknown_model" });
  assert.equal(pricier.calls.length, 0, "nothing is sent upstream and no limit is used");
  assert.equal((await run(request({ provider: "openai", model: "gpt-4o" }), { environment: mini })).response.status, 400);

  // The setting can allow another id, or several; it never widens beyond what it lists.
  const both = { ...ENV, OPENAI_ALLOWED_MODELS: "gpt-realtime-2.1-mini,gpt-realtime-next" };
  assert.equal((await run(request({ provider: "openai", model: "gpt-realtime-next" }), { environment: both, upstream: upstream() })).response.status, 200);
  assert.equal((await run(request({ provider: "openai", model: "gpt-realtime-2.1" }), { environment: both })).response.status, 400);
  // ElevenLabs doesn't read it at all.
  assert.equal((await run(request(null), { environment: { ...ENV, OPENAI_ALLOWED_MODELS: "!!!" } })).response.status, 200);
});

test("an OPENAI_ALLOWED_MODELS setting that doesn't parse fails closed for OpenAI and sends nothing upstream", async () => {
  for (const bad of [",", " , ", "gpt realtime", "gpt-realtime-2.1;drop", "model/with/slash", `x${"y".repeat(70)}`]) {
    const environment = { ...ENV, OPENAI_ALLOWED_MODELS: bad };
    for (const body of [{ provider: "openai", model: "gpt-realtime-2.1-mini" }, { provider: "openai" }]) {
      const authStore = store();
      const { response, body: reply, calls } = await run(request(body), { environment, authStore });
      assert.equal(response.status, 500, JSON.stringify(bad));
      assert.deepEqual(reply, { error: "server_not_configured" });
      assert.equal(calls.length, 0);
      assert.equal(authStore.calls.length, 0);
    }
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

test("OpenAI without a voice account is refused unless OPENAI_OPEN_ACCESS is on (ADR-726)", async () => {
  for (const environment of [ENV, { ...ENV, OPENAI_OPEN_ACCESS: "" }, { ...ENV, OPENAI_OPEN_ACCESS: "0" }, { ...ENV, OPENAI_OPEN_ACCESS: "yes please" }]) {
    const { response, body, calls } = await run(request({ provider: "openai" }), {
      environment, authenticateSession: async () => null,
      upstream: Response.json({ value: "ek_test", session: { model: "gpt-realtime-2.1-mini" } }),
    });
    assert.equal(response.status, 401);
    assert.deepEqual(body, { error: "session_expired" });
    assert.equal(calls.length, 0);
  }
});

test("with OPENAI_OPEN_ACCESS on, OpenAI works without a session, in one shared limit bucket", async () => {
  const authStore = store();
  const { response, body, calls, logs } = await run(request({ provider: "openai" }, ""), {
    environment: { ...ENV, OPENAI_OPEN_ACCESS: "1" }, authStore, authenticateSession: async () => null,
    upstream: Response.json({ value: "ek_test", session: { model: "gpt-realtime-2.1-mini" } }),
  });
  assert.equal(response.status, 200);
  assert.equal(body.token, "ek_test");
  assert.equal(calls.length, 1);
  assert.equal(authStore.calls[0].userId, "open-access-openai");
  assert.ok(!JSON.stringify(logs).includes("ek_test"));
});

test("with OPENAI_OPEN_ACCESS on, the limits still apply to the shared bucket", async () => {
  const { response, body, calls } = await run(request({ provider: "openai" }, ""), {
    environment: { ...ENV, OPENAI_OPEN_ACCESS: "true" }, authenticateSession: async () => null,
    limits: { allowed: false, limit: "hour" },
  });
  assert.equal(response.status, 429);
  assert.equal(body.error, "rate_limited");
  assert.equal(calls.length, 0);
});

test("OPENAI_OPEN_ACCESS never opens ElevenLabs, and a valid session keeps its own bucket", async () => {
  const environment = { ...ENV, OPENAI_OPEN_ACCESS: "1" };
  const eleven = await run(request(null, ""), { environment, authenticateSession: async () => null });
  assert.equal(eleven.response.status, 401);
  assert.equal(eleven.calls.length, 0);

  const authStore = store();
  const signedIn = await run(request({ provider: "openai" }), {
    environment, authStore,
    upstream: Response.json({ value: "ek_test", session: { model: "gpt-realtime-2.1-mini" } }),
  });
  assert.equal(signedIn.response.status, 200);
  assert.equal(authStore.calls[0].userId, USER_ID);
});
