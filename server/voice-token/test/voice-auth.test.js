import assert from "node:assert/strict";
import { generateKeyPairSync, sign as signRS256, createHash, verify as verifySig } from "node:crypto";
import { test } from "node:test";
import {
  handleVoiceAuthRequest,
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
  OPENAI_API_KEY: "openai-test-server-secret", ELEVENLABS_API_KEY: "elevenlabs-test-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
};

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
  const appleTokens = new Map();
  return {
    sessions, refresh, nonces, appleTokens,
    async setAppleToken(userId, sealed) { appleTokens.set(userId, sealed); },
    async getAppleToken(userId) { return appleTokens.get(userId) ?? null; },
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
      appleTokens.delete(userId);
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
    exchangeAppleAuthorizationCode: options.exchangeAppleAuthorizationCode,
    revokeAppleToken: options.revokeAppleToken,
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
  assert.deepEqual(deleted.body, { deleted: true, appleRevoked: false });
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
  assert.deepEqual(deleted.body, { deleted: true, appleRevoked: true });
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
  assert.deepEqual(deletedA.body, { deleted: true, appleRevoked: false });
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
  assert.deepEqual(deletedB.body, { deleted: true, appleRevoked: false });
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
