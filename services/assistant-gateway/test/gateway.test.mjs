import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createGateway } from "../src/server.mjs";
import { createSessionLimiter } from "../src/limiter.mjs";
import { verifyModelReply } from "../src/verify.mjs";

// These tests stub the provider with a fake fetch. They exercise the gateway's own behaviour only;
// they do NOT show that the real OpenAI API responds. That needs a live run with a real key.
const TOKEN = "t".repeat(40);
const KEY = "sk-test-not-real-0000000000";
const MODEL = "test-model";

function fakeProvider(content, { status = 200 } = {}) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    if (status !== 200) return new Response("{}", { status });
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
  };
  return { fetchImpl, calls };
}

async function start(options) {
  const logs = [];
  const server = createGateway({ token: TOKEN, apiKey: KEY, model: MODEL, log: (l) => logs.push(l), ...options });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  return {
    base,
    logs,
    close: () => new Promise((r) => server.close(r)),
  };
}

function validBody(overrides = {}) {
  return {
    sessionId: randomUUID(),
    requestId: randomUUID(),
    taskType: "memory_answer",
    locale: "en",
    prompt: "What is my locker code?",
    turns: [],
    memories: [{ id: "m1", currentText: "My locker code is 412.", source: "typed" }],
    ...overrides,
  };
}

async function post(base, body, { token = TOKEN } = {}) {
  const res = await fetch(`${base}/v1/assist`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  return { status: res.status, text: await res.text() };
}

test("refuses to build without a strong token", () => {
  assert.throws(() => createGateway({ token: "short", apiKey: KEY, model: MODEL }), /GATEWAY_TOKEN/);
});

test("rejects requests without the gateway token and never reaches the provider", async () => {
  const provider = fakeProvider("{}");
  const g = await start({ fetchImpl: provider.fetchImpl });
  try {
    const r = await post(g.base, validBody(), { token: "wrong" });
    assert.equal(r.status, 401);
    assert.equal(provider.calls.length, 0);
  } finally {
    await g.close();
  }
});

test("rejects contract violations with badRequest", async () => {
  const provider = fakeProvider("{}");
  const g = await start({ fetchImpl: provider.fetchImpl });
  try {
    assert.equal((await post(g.base, validBody({ sessionId: "not-a-uuid" }))).status, 400);
    assert.equal((await post(g.base, validBody({ taskType: "export_everything" }))).status, 400);
    assert.equal((await post(g.base, validBody({ prompt: "   " }))).status, 400);
    assert.equal((await post(g.base, validBody({ memories: [{ id: "a", currentText: "x", source: "" }, { id: "a", currentText: "y", source: "" }] }))).status, 400);
    assert.equal((await post(g.base, "{not json")).status, 400);
    assert.equal(provider.calls.length, 0);
  } finally {
    await g.close();
  }
});

test("memory question with no matching notes answers noMatch without calling the model", async () => {
  const provider = fakeProvider("{}");
  const g = await start({ fetchImpl: provider.fetchImpl });
  try {
    const r = await post(g.base, validBody({ memories: [] }));
    assert.equal(r.status, 200);
    const json = JSON.parse(r.text);
    assert.equal(json.noMatch, true);
    assert.equal(json.answer, null);
    assert.equal(provider.calls.length, 0);
  } finally {
    await g.close();
  }
});

test("valid memory answer returns the model text and cited ids, sent with the server-side key", async () => {
  const reply = JSON.stringify({ answer: "Your locker code is 412.", citedIds: ["m1"] });
  const provider = fakeProvider(reply);
  const g = await start({ fetchImpl: provider.fetchImpl });
  try {
    const r = await post(g.base, validBody());
    assert.equal(r.status, 200);
    const json = JSON.parse(r.text);
    assert.equal(json.answer, "Your locker code is 412.");
    assert.deepEqual(json.citedIds, ["m1"]);
    assert.equal(json.noMatch, false);

    assert.equal(provider.calls.length, 1);
    const sent = provider.calls[0];
    assert.equal(sent.init.headers.authorization, `Bearer ${KEY}`);
    assert.equal(sent.body.model, MODEL);
    assert.equal(sent.body.response_format.type, "json_object");
    assert.ok(sent.body.messages.at(-1).content.includes("My locker code is 412."));
    // The key must never appear in anything the client receives.
    assert.ok(!r.text.includes(KEY));
  } finally {
    await g.close();
  }
});

test("a citation to an id that was not sent fails the reply with invalidCitations", async () => {
  const provider = fakeProvider(JSON.stringify({ answer: "Found it.", citedIds: ["made-up-id"] }));
  const g = await start({ fetchImpl: provider.fetchImpl });
  try {
    const r = await post(g.base, validBody());
    assert.equal(r.status, 502);
    assert.equal(JSON.parse(r.text).error, "invalidCitations");
    assert.ok(!r.text.includes("Found it."), "unverified answer must not reach the client");
  } finally {
    await g.close();
  }
});

test("malformed model output is invalidResponse, not a guessed answer", async () => {
  const g = await start({ fetchImpl: fakeProvider("here is some prose").fetchImpl });
  try {
    const r = await post(g.base, validBody());
    assert.equal(r.status, 502);
    assert.equal(JSON.parse(r.text).error, "invalidResponse");
  } finally {
    await g.close();
  }
});

test("provider 429 maps to rateLimited and other provider failures to providerUnavailable", async () => {
  const limited = await start({ fetchImpl: fakeProvider("{}", { status: 429 }).fetchImpl });
  const down = await start({ fetchImpl: fakeProvider("{}", { status: 500 }).fetchImpl });
  try {
    assert.equal((await post(limited.base, validBody())).status, 429);
    const r = await post(down.base, validBody());
    assert.equal(r.status, 503);
    assert.equal(JSON.parse(r.text).error, "providerUnavailable");
  } finally {
    await limited.close();
    await down.close();
  }
});

test("a slow provider times out as timeout (504)", async () => {
  const hangs = async (url, init) =>
    new Promise((_, reject) => {
      init.signal.addEventListener("abort", () => reject(Object.assign(new Error("aborted"), { name: "AbortError" })));
    });
  const g = await start({ fetchImpl: hangs, timeoutMs: 50 });
  try {
    const r = await post(g.base, validBody());
    assert.equal(r.status, 504);
    assert.equal(JSON.parse(r.text).error, "timeout");
  } finally {
    await g.close();
  }
});

test("without a provider key the gateway answers providerUnavailable and never calls out", async () => {
  const provider = fakeProvider("{}");
  const g = await start({ fetchImpl: provider.fetchImpl, apiKey: "" });
  try {
    const r = await post(g.base, validBody());
    assert.equal(r.status, 503);
    assert.equal(provider.calls.length, 0);
  } finally {
    await g.close();
  }
});

test("per-session rate limit returns rateLimited once the window is full", async () => {
  const provider = fakeProvider(JSON.stringify({ answer: "ok", citedIds: [] }));
  const g = await start({ fetchImpl: provider.fetchImpl, limiter: createSessionLimiter({ maxRequests: 2 }) });
  try {
    const body = validBody();
    assert.equal((await post(g.base, body)).status, 200);
    assert.equal((await post(g.base, body)).status, 200);
    assert.equal((await post(g.base, body)).status, 429);
  } finally {
    await g.close();
  }
});

test("logs are content-free: no note text, question text or key", async () => {
  const provider = fakeProvider(JSON.stringify({ answer: "The code is 412.", citedIds: ["m1"] }));
  const g = await start({ fetchImpl: provider.fetchImpl });
  try {
    await post(g.base, validBody({ prompt: "PRIVATE-QUESTION-XYZ" }));
    assert.ok(g.logs.length >= 1);
    const joined = g.logs.join("\n");
    assert.ok(!joined.includes("PRIVATE-QUESTION-XYZ"));
    assert.ok(!joined.includes("My locker code is 412."));
    assert.ok(!joined.includes("The code is 412."));
    assert.ok(!joined.includes(KEY));
  } finally {
    await g.close();
  }
});

test("verifyModelReply keeps only allowed citations and caps answer length", () => {
  const ok = verifyModelReply(JSON.stringify({ answer: "a".repeat(3000), citedIds: ["m1", "m1"] }), ["m1"]);
  assert.equal([...ok.answer].length, 2000);
  assert.deepEqual(ok.citedIds, ["m1"]);
  assert.throws(() => verifyModelReply(JSON.stringify({ answer: "x", citedIds: ["m2"] }), ["m1"]), /invalidCitations/);
});
