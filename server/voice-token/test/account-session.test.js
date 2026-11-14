// One token per server (decision 2026-11-12-one-token-per-server, item 1 "Voice server" and item 3): a Doddy account's
// Supabase token is exchanged once, at `POST /api/voice-auth` `account-session`, for this server's own 10-minute access
// token and rotating 30-day refresh token, bound to the account (`account:<id>`), the same kind it already makes for an
// Apple voice account. `/api/voice-token` takes those and, for this release, the Supabase token too.
//
// The scenarios run against an in-memory store and, when redis-server is installed, against the real scripts on a
// local Redis (test/local-redis.js), so the two are held to each other. Everything here is made up: the Supabase
// project, its keys, the account ids and every token are fake, and none was ever a real credential.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { test } from "node:test";
import { handleTokenRequest } from "../src/handler.js";
import { keyRingFromEnv } from "../src/keys.js";
import {
  handleVoiceAuthRequest, openAppleToken, sealAppleToken, signAccessToken, verifyAccessToken, VoiceAuthStoreUnavailable,
} from "../src/voice-auth.js";
import { AccountCheckUnavailable } from "../src/doddy-account.js";
import { fakeConversationStore, fakeElevenLabs } from "./conversation-fakes.js";
import { modelLimitsStore } from "./limits-model.js";
import { hasRedis, withLocalRedis } from "./local-redis.js";

const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const SUB = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const SUB_B = "7c1d9a8f-3b52-4d4e-8f70-1234567890bc";
const SUB_C = "9d2e0b9a-4c63-4e5f-9a81-2345678901cd";
const ACCOUNT = `account:${SUB}`;
const ACCOUNT_B = `account:${SUB_B}`;
const NOW = 1_794_000_000_000;
const NOW_S = Math.floor(NOW / 1000);
const SIGNING_KEY = "session-signing-secret-for-tests-000000000000";
const CALLER = "203.0.113.7";
const PREFIX = "doddy:voice:v1:";
const DAY = 86_400;
const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev", DODDY_SESSION_SIGNING_KEY: SIGNING_KEY,
  ELEVENLABS_API_KEY: "elevenlabs-test-not-real", ELEVENLABS_AGENT_ID: "agent_test",
  SUPABASE_URL: PROJECT,
  // Vercel sets this itself; the caller's address is only trusted from Vercel's header (ADR-712).
  VERCEL: "1",
};
const APPLE_ENV = { ...ENV, APPLE_TEAM_ID: "TEAMID1234", APPLE_SIGN_IN_KEY_ID: "KEYID12345", APPLE_SIGN_IN_PRIVATE_KEY: "not-a-real-key" };

// ---- a fake Supabase project --------------------------------------------------------------------------------------

const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const stranger = generateKeyPairSync("ec", { namedCurve: "P-256" });
const b64 = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

/** A Doddy account's access token as the project makes them: ES256, issuer, audience, made with Apple, Google or a code. */
function accountToken(sub = SUB, claims = {}, key = ec.privateKey) {
  const header = b64({ alg: "ES256", kid: "k1", typ: "JWT" });
  const body = b64({
    iss: ISSUER, aud: "authenticated", role: "authenticated", sub, iat: NOW_S - 10, exp: NOW_S + 3600,
    is_anonymous: false, app_metadata: { provider: "apple", providers: ["apple"] }, amr: [{ method: "id_token", timestamp: NOW_S - 10 }],
    ...claims,
  });
  const signature = sign("sha256", Buffer.from(`${header}.${body}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${signature.toString("base64url")}`;
}

/** The project's published keys, as a fetch the server reads them with. */
function jwks() {
  const state = { fail: false };
  const fetch = async () => {
    if (state.fail) throw new Error("unreachable");
    return Response.json({ keys: [{ ...ec.publicKey.export({ format: "jwk" }), kid: "k1", alg: "ES256", use: "sig" }] });
  };
  return { state, fetch };
}

// ---- the store, in memory: the same contract as the Redis one ------------------------------------------------------

function memoryStore() {
  const sessions = new Map();
  const refresh = new Map();
  const nonces = new Set();
  const buckets = new Map();
  const appleTokens = new Map();
  const endSession = (session) => {
    sessions.delete(session.sessionId);
    refresh.delete(session.refreshHash);
    if (session.previousRefreshHash) refresh.delete(session.previousRefreshHash);
  };
  return {
    ...fakeConversationStore(),
    ...modelLimitsStore(),
    sessions, refresh, buckets, appleTokens,
    async createSession(input) {
      const guarded = typeof input.nonceHash === "string";
      if ((guarded && nonces.has(input.nonceHash)) || refresh.has(input.refreshHash)) return 0;
      if (guarded) nonces.add(input.nonceHash);
      sessions.set(input.sessionId, { userId: input.userId, sessionId: input.sessionId, refreshHash: input.refreshHash });
      refresh.set(input.refreshHash, { userId: input.userId, sessionId: input.sessionId });
      return 1;
    },
    async getRefresh(hash) { return refresh.get(hash) ?? null; },
    async getSession(id) { return sessions.get(id) ?? null; },
    async rotateRefreshSession(oldHash, newHash, prior) {
      const current = refresh.get(oldHash);
      if (!current || current.userId !== prior.userId || current.sessionId !== prior.sessionId) return null;
      const session = sessions.get(prior.sessionId);
      if (!session) return null;
      if (current.used) { endSession(session); return { reused: true }; }
      if (session.previousRefreshHash) refresh.delete(session.previousRefreshHash);
      refresh.set(newHash, { userId: current.userId, sessionId: current.sessionId });
      refresh.set(oldHash, { ...current, used: true });
      sessions.set(prior.sessionId, { ...session, refreshHash: newHash, previousRefreshHash: oldHash });
      return sessions.get(prior.sessionId);
    },
    async revokeSession(id, userId) {
      const session = sessions.get(id);
      if (!session || session.userId !== userId) return 0;
      endSession(session);
      return 1;
    },
    async revokeUserSessions(userId) {
      let ended = 0;
      for (const session of [...sessions.values()]) if (session.userId === userId) { endSession(session); ended += 1; }
      return ended;
    },
    async deleteAccount(userId) {
      const ended = await this.revokeUserSessions(userId);
      appleTokens.delete(userId);
      return ended;
    },
    async hitSignInLimits(bucket, perHour, perDay) {
      const entry = buckets.get(bucket) ?? { hour: 0, day: 0 };
      const limit = entry.hour >= perHour ? "client_hour" : entry.day >= perDay ? "client_day" : null;
      if (limit) return { allowed: false, limit, retryAfterSeconds: limit === "client_day" ? 3_600 : 60 };
      buckets.set(bucket, { hour: entry.hour + 1, day: entry.day + 1 });
      return { allowed: true, limit: null, retryAfterSeconds: 60 };
    },
    async setAppleToken(userId, sealed) { appleTokens.set(userId, sealed); },
    async getAppleToken(userId) { return appleTokens.get(userId) ?? null; },
    async deleteAppleToken(userId) { appleTokens.delete(userId); },
  };
}

/** Each scenario runs on the memory store, and on a local redis-server when there is one. `command` is a raw Redis command, or null. */
const BACKENDS = [
  ["memory", (body) => body({ store: memoryStore(), command: null }), false],
  ["redis", withLocalRedis, !hasRedis && "redis-server not installed"],
];
function onBackends(name, body, { redisOnly = false } = {}) {
  for (const [label, run, skip] of BACKENDS) {
    if (redisOnly && label !== "redis") continue;
    test(`${name} (${label})`, { skip }, () => run(body));
  }
}

const sessionCount = async ({ store, command }) => (command ? (await command("KEYS", `${PREFIX}session:*`)).length : store.sessions.size);
const refreshCount = async ({ store, command }) => (command ? (await command("KEYS", `${PREFIX}refresh:*`)).length : store.refresh.size);
const bucketCount = async ({ store, command }) => (command ? (await command("KEYS", `${PREFIX}limit-signin*`)).length : store.buckets.size);

// ---- calling the two routes ---------------------------------------------------------------------------------------

async function call(ctx, action, body = {}, { bearer, env = ENV, address = CALLER, now = NOW, keys = jwks(), raw, headers = {}, ...deps } = {}) {
  const logs = [];
  const request = new Request("https://example.test/api/voice-auth", {
    method: "POST",
    headers: {
      "content-type": "application/json", ...(address ? { "x-vercel-forwarded-for": address } : {}),
      ...(bearer ? { authorization: `Bearer ${bearer}` } : {}), ...headers,
    },
    body: raw ?? JSON.stringify({ action, ...body }),
  });
  const response = await handleVoiceAuthRequest(request, env, {
    store: ctx.store, now: () => now, log: (line) => logs.push(line), accountFetch: keys.fetch,
    elevenLabsFetch: fakeElevenLabs({ apiKey: ENV.ELEVENLABS_API_KEY }).fetch, ...deps,
  });
  return { response, body: await response.json(), logs };
}

const mint = (ctx, sub = SUB, options = {}) => call(ctx, "account-session", {}, { bearer: accountToken(sub), ...options });

async function voiceToken(ctx, bearer, { env = ENV, now = NOW, keys = jwks(), upstream = [] } = {}) {
  const logs = [];
  const response = await handleTokenRequest(
    new Request("https://example.test/api/voice-token", { method: "POST", headers: { authorization: `Bearer ${bearer}` } }),
    env,
    {
      authStore: ctx.store, accountFetch: keys.fetch, now: () => now, log: (line) => logs.push(line),
      fetch: async (url) => { upstream.push(String(url)); return Response.json({ token: "provider-credential-not-real", conversation_id: `conv_${upstream.length}` }); },
    },
  );
  return { response, body: await response.json(), logs, upstream };
}

const headerOf = (token) => JSON.parse(Buffer.from(token.split(".")[0], "base64url").toString("utf8"));

// ---- the exchange -------------------------------------------------------------------------------------------------

onBackends("account-session: a valid account token gets the voice server's own session, bound to the account", async (ctx) => {
  const { response, body, logs } = await mint(ctx);
  assert.equal(response.status, 200);
  assert.deepEqual(Object.keys(body).sort(), ["accessToken", "expiresIn", "refreshToken"], "the same reply as an Apple voice sign-in");
  assert.equal(body.expiresIn, 600);
  assert.equal(response.headers.get("cache-control"), "no-store");

  // The access token is this server's own kind: its audience and purpose key, and the id of the key that signed it.
  const claims = verifyAccessToken(body.accessToken, SIGNING_KEY, NOW);
  assert.equal(claims.iss, "doddy-voice");
  assert.equal(claims.aud, "voice");
  assert.equal(claims.sub, ACCOUNT, "the account's own bucket, apart from the Apple voice accounts' ids");
  assert.equal(claims.exp - claims.iat, 600);
  assert.equal(headerOf(body.accessToken).kid, keyRingFromEnv(ENV).current.kid);
  assert.equal(headerOf(body.accessToken).alg, "HS256");

  // It is a session in the same store as an Apple voice account's, found by its refresh token's hash alone.
  const stored = await ctx.store.getSession(claims.sid);
  assert.equal(stored.userId, ACCOUNT);
  assert.equal(stored.sessionId, claims.sid);
  assert.deepEqual(await ctx.store.getRefresh(sha256(body.refreshToken)), { userId: ACCOUNT, sessionId: claims.sid });
  assert.ok(body.refreshToken.length >= 40 && body.refreshToken.length <= 128, "a shape the refresh action reads");
  assert.deepEqual(logs, [{ event: "voice_auth", action: "account-session", status: 200, error: null, ms: 0 }]);
});

onBackends("account-session: a second session for the same account is another session, and neither needs an Apple nonce", async (ctx) => {
  const first = await mint(ctx);
  const second = await mint(ctx);
  assert.equal(first.response.status, 200);
  assert.equal(second.response.status, 200);
  assert.notEqual(first.body.refreshToken, second.body.refreshToken);
  assert.equal(await sessionCount(ctx), 2);
  assert.equal(await refreshCount(ctx), 2);
  if (ctx.command) {
    assert.deepEqual(await ctx.command("KEYS", `${PREFIX}nonce:*`), [], "no replay record: there is no Apple nonce to guard");
    assert.equal((await ctx.command("SMEMBERS", `${PREFIX}user-sessions:${ACCOUNT}`)).length, 2, "both are in the account's list of sessions");
  }
});

onBackends("account-session: everything that is not a Doddy account's own token is refused with the existing answer, and nothing is made or counted", async (ctx) => {
  const voiceAccess = signAccessToken({ userId: "c".repeat(64), sessionId: "sid-not-real" }, SIGNING_KEY, NOW);
  const own = (await mint(ctx)).body.accessToken;
  const afterOwn = [await sessionCount(ctx), await bucketCount(ctx)];
  const refused = {
    "no token": undefined,
    junk: "not-a-token",
    "another project's key": accountToken(SUB, {}, stranger.privateKey),
    expired: accountToken(SUB, { exp: NOW_S }),
    "another audience": accountToken(SUB, { aud: "voice" }),
    "service role": accountToken(SUB, { role: "service_role" }),
    anonymous: accountToken(SUB, { is_anonymous: true }),
    "made with a password": accountToken(SUB, { amr: [{ method: "password" }] }),
    "not a user id": accountToken("apple-sub-123"),
    "a voice session's own access token": voiceAccess,
    "an account-session access token: it cannot mint another session": own,
  };
  for (const [name, bearer] of Object.entries(refused)) {
    const result = await call(ctx, "account-session", {}, { bearer });
    assert.equal(result.response.status, 401, name);
    assert.deepEqual(result.body, { error: "session_expired" }, name);
    assert.deepEqual(result.logs, [{ event: "voice_auth", action: "account-session", status: 401, error: "session_expired", ms: 0 }], name);
  }
  assert.deepEqual([await sessionCount(ctx), await bucketCount(ctx)], afterOwn, "junk makes no session and uses up nobody's allowance");
});

onBackends("account-session: without a Supabase project, or when its keys can't be read, the answer is the neighbours' own", async (ctx) => {
  const { SUPABASE_URL: _unused, ...withoutSupabase } = ENV;
  const off = await mint(ctx, SUB, { env: withoutSupabase });
  assert.deepEqual([off.response.status, off.body], [401, { error: "session_expired" }]);
  const keys = jwks();
  keys.state.fail = true;
  const unreadable = await mint(ctx, SUB, { keys });
  assert.deepEqual([unreadable.response.status, unreadable.body], [503, { error: "account_check_unavailable" }], "try again, never 'signed out'");
  const viaDependency = await call(ctx, "account-session", {}, {
    bearer: "x", authenticateDoddyAccount: async () => { throw new AccountCheckUnavailable(); },
  });
  assert.equal(viaDependency.response.status, 503);
  assert.equal(await sessionCount(ctx), 0);
});

onBackends("account-session: a server that can't issue voice tokens, or has no keys, makes no session", async (ctx) => {
  for (const env of [
    { ...ENV, ELEVENLABS_API_KEY: "" }, { ...ENV, ELEVENLABS_AGENT_ID: " " },
    { ...ENV, DODDY_SESSION_SIGNING_KEY: "too-short" }, { ...ENV, DODDY_SESSION_SIGNING_KEY: undefined },
  ]) {
    const result = await mint(ctx, SUB, { env });
    assert.deepEqual([result.response.status, result.body], [503, { error: "server_not_configured" }]);
  }
  assert.equal(await sessionCount(ctx), 0);
  assert.equal(await bucketCount(ctx), 0);
});

// ---- the same limits as its neighbours ----------------------------------------------------------------------------

onBackends("account-session: limited per account, like apple-link, and a refused call makes nothing", async (ctx) => {
  for (let n = 1; n <= 10; n += 1) assert.equal((await mint(ctx, SUB, { address: `198.51.100.${n}` })).response.status, 200, `call ${n}`);
  const refused = await mint(ctx, SUB, { address: "198.51.100.50" });
  assert.equal(refused.response.status, 429);
  assert.deepEqual(refused.body, { error: "rate_limited" });
  assert.match(refused.response.headers.get("retry-after"), /^[1-9][0-9]*$/);
  assert.deepEqual(refused.logs, [{ event: "voice_auth", action: "account-session", status: 429, error: "rate_limited", ms: 0, limit: "client_hour" }]);
  assert.equal(await sessionCount(ctx), 10);
  // Another account is not affected.
  assert.equal((await mint(ctx, SUB_B, { address: "198.51.100.51" })).response.status, 200);
});

onBackends("account-session: limited per caller address, like a sign-in, and one account can't use up a shared address for the others", async (ctx) => {
  const accounts = Array.from({ length: 11 }, (_, n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`);
  for (const sub of accounts.slice(0, 10)) assert.equal((await mint(ctx, sub, { address: "198.51.100.1" })).response.status, 200);
  const refused = await mint(ctx, accounts[10], { address: "198.51.100.1" });
  assert.equal(refused.response.status, 429);
  assert.equal(refused.logs[0].limit, "client_hour");
  assert.equal(await sessionCount(ctx), 10, "no session for a refused call");
  assert.equal((await mint(ctx, accounts[10], { address: "198.51.100.2" })).response.status, 200, "another address is not affected");
  // Its own bucket: sign-ins from the same address are neither counted here nor refused by it.
  const signIn = await call(ctx, "sign-in", { identityToken: "id", rawNonce: "A".repeat(43), provider: "elevenlabs" }, {
    address: "198.51.100.1", verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: "apple-sub-test", nonce: rawNonce }),
  });
  assert.equal(signIn.response.status, 200);
  // The setting is the sign-ins': a daily limit can be set, and it is a whole number or the server says so.
  const daily = { ...ENV, DODDY_SIGNINS_PER_CLIENT_HOUR: "100", DODDY_SIGNINS_PER_CLIENT_DAY: "1" };
  assert.equal((await mint(ctx, SUB_B, { address: "198.51.100.3", env: daily })).response.status, 200);
  const day = await mint(ctx, SUB_C, { address: "198.51.100.3", env: daily });
  assert.equal(day.response.status, 429);
  assert.equal(day.logs[0].limit, "client_day");
  for (const bad of ["ten", "0", "10001", "2.5"]) {
    const result = await mint(ctx, SUB_C, { address: "198.51.100.4", env: { ...ENV, DODDY_SIGNINS_PER_CLIENT_HOUR: bad } });
    assert.deepEqual([result.response.status, result.body], [503, { error: "server_not_configured" }], bad);
  }
});

onBackends("account-session: only the address Vercel sets is believed; otherwise every caller shares one bucket with a higher limit", async (ctx) => {
  const subs = Array.from({ length: 21 }, (_, n) => `11111111-0000-4000-8000-${String(n).padStart(12, "0")}`);
  const env = { ...ENV, DODDY_SIGNINS_PER_CLIENT_HOUR: "2" };
  for (const [n, sub] of subs.slice(0, 20).entries()) {
    // A header any caller can set is ignored, so no new allowance comes of changing it.
    const result = await mint(ctx, sub, { env, address: null, headers: { "x-forwarded-for": `192.0.2.${n}` } });
    assert.equal(result.response.status, 200, `the shared bucket allows ten times the limit (${n + 1})`);
    assert.equal(result.logs[0].noClientAddress, true, "and the log line says there was no address to use");
  }
  const spoofed = await mint(ctx, subs[20], { env, address: null, headers: { "x-forwarded-for": "192.0.2.99" } });
  assert.equal(spoofed.response.status, 429);
  assert.equal(spoofed.logs[0].noClientAddress, true);
  const offVercel = await mint(ctx, subs[20], { env: { ...env, VERCEL: undefined }, address: "192.0.2.77" });
  assert.equal(offVercel.response.status, 429, "off Vercel the header is not believed either: the same shared bucket");
});

onBackends("account-session: a call the limits can't be checked for is refused, never let through", async (ctx) => {
  const broken = { ...ctx, store: { ...ctx.store, async hitSignInLimits() { throw new VoiceAuthStoreUnavailable(); } } };
  const result = await mint(broken);
  assert.deepEqual([result.response.status, result.body], [503, { error: "server_not_configured" }]);
  const missing = { ...ctx, store: { ...ctx.store, hitSignInLimits: undefined } };
  assert.equal((await mint(missing)).response.status, 503);
  assert.equal(await sessionCount(ctx), 0);
});

onBackends("account-session: the neighbours' size, method and body rules apply, and nothing is checked before them", async (ctx) => {
  let checked = 0;
  const spy = async () => { checked += 1; return { userId: ACCOUNT, sessionId: null }; };
  const big = JSON.stringify({ action: "account-session", padding: "x".repeat(24_100) });
  const oversized = await call(ctx, "account-session", {}, { bearer: "t", raw: big, authenticateDoddyAccount: spy });
  assert.deepEqual([oversized.response.status, oversized.body], [400, { error: "invalid_request" }]);
  const declared = await call(ctx, "account-session", {}, { bearer: "t", raw: "{}", headers: { "content-length": "99999" }, authenticateDoddyAccount: spy });
  assert.equal(declared.response.status, 400);
  const notJson = await call(ctx, "account-session", {}, { bearer: "t", raw: "{", authenticateDoddyAccount: spy });
  assert.equal(notJson.response.status, 400);
  assert.equal(checked, 0, "the account's token was not even checked");
  const get = await handleVoiceAuthRequest(new Request("https://example.test/api/voice-auth", { method: "GET" }), ENV, { store: ctx.store, log: () => {} });
  assert.equal(get.status, 405);
  assert.equal(get.headers.get("allow"), "POST");
  assert.equal(await sessionCount(ctx), 0);
});

// ---- /api/voice-token: both kinds of token, one account -----------------------------------------------------------

onBackends("voice-token takes the new access token and, this release, the Supabase token too, and both are the same account", async (ctx) => {
  const minted = await mint(ctx);
  const seen = [];
  const original = ctx.store.hitLimits;
  ctx.store.hitLimits = async (userId, ...rest) => { seen.push(userId); return original(userId, ...rest); };
  const upstream = [];
  const viaSession = await voiceToken(ctx, minted.body.accessToken, { upstream });
  const viaSupabase = await voiceToken(ctx, accountToken(), { upstream });
  for (const answer of [viaSession, viaSupabase]) {
    assert.equal(answer.response.status, 200);
    assert.equal(answer.body.token, "provider-credential-not-real");
  }
  assert.equal(viaSession.body.userId, viaSupabase.body.userId, "ElevenLabs is given the same keyed id for both, so one person's conversations stay together");
  assert.deepEqual(seen, [ACCOUNT, ACCOUNT], "one bucket, whichever token it came with");
  assert.equal(upstream.length, 2);
  // Which kind it was is a fixed word in the log, so the owner can see when the old kind is no longer used.
  assert.equal(viaSession.logs.at(-1).auth, "account_session");
  assert.equal(viaSupabase.logs.at(-1).auth, "account_token");
});

onBackends("a person is never counted twice, and never escapes counting, by switching the kind of token", async (ctx) => {
  const env = { ...ENV, DODDY_TOKENS_PER_HOUR: "2" };
  const seen = [];
  const original = ctx.store.hitLimits;
  ctx.store.hitLimits = async (userId, ...rest) => { seen.push(userId); return original(userId, ...rest); };
  const orders = {
    [SUB]: ["supabase", "session", "supabase"],
    [SUB_B]: ["session", "session", "supabase"],
    [SUB_C]: ["supabase", "supabase", "session"],
  };
  for (const [sub, order] of Object.entries(orders)) {
    const session = (await mint(ctx, sub, { address: `198.51.100.${sub.charCodeAt(0)}` })).body.accessToken;
    const upstream = [];
    const answers = [];
    for (const kind of order) answers.push(await voiceToken(ctx, kind === "session" ? session : accountToken(sub), { env, upstream }));
    assert.deepEqual(answers.map((answer) => answer.response.status), [200, 200, 429], order.join(", "));
    assert.deepEqual(answers[2].body, { error: "rate_limited" });
    assert.equal(answers[2].logs[0].limit, "user_hour");
    assert.match(answers[2].response.headers.get("retry-after"), /^[1-9][0-9]*$/);
    assert.equal(upstream.length, 2, "the refused one never reached ElevenLabs");
  }
  assert.equal(new Set(seen).size, 3, "three people, three buckets");
  assert.deepEqual(seen.filter((userId) => userId === ACCOUNT), [ACCOUNT, ACCOUNT, ACCOUNT]);
  if (ctx.command) {
    const hour = Math.floor(NOW / 3_600_000);
    assert.equal(await ctx.command("GET", `${PREFIX}limit-user:${ACCOUNT}:${hour}`), "2", "two tokens counted on the account, not four");
    assert.equal((await ctx.command("KEYS", `${PREFIX}first-seen:*`)).length, 3, "one first-seen day per person");
  }
});

onBackends("the other limits see one account too: the new-account day and the pool count the person once, whichever token", async (ctx) => {
  // An account is new when its first token is more than the grace days after the rules started: put the start 30 days back.
  await ctx.command("SET", `${PREFIX}fair-share-started`, String(Math.floor(NOW / 86_400_000) - 30));
  const env = { ...ENV, DODDY_NEW_ACCOUNT_TOKENS_PER_DAY: "2" };
  const session = (await mint(ctx)).body.accessToken;
  const answers = [];
  for (const bearer of [accountToken(), session, accountToken()]) answers.push(await voiceToken(ctx, bearer, { env }));
  assert.deepEqual(answers.map((answer) => answer.response.status), [200, 200, 429]);
  assert.equal(answers[2].logs[0].limit, "new_account_day");
  assert.equal(await ctx.command("GET", `${PREFIX}limit-new-pool:${Math.floor(NOW / 86_400_000)}`), "2", "the pool was used twice, not four times");
}, { redisOnly: true });

onBackends("voice-token refuses what is not a live session: an old kind of token, another account's session, a forged pairing", async (ctx) => {
  const a = (await mint(ctx, SUB)).body;
  const b = (await mint(ctx, SUB_B)).body;
  const sidOfA = verifyAccessToken(a.accessToken, SIGNING_KEY, NOW).sid;
  // Signed by this server, naming A's session but another person: the session's own record says whose it is.
  const mismatched = signAccessToken({ userId: ACCOUNT_B, sessionId: sidOfA }, SIGNING_KEY, NOW);
  const upstream = [];
  for (const [name, bearer] of Object.entries({
    "a session of A, claiming B": mismatched,
    "expired": a.accessToken,
    "no token": "",
  })) {
    const answer = await voiceToken(ctx, bearer, { upstream, now: name === "expired" ? NOW + 11 * 60_000 : NOW });
    assert.equal(answer.response.status, 401, name);
    assert.deepEqual(answer.body, { error: "session_expired" }, name);
  }
  assert.deepEqual(upstream, [], "nothing went to ElevenLabs");
  assert.equal((await voiceToken(ctx, b.accessToken, { upstream })).response.status, 200, "B's own is fine");
});

// ---- refreshing and ending ----------------------------------------------------------------------------------------

onBackends("refresh rotates the account session's refresh token, and an old one coming back ends the session", async (ctx) => {
  const minted = (await mint(ctx)).body;
  const rotated = await call(ctx, "refresh", { refreshToken: minted.refreshToken });
  assert.equal(rotated.response.status, 200);
  assert.notEqual(rotated.body.refreshToken, minted.refreshToken);
  const claims = verifyAccessToken(rotated.body.accessToken, SIGNING_KEY, NOW);
  assert.equal(claims.sub, ACCOUNT, "still the account's");
  assert.equal(claims.sid, verifyAccessToken(minted.accessToken, SIGNING_KEY, NOW).sid, "the same session");
  assert.equal((await voiceToken(ctx, rotated.body.accessToken)).response.status, 200);

  // A swapped-out token coming back means it was copied (ADR-712): the whole session ends, like an Apple voice session.
  const unknown = await call(ctx, "refresh", { refreshToken: "never-issued-".padEnd(43, "x") });
  const replay = await call(ctx, "refresh", { refreshToken: minted.refreshToken });
  assert.equal(replay.response.status, 401);
  assert.deepEqual(replay.body, unknown.body, "the same answer as any dead token");
  assert.equal(replay.logs[0].reuse, true);
  assert.equal((await call(ctx, "refresh", { refreshToken: rotated.body.refreshToken })).response.status, 401, "the newest refresh token is dead too");
  const after = await voiceToken(ctx, rotated.body.accessToken);
  assert.equal(after.response.status, 401, "and so is the access token: its session is gone");
  assert.equal(await sessionCount(ctx), 0);
  assert.equal(await refreshCount(ctx), 0);
});

onBackends("sign-out ends an account session the way it ends an Apple one, and only that session", async (ctx) => {
  const first = (await mint(ctx)).body;
  const second = (await mint(ctx)).body;
  const other = (await mint(ctx, SUB_B, { address: "198.51.100.9" })).body;
  const signedOut = await call(ctx, "sign-out", {}, { bearer: first.accessToken });
  assert.deepEqual([signedOut.response.status, signedOut.body], [200, { signedOut: true }]);
  const refresh = await call(ctx, "refresh", { refreshToken: first.refreshToken });
  assert.equal(refresh.response.status, 401, "ended: its refresh token gives nothing");
  const upstream = [];
  const reused = await voiceToken(ctx, first.accessToken, { upstream });
  assert.equal(reused.response.status, 401, "its access token, still inside its 10 minutes, is refused as well: the session record is gone");
  assert.deepEqual(upstream, []);
  assert.equal((await call(ctx, "refresh", { refreshToken: second.refreshToken })).response.status, 200, "the account's other session is untouched");
  assert.equal((await call(ctx, "refresh", { refreshToken: other.refreshToken })).response.status, 200, "and so is another account's");
  assert.equal((await call(ctx, "sign-out", {}, { bearer: first.accessToken })).response.status, 401, "signing out twice is a plain 401");
});

onBackends("a Supabase token is not a voice session: sign-out and delete-account refuse it", async (ctx) => {
  const minted = (await mint(ctx)).body;
  for (const action of ["sign-out", "delete-account"]) {
    const answer = await call(ctx, action, {}, { bearer: accountToken() });
    assert.deepEqual([answer.response.status, answer.body], [401, { error: "session_expired" }], action);
  }
  assert.equal((await call(ctx, "refresh", { refreshToken: minted.refreshToken })).response.status, 200);
});

onBackends("deleting a voice account with an account session's token ends every session of that account and revokes Apple, and no one else's", async (ctx) => {
  const a1 = (await mint(ctx, SUB)).body;
  const a2 = (await mint(ctx, SUB)).body;
  const b = (await mint(ctx, SUB_B, { address: "198.51.100.9" })).body;
  await ctx.store.setAppleToken(ACCOUNT, sealAppleToken("apple-refresh-not-real", SIGNING_KEY), 400 * DAY);
  const revoked = [];
  const deleted = await call(ctx, "delete-account", {}, {
    bearer: a1.accessToken, env: APPLE_ENV, revokeAppleToken: async (token) => { revoked.push(token); return true; },
  });
  assert.deepEqual([deleted.response.status, deleted.body], [200, { deleted: true, appleRevoked: true, conversations: { deleted: 0, pending: 0 } }]);
  assert.deepEqual(revoked, ["apple-refresh-not-real"]);
  assert.equal(await ctx.store.getAppleToken(ACCOUNT), null);
  for (const token of [a1.refreshToken, a2.refreshToken]) assert.equal((await call(ctx, "refresh", { refreshToken: token })).response.status, 401);
  assert.equal((await call(ctx, "refresh", { refreshToken: b.refreshToken })).response.status, 200, "another account's session lives on");
});

// ---- the Doddy account's deletion ends its sessions ---------------------------------------------------------------

onBackends("delete-conversations, which the app sends first when an account is deleted, also ends the account's voice sessions", async (ctx) => {
  const a1 = (await mint(ctx, SUB)).body;
  const a2 = (await mint(ctx, SUB)).body;
  const rotated = await call(ctx, "refresh", { refreshToken: a2.refreshToken });
  const b = (await mint(ctx, SUB_B, { address: "198.51.100.9" })).body;
  await ctx.store.setAppleToken(ACCOUNT, sealAppleToken("apple-refresh-not-real", SIGNING_KEY), 400 * DAY);
  assert.equal(await sessionCount(ctx), 3);

  const swept = await call(ctx, "delete-conversations", {}, { bearer: accountToken(SUB) });
  assert.deepEqual([swept.response.status, swept.body], [200, { deleted: 0, pending: 0 }], "the answer is the counts it always was");
  assert.equal(await sessionCount(ctx), 1, "only the other account's session is left");
  assert.equal((await call(ctx, "refresh", { refreshToken: a1.refreshToken })).response.status, 401);
  assert.equal((await call(ctx, "refresh", { refreshToken: rotated.body.refreshToken })).response.status, 401, "after a refresh too");
  assert.equal((await voiceToken(ctx, a1.accessToken)).response.status, 401, "an access token of an ended session is refused at once");
  assert.equal((await call(ctx, "refresh", { refreshToken: b.refreshToken })).response.status, 200, "another account's session is untouched");
  assert.notEqual(await ctx.store.getAppleToken(ACCOUNT), null, "the Apple link is apple-revoke's to remove, and stays for it");
  // Asking again is harmless.
  assert.deepEqual((await call(ctx, "delete-conversations", {}, { bearer: accountToken(SUB) })).body, { deleted: 0, pending: 0 });
  // A refused call, with nothing counted and nothing ended: it is limited like the others.
  const fresh = (await mint(ctx, SUB, { address: "198.51.100.20" })).body;
  const env = { ...ENV, DODDY_SIGNINS_PER_CLIENT_HOUR: "1" };
  const refused = await call(ctx, "delete-conversations", {}, { bearer: accountToken(SUB), env });
  assert.equal(refused.response.status, 429);
  assert.equal((await call(ctx, "refresh", { refreshToken: fresh.refreshToken })).response.status, 200, "a refused call ends nothing");
});

onBackends("delete-conversations with the store down is a 503 and ends nothing", async (ctx) => {
  const a = (await mint(ctx, SUB)).body;
  const broken = { ...ctx, store: { ...ctx.store, async revokeUserSessions() { throw new VoiceAuthStoreUnavailable(); } } };
  const answer = await call(broken, "delete-conversations", {}, { bearer: accountToken(SUB) });
  assert.deepEqual([answer.response.status, answer.body], [503, { error: "server_not_configured" }]);
  assert.equal((await call(ctx, "refresh", { refreshToken: a.refreshToken })).response.status, 200);
});

onBackends("apple-link, apple-revoke, delete-conversations and account-session take the Supabase token only, never a session's", async (ctx) => {
  const minted = (await mint(ctx)).body;
  let appleCalled = false;
  for (const action of ["apple-link", "apple-revoke", "delete-conversations", "account-session"]) {
    const answer = await call(ctx, action, { identityToken: "id", rawNonce: "A".repeat(43), authorizationCode: "code" }, {
      bearer: minted.accessToken, env: APPLE_ENV,
      exchangeAppleAuthorizationCode: async () => { appleCalled = true; return "t"; },
      revokeAppleToken: async () => { appleCalled = true; return true; },
    });
    assert.deepEqual([answer.response.status, answer.body], [401, { error: "session_expired" }], action);
  }
  assert.equal(appleCalled, false);
  assert.equal(await sessionCount(ctx), 1, "nothing was ended or made");
});

// ---- nothing secret in a log or an answer -------------------------------------------------------------------------

onBackends("no token, key, address or account id is in any log line or refusal, and none is in a bucket name", async (ctx) => {
  const secrets = new Set([SIGNING_KEY, SUB, SUB_B, ACCOUNT, CALLER, "provider-credential-not-real", ENV.ELEVENLABS_API_KEY, PREFIX]);
  const everything = [];
  // Every log line and header, and every answer that is a refusal. A success answer is where the app is meant to receive its tokens.
  const note = (...results) => results.forEach((result) => everything.push(JSON.stringify([
    result.logs, result.response.status === 200 ? null : result.body, [...result.response.headers],
  ])));
  const supabase = accountToken();
  secrets.add(supabase);
  const minted = await mint(ctx);
  note(minted);
  for (const token of [minted.body.accessToken, minted.body.refreshToken, sha256(minted.body.refreshToken)]) secrets.add(token);
  const refreshed = await call(ctx, "refresh", { refreshToken: minted.body.refreshToken });
  note(refreshed);
  secrets.add(refreshed.body.accessToken).add(refreshed.body.refreshToken);
  note(await voiceToken(ctx, refreshed.body.accessToken), await voiceToken(ctx, supabase), await voiceToken(ctx, `${supabase}x`));
  note(await call(ctx, "refresh", { refreshToken: minted.body.refreshToken }));
  note(await call(ctx, "account-session", {}, { bearer: accountToken(SUB, {}, stranger.privateKey) }));
  note(await call(ctx, "account-session", {}, { bearer: refreshed.body.accessToken }));
  for (let n = 0; n < 11; n += 1) note(await mint(ctx, SUB, { address: CALLER }));
  note(await call(ctx, "delete-conversations", {}, { bearer: supabase }));
  note(await call(ctx, "sign-out", {}, { bearer: refreshed.body.accessToken }));
  const text = everything.join("\n");
  assert.ok(text.length > 0);
  for (const secret of secrets) assert.ok(!text.includes(secret), `leaked ${secret.slice(0, 8)}...`);
  // The caller's address is hashed in the store, and the account too.
  if (ctx.command) {
    const stored = (await ctx.command("KEYS", `${PREFIX}limit-signin*`)).join("\n");
    for (const value of [CALLER, SUB]) assert.ok(!stored.includes(value), "a bucket name carried an address or an account");
    for (const key of await ctx.command("KEYS", `${PREFIX}limit-signin*`)) assert.match(key, /^doddy:voice:v1:limit-signin(-day)?:[0-9a-f]{64}:\d+$/);
  } else {
    for (const bucket of ctx.store.buckets.keys()) assert.match(bucket, /^[0-9a-f]{64}$/);
  }
});

// ---- the Redis store ----------------------------------------------------------------------------------------------

onBackends("Redis: an account session lives 30 days like an Apple one, and its Apple link keeps its own 400 days when it is refreshed", async ({ store, command }) => {
  await store.setAppleToken(ACCOUNT, sealAppleToken("apple-refresh-not-real", SIGNING_KEY), 400 * DAY);
  const ctx = { store, command };
  const minted = (await mint(ctx)).body;
  const { sid } = verifyAccessToken(minted.accessToken, SIGNING_KEY, NOW);
  for (const key of [`${PREFIX}session:${sid}`, `${PREFIX}refresh:${sha256(minted.refreshToken)}`, `${PREFIX}user-sessions:${ACCOUNT}`]) {
    const ttl = await command("TTL", key);
    assert.ok(ttl > 29 * DAY && ttl <= 30 * DAY, `${key.slice(PREFIX.length, PREFIX.length + 12)} lives 30 days (${ttl})`);
  }
  assert.equal((await call(ctx, "refresh", { refreshToken: minted.refreshToken })).response.status, 200);
  const link = await command("TTL", `${PREFIX}apple-token:${ACCOUNT}`);
  assert.ok(link > 399 * DAY, `a refresh never shortens the link that deleting the account needs (${link} s left)`);
  assert.equal(openAppleToken(await store.getAppleToken(ACCOUNT), SIGNING_KEY), "apple-refresh-not-real");

  // An older Apple voice session's token is still kept alive for as long as the session is refreshed.
  const pseudonym = "d".repeat(64);
  assert.equal(await store.createSession({
    userId: pseudonym, sessionId: "apple-session-not-real", refreshHash: sha256("r".repeat(43)), nonceHash: sha256("n".repeat(43)),
    ttlSeconds: 30 * DAY, nowSeconds: NOW_S,
  }), 1);
  await store.setAppleToken(pseudonym, "sealed-not-real", 10 * DAY);
  const rotated = await call(ctx, "refresh", { refreshToken: "r".repeat(43) });
  assert.equal(rotated.response.status, 200);
  const extended = await command("TTL", `${PREFIX}apple-token:${pseudonym}`);
  assert.ok(extended > 29 * DAY && extended <= 30 * DAY, `an Apple voice session's token is extended as before (${extended})`);
}, { redisOnly: true });

onBackends("Redis: a session past its 30 days, or ended, gives no access token; an access token already issued ends with its session", async (ctx) => {
  const { store, command } = ctx;
  const expiring = (await mint(ctx, SUB)).body;
  const { sid } = verifyAccessToken(expiring.accessToken, SIGNING_KEY, NOW);
  assert.equal((await voiceToken(ctx, expiring.accessToken)).response.status, 200);
  await command("PEXPIRE", `${PREFIX}session:${sid}`, 1);
  await command("PEXPIRE", `${PREFIX}refresh:${sha256(expiring.refreshToken)}`, 1);
  await new Promise((resolve) => setTimeout(resolve, 30));
  const dead = await call(ctx, "refresh", { refreshToken: expiring.refreshToken });
  assert.deepEqual([dead.response.status, dead.body], [401, { error: "session_expired" }]);
  assert.equal((await voiceToken(ctx, expiring.accessToken)).response.status, 401);
  assert.equal(await store.getSession(sid), null);
}, { redisOnly: true });

onBackends("Redis: createSession with no nonce makes the same three records, and a nonce still can't be used twice", async ({ store, command }) => {
  const base = { userId: ACCOUNT, ttlSeconds: 30 * DAY, nowSeconds: NOW_S };
  assert.equal(await store.createSession({ ...base, sessionId: "s1", refreshHash: "h1" }), 1);
  assert.equal(await store.createSession({ ...base, sessionId: "s2", refreshHash: "h2", nonceHash: null }), 1);
  assert.equal(await store.createSession({ ...base, sessionId: "s3", refreshHash: "h1" }), 0, "a refresh hash already in use is refused");
  assert.deepEqual(await command("KEYS", `${PREFIX}nonce:*`), []);
  assert.equal(await store.createSession({ ...base, sessionId: "s4", refreshHash: "h4", nonceHash: "n1" }), 1);
  assert.equal(await store.createSession({ ...base, sessionId: "s5", refreshHash: "h5", nonceHash: "n1" }), 0, "the replay guard of an Apple sign-in is unchanged");
  assert.equal(await command("GET", `${PREFIX}session:s5`), null, "and nothing of the refused one is left");
  const ttl = await command("TTL", `${PREFIX}nonce:n1`);
  assert.ok(ttl > 0 && ttl <= 600, `the nonce lives 10 minutes (${ttl})`);
}, { redisOnly: true });

onBackends("Redis: revokeUserSessions ends every session of one account and what a refresh left behind, and nothing else", async ({ store, command }) => {
  const sign = (userId, id) => store.createSession({
    userId, sessionId: id, refreshHash: sha256(`refresh-${id}`), ttlSeconds: 30 * DAY, nowSeconds: NOW_S,
  });
  for (const id of ["a1", "a2", "a3"]) assert.equal(await sign(ACCOUNT, id), 1);
  assert.equal(await sign(ACCOUNT_B, "b1"), 1);
  // One of A's has been refreshed once, so a swapped-out hash is remembered as well.
  const prior = await store.getRefresh(sha256("refresh-a1"));
  assert.ok(await store.rotateRefreshSession(sha256("refresh-a1"), sha256("refresh-a1-next"), prior, 30 * DAY));
  await store.setAppleToken(ACCOUNT, "sealed-not-real", 400 * DAY);
  assert.equal((await command("KEYS", `${PREFIX}refresh:*`)).length, 5);

  assert.equal(await store.revokeUserSessions(ACCOUNT), 3);
  assert.deepEqual((await command("KEYS", `${PREFIX}session:*`)), [`${PREFIX}session:b1`]);
  assert.deepEqual((await command("KEYS", `${PREFIX}refresh:*`)), [`${PREFIX}refresh:${sha256("refresh-b1")}`], "the swapped-out hash goes too");
  assert.deepEqual(await command("KEYS", `${PREFIX}user-sessions:*`), [`${PREFIX}user-sessions:${ACCOUNT_B}`]);
  assert.equal(await store.getAppleToken(ACCOUNT), "sealed-not-real", "the Apple link is left for apple-revoke");
  assert.equal(await store.revokeUserSessions(ACCOUNT), 0, "nothing left: asking again ends nothing");
  assert.equal(await store.revokeUserSessions("account:never-seen"), 0);

  // deleteAccount still does what it did: sessions and the Apple link together.
  assert.equal(await store.deleteAccount(ACCOUNT_B), 1);
  assert.deepEqual(await command("KEYS", `${PREFIX}*`), [`${PREFIX}apple-token:${ACCOUNT}`]);
}, { redisOnly: true });
