import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { AccountEraser } from "../src/account.js";
import { type AuthenticatedUser, DEV_IDENTITIES, DevSessionVerifier, type SessionVerifier } from "../src/auth.js";
import { defaultRegistry } from "../src/capabilities.js";
import { testLimits } from "../src/config.js";
import { createHandler } from "../src/http.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { ConnectedAppsService, PROVIDER as CALENDAR_PROVIDER } from "../src/service.js";
import { ERASED_TABLES, KEPT_ON_ERASE, Store } from "../src/store.js";
import { TOOLKITS } from "../src/tools/catalog.js";
import { MockToolsProvider } from "../src/tools/mock.js";
import { CloudToolsService } from "../src/tools/service.js";
import { Clock, USER_A, USER_B } from "./helpers.js";

/** Deleting the account on the server (ADR-674): everything of the person goes, and the receipt says what happened. */

const ID_A = DEV_IDENTITIES[USER_A]!;
const ID_B = DEV_IDENTITIES[USER_B]!;
const GUEST_TOKEN = "guest-token-0001";
const GUEST_ID = "00000000-0000-4000-8000-0000000000c1";

/** One row of every per-person table, the way each table is really filled. */
async function seed(store: Store, userId: string, tag: string): Promise<void> {
  const q = (sql: string, params: unknown[]) => store.db.query(sql, params);
  const uuid = (n: number) => `${tag.padEnd(8, "0").slice(0, 8)}-0000-4000-8000-${String(n).padStart(12, "0")}`;
  await q("INSERT INTO users (user_id, composio_user_id, created_at) VALUES ($1, $2, 1)", [userId, `doddy_${tag}`]);
  // An open sign-in whose consent finished at the provider but was never recorded here.
  await q(
    `INSERT INTO attempts (attempt_id, user_id, provider, auth_config_id, pending_connection_id, nonce_hash, created_at, expires_at)
     VALUES ($1, $2, 'gmail', 'ac_test', $3, 'h', 1, 9999999999999)`,
    [`att-${tag}`, userId, `pending-${tag}`],
  );
  await q(
    `INSERT INTO connections (user_id, provider, connection_id, status, connected_at) VALUES ($1, 'notion', $2, 'connected', 1)`,
    [userId, `conn-notion-${tag}`],
  );
  await q(
    `INSERT INTO connections (user_id, provider, connection_id, status, connected_at) VALUES ($1, $2, $3, 'connected', 1)`,
    [userId, CALENDAR_PROVIDER, `conn-cal-${tag}`],
  );
  await q("INSERT INTO receipts (operation_id, user_id, created_at, body) VALUES ($1, $2, 1, '{}')", [`r-${tag}`, userId]);
  await q(
    `INSERT INTO approvals (approval_id, user_id, capability, account_id, args_digest, created_at, expires_at)
     VALUES ($1, $2, 'send_email', 'acct', 'd', 1, 2)`,
    [`ap-${tag}`, userId],
  );
  await q("INSERT INTO tool_switches (user_id, tool, enabled, changed_at) VALUES ($1, 'check_email', 1, 1)", [userId]);
  await q("INSERT INTO tool_receipts (operation_id, user_id, created_at, body) VALUES ($1, $2, 1, '{}')", [`tr-${tag}`, userId]);
  // Payments (ADR-734): receipts and the per-attempt ledger go with the account.
  await q("INSERT INTO payment_receipts (operation_id, user_id, created_at, body) VALUES ($1, $2, 1, '{}')", [`pr-${tag}`, userId]);
  await q(
    `INSERT INTO payments (payment_id, user_id, created_at, updated_at, host, amount, network, url_hash, valid_before, status)
     VALUES ($1, $2, 1, 1, 'shop.example', 50000, 'base-sepolia', 'h', 1, 'settled')`,
    [`pay-${tag}`, userId],
  );
  await q("INSERT INTO documents (id, user_id, status, name, mime, body, created_at) VALUES ($1, $2, 'ready', 'a.md', 'text/markdown', $3, 1)", [
    `doc-${tag}`,
    userId,
    Buffer.from("secret plan"),
  ]);
  await q("INSERT INTO web_link_codes (code_hash, user_id, created_at, expires_at) VALUES ($1, $2, 1, 2)", [`code-${tag}`, userId]);
  await q(
    `INSERT INTO web_sessions (session_id, user_id, token_hash, browser, os, created_at, last_seen_at, expires_at)
     VALUES ($1, $2, $3, 'Safari', 'macOS', 1, 1, 9999999999999)`,
    [`ws-${tag}`, userId, `th-${tag}`],
  );
  // ADR-818: a linked Google sign-in, and an iPhone's link ticket not yet opened.
  await q("INSERT INTO web_identities (identity_id, user_id, provider, created_at) VALUES ($1, $2, 'google', 1)", [uuid(3), userId]);
  await q(
    `INSERT INTO web_oauth_states (state_hash, user_id, provider, intent, return_to, verifier, created_at, expires_at)
     VALUES ($1, $2, 'google', 'link', 'app', 'v', 1, 9999999999999)`,
    [`os-${tag}`, userId],
  );
  await q("INSERT INTO web_accounts (user_id, provider, created_at) VALUES ($1, 'google', 1)", [userId]);
  // ADR-819: another iPhone signed in to this account.
  await q("INSERT INTO device_joins (device_user_id, user_id, provider, created_at) VALUES ($1, $2, 'google', 1)", [uuid(5), userId]);
  // Decision 2026-11-08-required-account: a Doddy account that took over this person's earlier iPhone data.
  await q("INSERT INTO account_links (subject, user_id, linked_at) VALUES ($1, $2, 1)", [uuid(6), userId]);
  await q(
    `INSERT INTO web_link_pending (code_hash, user_id, identity_id, provider, created_at, expires_at) VALUES ($1, $2, $3, 'google', 1, 9999999999999)`,
    [`lp-${tag}`, userId, uuid(4)],
  );
  await q("INSERT INTO logbook_state (user_id, enabled, changed_at) VALUES ($1, true, 1)", [userId]);
  await q("INSERT INTO logbook_days (user_id, day, summary, received_at) VALUES ($1, '2026-10-09', '{}', 1)", [userId]);
  await q("INSERT INTO memory_state (user_id, notes, conversations, changed_at) VALUES ($1, true, true, 1)", [userId]);
  await q("INSERT INTO memory_notes (user_id, note_id, key_version, ciphertext, received_at) VALUES ($1, $2, 1, $3, 1)", [userId, uuid(1), Buffer.from("x")]);
  await q(
    `INSERT INTO memory_conversations (user_id, conversation_id, started_at, ended_at, turn_count, key_version, ciphertext, received_at)
     VALUES ($1, $2, 1, 2, 1, 1, $3, 1)`,
    [userId, uuid(2), Buffer.from("x")],
  );
  await q("INSERT INTO message_threads (user_id, key_version, ciphertext, message_count, received_at) VALUES ($1, 1, $2, 1, 1)", [userId, Buffer.from("x")]);
  // The iPhone an invite code signed in (ADR-709): deleting the account frees that place.
  await q("INSERT INTO invite_devices (code_id, user_id, first_used_at) VALUES ($1, $2, 1)", [`code-${tag}`, userId]);
  await store.reserveUsage([{ counter: `user:${userId}:ask`, period: "day:2026-10-10", limit: 50 }, { counter: "service:ask", period: "day:2026-10-10", limit: 500 }], 1);
}

async function rows(store: Store, userId: string): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const table of [...ERASED_TABLES, ...KEPT_ON_ERASE]) {
    out[table] = Number((await store.db.query<{ n: string }>(`SELECT count(*) AS n FROM ${table} WHERE user_id = $1`, [userId])).rows[0]!.n);
  }
  return out;
}

test("eraseUser deletes every row of one person, queues every grant for removal, and keeps the owner and the counters", async () => {
  const store = await Store.memory();
  try {
    await seed(store, ID_A, "aaaa");
    await seed(store, ID_B, "bbbb");
    await store.claimDeviceOwner(ID_A, 1);
    const before = await rows(store, ID_B);

    const erased = await store.eraseUser(ID_A, 5);

    assert.equal(erased.remaining, 0);
    for (const table of ERASED_TABLES) assert.ok(erased.deleted[table] >= 1, `${table} had a row of A`);
    const after = await rows(store, ID_A);
    for (const table of ERASED_TABLES) assert.equal(after[table], 0, `${table} still holds A`);
    // The open sign-in's grant, both connections, the linked Google sign-in (ADR-818, at Supabase) and
    // the Doddy account that took over A's data (decision 2026-11-08-required-account) are owed a removal.
    assert.deepEqual(
      erased.cleanups.map((c) => `${c.provider}:${c.connectionId}`).sort(),
      [
        `${CALENDAR_PROVIDER}:conn-cal-aaaa`,
        "gmail:pending-aaaa",
        "notion:conn-notion-aaaa",
        "supabase_auth:aaaa0000-0000-4000-8000-000000000003",
        "supabase_auth:aaaa0000-0000-4000-8000-000000000006",
      ].sort(),
    );
    assert.equal(after.cleanups, 5);
    assert.deepEqual(erased.subjects, ["aaaa0000-0000-4000-8000-000000000006"]);
    // The erasure itself cut off A's earlier sign-ins (ADR-709) and its account's, and the cut-offs are kept (KEPT_ON_ERASE).
    assert.equal(after.token_floor, 1);
    assert.equal(await store.tokenFloor("aaaa0000-0000-4000-8000-000000000006"), 1, "the account's own sign-ins end too");
    assert.equal(erased.tokensValidAfter, 1, "the second after the erasure's clock (5 ms)");
    assert.equal(await store.tokenFloor(ID_A), 1);
    assert.equal(await store.tokenFloor(ID_B), 0, "nobody else is cut off");
    // Not reset by deleting: the server stays A's, and the counts (A's own and the server's) stay.
    assert.equal(await store.claimDeviceOwner(ID_B, 6), ID_A);
    assert.equal(await store.usage(`user:${ID_A}:ask`, "day:2026-10-10"), 1);
    assert.equal(await store.usage("service:ask", "day:2026-10-10"), 2);
    // Nobody else's rows were touched.
    assert.deepEqual(await rows(store, ID_B), before);
  } finally {
    await store.close();
  }
});

test("every table with a user_id column is either erased or kept on purpose", async () => {
  const store = await Store.memory();
  try {
    const found = (await store.db.query<{ table_name: string }>(
      `SELECT DISTINCT table_name FROM information_schema.columns
       WHERE column_name = 'user_id' AND table_schema = current_schema() ORDER BY table_name`,
      [],
    )).rows.map((r) => r.table_name);
    assert.ok(found.length > 10, "the schema was read");
    assert.deepEqual(found, [...ERASED_TABLES, ...KEPT_ON_ERASE].sort(), "a new per-person table must be added to ERASED_TABLES (or KEPT_ON_ERASE, with a reason)");
  } finally {
    await store.close();
  }
});

// ---------------------------------------------------------------- the route

/** Dev identities for A and B, and one guest iPhone (ADR-587: Ask Doddy only). */
class Verifier implements SessionVerifier {
  private readonly dev = new DevSessionVerifier();
  verify(header: string | undefined): AuthenticatedUser | null {
    if (header === `Bearer ${GUEST_TOKEN}`) return { userId: GUEST_ID, scope: "ask" };
    return this.dev.verify(header);
  }
}

let server: Server | undefined;
let store: Store | undefined;
afterEach(async () => {
  server?.close();
  await store?.close();
  server = undefined;
  store = undefined;
});

async function rig() {
  store = await Store.memory();
  const clock = new Clock(Date.parse("2026-10-10T10:00:00Z"));
  const logs: string[] = [];
  const toolsProvider = new MockToolsProvider();
  // Flipped by a test: the provider answers that a removal failed.
  const removals = { fail: false };
  const calendarProvider = new MockCalendarProvider();
  const common = { store, limits: testLimits(), publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return", now: clock.now, sleep: async () => {} };
  const tools = new CloudToolsService({ ...common, provider: toolsProvider, webSearch: null, claude: null, documentLinks: null, completionMode: "mock" });
  const service = new ConnectedAppsService({ ...common, provider: calendarProvider, registry: defaultRegistry(), completionMode: "mock" });
  const account = new AccountEraser({
    store,
    removers: [
      { providers: [CALENDAR_PROVIDER], remove: (connectionId) => calendarProvider.removeConnection({ connectionId }) },
      {
        providers: Object.keys(TOOLKITS),
        remove: async (connectionId) => {
          if (!removals.fail) return toolsProvider.removeConnection({ connectionId });
          toolsProvider.calls.push("removeConnection");
          return "failed";
        },
      },
    ],
    timeoutMs: 1_000,
    now: clock.now,
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const handler = createHandler({
    service,
    tools,
    account,
    verifier: new Verifier(),
    appReturnUrl: common.appReturnUrl,
    maxBodyBytes: 8 * 1024,
    now: () => new Date(clock.ms),
    log: (line) => logs.push(JSON.stringify(line)),
  });
  server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = async (method: string, path: string, o: { token?: string | null; body?: unknown; headers?: Record<string, string> } = {}) => {
    const headers: Record<string, string> = { ...(o.headers ?? {}) };
    const token = o.token === undefined ? USER_A : o.token;
    if (token !== null) headers.authorization = `Bearer ${token}`;
    let body: string | undefined;
    if (o.body !== undefined) {
      headers["content-type"] = "application/json";
      body = JSON.stringify(o.body);
    }
    const res = await fetch(`${base}${path}`, { method, headers, ...(body !== undefined ? { body } : {}) });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  const connect = async (toolkit: string, token = USER_A) => {
    const begin = await call("POST", `/v1/tools/${toolkit}/connect`, { token, body: {} });
    assert.equal(begin.status, 200, JSON.stringify(begin.body));
    const done = await call("POST", `/v1/tools/${toolkit}/complete`, {
      token,
      body: { attemptId: begin.body.attemptId, nonce: begin.body.nonce, result: { kind: "mock", outcome: "approve" } },
    });
    assert.equal(done.status, 200, JSON.stringify(done.body));
  };
  return { store, clock, logs, toolsProvider, calendarProvider, removals, tools, call, connect };
}

test("DELETE /v1/account erases the person's rows and removes each online account at its provider", async () => {
  const r = await rig();
  await r.connect("gmail");
  await r.connect("notion");
  await r.connect("gmail", USER_B);
  await r.store.claimDeviceOwner(ID_A, r.clock.ms);

  const res = await r.call("DELETE", "/v1/account");
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.complete, true);
  assert.equal(res.body.remaining, 0);
  assert.deepEqual([...res.body.onlineAccounts.removed].sort(), ["gmail", "notion"]);
  assert.deepEqual(res.body.onlineAccounts.pending, []);
  assert.equal(res.body.deleted.connections, 2);
  assert.equal(res.body.deleted.users, 1);
  assert.equal(res.body.erasedAt, "2026-10-10T10:00:00.000Z");
  assert.ok(Array.isArray(res.body.kept) && res.body.kept.length === 4, "the owner, the counts, the owed removals and (ADR-709) the sign-in cut-off");
  assert.equal(r.toolsProvider.calls.filter((c) => c === "removeConnection").length, 2);
  const left = await rows(r.store, ID_A);
  for (const table of ERASED_TABLES) assert.equal(left[table], 0, `${table} still holds A`);
  assert.equal(left.cleanups, 0, "every removal was confirmed");
  assert.equal(left.device_owner, 1, "the server stays A's");

  // B keeps everything; A starts over as a stranger with nothing connected.
  assert.equal((await r.store.getConnection(ID_B, "gmail"))?.status, "connected");
  const catalog = await r.call("GET", "/v1/tools");
  assert.equal(catalog.status, 200);
  assert.equal(catalog.body.toolkits.find((t: { id: string }) => t.id === "gmail")?.status, "disconnected");
  // The log line is content-free.
  const line = r.logs.find((l) => l.includes("account_erased"))!;
  assert.ok(!line.includes(ID_A) && !line.includes("gmail"), line);
});

test("a removal that fails is pending, never done, and the hourly sweep finishes it", async () => {
  const r = await rig();
  await r.connect("gmail");
  r.removals.fail = true;

  const res = await r.call("DELETE", "/v1/account");
  assert.equal(res.status, 200);
  assert.equal(res.body.complete, false, "a grant still at the provider is not a finished deletion");
  assert.equal(res.body.remaining, 0, "the rows are gone either way");
  assert.deepEqual(res.body.onlineAccounts, { removed: [], pending: ["gmail"] });
  assert.equal((await rows(r.store, ID_A)).cleanups, 1);

  r.removals.fail = false;
  r.clock.advance(10 * 60_000);
  await r.tools.sweepAbandoned();
  assert.equal((await rows(r.store, ID_A)).cleanups, 0, "the sweep removed it at the provider");
});

test("a guest iPhone can delete its own data; a request without the iPhone's session can't", async () => {
  const r = await rig();
  await r.store.setLogbookEnabled(GUEST_ID, true, r.clock.ms);
  // A guest can't use the rest of the API, but deleting is theirs.
  assert.equal((await r.call("GET", "/v1/tools", { token: GUEST_TOKEN })).body.error.code, "live_not_configured");
  const res = await r.call("DELETE", "/v1/account", { token: GUEST_TOKEN });
  assert.equal(res.status, 200);
  assert.equal(res.body.complete, true);
  assert.equal(res.body.deleted.logbook_state, 1);

  // No Authorization header (a browser cookie alone, or nothing): refused, nothing deleted.
  await r.store.setLogbookEnabled(ID_A, true, r.clock.ms);
  const anon = await r.call("DELETE", "/v1/account", { token: null, headers: { cookie: "doddy_web=whatever" } });
  assert.equal(anon.status, 401);
  assert.equal(await r.store.logbookEnabled(ID_A), true);
});
