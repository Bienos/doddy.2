import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES, SignedSessionVerifier } from "../src/auth.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * DELETE /v1/account: everything the backend holds for one user goes in one verified transaction,
 * their connections are removed at the provider (or queued to be), and nobody else's rows change.
 * Mock providers only.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const ID_A = DEV_IDENTITIES[USER_A]!;
const ID_B = DEV_IDENTITIES[USER_B]!;
const DAY = "2026-10-21";
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

/** Every table with a user_id column (device_owner and cleanups are checked on their own). */
const TABLES = [
  "users", "attempts", "connections", "receipts", "tool_receipts", "approvals", "tool_switches", "documents", "web_link_codes",
  "web_sessions", "logbook_state", "logbook_days", "memory_state", "memory_notes", "memory_conversations", "message_threads",
];

async function rowsOf(r: WebRig, userId: string): Promise<Record<string, number>> {
  const db = (r.store as unknown as { db: { query(sql: string, p?: unknown[]): Promise<{ rows: { n: number }[] }> } }).db;
  const out: Record<string, number> = {};
  for (const table of TABLES) out[table] = (await db.query(`SELECT COUNT(*)::int AS n FROM ${table} WHERE user_id = $1`, [userId])).rows[0]!.n;
  out.usage = (await db.query("SELECT COUNT(*)::int AS n FROM usage WHERE starts_with(counter, $1)", [`user:${userId}:`])).rows[0]!.n;
  return out;
}

async function connect(r: WebRig, toolkit: string, token: string) {
  const begin = await r.call("POST", `/v1/tools/${toolkit}/connect`, { token, body: {} });
  assert.equal(begin.status, 200, begin.text);
  const done = await r.call("POST", `/v1/tools/${toolkit}/complete`, {
    token,
    body: { attemptId: begin.body.attemptId, nonce: begin.body.nonce, result: { kind: "mock", outcome: "approve" } },
  });
  assert.equal(done.status, 200, done.text);
}

/** A user with connections, receipts, a document, kept memory, a Messages copy, a Logbook day, an approval, usage and a web session. */
async function fill(r: WebRig, token: string, userId: string): Promise<string> {
  await connect(r, "gmail", token);
  await connect(r, "notion", token);
  assert.equal((await r.call("PUT", "/v1/tools/switch", { token, body: { tool: "search_notion", enabled: true } })).status, 200);
  assert.equal((await r.call("PUT", "/v1/web/memory/state", { token, body: { notes: true, conversations: true } })).status, 200);
  const note = { id: uuid(1), text: "Anna's birthday is 14 March", source: "explicit_voice" };
  assert.equal((await r.call("PUT", "/v1/web/memory/notes", { token, body: { items: [note] } })).status, 200);
  const conversation = { startedAt: "2026-10-21T09:00:00.000Z", endedAt: "2026-10-21T09:03:00.000Z", turns: [{ role: "user", text: "Hi there" }, { role: "doddy", text: "Hello" }] };
  assert.equal((await r.call("PUT", `/v1/web/memory/conversations/${uuid(3)}`, { token, body: conversation })).status, 200);
  assert.equal((await r.call("PUT", "/v1/web/messages", { token, body: { messages: [{ id: uuid(2), sender: "user", text: "Hi", createdAt: "2026-10-22T09:00:00.000Z" }] } })).status, 200);
  assert.equal((await r.call("PUT", "/v1/web/logbook/state", { token, body: { enabled: true } })).status, 200);
  assert.ok(await r.store.putLogbookDay(userId, DAY, "{}", r.clock.now()));
  await r.store.saveReceipt(userId, { operationId: `op-${userId}` } as never, r.clock.now());
  await r.store.startDocument(userId, "Plan", "text/plain", r.clock.now());
  await r.store.createApproval({ userId, capability: "x", accountId: "y", argsDigest: "z", now: r.clock.now(), ttlSeconds: 60 });
  await r.store.reserveUsage([{ counter: `user:${userId}:ask`, period: "day:2026-10-22", limit: 10 }], 1);
  return r.signIn(await r.code(token));
}

test("DELETE /v1/account removes every row of the user, asks Composio to drop each connection, and leaves another user alone", async () => {
  rig = await startWeb();
  await rig.store.claimDeviceOwner(ID_A, rig.clock.now());
  const cookieA = await fill(rig, USER_A, ID_A);
  await fill(rig, USER_B, ID_B);
  const before = await rowsOf(rig, ID_A);
  for (const [table, n] of Object.entries(before)) assert.ok(n > 0, `${table} has a row to delete`);
  const otherBefore = await rowsOf(rig, ID_B);
  const removalsBefore = rig.toolsProvider.calls.filter((c) => c === "removeConnection").length;

  const res = await rig.call("DELETE", "/v1/account", { token: USER_A });
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.body.remoteConnections, { removed: 2, queued: 0 });
  assert.equal(res.body.deleted.connections, 2);
  assert.equal(res.body.deleted.users, 1);
  assert.equal(rig.toolsProvider.calls.filter((c) => c === "removeConnection").length - removalsBefore, 2);

  assert.deepEqual(Object.values(await rowsOf(rig, ID_A)).filter((n) => n !== 0), [], "no row is left for the user");
  assert.deepEqual(await rowsOf(rig, ID_B), otherBefore, "the other user's rows are untouched");
  const db = (rig.store as unknown as { db: { query(sql: string): Promise<{ rows: { user_id: string }[] }> } }).db;
  assert.equal((await db.query("SELECT user_id FROM device_owner")).rows[0]?.user_id, ID_A, "the device owner row stays");
  assert.equal((await db.query("SELECT user_id FROM cleanups")).rows.length, 0, "every removal finished, so nothing is queued");

  // The browser session that was signed in is gone with the rest.
  assert.equal((await rig.call("GET", "/v1/web/memory", { cookie: cookieA })).status, 401);
  // The other user still works.
  assert.equal((await rig.call("GET", "/v1/web/memory", { token: USER_B })).status, 200);
});

test("a browser cookie, or no sign-in, cannot delete the account", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  for (const o of [{ cookie }, { cookie, browser: true }, {}]) {
    const res = await rig.call("DELETE", "/v1/account", o);
    assert.equal(res.status, 401, JSON.stringify(o));
  }
  assert.equal((await rig.call("GET", "/v1/web/memory", { cookie })).status, 200, "the session is still there");
});

test("a guest iPhone (Ask Doddy only) can delete its own data", async () => {
  const verifier = new SignedSessionVerifier(Buffer.alloc(32, 9));
  rig = await startWeb({ verifier });
  const guest = verifier.mint(ID_B, new Date(rig.clock.ms), 3600, "ask");
  await rig.store.reserveUsage([{ counter: `user:${ID_B}:ask`, period: "day:2026-10-22", limit: 10 }], 1);
  await rig.store.composioUserId(ID_B, rig.clock.now());
  const res = await rig.call("DELETE", "/v1/account", { token: guest });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.deleted.users, 1);
  assert.equal(res.body.deleted.usage, 1);
  assert.deepEqual(Object.values(await rowsOf(rig, ID_B)).filter((n) => n !== 0), []);
});

test("a removal Composio refuses is queued before the rows go, and the hourly sweep finishes it", async () => {
  rig = await startWeb();
  await connect(rig, "gmail", USER_A);
  const connectionId = (await rig.store.getConnection(ID_A, "gmail"))!.connection_id;
  const real = rig.toolsProvider.removeConnection.bind(rig.toolsProvider);
  rig.toolsProvider.removeConnection = (async () => "failed") as unknown as typeof real;

  const res = await rig.call("DELETE", "/v1/account", { token: USER_A });
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.body.remoteConnections, { removed: 0, queued: 1 });
  assert.deepEqual(Object.values(await rowsOf(rig, ID_A)).filter((n) => n !== 0), []);
  const db = (rig.store as unknown as { db: { query(sql: string): Promise<{ rows: { connection_id: string; state: string }[] }> } }).db;
  assert.deepEqual((await db.query("SELECT connection_id, state FROM cleanups")).rows, [{ connection_id: connectionId, state: "failed" }]);

  rig.toolsProvider.removeConnection = real;
  rig.clock.advance(10 * 60_000);
  await rig.tools.sweepAbandoned();
  assert.equal((await db.query("SELECT connection_id, state FROM cleanups")).rows.length, 0, "the sweep removed it");
  assert.ok(rig.toolsProvider.calls.includes("removeConnection"));
});
