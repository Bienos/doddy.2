import assert from "node:assert/strict";
import { test } from "node:test";
import { createApp } from "../server.js";

/** Starts the Render host on a free port, runs `fn` with its base URL, then closes it. */
async function withServer(routes, fn) {
  const server = createApp(routes);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = /** @type {import("node:net").AddressInfo} */ (server.address());
  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("health check answers 200 and unknown paths 404", async () => {
  await withServer(undefined, async (base) => {
    assert.equal((await fetch(`${base}/healthz`)).status, 200);
    assert.equal((await fetch(`${base}/nope`)).status, 404);
  });
});

test("the real route reaches the handler, which refuses GET with Allow: POST", async () => {
  await withServer(undefined, async (base) => {
    const res = await fetch(`${base}/api/voice-token`);
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("allow"), "POST");
  });
});

test("method, headers and body reach the route unchanged", async () => {
  const routes = {
    "/api/voice-token": async (request) =>
      Response.json({ method: request.method, auth: request.headers.get("authorization"), body: await request.json() }),
  };
  await withServer(routes, async (base) => {
    const res = await fetch(`${base}/api/voice-token`, {
      method: "POST",
      headers: { authorization: "Bearer code-0001", "content-type": "application/json" },
      body: JSON.stringify({ provider: "openai" }),
    });
    assert.deepEqual(await res.json(), { method: "POST", auth: "Bearer code-0001", body: { provider: "openai" } });
  });
});

test("a route that throws becomes a 500 without its message", async () => {
  const routes = { "/api/voice-token": () => { throw new Error("secret detail"); } };
  await withServer(routes, async (base) => {
    const res = await fetch(`${base}/api/voice-token`, { method: "POST" });
    assert.equal(res.status, 500);
    assert.doesNotMatch(await res.text(), /secret detail/);
  });
});
