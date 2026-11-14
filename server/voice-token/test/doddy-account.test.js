import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { test } from "node:test";
import { AccountCheckUnavailable, createAccountVerifier, madeWithPassword } from "../src/doddy-account.js";
import { conversationIdentity } from "../src/conversations.js";
import { handleTokenRequest } from "../src/handler.js";
import { fakeConversationStore } from "./conversation-fakes.js";

// Decision 2026-11-08-required-account: the voice token server accepts a Doddy account (a Supabase
// user: Apple, Google or a code by email), checked against the project's published keys.

const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const SUB = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const NOW = 1_794_000_000_000;
const NOW_S = Math.floor(NOW / 1000);

const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const other = generateKeyPairSync("ec", { namedCurve: "P-256" });
const rsa = generateKeyPairSync("rsa", { modulusLength: 2048 });
const b64 = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
const jwk = (key, kid, alg) => ({ ...key.export({ format: "jwk" }), kid, alg, use: "sig" });

function token(claims = {}, { alg = "ES256", kid = "k1", key } = {}) {
  const header = b64({ alg, kid, typ: "JWT" });
  const body = b64({
    iss: ISSUER, aud: "authenticated", role: "authenticated", sub: SUB, iat: NOW_S - 10, exp: NOW_S + 3600,
    is_anonymous: false, app_metadata: { provider: "email", providers: ["email"] }, amr: [{ method: "otp", timestamp: NOW_S - 10 }],
    ...claims,
  });
  const data = Buffer.from(`${header}.${body}`);
  const signature = alg === "RS256"
    ? sign("RSA-SHA256", data, key ?? rsa.privateKey)
    : sign("sha256", data, { key: key ?? ec.privateKey, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${signature.toString("base64url")}`;
}

/** A fake JWKS endpoint that counts fetches and can fail. */
function jwks(keys = [jwk(ec.publicKey, "k1", "ES256"), jwk(rsa.publicKey, "r1", "RS256")]) {
  const state = { fetches: 0, fail: false, urls: [] };
  const fetch = async (url) => {
    state.fetches += 1;
    state.urls.push(String(url));
    if (state.fail) throw new Error("unreachable");
    return Response.json({ keys });
  };
  return { state, fetch };
}

test("a valid account token is accepted: Apple, Google or email, ES256 or RS256", async () => {
  const { state, fetch } = jwks();
  const v = createAccountVerifier({ projectUrl: PROJECT, fetch });
  assert.deepEqual(await v.verify(token(), NOW), { sub: SUB });
  assert.deepEqual(await v.verify(token({ app_metadata: { provider: "apple" }, amr: [{ method: "id_token" }] }), NOW), { sub: SUB });
  assert.deepEqual(await v.verify(token({ app_metadata: { provider: "google" }, amr: [{ method: "oauth" }] }), NOW), { sub: SUB });
  assert.deepEqual(await v.verify(token({}, { alg: "RS256", kid: "r1" }), NOW), { sub: SUB });
  assert.deepEqual(state.urls, [`${ISSUER}/.well-known/jwks.json`], "keys fetched once, from the project");
});

test("everything else is refused", async () => {
  const { fetch } = jwks();
  const v = createAccountVerifier({ projectUrl: PROJECT, fetch });
  const refused = {
    "another key": token({}, { key: other.privateKey }),
    "shared-secret algorithm": token({}, { alg: "HS256" }),
    "ES256 naming the RSA key": token({}, { kid: "r1" }),
    "another project": token({ iss: "https://zzzzzzzzzzzzzzzzzzzz.supabase.co/auth/v1" }),
    "another audience": token({ aud: "voice" }),
    "service role": token({ role: "service_role" }),
    anonymous: token({ is_anonymous: true }),
    "not a user id": token({ sub: "apple-sub-123" }),
    expired: token({ exp: NOW_S }),
    "issued in the future": token({ iat: NOW_S + 3600 }),
    phone: token({ app_metadata: { provider: "phone" } }),
    "no method": token({ app_metadata: {} }),
    "a password": token({ amr: [{ method: "password", timestamp: NOW_S }] }),
    "a password, as a word": token({ app_metadata: { provider: "google" }, amr: ["password"] }),
  };
  for (const [name, bad] of Object.entries(refused)) assert.equal(await v.verify(bad, NOW), null, name);
  for (const junk of [undefined, "", "a.b", "a.b.c.d", `${token()}x.y`, "x".repeat(9_000)]) assert.equal(await v.verify(junk, NOW), null, String(junk).slice(0, 20));
});

test("passwords are found in either amr shape, and an amr without one passes", () => {
  assert.equal(madeWithPassword([{ method: "password" }]), true);
  assert.equal(madeWithPassword(["Password"]), true);
  assert.equal(madeWithPassword([{ method: "otp" }, { method: "password" }]), true);
  for (const amr of [undefined, null, [], [{ method: "otp" }], ["oauth"], "password"]) assert.equal(madeWithPassword(amr), false, JSON.stringify(amr));
});

test("junk key ids can't make the server flood Supabase, and an outage keeps cached keys working", async () => {
  const { state, fetch } = jwks();
  const v = createAccountVerifier({ projectUrl: PROJECT, fetch });
  assert.deepEqual(await v.verify(token(), NOW), { sub: SUB });
  for (let i = 0; i < 20; i += 1) assert.equal(await v.verify(token({}, { kid: `junk-${i}` }), NOW + 1_000), null);
  assert.equal(state.fetches, 1, "no refetch for unknown ids within 30 s of the last fetch");
  for (let i = 0; i < 20; i += 1) assert.equal(await v.verify(token({}, { kid: `junk-${i}` }), NOW + 31_000), null);
  assert.equal(state.fetches, 2, "one refetch after 30 s, not twenty");
  state.fail = true;
  assert.deepEqual(await v.verify(token(), NOW + 11 * 60_000), { sub: SUB }, "stale keys still work while Supabase is down");
});

test("with no keys ever read, the answer is 'can't check now', never 'signed out'", async () => {
  const { state, fetch } = jwks();
  state.fail = true;
  const v = createAccountVerifier({ projectUrl: PROJECT, fetch });
  await assert.rejects(v.verify(token(), NOW), AccountCheckUnavailable);
});

// ------------------------------------------------------------------ the token route

const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev",
  DODDY_SESSION_SIGNING_KEY: "server-only-session-key-for-tests-000000000000000",
  ELEVENLABS_API_KEY: "elevenlabs-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
  SUPABASE_URL: PROJECT,
};

function limits() {
  const calls = [];
  return {
    ...fakeConversationStore(),
    calls,
    async hitLimits(userId) {
      calls.push(userId);
      return { allowed: true, retryAfterSeconds: 0 };
    },
    async getSession() { return null; },
  };
}

async function tokenRequest(bearer, { env = ENV, keys = jwks() } = {}) {
  const store = limits();
  const upstream = [];
  const logs = [];
  const response = await handleTokenRequest(
    new Request("https://example.test/api/voice-token", { method: "POST", headers: { authorization: `Bearer ${bearer}` } }),
    env,
    {
      fetch: async (url) => {
        upstream.push(String(url));
        return Response.json({ token: "provider-credential" });
      },
      accountFetch: keys.fetch,
      log: (entry) => logs.push(entry),
      now: () => NOW,
      authStore: store,
    },
  );
  return { response, body: await response.json(), store, upstream, logs };
}

test("a Doddy account gets an ElevenLabs token, in its own limit bucket, and nothing secret is logged", async () => {
  const bearer = token();
  const { response, body, store, upstream, logs } = await tokenRequest(bearer);
  assert.equal(response.status, 200);
  // The conversation is tied to the account: the answer adds the account's keyed user id (the Doddy account's id is
  // the Supabase user's, in its own `account:` namespace), and the log carries neither.
  assert.deepEqual(body, { token: "provider-credential", userId: conversationIdentity(ENV, `account:${SUB}`).userId });
  assert.deepEqual(store.calls, [`account:${SUB}`]);
  assert.deepEqual(upstream, ["https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=agent_test"]);
  const logged = JSON.stringify(logs);
  for (const secret of [bearer, SUB, "provider-credential"]) assert.ok(!logged.includes(secret), "log leaked a secret or an id");
});

test("a refused account token is a 401 and nothing goes upstream; without SUPABASE_URL accounts aren't accepted", async () => {
  const forged = await tokenRequest(token({}, { key: other.privateKey }));
  assert.equal(forged.response.status, 401);
  assert.equal(forged.body.error, "session_expired");
  assert.deepEqual(forged.upstream, []);
  const password = await tokenRequest(token({ amr: [{ method: "password" }] }));
  assert.equal(password.response.status, 401);
  const { SUPABASE_URL: _unused, ...withoutSupabase } = ENV;
  const off = await tokenRequest(token(), { env: withoutSupabase });
  assert.equal(off.response.status, 401);
  assert.deepEqual(off.upstream, []);
});

test("keys that can't be read are a 503 'try again', never a 401", async () => {
  const keys = jwks();
  keys.state.fail = true;
  const { response, body, upstream } = await tokenRequest(token(), { keys });
  assert.equal(response.status, 503);
  assert.equal(body.error, "account_check_unavailable");
  assert.deepEqual(upstream, []);
});
