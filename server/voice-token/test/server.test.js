import assert from "node:assert/strict";
import { test } from "node:test";
import { createTokenServer } from "../server.js";

async function withServer(handle, run) {
  const server = createTokenServer({ env: { marker: "env" }, handle });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = /** @type {import("node:net").AddressInfo} */ (server.address());
  try {
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("passes method, headers, body and env to the handler and returns its response", async () => {
  let seen;
  const handle = async (request, env) => {
    seen = { method: request.method, auth: request.headers.get("authorization"), body: await request.text(), env };
    return Response.json({ token: "t" }, { status: 200, headers: { "cache-control": "no-store" } });
  };
  await withServer(handle, async (base) => {
    const res = await fetch(`${base}/api/voice-token`, {
      method: "POST",
      headers: { authorization: "Bearer code", "content-type": "application/json" },
      body: '{"provider":"openai"}',
    });
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("cache-control"), "no-store");
    assert.deepEqual(await res.json(), { token: "t" });
  });
  assert.deepEqual(seen, { method: "POST", auth: "Bearer code", body: '{"provider":"openai"}', env: { marker: "env" } });
});

test("a POST without a body reaches the handler with an empty body", async () => {
  let body;
  const handle = async (request) => { body = await request.text(); return Response.json({ error: "x" }, { status: 401 }); };
  await withServer(handle, async (base) => {
    const res = await fetch(`${base}/api/voice-token`, { method: "POST" });
    assert.equal(res.status, 401);
  });
  assert.equal(body, "");
});

test("health check, unknown paths and oversized bodies never reach the handler", async () => {
  let calls = 0;
  const handle = async () => { calls += 1; return new Response(null, { status: 204 }); };
  await withServer(handle, async (base) => {
    const health = await fetch(`${base}/healthz`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { ok: true });
    assert.equal((await fetch(`${base}/other`, { method: "POST" })).status, 404);
    const big = await fetch(`${base}/api/voice-token`, { method: "POST", body: "x".repeat(5000) });
    assert.equal(big.status, 413);
  });
  assert.equal(calls, 0);
});

test("a handler that throws gives a content-free 500", async () => {
  const handle = async () => { throw new Error("secret detail"); };
  await withServer(handle, async (base) => {
    const res = await fetch(`${base}/api/voice-token`, { method: "POST" });
    assert.equal(res.status, 500);
    assert.deepEqual(await res.json(), { error: "unexpected" });
  });
});
