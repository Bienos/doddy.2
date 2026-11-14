import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { AccountEraser } from "../src/account.js";
import { AccountLinker } from "../src/accountLinks.js";
import { type AuthenticatedUser, RevocableSessionVerifier, type SessionVerifier, SignedSessionVerifier, TokenFloors } from "../src/auth.js";
import { defaultRegistry } from "../src/capabilities.js";
import { testLimits } from "../src/config.js";
import { DocumentSeal } from "../src/documents.js";
import { AppError } from "../src/errors.js";
import { MemoryCipher } from "../src/memory/crypto.js";
import { createHandler } from "../src/http.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { requestCredential } from "../src/requestCredential.js";
import { ConnectedAppsService } from "../src/service.js";
import { CLEANUP_RETRY, retryDelayMs, Store, SUPABASE_AUTH_CLEANUP } from "../src/store.js";
import { MockToolsProvider } from "../src/tools/mock.js";
import { CloudToolsService } from "../src/tools/service.js";
import { MockWebSearchProvider, type WebSearchRun } from "../src/tools/websearch.js";
import { Clock } from "./helpers.js";

/**
 * Deleting an account, and what it leaves to finish (ADR-674, ADR-709):
 * - a request let in just before the deletion can't write the person's rows back after it;
 * - removals owed at providers are retried without a last try, and reported when stuck;
 * - the account-link count lives under a period that is pruned.
 */

const KEY = Buffer.alloc(32, 7);
const USER = "00000000-0000-4000-8000-0000000000e1";
const OTHER = "00000000-0000-4000-8000-0000000000e2";
const HOUR = 3_600_000;

let servers: Server[] = [];
let stores: Store[] = [];
afterEach(async () => {
  for (const server of servers) server.close();
  for (const store of stores) await store.close();
  servers = [];
  stores = [];
});

/** The demo web search, held at the provider until the test lets it go. */
class HeldSearch extends MockWebSearchProvider {
  private release!: () => void;
  private readonly gate = new Promise<void>((resolve) => (this.release = resolve));
  private reached!: () => void;
  /** Resolves once a search is waiting at the provider. */
  readonly waiting = new Promise<void>((resolve) => (this.reached = resolve));

  override async search(input: { query: string; signal: AbortSignal }): Promise<WebSearchRun> {
    this.reached();
    await this.gate;
    return super.search(input);
  }

  letGo(): void {
    this.release();
  }
}

async function rig() {
  const store = await Store.memory();
  stores.push(store);
  const clock = new Clock(Date.parse("2026-11-12T10:00:00.400Z"));
  const floors = new TokenFloors(store);
  const webSearch = new HeldSearch();
  const common = { store, limits: testLimits(), publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return", now: clock.now, sleep: async () => {} };
  const tools = new CloudToolsService({ ...common, provider: new MockToolsProvider(), webSearch, claude: null, documentLinks: null, completionMode: "mock" });
  const service = new ConnectedAppsService({ ...common, provider: new MockCalendarProvider(), registry: defaultRegistry(), completionMode: "mock" });
  const account = new AccountEraser({ store, removers: [], timeoutMs: 1_000, floors, now: clock.now });
  const handler = createHandler({
    service,
    tools,
    account,
    verifier: new RevocableSessionVerifier(new SignedSessionVerifier(KEY), floors),
    appReturnUrl: common.appReturnUrl,
    maxBodyBytes: 8 * 1024,
    now: () => new Date(clock.ms),
    log: () => {},
  });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  servers.push(server);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const api = async (method: string, path: string, token: string, body?: unknown) => {
    const headers: Record<string, string> = { authorization: `Bearer ${token}` };
    if (body !== undefined) headers["content-type"] = "application/json";
    const res = await fetch(`${base}${path}`, { method, headers, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
    const text = await res.text();
    return { status: res.status, body: text ? (JSON.parse(text) as any) : null };
  };
  /** A device token for USER dated `ms` (the iPhone's sign-in). */
  const token = (ms: number) => new SignedSessionVerifier(KEY).mint(USER, new Date(ms), 3_600);
  const count = async (table: string) =>
    Number((await store.db.query<{ n: string }>(`SELECT count(*) AS n FROM ${table} WHERE user_id = $1`, [USER])).rows[0]!.n);
  return { store, clock, webSearch, api, token, count };
}

test("a request let in just before the account is deleted can't write the person's rows back after it", async () => {
  const r = await rig();
  const before = r.token(r.clock.ms - 10_000);
  assert.equal((await r.api("PUT", "/v1/tools/switch", before, { tool: "web_search", enabled: true })).status, 200);
  assert.equal(await r.count("tool_switches"), 1);

  // A search (asked first, as the app does) is let in and waits at the provider while the account is deleted.
  const args = { query: "opening hours" };
  const asked = await r.api("POST", "/v1/tools/prepare", before, { tool: "web_search", arguments: args });
  assert.equal(asked.status, 200, JSON.stringify(asked.body));
  const running = r.api("POST", "/v1/tools/run", before, { tool: "web_search", arguments: args, timeZone: "Europe/Warsaw", approvalId: asked.body.approvalId });
  await Promise.race([
    r.webSearch.waiting,
    running.then((res) => assert.fail(`the search answered before it reached the provider: ${JSON.stringify(res.body)}`)),
  ]);
  const erased = await r.api("DELETE", "/v1/account", before);
  assert.equal(erased.status, 200, JSON.stringify(erased.body));
  assert.equal(erased.body.deleted.tool_switches, 1);
  r.webSearch.letGo();

  // Its receipt is refused like the token itself now is, and nothing of the person is back.
  const late = await running;
  assert.equal(late.status, 401, JSON.stringify(late.body));
  assert.equal(late.body.error.code, "unauthenticated");
  for (const table of ["tool_receipts", "tool_switches", "users", "receipts", "documents", "approvals"]) assert.equal(await r.count(table), 0, table);

  // A sign-in after the deletion (dated at its cut-off or later) writes as usual.
  const floorMs = (await r.store.tokenFloor(USER)) * 1000;
  const after = r.token(floorMs);
  assert.equal((await r.api("PUT", "/v1/tools/switch", after, { tool: "web_search", enabled: false })).status, 200);
  assert.equal(await r.count("tool_switches"), 1);
});

test("each kind of write a request makes for a deleted person is refused, and only for that person and that request", async () => {
  const store = await Store.memory();
  stores.push(store);
  // Files are kept only encrypted: with a key, so the documents write below reaches the cut-off check.
  store.sealDocumentsWith(new DocumentSeal(new MemoryCipher(Buffer.alloc(32, 6))));
  const now = Date.parse("2026-11-12T10:00:00Z");
  await store.eraseUser(USER, now);
  const floor = await store.tokenFloor(USER);
  const writes: [string, () => Promise<unknown>][] = [
    ["users", () => store.composioUserId(USER, now)],
    ["receipts", () => store.saveReceipt(USER, { operationId: "op-1" } as never, now)],
    ["tool_receipts", () => store.saveToolReceipt(USER, { operationId: "op-2" }, now)],
    ["payment_receipts", () => store.savePaymentReceipt(USER, { operationId: "op-3" }, now)],
    ["tool_switches", () => store.setToolEnabled(USER, "web_search", true, now)],
    ["tool_switches (off)", () => store.disableTools(USER, ["check_email"], now)],
    ["documents", () => store.startDocument(USER, "a.md", "text/markdown", now)],
    ["payments", () => store.insertPayment({ paymentId: "p-1", userId: USER, now, host: "shop.example", amount: 1, network: "base-sepolia", urlHash: "h", validBefore: now })],
    ["approvals", () => store.createApproval({ userId: USER, capability: "send_email", accountId: "a", argsDigest: "d", now, ttlSeconds: 60 })],
  ];
  for (const [name, write] of writes) {
    // A request whose sign-in dates from before the deletion: refused, like its token.
    await assert.rejects(
      requestCredential.run({ userId: USER, issuedAt: floor - 1 }, write),
      (error: unknown) => error instanceof AppError && error.code === "unauthenticated",
      name,
    );
  }
  const rows = async () => {
    let n = 0;
    for (const table of ["users", "receipts", "tool_receipts", "payment_receipts", "tool_switches", "documents", "payments", "approvals"]) {
      n += Number((await store.db.query<{ n: string }>(`SELECT count(*) AS n FROM ${table} WHERE user_id = $1`, [USER])).rows[0]!.n);
    }
    return n;
  };
  assert.equal(await rows(), 0, "nothing written");
  // A sign-in dated at the cut-off (a new one), a request for someone else, and work outside any request all write.
  await requestCredential.run({ userId: USER, issuedAt: floor }, () => store.setToolEnabled(USER, "web_search", true, now));
  await requestCredential.run({ userId: OTHER, issuedAt: 0 }, () => store.setToolEnabled(USER, "news_search", true, now));
  await store.composioUserId(USER, now);
  assert.equal(await rows(), 3);
});

test("a removal owed after a deletion with no way to remove it here is reported stuck at once, and the sweep finishes it once there is", async () => {
  const store = await Store.memory();
  stores.push(store);
  const clock = new Clock(Date.parse("2026-11-12T10:00:00Z"));
  const logs: Record<string, unknown>[] = [];
  const identity = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
  await store.createWebAccount({ userId: USER, identityId: identity, provider: "google", now: clock.ms });
  // No SUPABASE_SECRET_KEY on this server: nothing can remove the Supabase user.
  const without = new AccountEraser({ store, removers: [], timeoutMs: 1_000, now: clock.now, log: (line) => logs.push(line) });
  const erased = await without.erase(USER);
  assert.equal(erased.complete, false);
  assert.deepEqual(erased.onlineAccounts.pending, [SUPABASE_AUTH_CLEANUP]);
  const stuck = await store.stuckCleanups();
  assert.deepEqual(stuck.map((s) => [s.provider, s.last_error, s.stuck_at]), [[SUPABASE_AUTH_CLEANUP, "no_remover", clock.ms]]);
  const line = logs.find((l) => l.event === "cleanup_stuck")!;
  assert.deepEqual([line.level, line.provider, line.reason], ["warn", SUPABASE_AUTH_CLEANUP, "no_remover"]);
  assert.ok(!JSON.stringify(logs).includes(identity) && !JSON.stringify(logs).includes(USER), "no id in the log");

  // The key is set later: the hourly sweep removes it, and it is no longer listed.
  const removed: string[] = [];
  const withKey = new AccountEraser({
    store,
    removers: [{ providers: [SUPABASE_AUTH_CLEANUP], remove: async (id) => (removed.push(id), "removed") }],
    timeoutMs: 1_000,
    now: clock.now,
  });
  clock.advance(HOUR);
  await withKey.sweep([SUPABASE_AUTH_CLEANUP]);
  assert.deepEqual(removed, [identity]);
  assert.deepEqual(await store.stuckCleanups(), []);
});

test("a removal that keeps failing at the provider is retried at the hourly sweeps without end, and reported once", async () => {
  const store = await Store.memory();
  stores.push(store);
  const clock = new Clock(Date.parse("2026-11-12T10:00:00Z"));
  const logs: Record<string, unknown>[] = [];
  let tries = 0;
  const eraser = new AccountEraser({
    store,
    removers: [{ providers: [SUPABASE_AUTH_CLEANUP], remove: async () => (tries++, "failed") }],
    timeoutMs: 1_000,
    now: clock.now,
    log: (line) => logs.push(line),
  });
  await store.createWebAccount({ userId: USER, identityId: "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab", provider: "google", now: clock.ms });
  await eraser.erase(USER);
  assert.equal(tries, 1);
  // Thirty days of hourly sweeps: the tries thin out (backing off to one a day) but never stop.
  const triedAt: number[] = [];
  for (let hour = 1; hour <= 30 * 24; hour++) {
    clock.advance(HOUR);
    const before = tries;
    await eraser.sweep([SUPABASE_AUTH_CLEANUP]);
    if (tries > before) triedAt.push(hour);
  }
  assert.ok(tries > CLEANUP_RETRY.stuckAfter, `${tries} tries`);
  assert.ok(triedAt.at(-1)! > 29 * 24, "still trying on the last day");
  const gaps = triedAt.slice(1).map((h, i) => h - triedAt[i]!);
  assert.ok(gaps.every((g) => g <= 25), "never more than a day (and the sweep's hour) apart");
  assert.equal(gaps.at(-1), 24, "a day apart once backed off");
  assert.equal(retryDelayMs(1), CLEANUP_RETRY.firstDelayMs);
  assert.equal(retryDelayMs(1_000), CLEANUP_RETRY.maxDelayMs);
  const reported = logs.filter((l) => l.event === "cleanup_stuck");
  assert.equal(reported.length, 1, "reported once");
  assert.equal(reported[0]!.attempts, CLEANUP_RETRY.stuckAfter);
  assert.equal(reported[0]!.reason, "remote_cleanup_failed");
  assert.equal((await store.stuckCleanups()).length, 1);
});

test("the account-link count is kept per hour under a pruned period, and old hour periods are pruned", async () => {
  const store = await Store.memory();
  stores.push(store);
  const now = new Date("2026-11-12T10:30:00Z");
  // A stand-in for the Supabase check: the header's own claims (the real check is in account-links.test.ts).
  const subject = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
  const jwt = `${Buffer.from("{}").toString("base64url")}.${Buffer.from(JSON.stringify({ sub: subject, iat: 1 })).toString("base64url")}.sig`;
  const accounts: SessionVerifier = { verify: (header): AuthenticatedUser | null => (header === `Bearer ${jwt}` ? { userId: subject } : null) };
  const devices = new SignedSessionVerifier(KEY);
  const linker = new AccountLinker({ store, accounts, devices, floors: new TokenFloors(store) });
  // One well-formed try (with a device token, or with a link code where the link takes one) is counted
  // before its outcome; a body the route doesn't take is refused before anything is counted.
  const deviceToken = devices.mint(USER, now, 3_600);
  for (const body of [{ deviceToken }, { linkCode: "A".repeat(43) }]) await linker.link(`Bearer ${jwt}`, body, now).catch(() => null);
  const counts = (await store.db.query<{ period: string; count: number }>("SELECT period, count FROM usage WHERE counter = $1", [`account_link:${subject}`])).rows;
  assert.deepEqual(counts.map((c) => [c.period, Number(c.count)]), [["day:2026-11-12T10", 1]]);

  // Rows from before the change (`hour:`) go once a day old; this hour's stays until its day is pruned.
  await store.db.query("INSERT INTO usage (counter, period, count) VALUES ('account_link:old', 'hour:2026-11-01T09', 3), ('account_link:recent', 'hour:2026-11-12T09', 1)");
  await store.prune(now.getTime());
  const left = (await store.db.query<{ period: string }>("SELECT period FROM usage ORDER BY period")).rows.map((r) => r.period);
  assert.deepEqual(left, ["day:2026-11-12T10", "hour:2026-11-12T09"]);
  await store.prune(now.getTime() + 70 * 24 * HOUR);
  assert.equal(Number((await store.db.query<{ n: string }>("SELECT count(*) AS n FROM usage")).rows[0]!.n), 0, "both pruned in time");
});
