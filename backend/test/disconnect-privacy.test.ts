import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import net from "node:net";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { CapabilityRegistry, defaultRegistry } from "../src/capabilities.js";
import { ConfirmationPolicy } from "../src/policy.js";
import type { CapabilityDefinition } from "../src/capabilities.js";
import {
  ConnectionResultSchema,
  ConnectionViewSchema,
  ConnectResponseSchema,
  ErrorResponseSchema,
  EventsResultSchema,
} from "../src/contracts.js";
import { Store } from "../src/store.js";
import { z } from "zod";
import { CAL, connectMock, FakeComposio, type Harness, harness, liveProvider, PLANTED_TOKEN, tomorrow } from "./helpers.js";

let h: Harness;
afterEach(async () => h?.close());

test("disconnect blocks reads at once and reports remote cleanup honestly when it fails", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const start = await h.call("POST", `${CAL}/connect`, { body: {} });
  const pending = [...fake.accounts.keys()][0]!;
  fake.activate(pending);
  await h.call("POST", `${CAL}/complete`, {
    body: { attemptId: start.body.attemptId, nonce: start.body.nonce, result: { kind: "callback", status: "success", connectedAccountId: pending } },
  });
  fake.deleteFails = true;
  const off = await h.call("POST", `${CAL}/disconnect`, { body: {} });
  assert.equal(off.status, 200);
  assert.equal(off.body.connection.status, "disconnected");
  assert.equal(off.body.connection.remoteCleanup, "failed");
  assert.equal(off.body.receipt.status, "outcome_unknown");
  assert.ok(fake.calls.includes("revoke"));

  const executes = fake.calls.filter((c) => c.startsWith("execute")).length;
  const read = await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
  assert.equal(read.body.error.code, "not_connected");
  assert.equal(fake.calls.filter((c) => c.startsWith("execute")).length, executes, "no provider call after disconnect");

  fake.deleteFails = false;
  const retry = await h.call("POST", `${CAL}/disconnect`, { body: {} });
  assert.equal(retry.body.connection.remoteCleanup, "none");
  assert.equal(retry.body.receipt.status, "succeeded");
  assert.equal(fake.accounts.has(pending), false);
});

test("mock disconnect succeeds and a later read is blocked", async () => {
  h = await harness();
  await connectMock(h);
  const off = await h.call("POST", `${CAL}/disconnect`, { body: {} });
  assert.equal(off.body.receipt.status, "succeeded");
  assert.equal((await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } })).status, 409);
});

test("mock mode opens zero outbound connections", async () => {
  const outbound: string[] = [];
  const original = net.Socket.prototype.connect;
  net.Socket.prototype.connect = function (this: net.Socket, ...args: unknown[]) {
    const first = args[0] as { host?: string; port?: number } | number | string;
    const host = typeof first === "object" && first !== null ? (first.host ?? "localhost") : typeof args[1] === "string" ? args[1] : "localhost";
    if (!["127.0.0.1", "localhost", "::1"].includes(host)) outbound.push(host);
    return (original as (...a: unknown[]) => net.Socket).apply(this, args);
  } as typeof original;
  try {
    h = await harness();
    await connectMock(h);
    for (const scenario of ["events", "empty", "many", "timeout", "rate_limited", "malformed"]) {
      await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" }, headers: { "x-doddy-demo-scenario": scenario } });
    }
    await h.call("GET", CAL);
    await h.call("POST", `${CAL}/disconnect`, { body: {} });
  } finally {
    net.Socket.prototype.connect = original;
  }
  assert.deepEqual(outbound, []);
});

test("logs, receipts and the database hold no event content, tokens, nonces or session URIs", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake), completionMode: "verifier" });
  const start = await h.call("POST", `${CAL}/connect`, { body: {} });
  const pending = [...fake.accounts.keys()][0]!;
  fake.sessions.set("composio://session/SENSITIVE-SESSION", pending);
  fake.accounts.get(pending)!.scope = "https://www.googleapis.com/auth/calendar.events.readonly";
  await h.call("POST", `${CAL}/complete`, {
    body: { attemptId: start.body.attemptId, nonce: start.body.nonce, result: { kind: "verifier", sessionUri: "composio://session/SENSITIVE-SESSION" } },
  });
  await h.call("GET", "/v1/oauth/verify?session_uri=composio://session/SENSITIVE-SESSION", { token: null });
  fake.execute = async () => ({
    successful: true,
    error: null,
    data: { items: [{ summary: "Therapy appointment", description: "private", start: { date: tomorrow(h) }, end: { date: "2099-01-01" } }] },
  });
  const res = await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
  assert.equal(res.body.events[0].title, "Therapy appointment", "the user sees their event");

  const dump = [
    h.logs.join("\n"),
    JSON.stringify((await h.store.db.query("SELECT * FROM receipts")).rows),
    JSON.stringify((await h.store.db.query("SELECT * FROM connections")).rows),
    JSON.stringify((await h.store.db.query("SELECT * FROM attempts")).rows),
  ].join("\n");
  for (const secret of ["Therapy", "private", PLANTED_TOKEN, "PLANTED-REFRESH", "SENSITIVE-SESSION", start.body.nonce, "dev-user-a"]) {
    assert.ok(!dump.includes(secret), `leaked: ${secret}`);
  }
  const tables = (await h.store.db.query<{ name: string }>(
    "SELECT table_name AS name FROM information_schema.tables WHERE table_schema = 'doddy_backend'",
  )).rows.map((t) => t.name);
  assert.ok(tables.includes("receipts"), "the schema's tables are listed");
  // ADR-595: the three tables of notes and conversations a person chose to keep on the server (encrypted,
  // off until the iPhone turns them on; test/memory.test.ts) are the only content tables allowed. Anything
  // else that looks like content still fails here.
  const keptOnRequest = new Set(["memory_state", "memory_notes", "memory_conversations"]);
  assert.deepEqual(tables.filter((t) => /memor/i.test(t)).sort(), [...keptOnRequest].sort(), "exactly the kept-on-request tables");
  assert.ok(!tables.filter((t) => !keptOnRequest.has(t)).some((t) => /event|memor|chat|contact/i.test(t)), `no other content tables: ${tables}`);
});

// ------------------------------------------------------------------ confirmation foundation

const SYNTHETIC_WRITE: CapabilityDefinition = {
  id: "test.syntheticWrite",
  version: 1,
  provider: "synthetic",
  input: z.object({ title: z.string() }).strict(),
  requiredAnyGrant: [],
  risk: "write",
  confirmation: "fresh_per_execution",
  enabledModes: [],
  timeoutMs: 1_000,
  resultBounds: { maxEvents: 0, maxPages: 0, maxTitleLength: 0 },
  retry: { maxRetries: 0, baseDelayMs: 0, maxDelayMs: 0 },
  costClass: "provider_call",
  receipt: "always",
  status: "planned",
  evidence: "test only; never executes",
};

test("confirmation: missing, expired, replayed, changed-argument, other-user and other-account approvals are rejected", async () => {
  const store = await Store.memory();
  const policy = new ConfirmationPolicy(store, 120);
  const t0 = Date.parse("2026-10-09T10:00:00Z");
  const base = { userId: "u1", capability: SYNTHETIC_WRITE, accountId: "acct1", args: { title: "Dinner" } };
  let executions = 0;
  const execute = async (approvalId: string | undefined, overrides: Partial<typeof base> = {}, now = t0 + 1_000) => {
    await policy.require({ ...base, ...overrides, approvalId, now });
    executions += 1; // stands in for a handler; nothing real is executed
  };

  await assert.rejects(() => execute(undefined));
  const a1 = await policy.approve({ ...base, now: t0 });
  await assert.rejects(() => execute(a1.approvalId, { args: { title: "Dinner!" } }), "changed arguments");
  await assert.rejects(() => execute(a1.approvalId, { userId: "u2" }), "other user");
  await assert.rejects(() => execute(a1.approvalId, { accountId: "acct2" }), "other account");
  await execute(a1.approvalId);
  await assert.rejects(() => execute(a1.approvalId), "replay");
  const a2 = await policy.approve({ ...base, now: t0 });
  await assert.rejects(() => execute(a2.approvalId, {}, t0 + 121_000), "expired");
  const a3 = await policy.approve({ ...base, args: { title: "Dinner" }, now: t0 });
  await execute(a3.approvalId, { args: JSON.parse('{"title":"Dinner"}') });
  assert.equal(executions, 2);
  (await store.close());
});

test("the registry keeps writes disabled and refuses unsafe write definitions", () => {
  const registry = defaultRegistry();
  assert.equal(registry.isEnabled("calendar.createEvent", "live"), false);
  assert.equal(registry.isEnabled("calendar.createEvent", "mock"), false);
  assert.equal(registry.isEnabled("calendar.listEvents", "live"), true);
  assert.throws(() => new CapabilityRegistry([{ ...SYNTHETIC_WRITE, confirmation: "none" }]), /confirmation/);
  assert.throws(() => new CapabilityRegistry([{ ...SYNTHETIC_WRITE, retry: { maxRetries: 1, baseDelayMs: 1, maxDelayMs: 1 } }]), /retry/);
});

// ------------------------------------------------------------------ contract fixtures (shared with Swift)

test("contract fixtures match the server schemas", () => {
  const dir = join(process.cwd(), "..", "contracts", "connected-apps");
  const schemas: Record<string, z.ZodTypeAny> = {
    "connect-response": ConnectResponseSchema,
    "connection-result": ConnectionResultSchema,
    "connection-view": ConnectionViewSchema,
    "events-result": EventsResultSchema,
    error: ErrorResponseSchema,
  };
  const files = readdirSync(dir).filter((f) => f.endsWith(".json"));
  assert.ok(files.length >= 6, "fixtures exist");
  for (const file of files) {
    const prefix = Object.keys(schemas).find((p) => file.startsWith(p));
    assert.ok(prefix, `no schema for ${file}`);
    schemas[prefix!]!.parse(JSON.parse(readFileSync(join(dir, file), "utf8")));
  }
});

test("reconnecting retries a failed remote cleanup before creating a new link", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const first = await h.call("POST", `${CAL}/connect`, { body: {} });
  const old = [...fake.accounts.keys()][0]!;
  fake.activate(old);
  await h.call("POST", `${CAL}/complete`, {
    body: { attemptId: first.body.attemptId, nonce: first.body.nonce, result: { kind: "callback", status: "success", connectedAccountId: old } },
  });
  fake.deleteFails = true;
  await h.call("POST", `${CAL}/disconnect`, { body: {} });
  fake.deleteFails = false;
  const again = await h.call("POST", `${CAL}/connect`, { body: {} });
  assert.equal(again.status, 200);
  assert.equal(fake.accounts.has(old), false, "stale connection removed before the new link");
  assert.equal((await h.call("GET", CAL)).body.remoteCleanup, "none");
});
