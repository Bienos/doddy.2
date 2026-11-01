import assert from "node:assert/strict";
import { after, test } from "node:test";
import { handleTokenRequest } from "../src/handler.js";
import { createVoiceAuthStore, VoiceAuthStoreUnavailable } from "../src/voice-auth.js";
import { startRedis } from "./redisBridge.js";

// The hourly limits on /api/voice-token (ADR-670): an account over its own limit must not use up
// the shared allowance, so one signed-in account can't block voice for everyone else.

const redis = await startRedis();
after(() => redis?.stop());
const noRedis = redis ? false : "no redis-server on the PATH and no TEST_REDIS_URL";

// A window of its own on every run, so a shared TEST_REDIS_URL never sees an earlier run's counts.
const NOW = Date.parse("2026-10-16T12:00:00Z") + Math.floor(Math.random() * 1_000_000) * 3_600_000;
const HOUR = Math.floor(NOW / 3_600_000);
const id = (name) => `${name}-${Math.random().toString(36).slice(2)}`;
const realStore = () => createVoiceAuthStore({ url: "https://redis.example.test", token: "store-secret", fetch: redis.fetch });

test("the adapter sends both limits to the script and allows only what the script granted", async () => {
  let sent;
  let reply = [{ result: [3, 7, 1] }];
  const store = createVoiceAuthStore({
    url: "https://redis.example.test", token: "store-secret",
    fetch: async (_url, init) => { sent = JSON.parse(init.body); return Response.json(reply); },
  });
  assert.deepEqual(await store.hitLimits("user", 30, 100, NOW), {
    allowed: true, perUserCount: 3, globalCount: 7, retryAfterSeconds: (HOUR + 1) * 3_600 - Math.floor(NOW / 1_000),
  });
  const [command] = sent;
  assert.equal(command[0], "EVAL");
  assert.deepEqual(command.slice(2), ["2", `doddy:voice:v1:limit-user:user:${HOUR}`, `doddy:voice:v1:limit-global:${HOUR}`, "3660", "30", "100"]);
  reply = [{ result: [30, 7, 0] }];
  assert.equal((await store.hitLimits("user", 30, 100, NOW)).allowed, false);
  // An answer of the old shape, or anything else, fails closed instead of guessing.
  for (const odd of [[3, 7], [3, 7, 2], ["x", 7, 1], null]) {
    reply = [{ result: odd }];
    await assert.rejects(() => store.hitLimits("user", 30, 100, NOW), VoiceAuthStoreUnavailable);
  }
});

test("Redis: an account over its own limit moves neither counter; others keep the shared allowance", { skip: noRedis }, async () => {
  const store = realStore();
  const [heavy, second, third] = [id("heavy"), id("second"), id("third")];
  const results = [];
  for (let i = 0; i < 10; i += 1) results.push((await store.hitLimits(heavy, 3, 5, NOW)).allowed);
  assert.deepEqual(results, [true, true, true, false, false, false, false, false, false, false]);
  const global = `doddy:voice:v1:limit-global:${HOUR}`;
  assert.equal(await redis.command(["GET", global]), "3", "the seven refused calls took nothing from the shared allowance");
  assert.equal(await redis.command(["GET", `doddy:voice:v1:limit-user:${heavy}:${HOUR}`]), "3");

  assert.equal((await store.hitLimits(second, 3, 5, NOW)).allowed, true);
  assert.equal((await store.hitLimits(second, 3, 5, NOW)).allowed, true);
  // The shared allowance is used up now: a third account is refused, and its own count stays at zero.
  const refused = await store.hitLimits(third, 3, 5, NOW);
  assert.equal(refused.allowed, false);
  assert.equal(refused.globalCount, 5);
  assert.equal(await redis.command(["GET", `doddy:voice:v1:limit-user:${third}:${HOUR}`]), null);
  assert.equal(await redis.command(["GET", global]), "5");

  // Both counters expire a minute after their hour.
  const ttl = await redis.command(["TTL", global]);
  assert.ok(ttl > 3_600 && ttl <= 3_660, `ttl ${ttl}`);
  assert.ok((await redis.command(["TTL", `doddy:voice:v1:limit-user:${heavy}:${HOUR}`])) > 3_600);
  // The next hour starts from zero.
  assert.equal((await store.hitLimits(heavy, 3, 5, NOW + 3_600_000)).allowed, true);
});

test("Redis, end to end: 100 calls from one account in an hour leave voice working for another", { skip: noRedis }, async () => {
  const store = realStore();
  const [heavy, other] = [id("heavy"), id("other")];
  const env = { ELEVENLABS_API_KEY: "elevenlabs-server-secret", ELEVENLABS_AGENT_ID: "agent_test" };
  // The default limits: 30 per account, 100 for the whole service, per hour.
  const call = (userId) => handleTokenRequest(new Request("https://example.test/api/voice-token", { method: "POST" }), env, {
    authStore: store,
    authenticateSession: async () => ({ userId, sessionId: "s" }),
    fetch: async () => Response.json({ token: "conversation-token" }),
    log: () => {},
    now: () => NOW + 2 * 3_600_000, // an hour no other test here counts in
  });
  const statuses = [];
  for (let i = 0; i < 100; i += 1) statuses.push((await call(heavy)).status);
  assert.equal(statuses.filter((s) => s === 200).length, 30);
  assert.equal(statuses.filter((s) => s === 429).length, 70);
  const response = await call(other);
  assert.equal(response.status, 200, "another account still gets a voice token");
  assert.deepEqual(await response.json(), { token: "conversation-token" });
});
