import assert from "node:assert/strict";
import { test } from "node:test";
import { handleTokenRequest } from "../src/handler.js";
import { signAccessToken } from "../src/voice-auth.js";

const USER_ID = "opaque-account-id";
const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev",
  DODDY_SESSION_SIGNING_KEY: "server-only-session-key-for-tests-000000000000000",
  ELEVENLABS_API_KEY: "elevenlabs-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
  OPENAI_API_KEY: "openai-server-secret",
};

function store({ allowed = true, limit } = {}) {
  const calls = [];
  const daily = [];
  return {
    calls, daily,
    async hitLimits(userId, perUserLimit, globalLimit, now, dailyLimits) {
      calls.push({ userId, perUserLimit, globalLimit, now });
      daily.push(dailyLimits);
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
  assert.deepEqual(authStore.calls[0], { userId: USER_ID, perUserLimit: 30, globalLimit: 100, now: 100_000 });
});

test("a daily limit refuses with daily_limit, says which one, and the full model counts on its own", async () => {
  for (const limit of ["voice", "full_model"]) {
    const { response, body, calls, logs } = await run(request({ provider: "openai", model: "gpt-realtime-2.1" }), {
      limits: { allowed: false, limit },
    });
    assert.equal(response.status, 429);
    assert.deepEqual(body, { error: "daily_limit", limit });
    assert.equal(response.headers.get("retry-after"), "120");
    assert.equal(calls.length, 0, "no provider request");
    assert.equal(logs[0].limit, limit);
  }
  const counted = async (body, environment) => {
    const authStore = store();
    await run(request(body), { authStore, environment });
    return authStore.daily[0];
  };
  assert.deepEqual(await counted({ provider: "openai", model: "gpt-realtime-2.1" }),
    { dailyLimit: 100, fullModelDailyLimit: 10, fullModel: true });
  assert.equal((await counted({ provider: "openai", model: "gpt-realtime-2.1-mini" })).fullModel, false);
  assert.equal((await counted(null)).fullModel, false, "ElevenLabs counts only against the overall daily limit");
  assert.equal((await counted({ provider: "openai" }, { ...ENV, OPENAI_REALTIME_MODEL: "gpt-realtime-2.1" })).fullModel, true,
    "the server's default model counts too");
  assert.deepEqual(await counted(null, { ...ENV, VOICE_DAILY_PER_USER: "250", VOICE_DAILY_FULL_MODEL_PER_USER: "3" }),
    { dailyLimit: 250, fullModelDailyLimit: 3, fullModel: false });
  for (const bad of [{ VOICE_DAILY_PER_USER: "0" }, { VOICE_DAILY_FULL_MODEL_PER_USER: "lots" }]) {
    const authStore = store();
    const refused = await run(request(null), { authStore, environment: { ...ENV, ...bad } });
    assert.equal(refused.response.status, 500, "a bad setting fails closed");
    assert.equal(authStore.calls.length, 0);
  }
});

/** The real token check and store adapter, over a fake Redis REST endpoint that answers after a delay. */
async function throughStore({ session = { userId: USER_ID, sessionId: "session-1", refreshHash: "h" }, sessionFails = false,
  limits = [1, 1, "ok"], limitsFail = false, token, environment = {} } = {}) {
  const now = Date.parse("2026-10-16T12:00:00Z");
  const events = [];
  const storeFetch = async (_url, init) => {
    const name = JSON.parse(init.body)[0][0] === "GET" ? "session" : "limits";
    events.push(`${name} sent`);
    await new Promise((resolve) => setTimeout(resolve, 10));
    events.push(`${name} answered`);
    if (name === "session") {
      return sessionFails ? new Response("", { status: 500 }) : Response.json([{ result: session && JSON.stringify(session) }]);
    }
    return Response.json([limitsFail ? { error: "ERR" } : { result: limits }]);
  };
  const upstream = [];
  const accessToken = token ?? signAccessToken({ userId: USER_ID, sessionId: "session-1" }, ENV.DODDY_SESSION_SIGNING_KEY, now);
  const response = await handleTokenRequest(request(null, accessToken), {
    ...ENV, UPSTASH_REDIS_REST_URL: "https://redis.example.test", UPSTASH_REDIS_REST_TOKEN: "store-secret", ...environment,
  }, {
    storeFetch, now: () => now, log: () => {},
    fetch: async (url) => { upstream.push(String(url)); return Response.json({ token: "provider-credential" }); },
  });
  return { response, body: await response.json(), events, upstream };
}

test("the session lookup and the limit count are sent together, with the same outcomes as before", async () => {
  const ok = await throughStore();
  assert.equal(ok.response.status, 200);
  assert.deepEqual(ok.events.slice(0, 2).sort(), ["limits sent", "session sent"], "both in flight before either answers");
  assert.equal(ok.upstream.length, 1);

  const otherAccount = { userId: "someone-else", sessionId: "session-1", refreshHash: "h" };
  for (const options of [{ session: null }, { session: null, limitsFail: true }, { session: otherAccount },
    { session: null, environment: { VOICE_DAILY_PER_USER: "x" } }]) {
    const refused = await throughStore(options);
    assert.equal(refused.response.status, 401, JSON.stringify(options));
    assert.deepEqual(refused.body, { error: "session_expired" });
    assert.equal(refused.upstream.length, 0);
  }
  for (const options of [{ sessionFails: true }, { limitsFail: true }]) {
    const down = await throughStore(options);
    assert.equal(down.response.status, 503, JSON.stringify(options));
    assert.deepEqual(down.body, { error: "server_not_configured" });
    assert.equal(down.upstream.length, 0);
  }
  const misconfigured = await throughStore({ environment: { VOICE_DAILY_PER_USER: "x" } });
  assert.equal(misconfigured.response.status, 500);
  assert.deepEqual(misconfigured.events, ["session sent", "session answered"], "nothing counted with a bad setting");
  const limited = await throughStore({ limits: [31, 1, "hourly"] });
  assert.equal(limited.response.status, 429);
  assert.deepEqual(limited.body, { error: "rate_limited" });
  assert.equal(limited.response.headers.get("retry-after"), "3600");
  assert.equal(limited.upstream.length, 0);
  const badToken = await throughStore({ token: "not-a-signed-token" });
  assert.equal(badToken.response.status, 401);
  assert.deepEqual(badToken.events, [], "a bad token reaches no store");
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
