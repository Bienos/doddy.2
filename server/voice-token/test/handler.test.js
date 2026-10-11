import assert from "node:assert/strict";
import { test } from "node:test";
import { createTesterLimiter, handleTokenRequest, ignoredShortCodes, parseAccessCodes } from "../src/handler.js";

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

async function run(req, { upstream, environment = env, deps = {} } = {}) {
  const logs = [];
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (upstream instanceof Error) throw upstream;
    return upstream ?? Response.json({ token: "jwt-token" });
  };
  const response = await handleTokenRequest(req, environment, { fetch, log: (entry) => logs.push(entry), ...deps });
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

test("only POST, and the refusal says so", async () => {
  const { response } = await run(request("GET"));
  assert.equal(response.status, 405);
  assert.equal(response.headers.get("allow"), "POST");
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

test("one tester can't use up the shared voice limits: tokens per tester per hour", async () => {
  const OTHER = "another-tester-code-02";
  const environment = { ...env, DODDY_ACCESS_CODES: `owner:${CODE},other:${OTHER}`, DODDY_TOKENS_PER_HOUR: "2" };
  const limiter = createTesterLimiter();
  let ms = Date.parse("2026-10-11T10:15:00Z");
  const deps = { limiter, now: () => ms };
  assert.equal((await run(request(), { environment, deps })).response.status, 200);
  assert.equal((await run(request(), { environment, deps })).response.status, 200);
  const third = await run(request(), { environment, deps });
  assert.equal(third.response.status, 429);
  assert.deepEqual(third.body, { error: "rate_limited" });
  assert.equal(third.response.headers.get("retry-after"), String(45 * 60));
  assert.equal(third.calls.length, 0, "ElevenLabs is not called");
  assert.equal((await run(request("POST", OTHER), { environment, deps })).response.status, 200, "other testers unaffected");
  ms += 45 * 60_000;
  assert.equal((await run(request(), { environment, deps })).response.status, 200, "a new hour starts fresh");
});

test("an invalid per-hour setting fails closed", async () => {
  const { response, calls } = await run(request(), { environment: { ...env, DODDY_TOKENS_PER_HOUR: "lots" } });
  assert.equal(response.status, 500);
  assert.equal(calls.length, 0);
});

test("ignored short codes are logged once, by label only", async () => {
  const environment = { ...env, DODDY_ACCESS_CODES: `owner:${CODE},anna:tooshort,bob:alsoshort` };
  const first = await run(request(), { environment });
  const second = await run(request(), { environment });
  const config = first.logs.filter((l) => l.event === "voice_token_config");
  assert.deepEqual(config, [{ event: "voice_token_config", ignoredShortCodes: ["anna", "bob"] }]);
  assert.ok(!JSON.stringify(first.logs).includes("tooshort"));
  assert.equal(second.logs.filter((l) => l.event === "voice_token_config").length, 0);
  assert.deepEqual(ignoredShortCodes(`a:${CODE},b:x`), ["b"]);
});
