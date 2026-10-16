import assert from "node:assert/strict";
import { generateKeyPairSync, sign as signRS256, createHash } from "node:crypto";
import { test } from "node:test";
import {
  handleVoiceAuthRequest,
  createVoiceAuthStore,
  VoiceAuthStoreUnavailable,
  signAccessToken,
  verifyAccessToken,
  verifyAppleIdentityToken,
} from "../src/voice-auth.js";

const NOW = Date.parse("2026-10-16T12:00:00Z");
const NONCE = "A".repeat(43);
const SIGNING_KEY = "session-signing-secret-for-tests-000000000000";
const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev", DODDY_SESSION_SIGNING_KEY: SIGNING_KEY,
  OPENAI_API_KEY: "openai-test-server-secret", ELEVENLABS_API_KEY: "elevenlabs-test-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
};

function fakeStore() {
  const sessions = new Map();
  const refresh = new Map();
  const nonces = new Set();
  const limits = new Map();
  return {
    sessions, refresh, nonces,
    async createSession(input) {
      if (nonces.has(input.nonceHash) || refresh.has(input.refreshHash)) return 0;
      nonces.add(input.nonceHash);
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
      refresh.delete(oldHash);
      refresh.set(newHash, current);
      sessions.set(prior.sessionId, { ...session, refreshHash: newHash });
      return sessions.get(prior.sessionId);
    },
    async hitLimits(userId, perLimit, globalLimit) {
      const key = `${userId}:per`;
      const per = (limits.get(key) ?? 0) + 1;
      const global = (limits.get("global") ?? 0) + 1;
      limits.set(key, per);
      limits.set("global", global);
      return { allowed: per <= perLimit && global <= globalLimit, retryAfterSeconds: 60 };
    },
    async revokeSession(id, userId) {
      const session = sessions.get(id);
      if (!session || session.userId !== userId) return 0;
      sessions.delete(id);
      refresh.delete(session.refreshHash);
      return 1;
    },
    async deleteAccount(userId) {
      let deleted = 0;
      for (const [id, session] of sessions) {
        if (session.userId === userId) {
          sessions.delete(id);
          refresh.delete(session.refreshHash);
          deleted += 1;
        }
      }
      return deleted;
    },
  };
}

function request(action, body = {}, authorization) {
  return new Request("https://example.test/api/voice-auth", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(authorization ? { authorization: `Bearer ${authorization}` } : {}),
    },
    body: JSON.stringify({ action, ...(action === "sign-in" ? { provider: "openai" } : {}), ...body }),
  });
}

async function run(req, options = {}) {
  const logs = [];
  const response = await handleVoiceAuthRequest(req, options.environment ?? ENV, {
    store: options.store ?? fakeStore(),
    now: options.now ?? (() => NOW),
    log: (line) => logs.push(line),
    verifyAppleIdentityToken: options.verifyAppleIdentityToken ?? (async (_token, rawNonce) => ({ sub: "apple-sub-test", nonce: rawNonce })),
    fetch: options.fetch,
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
    store, environment: { ...ENV, OPENAI_API_KEY: "" },
  });
  assert.equal(missing.response.status, 503);
  assert.deepEqual(missing.body, { error: "server_not_configured" });
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
  assert.deepEqual(deleted.body, { deleted: true });
  assert.equal(store.sessions.size, 0);
  assert.equal(store.refresh.size, 0);
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
  const down = createVoiceAuthStore({
    url: "https://redis.example.test", token: "store-secret",
    fetch: async () => { throw new Error("URL includes confidential data"); },
  });
  await assert.rejects(() => down.getSession("sid"), VoiceAuthStoreUnavailable);
  assert.throws(() => createVoiceAuthStore({ url: "http://redis.example.test", token: "x" }), VoiceAuthStoreUnavailable);
  assert.throws(() => createVoiceAuthStore({ url: "https://user:pass@redis.example.test", token: "x" }), VoiceAuthStoreUnavailable);
});
