// GET /v1/health (engineering audit, 7 Nov 2026; status only since 12 Nov 2026): it asks the database, so a
// server whose database is gone answers 503 instead of a static "ok", and it answers with its status alone.
// The mode moved to the signed-in GET /v1/server; the running commit to the start log (server.ts).
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { HealthSchema, ServerInfoSchema } from "../src/contracts.js";
import { listeningLine } from "../src/startLine.js";
import { harness, type Harness } from "./helpers.js";

let h: Harness | undefined;
afterEach(async () => {
  await h?.close();
  h = undefined;
});

test("health is 200 with the database answering, and says only that", async () => {
  h = await harness({ health: { ping: async () => {} } });
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { status: "ok" }, "no mode, version, commit, capabilities or database detail");
  assert.ok(HealthSchema.safeParse(res.body).success);
});

test("health is 503 when the database refuses, and says only that", async () => {
  h = await harness({ health: { ping: async () => { throw new Error("connect ECONNREFUSED 10.0.0.5:5432"); } } });
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 503);
  assert.deepEqual(res.body, { status: "unavailable" });
  assert.ok(!res.text.includes("ECONNREFUSED") && !res.text.includes("10.0.0.5"), "the database error never reaches the caller");
  assert.ok(HealthSchema.safeParse(res.body).success);
});

test("health is 503 when the database doesn't answer within 3 seconds", { timeout: 10_000 }, async () => {
  h = await harness({ health: { ping: () => new Promise<void>(() => {}) } });
  const started = Date.now();
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 503);
  assert.deepEqual(res.body, { status: "unavailable" });
  assert.ok(Date.now() - started < 6_000);
});

test("health without a database check is 200 with its status only", async () => {
  h = await harness();
  const res = await h.call("GET", "/v1/health", { token: null });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { status: "ok" });
});

test("the server's mode is told only to a signed-in caller", async () => {
  h = await harness();
  const anonymous = await h.call("GET", "/v1/server", { token: null });
  assert.equal(anonymous.status, 401);
  assert.equal(anonymous.text.includes("mock"), false);
  const signedIn = await h.call("GET", "/v1/server");
  assert.equal(signedIn.status, 200);
  assert.deepEqual(signedIn.body, { mode: "mock" });
  assert.ok(ServerInfoSchema.safeParse(signedIn.body).success);
});

test("the start log names the running commit for whoever reads the logs", () => {
  const config = { host: "0.0.0.0", port: 10000, mode: "live", authMode: "signed", env: "development", web: null, ownerClaim: "closed" } as const;
  const line = JSON.parse(listeningLine(config, "postgres", { RENDER_GIT_COMMIT: "0123456789abcdef0123" }));
  assert.equal(line.event, "listening");
  assert.equal(line.mode, "live");
  assert.equal(line.commit, "0123456789ab");
  assert.equal(JSON.parse(listeningLine(config, "postgres", {})).commit, null);
});

test("the real store answers the ping", async () => {
  h = await harness();
  await h.store.ping();
});
