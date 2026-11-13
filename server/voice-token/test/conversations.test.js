// Deleting a Doddy account also deletes its voice conversations at ElevenLabs (decision
// 2026-11-12-voice-conversations-per-account): the voice server records which conversations belong to which
// account when it issues a token, deletes them when the account is deleted, and retries what is still owed
// once a day. A conversation counts as deleted only when ElevenLabs answers 404 on reading it back (DOD-08).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { handleConversationsCron } from "../src/cron.js";
import {
  conversationIdentity, doddyAgentIds, MAX_RECORDED_CONVERSATIONS, validConversationId, validInstallUserId,
} from "../src/conversations.js";
import { handleTokenRequest } from "../src/handler.js";
import { handleVoiceAuthRequest, signAccessToken } from "../src/voice-auth.js";
import {
  fakeConversationStore, fakeElevenLabs, MAIN_AGENT, OTHER_AGENT, TRANSLATOR_AGENT,
} from "./conversation-fakes.js";
import { hasRedis, withLocalRedis } from "./local-redis.js";

const NOW = Date.parse("2026-11-13T09:00:00Z");
const SIGNING_KEY = "session-signing-secret-for-tests-000000000000";
const ENV = {
  APPLE_BUNDLE_ID: "com.bienos.doddy2.dev", DODDY_SESSION_SIGNING_KEY: SIGNING_KEY,
  ELEVENLABS_API_KEY: "elevenlabs-server-secret", ELEVENLABS_AGENT_ID: MAIN_AGENT, VERCEL: "1",
  CRON_SECRET: "cron-secret-for-tests",
};
const ACCOUNT_ID = "account:3f2b8c1e-5a47-4d3e-9b6a-0c1d2e3f4a5b";
const OTHER_ACCOUNT_ID = "account:9a8b7c6d-1111-4222-8333-444455556666";
const INSTALL_ID = "0f8fad5b-d9cb-469f-a165-70867728950e";
const IDENTITY = conversationIdentity(ENV, ACCOUNT_ID);
const OTHER_IDENTITY = conversationIdentity(ENV, OTHER_ACCOUNT_ID);

// ---- helpers -------------------------------------------------------------------------------------------------

/** A store for the token handler: limits that always allow, and the conversation part. */
function tokenStore() {
  return {
    ...fakeConversationStore(),
    async hitLimits() { return { allowed: true, limit: null, retryAfterSeconds: 60 }; },
    async getSession() { return null; },
  };
}
const tokenRequest = (body) => new Request("https://example.test/api/voice-token", {
  method: "POST", headers: { authorization: "Bearer session", "content-type": "application/json" },
  ...(body ? { body: JSON.stringify(body) } : {}),
});
async function issue(store, eleven, { body = null, userId = ACCOUNT_ID, environment = ENV } = {}) {
  const logs = [];
  const response = await handleTokenRequest(tokenRequest(body), environment, {
    fetch: eleven.fetch, log: (entry) => logs.push(entry), now: () => NOW, authStore: store,
    authenticateSession: async () => ({ userId, sessionId: null }),
  });
  return { response, body: await response.json(), logs };
}

const authRequest = (action, body = {}, token) => new Request("https://example.test/api/voice-auth", {
  method: "POST",
  headers: { "content-type": "application/json", "x-vercel-forwarded-for": "203.0.113.7", ...(token ? { authorization: `Bearer ${token}` } : {}) },
  body: JSON.stringify({ action, ...body }),
});
const accountAuth = async (req) => (req.headers.get("authorization") === "Bearer account-token" ? { userId: ACCOUNT_ID, sessionId: null } : null);
async function runAuth(req, { store, eleven, environment = ENV, authenticateDoddyAccount = accountAuth, now = () => NOW } = {}) {
  const logs = [];
  const response = await handleVoiceAuthRequest(req, environment, {
    store: store ?? authStore(), now, log: (entry) => logs.push(entry), authenticateDoddyAccount,
    elevenLabsFetch: eleven?.fetch ?? (async () => assert.fail("ElevenLabs must not be called")),
    verifyAppleIdentityToken: async (_t, rawNonce) => ({ sub: "apple-sub-test", nonce: rawNonce }),
  });
  return { response, body: await response.json(), logs };
}
/** The store the voice-auth handler needs for these actions: conversations and the per-caller limits. */
function authStore() {
  const signIns = new Map();
  const sessions = new Map();
  return {
    ...fakeConversationStore(), sessions,
    async hitSignInLimits(bucket, perHour, perDay) {
      const entry = signIns.get(bucket) ?? { hour: 0, day: 0 };
      if (entry.hour >= perHour) return { allowed: false, limit: "client_hour", retryAfterSeconds: 60 };
      signIns.set(bucket, { hour: entry.hour + 1, day: entry.day + 1 });
      return { allowed: true, limit: null, retryAfterSeconds: 60 };
    },
    async getSession(id) { return sessions.get(id) ?? null; },
    async deleteAccount(userId) { let n = 0; for (const [id, s] of sessions) if (s.userId === userId) { sessions.delete(id); n += 1; } return n; },
    async getAppleToken() { return null; },
  };
}
/** `ids` recorded for `identity`, and present at ElevenLabs as that person's conversations. */
async function seed(store, eleven, identity, ids, { agent = MAIN_AGENT, started = true } = {}) {
  let at = 0;
  for (const id of ids) {
    await store.recordConversation(identity.recordKey, id, NOW + (at += 1), MAX_RECORDED_CONVERSATIONS);
    eleven.add({ id, agent, user: started ? identity.userId : null });
  }
}
const logsText = (logs) => JSON.stringify(logs);
function assertNoLeaks(logs, secrets) {
  const text = logsText(logs);
  for (const secret of secrets) assert.ok(!text.includes(secret), `log leaked ${secret}`);
}

// ---- identifiers ---------------------------------------------------------------------------------------------

test("the record key and the user id are keyed hashes of the account: stable, apart from each other, and not the account", () => {
  assert.match(IDENTITY.recordKey, /^[0-9a-f]{64}$/);
  assert.match(IDENTITY.userId, /^[0-9a-f]{32}$/);
  assert.notEqual(IDENTITY.recordKey, IDENTITY.userId);
  assert.deepEqual(conversationIdentity(ENV, ACCOUNT_ID), IDENTITY);
  assert.notEqual(OTHER_IDENTITY.recordKey, IDENTITY.recordKey);
  assert.notEqual(OTHER_IDENTITY.userId, IDENTITY.userId);
  for (const part of Object.values(IDENTITY)) assert.ok(!ACCOUNT_ID.includes(part) && !part.includes("3f2b8c1e"));
  // Another key makes other ids, so the key is what ties them to this server.
  assert.notDeepEqual(conversationIdentity({ DODDY_SESSION_SIGNING_KEY: "another-signing-key-00000000000000000" }, ACCOUNT_ID), IDENTITY);
  // No usable key, no identity.
  for (const bad of [undefined, "", "short"]) assert.equal(conversationIdentity({ DODDY_SESSION_SIGNING_KEY: bad }, ACCOUNT_ID), null);
  assert.equal(conversationIdentity(ENV, ""), null);
  assert.equal(conversationIdentity(ENV, undefined), null);
});

test("Doddy's agents are the main agent and the translator agent, and nothing else", () => {
  assert.deepEqual(doddyAgentIds(ENV), [MAIN_AGENT, TRANSLATOR_AGENT]);
  assert.deepEqual(doddyAgentIds({ ...ENV, ELEVENLABS_TRANSLATOR_AGENT_ID: "agent_translator_override" }), [MAIN_AGENT, "agent_translator_override"]);
  assert.deepEqual(doddyAgentIds({ ...ENV, ELEVENLABS_AGENT_ID: "" }), [TRANSLATOR_AGENT], "an unset main agent is not an empty filter");
});

test("only the shapes ElevenLabs uses are accepted as conversation ids and install ids", () => {
  for (const good of ["conv_7401k5m9x2p8ec3rqv6dtnhb0fzw", "abc-DEF_123"]) assert.equal(validConversationId(good), good);
  for (const bad of [undefined, null, 5, "", "a/b", "a b", "../x", "x".repeat(129), "a?b=c", {}, ["a"]]) assert.equal(validConversationId(bad), null, String(bad));
  assert.equal(validInstallUserId(INSTALL_ID), INSTALL_ID);
  assert.equal(validInstallUserId(INSTALL_ID.toUpperCase()), INSTALL_ID.toUpperCase());
  for (const bad of [undefined, null, 5, "", "user", "anonymous", "*", INSTALL_ID.slice(1), `${INSTALL_ID}0`, ` ${INSTALL_ID}`, `${INSTALL_ID}\n`, "0f8fad5b-d9cb-469f-a165-70867728950g", {}, [INSTALL_ID]]) {
    assert.equal(validInstallUserId(bad), null, JSON.stringify(bad));
  }
});

// ---- recording when a token is issued ------------------------------------------------------------------------

test("a token issues the conversation id into the account's record, and the answer adds only the keyed user id", async () => {
  const store = tokenStore();
  const eleven = fakeElevenLabs();
  const { response, body, logs } = await issue(store, eleven);
  assert.equal(response.status, 200);
  assert.deepEqual(body, { token: "token-1", userId: IDENTITY.userId });
  assert.deepEqual([...store.records.get(IDENTITY.recordKey).keys()], ["conv_issued_1"]);
  assert.deepEqual([...store.records.keys()], [IDENTITY.recordKey], "under the keyed hash, never the account");
  assert.equal(logs.at(-1).conversation_id, "recorded");
  // Counts and words only: no token, id, account, hash or key in the log.
  assertNoLeaks(logs, ["token-1", "conv_issued_1", ACCOUNT_ID, "3f2b8c1e", IDENTITY.recordKey, IDENTITY.userId, "elevenlabs-server-secret", SIGNING_KEY]);
  // A second conversation is added, not swapped in.
  await issue(store, eleven);
  assert.deepEqual([...store.records.get(IDENTITY.recordKey).keys()].sort(), ["conv_issued_1", "conv_issued_2"]);
});

test("the main and the translator agent are both recorded, and the account gets one user id for both", async () => {
  const store = tokenStore();
  const eleven = fakeElevenLabs();
  const main = await issue(store, eleven);
  const translator = await issue(store, eleven, { body: { agent: "translator" } });
  assert.equal(main.body.userId, translator.body.userId);
  assert.equal(store.records.get(IDENTITY.recordKey).size, 2);
  assert.deepEqual(eleven.calls.map((call) => call.search.agent_id), [MAIN_AGENT, TRANSLATOR_AGENT]);
  const other = await issue(store, eleven, { userId: OTHER_ACCOUNT_ID });
  assert.notEqual(other.body.userId, main.body.userId, "another account, another user id");
  assert.equal(store.records.get(OTHER_IDENTITY.recordKey).size, 1);
});

test("the older Apple voice accounts are recorded the same way, apart from the Doddy accounts", async () => {
  const store = tokenStore();
  const eleven = fakeElevenLabs();
  const voiceUser = "b".repeat(64);
  const voice = await issue(store, eleven, { userId: voiceUser });
  assert.equal(voice.response.status, 200);
  assert.equal(voice.body.userId, conversationIdentity(ENV, voiceUser).userId);
  assert.equal(store.records.get(conversationIdentity(ENV, voiceUser).recordKey).size, 1);
  assert.ok(!store.records.has(IDENTITY.recordKey));
});

test("if the id can't be recorded no token is handed out (503), and nothing leaks", async () => {
  const store = tokenStore();
  store.state.failRecording = true;
  const eleven = fakeElevenLabs();
  const { response, body, logs } = await issue(store, eleven);
  assert.equal(response.status, 503);
  assert.deepEqual(body, { error: "server_not_configured" });
  assert.ok(!JSON.stringify(body).includes("token-1"));
  assert.equal(logs.at(-1).conversation_id, "not_recorded");
  assertNoLeaks(logs, ["token-1", "conv_issued_1", IDENTITY.userId]);
  // The store coming back is all it takes.
  store.state.failRecording = false;
  assert.equal((await issue(store, eleven)).response.status, 200);
});

test("an answer without a usable conversation_id still hands out the token and the user id, and logs it as missing", async () => {
  for (const answer of ["omit", "empty", "not a string", "bad characters", "too long"]) {
    const store = tokenStore();
    const eleven = fakeElevenLabs();
    const upstream = eleven.fetch;
    const fetch = answer === "omit" ? upstream : async () => Response.json({
      token: "provider-credential",
      conversation_id: { empty: "", "not a string": 7, "bad characters": "conv/../x", "too long": "c".repeat(200) }[answer],
    });
    if (answer === "omit") eleven.knobs.omitConversationId = true;
    const logs = [];
    const response = await handleTokenRequest(tokenRequest(null), ENV, {
      fetch, log: (entry) => logs.push(entry), now: () => NOW, authStore: store,
      authenticateSession: async () => ({ userId: ACCOUNT_ID, sessionId: null }),
    });
    const body = await response.json();
    assert.equal(response.status, 200, answer);
    assert.deepEqual(Object.keys(body).sort(), ["token", "userId"]);
    assert.equal(body.userId, IDENTITY.userId);
    assert.equal(logs.at(-1).conversation_id, "missing", answer);
    assert.equal(store.records.size, 0, `${answer}: nothing is recorded, and a bad id is never kept`);
    assertNoLeaks(logs, ["provider-credential", "token-1", IDENTITY.userId, "conv/../x"]);
  }
});

test("without a usable signing key nothing is issued: no identity, no token, nothing sent to ElevenLabs", async () => {
  for (const key of [undefined, "short"]) {
    const store = tokenStore();
    const eleven = fakeElevenLabs();
    const { response, body } = await issue(store, eleven, { environment: { ...ENV, DODDY_SESSION_SIGNING_KEY: key } });
    assert.equal(response.status, 500);
    assert.deepEqual(body, { error: "server_not_configured" });
    assert.equal(eleven.calls.length, 0);
    assert.equal(store.records.size, 0);
  }
});

test("a store without recording is a configuration failure, not a token without a record", async () => {
  const store = tokenStore();
  delete store.recordConversation;
  const eleven = fakeElevenLabs();
  const { response } = await issue(store, eleven);
  assert.equal(response.status, 500);
  assert.equal(eleven.calls.length, 0);
});

test("a refused or failed token request records nothing", async () => {
  const store = tokenStore();
  const failing = async () => new Response("provider details", { status: 401 });
  const response = await handleTokenRequest(tokenRequest(null), ENV, {
    fetch: failing, log: () => {}, now: () => NOW, authStore: store,
    authenticateSession: async () => ({ userId: ACCOUNT_ID, sessionId: null }),
  });
  assert.equal(response.status, 502);
  assert.equal(store.records.size, 0);
});

// ---- the store's contract, in memory and on a real Redis ----------------------------------------------------

async function storeContract(store, label, { redis = null } = {}) {
  const key = "a".repeat(64);
  // Recording keeps the newest ids up to the cap and says how many it let go of.
  assert.equal(await store.recordConversation(key, "c1", 1_000, 3), 0, label);
  assert.equal(await store.recordConversation(key, "c2", 2_000, 3), 0);
  assert.equal(await store.recordConversation(key, "c3", 3_000, 3), 0);
  assert.equal(await store.recordConversation(key, "c4", 4_000, 3), 1, `${label}: the oldest goes when the cap is passed`);
  assert.deepEqual(await store.listConversations(key, 10), ["c2", "c3", "c4"]);
  assert.deepEqual(await store.listConversations(key, 2), ["c2", "c3"], "oldest first, bounded");
  assert.equal(await store.countConversations(key), 3);
  assert.equal(await store.recordConversation(key, "c4", 4_500, 3), 0, "the same id again is not a second one");
  assert.equal(await store.countConversations(key), 3);
  // Ids found at ElevenLabs are added without moving the ones already there, and without a cap.
  assert.equal(await store.addConversations(key, ["c3", "d1", "d2"], 9_000), 2);
  assert.deepEqual(await store.listConversations(key, 10), ["c2", "c3", "c4", "d1", "d2"]);
  assert.equal(await store.addConversations(key, [], 9_000), 0);
  assert.equal(await store.removeConversations(key, ["c2", "nope", "d2"]), 2);
  assert.equal(await store.removeConversations(key, []), 0);
  assert.deepEqual(await store.listConversations(key, 10), ["c3", "c4", "d1"]);
  assert.deepEqual(await store.listConversations("b".repeat(64), 10), [], "another account's record is another key");
  assert.equal(await store.countConversations("b".repeat(64)), 0);
  assert.equal(await store.removeConversations(key, ["c3", "c4", "d1"]), 3);
  assert.equal(await store.countConversations(key), 0);
  // What is owed.
  assert.deepEqual(await store.listOwed(), []);
  await store.markOwed(key, { filters: ["u1", "u2"] }, 5_000);
  await store.markOwed("b".repeat(64), { filters: [] }, 6_000);
  await store.markOwed(key, { filters: ["u1"] }, 7_000);
  const owed = (await store.listOwed()).sort((a, b) => (a.recordKey < b.recordKey ? -1 : 1));
  assert.deepEqual(owed.map((entry) => entry.recordKey), [key, "b".repeat(64)]);
  assert.deepEqual(owed[0].record.filters, ["u1"], "marking again replaces what was owed");
  assert.equal(owed[0].record.since, 7_000);
  await store.clearOwed(key);
  await store.clearOwed(key);
  assert.deepEqual((await store.listOwed()).map((entry) => entry.recordKey), ["b".repeat(64)]);
  await store.clearOwed("b".repeat(64));
  assert.deepEqual(await store.listOwed(), []);
  if (redis) {
    // Never expires: the owner chose no retention limit at ElevenLabs, so what is owed must not run out either.
    await store.recordConversation(key, "keep", 1_000, 3);
    await store.markOwed(key, { filters: [] }, 1_000);
    assert.equal(await redis("TTL", `doddy:voice:v1:conversations:${key}`), -1);
    assert.equal(await redis("TTL", "doddy:voice:v1:conversations-owed"), -1);
    assert.deepEqual(await redis("KEYS", "doddy:voice:v1:*"), [`doddy:voice:v1:conversations:${key}`, "doddy:voice:v1:conversations-owed"].sort());
  }
}

test("the in-memory conversation store behaves as the Redis one is tested to", async () => {
  await storeContract(fakeConversationStore(), "memory");
});

test("the Redis conversation store: capped, oldest first, never expiring, one key per account", { skip: !hasRedis && "redis-server not installed" }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    await storeContract(store, "redis", { redis: async (...parts) => { const r = await command(...parts); return Array.isArray(r) ? r.sort() : r; } });
  });
});

test("the Redis store sends the record as commands for its own keys only, with the account's hash and never a secret in a key", async () => {
  const { createVoiceAuthStore } = await import("../src/voice-auth.js");
  const sent = [];
  const store = createVoiceAuthStore({
    url: "https://redis.example.test", token: "store-secret",
    fetch: async (_url, init) => { sent.push(JSON.parse(init.body)); return Response.json([{ result: 0 }]); },
  });
  await store.recordConversation(IDENTITY.recordKey, "conv_1", NOW, 5);
  const [[command, , keyCount, key, ...rest]] = sent[0];
  assert.equal(command, "EVAL");
  assert.equal(keyCount, "1");
  assert.equal(key, `doddy:voice:v1:conversations:${IDENTITY.recordKey}`);
  assert.deepEqual(rest, ["conv_1", String(NOW), "5"]);
  assert.ok(!JSON.stringify(sent).includes("store-secret"));
});

// ---- deleting with the account -------------------------------------------------------------------------------

test("delete-conversations needs the Doddy account's token, and touches nothing without it", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a"]);
  for (const token of [undefined, "wrong-token", "voice-session-access-token"]) {
    const result = await runAuth(authRequest("delete-conversations", {}, token), { store, eleven });
    assert.equal(result.response.status, 401, String(token));
    assert.deepEqual(result.body, { error: "session_expired" });
  }
  assert.equal(eleven.calls.length, 0);
  assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_a"]);
  assert.ok(eleven.has("conv_a"));
});

test("a real voice session's token is not a Doddy account's token here", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  const voiceSession = signAccessToken({ userId: "c".repeat(64), sessionId: "sid" }, SIGNING_KEY, NOW);
  const result = await runAuth(authRequest("delete-conversations", {}, voiceSession), {
    store, eleven, authenticateDoddyAccount: async () => null,
  });
  assert.equal(result.response.status, 401);
  assert.equal(eleven.calls.length, 0);
});

test("when the project's signing keys can't be read the answer is 503, never 'signed out'", async () => {
  const { AccountCheckUnavailable } = await import("../src/doddy-account.js");
  const result = await runAuth(authRequest("delete-conversations", {}, "account-token"), {
    eleven: fakeElevenLabs(), authenticateDoddyAccount: async () => { throw new AccountCheckUnavailable(); },
  });
  assert.equal(result.response.status, 503);
  assert.deepEqual(result.body, { error: "account_check_unavailable" });
});

test("every recorded conversation is deleted and counted only after reading it back answered 404; the answer is counts only", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a", "conv_b", "conv_c"]);
  await seed(store, eleven, OTHER_IDENTITY, ["conv_other"]);
  const { response, body, logs } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.equal(response.status, 200);
  assert.deepEqual(body, { deleted: 3, pending: 0 }, "counts and nothing else");
  for (const id of ["conv_a", "conv_b", "conv_c"]) assert.ok(!eleven.has(id), `${id} is gone at ElevenLabs`);
  assert.ok(eleven.has("conv_other"), "another account's conversation is untouched");
  assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), [], "nothing is owed any more");
  assert.deepEqual(await store.listConversations(OTHER_IDENTITY.recordKey, 10), ["conv_other"]);
  assert.deepEqual(await store.listOwed(), []);
  // Each id: delete, then read back.
  for (const id of ["conv_a", "conv_b", "conv_c"]) {
    const mine = eleven.calls.filter((call) => call.path === `/v1/convai/conversations/${id}`).map((call) => call.method);
    assert.deepEqual(mine, ["DELETE", "GET"], id);
  }
  assert.deepEqual(logs.at(-1), { event: "voice_auth", action: "delete-conversations", status: 200, error: null, ms: 0, deleted: 3, pending: 0 });
  assertNoLeaks(logs, ["conv_a", "conv_b", "conv_c", IDENTITY.userId, IDENTITY.recordKey, "account-token", ACCOUNT_ID, "elevenlabs-server-secret"]);
});

test("a conversation that reading back still finds stays recorded as owed, and the answer says pending", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a", "conv_b", "conv_c"]);
  eleven.knobs.readBackStillThere.add("conv_b");
  const { body, logs } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(body, { deleted: 2, pending: 1 });
  assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_b"], "only the unconfirmed one stays");
  const owed = await store.listOwed();
  assert.deepEqual(owed.map((entry) => entry.recordKey), [IDENTITY.recordKey]);
  assert.ok(owed[0].record.filters.includes(IDENTITY.userId), "what is needed to look again is kept");
  assert.equal(logs.at(-1).pending, 1);
  // Asking again once the read-back is honest finishes it, and what was owed is cleared.
  eleven.knobs.readBackStillThere.clear();
  const again = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(again.body, { deleted: 1, pending: 0 });
  assert.deepEqual(await store.listOwed(), []);
});

test("a delete that fails keeps the id owed, and a delete that finds it already gone counts it deleted", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_ok", "conv_fails", "conv_already_gone"]);
  eleven.live.delete("conv_already_gone");
  eleven.knobs.deleteFails.add("conv_fails");
  const { body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(body, { deleted: 2, pending: 1 });
  assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_fails"]);
});

test("only a 404 on reading it back is a deletion: any other answer, an error included, leaves it owed", async () => {
  for (const status of [200, 204, 301, 400, 401, 403, 408, 422, 429, 500, 502, 503]) {
    const store = authStore();
    const eleven = fakeElevenLabs();
    await seed(store, eleven, IDENTITY, ["conv_a"]);
    eleven.knobs.readBackStatus.set("conv_a", status);
    const { body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
    assert.deepEqual(body, { deleted: 0, pending: 1 }, `read-back ${status}`);
    assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_a"], `read-back ${status}`);
  }
  // A 404 from the delete itself is not enough either: it is the read-back that decides.
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a"]);
  eleven.knobs.readBackStatus.set("conv_a", 500);
  eleven.live.delete("conv_a");
  const { body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(body, { deleted: 0, pending: 1 }, "the delete answered 404, the read-back 500");
});

test("ElevenLabs unreachable: nothing is called deleted, everything stays owed", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a", "conv_b"]);
  eleven.knobs.unreachable = true;
  const { response, body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.equal(response.status, 200);
  assert.equal(body.deleted, 0);
  assert.ok(body.pending >= 2);
  assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_a", "conv_b"]);
  assert.equal((await store.listOwed()).length, 1);
});

test("without the ElevenLabs key the answer is pending, never deleted, and the record is kept", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a"]);
  const { response, body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), {
    store, eleven: { fetch: async () => assert.fail("no key, no call") }, environment: { ...ENV, ELEVENLABS_API_KEY: "" },
  });
  assert.equal(response.status, 200);
  assert.equal(body.deleted, 0);
  assert.ok(body.pending >= 1);
  assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_a"]);
  assert.equal((await store.listOwed()).length, 1);
});

test("an unreachable store is a 503 and says nothing about deleting", async () => {
  const store = authStore();
  store.state.failing = true;
  const eleven = fakeElevenLabs();
  const { response, body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.equal(response.status, 503);
  assert.deepEqual(body, { error: "server_not_configured" });
  assert.equal(eleven.calls.length, 0);
});

test("conversations never recorded are found by the account's user id, in Doddy's agents only", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs({ conversations: [
    { id: "conv_main", agent: MAIN_AGENT, user: IDENTITY.userId },
    { id: "conv_translator", agent: TRANSLATOR_AGENT, user: IDENTITY.userId },
    { id: "conv_foreign_agent", agent: OTHER_AGENT, user: IDENTITY.userId },
    { id: "conv_someone_else", agent: MAIN_AGENT, user: OTHER_IDENTITY.userId },
    { id: "conv_no_user", agent: MAIN_AGENT, user: null },
  ] });
  const { body, logs } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(body, { deleted: 2, pending: 0 });
  assert.ok(!eleven.has("conv_main") && !eleven.has("conv_translator"));
  for (const id of ["conv_foreign_agent", "conv_someone_else", "conv_no_user"]) assert.ok(eleven.has(id), `${id} is not this account's in Doddy's agents`);
  const lists = eleven.calls.filter((call) => call.path === "/v1/convai/conversations");
  assert.deepEqual(lists.map((call) => call.search.agent_id).sort(), [MAIN_AGENT, TRANSLATOR_AGENT].sort(), "one list per Doddy agent, none for another");
  for (const list of lists) assert.equal(list.search.user_id, IDENTITY.userId);
  assertNoLeaks(logs, ["conv_main", "conv_translator", IDENTITY.userId]);
});

test("a list answer that includes another agent's conversations is not trusted: they are not deleted", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs({ conversations: [
    { id: "conv_main", agent: MAIN_AGENT, user: IDENTITY.userId },
    { id: "conv_foreign_agent", agent: OTHER_AGENT, user: IDENTITY.userId },
  ] });
  eleven.knobs.ignoreAgentFilter = true;
  const { body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(body, { deleted: 1, pending: 0 });
  assert.ok(eleven.has("conv_foreign_agent"));
  assert.ok(!eleven.calls.some((call) => call.path === "/v1/convai/conversations/conv_foreign_agent"), "never even asked about it");
});

test("the list is read page by page until it ends", async () => {
  const store = authStore();
  const conversations = Array.from({ length: 5 }, (_, n) => ({ id: `conv_${n}`, agent: MAIN_AGENT, user: IDENTITY.userId }));
  const eleven = fakeElevenLabs({ conversations, pageSize: 2 });
  const { body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(body, { deleted: 5, pending: 0 });
  assert.equal(eleven.live.size, 0);
});

test("a found conversation that can't be confirmed gone stays recorded and owed, so a later try keeps it", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs({ conversations: [{ id: "conv_found", agent: MAIN_AGENT, user: IDENTITY.userId }] });
  eleven.knobs.deleteFails.add("conv_found");
  const { body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.deepEqual(body, { deleted: 0, pending: 1 });
  assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_found"]);
});

test("if the list can't be read the answer is pending (it can't be known), and the filters stay owed for the daily retry", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs({ conversations: [{ id: "conv_found", agent: MAIN_AGENT, user: IDENTITY.userId }] });
  eleven.knobs.listFails = true;
  const { response, body } = await runAuth(authRequest("delete-conversations", { installUserId: INSTALL_ID }, "account-token"), { store, eleven });
  assert.equal(response.status, 200);
  assert.equal(body.deleted, 0);
  assert.ok(body.pending >= 1, "never 0 when the list wasn't read");
  const [owed] = await store.listOwed();
  assert.deepEqual(owed.record.filters.sort(), [IDENTITY.userId, INSTALL_ID].sort());
  // The retry, with ElevenLabs answering again, finds and deletes it and ends what was owed.
  eleven.knobs.listFails = false;
  const cron = await runCron({ store, eleven });
  assert.equal(cron.response.status, 200);
  assert.deepEqual(cron.body, { accounts: 1, deleted: 1, pending: 0 });
  assert.ok(!eleven.has("conv_found"));
  assert.deepEqual(await store.listOwed(), []);
});

test("the old per-install id is one more user id to look for, in Doddy's agents only, and only in the shape the app makes", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs({ conversations: [
    { id: "conv_install_main", agent: MAIN_AGENT, user: INSTALL_ID },
    { id: "conv_install_translator", agent: TRANSLATOR_AGENT, user: INSTALL_ID },
    { id: "conv_install_foreign", agent: OTHER_AGENT, user: INSTALL_ID },
    { id: "conv_other_install", agent: MAIN_AGENT, user: "11111111-2222-4333-8444-555555555555" },
  ] });
  const { response, body, logs } = await runAuth(authRequest("delete-conversations", { installUserId: INSTALL_ID }, "account-token"), { store, eleven });
  assert.equal(response.status, 200);
  assert.deepEqual(body, { deleted: 2, pending: 0 });
  assert.ok(eleven.has("conv_install_foreign") && eleven.has("conv_other_install"));
  const lists = eleven.calls.filter((call) => call.path === "/v1/convai/conversations");
  assert.equal(lists.length, 4, "the account's user id and the install id, each in both of Doddy's agents");
  assert.ok(lists.every((call) => [MAIN_AGENT, TRANSLATOR_AGENT].includes(call.search.agent_id)));
  assert.deepEqual([...new Set(lists.map((call) => call.search.user_id))].sort(), [IDENTITY.userId, INSTALL_ID].sort());
  assertNoLeaks(logs, [INSTALL_ID, "conv_install_main"]);
});

test("an install id that isn't the app's kind of id is refused before anything is looked up or deleted", async () => {
  for (const installUserId of ["user", "anonymous", "*", "", 7, {}, [INSTALL_ID], `${INSTALL_ID}x`, IDENTITY.userId]) {
    const store = authStore();
    const eleven = fakeElevenLabs();
    await seed(store, eleven, IDENTITY, ["conv_a"]);
    const result = await runAuth(authRequest("delete-conversations", { installUserId }, "account-token"), { store, eleven });
    assert.equal(result.response.status, 400, JSON.stringify(installUserId));
    assert.deepEqual(result.body, { error: "invalid_request" });
    assert.equal(eleven.calls.length, 0);
    assert.deepEqual(await store.listConversations(IDENTITY.recordKey, 10), ["conv_a"]);
  }
  // Left out (or null) is fine: an iPhone that never made one.
  for (const body of [{}, { installUserId: null }]) {
    const result = await runAuth(authRequest("delete-conversations", body, "account-token"), { eleven: fakeElevenLabs() });
    assert.equal(result.response.status, 200);
  }
});

test("asking again after everything is deleted answers 0 and 0, so a retry of the whole account deletion works", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a"]);
  assert.deepEqual((await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven })).body, { deleted: 1, pending: 0 });
  assert.deepEqual((await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven })).body, { deleted: 0, pending: 0 });
});

test("the action is limited per account like the other account actions, and a refused one never reaches ElevenLabs", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  for (let n = 0; n < 10; n += 1) assert.equal((await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven })).response.status, 200);
  const calls = eleven.calls.length;
  const refused = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven });
  assert.equal(refused.response.status, 429);
  assert.equal(refused.response.headers.get("retry-after"), "60");
  assert.equal(eleven.calls.length, calls);
});

test("a long list is worked on within a time budget: what is left stays owed instead of the request running on", async () => {
  const store = authStore();
  let clock = NOW;
  const eleven = fakeElevenLabs();
  eleven.knobs.onCall = () => { clock += 1_000; };
  await seed(store, eleven, IDENTITY, Array.from({ length: 200 }, (_, n) => `conv_${String(n).padStart(3, "0")}`));
  const { response, body } = await runAuth(authRequest("delete-conversations", {}, "account-token"), { store, eleven, now: () => clock });
  assert.equal(response.status, 200);
  assert.ok(body.deleted > 0 && body.deleted < 200, `some, not all: ${body.deleted}`);
  assert.equal(body.deleted + body.pending, 200, "every id is either confirmed gone or still owed");
  assert.equal((await store.listOwed()).length, 1);
  assert.equal(await store.countConversations(IDENTITY.recordKey), body.pending);
});

// ---- a voice session's own deletion (the older Apple voice accounts) ---------------------------------------

test("deleting a voice account also deletes its recorded conversations, and says how many; the session is deleted either way", async () => {
  const voiceUser = "d".repeat(64);
  const voiceIdentity = conversationIdentity(ENV, voiceUser);
  const store = authStore();
  store.sessions.set("sid", { userId: voiceUser, sessionId: "sid", refreshHash: "h" });
  const eleven = fakeElevenLabs();
  await seed(store, eleven, voiceIdentity, ["conv_v1", "conv_v2"]);
  eleven.knobs.readBackStillThere.add("conv_v2");
  const token = signAccessToken({ userId: voiceUser, sessionId: "sid" }, SIGNING_KEY, NOW);
  const { response, body, logs } = await runAuth(authRequest("delete-account", {}, token), { store, eleven });
  assert.equal(response.status, 200);
  assert.deepEqual(body, { deleted: true, appleRevoked: false, conversations: { deleted: 1, pending: 1 } });
  assert.equal(store.sessions.size, 0, "the session is gone");
  assert.deepEqual(await store.listConversations(voiceIdentity.recordKey, 10), ["conv_v2"], "what wasn't confirmed stays owed");
  assert.equal(logs.at(-1).pending, 1);
  assertNoLeaks(logs, ["conv_v1", "conv_v2", voiceIdentity.userId]);
});

test("a voice account's own deletion never touches a Doddy account's conversations", async () => {
  const voiceUser = "d".repeat(64);
  const store = authStore();
  store.sessions.set("sid", { userId: voiceUser, sessionId: "sid", refreshHash: "h" });
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_account"]);
  const token = signAccessToken({ userId: voiceUser, sessionId: "sid" }, SIGNING_KEY, NOW);
  const { body } = await runAuth(authRequest("delete-account", {}, token), { store, eleven });
  assert.deepEqual(body.conversations, { deleted: 0, pending: 0 });
  assert.ok(eleven.has("conv_account"));
});

// ---- the daily retry -----------------------------------------------------------------------------------------

const cronRequest = (authorization, method = "GET") => new Request("https://example.test/api/voice-cron", {
  method, headers: authorization === null ? {} : { authorization },
});
// `authorization: null` sends no header; leaving it out sends the right secret.
async function runCron({ store, eleven, environment = ENV, authorization = `Bearer ${ENV.CRON_SECRET}`, method = "GET", now = () => NOW } = {}) {
  const logs = [];
  const response = await handleConversationsCron(cronRequest(authorization, method), environment, {
    store, elevenLabsFetch: eleven?.fetch ?? (async () => assert.fail("ElevenLabs must not be called")), now, log: (entry) => logs.push(entry),
  });
  return { response, body: await response.json(), logs };
}

test("without CRON_SECRET the cron does nothing, whatever it is sent", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a"]);
  await store.markOwed(IDENTITY.recordKey, { filters: [IDENTITY.userId] }, NOW);
  for (const authorization of [null, "Bearer ", "Bearer undefined", "Bearer anything"]) {
    for (const secret of [undefined, "", "   "]) {
      const result = await runCron({ store, eleven, authorization, environment: { ...ENV, CRON_SECRET: secret } });
      assert.equal(result.response.status, 503, `${authorization} / ${JSON.stringify(secret)}`);
      assert.deepEqual(result.body, { error: "cron_not_configured" });
    }
  }
  assert.equal(eleven.calls.length, 0);
  assert.ok(eleven.has("conv_a"));
  assert.equal((await store.listOwed()).length, 1);
});

test("the cron refuses a missing or wrong secret, and any method but GET, before any work", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a"]);
  await store.markOwed(IDENTITY.recordKey, { filters: [IDENTITY.userId] }, NOW);
  for (const authorization of [null, "", "Bearer", "Bearer wrong", `bearer ${ENV.CRON_SECRET}x`, ENV.CRON_SECRET, `Basic ${ENV.CRON_SECRET}`, `Bearer ${ENV.CRON_SECRET} and more`]) {
    const result = await runCron({ store, eleven, authorization });
    assert.equal(result.response.status, 401, String(authorization));
    assert.deepEqual(result.body, { error: "unauthorized" });
  }
  for (const method of ["POST", "PUT", "DELETE"]) {
    const result = await runCron({ store, eleven, method });
    assert.equal(result.response.status, 405, method);
    assert.equal(result.response.headers.get("allow"), "GET");
  }
  assert.equal(eleven.calls.length, 0);
  assert.ok(eleven.has("conv_a"));
});

test("the cron finishes what is owed, clears it, answers counts only, and logs counts only", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  await seed(store, eleven, IDENTITY, ["conv_a", "conv_b"]);
  await seed(store, eleven, OTHER_IDENTITY, ["conv_c"]);
  await store.markOwed(IDENTITY.recordKey, { filters: [IDENTITY.userId] }, NOW - 1_000);
  await store.markOwed(OTHER_IDENTITY.recordKey, { filters: [OTHER_IDENTITY.userId] }, NOW - 1_000);
  eleven.knobs.deleteFails.add("conv_c");
  const { response, body, logs } = await runCron({ store, eleven });
  assert.equal(response.status, 200);
  assert.deepEqual(body, { accounts: 2, deleted: 2, pending: 1 });
  assert.ok(!eleven.has("conv_a") && !eleven.has("conv_b") && eleven.has("conv_c"));
  assert.deepEqual((await store.listOwed()).map((entry) => entry.recordKey), [OTHER_IDENTITY.recordKey], "only what is still not gone stays owed");
  assert.deepEqual(logs.at(-1), { event: "voice_conversations_cron", status: 200, error: null, ms: 0, accounts: 2, deleted: 2, pending: 1 });
  assertNoLeaks(logs, ["conv_a", "conv_b", "conv_c", IDENTITY.userId, OTHER_IDENTITY.userId, IDENTITY.recordKey, ENV.CRON_SECRET]);
  // And the next day it tries the one left again.
  eleven.knobs.deleteFails.clear();
  assert.deepEqual((await runCron({ store, eleven })).body, { accounts: 1, deleted: 1, pending: 0 });
  assert.deepEqual(await store.listOwed(), []);
});

test("with nothing owed the cron makes no call to ElevenLabs", async () => {
  const store = authStore();
  const eleven = fakeElevenLabs();
  const { response, body } = await runCron({ store, eleven });
  assert.equal(response.status, 200);
  assert.deepEqual(body, { accounts: 0, deleted: 0, pending: 0 });
  assert.equal(eleven.calls.length, 0);
});

test("the cron cannot run without the ElevenLabs key or the store, and says so instead of reporting success", async () => {
  const eleven = fakeElevenLabs();
  const noKey = await runCron({ store: authStore(), eleven, environment: { ...ENV, ELEVENLABS_API_KEY: "" } });
  assert.equal(noKey.response.status, 503);
  const down = authStore();
  down.state.failing = true;
  const noStore = await runCron({ store: down, eleven });
  assert.equal(noStore.response.status, 503);
  assert.equal(eleven.calls.length, 0);
});

test("the cron works through its owed accounts within a time budget and leaves the rest for tomorrow", async () => {
  const store = authStore();
  let clock = NOW;
  const eleven = fakeElevenLabs();
  eleven.knobs.onCall = () => { clock += 1_000; };
  for (let n = 0; n < 5; n += 1) {
    const identity = conversationIdentity(ENV, `account:${String(n).padStart(8, "0")}-0000-4000-8000-000000000000`);
    await seed(store, eleven, identity, Array.from({ length: 40 }, (_, i) => `conv_${n}_${i}`));
    await store.markOwed(identity.recordKey, { filters: [identity.userId] }, NOW);
  }
  const { body } = await runCron({ store, eleven, now: () => clock });
  assert.ok(body.deleted > 0 && body.deleted < 200, `some, not all: ${body.deleted}`);
  assert.ok(body.accounts >= 1 && body.accounts < 5, `not every account was reached: ${body.accounts}`);
  const left = [...store.records.values()].reduce((sum, ids) => sum + ids.size, 0);
  assert.equal(left + body.deleted, 200, "everything is either confirmed gone or still recorded");
  assert.equal((await store.listOwed()).length, 5, "every account is still owed, the ones not reached as they were");
});

// ---- configuration the repository states ---------------------------------------------------------------------

test("vercel.json has a daily cron for the retry whose path is a function in api/, and nothing else is scheduled", () => {
  const config = JSON.parse(readFileSync(new URL("../vercel.json", import.meta.url), "utf8"));
  assert.equal(config.crons.length, 1);
  const [cron] = config.crons;
  assert.equal(cron.path, "/api/voice-cron");
  const fields = cron.schedule.split(" ");
  assert.equal(fields.length, 5);
  assert.match(fields[0], /^\d+$/, "a fixed minute, off the hour");
  assert.notEqual(fields[0], "0");
  assert.match(fields[1], /^\d+$/);
  assert.deepEqual(fields.slice(2), ["*", "*", "*"], "once a day");
  const entry = readFileSync(new URL("../api/voice-cron.js", import.meta.url), "utf8");
  assert.match(entry, /handleConversationsCron/);
});
