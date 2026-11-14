// One key per job, with a key id and a previous key for rotation (decision 2026-11-12-account-and-device-tokens,
// part b). The voice server's signing key used to be used as it was for everything: it signed the access tokens,
// pseudonymized the Apple subjects and the caller addresses, tagged each account's voice conversations and, through a
// derived key, sealed Apple's refresh token. Now each job gets its own key derived from it, every signed or sealed
// value carries a key id, and `DODDY_SESSION_SIGNING_KEY_PREVIOUS` is accepted for checking and opening only.
//
// Everything issued before the change has to keep working with no setting changed at deploy, and the identifiers
// (the Apple pseudonyms, the conversation record keys, the rate-limit buckets) have to stay byte for byte the same:
// `BEFORE` holds what the code as it was before this change (2dc7af33) made from the fixed fake key `SECRET`.
import assert from "node:assert/strict";
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes } from "node:crypto";
import { test } from "node:test";
import { fakeConversationStore, fakeElevenLabs } from "./conversation-fakes.js";
import { hasRedis, withLocalRedis } from "./local-redis.js";
import { conversationIdentity } from "../src/conversations.js";
import { handleTokenRequest } from "../src/handler.js";
import {
  ACCESS_TOKEN_LABEL, APPLE_TOKEN_SEAL_LABEL, asKeyRing, keyId, keyRingFromEnv, purposeKey,
} from "../src/keys.js";
import {
  authenticateVoiceSession, handleVoiceAuthRequest, openAppleToken, sealAppleToken, signAccessToken, verifyAccessToken,
} from "../src/voice-auth.js";

const NOW = Date.parse("2026-10-16T12:00:00Z");
const NONCE = "A".repeat(43);
// Obviously fake, and made up for these tests: none of these was ever a real key.
const SECRET = "voice-keys-test-secret-not-real-000000";
const NEW_SECRET = "voice-keys-test-secret-newer-not-real-0000";
const OTHER_SECRET = "voice-keys-test-secret-other-not-real-000";
const SUB = "000000.fake-apple-subject-not-real.0000";
const ACCOUNT = "account:00000000-0000-4000-8000-000000000000";
const SESSION_ID = "session-id-fixed-not-real";
const APPLE_REFRESH = "fake-apple-refresh-token-not-real";
const CALLER = "203.0.113.7";

/** What the code before this change made from SECRET (recorded by running it, before anything here was written). */
const BEFORE = {
  applePseudonym: "4914239b4ad9ff444756bb8e6e2e8ab54ca6a65dfbab162e0a5cf8cd210df828",
  signInBucket: "302484ddf7739a4a1e58a63e36cca12e1afd613fb5b45ab487f938a30f6d1bfb",
  deleteConversationsBucket: "088a3269482ff4a118d6211669b03004b9a5f29006e963d07e1b79f97decdc56",
  appleLinkBucket: "e53b5f15f90b4953704b0d0df82e8e598473f2be189344d6496952c916f40175",
  conversationsOfDoddyAccount: { recordKey: "634169d84c2ed905109816cdffba2d8f91627816b3626708087093bf302bfa30", userId: "fed5d5f4d93b6059369e943282373c68" },
  conversationsOfApplePseudonym: { recordKey: "5ae782b972f690f6779ef37cca8d295d953f898d57974c4b2f3f52591c494699", userId: "1a66c934b3965d03c7cbde3182df85d4" },
  // An access token for the pseudonym and SESSION_ID issued at NOW, and Apple's refresh token sealed (opens to APPLE_REFRESH).
  accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJkb2RkeS12b2ljZSIsImF1ZCI6InZvaWNlIiwic3ViIjoiNDkxNDIzOWI0YWQ5ZmY0NDQ3NTZiYjhlNmUyZThhYjU0Y2E2YTY1ZGZiYWIxNjJlMGE1Y2Y4Y2QyMTBkZjgyOCIsInNpZCI6InNlc3Npb24taWQtZml4ZWQtbm90LXJlYWwiLCJpYXQiOjE3OTIxNTIwMDAsImV4cCI6MTc5MjE1MjYwMH0.zNX2hkrhiOodyXHidnNWS7j-qXKaYDG0sQkGm3buce4",
  sealedAppleToken: "b104nI8KSPMnlo3luPz2tLeeOBm3mBBxzq1wGuF0W8xusRA3N9VdYygps6yzLG4Ebkl1Pso6BAGpjjSpHw",
};

// ---- helpers ----

const ENV = {
  APPLE_BUNDLE_ID: "com.example.test", DODDY_SESSION_SIGNING_KEY: SECRET,
  ELEVENLABS_API_KEY: "elevenlabs-test-not-real", ELEVENLABS_AGENT_ID: "agent_test", VERCEL: "1",
};
/** The owner's rotation: the identifiers are pinned to the old value, the old key is kept for checking, a new key signs. */
const ROTATED = { ...ENV, DODDY_SESSION_SIGNING_KEY: NEW_SECRET, DODDY_SESSION_SIGNING_KEY_PREVIOUS: SECRET, DODDY_IDENTIFIER_KEY: SECRET };
/** The same after the previous key has been removed again. */
const ROTATED_FOR_GOOD = { ...ROTATED, DODDY_SESSION_SIGNING_KEY_PREVIOUS: undefined };
const APPLE_ENV = (env) => ({ ...env, APPLE_TEAM_ID: "TEAMID1234", APPLE_SIGN_IN_KEY_ID: "KEYID12345", APPLE_SIGN_IN_PRIVATE_KEY: "not-a-real-key" });

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const base64url = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
const headerOf = (token) => JSON.parse(Buffer.from(token.split(".")[0], "base64url").toString("utf8"));

/** An independent HKDF-SHA256 (RFC 5869, zero salt), written from the RFC and not from Node's own. */
function rfc5869(ikm, info, length) {
  const prk = createHmac("sha256", Buffer.alloc(32)).update(ikm).digest();
  let previous = Buffer.alloc(0);
  const blocks = [];
  for (let i = 1; Buffer.concat(blocks).length < length; i += 1) {
    previous = createHmac("sha256", prk).update(Buffer.concat([previous, Buffer.from(info), Buffer.from([i])])).digest();
    blocks.push(previous);
  }
  return Buffer.concat(blocks).subarray(0, length);
}

/** An access token as this server forms them, signed with whatever key and header the test hands it. */
function jwt(header, key, { userId = BEFORE.applePseudonym, sessionId = SESSION_ID, now = NOW } = {}) {
  const seconds = Math.floor(now / 1_000);
  const input = `${base64url(header)}.${base64url({ iss: "doddy-voice", aud: "voice", sub: userId, sid: sessionId, iat: seconds, exp: seconds + 600 })}`;
  return `${input}.${createHmac("sha256", key).update(input).digest("base64url")}`;
}
/** The format before key ids: no `kid`, signed with the key itself. */
const oldFormatToken = (secret, options) => jwt({ alg: "HS256", typ: "JWT" }, secret, options);

/** A sealed value in the documented layout, `v2.<key id>.<iv, ciphertext, tag>`, made with any key. */
function sealWith(key, plaintext, kid) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const body = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return `v2.${kid}.${Buffer.concat([iv, body, cipher.getAuthTag()]).toString("base64url")}`;
}

/** The part of the voice store these tests touch, in memory (the Redis one is covered in voice-auth.test.js). */
function fakeStore() {
  const sessions = new Map();
  const refresh = new Map();
  const appleTokens = new Map();
  const buckets = [];
  const created = [];
  return {
    ...fakeConversationStore(),
    sessions, refresh, appleTokens, buckets, created,
    async hitSignInLimits(bucket) { buckets.push(bucket); return { allowed: true, limit: null, retryAfterSeconds: 60 }; },
    async hitLimits() { return { allowed: true, limit: null, retryAfterSeconds: 60 }; },
    async createSession(input) {
      created.push(input);
      sessions.set(input.sessionId, { userId: input.userId, sessionId: input.sessionId, refreshHash: input.refreshHash });
      refresh.set(input.refreshHash, { userId: input.userId, sessionId: input.sessionId });
      return 1;
    },
    async getRefresh(hash) { return refresh.get(hash) ?? null; },
    async getSession(id) { return sessions.get(id) ?? null; },
    async rotateRefreshSession(oldHash, newHash, prior) {
      const session = sessions.get(prior.sessionId);
      if (!refresh.has(oldHash) || !session) return null;
      refresh.set(newHash, { userId: prior.userId, sessionId: prior.sessionId });
      refresh.set(oldHash, { ...refresh.get(oldHash), used: true });
      sessions.set(prior.sessionId, { ...session, refreshHash: newHash, previousRefreshHash: oldHash });
      return sessions.get(prior.sessionId);
    },
    async revokeSession(id, userId) {
      const session = sessions.get(id);
      if (!session || session.userId !== userId) return 0;
      sessions.delete(id);
      return 1;
    },
    async setAppleToken(userId, sealed) { appleTokens.set(userId, sealed); },
    async getAppleToken(userId) { return appleTokens.get(userId) ?? null; },
    async deleteAppleToken(userId) { appleTokens.delete(userId); },
    async deleteAccount(userId) {
      let deleted = 0;
      for (const [id, session] of [...sessions]) if (session.userId === userId) { sessions.delete(id); deleted += 1; }
      appleTokens.delete(userId);
      return deleted;
    },
  };
}

function request(action, body = {}, bearer) {
  return new Request("https://example.test/api/voice-auth", {
    method: "POST",
    headers: { "content-type": "application/json", "x-vercel-forwarded-for": CALLER, ...(bearer ? { authorization: `Bearer ${bearer}` } : {}) },
    body: JSON.stringify({ action, ...(action === "sign-in" ? { provider: "elevenlabs" } : {}), ...body }),
  });
}

async function call(action, body, { env = ENV, store = fakeStore(), bearer, ...deps } = {}) {
  const logs = [];
  const response = await handleVoiceAuthRequest(request(action, body, bearer), env, {
    store, now: () => NOW, log: (line) => logs.push(line),
    verifyAppleIdentityToken: async (_token, rawNonce) => ({ sub: SUB, nonce: rawNonce }),
    elevenLabsFetch: fakeElevenLabs({ apiKey: ENV.ELEVENLABS_API_KEY }).fetch,
    ...deps,
  });
  return { response, body: await response.json(), logs, store };
}

const signIn = (options) => call("sign-in", { identityToken: "apple-id-token-not-real", rawNonce: NONCE }, options);

/** `/api/voice-token` for a voice session: the real session check against a store holding that session. */
async function voiceToken(env, bearer, store = fakeStore()) {
  const logs = [];
  const response = await handleTokenRequest(
    new Request("https://example.test/api/voice-token", { method: "POST", headers: { authorization: `Bearer ${bearer}` } }),
    env,
    {
      authStore: store, now: () => NOW, log: (line) => logs.push(line),
      fetch: async () => Response.json({ token: "provider-credential-not-real", conversation_id: "conv_1" }),
    },
  );
  return { response, body: await response.json(), logs };
}

/** A session as the code before this change stored it at sign-in. */
function sessionFromBefore(store, refreshToken = "r".repeat(43)) {
  const refreshHash = sha256(refreshToken);
  store.sessions.set(SESSION_ID, { userId: BEFORE.applePseudonym, sessionId: SESSION_ID, refreshHash });
  store.refresh.set(refreshHash, { userId: BEFORE.applePseudonym, sessionId: SESSION_ID });
  return refreshToken;
}

// ---- the helpers model the old format exactly ----

test("the test helpers reproduce what the code before this change made: the recorded token and the recorded identifiers", () => {
  assert.equal(oldFormatToken(SECRET), BEFORE.accessToken);
  const hmac = (message) => createHmac("sha256", SECRET).update(message).digest("hex");
  assert.equal(hmac(`apple-sub:${SUB}`), BEFORE.applePseudonym);
  assert.equal(hmac(`client:${CALLER}`), BEFORE.signInBucket);
  assert.equal(hmac(`delete-conversations:${ACCOUNT}`), BEFORE.deleteConversationsBucket);
  assert.equal(hmac(`apple-link:${ACCOUNT}`), BEFORE.appleLinkBucket);
  // The old way of sealing: AES-256-GCM, the key an HMAC of a fixed word, the layout iv + ciphertext + tag.
  const sealKey = createHmac("sha256", SECRET).update("apple-refresh-token:v1").digest();
  const raw = Buffer.from(BEFORE.sealedAppleToken, "base64url");
  const decipher = createDecipheriv("aes-256-gcm", sealKey, raw.subarray(0, 12));
  decipher.setAuthTag(raw.subarray(raw.length - 16));
  assert.equal(Buffer.concat([decipher.update(raw.subarray(12, raw.length - 16)), decipher.final()]).toString("utf8"), APPLE_REFRESH);
});

// ---- the key module ----

test("a purpose key is HKDF-SHA256 over the key with a fixed label, as an independent RFC 5869 implementation makes it", () => {
  for (const label of [ACCESS_TOKEN_LABEL, APPLE_TOKEN_SEAL_LABEL, "doddy/voice/another-job/v1"]) {
    assert.deepEqual(purposeKey(SECRET, label), rfc5869(Buffer.from(SECRET, "utf8"), label, 32), label);
  }
  assert.equal(ACCESS_TOKEN_LABEL, "doddy/voice/access-token/v1");
  assert.equal(APPLE_TOKEN_SEAL_LABEL, "doddy/voice/apple-token-seal/v1");
});

test("the labels are frozen: known answers for a fixed fake key (changing a label would sign everyone out)", () => {
  assert.equal(purposeKey(SECRET, ACCESS_TOKEN_LABEL).toString("hex"), "c40d8e0431361bee269c567edea0d4e4dd52ecbd5a28b2eb5755bd0c6ca40edc");
  assert.equal(purposeKey(SECRET, APPLE_TOKEN_SEAL_LABEL).toString("hex"), "78a86e51103d9e7a23bbec87d3429a1bfc15603248ca5c9b191ddce658d91766");
  assert.equal(keyId(SECRET), "TUkr1_pI");
});

test("each job gets its own key, none is the key itself, and another key gives other keys", () => {
  const access = purposeKey(SECRET, ACCESS_TOKEN_LABEL);
  const seal = purposeKey(SECRET, APPLE_TOKEN_SEAL_LABEL);
  assert.equal(access.length, 32);
  assert.notDeepEqual(access, seal);
  for (const derived of [access, seal]) {
    assert.notDeepEqual(derived, Buffer.from(SECRET, "utf8").subarray(0, 32));
    assert.notDeepEqual(derived, createHmac("sha256", SECRET).update("apple-refresh-token:v1").digest());
  }
  assert.notDeepEqual(purposeKey(NEW_SECRET, ACCESS_TOKEN_LABEL), access);
  assert.deepEqual(purposeKey(SECRET, ACCESS_TOKEN_LABEL), access, "the same key and label always give the same key");
});

test("a key id names the key without giving it away", () => {
  assert.match(keyId(SECRET), /^[A-Za-z0-9_-]{8}$/);
  assert.notEqual(keyId(SECRET), keyId(NEW_SECRET));
  assert.equal(keyId(SECRET), keyId(SECRET));
  for (const secretText of [SECRET, purposeKey(SECRET, ACCESS_TOKEN_LABEL).toString("hex"), purposeKey(SECRET, ACCESS_TOKEN_LABEL).toString("base64url")]) {
    assert.ok(!secretText.includes(keyId(SECRET)), "the id is not a piece of the key or of a key derived from it");
  }
  assert.ok(!SECRET.includes(keyId(SECRET)));
});

test("settings: the signing key alone works as it did; the previous key and the identifier key are optional extras", () => {
  const alone = keyRingFromEnv({ DODDY_SESSION_SIGNING_KEY: SECRET });
  assert.equal(alone.current.master, SECRET);
  assert.equal(alone.current.kid, keyId(SECRET));
  assert.equal(alone.previous, null);
  assert.equal(alone.identifier, SECRET, "with no identifier key set, identifiers use the signing key exactly as before");

  const rotated = keyRingFromEnv(ROTATED);
  assert.equal(rotated.current.master, NEW_SECRET);
  assert.equal(rotated.previous.master, SECRET);
  assert.equal(rotated.previous.kid, keyId(SECRET));
  assert.equal(rotated.identifier, SECRET);

  const pinned = keyRingFromEnv({ DODDY_SESSION_SIGNING_KEY: SECRET, DODDY_IDENTIFIER_KEY: OTHER_SECRET });
  assert.equal(pinned.identifier, OTHER_SECRET);
  assert.equal(pinned.previous, null);
});

test("settings: a previous key without a pinned identifier key is refused, so a rotation can never change anyone's identifier", () => {
  assert.equal(keyRingFromEnv({ DODDY_SESSION_SIGNING_KEY: NEW_SECRET, DODDY_SESSION_SIGNING_KEY_PREVIOUS: SECRET }), null);
  assert.equal(conversationIdentity({ DODDY_SESSION_SIGNING_KEY: NEW_SECRET, DODDY_SESSION_SIGNING_KEY_PREVIOUS: SECRET }, ACCOUNT), null);
  // The same previous key as the signing key is no rotation at all.
  assert.equal(keyRingFromEnv({ DODDY_SESSION_SIGNING_KEY: SECRET, DODDY_SESSION_SIGNING_KEY_PREVIOUS: SECRET }).previous, null);
});

test("settings: a key that is too short is refused (fails closed like a bad limit), a blank one is the same as not set", () => {
  assert.equal(keyRingFromEnv({ DODDY_SESSION_SIGNING_KEY: "short" }), null);
  assert.equal(keyRingFromEnv({}), null);
  assert.equal(keyRingFromEnv({ ...ROTATED, DODDY_SESSION_SIGNING_KEY_PREVIOUS: "short" }), null);
  assert.equal(keyRingFromEnv({ ...ROTATED, DODDY_IDENTIFIER_KEY: "short" }), null);
  for (const blank of [undefined, "", "   "]) {
    const ring = keyRingFromEnv({ DODDY_SESSION_SIGNING_KEY: SECRET, DODDY_SESSION_SIGNING_KEY_PREVIOUS: blank, DODDY_IDENTIFIER_KEY: blank });
    assert.equal(ring.previous, null);
    assert.equal(ring.identifier, SECRET);
  }
});

test("a plain secret is read as a key set of its own (what the older callers pass)", () => {
  assert.equal(asKeyRing(SECRET).current.master, SECRET);
  assert.equal(asKeyRing(SECRET).identifier, SECRET);
  assert.equal(asKeyRing("short"), null);
  const ring = keyRingFromEnv(ROTATED);
  assert.equal(asKeyRing(ring), ring);
});

// ---- access tokens ----

test("a new access token carries the id of the current key and is signed with the access-token key, not with the key itself", () => {
  const token = signAccessToken({ userId: BEFORE.applePseudonym, sessionId: SESSION_ID }, SECRET, NOW);
  assert.deepEqual(headerOf(token), { alg: "HS256", typ: "JWT", kid: keyId(SECRET) });
  const [header, claims, signature] = token.split(".");
  const expected = createHmac("sha256", purposeKey(SECRET, ACCESS_TOKEN_LABEL)).update(`${header}.${claims}`).digest("base64url");
  assert.equal(signature, expected);
  assert.notEqual(signature, createHmac("sha256", SECRET).update(`${header}.${claims}`).digest("base64url"));
  const verified = verifyAccessToken(token, SECRET, NOW);
  assert.equal(verified.sub, BEFORE.applePseudonym);
  assert.equal(verified.sid, SESSION_ID);
  assert.equal(verified.exp, Math.floor(NOW / 1_000) + 600, "still 10 minutes");
});

test("a token made for another job is refused as an access token, whatever its header says", () => {
  const ring = keyRingFromEnv(ENV);
  const kid = keyId(SECRET);
  const header = { alg: "HS256", typ: "JWT", kid };
  const own = jwt(header, purposeKey(SECRET, ACCESS_TOKEN_LABEL));
  assert.ok(verifyAccessToken(own, ring, NOW), "the control: signed with the access-token key it passes");
  const foreign = [
    purposeKey(SECRET, APPLE_TOKEN_SEAL_LABEL),
    purposeKey(SECRET, "doddy/voice/another-job/v1"),
    createHmac("sha256", SECRET).update("apple-refresh-token:v1").digest(),
    Buffer.from(SECRET, "utf8"),
    purposeKey(OTHER_SECRET, ACCESS_TOKEN_LABEL),
  ];
  for (const key of foreign) assert.equal(verifyAccessToken(jwt(header, key), ring, NOW), null);
});

test("an access token from before this change is accepted, until it expires", () => {
  const claims = verifyAccessToken(BEFORE.accessToken, SECRET, NOW);
  assert.equal(claims.sub, BEFORE.applePseudonym);
  assert.equal(claims.sid, SESSION_ID);
  assert.equal(verifyAccessToken(BEFORE.accessToken, keyRingFromEnv(ENV), NOW + 599_000).sid, SESSION_ID);
  assert.equal(verifyAccessToken(BEFORE.accessToken, SECRET, NOW + 11 * 60_000), null, "it still ends after its 10 minutes");
  assert.equal(verifyAccessToken(BEFORE.accessToken, OTHER_SECRET, NOW), null, "and only this server's key opens it");
});

test("the previous key is accepted for checking: old and new format tokens made with it", () => {
  const before = keyRingFromEnv(ENV);
  const after = keyRingFromEnv(ROTATED);
  const newFormatUnderOld = signAccessToken({ userId: "user", sessionId: "session" }, before, NOW);
  const oldFormatUnderOld = oldFormatToken(SECRET, { userId: "user", sessionId: "session" });
  for (const token of [newFormatUnderOld, oldFormatUnderOld]) {
    assert.equal(verifyAccessToken(token, after, NOW).sub, "user");
    assert.equal(verifyAccessToken(token, keyRingFromEnv(ROTATED_FOR_GOOD), NOW), null, "gone once the previous key is removed");
  }
  // And the current key's own tokens, of course.
  assert.equal(verifyAccessToken(signAccessToken({ userId: "u", sessionId: "s" }, after, NOW), after, NOW).sub, "u");
});

test("an unknown key id is refused, and never falls back to checking with the key itself", () => {
  const ring = keyRingFromEnv(ROTATED);
  const unknown = { alg: "HS256", typ: "JWT", kid: keyId(OTHER_SECRET) };
  assert.equal(verifyAccessToken(jwt(unknown, purposeKey(OTHER_SECRET, ACCESS_TOKEN_LABEL)), ring, NOW), null, "a real key of someone else");
  // A token that names a key id nobody here has, signed with the keys this server does have.
  for (const secret of [SECRET, NEW_SECRET]) {
    assert.equal(verifyAccessToken(jwt(unknown, secret), ring, NOW), null);
    assert.equal(verifyAccessToken(jwt(unknown, purposeKey(secret, ACCESS_TOKEN_LABEL)), ring, NOW), null);
  }
  // A known id with the key itself (the old way of signing) is not the new format either.
  assert.equal(verifyAccessToken(jwt({ alg: "HS256", typ: "JWT", kid: keyId(NEW_SECRET) }, NEW_SECRET), ring, NOW), null);
  for (const kid of [null, 7, "", {}, []]) {
    assert.equal(verifyAccessToken(jwt({ alg: "HS256", typ: "JWT", kid }, NEW_SECRET), ring, NOW), null, JSON.stringify(kid));
    assert.equal(verifyAccessToken(jwt({ alg: "HS256", typ: "JWT", kid }, purposeKey(NEW_SECRET, ACCESS_TOKEN_LABEL)), ring, NOW), null, JSON.stringify(kid));
  }
});

test("changing the key id of a token breaks it: the header is signed too", () => {
  const ring = keyRingFromEnv(ROTATED);
  const token = signAccessToken({ userId: "user", sessionId: "session" }, ring, NOW);
  const [, claims, signature] = token.split(".");
  const swapped = `${base64url({ alg: "HS256", typ: "JWT", kid: ring.previous.kid })}.${claims}.${signature}`;
  assert.equal(verifyAccessToken(swapped, ring, NOW), null);
  const noKid = `${base64url({ alg: "HS256", typ: "JWT" })}.${claims}.${signature}`;
  assert.equal(verifyAccessToken(noKid, ring, NOW), null, "dropping the id turns it into an old-format token, which it was not signed as");
  const otherAlgorithm = `${base64url({ alg: "none", typ: "JWT", kid: ring.current.kid })}.${claims}.`;
  assert.equal(verifyAccessToken(otherAlgorithm, ring, NOW), null);
});

test("the previous key never signs: a new token names the current key and the current key alone checks it", () => {
  const ring = keyRingFromEnv(ROTATED);
  const token = signAccessToken({ userId: "user", sessionId: "session" }, ring, NOW);
  assert.equal(headerOf(token).kid, keyId(NEW_SECRET));
  assert.notEqual(headerOf(token).kid, keyId(SECRET));
  assert.equal(verifyAccessToken(token, keyRingFromEnv(ROTATED_FOR_GOOD), NOW).sub, "user", "the current key alone is enough");
  assert.equal(verifyAccessToken(token, keyRingFromEnv({ ...ENV }), NOW), null, "the previous key alone is not");
  const [header, claims, signature] = token.split(".");
  assert.notEqual(signature, createHmac("sha256", purposeKey(SECRET, ACCESS_TOKEN_LABEL)).update(`${header}.${claims}`).digest("base64url"));
});

// ---- sealed Apple tokens ----

test("a sealed Apple token is v2.<key id>.<value>, sealed with the Apple-token key, and never shows the token", () => {
  const sealed = sealAppleToken(APPLE_REFRESH, SECRET);
  const [version, kid, payload, ...extra] = sealed.split(".");
  assert.deepEqual([version, kid, extra.length], ["v2", keyId(SECRET), 0]);
  assert.ok(!sealed.includes(APPLE_REFRESH) && !Buffer.from(payload, "base64url").includes(APPLE_REFRESH));
  assert.notEqual(sealAppleToken(APPLE_REFRESH, SECRET), sealed, "a fresh nonce every time");
  assert.equal(openAppleToken(sealed, SECRET), APPLE_REFRESH);
  // The documented layout opens with the documented key, so a reader can be written from the README alone.
  assert.equal(openAppleToken(sealWith(purposeKey(SECRET, APPLE_TOKEN_SEAL_LABEL), APPLE_REFRESH, keyId(SECRET)), SECRET), APPLE_REFRESH);
});

test("a sealed value made with another job's key, or touched anywhere, does not open", () => {
  const ring = keyRingFromEnv(ENV);
  const kid = keyId(SECRET);
  assert.equal(openAppleToken(sealWith(purposeKey(SECRET, ACCESS_TOKEN_LABEL), APPLE_REFRESH, kid), ring), null, "the access-token key");
  assert.equal(openAppleToken(sealWith(purposeKey(SECRET, "doddy/voice/another-job/v1"), APPLE_REFRESH, kid), ring), null);
  assert.equal(openAppleToken(sealWith(createHmac("sha256", SECRET).update("apple-refresh-token:v1").digest(), APPLE_REFRESH, kid), ring), null, "the key of the old format");
  assert.equal(openAppleToken(sealWith(Buffer.from(SECRET, "utf8").subarray(0, 32), APPLE_REFRESH, kid), ring), null, "the key itself");
  assert.equal(openAppleToken(sealAppleToken(APPLE_REFRESH, OTHER_SECRET), ring), null, "another server's key");

  const sealed = sealAppleToken(APPLE_REFRESH, ring);
  const [version, , payload] = sealed.split(".");
  const bytes = Buffer.from(payload, "base64url");
  for (const at of [0, 14, bytes.length - 1]) {
    const touched = Buffer.from(bytes);
    touched[at] ^= 1;
    assert.equal(openAppleToken(`${version}.${kid}.${touched.toString("base64url")}`, ring), null, `byte ${at}`);
  }
  for (const broken of [`v3.${kid}.${payload}`, `v2.${kid}`, `v2.${kid}.${payload}.x`, `${kid}.${payload}`, `v2..${payload}`, "v2.", ".", "", "short"]) {
    assert.equal(openAppleToken(broken, ring), null, broken);
  }
  assert.equal(openAppleToken(undefined, ring), null);
});

test("a sealed Apple token from before this change opens, with the key itself or as the previous key", () => {
  assert.equal(openAppleToken(BEFORE.sealedAppleToken, SECRET), APPLE_REFRESH);
  assert.equal(openAppleToken(BEFORE.sealedAppleToken, keyRingFromEnv(ENV)), APPLE_REFRESH);
  assert.equal(openAppleToken(BEFORE.sealedAppleToken, keyRingFromEnv(ROTATED)), APPLE_REFRESH, "under the previous key after a rotation");
  assert.equal(openAppleToken(BEFORE.sealedAppleToken, keyRingFromEnv(ROTATED_FOR_GOOD)), null, "gone once it is removed");
  assert.equal(openAppleToken(BEFORE.sealedAppleToken, OTHER_SECRET), null);
});

test("the previous key opens but never seals: a new sealed value names the current key", () => {
  const ring = keyRingFromEnv(ROTATED);
  const underOld = sealAppleToken(APPLE_REFRESH, keyRingFromEnv(ENV));
  assert.equal(openAppleToken(underOld, ring), APPLE_REFRESH);
  assert.equal(openAppleToken(underOld, keyRingFromEnv(ROTATED_FOR_GOOD)), null);
  const sealed = sealAppleToken(APPLE_REFRESH, ring);
  assert.equal(sealed.split(".")[1], keyId(NEW_SECRET));
  assert.equal(openAppleToken(sealed, keyRingFromEnv(ROTATED_FOR_GOOD)), APPLE_REFRESH);
  assert.equal(openAppleToken(sealed, keyRingFromEnv(ENV)), null);
  assert.equal(openAppleToken(`v2.${keyId(OTHER_SECRET)}.${sealed.split(".")[2]}`, ring), null, "an id nobody here has");
});

// ---- identifiers stay byte for byte the same ----

test("Apple pseudonyms, conversation record keys and rate-limit buckets are what the code before this change made", async () => {
  const store = fakeStore();
  const signedIn = await signIn({ store });
  assert.equal(signedIn.response.status, 200);
  assert.equal(store.created[0].userId, BEFORE.applePseudonym);
  assert.equal(store.buckets[0], BEFORE.signInBucket);
  assert.deepEqual(conversationIdentity(ENV, ACCOUNT), BEFORE.conversationsOfDoddyAccount);
  assert.deepEqual(conversationIdentity(ENV, BEFORE.applePseudonym), BEFORE.conversationsOfApplePseudonym);

  const sweep = await call("delete-conversations", {}, { store, bearer: "account-token-not-real", authenticateDoddyAccount: async () => ({ userId: ACCOUNT }) });
  assert.equal(sweep.response.status, 200);
  assert.equal(store.buckets[1], BEFORE.deleteConversationsBucket);
  await call("apple-link", { identityToken: "id", rawNonce: NONCE, authorizationCode: "code-not-real" }, {
    store, env: APPLE_ENV(ENV), bearer: "account-token-not-real", authenticateDoddyAccount: async () => ({ userId: ACCOUNT }),
    exchangeAppleAuthorizationCode: async () => APPLE_REFRESH,
  });
  assert.equal(store.buckets[2], BEFORE.appleLinkBucket);
});

test("the same identifiers after a rotation, with the identifier key pinned to the old value (and with it set to the same value)", async () => {
  for (const env of [ROTATED, ROTATED_FOR_GOOD, { ...ENV, DODDY_IDENTIFIER_KEY: SECRET }]) {
    const store = fakeStore();
    const signedIn = await signIn({ store, env });
    assert.equal(signedIn.response.status, 200);
    assert.equal(store.created[0].userId, BEFORE.applePseudonym);
    assert.equal(store.buckets[0], BEFORE.signInBucket);
    assert.deepEqual(conversationIdentity(env, ACCOUNT), BEFORE.conversationsOfDoddyAccount);
    assert.deepEqual(conversationIdentity(env, BEFORE.applePseudonym), BEFORE.conversationsOfApplePseudonym);
  }
});

test("a previous key without the pinned identifier key stops sign-in and conversations with server_not_configured, creating nothing", async () => {
  const env = { ...ENV, DODDY_SESSION_SIGNING_KEY: NEW_SECRET, DODDY_SESSION_SIGNING_KEY_PREVIOUS: SECRET };
  const store = fakeStore();
  const signedIn = await signIn({ store, env });
  assert.equal(signedIn.response.status, 503);
  assert.deepEqual(signedIn.body, { error: "server_not_configured" });
  assert.equal(store.created.length, 0);
  const token = await voiceToken(env, oldFormatToken(NEW_SECRET), store);
  assert.equal(token.response.status, 503);
  assert.deepEqual(token.body, { error: "server_not_configured" });
});

// ---- what was issued before keeps working, at deploy and across a rotation ----

test("a session from before the change keeps working with no setting changed: its access token, its refresh token, sign-out", async () => {
  const store = fakeStore();
  const refreshToken = sessionFromBefore(store);
  assert.deepEqual(await authenticateVoiceSession(new Request("https://example.test", { headers: { authorization: `Bearer ${BEFORE.accessToken}` } }), ENV, { store, now: NOW }),
    { userId: BEFORE.applePseudonym, sessionId: SESSION_ID });

  const asked = await voiceToken(ENV, BEFORE.accessToken, store);
  assert.equal(asked.response.status, 200, "the old access token still gets a voice token from /api/voice-token");
  assert.equal(asked.body.token, "provider-credential-not-real");

  const refreshed = await call("refresh", { refreshToken }, { store });
  assert.equal(refreshed.response.status, 200);
  assert.equal(refreshed.body.expiresIn, 600);
  assert.notEqual(refreshed.body.refreshToken, refreshToken, "refresh tokens still rotate");
  assert.equal(headerOf(refreshed.body.accessToken).kid, keyId(SECRET), "the new access token is in the new format");
  assert.deepEqual(await authenticateVoiceSession(new Request("https://example.test", { headers: { authorization: `Bearer ${refreshed.body.accessToken}` } }), ENV, { store, now: NOW }),
    { userId: BEFORE.applePseudonym, sessionId: SESSION_ID });

  const out = await call("sign-out", {}, { store, bearer: BEFORE.accessToken });
  assert.equal(out.response.status, 200, "the old token ends the session it belongs to");
  assert.equal(store.sessions.size, 0);
});

test("a rotation signs nobody out: tokens from before it, new format and old, work while the previous key is set and the session goes on", async () => {
  const store = fakeStore();
  const signedIn = await signIn({ store });
  const asBefore = (env, token) => authenticateVoiceSession(new Request("https://example.test", { headers: { authorization: `Bearer ${token}` } }), env, { store, now: NOW });
  const session = { userId: BEFORE.applePseudonym, sessionId: store.created[0].sessionId };
  assert.deepEqual(await asBefore(ENV, signedIn.body.accessToken), session);

  // The owner rotates: new key, the old one as the previous key, identifiers pinned.
  assert.deepEqual(await asBefore(ROTATED, signedIn.body.accessToken), session, "its access token");
  const refreshed = await call("refresh", { refreshToken: signedIn.body.refreshToken }, { store, env: ROTATED });
  assert.equal(refreshed.response.status, 200, "its refresh token");
  assert.equal(headerOf(refreshed.body.accessToken).kid, keyId(NEW_SECRET), "the new access token is signed with the new key");
  assert.deepEqual(await asBefore(ROTATED, refreshed.body.accessToken), session);
  assert.equal(store.sessions.get(session.sessionId).userId, BEFORE.applePseudonym, "the same person");

  // Once the previous key is removed: tokens made under it are gone (10 minutes after the rotation they have expired anyway), the rest go on.
  assert.equal(await asBefore(ROTATED_FOR_GOOD, signedIn.body.accessToken), null);
  assert.deepEqual(await asBefore(ROTATED_FOR_GOOD, refreshed.body.accessToken), session);
  const again = await call("refresh", { refreshToken: refreshed.body.refreshToken }, { store, env: ROTATED_FOR_GOOD });
  assert.equal(again.response.status, 200, "the 30-day refresh token never depended on a key");
});

test("a voice token is handed out for an access token from before the rotation and for one after it, and refused for an unknown key id", async () => {
  const store = fakeStore();
  const signedIn = await signIn({ store });
  assert.equal((await voiceToken(ROTATED, signedIn.body.accessToken, store)).response.status, 200);
  const refreshed = await call("refresh", { refreshToken: signedIn.body.refreshToken }, { store, env: ROTATED });
  assert.equal((await voiceToken(ROTATED, refreshed.body.accessToken, store)).response.status, 200);
  const session = store.created[0].sessionId;
  const stranger = jwt({ alg: "HS256", typ: "JWT", kid: keyId(OTHER_SECRET) }, purposeKey(OTHER_SECRET, ACCESS_TOKEN_LABEL), { sessionId: session });
  const refused = await voiceToken(ROTATED, stranger, store);
  assert.equal(refused.response.status, 401);
  assert.deepEqual(refused.body, { error: "session_expired" });
});

test("Apple's refresh token sealed before the change is revoked on account deletion, also after a rotation while the previous key is set", async () => {
  for (const [env, expected] of [[ENV, "revoked"], [ROTATED, "revoked"], [ROTATED_FOR_GOOD, "no_token"]]) {
    const store = fakeStore();
    sessionFromBefore(store);
    store.appleTokens.set(BEFORE.applePseudonym, BEFORE.sealedAppleToken);
    const revoked = [];
    const deleted = await call("delete-account", {}, {
      store, env: APPLE_ENV(env), bearer: env === ROTATED_FOR_GOOD ? signAccessToken({ userId: BEFORE.applePseudonym, sessionId: SESSION_ID }, keyRingFromEnv(env), NOW) : BEFORE.accessToken,
      revokeAppleToken: async (token) => { revoked.push(token); return true; },
    });
    assert.equal(deleted.response.status, 200);
    assert.equal(deleted.body.appleRevoked, expected === "revoked");
    assert.deepEqual(revoked, expected === "revoked" ? [APPLE_REFRESH] : [], "Apple gets the original token, and only when it could be opened");
    assert.equal(store.sessions.size, 0, "the account is deleted either way");
    assert.equal(store.appleTokens.size, 0);
  }
});

test("a new Apple link is sealed in the new format under the current key, and revoked by the same server", async () => {
  const store = fakeStore();
  const env = APPLE_ENV(ROTATED);
  const linked = await call("apple-link", { identityToken: "id", rawNonce: NONCE, authorizationCode: "code-not-real" }, {
    store, env, bearer: "account-token-not-real", authenticateDoddyAccount: async () => ({ userId: ACCOUNT }),
    exchangeAppleAuthorizationCode: async () => APPLE_REFRESH,
  });
  assert.deepEqual(linked.body, { linked: true });
  const sealed = store.appleTokens.get(ACCOUNT);
  assert.equal(sealed.split(".")[0], "v2");
  assert.equal(sealed.split(".")[1], keyId(NEW_SECRET), "sealed with the new key, never with the previous one");
  assert.ok(!sealed.includes(APPLE_REFRESH));
  const revoked = [];
  const result = await call("apple-revoke", {}, {
    store, env, bearer: "account-token-not-real", authenticateDoddyAccount: async () => ({ userId: ACCOUNT }),
    revokeAppleToken: async (token) => { revoked.push(token); return true; },
  });
  assert.deepEqual(result.body, { appleRevoked: true, apple: "revoked" });
  assert.deepEqual(revoked, [APPLE_REFRESH]);
});

test("sign-in under a rotated setup signs with the new key alone: the previous key never signs", async () => {
  const signedIn = await signIn({ env: ROTATED });
  assert.equal(signedIn.response.status, 200);
  assert.equal(headerOf(signedIn.body.accessToken).kid, keyId(NEW_SECRET));
  assert.ok(verifyAccessToken(signedIn.body.accessToken, keyRingFromEnv(ROTATED_FOR_GOOD), NOW), "the new key alone is enough");
  assert.equal(verifyAccessToken(signedIn.body.accessToken, keyRingFromEnv(ENV), NOW), null, "the previous key alone is not");
});

// ---- nothing secret is written down ----

test("no key, derived key, key id, token or sealed value reaches a log or an error answer", async () => {
  const captured = [];
  const secrets = new Set([SECRET, NEW_SECRET, OTHER_SECRET, APPLE_REFRESH, BEFORE.accessToken, BEFORE.sealedAppleToken]);
  for (const master of [SECRET, NEW_SECRET, OTHER_SECRET]) {
    for (const label of [ACCESS_TOKEN_LABEL, APPLE_TOKEN_SEAL_LABEL]) {
      for (const encoding of ["hex", "base64url", "base64"]) secrets.add(purposeKey(master, label).toString(encoding));
    }
    secrets.add(keyId(master));
  }
  const note = (...results) => results.forEach((result) => captured.push(JSON.stringify(result.logs), JSON.stringify(result.body)));

  for (const env of [ENV, ROTATED, ROTATED_FOR_GOOD]) {
    const store = fakeStore();
    const signedIn = await signIn({ store, env });
    secrets.add(signedIn.body.accessToken).add(signedIn.body.refreshToken);
    captured.push(JSON.stringify(signedIn.logs));
    const refreshed = await call("refresh", { refreshToken: signedIn.body.refreshToken }, { store, env });
    secrets.add(refreshed.body.accessToken).add(refreshed.body.refreshToken);
    captured.push(JSON.stringify(refreshed.logs));
    sessionFromBefore(store);
    store.appleTokens.set(BEFORE.applePseudonym, BEFORE.sealedAppleToken);
    // Refused tokens: unknown key id, wrong key, expired, old format under a key nobody has.
    const stranger = jwt({ alg: "HS256", typ: "JWT", kid: keyId(OTHER_SECRET) }, purposeKey(OTHER_SECRET, ACCESS_TOKEN_LABEL));
    for (const bearer of [stranger, oldFormatToken(OTHER_SECRET), BEFORE.accessToken.slice(0, -3)]) {
      secrets.add(bearer);
      note(await call("sign-out", {}, { store, env, bearer }), await voiceToken(env, bearer, store));
    }
    note(await call("delete-account", {}, { store, env: APPLE_ENV(env), bearer: BEFORE.accessToken, revokeAppleToken: async () => true }));
  }
  // Settings that are refused say so in a word and show no value.
  for (const env of [
    { ...ENV, DODDY_SESSION_SIGNING_KEY: NEW_SECRET, DODDY_SESSION_SIGNING_KEY_PREVIOUS: SECRET },
    { ...ROTATED, DODDY_SESSION_SIGNING_KEY_PREVIOUS: "short-previous-not-real" },
    { ...ROTATED, DODDY_IDENTIFIER_KEY: "short-identifier-not-real" },
  ]) {
    const refused = await signIn({ env });
    assert.deepEqual(refused.body, { error: "server_not_configured" });
    note(refused, await voiceToken(env, oldFormatToken(NEW_SECRET)));
    for (const value of ["short-previous-not-real", "short-identifier-not-real"]) secrets.add(value);
  }
  const everything = captured.join("\n");
  assert.ok(everything.length > 0);
  for (const secret of secrets) assert.ok(!everything.includes(secret), `leaked ${secret.slice(0, 6)}...`);
  // The thrown errors of the key functions are no different.
  assert.throws(() => signAccessToken({ userId: "u", sessionId: "s" }, "tiny-key-not-real", NOW), (error) => !String(error.message).includes("tiny-key"));
});

// ---- the same, on a real Redis ----

const REDIS_SKIP = !hasRedis && "redis-server not installed";

test("on a real Redis: a session stored by the code before the change refreshes, its old tokens work, and its sealed Apple token opens", { skip: REDIS_SKIP }, async () => {
  await withLocalRedis(async ({ store }) => {
    const refreshToken = "r".repeat(43);
    // The call the old code made at sign-in; the records are the same ones now.
    assert.equal(await store.createSession({
      userId: BEFORE.applePseudonym, sessionId: SESSION_ID, refreshHash: sha256(refreshToken), nonceHash: sha256(NONCE),
      ttlSeconds: 30 * 86_400, nowSeconds: Math.floor(NOW / 1_000),
    }), 1);
    await store.setAppleToken(BEFORE.applePseudonym, BEFORE.sealedAppleToken, 30 * 86_400);

    const session = { userId: BEFORE.applePseudonym, sessionId: SESSION_ID };
    const asBefore = (env, token) => authenticateVoiceSession(new Request("https://example.test", { headers: { authorization: `Bearer ${token}` } }), env, { store, now: NOW });
    assert.deepEqual(await asBefore(ENV, BEFORE.accessToken), session);
    assert.deepEqual(await asBefore(ROTATED, BEFORE.accessToken), session, "and after a rotation, while the previous key is set");
    assert.equal(openAppleToken(await store.getAppleToken(BEFORE.applePseudonym), keyRingFromEnv(ROTATED)), APPLE_REFRESH);

    const refreshed = await call("refresh", { refreshToken }, { store, env: ROTATED });
    assert.equal(refreshed.response.status, 200);
    assert.equal(headerOf(refreshed.body.accessToken).kid, keyId(NEW_SECRET));
    assert.deepEqual(await asBefore(ROTATED_FOR_GOOD, refreshed.body.accessToken), session);
    assert.equal(await asBefore(ROTATED_FOR_GOOD, BEFORE.accessToken), null, "the old key is gone once removed");
  });
});
