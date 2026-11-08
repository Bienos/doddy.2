// GET /v1/health (engineering audit, 7 Nov 2026): it asks the database and names the running commit, so
// a server whose database is gone answers 503 instead of a static "ok", and "what is live" is one request.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { harness, type Harness } from "./helpers.js";

let h: Harness | undefined;
afterEach(async () => {
  await h?.close();
  h = undefined;
});

test("health is 200 with the database answering, and names the commit", async () => {
  h = await harness({ health: { ping: async () => {}, commit: "0123456789ab" } });
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 200);
  const body = res.body as Record<string, unknown>;
  assert.equal(body.status, "ok");
  assert.equal(body.database, "ok");
  assert.equal(body.commit, "0123456789ab");
  assert.deepEqual(body.capabilities, ["calendar.listEvents"]);
});

test("health is 503 when the database refuses, and says only that", async () => {
  h = await harness({ health: { ping: async () => { throw new Error("connect ECONNREFUSED 10.0.0.5:5432"); } } });
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 503);
  const body = res.body as Record<string, unknown>;
  assert.equal(body.status, "unavailable");
  assert.equal(body.database, "unavailable");
  assert.ok(!res.text.includes("ECONNREFUSED") && !res.text.includes("10.0.0.5"), "the database error never reaches the caller");
  assert.equal("commit" in body, false);
});

test("health is 503 when the database doesn't answer within 3 seconds", { timeout: 10_000 }, async () => {
  h = await harness({ health: { ping: () => new Promise<void>(() => {}) } });
  const started = Date.now();
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 503);
  assert.ok(Date.now() - started < 6_000);
});

test("health without a database check stays as before", async () => {
  h = await harness();
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 200);
  const body = res.body as Record<string, unknown>;
  assert.equal(body.status, "ok");
  assert.equal("database" in body, false);
});

test("the real store answers the ping", async () => {
  h = await harness();
  await h.store.ping();
});
