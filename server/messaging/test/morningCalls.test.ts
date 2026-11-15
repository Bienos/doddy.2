import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { callApprovalHash, morningCallApprovalHash } from "../src/approval.js";
import { callOpening } from "../src/calls.js";
import { DEFAULT_ABUSE_LIMITS, loadConfig } from "../src/config.js";
import type { Db } from "../src/db.js";
import {
  isDays, isMorningTime, morningCallsBetween, morningPlan, nextMorningCallAt, NO_FACTS, prepareMorningCall,
} from "../src/morningCalls.js";
import { dispatchDue } from "../src/outbox.js";
import { placeDueCall } from "../src/scheduledCalls.js";
import { runCallPass } from "../src/workerLoop.js";
import {
  BASE_URL, CONNECT_TWIML, dbSkip, DODDY_NUMBER, FakeOutbound, FakePush, FakeRegistrar, freshDb, testApp, testCipher, twilioRequest,
} from "./helpers.js";

// Morning calls (decision 2026-11-14-morning-call). The schedule's arithmetic and the plan's words first, with no
// database; then the routes and the worker against real Postgres, with stand-ins for Twilio and ElevenLabs and a
// chosen clock for the worker.

const Z = (s: string) => new Date(s);

describe("morning call schedule and plan (no database)", () => {
  test("the next call is the chosen time on the zone's own clock, strictly after, on the chosen days", () => {
    // Saturday 14 Nov 2026, 07:00 in Warsaw (CET, UTC+1).
    const sat = Z("2026-11-14T06:00:00Z");
    assert.deepEqual(nextMorningCallAt(sat, "08:00", "1234567", "Europe/Warsaw"), Z("2026-11-14T07:00:00Z"), "today, an hour on");
    assert.deepEqual(nextMorningCallAt(Z("2026-11-14T07:00:00Z"), "08:00", "1234567", "Europe/Warsaw"), Z("2026-11-15T07:00:00Z"),
      "at 08:00 exactly the next one is tomorrow's");
    assert.deepEqual(nextMorningCallAt(sat, "08:00", "12345", "Europe/Warsaw"), Z("2026-11-16T07:00:00Z"), "weekdays: Monday");
    assert.deepEqual(nextMorningCallAt(sat, "08:00", "7", "Europe/Warsaw"), Z("2026-11-15T07:00:00Z"), "Sundays only");
    assert.deepEqual(nextMorningCallAt(Z("2026-11-16T07:00:00Z"), "08:00", "1", "Europe/Warsaw"), Z("2026-11-23T07:00:00Z"), "a week on");
    // Zones without summer time, and ones a day ahead of UTC.
    assert.deepEqual(nextMorningCallAt(sat, "08:00", "1234567", "Asia/Kolkata"), Z("2026-11-15T02:30:00Z"), "08:00 IST is 02:30 UTC; already past today");
    assert.deepEqual(nextMorningCallAt(Z("2026-11-14T10:00:00Z"), "07:15", "1234567", "Pacific/Auckland"), Z("2026-11-14T18:15:00Z"),
      "23:00 on Saturday in Auckland (NZDT, UTC+13): 07:15 on Sunday is 18:15 UTC on Saturday");
  });

  test("08:00 stays 08:00 across summer time: Warsaw in October and March, New York in November", () => {
    const warsaw = (from: string) => nextMorningCallAt(Z(from), "08:00", "1234567", "Europe/Warsaw").toISOString();
    assert.equal(warsaw("2026-10-23T07:00:00Z"), "2026-10-24T06:00:00.000Z", "Saturday 24 Oct, CEST (UTC+2)");
    assert.equal(warsaw("2026-10-24T06:00:00Z"), "2026-10-25T07:00:00.000Z", "Sunday 25 Oct, the clocks went back: CET (UTC+1)");
    assert.equal(warsaw("2027-03-27T07:00:00Z"), "2027-03-28T06:00:00.000Z", "Sunday 28 Mar 2027, the clocks went forward");
    const ny = (from: string) => nextMorningCallAt(Z(from), "08:00", "1234567", "America/New_York").toISOString();
    assert.equal(ny("2026-10-31T00:00:00Z"), "2026-10-31T12:00:00.000Z", "EDT");
    assert.equal(ny("2026-10-31T12:00:00Z"), "2026-11-01T13:00:00.000Z", "EST from 1 Nov");
    // Every call in a span, as the one-off booking counts them.
    assert.deepEqual(morningCallsBetween(Z("2026-10-24T00:00:00Z"), Z("2026-10-27T00:00:00Z"), "08:00", "1234567", "Europe/Warsaw")
      .map((d) => d.toISOString()), ["2026-10-24T06:00:00.000Z", "2026-10-25T07:00:00.000Z", "2026-10-26T07:00:00.000Z"]);
  });

  test("a morning is 05:00 to 11:59, and days are ISO weekdays in order", () => {
    for (const t of ["05:00", "08:00", "11:59"]) assert.ok(isMorningTime(t), t);
    for (const t of ["04:59", "12:00", "8:00", "08:0", "24:00", "", "08:00:00"]) assert.ok(!isMorningTime(t), t);
    for (const d of ["1234567", "12345", "67", "1"]) assert.ok(isDays(d), d);
    for (const d of ["", "21", "11", "8", "0123", "mon"]) assert.ok(!isDays(d), d);
  });

  test("the plan says the day, only what the server holds, and that the calendar is on the iPhone", () => {
    const day = Z("2026-11-16T07:00:00Z"); // Monday 08:00 in Warsaw
    assert.equal(morningPlan(NO_FACTS, day, "Europe/Warsaw", "pl"),
      "Dziś poniedziałek, 16 listopada. Poza tym nic od Ciebie u mnie dziś nie czeka. "
      + "Twojego kalendarza i przypomnień nie widzę, są tylko na iPhonie. Chcesz coś dodać albo o coś zapytać?");
    assert.equal(morningPlan(NO_FACTS, day, "Europe/Warsaw", "en"),
      "Today is Monday 16 November. Nothing else is waiting for you with me today. "
      + "I can't see your calendar or reminders: they are only on your iPhone. Anything you'd like to add or ask?");
    const facts = { laterCalls: ["12:00", "15:30", "18:00"], notesWaiting: 2, errandsReady: 1, radarNew: 5, newsAt: "08:30" };
    const pl = morningPlan(facts, day, "Europe/Warsaw", "pl");
    assert.match(pl, /Zadzwonię do Ciebie dziś jeszcze o 12:00, 15:30 i 18:00\./);
    assert.match(pl, /W aplikacji czekają 2 notatki do potwierdzenia\./);
    assert.match(pl, /W aplikacji czeka gotowy wynik zadania/);
    assert.match(pl, /Na radarze jest 5 nowych artykułów\./);
    assert.match(pl, /Wiadomości dnia przyślę o 08:30\./);
    assert.doesNotMatch(pl, /Poza tym nic/, "said only when there is nothing");
    // Polish counts: 1, 2-4 (not 12-14), the rest.
    const notes = (n: number) => morningPlan({ ...NO_FACTS, notesWaiting: n }, day, "Europe/Warsaw", "pl");
    assert.match(notes(1), /czeka 1 notatka do/);
    assert.match(notes(3), /czekają 3 notatki do/);
    assert.match(notes(5), /czeka 5 notatek do/);
    assert.match(notes(12), /czeka 12 notatek do/);
    assert.match(notes(22), /czekają 22 notatki do/);
    const en = morningPlan(facts, day, "Europe/Warsaw", "en");
    assert.match(en, /I'll call you again today at 12:00, 15:30 and 18:00\. 2 notes wait in the app/);
    // One line with no braces: it is handed to the phone agent as a variable inside its instructions.
    for (const plan of [pl, en]) assert.doesNotMatch(plan, /[\r\n{}]/);
    // The opening is the server's own sentence and says Doddy is an AI (DOD-03).
    assert.equal(callOpening(pl, "pl", "morning"), `Dzień dobry, tu Doddy, asystent AI, z Twoim planem dnia. ${pl}`);
    assert.equal(callOpening(en, "en", "morning"), `Good morning, this is Doddy, an AI assistant, with your plan for the day. ${en}`);
    assert.equal(callOpening("Cake", "en"), "Hi, this is Doddy, an AI assistant. You asked me to call you about this: Cake", "a call booked once is unchanged");
  });

  test("the switch is off by default, and the server cap may not be above the server's daily calls", () => {
    const db = { DATABASE_URL: "postgres://x/y" };
    assert.deepEqual(loadConfig(db).morningCalls, { enabled: false, maxPerServer: 10 });
    assert.deepEqual(loadConfig({ ...db, MORNING_CALLS_ENABLED: "1", MORNING_CALLS_MAX_PER_SERVER: "5" }).morningCalls, { enabled: true, maxPerServer: 5 });
    assert.throws(() => loadConfig({ ...db, MORNING_CALLS_MAX_PER_SERVER: "21" }), /MORNING_CALLS_MAX_PER_SERVER must not be above/);
    assert.doesNotThrow(() => loadConfig({ ...db, MORNING_CALLS_MAX_PER_SERVER: "30", OUTBOUND_CALLS_DAILY_PER_SERVER: "40" }));
    // Left at its default under a lower daily cap, it follows the cap instead of stopping the server.
    assert.equal(loadConfig({ ...db, OUTBOUND_CALLS_DAILY_PER_SERVER: "4" }).morningCalls.maxPerServer, 4);
  });
});

describe("morning calls against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let push: FakePush;
  let outbound: FakeOutbound;
  let registrar: FakeRegistrar;

  before(async () => {
    db = await freshDb();
    ({ app, push, outbound, registrar } = await testApp(db, { morningCalls: { enabled: true } }));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });
  // The worker takes the earliest due call of any account, and the server cap counts every account's morning calls,
  // so each test starts with none waiting and none active.
  beforeEach(async () => {
    await db.query(`UPDATE morning_calls SET state = 'stopped', stop_code = 'test_reset', stopped_at = now(), next_call_at = NULL
      WHERE state = 'active'`);
    await db.query(`UPDATE scheduled_calls SET state = 'cancelled', error_code = 'test_reset', reason_ciphertext = NULL,
      reason_key_version = NULL WHERE state = 'scheduled'`);
  });

  const call = (method: "GET" | "POST" | "PUT" | "DELETE", url: string, headers: object, payload?: object, on = app) =>
    on.inject({ method, url, headers: headers as Record<string, string>, payload });
  const scheduledCalls = {
    outbound: undefined as unknown as FakeOutbound, doddyPhoneNumber: DODDY_NUMBER, publicBaseUrl: BASE_URL,
    limits: { allowedCountryCodes: DEFAULT_ABUSE_LIMITS.allowedCountryCodes, outboundCallsPerServerDay: 1000 },
  };
  /** One pass of the worker's call loop at `now`, the switch on unless said otherwise. */
  const pass = (now: Date, enabled = true) =>
    runCallPass(db, { cipher: testCipher, morningCalls: { enabled }, scheduledCalls: { ...scheduledCalls, outbound } }, () => now);
  const later = (d: Date, s: number) => new Date(d.getTime() + s * 1000);

  let accounts = 0;
  async function owner(phone: string, opts: { consent?: boolean; push?: boolean } = {}) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.6.0.${++accounts}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    assert.equal((await call("POST", "/v1/phone/verification/check", h, { phone, code: "123456" })).statusCode, 200);
    if (opts.consent !== false) {
      assert.equal((await call("PUT", "/v1/calls/settings", h, { outboundConsent: true, outboundConsentTextVersion: "calls-v1" })).statusCode, 204);
    }
    if (opts.push) {
      assert.equal((await call("PUT", "/v1/device/push-token", h, { token: randomBytes(32).toString("hex"), environment: "sandbox" })).statusCode, 204);
    }
    return { accountId, h, phone };
  }

  interface Booking {
    time?: string; days?: string; zone?: string; allowQuietHours?: boolean; language?: "en" | "pl"; key?: string;
    replaces?: string | null; hashFor?: Partial<{ phone: string; time: string; days: string; zone: string; allowQuietHours: boolean; language: string }>;
  }
  /** Books the way the app does: the hash covers the number, time, days, zone, quiet-hours choice and language the card showed. */
  function book(o: { h: object; phone: string }, b: Booking = {}, on = app) {
    const time = b.time ?? "09:00";
    const days = b.days ?? "1234567";
    const zone = b.zone ?? "Europe/Warsaw";
    const allowQuietHours = b.allowQuietHours ?? false;
    const language = b.language ?? "pl";
    const f = { phone: o.phone, time, days, zone, allowQuietHours, language, ...b.hashFor };
    return call("POST", "/v1/calls/morning", o.h, {
      time, days, timeZone: zone, allowQuietHours, language, replaces: b.replaces ?? null, idempotencyKey: b.key ?? randomUUID(),
      approvalHash: morningCallApprovalHash(f.phone, f.time, f.days, f.zone, f.allowQuietHours, f.language).toString("hex"),
    }, on);
  }
  const booked = async (o: { h: object; phone: string }, b: Booking = {}) => {
    const r = await book(o, b);
    assert.equal(r.statusCode, 202, r.body);
    const body = r.json() as { id: string; nextCallAt: string };
    return { id: body.id, next: new Date(body.nextCallAt) };
  };
  const schedule = async (id: string) => (await db.query<{ state: string; stop_code: string | null; next_call_at: Date | null }>(
    "SELECT state, stop_code, next_call_at FROM morning_calls WHERE id = $1", [id])).rows[0]!;
  const days = async (id: string) => (await db.query<{ id: string; state: string; error_code: string | null; reason: boolean; call_id: string | null; call_at: Date }>(
    `SELECT id, state, error_code, reason_ciphertext IS NOT NULL AS reason, call_id, call_at FROM scheduled_calls
     WHERE morning_call_id = $1 ORDER BY call_at`, [id])).rows;

  test("booked only as the card showed it: number, time, days, zone, quiet-hours choice and language", async () => {
    const o = await owner("+48500300001");
    for (const [field, change] of [
      ["number", { phone: "+48500300999" }], ["time", { time: "09:30" }], ["days", { days: "12345" }], ["zone", { zone: "Europe/Berlin" }],
      ["quiet-hours switch", { allowQuietHours: true }], ["language", { language: "en" }],
    ] as const) {
      const r = await book(o, { hashFor: change });
      assert.deepEqual([r.statusCode, r.json().error], [409, "approval_mismatch"], `${field} changed after the card`);
    }
    // Only a morning, only real weekdays, only a zone the server knows.
    for (const bad of [{ time: "12:00" }, { time: "04:59" }, { days: "21" }, { days: "" }, { days: "8" }, { zone: "Mars/Base" }]) {
      assert.equal((await book(o, bad)).statusCode, 400, JSON.stringify(bad));
    }
    // Inside quiet hours (21:00-08:00) only with the switch on.
    assert.equal((await book(o, { time: "06:30" })).json().error, "quiet_hours");
    const early = await booked(o, { time: "06:30", allowQuietHours: true });

    // One per account: a new one only replaces the one its card said it replaces.
    const key = randomUUID();
    const other = await book(o, { time: "08:15", key });
    assert.deepEqual([other.statusCode, other.json().error, other.json().call.id], [409, "already_active", early.id]);
    const replacing = randomUUID();
    const replaced = await book(o, { time: "08:15", key: replacing, replaces: early.id });
    assert.equal(replaced.statusCode, 202);
    assert.deepEqual([(await schedule(early.id)).state, (await schedule(early.id)).stop_code], ["stopped", "replaced"]);
    const active = await db.query("SELECT 1 FROM morning_calls WHERE account_id = $1 AND state = 'active'", [o.accountId]);
    assert.equal(active.rowCount, 1);
    // The same tap again is the same booking; the same key with another approval is refused; the same approval on another card isn't a second one.
    const first = replaced.json() as { id: string };
    const again = await book(o, { time: "08:15", key: replacing, replaces: early.id });
    assert.deepEqual([again.statusCode, again.json().id], [202, first.id]);
    assert.equal((await book(o, { time: "08:20", key: replacing, replaces: first.id })).json().error, "idempotency_mismatch");
    assert.equal((await book(o, { time: "08:15", replaces: first.id })).json().error, "already_booked");
    // The replaced one's own tap, sent again, doesn't say booked.
    const old = await db.query<{ idempotency_key: string }>("SELECT idempotency_key FROM morning_calls WHERE id = $1", [early.id]);
    const repeat = await book(o, { time: "06:30", allowQuietHours: true, key: old.rows[0]!.idempotency_key });
    assert.deepEqual([repeat.statusCode, repeat.json().error, repeat.json().state], [409, "already_done", "stopped"]);
    // GET shows the active one.
    const got = (await call("GET", "/v1/calls/morning", o.h)).json() as { enabled: boolean; available: boolean; call: { id: string; time: string; days: string } };
    assert.deepEqual([got.enabled, got.available, got.call.id, got.call.time, got.call.days], [true, true, first.id, "08:15", "1234567"]);

    // Without consent nothing is booked.
    const p = await owner("+48500300002", { consent: false });
    assert.equal((await book(p)).json().error, "outbound_not_enabled");
  });

  test("the switch off: nothing stored, no call made, and stopping still works", async () => {
    const { app: off } = await testApp(db, { morningCalls: { enabled: false } });
    try {
      const o = await owner("+48500300010");
      const r = await book(o, {}, off);
      assert.deepEqual([r.statusCode, r.json().error], [503, "morning_calls_off"]);
      assert.equal((await db.query("SELECT 1 FROM morning_calls WHERE account_id = $1", [o.accountId])).rowCount, 0, "nothing stored");
      assert.deepEqual((await call("GET", "/v1/calls/morning", o.h, undefined, off)).json(), { enabled: false, available: false, call: null, recent: [] });
      // One booked while the switch was on: with it off the worker makes no call, and the person can still stop it.
      const { id, next } = await booked(o);
      const before = outbound.calls.length;
      assert.equal(await pass(later(next, 10), false), false);
      assert.equal((await days(id)).length, 0, "no day's call made");
      assert.equal(outbound.calls.length, before);
      assert.deepEqual((await call("DELETE", "/v1/calls/morning", o.h, undefined, off)).json(), { stopped: true, calling: false });
    } finally {
      await off.close();
    }
  });

  test("each day the worker makes a normal scheduled call, says the plan first, and moves on to the next day", async () => {
    const o = await owner("+48500300020");
    const { id, next } = await booked(o);
    // What the server holds for that day: a call booked for later (its reason is never said), and two notes waiting.
    const noon = new Date(next.getTime() + 3 * 3600_000);
    const reason = "Odbierz paczkę z paczkomatu";
    const oneOff = await call("POST", "/v1/calls/scheduled", o.h, {
      at: noon.toISOString().replace(/\.\d{3}Z$/, "Z"), reason, timeZone: "Europe/Warsaw", allowQuietHours: false, language: "pl",
      approvalHash: callApprovalHash(o.phone, noon.toISOString().replace(/\.\d{3}Z$/, "Z"), reason, false).toString("hex"), idempotencyKey: randomUUID(),
    });
    assert.equal(oneOff.statusCode, 202, oneOff.body);
    await db.query(
      `INSERT INTO call_notes (id, account_id, key_version, ciphertext) SELECT gen_random_uuid(), $1, 1, '\\x00' FROM generate_series(1, 2)`,
      [o.accountId]);

    assert.equal(await pass(later(next, -60)), false, "not due yet");
    assert.equal((await days(id)).length, 0);
    const before = outbound.calls.length;
    assert.equal(await pass(later(next, 10)), true);
    const [today] = await days(id);
    assert.ok(today);
    assert.deepEqual([today.state, today.call_at.toISOString()], ["placed", next.toISOString()]);
    assert.equal(outbound.calls.length, before + 1);
    assert.deepEqual(outbound.calls.at(-1), {
      to: o.phone, from: DODDY_NUMBER, answerUrl: `${BASE_URL}/webhooks/twilio/voice/outbound/${today.call_id}`,
      statusCallbackUrl: `${BASE_URL}/webhooks/twilio/call-status`,
    });
    assert.deepEqual((await schedule(id)).next_call_at, nextMorningCallAt(next, "09:00", "1234567", "Europe/Warsaw"), "tomorrow at 09:00");
    assert.equal(await pass(later(next, 20)), false, "once a day");
    assert.equal(outbound.calls.length, before + 1);

    // Answered: Doddy says the plan the server wrote, in Polish, and says it is an AI.
    const callSid = `CAout${outbound.calls.length}`;
    const answered = await app.inject(twilioRequest(`/webhooks/twilio/voice/outbound/${today.call_id}`, { CallSid: callSid, CallStatus: "in-progress" }));
    assert.equal(answered.body, CONNECT_TWIML);
    const v = registrar.calls.at(-1)!.variables;
    const [opening, plan] = [v.doddy_call_opening ?? "", v.doddy_call_reason ?? ""];
    assert.match(opening, /^Dzień dobry, tu Doddy, asystent AI, z Twoim planem dnia\. Dziś /);
    assert.equal(opening, `Dzień dobry, tu Doddy, asystent AI, z Twoim planem dnia. ${plan}`);
    assert.match(plan, /Zadzwonię do Ciebie dziś jeszcze o 12:00\./);
    assert.match(plan, /W aplikacji czekają 2 notatki do potwierdzenia\./);
    assert.match(plan, /Twojego kalendarza i przypomnień nie widzę/);
    assert.doesNotMatch(plan, /paczk/, "another call's reason is never said");
    await app.inject(twilioRequest("/webhooks/twilio/call-status", { CallSid: callSid, CallStatus: "completed" }));
    assert.equal((await days(id))[0]!.reason, false, "the day's plan is erased once the call is over");
    // The booked-calls list shows the call booked once, not the morning call's day.
    const list = (await call("GET", "/v1/calls/scheduled", o.h)).json().calls as { id: string }[];
    assert.deepEqual(list.map((c) => c.id), [oneOff.json().id]);
    assert.equal((await call("DELETE", `/v1/calls/scheduled/${oneOff.json().id}`, o.h)).statusCode, 204);

    // The next day: the same again, and it counts toward the day's calls like any other.
    const next2 = (await schedule(id)).next_call_at!;
    assert.equal(await pass(later(next2, 5)), true);
    assert.deepEqual((await days(id)).map((d) => d.state), ["placed", "placed"]);
    const got = (await call("GET", "/v1/calls/morning", o.h)).json() as { recent: { state: string }[] };
    assert.deepEqual(got.recent.map((d) => d.state), ["placed", "placed"]);
    const counted = await db.query("SELECT count(*)::int AS n FROM calls WHERE account_id = $1 AND direction = 'outbound'", [o.accountId]);
    assert.equal(counted.rows[0].n, 2);
  });

  test("stop works at once: by request, before the call, and when it landed while the call was being prepared", async () => {
    const o = await owner("+48500300030");
    const before = outbound.calls.length;
    const a = await booked(o);
    assert.deepEqual((await call("DELETE", "/v1/calls/morning", o.h)).json(), { stopped: true, calling: false });
    assert.equal((await call("GET", "/v1/calls/morning", o.h)).json().call, null);
    assert.equal(await pass(later(a.next, 10)), false);
    assert.equal((await days(a.id)).length, 0);
    assert.deepEqual((await call("DELETE", "/v1/calls/morning", o.h)).json(), { stopped: false, calling: false }, "nothing left to stop");

    // The day's call made but not placed yet: the stop cancels it and erases its plan.
    const b = await booked(o);
    assert.equal(await prepareMorningCall({ db, cipher: testCipher, now: () => later(b.next, 10) }), true);
    assert.equal((await days(b.id))[0]!.state, "scheduled");
    assert.deepEqual((await call("DELETE", "/v1/calls/morning", o.h)).json(), { stopped: true, calling: false });
    assert.deepEqual((await days(b.id)).map((d) => [d.state, d.error_code, d.reason]), [["cancelled", "cancelled_by_user", false]]);
    assert.equal(await placeDueCall({ db, cipher: testCipher, ...scheduledCalls, outbound, now: () => later(b.next, 11) }), false);

    // Stopped after the worker made the day's call (here, straight in the database): the worker checks the schedule
    // again before it calls, and tells nobody, because the person stopped it.
    const c = await booked(o, { language: "en" });
    assert.equal(await prepareMorningCall({ db, cipher: testCipher, now: () => later(c.next, 10) }), true);
    await db.query("UPDATE morning_calls SET state = 'stopped', stop_code = 'stopped_by_user', stopped_at = now(), next_call_at = NULL WHERE id = $1", [c.id]);
    const notices = push.sent.length;
    assert.equal(await pass(later(c.next, 11)), true);
    assert.deepEqual((await days(c.id)).map((d) => [d.state, d.error_code, d.reason]), [["cancelled", "morning_calls_stopped", false]]);
    assert.equal(outbound.calls.length, before, "nothing rang");
    assert.equal(push.sent.length, notices);

    // A stop that lands while the worker is between its checks and the call: the worker waits on the lock the stop
    // holds, then reads the schedule again under it and calls nobody.
    const d = await booked(o);
    assert.equal(await prepareMorningCall({ db, cipher: testCipher, now: () => later(d.next, 10) }), true);
    const stopper = await db.connect();
    try {
      await stopper.query("BEGIN");
      await stopper.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [o.accountId]);
      const placing = placeDueCall({ db, cipher: testCipher, ...scheduledCalls, outbound, now: () => later(d.next, 11) });
      // Wait (up to 10 s) until the worker is past its first check and waiting on the lock the stop holds.
      for (let i = 0; i < 200; i++) {
        const { rows: [w] } = await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM pg_locks WHERE locktype = 'advisory' AND NOT granted
           AND database = (SELECT oid FROM pg_database WHERE datname = current_database())`);
        if (w!.n > 0) break;
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      assert.deepEqual((await days(d.id)).map((x) => x.state), ["placing"], "past the first check, waiting on the lock");
      await stopper.query(
        `UPDATE morning_calls SET state = 'stopped', stop_code = 'stopped_by_user', stopped_at = now(), next_call_at = NULL
         WHERE id = $1`, [d.id]);
      await stopper.query("COMMIT");
      assert.equal(await placing, true);
    } finally {
      stopper.release();
    }
    assert.deepEqual((await days(d.id)).map((x) => [x.state, x.error_code, x.call_id]), [["cancelled", "morning_calls_stopped", null]]);
    assert.equal(outbound.calls.length, before, "nothing rang after the stop");
  });

  test("at call time: quiet hours where the person is now, the caps, an unknown outcome, a late worker", async () => {
    const o = await owner("+48500300040", { push: true });
    const deliver = () => dispatchDue(db, { push, cipher: testCipher });
    const { id, next } = await booked(o, { language: "en" });

    // The person flew to Honolulu: 09:00 in Warsaw is night there, so no call, a notice, and tomorrow's stays.
    assert.equal((await call("PUT", "/v1/calls/settings", o.h, { timeZone: "Pacific/Honolulu" })).statusCode, 204);
    const before = outbound.calls.length;
    assert.equal(await pass(later(next, 10)), true);
    assert.deepEqual((await days(id)).map((d) => [d.state, d.error_code]), [["skipped_quiet_hours", "quiet_hours"]]);
    await deliver();
    assert.match(push.sent.at(-1)!.body, /^Doddy didn't make your morning call at \d\d:\d\d: it was quiet hours .* Your morning calls go on as set\.$/);
    assert.equal((await schedule(id)).state, "active");
    assert.equal((await call("PUT", "/v1/calls/settings", o.h, { timeZone: "Europe/Warsaw" })).statusCode, 204);

    // Ten calls already in the day before: the day's call isn't placed, the person is told, the schedule goes on.
    const next2 = (await schedule(id)).next_call_at!;
    await db.query(
      `INSERT INTO calls (id, account_id, direction, status, created_at)
       SELECT gen_random_uuid(), $1, 'outbound', 'completed', $2::timestamptz - interval '3 hours' FROM generate_series(1, 10)`,
      [o.accountId, next2]);
    assert.equal(await pass(later(next2, 10)), true);
    assert.equal((await days(id)).at(-1)!.state, "limit");
    await deliver();
    assert.match(push.sent.at(-1)!.body, /as many times as it may in an hour or a day/);
    assert.equal(outbound.calls.length, before);
    await db.query("DELETE FROM calls WHERE account_id = $1", [o.accountId]);

    // Twilio's answer never came: unknown, never placed again; the next day is a new call.
    const next3 = (await schedule(id)).next_call_at!;
    outbound.next = [{ kind: "unknown", code: "twilio_network" }];
    assert.equal(await pass(later(next3, 10)), true);
    assert.deepEqual([(await days(id)).at(-1)!.state, (await days(id)).at(-1)!.reason], ["unknown", false]);
    assert.equal(await pass(later(next3, 70)), false);
    assert.equal(outbound.calls.length, before + 1, "asked Twilio once");
    const next4 = (await schedule(id)).next_call_at!;
    assert.equal(await pass(later(next4, 10)), true);
    assert.equal((await days(id)).at(-1)!.state, "placed");

    // The worker was down for three days: one missed call and one notice, then the schedule goes on from the next day.
    const next5 = (await schedule(id)).next_call_at!;
    const back = later(next5, 3 * 86_400 + 600);
    const count = (await days(id)).length;
    assert.equal(await pass(back), true);
    assert.equal(await pass(back), false);
    const now = await days(id);
    assert.equal(now.length, count + 1, "one day's call, not three");
    assert.deepEqual([now.at(-1)!.state, now.at(-1)!.error_code], ["missed", "server_late"]);
    assert.ok((await schedule(id)).next_call_at! > back);
    await deliver();
    assert.match(push.sent.at(-1)!.body, /^Doddy couldn't make your morning call at/);
  });

  test("a changed number or consent stops the morning call; a number swapped behind the API's back is refused at call time", async () => {
    const o = await owner("+48500300050", { push: true });
    const a = await booked(o);
    assert.equal((await call("PUT", "/v1/calls/settings", o.h, { outboundConsent: false })).statusCode, 204);
    assert.deepEqual([(await schedule(a.id)).state, (await schedule(a.id)).stop_code], ["stopped", "consent_off"]);
    assert.equal((await call("PUT", "/v1/calls/settings", o.h, { outboundConsent: true, outboundConsentTextVersion: "calls-v1" })).statusCode, 204);
    assert.equal((await schedule(a.id)).state, "stopped", "consent back on doesn't bring it back: it needs a new card");

    const b = await booked(o);
    assert.equal((await call("POST", "/v1/phone/verification/check", o.h, { phone: "+48500300051", code: "123456" })).statusCode, 200);
    assert.deepEqual([(await schedule(b.id)).state, (await schedule(b.id)).stop_code], ["stopped", "number_changed"]);

    // Not through the API: only the approval stands between this and a call to another number.
    const p = { ...o, phone: "+48500300051" };
    const c = await booked(p);
    await db.query("UPDATE phone_numbers SET e164 = '+48500300059' WHERE account_id = $1", [o.accountId]);
    const before = outbound.calls.length;
    assert.equal(await pass(later(c.next, 10)), true);
    assert.deepEqual((await days(c.id)).map((d) => [d.state, d.error_code]), [["cancelled", "number_changed"]]);
    assert.deepEqual([(await schedule(c.id)).state, (await schedule(c.id)).stop_code], ["stopped", "number_changed"]);
    assert.equal(outbound.calls.length, before);
    await dispatchDue(db, { push, cipher: testCipher });
    assert.equal(push.sent.at(-1)!.body, "Doddy przestał dzwonić rano: zmienił się Twój numer albo zgoda na rozmowy. Poproś ponownie, żeby to ustawić.");
  });

  test("the server's cap on morning calls, and a call booked once counts the morning call in its hour", async () => {
    const { app: capped } = await testApp(db, { morningCalls: { enabled: true, maxPerServer: 1 } });
    try {
      const a = await owner("+48500300060");
      const b = await owner("+48500300061");
      const first = await book(a, {}, capped);
      assert.equal(first.statusCode, 202);
      const full = await book(b, {}, capped);
      assert.deepEqual([full.statusCode, full.json().error], [429, "server_limit"]);
      // The account's own, replaced, doesn't count against it.
      assert.equal((await book(a, { time: "09:30", replaces: first.json().id }, capped)).statusCode, 202);
    } finally {
      await capped.close();
    }

    // At most 3 calls in an hour: the morning call and two booked once fill the hour after 09:00.
    const o = await owner("+48500300062");
    const { next } = await booked(o);
    const once = (m: number, r: string) => {
      const at = new Date(next.getTime() + m * 60_000).toISOString().replace(/\.\d{3}Z$/, "Z");
      return call("POST", "/v1/calls/scheduled", o.h, {
        at, reason: r, timeZone: "Europe/Warsaw", allowQuietHours: false, language: "pl", idempotencyKey: randomUUID(),
        approvalHash: callApprovalHash(o.phone, at, r, false).toString("hex"),
      });
    };
    assert.equal((await once(5, "a")).statusCode, 202);
    assert.equal((await once(10, "b")).statusCode, 202);
    assert.equal((await once(15, "c")).json().error, "hourly_limit");
  });

  test("08:00 in Warsaw is 06:00 UTC before the clocks go back and 07:00 after, as the worker moves the schedule", async () => {
    const o = await owner("+48500300070");
    const { id } = await booked(o, { time: "08:00" });
    await db.query("UPDATE morning_calls SET next_call_at = '2026-10-24T06:00:00Z' WHERE id = $1", [id]);
    assert.equal(await prepareMorningCall({ db, cipher: testCipher, now: () => Z("2026-10-24T06:00:05Z") }), true);
    assert.equal((await schedule(id)).next_call_at!.toISOString(), "2026-10-25T07:00:00.000Z");
    assert.equal(await prepareMorningCall({ db, cipher: testCipher, now: () => Z("2026-10-25T07:00:05Z") }), true);
    assert.equal((await schedule(id)).next_call_at!.toISOString(), "2026-10-26T07:00:00.000Z");
    assert.deepEqual((await days(id)).map((d) => d.call_at.toISOString()), ["2026-10-24T06:00:00.000Z", "2026-10-25T07:00:00.000Z"]);
    // Two workers at once make one day's call: the second finds the schedule already moved on.
    await db.query("UPDATE morning_calls SET next_call_at = '2026-10-26T07:00:00Z' WHERE id = $1", [id]);
    await Promise.all([1, 2].map(() => prepareMorningCall({ db, cipher: testCipher, now: () => Z("2026-10-26T07:00:05Z") })));
    assert.equal((await days(id)).length, 3);
    assert.equal((await schedule(id)).next_call_at!.toISOString(), "2026-10-27T07:00:00.000Z");
  });

  test("the history export lists the morning call's schedule, never a day's plan", async () => {
    const o = await owner("+48500300080");
    const { id } = await booked(o);
    const h = (await call("GET", "/v1/phone/history", o.h)).json() as { morningCalls: { id: string; time: string; days: string; state: string }[] };
    assert.deepEqual(h.morningCalls.map((m) => [m.id, m.time, m.days, m.state]), [[id, "09:00", "1234567", "active"]]);
  });
});
