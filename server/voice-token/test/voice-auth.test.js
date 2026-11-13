import assert from "node:assert/strict";
import { generateKeyPairSync, sign as signRS256, createHash, verify as verifySig } from "node:crypto";
import { test } from "node:test";
import { fakeConversationStore, fakeElevenLabs } from "./conversation-fakes.js";
import { hasRedis, startLocalRedis, withLocalRedis } from "./local-redis.js";
import {
  handleVoiceAuthRequest,
  clientAddress,
  createVoiceAuthStore,
  VoiceAuthStoreUnavailable,
  signAccessToken,
  verifyAccessToken,
  verifyAppleIdentityToken,
  appleClientSecret,
  appleRevocationConfigured,
  exchangeAppleAuthorizationCode,
  revokeAppleToken,
  sealAppleToken,
  openAppleToken,
} from "../src/voice-auth.js";

const NOW = Date.parse("2026-10-16T12:00:00Z");
const NONCE = "A".repeat(43);
const SIGNING_KEY = "session-signing-secret-for-tests-000000000000";
const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev", DODDY_SESSION_SIGNING_KEY: SIGNING_KEY,
  ELEVENLABS_API_KEY: "elevenlabs-test-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
  // Vercel sets this itself; the caller's address is only trusted from Vercel's header (ADR-712).
  VERCEL: "1",
};
const CALLER = "203.0.113.7";
/** Deleting a voice account that never had a conversation recorded: nothing deleted, nothing owed. */
const NO_CONVERSATIONS = { deleted: 0, pending: 0 };

// A Sign in with Apple key, as the owner would make one in the Apple Developer account (ADR-524).
const APPLE_KEY = generateKeyPairSync("ec", { namedCurve: "P-256" });
/** The shape of the id_token in Apple's code-swap reply; only its `sub` is read. */
const appleIdToken = (sub) => `e30.${Buffer.from(JSON.stringify({ iss: "https://appleid.apple.com", sub })).toString("base64url")}.sig`;
const APPLE_ENV = {
  ...ENV, APPLE_TEAM_ID: "TEAMID1234", APPLE_SIGN_IN_KEY_ID: "KEYID12345",
  APPLE_SIGN_IN_PRIVATE_KEY: APPLE_KEY.privateKey.export({ format: "pem", type: "pkcs8" }),
};

function fakeStore() {
  const sessions = new Map();
  const refresh = new Map();
  const nonces = new Set();
  const limits = new Map();
  const signIns = new Map();
  const appleTokens = new Map();
  /** Ends a session the way the Redis scripts do: the record and both remembered refresh hashes. */
  const endSession = (session) => {
    sessions.delete(session.sessionId);
    refresh.delete(session.refreshHash);
    if (session.previousRefreshHash) refresh.delete(session.previousRefreshHash);
  };
  return {
    // Deleting a voice account also looks after its conversations at ElevenLabs (test/conversations.test.js).
    ...fakeConversationStore(),
    sessions, refresh, nonces, appleTokens, signIns,
    async setAppleToken(userId, sealed) { appleTokens.set(userId, sealed); },
    async getAppleToken(userId) { return appleTokens.get(userId) ?? null; },
    async deleteAppleToken(userId) { appleTokens.delete(userId); },
    async createSession(input) {
      if (nonces.has(input.nonceHash) || refresh.has(input.refreshHash)) return 0;
      nonces.add(input.nonceHash);
      sessions.set(input.sessionId, { userId: input.userId, sessionId: input.sessionId, refreshHash: input.refreshHash });
      refresh.set(input.refreshHash, { userId: input.userId, sessionId: input.sessionId });
      return 1;
    },
    async getRefresh(hash) { return refresh.get(hash) ?? null; },
    async getSession(id) { return sessions.get(id) ?? null; },
    // Same contract as the Redis script: the swapped-out hash stays as a marked record; showing it
    // again ends the session. Only the latest swapped-out hash is remembered.
    async rotateRefreshSession(oldHash, newHash, prior) {
      const current = refresh.get(oldHash);
      if (!current || current.userId !== prior.userId || current.sessionId !== prior.sessionId) return null;
      const session = sessions.get(prior.sessionId);
      if (!session) return null;
      if (current.used) {
        endSession(session);
        return { reused: true };
      }
      if (session.previousRefreshHash) refresh.delete(session.previousRefreshHash);
      refresh.set(newHash, { userId: current.userId, sessionId: current.sessionId });
      refresh.set(oldHash, { ...current, used: true });
      sessions.set(prior.sessionId, { ...session, refreshHash: newHash, previousRefreshHash: oldHash });
      return sessions.get(prior.sessionId);
    },
    async hitLimits(userId, perLimit, globalLimit, _now, dailyLimit = 150) {
      // Same rule as the Redis script: only an issued token counts, so a refused request never moves
      // the global count, and a refusal for a full global budget never uses the account's allowance.
      const hour = limits.get(`${userId}:hour`) ?? 0;
      const day = limits.get(`${userId}:day`) ?? 0;
      const global = limits.get("global") ?? 0;
      const limit = hour >= perLimit ? "user_hour" : day >= dailyLimit ? "user_day" : global >= globalLimit ? "global" : null;
      if (limit) return { allowed: false, limit, retryAfterSeconds: 60 };
      limits.set(`${userId}:hour`, hour + 1);
      limits.set(`${userId}:day`, day + 1);
      limits.set("global", global + 1);
      return { allowed: true, limit: null, retryAfterSeconds: 60 };
    },
    // Same rule as the Redis script. The test clock stands still, so hour and day never roll over.
    async hitSignInLimits(bucket, perHour, perDay) {
      const entry = signIns.get(bucket) ?? { hour: 0, day: 0 };
      const limit = entry.hour >= perHour ? "client_hour" : entry.day >= perDay ? "client_day" : null;
      if (limit) return { allowed: false, limit, retryAfterSeconds: limit === "client_day" ? 3_600 : 60 };
      signIns.set(bucket, { hour: entry.hour + 1, day: entry.day + 1 });
      return { allowed: true, limit: null, retryAfterSeconds: 60 };
    },
    async revokeSession(id, userId) {
      const session = sessions.get(id);
      if (!session || session.userId !== userId) return 0;
      endSession(session);
      return 1;
    },
    async deleteAccount(userId) {
      let deleted = 0;
      for (const session of [...sessions.values()]) {
        if (session.userId === userId) {
          endSession(session);
          deleted += 1;
        }
      }
      appleTokens.delete(userId);
      return deleted;
    },
  };
}

function request(action, body = {}, authorization, headers = { "x-vercel-forwarded-for": CALLER }) {
  return new Request("https://example.test/api/voice-auth", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
      ...(authorization ? { authorization: `Bearer ${authorization}` } : {}),
    },
    body: JSON.stringify({ action, ...(action === "sign-in" ? { provider: "elevenlabs" } : {}), ...body }),
  });
}

async function run(req, options = {}) {
  const logs = [];
  const response = await handleVoiceAuthRequest(req, options.environment ?? ENV, {
    store: options.store ?? fakeStore(),
    now: options.now ?? (() => NOW),
    log: (line) => logs.push(line),
    verifyAppleIdentityToken: options.verifyAppleIdentityToken ?? (async (_token, rawNonce) => ({ sub: "apple-sub-test", nonce: rawNonce })),
    exchangeAppleAuthorizationCode: options.exchangeAppleAuthorizationCode,
    revokeAppleToken: options.revokeAppleToken,
    authenticateDoddyAccount: options.authenticateDoddyAccount,
    fetch: options.fetch,
    // ElevenLabs is never reached from these tests: an empty one answers what deleting a voice account asks it.
    elevenLabsFetch: options.elevenLabsFetch ?? fakeElevenLabs({ apiKey: ENV.ELEVENLABS_API_KEY }).fetch,
  });
  return { response, body: await response.json(), logs };
}

test("Apple sign-in creates a short-lived access token and opaque refresh session without logging credentials", async () => {
  const store = fakeStore();
  const { response, body, logs } = await run(request("sign-in", { identityToken: "apple-id-token", rawNonce: NONCE }), { store });
  assert.equal(response.status, 200);
  assert.equal(body.expiresIn, 600);
  assert.equal(typeof body.accessToken, "string");
  assert.equal(typeof body.refreshToken, "string");
  assert.equal(verifyAccessToken(body.accessToken, SIGNING_KEY, NOW).aud, "voice");
  assert.equal(store.sessions.size, 1);
  assert.equal(store.refresh.size, 1);
  const logged = JSON.stringify(logs);
  for (const secret of ["apple-id-token", NONCE, body.accessToken, body.refreshToken, "apple-sub-test"]) {
    assert.ok(!logged.includes(secret), `log leaked ${secret}`);
  }
  assert.deepEqual(logs[0], { event: "voice_auth", action: "sign-in", status: 200, error: null, ms: 0 });
});

test("Apple sign-in rejects invalid tokens and replayed nonce before creating a session", async () => {
  const store = fakeStore();
  const invalid = await run(request("sign-in", { identityToken: "bad-token", rawNonce: NONCE }), {
    store, verifyAppleIdentityToken: async () => null,
  });
  assert.equal(invalid.response.status, 401);
  const first = await run(request("sign-in", { identityToken: "apple-id-token", rawNonce: NONCE }), { store });
  assert.equal(first.response.status, 200);
  const replay = await run(request("sign-in", { identityToken: "apple-id-token", rawNonce: NONCE }), { store });
  assert.equal(replay.response.status, 401);
  assert.equal(store.sessions.size, 1);
});

test("missing durable store or signing key fails closed", async () => {
  const noStoreResponse = await handleVoiceAuthRequest(
    request("sign-in", { identityToken: "id", rawNonce: NONCE }),
    { ...ENV, UPSTASH_REDIS_REST_URL: undefined, UPSTASH_REDIS_REST_TOKEN: undefined },
    { now: () => NOW, log: () => {}, verifyAppleIdentityToken: async () => ({ sub: "x", nonce: NONCE }) },
  );
  assert.equal(noStoreResponse.status, 503);
  assert.deepEqual(await noStoreResponse.json(), { error: "server_not_configured" });
  const noKey = await run(request("sign-in", { identityToken: "id", rawNonce: NONCE }), {
    environment: { APPLE_BUNDLE_ID: ENV.APPLE_BUNDLE_ID },
  });
  assert.equal(noKey.response.status, 503);
});

test("missing selected provider configuration fails before creating a DODDY account", async () => {
  const store = fakeStore();
  const missing = await run(request("sign-in", { identityToken: "id", rawNonce: NONCE }), {
    store, environment: { ...ENV, ELEVENLABS_API_KEY: "" },
  });
  assert.equal(missing.response.status, 503);
  assert.deepEqual(missing.body, { error: "server_not_configured" });
  assert.equal(store.sessions.size, 0);
});

test("a sign-in that names OpenAI is refused: ElevenLabs is the only voice (9 Nov 2026)", async () => {
  const store = fakeStore();
  const { response, body } = await run(request("sign-in", { identityToken: "id", rawNonce: NONCE, provider: "openai" }), { store });
  assert.equal(response.status, 400);
  assert.deepEqual(body, { error: "invalid_request" });
  assert.equal(store.sessions.size, 0);
});

test("refresh rotates the refresh token and rejects reuse of the old token", async () => {
  const store = fakeStore();
  const signedIn = await run(request("sign-in", { identityToken: "apple-id-token", rawNonce: NONCE }), { store });
  const rotated = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), { store });
  assert.equal(rotated.response.status, 200);
  assert.notEqual(rotated.body.refreshToken, signedIn.body.refreshToken);
  const replay = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), { store });
  assert.equal(replay.response.status, 401);
  assert.deepEqual(replay.body, { error: "session_expired" });
  // A swapped-out token coming back means it was copied (ADR-712): the whole session ends, so the
  // newest refresh token and the access token stop working too.
  assert.equal(store.sessions.size, 0, "the session is revoked");
  assert.equal(store.refresh.size, 0, "no refresh token of it is left");
  const newest = await run(request("refresh", { refreshToken: rotated.body.refreshToken }), { store });
  assert.equal(newest.response.status, 401);
  const access = await run(request("sign-out", {}, rotated.body.accessToken), { store });
  assert.equal(access.response.status, 401, "the access token no longer maps to a session");
});

test("reusing a swapped-out refresh token ends the session, and is the same 401 as any dead token", async () => {
  const store = fakeStore();
  const other = await run(request("sign-in", { identityToken: "id-other", rawNonce: "O".repeat(43) }), {
    store, verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: "someone-else", nonce: rawNonce }),
  });
  const signedIn = await run(request("sign-in", { identityToken: "apple-id-token", rawNonce: NONCE }), { store });
  const first = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), { store });
  // Normal rotation keeps working, several times in a row, and leaves nothing behind but the latest swapped-out hash.
  const second = await run(request("refresh", { refreshToken: first.body.refreshToken }), { store });
  const third = await run(request("refresh", { refreshToken: second.body.refreshToken }), { store });
  for (const step of [first, second, third]) assert.equal(step.response.status, 200);
  assert.equal(store.sessions.size, 2);
  assert.equal(store.refresh.size, 2 + 1, "one current hash per session, plus the latest swapped-out one");

  const unknown = await run(request("refresh", { refreshToken: "never-issued-".padEnd(43, "x") }), { store });
  assert.equal(store.sessions.size, 2, "a token nobody ever held ends nothing");
  const replay = await run(request("refresh", { refreshToken: second.body.refreshToken }), { store });
  assert.equal(replay.response.status, 401);
  assert.deepEqual(replay.body, unknown.body, "the caller can't tell reuse from any other invalid token");
  assert.equal(replay.response.headers.get("cache-control"), unknown.response.headers.get("cache-control"));
  assert.equal(replay.logs[0].reuse, true, "the content-free log line says it happened");
  assert.equal(unknown.logs[0].reuse, undefined);
  assert.ok(!JSON.stringify(replay.logs).includes(second.body.refreshToken));
  // That session and every token of it are gone; someone else's session is untouched.
  assert.equal(store.sessions.size, 1);
  const dead = await run(request("refresh", { refreshToken: third.body.refreshToken }), { store });
  assert.equal(dead.response.status, 401);
  const alive = await run(request("refresh", { refreshToken: other.body.refreshToken }), { store });
  assert.equal(alive.response.status, 200);
});

test("sign-out revokes the refresh session and the current access token", async () => {
  const store = fakeStore();
  const signedIn = await run(request("sign-in", { identityToken: "apple-id-token", rawNonce: NONCE }), { store });
  const signedOut = await run(request("sign-out", {}, signedIn.body.accessToken), { store });
  assert.equal(signedOut.response.status, 200);
  assert.deepEqual(signedOut.body, { signedOut: true });
  const refresh = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), { store });
  assert.equal(refresh.response.status, 401);
  assert.equal(store.sessions.size, 0);
});

test("account deletion revokes all sessions for the same Apple identity", async () => {
  const store = fakeStore();
  const a = await run(request("sign-in", { identityToken: "id-a", rawNonce: "A".repeat(43) }), { store });
  const b = await run(request("sign-in", { identityToken: "id-b", rawNonce: "B".repeat(43) }), { store });
  assert.equal(store.sessions.size, 2);
  const deleted = await run(request("delete-account", {}, a.body.accessToken), { store });
  assert.equal(deleted.response.status, 200);
  assert.deepEqual(deleted.body, { deleted: true, appleRevoked: false, conversations: NO_CONVERSATIONS });
  assert.equal(deleted.logs[0].apple, "not_configured");
  assert.equal(store.sessions.size, 0);
  assert.equal(store.refresh.size, 0);
});

// ADR-524: deleting the account also ends Sign in with Apple, when the owner set up an Apple key.
test("with an Apple key, sign-in keeps Apple's token sealed and deletion revokes it", async () => {
  const store = fakeStore();
  const exchanged = [];
  const revoked = [];
  const options = {
    store, environment: APPLE_ENV,
    exchangeAppleAuthorizationCode: async (code, _env, { expectedSub }) => { exchanged.push([code, expectedSub]); return "apple-refresh-token-value"; },
    revokeAppleToken: async (token) => { revoked.push(token); return true; },
  };
  const signedIn = await run(request("sign-in", { identityToken: "apple-id-token", rawNonce: NONCE, authorizationCode: "one-time-code" }), options);
  assert.equal(signedIn.response.status, 200);
  assert.deepEqual(exchanged, [["one-time-code", "apple-sub-test"]], "the code must belong to the person just verified");
  const [sealed] = [...store.appleTokens.values()];
  assert.equal(typeof sealed, "string");
  assert.ok(!sealed.includes("apple-refresh-token-value"), "stored sealed, never as it came");
  assert.equal(openAppleToken(sealed, SIGNING_KEY), "apple-refresh-token-value");

  const deleted = await run(request("delete-account", {}, signedIn.body.accessToken), options);
  assert.equal(deleted.response.status, 200);
  assert.deepEqual(deleted.body, { deleted: true, appleRevoked: true, conversations: NO_CONVERSATIONS });
  assert.deepEqual(revoked, ["apple-refresh-token-value"]);
  assert.equal(store.appleTokens.size, 0, "the sealed token goes with the account");
  assert.equal(store.sessions.size, 0);
  assert.equal(deleted.logs[0].apple, "revoked");
  const logged = JSON.stringify([...signedIn.logs, ...deleted.logs]);
  for (const secret of ["one-time-code", "apple-refresh-token-value", sealed]) {
    assert.ok(!logged.includes(secret), `log leaked ${secret}`);
  }
});

test("Apple failing never blocks sign-in or deletion, and the reply says so", async () => {
  // The code swap fails: sign-in still works, deletion has nothing to revoke.
  const store = fakeStore();
  const failingSwap = {
    store, environment: APPLE_ENV,
    exchangeAppleAuthorizationCode: async () => null,
    revokeAppleToken: async () => assert.fail("nothing to revoke"),
  };
  const a = await run(request("sign-in", { identityToken: "id-a", rawNonce: "A".repeat(43), authorizationCode: "code-a" }), failingSwap);
  assert.equal(a.response.status, 200);
  assert.equal(store.appleTokens.size, 0);
  const deletedA = await run(request("delete-account", {}, a.body.accessToken), failingSwap);
  assert.deepEqual(deletedA.body, { deleted: true, appleRevoked: false, conversations: NO_CONVERSATIONS });
  assert.equal(deletedA.logs[0].apple, "no_token");

  // The swap throws (Apple unreachable): sign-in still works.
  const throwing = await run(request("sign-in", { identityToken: "id-c", rawNonce: "C".repeat(43), authorizationCode: "code-c" }), {
    store, environment: APPLE_ENV, exchangeAppleAuthorizationCode: async () => { throw new Error("network"); },
  });
  assert.equal(throwing.response.status, 200);

  // Apple refuses the revoke: the account is still deleted.
  const refusing = {
    store, environment: APPLE_ENV,
    exchangeAppleAuthorizationCode: async () => "apple-token-b",
    revokeAppleToken: async () => false,
  };
  const b = await run(request("sign-in", { identityToken: "id-b", rawNonce: "B".repeat(43), authorizationCode: "code-b" }), refusing);
  const deletedB = await run(request("delete-account", {}, b.body.accessToken), refusing);
  assert.equal(deletedB.response.status, 200);
  assert.deepEqual(deletedB.body, { deleted: true, appleRevoked: false, conversations: NO_CONVERSATIONS });
  assert.equal(deletedB.logs[0].apple, "failed");
  assert.equal([...store.sessions.values()].filter((item) => item.userId === b.body.userId).length, 0);
});

test("without an Apple key, or without a code, nothing is sent to Apple", async () => {
  const store = fakeStore();
  const never = { exchangeAppleAuthorizationCode: async () => assert.fail("no Apple key, no swap") };
  const noKey = await run(request("sign-in", { identityToken: "id", rawNonce: NONCE, authorizationCode: "code" }), { store, ...never });
  assert.equal(noKey.response.status, 200);
  const noCode = await run(request("sign-in", { identityToken: "id-2", rawNonce: "Q".repeat(43) }), {
    store, environment: APPLE_ENV, ...never,
  });
  assert.equal(noCode.response.status, 200);
  const tooLong = await run(request("sign-in", { identityToken: "id-3", rawNonce: "R".repeat(43), authorizationCode: "x".repeat(2_000) }), {
    store, environment: APPLE_ENV, ...never,
  });
  assert.equal(tooLong.response.status, 200);
  assert.equal(store.appleTokens.size, 0);
  assert.equal(appleRevocationConfigured(ENV), false);
  assert.equal(appleRevocationConfigured(APPLE_ENV), true);
  assert.equal(appleRevocationConfigured({ ...APPLE_ENV, APPLE_SIGN_IN_PRIVATE_KEY: " " }), false);
});

test("the Apple client secret is an ES256 token for this app, signed with the owner's key", () => {
  const secret = appleClientSecret(APPLE_ENV, NOW);
  const [headerPart, claimsPart, signaturePart] = secret.split(".");
  const header = JSON.parse(Buffer.from(headerPart, "base64url"));
  const claims = JSON.parse(Buffer.from(claimsPart, "base64url"));
  assert.deepEqual(header, { alg: "ES256", kid: "KEYID12345" });
  assert.deepEqual(claims, { iss: "TEAMID1234", iat: NOW / 1_000, exp: NOW / 1_000 + 300,
    aud: "https://appleid.apple.com", sub: "com.bienos.doddy2.dev" });
  assert.ok(verifySig("sha256", Buffer.from(`${headerPart}.${claimsPart}`),
    { key: APPLE_KEY.publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signaturePart, "base64url")));
  // A key pasted with literal \n line breaks works too.
  const flattened = { ...APPLE_ENV, APPLE_SIGN_IN_PRIVATE_KEY: APPLE_ENV.APPLE_SIGN_IN_PRIVATE_KEY.replace(/\n/g, "\\n") };
  assert.equal(appleClientSecret(flattened, NOW).split(".").length, 3);
});

test("the code swap and the revoke post the right form to Apple and fail safely", async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, form: Object.fromEntries(new URLSearchParams(init.body)), type: init.headers["content-type"] });
    return url.endsWith("/auth/token") ? Response.json({ refresh_token: "rt", access_token: "at", id_token: appleIdToken("person-a") })
      : new Response("", { status: 200 });
  };
  const asA = { fetch: fetchImpl, now: NOW, expectedSub: "person-a" };
  assert.equal(await exchangeAppleAuthorizationCode("the-code", APPLE_ENV, asA), "rt");
  assert.equal(await revokeAppleToken("rt", APPLE_ENV, { fetch: fetchImpl, now: NOW }), true);
  assert.equal(calls[0].url, "https://appleid.apple.com/auth/token");
  assert.equal(calls[0].type, "application/x-www-form-urlencoded");
  assert.deepEqual(Object.keys(calls[0].form).sort(), ["client_id", "client_secret", "code", "grant_type"]);
  assert.equal(calls[0].form.client_id, "com.bienos.doddy2.dev");
  assert.equal(calls[0].form.grant_type, "authorization_code");
  assert.equal(calls[0].form.code, "the-code");
  assert.equal(calls[1].url, "https://appleid.apple.com/auth/revoke");
  assert.equal(calls[1].form.token, "rt");
  assert.equal(calls[1].form.token_type_hint, "refresh_token");

  // A code from another Apple account, or no one to compare with, is never kept.
  assert.equal(await exchangeAppleAuthorizationCode("c", APPLE_ENV, { ...asA, expectedSub: "person-b" }), null);
  assert.equal(await exchangeAppleAuthorizationCode("c", APPLE_ENV, { fetch: fetchImpl, now: NOW }), null);
  assert.equal(calls.length, 3, "no call to Apple without someone to compare with");
  const noIdToken = async () => Response.json({ refresh_token: "rt" });
  assert.equal(await exchangeAppleAuthorizationCode("c", APPLE_ENV, { ...asA, fetch: noIdToken }), null);
  const brokenIdToken = async () => Response.json({ refresh_token: "rt", id_token: "not-a-jwt" });
  assert.equal(await exchangeAppleAuthorizationCode("c", APPLE_ENV, { ...asA, fetch: brokenIdToken }), null);

  const refused = async () => new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
  assert.equal(await exchangeAppleAuthorizationCode("c", APPLE_ENV, { ...asA, fetch: refused }), null);
  assert.equal(await revokeAppleToken("rt", APPLE_ENV, { fetch: refused, now: NOW }), false);
  const down = async () => { throw new Error("network"); };
  assert.equal(await exchangeAppleAuthorizationCode("c", APPLE_ENV, { ...asA, fetch: down }), null);
  assert.equal(await revokeAppleToken("rt", APPLE_ENV, { fetch: down, now: NOW }), false);
  const noToken = async () => Response.json({ access_token: "only", id_token: appleIdToken("person-a") });
  assert.equal(await exchangeAppleAuthorizationCode("c", APPLE_ENV, { ...asA, fetch: noToken }), null);
});

test("a sealed Apple token opens only with the same signing key and untouched", () => {
  const sealed = sealAppleToken("apple-token", SIGNING_KEY);
  assert.notEqual(sealAppleToken("apple-token", SIGNING_KEY), sealed, "a fresh nonce every time");
  assert.equal(openAppleToken(sealed, SIGNING_KEY), "apple-token");
  assert.equal(openAppleToken(sealed, "another-signing-key-0000000000000000"), null);
  const bytes = Buffer.from(sealed, "base64url");
  bytes[14] ^= 1;
  assert.equal(openAppleToken(bytes.toString("base64url"), SIGNING_KEY), null);
  assert.equal(openAppleToken("short", SIGNING_KEY), null);
});

test("malformed, oversized and unknown auth requests are rejected without content in logs", async () => {
  const logs = [];
  const invalid = await handleVoiceAuthRequest(new Request("https://example.test/auth", { method: "POST", body: "{" }), ENV, {
    store: fakeStore(), log: (entry) => logs.push(entry), now: () => NOW,
  });
  assert.equal(invalid.status, 400);
  const unknown = await run(request("set-password", { password: "sensitive" }));
  assert.equal(unknown.response.status, 400);
  assert.ok(!JSON.stringify([...logs, ...unknown.logs]).includes("sensitive"));
  const get = await run(new Request("https://example.test/auth", { method: "GET" }));
  assert.equal(get.response.status, 405);
  assert.equal(get.response.headers.get("allow"), "POST");
});

test("access token signatures, expiry and audience are validated", () => {
  const token = signAccessToken({ userId: "user", sessionId: "session" }, SIGNING_KEY, NOW);
  assert.equal(verifyAccessToken(token, SIGNING_KEY, NOW).sub, "user");
  assert.equal(verifyAccessToken(token, "wrong-signing-key-000000000000000000", NOW), null);
  assert.equal(verifyAccessToken(token, SIGNING_KEY, NOW + 11 * 60 * 1_000), null);
  const [, payload, signature] = token.split(".");
  const wrongAudience = `${token.split(".")[0]}.${Buffer.from(JSON.stringify({ iss: "doddy-voice", aud: "other", sub: "user", sid: "session", exp: Math.floor(NOW / 1000) + 300 })).toString("base64url")}.${signature}`;
  assert.equal(verifyAccessToken(wrongAudience, SIGNING_KEY, NOW), null);
  assert.ok(payload);
});

test("Apple identity token signature, issuer, audience, expiry and nonce are checked", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const kid = `test-${Math.random()}`;
  const jwk = { ...publicKey.export({ format: "jwk" }), kid, use: "sig", alg: "RS256" };
  const rawNonce = "Z".repeat(43);
  const nonce = createHash("sha256").update(rawNonce).digest("hex");
  const nowSeconds = Math.floor(NOW / 1_000);
  const makeToken = (claims) => {
    const header = Buffer.from(JSON.stringify({ alg: "RS256", kid, typ: "JWT" })).toString("base64url");
    const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
    const signingInput = `${header}.${payload}`;
    return `${signingInput}.${signRS256("RSA-SHA256", Buffer.from(signingInput), privateKey).toString("base64url")}`;
  };
  const verify = (claims) => verifyAppleIdentityToken(makeToken(claims), rawNonce, ENV.APPLE_BUNDLE_ID, {
    now: NOW, fetch: async () => Response.json({ keys: [jwk] }),
  });
  const valid = { iss: "https://appleid.apple.com", aud: ENV.APPLE_BUNDLE_ID, exp: nowSeconds + 300,
    iat: nowSeconds, nonce, sub: "apple-sub" };
  assert.deepEqual(await verify(valid), { sub: "apple-sub", nonce: rawNonce });
  assert.equal(await verify({ ...valid, aud: "wrong.bundle" }), null);
  assert.equal(await verify({ ...valid, nonce: "wrong" }), null);
  assert.equal(await verify({ ...valid, iss: "https://evil.example" }), null);
  assert.equal(await verify({ ...valid, exp: nowSeconds - 1 }), null);
});

test("shared-store adapter sends credentials only in headers and fails closed on network errors", async () => {
  let sent;
  const store = createVoiceAuthStore({
    url: "https://redis.example.test",
    token: "store-secret",
    fetch: async (url, init) => {
      sent = { url, init };
      return Response.json([{ result: 1 }]);
    },
  });
  assert.equal(await store.createSession({ userId: "opaque", sessionId: "sid", refreshHash: "rh", nonceHash: "nh", ttlSeconds: 100, nowSeconds: 1 }), 1);
  assert.equal(sent.url, "https://redis.example.test/multi-exec");
  assert.equal(sent.init.headers.authorization, "Bearer store-secret");
  assert.ok(!sent.init.body.includes("store-secret"));
  assert.ok(!sent.init.body.includes("AppleID"));
  await store.setAppleToken("opaque", "sealed-value", 100);
  assert.deepEqual(JSON.parse(sent.init.body), [["SET", "doddy:voice:v1:apple-token:opaque", "sealed-value", "EX", "100"]]);
  await store.deleteAccount("opaque");
  const deleteCommand = JSON.parse(sent.init.body)[0];
  assert.equal(deleteCommand[0], "EVAL");
  assert.ok(deleteCommand.includes("doddy:voice:v1:apple-token:opaque"), "deleting the account deletes the sealed Apple token");
  const down = createVoiceAuthStore({
    url: "https://redis.example.test", token: "store-secret",
    fetch: async () => { throw new Error("URL includes confidential data"); },
  });
  await assert.rejects(() => down.getSession("sid"), VoiceAuthStoreUnavailable);
  assert.throws(() => createVoiceAuthStore({ url: "http://redis.example.test", token: "x" }), VoiceAuthStoreUnavailable);
  assert.throws(() => createVoiceAuthStore({ url: "https://user:pass@redis.example.test", token: "x" }), VoiceAuthStoreUnavailable);
});

test("an unknown Apple key ID fetches Apple's keys at most once every 30 seconds", async () => {
  const { publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: "jwk" }), kid: "known-kid", use: "sig", alg: "RS256" };
  let fetches = 0;
  const fetch = async () => { fetches += 1; return Response.json({ keys: [jwk] }); };
  const junk = (kid) => `${Buffer.from(JSON.stringify({ alg: "RS256", kid })).toString("base64url")}.e30.c2ln`;
  // Ten days after the other tests' clock, so their cached keys have expired.
  const later = NOW + 10 * 86_400_000;
  assert.equal(await verifyAppleIdentityToken(junk("junk-1"), NONCE, ENV.APPLE_BUNDLE_ID, { fetch, now: later }), null);
  assert.equal(fetches, 1);
  for (let i = 0; i < 20; i += 1) {
    assert.equal(await verifyAppleIdentityToken(junk(`junk-${i + 2}`), NONCE, ENV.APPLE_BUNDLE_ID, { fetch, now: later + 1_000 }), null);
  }
  assert.equal(fetches, 1, "junk key IDs within 30 s don't call Apple again");
  await verifyAppleIdentityToken(junk("known-kid"), NONCE, ENV.APPLE_BUNDLE_ID, { fetch, now: later + 2_000 });
  assert.equal(fetches, 1, "a key already fetched is used from the cache");
  await verifyAppleIdentityToken(junk("junk-late"), NONCE, ENV.APPLE_BUNDLE_ID, { fetch, now: later + 31_000 });
  assert.equal(fetches, 2, "after 30 s an unknown key ID may fetch again");
});

// ADR-712: how many accounts one caller can make is limited per caller address.
const nonceFor = (n) => String(n).padStart(43, "n");
const from = (address) => ({ "x-vercel-forwarded-for": address });
async function signInAs(address, n, options = {}) {
  return run(request("sign-in", { identityToken: `id-${n}`, rawNonce: nonceFor(n) }, undefined, address === null ? {} : from(address)), {
    verifyAppleIdentityToken: async (_token, rawNonce) => ({ sub: `apple-sub-${n}`, nonce: rawNonce }), ...options,
  });
}

test("sign-ins are limited per caller address, refresh and sign-out are not, and the address is never stored or logged", async () => {
  const store = fakeStore();
  const granted = [];
  for (let n = 1; n <= 10; n += 1) {
    const result = await signInAs("198.51.100.1", n, { store });
    assert.equal(result.response.status, 200, `sign-in ${n}`);
    granted.push(result);
  }
  const refused = await signInAs("198.51.100.1", 11, { store });
  assert.equal(refused.response.status, 429);
  assert.deepEqual(refused.body, { error: "rate_limited" });
  assert.match(refused.response.headers.get("retry-after"), /^[1-9][0-9]*$/);
  assert.equal(store.sessions.size, 10, "no account is made for a refused sign-in");
  assert.equal(store.nonces.size, 10, "and its Apple token is not used up");
  assert.deepEqual(refused.logs[0], { event: "voice_auth", action: "sign-in", status: 429, error: "rate_limited", ms: 0, limit: "client_hour" });

  // Someone else is not affected, and neither is anything that isn't a sign-in.
  assert.equal((await signInAs("198.51.100.2", 12, { store })).response.status, 200);
  const refreshed = await run(request("refresh", { refreshToken: granted[0].body.refreshToken }, undefined, from("198.51.100.1")), { store });
  assert.equal(refreshed.response.status, 200);
  const signedOut = await run(request("sign-out", {}, granted[1].body.accessToken, from("198.51.100.1")), { store });
  assert.equal(signedOut.response.status, 200);
  assert.equal((await signInAs("198.51.100.1", 13, { store })).response.status, 429, "still refused");

  const seen = JSON.stringify([...store.signIns.keys(), ...refused.logs]);
  assert.ok(!seen.includes("198.51.100"), "the store holds a keyed hash, the log holds nothing about the caller");
  for (const bucket of store.signIns.keys()) assert.match(bucket, /^[0-9a-f]{64}$/);
});

test("sign-ins have a daily limit per caller address too, and both limits can be set", async () => {
  const daily = { ...ENV, DODDY_SIGNINS_PER_CLIENT_HOUR: "100", DODDY_SIGNINS_PER_CLIENT_DAY: "3" };
  const store = fakeStore();
  for (let n = 1; n <= 3; n += 1) assert.equal((await signInAs("198.51.100.3", n, { store, environment: daily })).response.status, 200);
  const refused = await signInAs("198.51.100.3", 4, { store, environment: daily });
  assert.equal(refused.response.status, 429);
  assert.equal(refused.logs[0].limit, "client_day");

  const hourly = { ...ENV, DODDY_SIGNINS_PER_CLIENT_HOUR: "2" };
  const other = fakeStore();
  assert.equal((await signInAs("198.51.100.4", 1, { store: other, environment: hourly })).response.status, 200);
  assert.equal((await signInAs("198.51.100.4", 2, { store: other, environment: hourly })).response.status, 200);
  assert.equal((await signInAs("198.51.100.4", 3, { store: other, environment: hourly })).response.status, 429);
});

test("an invalid sign-in limit setting stops new sign-ins, and only those", async () => {
  const store = fakeStore();
  const signedIn = await signInAs("198.51.100.5", 1, { store });
  for (const bad of ["ten", "0", "-1", "1e3", "10001", "2.5"]) {
    for (const name of ["DODDY_SIGNINS_PER_CLIENT_HOUR", "DODDY_SIGNINS_PER_CLIENT_DAY"]) {
      const environment = { ...ENV, [name]: bad };
      const refused = await signInAs("198.51.100.5", 2, { store, environment });
      assert.equal(refused.response.status, 503, `${name}=${bad}`);
      assert.deepEqual(refused.body, { error: "server_not_configured" });
      const refreshed = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), { store, environment });
      assert.equal(refreshed.response.status, 200, "existing sessions keep working");
      signedIn.body.refreshToken = refreshed.body.refreshToken;
    }
  }
  assert.equal(store.sessions.size, 1, "nothing was created by a refused sign-in");
});

test("a sign-in the throttle can't check is refused, never let through", async () => {
  const store = { ...fakeStore(), async hitSignInLimits() { throw new VoiceAuthStoreUnavailable(); } };
  const result = await signInAs("198.51.100.6", 1, { store });
  assert.equal(result.response.status, 503);
  assert.deepEqual(result.body, { error: "server_not_configured" });
  assert.equal(store.sessions.size, 0);
  const noMethod = { ...fakeStore(), hitSignInLimits: undefined };
  assert.equal((await signInAs("198.51.100.6", 2, { store: noMethod })).response.status, 503);
});

test("a sign-in only counts once Apple has vouched for it", async () => {
  const store = fakeStore();
  for (let n = 1; n <= 25; n += 1) {
    const junk = await signInAs("198.51.100.7", n, { store, verifyAppleIdentityToken: async () => null });
    assert.equal(junk.response.status, 401);
  }
  assert.equal(store.signIns.size, 0, "unverified requests use up nobody's allowance");
  assert.equal((await signInAs("198.51.100.7", 26, { store })).response.status, 200);
});

test("only the address Vercel sets is believed; otherwise every caller shares one bucket with a higher limit", async () => {
  const environment = { ...ENV, DODDY_SIGNINS_PER_CLIENT_HOUR: "2" };
  // Headers a caller can set on any host are ignored: spoofing them buys no new allowance.
  const store = fakeStore();
  for (let n = 1; n <= 20; n += 1) {
    const result = await run(request("sign-in", { identityToken: `id-${n}`, rawNonce: nonceFor(n) }, undefined, {
      "x-forwarded-for": `192.0.2.${n}`, "x-real-ip": `192.0.2.${n}`, forwarded: `for=192.0.2.${n}`,
    }), { store, environment, verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: `s-${n}`, nonce: rawNonce }) });
    assert.equal(result.response.status, 200, `the shared bucket allows ten times the limit (${n})`);
    assert.equal(result.logs[0].noClientAddress, true, "and the log line says there was no address to use");
  }
  const spoofed = await run(request("sign-in", { identityToken: "id-21", rawNonce: nonceFor(21) }, undefined, { "x-forwarded-for": "192.0.2.99" }), {
    store, environment, verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: "s-21", nonce: rawNonce }),
  });
  assert.equal(spoofed.response.status, 429);
  assert.equal(spoofed.logs[0].noClientAddress, true);
  assert.equal(store.signIns.size, 1, "one shared bucket");

  // Off Vercel even that header is whatever the caller sends, so it is not believed either.
  const elsewhere = fakeStore();
  const offVercel = { ...environment, VERCEL: undefined };
  for (let n = 1; n <= 20; n += 1) {
    assert.equal((await signInAs(`192.0.2.${n}`, n, { store: elsewhere, environment: offVercel })).response.status, 200);
  }
  assert.equal((await signInAs("192.0.2.200", 21, { store: elsewhere, environment: offVercel })).response.status, 429);

  // On Vercel but with something that isn't an address: the same shared bucket.
  const junk = fakeStore();
  for (let n = 1; n <= 20; n += 1) assert.equal((await signInAs("not-an-address", n, { store: junk, environment })).response.status, 200);
  assert.equal((await signInAs("not-an-address", 21, { store: junk, environment })).response.status, 429);
});

test("the caller's address: first of Vercel's list, an IPv4 behind IPv6 is IPv4, other IPv6 counts as its /64", () => {
  const vercel = { VERCEL: "1" };
  const addressOf = (header, env = vercel) => clientAddress(new Request("https://example.test/", { headers: header === null ? {} : { "x-vercel-forwarded-for": header } }), env);
  assert.equal(addressOf("203.0.113.9"), "203.0.113.9");
  assert.equal(addressOf("203.0.113.9, 10.0.0.1"), "203.0.113.9");
  assert.equal(addressOf("::ffff:203.0.113.9"), "203.0.113.9");
  assert.equal(addressOf("2001:db8:1:2::1"), addressOf("2001:DB8:1:2:ffff:ffff:ffff:ffff"), "one /64 is one caller");
  assert.equal(addressOf("2001:db8:1:2::1"), "2001:db8:1:2::/64");
  assert.notEqual(addressOf("2001:db8:1:2::1"), addressOf("2001:db8:1:3::1"));
  assert.equal(addressOf(null), "unknown");
  assert.equal(addressOf(""), "unknown");
  assert.equal(addressOf("203.0.113.9", {}), "unknown", "not believed off Vercel");
  assert.equal(addressOf("203.0.113.9", { VERCEL: "" }), "unknown");
  assert.equal(addressOf("203.0.113.999"), "unknown");
  assert.equal(addressOf("<script>"), "unknown");
});

// The scripts themselves, run on a real Redis when one is installed (CI may not have it; test/local-redis.js).
test("the Redis limit script: a user over their own limit doesn't use up the global one", { skip: !hasRedis && "redis-server not installed" }, async () => {
  const { server, client } = await startLocalRedis();
  try {
    assert.ok(client, "local redis-server started");
    const store = createVoiceAuthStore({ url: "https://redis.example.test", token: "t", fetch: client.fetch });
    const perUser = 3;
    const global = 5;
    for (let i = 0; i < perUser; i += 1) assert.equal((await store.hitLimits("greedy", perUser, global, NOW)).allowed, true);
    for (let i = 0; i < 50; i += 1) {
      const over = await store.hitLimits("greedy", perUser, global, NOW);
      assert.equal(over.allowed, false);
      assert.equal(over.globalCount, perUser, "refused calls don't move the global count");
    }
    const other = await store.hitLimits("someone-else", perUser, global, NOW);
    assert.equal(other.allowed, true, "another user still gets a token");
    assert.equal(other.globalCount, perUser + 1);
    client.close();
  } finally {
    server?.kill();
  }
});

const REDIS_SKIP = !hasRedis && "redis-server not installed";
const HOUR = 3_600_000;

// ADR-712: the daily cap sits in the same step as the hourly and global limits.
test("the Redis limit script: a daily cap per account, and a refusal never uses up shared budget or the account's own allowance", { skip: REDIS_SKIP }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    // 5 an hour, 7 a day, 100 for everyone.
    for (let i = 1; i <= 5; i += 1) {
      const granted = await store.hitLimits("busy", 5, 100, NOW, 7);
      assert.deepEqual([granted.allowed, granted.limit, granted.perUserCount, granted.dailyCount, granted.globalCount], [true, null, i, i, i]);
    }
    for (let i = 0; i < 20; i += 1) {
      const refused = await store.hitLimits("busy", 5, 100, NOW, 7);
      assert.deepEqual([refused.allowed, refused.limit, refused.perUserCount, refused.dailyCount, refused.globalCount], [false, "user_hour", 5, 5, 5],
        "refused calls move no counter, the global one included");
      assert.equal(refused.retryAfterSeconds, 3_600);
    }
    // Next hour: two more fit in the day, then the daily cap says no even though the hour has room.
    for (let i = 6; i <= 7; i += 1) assert.equal((await store.hitLimits("busy", 5, 100, NOW + HOUR, 7)).allowed, true);
    for (let i = 0; i < 20; i += 1) {
      const refused = await store.hitLimits("busy", 5, 100, NOW + HOUR, 7);
      assert.deepEqual([refused.allowed, refused.limit, refused.dailyCount], [false, "user_day", 7]);
      assert.equal(refused.retryAfterSeconds, 11 * 3_600, "until the next UTC midnight");
    }
    // The shared budget only ever saw the 7 issued tokens, so others still get theirs.
    const other = await store.hitLimits("someone-else", 5, 100, NOW + HOUR, 7);
    assert.deepEqual([other.allowed, other.globalCount], [true, 3], "this hour's global count: the account's 2 issued tokens, plus this one");
    const day = Math.floor(NOW / 86_400_000);
    assert.equal(await command("GET", `doddy:voice:v1:limit-user-day:busy:${day}`), "7");
    const dayTtl = await command("TTL", `doddy:voice:v1:limit-user-day:busy:${day}`);
    assert.ok(dayTtl > 3_660 && dayTtl <= 90_000, `the daily counter lives about a day, not an hour (${dayTtl})`);
    const hourTtl = await command("TTL", `doddy:voice:v1:limit-user:busy:${Math.floor(NOW / HOUR)}`);
    assert.ok(hourTtl > 0 && hourTtl <= 3_660);
  });
});

test("the Redis limit script: a full global budget refuses without costing the account anything", { skip: REDIS_SKIP }, async () => {
  await withLocalRedis(async ({ store }) => {
    assert.equal((await store.hitLimits("a", 10, 2, NOW, 10)).allowed, true);
    assert.equal((await store.hitLimits("b", 10, 2, NOW, 10)).allowed, true);
    for (let i = 0; i < 10; i += 1) {
      const refused = await store.hitLimits("c", 10, 2, NOW, 10);
      assert.deepEqual([refused.allowed, refused.limit, refused.perUserCount, refused.dailyCount, refused.globalCount], [false, "global", 0, 0, 2]);
    }
    // When the hour's budget starts again, "c" has all of its own allowance left: one token used, not eleven.
    const later = await store.hitLimits("c", 10, 2, NOW + HOUR, 10);
    assert.deepEqual([later.allowed, later.dailyCount], [true, 1]);
  });
});

test("the Redis sign-in script: per caller, per hour and per day, counting only sign-ins that were let through", { skip: REDIS_SKIP }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    for (let i = 1; i <= 3; i += 1) {
      const granted = await store.hitSignInLimits("caller-a", 3, 5, NOW);
      assert.deepEqual([granted.allowed, granted.limit, granted.hourCount, granted.dayCount], [true, null, i, i]);
    }
    for (let i = 0; i < 20; i += 1) {
      const refused = await store.hitSignInLimits("caller-a", 3, 5, NOW);
      assert.deepEqual([refused.allowed, refused.limit, refused.hourCount, refused.dayCount], [false, "client_hour", 3, 3], "refusals don't count");
      assert.equal(refused.retryAfterSeconds, 3_600);
    }
    assert.equal((await store.hitSignInLimits("caller-b", 3, 5, NOW)).allowed, true, "another caller has its own allowance");
    for (let i = 4; i <= 5; i += 1) assert.equal((await store.hitSignInLimits("caller-a", 3, 5, NOW + HOUR)).allowed, true);
    const dayRefused = await store.hitSignInLimits("caller-a", 3, 5, NOW + HOUR);
    assert.deepEqual([dayRefused.allowed, dayRefused.limit, dayRefused.dayCount], [false, "client_day", 5]);
    assert.equal(dayRefused.retryAfterSeconds, 11 * 3_600);
    const dayTtl = await command("TTL", `doddy:voice:v1:limit-signin-day:caller-a:${Math.floor(NOW / 86_400_000)}`);
    assert.ok(dayTtl > 3_660 && dayTtl <= 90_000, `the daily counter lives about a day (${dayTtl})`);
    // A script that can't be run is "unavailable", never "allowed".
    await assert.rejects(() => store.hitSignInLimits("caller-a", "three", 5, NOW), VoiceAuthStoreUnavailable);
  });
});

test("the Redis refresh script: a swapped-out token that comes back ends the session, and only the latest one is remembered", { skip: REDIS_SKIP }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    const options = { store, verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: "apple-sub-redis", nonce: rawNonce }) };
    const refreshKeys = async () => (await command("KEYS", "doddy:voice:v1:refresh:*")).length;
    const signedIn = await run(request("sign-in", { identityToken: "id", rawNonce: NONCE }), options);
    assert.equal(signedIn.response.status, 200);
    const first = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), options);
    const second = await run(request("refresh", { refreshToken: first.body.refreshToken }), options);
    assert.equal(second.response.status, 200);
    assert.equal(await refreshKeys(), 2, "the current token and the latest swapped-out one");
    const [sessionKey] = await command("KEYS", "doddy:voice:v1:session:*");
    const hashOf = (token) => createHash("sha256").update(token).digest("hex");
    const tombstone = `doddy:voice:v1:refresh:${hashOf(first.body.refreshToken)}`;
    assert.equal(JSON.parse(await command("GET", tombstone)).used, true);
    const sessionTtl = await command("TTL", sessionKey);
    assert.ok(Math.abs(sessionTtl - await command("TTL", tombstone)) <= 2, "the remembered hash lives as long as the session");
    assert.ok(sessionTtl > 29 * 86_400);

    // Two swaps back is no longer remembered: unknown, so the same plain 401 and nothing ends.
    const old = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), options);
    assert.equal(old.response.status, 401);
    assert.equal(old.logs[0].reuse, undefined);
    const third = await run(request("refresh", { refreshToken: second.body.refreshToken }), options);
    assert.equal(third.response.status, 200, "the session lived on");

    // The latest swapped-out token coming back ends everything, in one step.
    const replay = await run(request("refresh", { refreshToken: second.body.refreshToken }), options);
    assert.equal(replay.response.status, 401);
    assert.deepEqual(replay.body, { error: "session_expired" });
    assert.equal(replay.logs[0].reuse, true);
    assert.equal(await command("GET", sessionKey), null);
    assert.equal(await refreshKeys(), 0, "no refresh record of that session is left");
    assert.equal((await run(request("refresh", { refreshToken: third.body.refreshToken }), options)).response.status, 401);
    assert.equal((await run(request("sign-out", {}, third.body.accessToken), options)).response.status, 401, "the access token is dead too");
  });
});

test("the Redis refresh script: two refreshes with the same token at once leave one winner and no session", { skip: REDIS_SKIP }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    const options = { store, verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: "apple-sub-race", nonce: rawNonce }) };
    const signedIn = await run(request("sign-in", { identityToken: "id", rawNonce: NONCE }), options);
    const both = await Promise.all([1, 2].map(() => run(request("refresh", { refreshToken: signedIn.body.refreshToken }), options)));
    assert.deepEqual(both.map((reply) => reply.response.status).sort(), [200, 401]);
    assert.equal((await command("KEYS", "doddy:voice:v1:session:*")).length, 0, "the second showing of one token ended the session");
    assert.equal((await command("KEYS", "doddy:voice:v1:refresh:*")).length, 0);
  });
});

test("the Redis scripts: sign-out and account deletion also remove the remembered swapped-out token", { skip: REDIS_SKIP }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    const options = { store, verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: "apple-sub-clean", nonce: rawNonce }) };
    const keys = async () => (await command("KEYS", "doddy:voice:v1:refresh:*")).length;
    for (const [action, nonce] of [["sign-out", "S".repeat(43)], ["delete-account", "D".repeat(43)]]) {
      const signedIn = await run(request("sign-in", { identityToken: "id", rawNonce: nonce }), options);
      const rotated = await run(request("refresh", { refreshToken: signedIn.body.refreshToken }), options);
      assert.equal(rotated.response.status, 200);
      assert.equal(await keys(), 2, `${action}: current and swapped-out`);
      const ended = await run(request(action, {}, rotated.body.accessToken), options);
      assert.equal(ended.response.status, 200);
      assert.equal(await keys(), 0, `${action} leaves no refresh record behind`);
    }
  });
});

// Decision 2026-11-09-apple-revoke-for-doddy-accounts: a Doddy account (a Supabase user) that signed
// in with Apple has its Apple token kept sealed, and Apple is told to end the link before the
// account is deleted. The account's token is checked by `authenticateDoddyAccount`, faked here.
const ACCOUNT_ID = "account:3f2b8c1e-5a47-4d3e-9b6a-0c1d2e3f4a5b";
const accountAuth = async (req) => (req.headers.get("authorization") === "Bearer account-token" ? { userId: ACCOUNT_ID, sessionId: null } : null);
const LINK_BODY = { identityToken: "apple-identity-token", rawNonce: NONCE, authorizationCode: "one-time-code" };

test("apple-link keeps Apple's token sealed under the Doddy account, and revoking removes it", async () => {
  const store = fakeStore();
  const exchanged = [];
  const revoked = [];
  const options = {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    exchangeAppleAuthorizationCode: async (code, _env, input) => { exchanged.push({ code, sub: input.expectedSub }); return "apple-refresh-token"; },
    revokeAppleToken: async (token) => { revoked.push(token); return true; },
  };
  const linked = await run(request("apple-link", LINK_BODY, "account-token"), options);
  assert.equal(linked.response.status, 200);
  assert.deepEqual(linked.body, { linked: true });
  assert.deepEqual(exchanged, [{ code: "one-time-code", sub: "apple-sub-test" }], "the code is swapped for the person the identity token names");
  const sealed = store.appleTokens.get(ACCOUNT_ID);
  assert.ok(sealed && !sealed.includes("apple-refresh-token"), "kept sealed, never in the clear");
  assert.equal(openAppleToken(sealed, SIGNING_KEY), "apple-refresh-token");
  assert.ok(!JSON.stringify(linked.logs).includes("apple-refresh-token") && !JSON.stringify(linked.logs).includes("one-time-code"), "nothing secret in the log");
  assert.deepEqual(linked.logs[0], { event: "voice_auth", action: "apple-link", status: 200, error: null, ms: 0, apple: "linked" });

  const gone = await run(request("apple-revoke", {}, "account-token"), options);
  assert.equal(gone.response.status, 200);
  assert.deepEqual(gone.body, { appleRevoked: true, apple: "revoked" });
  assert.deepEqual(revoked, ["apple-refresh-token"]);
  assert.equal(store.appleTokens.size, 0, "the sealed token is forgotten once Apple revoked it");
});

test("apple-link and apple-revoke need a valid Doddy account token and touch nothing without one", async () => {
  const store = fakeStore();
  let appleCalled = false;
  const options = {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    exchangeAppleAuthorizationCode: async () => { appleCalled = true; return "t"; },
    revokeAppleToken: async () => { appleCalled = true; return true; },
  };
  for (const action of ["apple-link", "apple-revoke"]) {
    for (const token of [undefined, "wrong-token"]) {
      const result = await run(request(action, LINK_BODY, token), options);
      assert.equal(result.response.status, 401, `${action} with ${token ?? "no token"}`);
      assert.deepEqual(result.body, { error: "session_expired" });
    }
  }
  assert.equal(appleCalled, false);
  assert.equal(store.appleTokens.size, 0);
});

test("a voice session's token cannot link or revoke: only a Doddy account's can", async () => {
  const store = fakeStore();
  const signedIn = await run(request("sign-in", { identityToken: "id", rawNonce: "V".repeat(43) }), { store, environment: APPLE_ENV });
  const result = await run(request("apple-link", LINK_BODY, signedIn.body.accessToken), {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    exchangeAppleAuthorizationCode: async () => "t",
  });
  assert.equal(result.response.status, 401);
  assert.equal(store.appleTokens.size, 0);
});

test("apple-link with a code that isn't the same Apple person's keeps nothing, and the account still works", async () => {
  const store = fakeStore();
  const result = await run(request("apple-link", LINK_BODY, "account-token"), {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    exchangeAppleAuthorizationCode: async () => null, // the swap said no: another Apple account, or Apple refused
  });
  assert.equal(result.response.status, 200);
  assert.deepEqual(result.body, { linked: false });
  assert.equal(store.appleTokens.size, 0);
});

test("apple-link refuses an identity token that Apple's keys don't vouch for", async () => {
  const store = fakeStore();
  let exchanged = false;
  const result = await run(request("apple-link", LINK_BODY, "account-token"), {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    verifyAppleIdentityToken: async () => null,
    exchangeAppleAuthorizationCode: async () => { exchanged = true; return "t"; },
  });
  assert.equal(result.response.status, 401);
  assert.deepEqual(result.body, { error: "apple_sign_in_failed" });
  assert.equal(exchanged, false, "Apple's code is not swapped for an unverified token");
  assert.equal(store.appleTokens.size, 0);
});

test("without the Sign in with Apple key, nothing is kept and Apple is never called", async () => {
  const store = fakeStore();
  let appleCalled = false;
  const options = {
    store, environment: ENV, authenticateDoddyAccount: accountAuth,
    exchangeAppleAuthorizationCode: async () => { appleCalled = true; return "t"; },
    revokeAppleToken: async () => { appleCalled = true; return true; },
  };
  const link = await run(request("apple-link", LINK_BODY, "account-token"), options);
  assert.deepEqual([link.response.status, link.body], [200, { linked: false }]);
  const revoke = await run(request("apple-revoke", {}, "account-token"), options);
  assert.deepEqual([revoke.response.status, revoke.body], [200, { appleRevoked: false, apple: "not_configured" }]);
  assert.equal(appleCalled, false);
  assert.equal(store.appleTokens.size, 0);
});

test("apple-revoke says no_token when none was kept, and keeps the token when Apple fails so asking again can work", async () => {
  const store = fakeStore();
  let appleOk = false;
  const options = {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    revokeAppleToken: async () => appleOk,
  };
  const none = await run(request("apple-revoke", {}, "account-token"), options);
  assert.deepEqual(none.body, { appleRevoked: false, apple: "no_token" });

  store.appleTokens.set(ACCOUNT_ID, sealAppleToken("apple-refresh-token", SIGNING_KEY));
  const failed = await run(request("apple-revoke", {}, "account-token"), options);
  assert.deepEqual(failed.body, { appleRevoked: false, apple: "failed" });
  assert.equal(failed.response.status, 200, "Apple failing is reported, not an error: the deletion goes on");
  assert.ok(store.appleTokens.has(ACCOUNT_ID), "kept for another try");

  appleOk = true;
  const retried = await run(request("apple-revoke", {}, "account-token"), options);
  assert.deepEqual(retried.body, { appleRevoked: true, apple: "revoked" });
  assert.equal(store.appleTokens.size, 0);
});

test("a token sealed for one Doddy account is never revoked for another", async () => {
  const store = fakeStore();
  store.appleTokens.set("account:00000000-0000-4000-8000-000000000000", sealAppleToken("someone-elses-token", SIGNING_KEY));
  let revoked = false;
  const result = await run(request("apple-revoke", {}, "account-token"), {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    revokeAppleToken: async () => { revoked = true; return true; },
  });
  assert.deepEqual(result.body, { appleRevoked: false, apple: "no_token" });
  assert.equal(revoked, false);
  assert.equal(store.appleTokens.size, 1, "the other account's token is untouched");
});

test("when the project's signing keys can't be read the answer is 503, never 'signed out'", async () => {
  const { AccountCheckUnavailable } = await import("../src/doddy-account.js");
  const result = await run(request("apple-revoke", {}, "account-token"), {
    environment: APPLE_ENV,
    authenticateDoddyAccount: async () => { throw new AccountCheckUnavailable(); },
  });
  assert.equal(result.response.status, 503);
  assert.deepEqual(result.body, { error: "account_check_unavailable" });
});

test("apple-link is limited per account like a sign-in, and a refused one never reaches Apple", async () => {
  const store = fakeStore();
  let swaps = 0;
  const options = {
    store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth,
    exchangeAppleAuthorizationCode: async () => { swaps += 1; return "t"; },
  };
  for (let n = 0; n < 10; n += 1) assert.equal((await run(request("apple-link", LINK_BODY, "account-token"), options)).response.status, 200);
  const refused = await run(request("apple-link", LINK_BODY, "account-token"), options);
  assert.equal(refused.response.status, 429);
  assert.match(refused.response.headers.get("retry-after"), /^[1-9][0-9]*$/);
  assert.equal(swaps, 10);
});

test("apple-link rejects a malformed body before anything is checked or kept", async () => {
  const store = fakeStore();
  for (const bad of [{}, { ...LINK_BODY, authorizationCode: "" }, { ...LINK_BODY, authorizationCode: "x".repeat(1_025) },
    { ...LINK_BODY, rawNonce: "short" }, { ...LINK_BODY, identityToken: "x".repeat(18_001) }, { ...LINK_BODY, identityToken: 7 }]) {
    const result = await run(request("apple-link", bad, "account-token"), { store, environment: APPLE_ENV, authenticateDoddyAccount: accountAuth });
    assert.equal(result.response.status, 400);
    assert.deepEqual(result.body, { error: "invalid_request" });
  }
  assert.equal(store.appleTokens.size, 0);
});

test("the Redis adapter's deleteAppleToken deletes only the one sealed Apple token", async () => {
  let sent;
  const store = createVoiceAuthStore({
    url: "https://redis.example.test", token: "store-secret",
    fetch: async (_url, init) => { sent = JSON.parse(init.body); return Response.json([{ result: 1 }]); },
  });
  await store.deleteAppleToken(ACCOUNT_ID);
  assert.deepEqual(sent, [["DEL", `doddy:voice:v1:apple-token:${ACCOUNT_ID}`]]);
});
