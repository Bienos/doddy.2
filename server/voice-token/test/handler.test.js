import assert from "node:assert/strict";
import { test } from "node:test";
import { handleTokenRequest, parseAccessCodes } from "../src/handler.js";

const CODE = "a-long-tester-code-0001";
const env = {
  ELEVENLABS_API_KEY: "server-only-key",
  ELEVENLABS_AGENT_ID: "agent_test",
  DODDY_ACCESS_CODES: `owner:${CODE}, short:abc`,
};

function request(method = "POST", code = CODE) {
  return new Request("https://example.test/api/voice-token", {
    method,
    headers: code ? { authorization: `Bearer ${code}` } : {},
  });
}

async function run(req, { upstream, environment = env } = {}) {
  const logs = [];
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (upstream instanceof Error) throw upstream;
    return upstream ?? Response.json({ token: "jwt-token" });
  };
  const response = await handleTokenRequest(req, environment, { fetch, log: (entry) => logs.push(entry) });
  return { response, body: await response.json(), logs, calls };
}

test("valid code returns the token, uncached, and never logs secrets", async () => {
  const { response, body, logs, calls } = await run(request());
  assert.equal(response.status, 200);
  assert.deepEqual(body, { token: "jwt-token" });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(calls[0].url, "https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=agent_test");
  assert.equal(calls[0].init.headers["xi-api-key"], "server-only-key");
  const logged = JSON.stringify(logs);
  assert.match(logged, /"tester":"owner"/);
  for (const secret of ["jwt-token", CODE, "server-only-key"]) assert.ok(!logged.includes(secret), secret);
});

test("wrong, missing and too-short codes are refused before ElevenLabs is called", async () => {
  for (const code of ["wrong-code-but-long-enough", null, "abc"]) {
    const { response, body, calls } = await run(request("POST", code));
    assert.equal(response.status, 401);
    assert.deepEqual(body, { error: "invalid_access_code" });
    assert.equal(calls.length, 0);
  }
});

test("only POST", async () => {
  assert.equal((await run(request("GET"))).response.status, 405);
});

test("missing configuration fails closed", async () => {
  const { response, body, calls } = await run(request(), { environment: { ...env, ELEVENLABS_API_KEY: "" } });
  assert.equal(response.status, 500);
  assert.deepEqual(body, { error: "server_not_configured" });
  assert.equal(calls.length, 0);
});

test("upstream failures map to clear errors without leaking upstream bodies", async () => {
  const cases = [
    [new Response("limit", { status: 429 }), 503, "voice_busy"],
    [new Response("nope", { status: 401 }), 502, "upstream_failed"],
    [Response.json({}), 502, "upstream_bad_response"],
    [Object.assign(new Error("t"), { name: "TimeoutError" }), 504, "upstream_timeout"],
    [new TypeError("fetch failed"), 502, "upstream_unreachable"],
  ];
  for (const [upstream, status, error] of cases) {
    const { response, body } = await run(request(), { upstream });
    assert.equal(response.status, status, error);
    assert.deepEqual(body, { error });
  }
});

test("access code list parsing", () => {
  assert.deepEqual(parseAccessCodes(" a:0123456789abcdef ,0123456789abcdefX,b:short, "), [
    { label: "a", code: "0123456789abcdef" },
    { label: "unlabelled", code: "0123456789abcdefX" },
  ]);
});

// OpenAI Realtime test voice (ADR-235).
const openAIEnv = { ...env, OPENAI_API_KEY: "openai-server-key" };

function openAIRequest(body = JSON.stringify({ provider: "openai" }), code = CODE) {
  return new Request("https://example.test/api/voice-token", {
    method: "POST",
    headers: { authorization: `Bearer ${code}`, "content-type": "application/json" },
    body,
  });
}

test("openai: returns a client secret carrying only model and voice, and never logs secrets", async () => {
  const upstream = Response.json({ value: "ek_secret", expires_at: 1, session: { model: "gpt-realtime" } });
  const { response, body, logs, calls } = await run(openAIRequest(), { upstream, environment: openAIEnv });
  assert.equal(response.status, 200);
  assert.deepEqual(body, { token: "ek_secret", provider: "openai", model: "gpt-realtime" });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.openai.com/v1/realtime/client_secrets");
  assert.equal(calls[0].init.method, "POST");
  assert.equal(calls[0].init.headers.authorization, "Bearer openai-server-key");
  const sent = JSON.parse(calls[0].init.body);
  assert.deepEqual(sent, {
    expires_after: { anchor: "created_at", seconds: 120 },
    session: { type: "realtime", model: "gpt-realtime", audio: { output: { voice: "marin" } } },
  });
  // No prompt, notes or tools go through this server.
  assert.equal(sent.session.instructions, undefined);
  assert.equal(sent.session.tools, undefined);
  const logged = JSON.stringify(logs);
  assert.match(logged, /"provider":"openai"/);
  for (const secret of ["ek_secret", CODE, "openai-server-key"]) assert.ok(!logged.includes(secret), secret);
});

test("openai: model and voice come from the environment", async () => {
  const upstream = Response.json({ value: "ek_secret", session: {} });
  const environment = { ...openAIEnv, OPENAI_REALTIME_MODEL: "gpt-realtime-2.1", OPENAI_REALTIME_VOICE: "cedar" };
  const { body, calls } = await run(openAIRequest(), { upstream, environment });
  const sent = JSON.parse(calls[0].init.body);
  assert.equal(sent.session.model, "gpt-realtime-2.1");
  assert.equal(sent.session.audio.output.voice, "cedar");
  assert.equal(body.model, "gpt-realtime-2.1");
});

test("openai: needs its own key; ElevenLabs keys alone are not enough, and nothing is called", async () => {
  const { response, body, calls } = await run(openAIRequest(), { environment: env });
  assert.equal(response.status, 500);
  assert.deepEqual(body, { error: "server_not_configured" });
  assert.equal(calls.length, 0);
});

test("openai: OpenAI alone is enough for the OpenAI voice, and ElevenLabs then reports not configured", async () => {
  const onlyOpenAI = { DODDY_ACCESS_CODES: env.DODDY_ACCESS_CODES, OPENAI_API_KEY: "openai-server-key" };
  const upstream = Response.json({ value: "ek_secret" });
  assert.equal((await run(openAIRequest(), { upstream, environment: onlyOpenAI })).response.status, 200);
  assert.equal((await run(request(), { environment: onlyOpenAI })).response.status, 500);
});

test("openai: a wrong code is refused before OpenAI is called", async () => {
  const { response, calls } = await run(openAIRequest(undefined, "wrong-code-but-long-enough"), { environment: openAIEnv });
  assert.equal(response.status, 401);
  assert.equal(calls.length, 0);
});

test("unknown provider or a body that isn't JSON is refused before anything is called", async () => {
  for (const raw of [JSON.stringify({ provider: "other" }), "not json"]) {
    const { response, body, calls } = await run(openAIRequest(raw), { environment: openAIEnv });
    assert.equal(response.status, 400);
    assert.deepEqual(body, { error: "unknown_provider" });
    assert.equal(calls.length, 0);
  }
});

test("an explicit elevenlabs provider behaves like no body", async () => {
  const { response, body } = await run(openAIRequest(JSON.stringify({ provider: "elevenlabs" })));
  assert.equal(response.status, 200);
  assert.deepEqual(body, { token: "jwt-token" });
});

test("openai: upstream limits, failures and bad replies map like ElevenLabs'", async () => {
  const cases = [
    [new Response("{}", { status: 429 }), 503, "voice_busy"],
    [new Response("{}", { status: 401 }), 502, "upstream_failed"],
    [Response.json({ nothing: true }), 502, "upstream_bad_response"],
    [new Response("not json", { status: 200 }), 502, "upstream_bad_response"],
    [Object.assign(new Error("t"), { name: "TimeoutError" }), 504, "upstream_timeout"],
    [new TypeError("fetch failed"), 502, "upstream_unreachable"],
  ];
  for (const [upstream, status, error] of cases) {
    const { response, body } = await run(openAIRequest(), { upstream, environment: openAIEnv });
    assert.equal(response.status, status, error);
    assert.deepEqual(body, { error });
  }
});
