import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { EventsResultSchema } from "../src/contracts.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { CAL, connectMock, FakeComposio, type Harness, harness, liveProvider, PLANTED_TOKEN, tomorrow } from "./helpers.js";

let h: Harness;
afterEach(async () => h?.close());

const listCalls = (h: Harness) => (h.provider as MockCalendarProvider).calls.filter((c) => c === "listEvents").length;
const read = (h: Harness, scenario?: string, tz = "Europe/Warsaw") =>
  h.call("POST", `${CAL}/events`, {
    body: { date: tomorrow(h, tz), timeZone: tz },
    ...(scenario ? { headers: { "x-doddy-demo-scenario": scenario } } : {}),
  });

test("tomorrow's events: bounded, normalized, with source, freshness, mode and receipt", async () => {
  h = await harness();
  await connectMock(h);
  const res = await read(h);
  assert.equal(res.status, 200, res.text);
  EventsResultSchema.parse(res.body);
  assert.equal(res.body.mode, "mock");
  assert.equal(res.body.window.start, "2026-10-10T00:00:00+02:00");
  assert.equal(res.body.window.end, "2026-10-11T00:00:00+02:00");
  assert.deepEqual(
    res.body.events.map((e: { title: string; allDay: boolean; isRecurring: boolean }) => [e.title, e.allDay, e.isRecurring]),
    [
      ["Demo: Mum's birthday", true, false],
      ["Demo: Team stand-up", false, true],
      ["Demo: Dentist", false, false],
    ],
  );
  assert.equal(res.body.cancelledHidden, 1);
  assert.equal(res.body.receipt.status, "succeeded");
  assert.equal(res.body.receipt.providerReference, null, "mock never invents a provider reference");
  assert.ok(Date.parse(res.body.expiresAt) > Date.parse(res.body.retrievedAt));
});

test("tomorrow across a DST change is a 25-hour local day", async () => {
  h = await harness({ nowIso: "2026-10-24T12:00:00Z" });
  await connectMock(h);
  const res = await read(h);
  assert.equal(res.body.window.date, "2026-10-25");
  assert.equal(res.body.window.start, "2026-10-25T00:00:00+02:00");
  assert.equal(res.body.window.end, "2026-10-26T00:00:00+01:00");
});

test("the user's explicit time zone decides which day is tomorrow", async () => {
  h = await harness({ nowIso: "2026-10-09T23:30:00Z" });
  await connectMock(h);
  assert.equal((await read(h, undefined, "Europe/Warsaw")).body.window.date, "2026-10-11");
  assert.equal((await read(h, undefined, "America/Los_Angeles")).body.window.date, "2026-10-10");
});

test("an empty calendar is a valid, successful empty result", async () => {
  h = await harness();
  await connectMock(h, "dev-user-a", "empty");
  const res = await read(h);
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.events, []);
  assert.equal(res.body.receipt.status, "succeeded");
});

test("pagination is bounded and truncation is reported", async () => {
  h = await harness();
  await connectMock(h, "dev-user-a", "many");
  const res = await read(h);
  assert.equal(res.status, 200);
  assert.equal(listCalls(h), 3, "stops at maxPages");
  assert.equal(res.body.events.length, 100, "capped at maxEvents");
  assert.equal(res.body.truncated, true);
  assert.match(res.body.receipt.summary, /shortened/);
});

test("malformed provider data is an error with a failed receipt, never an empty list", async () => {
  h = await harness();
  await connectMock(h, "dev-user-a", "malformed");
  const res = await read(h);
  assert.equal(res.status, 502);
  assert.equal(res.body.error.code, "malformed_provider_result");
  assert.equal(res.body.error.receipt.status, "failed");
  assert.equal(res.body.events, undefined);
});

test("provider failure is an error, not an empty result", async () => {
  h = await harness();
  await connectMock(h, "dev-user-a", "provider_error");
  const res = await read(h);
  assert.equal(res.status, 502);
  assert.equal(res.body.error.code, "provider_unavailable");
});

test("timeouts retry with capped backoff, then fail; every try reserved allowance", async () => {
  h = await harness();
  await connectMock(h, "dev-user-a", "timeout");
  const res = await read(h);
  assert.equal(res.status, 504);
  assert.equal(listCalls(h), 3, "1 try + 2 retries");
  assert.deepEqual(h.sleeps, [250, 500]);
  const day = "day:2026-10-09";
  assert.equal(h.store.usage("service:calls", day), 3);
});

test("rate limits: a long Retry-After is passed to the client instead of a retry storm", async () => {
  h = await harness();
  await connectMock(h, "dev-user-a", "rate_limited");
  const res = await read(h);
  assert.equal(res.status, 429);
  assert.equal(res.body.error.retryAfterSeconds, 30);
  assert.equal(res.headers.get("retry-after"), "30");
  assert.equal(listCalls(h), 1);
  assert.deepEqual(h.sleeps, []);
});

test("daily per-user ceiling blocks reads before any provider call", async () => {
  h = await harness({ limits: { userDailyReads: 2 } });
  await connectMock(h);
  assert.equal((await read(h)).status, 200);
  assert.equal((await read(h)).status, 200);
  const third = await read(h);
  assert.equal(third.status, 429);
  assert.equal(third.body.error.code, "quota_exceeded");
  assert.equal(listCalls(h), 2);
  h.clock.advance(24 * 3600_000);
  assert.equal((await read(h)).status, 200, "a new UTC day resets the daily counter");
});

test("service-wide monthly ceiling is enforced across users", async () => {
  h = await harness({ limits: { serviceMonthlyCalls: 1 } });
  await connectMock(h);
  await connectMock(h, "dev-user-b");
  assert.equal((await read(h)).status, 200);
  const other = await h.call("POST", `${CAL}/events`, { token: "dev-user-b", body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
  assert.equal(other.body.error.code, "quota_exceeded");
});

test("expired or revoked access is reported and the connection state updated", async () => {
  h = await harness();
  await connectMock(h);
  (h.provider as MockCalendarProvider).setScenario(h.store.composioUserId("00000000-0000-4000-8000-00000000000a", 0), "expired");
  const res = await read(h);
  assert.equal(res.body.error.code, "connection_expired");
  assert.equal((await h.call("GET", CAL)).body.status, "expired");
  const again = await read(h);
  assert.equal(again.body.error.receipt.status, "blocked");
});

test("live adapter: pinned version, explicit account and user, primary calendar, minimal fields; real log ID kept", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const start = await h.call("POST", `${CAL}/connect`, { body: {} });
  const pending = [...fake.accounts.keys()][0]!;
  fake.activate(pending);
  await h.call("POST", `${CAL}/complete`, {
    body: { attemptId: start.body.attemptId, nonce: start.body.nonce, result: { kind: "callback", status: "success", connectedAccountId: pending } },
  });
  fake.execute = async () => ({
    successful: true,
    error: null,
    logId: "log_real_42",
    data: { summary: "owner@example.com", items: [{ summary: "Real", start: { dateTime: "2026-10-10T10:00:00+02:00" }, end: { dateTime: "2026-10-10T11:00:00+02:00" } }] },
  });
  const res = await read(h);
  assert.equal(res.status, 200, res.text);
  const call = fake.executeArgs[0]!;
  assert.equal(call.slug, "GOOGLECALENDAR_EVENTS_LIST");
  assert.equal(call.version, "20250909_00");
  assert.equal(call.connectedAccountId, pending);
  const args = call.arguments as Record<string, unknown>;
  assert.equal(args.calendarId, "primary");
  assert.equal(args.singleEvents, true);
  assert.equal(args.timeMin, "2026-10-10T00:00:00+02:00");
  assert.equal(args.timeMax, "2026-10-11T00:00:00+02:00");
  assert.ok(!String(args.fields).includes("description") && !String(args.fields).includes("attendees"));
  assert.equal(res.body.receipt.providerReference, "log_real_42");
  assert.equal(res.body.source.label, "o•••@e•••.com");
  assert.ok(!res.text.includes(PLANTED_TOKEN));
});

test("invalid live credentials surface as errors, never as demo or empty data", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  fake.connectedAccounts.link = async () => {
    throw Object.assign(new Error("Invalid API key"), { status: 401 });
  };
  const res = await h.call("POST", `${CAL}/connect`, { body: {} });
  assert.equal(res.status, 502);
  assert.equal(res.body.error.code, "provider_unavailable");
  assert.ok(!res.text.includes("Invalid API key"), "provider messages are not forwarded");
});
