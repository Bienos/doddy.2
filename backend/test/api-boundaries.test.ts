import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { CAL, connectMock, FakeComposio, type Harness, harness, liveProvider, tomorrow, USER_B } from "./helpers.js";

let h: Harness;
afterEach(async () => h?.close());

const providerCalls = (h: Harness) => (h.provider instanceof MockCalendarProvider ? h.provider.calls.length : -1);

test("every user route rejects missing or invalid sessions before any provider call", async () => {
  h = await harness();
  const routes: [string, string][] = [
    ["GET", "/v1/connected-apps"],
    ["GET", CAL],
    ["GET", `${CAL}/receipts`],
    ["POST", `${CAL}/connect`],
    ["POST", `${CAL}/complete`],
    ["POST", `${CAL}/events`],
    ["POST", `${CAL}/disconnect`],
  ];
  for (const [method, path] of routes) {
    for (const token of [null, "dev-user-z", "eyJhbGciOiJub25lIn0.e30."]) {
      const res = await h.call(method, path, { token, ...(method === "POST" ? { body: {} } : {}) });
      assert.equal(res.status, 401, `${method} ${path} with ${token}`);
      assert.equal(res.body.error.code, "unauthenticated");
    }
  }
  assert.equal(providerCalls(h), 0);
});

test("a user cannot see, read, complete or disconnect another user's connection", async () => {
  h = await harness();
  const a = await connectMock(h);
  assert.equal(a.done.status, 200);
  assert.equal(a.done.body.connection.status, "connected");

  const bStatus = await h.call("GET", CAL, { token: USER_B });
  assert.equal(bStatus.body.status, "disconnected");

  const before = providerCalls(h);
  const bRead = await h.call("POST", `${CAL}/events`, { token: USER_B, body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
  assert.equal(bRead.status, 409);
  assert.equal(bRead.body.error.code, "not_connected");
  assert.equal(providerCalls(h), before, "no provider call for user B");

  // B replays A's attempt credentials.
  const bComplete = await h.call("POST", `${CAL}/complete`, {
    token: USER_B,
    body: { attemptId: a.start.attemptId, nonce: a.start.nonce, result: { kind: "mock", outcome: "approve" } },
  });
  assert.equal(bComplete.body.error.code, "attempt_invalid");

  const bDisconnect = await h.call("POST", `${CAL}/disconnect`, { token: USER_B, body: {} });
  assert.equal(bDisconnect.status, 200);
  assert.equal((await h.call("GET", CAL)).body.status, "connected", "A is still connected");

  const bReceipts = await h.call("GET", `${CAL}/receipts`, { token: USER_B });
  assert.ok(bReceipts.body.receipts.every((r: { operation: string }) => r.operation !== "connect"), "B sees none of A's receipts");
});

test("raw tool, proxy and account-selection escape attempts are refused before the provider", async () => {
  h = await harness();
  await connectMock(h);
  const before = providerCalls(h);
  const date = tomorrow(h);
  for (const path of ["/v1/tools/execute", "/v1/proxy", "/v1/connected-apps/googlecalendar/events", `${CAL}/../../tools`, "/v1/connected-apps/notion/connect"]) {
    const res = await h.call("POST", path, { body: { tool: "GOOGLECALENDAR_CREATE_EVENT" } });
    assert.equal(res.status, 404, path);
  }
  const bodies = [
    { date, timeZone: "Europe/Warsaw", toolSlug: "GOOGLECALENDAR_CREATE_EVENT" },
    { date, timeZone: "Europe/Warsaw", connectedAccountId: "ca_other" },
    { date, timeZone: "Europe/Warsaw", userId: "00000000-0000-4000-8000-00000000000b" },
    { date, timeZone: "Europe/Warsaw", calendarId: "someone@example.com" },
    { date, timeZone: "Europe/Warsaw", url: "https://evil.example" },
  ];
  for (const body of bodies) {
    const res = await h.call("POST", `${CAL}/events`, { body });
    assert.equal(res.status, 400, JSON.stringify(body));
  }
  assert.equal(providerCalls(h), before);
});

test("invalid arguments are rejected before the provider", async () => {
  h = await harness();
  await connectMock(h);
  const before = providerCalls(h);
  const date = tomorrow(h);
  const cases: unknown[] = [
    { date, timeZone: "+02:00" },
    { date, timeZone: "PST" },
    { date: "tomorrow", timeZone: "Europe/Warsaw" },
    { date: "2026-02-30", timeZone: "Europe/Warsaw" },
    { date: "2026-10-01", timeZone: "Europe/Warsaw" },
    { date: "2026-12-31", timeZone: "Europe/Warsaw" },
    { date },
    "[]",
    "{not json",
  ];
  for (const body of cases) {
    const res = await h.call("POST", `${CAL}/events`, { body });
    assert.equal(res.status, 400, JSON.stringify(body));
  }
  const noType = await fetch(`${h.base}${CAL}/events`, {
    method: "POST",
    headers: { authorization: "Bearer dev-user-a", "content-type": "text/plain" },
    body: JSON.stringify({ date, timeZone: "Europe/Warsaw" }),
  });
  assert.equal(noType.status, 400);
  const huge = await h.call("POST", `${CAL}/events`, { body: { date, timeZone: "Europe/Warsaw", pad: "x".repeat(20_000) } });
  assert.equal(huge.status, 413);
  assert.equal(providerCalls(h), before);
});

test("demo scenario header is refused outside mock mode", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const res = await h.call("POST", `${CAL}/connect`, { body: {}, headers: { "x-doddy-demo-scenario": "events" } });
  assert.equal(res.status, 400);
  assert.equal(fake.calls.length, 0);
});

test("a write-capable grant is never treated as read-only; reads are blocked before the provider", async () => {
  h = await harness();
  const broad = await connectMock(h, "dev-user-a", "broad_scope");
  assert.equal(broad.done.body.connection.status, "permission_insufficient");
  assert.equal(broad.done.body.connection.reason, "grant_not_read_only");
  assert.equal(broad.done.body.receipt.status, "blocked");
  const before = providerCalls(h);
  const read = await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
  assert.equal(read.status, 403);
  assert.equal(read.body.error.code, "permission_insufficient");
  assert.equal(read.body.error.receipt.status, "blocked");
  assert.equal(providerCalls(h), before);
});

test("a grant without calendar read is insufficient", async () => {
  h = await harness();
  const res = await connectMock(h, "dev-user-a", "insufficient_scope");
  assert.equal(res.done.body.connection.reason, "missing_read_scope");
});

test("an unverifiable grant (scopes not exposed) blocks live use", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const start = await h.call("POST", `${CAL}/connect`, { body: {} });
  const pending = [...fake.accounts.keys()][0]!;
  fake.activate(pending, null);
  const done = await h.call("POST", `${CAL}/complete`, {
    body: { attemptId: start.body.attemptId, nonce: start.body.nonce, result: { kind: "callback", status: "success", connectedAccountId: pending } },
  });
  assert.equal(done.body.connection.status, "permission_insufficient");
  assert.equal(done.body.connection.reason, "grant_unverifiable");
  const executes = fake.calls.filter((c) => c.startsWith("execute")).length;
  await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
  assert.equal(fake.calls.filter((c) => c.startsWith("execute")).length, executes);
});

test("no write capability is reachable", async () => {
  h = await harness();
  const health = await h.call("GET", "/v1/health", { token: null });
  assert.deepEqual(health.body.capabilities, ["calendar.listEvents"]);
  assert.equal(h.service.confirmations instanceof Object, true);
});

test("a malformed request target is a 400, and the server keeps serving", async () => {
  h = await harness();
  const { request } = await import("node:net").then((net) => ({
    request: (raw: string) =>
      new Promise<string>((resolve) => {
        const socket = net.connect(Number(new URL(h.base).port), "127.0.0.1");
        let data = "";
        socket.on("data", (d) => (data += d.toString()));
        socket.on("close", () => resolve(data));
        socket.on("error", () => resolve(data));
        socket.write(raw);
        setTimeout(() => socket.end(), 200);
      }),
  }));
  for (const target of ["//[", "//h:99999999"]) {
    const reply = await request(`GET ${target} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n`);
    assert.match(reply.split("\r\n")[0] ?? "", /^HTTP\/1\.1 400/, target);
  }
  assert.equal((await h.call("GET", "/v1/health", { token: null })).status, 200);
});

test("refused requests are capped before any receipt is written", async () => {
  h = await harness({ limits: { userDailyReads: 2 } });
  const statuses: number[] = [];
  for (let i = 0; i < 12; i++) {
    statuses.push((await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } })).status);
  }
  assert.deepEqual(statuses.slice(0, 8), Array(8).fill(409));
  assert.ok(statuses.slice(8).every((s) => s === 429));
  const receipts = h.store.db.prepare("SELECT COUNT(*) AS n FROM receipts").get() as { n: number };
  assert.equal(receipts.n, 8);
});

test("one user can never use more than a quarter of the service's daily provider calls", async () => {
  h = await harness({ limits: { serviceDailyCalls: 8, userDailyReads: 30 } });
  await connectMock(h, "dev-user-a", "many"); // 3 provider calls per read
  assert.equal((await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } })).body.error.code, "quota_exceeded");
});
