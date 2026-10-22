import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES } from "../src/auth.js";
import { DaySummarySchema, LOGBOOK_TOOL_IDS, LogbookViewSchema, oldestKeptDay } from "../src/web/logbook.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * Logbook, the server's half (ADR-593): the iPhone sends one counts-only summary per day, the
 * person reads them in Doddy Web. Off until the iPhone turns it on; nothing but numbers can be
 * stored; the browser reads, downloads and deletes but never writes.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const DAY = 86_400_000;
/** The store is keyed by the person, not by the dev token that stands for them. */
const ID_A = DEV_IDENTITIES[USER_A]!;
const ID_B = DEV_IDENTITIES[USER_B]!;
const SINCE_ALWAYS = "0000-00-00";
const TODAY = "2026-10-22"; // the rig's clock is 2026-10-22T10:00:00Z

/** A valid day: 3 conversations, 2 notes' worth of tools, every sum adding up. */
function day(date: string, extra: Record<string, unknown> = {}) {
  return {
    schema: "doddy.logbook.day.v1",
    day: date,
    conversations: {
      count: 3,
      seconds: 540,
      by_hour: Array.from({ length: 24 }, (_, h) => (h === 8 ? 1 : h === 13 ? 1 : h === 20 ? 1 : 0)),
      lengths: { under_1: 1, "1_3": 1, "3_5": 1, "5_10": 0 },
      ended: { you: 2, doddy: 1, quiet: 0, dropped: 0 },
      languages: { en: 2, pl: 1 },
      ways_in: { app: 1, back_tap: 1, action_button: 0, widget: 0, siri: 0, island: 1 },
    },
    tools: { save_memory: { done: 2 }, read_calendar: { done: 1, failed: 1 }, send_email: { done: 0, declined: 1, unsure: 1 } },
    notes: { by_source: { voice: 2, typed: 0, shared: 0, imported: 0 }, by_kind: { fact: 1, commitment: 1 }, edited: 0 },
    lists: { added_voice: 2, added_typed: 0, ticked: 1 },
    errands: { handed_over: 1, finished: 1, stopped: 0, minutes: 4, searches: 6, pages: 3 },
    translator: { sessions: 1, minutes: 5 },
    ...extra,
  };
}

const iso = (offsetDays: number) => new Date(Date.parse(`${TODAY}T00:00:00Z`) + offsetDays * DAY).toISOString().slice(0, 10);
const put = (r: WebRig, date: string, body: unknown, token = USER_A) => r.call("PUT", `/v1/web/logbook/days/${date}`, { token, body });
const turnOn = async (r: WebRig, token = USER_A) => {
  const res = await r.call("PUT", "/v1/web/logbook/state", { token, body: { enabled: true } });
  assert.equal(res.status, 200, res.text);
};

// ------------------------------------------------------------------ the contract

test("the counted tool ids are exactly the voice agent's tools", () => {
  const spec = JSON.parse(readFileSync(join(process.cwd(), "..", "voice-agent", "tools.json"), "utf8")) as { tools: { name: string }[] };
  assert.deepEqual([...LOGBOOK_TOOL_IDS].sort(), spec.tools.map((tool) => tool.name).sort());
});

// ------------------------------------------------------------------ off by default

test("Logbook starts off: the page reads an empty, switched-off view, and a day sent now is refused and not stored", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());

  const view = await rig.call("GET", "/v1/web/logbook", { cookie });
  assert.equal(view.status, 200, view.text);
  assert.deepEqual(LogbookViewSchema.parse(view.body), { enabled: false, keptDays: 90, updatedAt: null, days: [] });

  const refused = await put(rig, TODAY, day(TODAY));
  assert.equal(refused.status, 403, refused.text);
  assert.equal(refused.body.error.code, "capability_disabled");
  assert.match(refused.body.error.message, /Logbook is off/);
  assert.deepEqual(await rig.store.logbookDays(ID_A, SINCE_ALWAYS), [], "nothing was stored");
});

test("turning Logbook on is the iPhone's choice alone: a browser can't turn it on, off or write a day", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  const state = await rig.call("PUT", "/v1/web/logbook/state", { cookie, browser: true, body: { enabled: true } });
  assert.equal(state.status, 401, "the state is the phone's");
  await turnOn(rig);
  const written = await rig.call("PUT", `/v1/web/logbook/days/${TODAY}`, { cookie, browser: true, body: day(TODAY) });
  assert.equal(written.status, 401, "a day is the phone's");
  assert.deepEqual(await rig.store.logbookDays(ID_A, SINCE_ALWAYS), []);
  // And no session at all is refused too.
  assert.equal((await rig.call("PUT", "/v1/web/logbook/state", { body: { enabled: true } })).status, 401);
  assert.equal((await rig.call("GET", "/v1/web/logbook")).status, 401);
});

test("the state takes one boolean and nothing else", async () => {
  rig = await startWeb();
  for (const body of [{}, { enabled: "yes" }, { enabled: true, extra: 1 }, [], "on"]) {
    const res = await rig.call("PUT", "/v1/web/logbook/state", { token: USER_A, body });
    assert.equal(res.status, 400, JSON.stringify(body));
  }
  assert.equal(await rig.store.logbookEnabled(ID_A), false);
});

// ------------------------------------------------------------------ sending and reading

test("a day the iPhone sends is what the page reads, oldest first, and a second send of the same day replaces it", async () => {
  rig = await startWeb();
  await turnOn(rig);
  const cookie = await rig.signIn(await rig.code());

  assert.equal((await put(rig, iso(0), day(iso(0)))).body.stored, true);
  assert.deepEqual((await put(rig, iso(-2), day(iso(-2)))).body, { stored: true, day: iso(-2) });
  const first = await rig.call("GET", "/v1/web/logbook", { cookie });
  const view = LogbookViewSchema.parse(first.body);
  assert.equal(view.enabled, true);
  assert.deepEqual(view.days.map((d) => d.day), [iso(-2), iso(0)]);
  assert.equal(view.updatedAt, "2026-10-22T10:00:00.000Z");

  // The same day again with other numbers: replaced, not added.
  const newer = day(iso(0), { translator: { sessions: 4, minutes: 20 } });
  await put(rig, iso(0), newer);
  const second = LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { cookie })).body);
  assert.equal(second.days.length, 2);
  assert.deepEqual(second.days[1]!.translator, { sessions: 4, minutes: 20 });
});

test("the phone reads the same view as the browser, and sees its own days only", async () => {
  rig = await startWeb();
  await turnOn(rig);
  await turnOn(rig, USER_B);
  await put(rig, iso(-1), day(iso(-1)), USER_A);
  await put(rig, iso(-1), day(iso(-1), { translator: { sessions: 9, minutes: 9 } }), USER_B);

  const a = LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { token: USER_A })).body);
  const b = LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { token: USER_B })).body);
  assert.equal(a.days.length, 1);
  assert.equal(a.days[0]!.translator.sessions, 1);
  assert.equal(b.days[0]!.translator.sessions, 9);
});

test("a day is stored in its canonical form: defaults filled in, nothing else", async () => {
  rig = await startWeb();
  await turnOn(rig);
  await put(rig, TODAY, day(TODAY));
  const [row] = await rig.store.logbookDays(ID_A, SINCE_ALWAYS);
  const stored = JSON.parse(row!.summary);
  assert.deepEqual(stored.tools.save_memory, { done: 2, declined: 0, unsure: 0, failed: 0, undone: 0 });
  assert.deepEqual(Object.keys(stored).sort(), Object.keys(DaySummarySchema.parse(day(TODAY))).sort());
});

test("a full day with every tool in use fits: bigger than the usual body limit, within Logbook's own", async () => {
  rig = await startWeb();
  await turnOn(rig);
  const tools = Object.fromEntries(LOGBOOK_TOOL_IDS.map((id) => [id, { done: 1234, declined: 12, unsure: 3, failed: 5, undone: 7 }]));
  const body = JSON.stringify(day(TODAY, { tools }), null, 2);
  assert.ok(body.length > 8 * 1024 && body.length < 16 * 1024, `the body is ${body.length} bytes`);
  const res = await fetch(`${rig.base}/v1/web/logbook/days/${TODAY}`, { method: "PUT", headers: { authorization: `Bearer ${USER_A}`, "content-type": "application/json" }, body });
  assert.equal(res.status, 200, await res.text());
  const view = LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { token: USER_A })).body);
  assert.equal(Object.keys(view.days[0]!.tools).length, LOGBOOK_TOOL_IDS.length);
});

test("a body larger than Logbook's limit is refused as too large, and the usual limit still applies elsewhere", async () => {
  rig = await startWeb();
  await turnOn(rig);
  const res = await fetch(`${rig.base}/v1/web/logbook/days/${TODAY}`, {
    method: "PUT",
    headers: { authorization: `Bearer ${USER_A}`, "content-type": "application/json" },
    body: JSON.stringify(day(TODAY), null, 1) + " ".repeat(17 * 1024),
  });
  assert.equal(res.status, 413);
  const other = await fetch(`${rig.base}/v1/web/logbook/state`, {
    method: "PUT",
    headers: { authorization: `Bearer ${USER_A}`, "content-type": "application/json" },
    body: JSON.stringify({ enabled: true }) + " ".repeat(9 * 1024),
  });
  assert.equal(other.status, 413, "the state route keeps the usual 8 KiB");
  assert.deepEqual(await rig.store.logbookDays(ID_A, SINCE_ALWAYS), []);
});

// ------------------------------------------------------------------ nothing but counts

const REFUSED: [string, (d: ReturnType<typeof day>) => unknown][] = [
  ["an extra field at the top", (d) => ({ ...d, transcript: "buy milk" })],
  ["an extra field in a section", (d) => ({ ...d, notes: { ...d.notes, text: "my password is x" } })],
  ["a tool that isn't one of Doddy's", (d) => ({ ...d, tools: { ...d.tools, "call_my_mother_anna_kowalska": { done: 1 } } })],
  ["words as a language", (d) => ({ ...d, conversations: { ...d.conversations, languages: { "I told Doddy about the surprise party": 1 } } })],
  ["a note type that isn't one of the nine", (d) => ({ ...d, notes: { ...d.notes, by_kind: { secret: 1 } } })],
  ["a count that is text", (d) => ({ ...d, lists: { ...d.lists, ticked: "three" } })],
  ["a negative count", (d) => ({ ...d, lists: { ...d.lists, ticked: -1 } })],
  ["a count with a fraction", (d) => ({ ...d, lists: { ...d.lists, ticked: 1.5 } })],
  ["a count above the cap", (d) => ({ ...d, lists: { ...d.lists, ticked: 10_001 } })],
  ["hours that don't add up to the conversations", (d) => ({ ...d, conversations: { ...d.conversations, count: 4 } })],
  ["more languages than conversations", (d) => ({ ...d, conversations: { ...d.conversations, languages: { en: 3, pl: 3 } } })],
  ["more errands finished than handed over", (d) => ({ ...d, errands: { ...d.errands, finished: 2 } })],
  ["the wrong schema name", (d) => ({ ...d, schema: "doddy.logbook.day.v2" })],
  ["a day that isn't a calendar day", (d) => ({ ...d, day: "2026-02-31" })],
  ["twenty-five hours", (d) => ({ ...d, conversations: { ...d.conversations, by_hour: [...d.conversations.by_hour, 0] } })],
  ["a list instead of an object", () => [1, 2, 3]],
  ["nothing", () => null],
];

for (const [name, change] of REFUSED) {
  test(`a summary with ${name} is refused whole and nothing is stored`, async () => {
    rig = await startWeb();
    await turnOn(rig);
    const date = TODAY;
    const res = await put(rig, date, change(day(date)));
    assert.equal(res.status, 400, res.text);
    assert.equal(res.body.error.code, "invalid_request");
    assert.deepEqual(await rig.store.logbookDays(ID_A, SINCE_ALWAYS), []);
  });
}

test("a refusal names the section, never what was sent", async () => {
  rig = await startWeb();
  await turnOn(rig);
  const planted = "PLANTED-words-someone-said-to-Doddy";
  const body = day(TODAY, { tools: { [planted]: { done: 1 } }, conversations: { ...day(TODAY).conversations, languages: { [planted]: 1 } } });
  const res = await put(rig, TODAY, body);
  assert.equal(res.status, 400);
  assert.ok(!res.text.includes(planted), res.text);
  assert.ok(!rig.logs.join("\n").includes(planted), "not in the logs either");
  assert.match(res.body.error.message, /tools|conversations/);
});

// ------------------------------------------------------------------ which days

test("the day in the address must be the day in the summary", async () => {
  rig = await startWeb();
  await turnOn(rig);
  const res = await put(rig, iso(-1), day(iso(0)));
  assert.equal(res.status, 400, res.text);
  assert.deepEqual(await rig.store.logbookDays(ID_A, SINCE_ALWAYS), []);
});

test("days older than the kept window, or further ahead than tomorrow, are refused; the edges are kept", async () => {
  rig = await startWeb();
  await turnOn(rig);
  const oldest = oldestKeptDay(rig.clock.ms);
  assert.equal(oldest, iso(-90));
  assert.equal((await put(rig, iso(-91), day(iso(-91)))).status, 400, "91 days back");
  assert.equal((await put(rig, iso(2), day(iso(2)))).status, 400, "the day after tomorrow");
  assert.equal((await put(rig, oldest, day(oldest))).status, 200, "90 days back");
  assert.equal((await put(rig, iso(1), day(iso(1)))).status, 200, "tomorrow, for a phone east of UTC");
});

test("an address that isn't a day is not a route", async () => {
  rig = await startWeb();
  await turnOn(rig);
  for (const path of ["/v1/web/logbook/days/yesterday", "/v1/web/logbook/days/2026-10-2", "/v1/web/logbook/days/"]) {
    assert.equal((await rig.call("PUT", path, { token: USER_A, body: day(TODAY) })).status, 404, path);
  }
});

// ------------------------------------------------------------------ turning off, deleting, export

test("turning Logbook off deletes every stored day in the same step, and says how many", async () => {
  rig = await startWeb();
  await turnOn(rig);
  await put(rig, iso(-1), day(iso(-1)));
  await put(rig, iso(0), day(iso(0)));
  await turnOn(rig, USER_B);
  await put(rig, iso(0), day(iso(0)), USER_B);

  const off = await rig.call("PUT", "/v1/web/logbook/state", { token: USER_A, body: { enabled: false } });
  assert.deepEqual(off.body, { enabled: false, deletedDays: 2 });
  assert.deepEqual(await rig.store.logbookDays(ID_A, SINCE_ALWAYS), []);
  assert.equal((await rig.store.logbookDays(ID_B, SINCE_ALWAYS)).length, 1, "another person's days stay");
  const view = LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { token: USER_A })).body);
  assert.equal(view.enabled, false);
  assert.equal((await put(rig, iso(0), day(iso(0)))).status, 403, "and nothing more is taken");
  // Turning it on again starts from nothing.
  assert.deepEqual((await rig.call("PUT", "/v1/web/logbook/state", { token: USER_A, body: { enabled: true } })).body, { enabled: true, deletedDays: 0 });
});

test("the person can delete everything from the browser: only with the web app's own request, and only their own days", async () => {
  rig = await startWeb();
  await turnOn(rig);
  await turnOn(rig, USER_B);
  await put(rig, iso(-1), day(iso(-1)));
  await put(rig, iso(0), day(iso(0)));
  await put(rig, iso(0), day(iso(0)), USER_B);
  const cookie = await rig.signIn(await rig.code());

  const foreign = await rig.call("DELETE", "/v1/web/logbook", { cookie });
  assert.equal(foreign.status, 401, "a cookie request that isn't from the web app is refused");
  assert.equal((await rig.store.logbookDays(ID_A, SINCE_ALWAYS)).length, 2);

  const deleted = await rig.call("DELETE", "/v1/web/logbook", { cookie, browser: true });
  assert.deepEqual(deleted.body, { deletedDays: 2 });
  assert.deepEqual(await rig.store.logbookDays(ID_A, SINCE_ALWAYS), []);
  assert.equal((await rig.store.logbookDays(ID_B, SINCE_ALWAYS)).length, 1);
  // Logbook stays on: the iPhone keeps sending, the person only cleared what was there.
  assert.equal(LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { cookie })).body).enabled, true);
  assert.deepEqual((await rig.call("DELETE", "/v1/web/logbook", { token: USER_A })).body, { deletedDays: 0 });
});

test("download everything: a JSON file with the state and every kept day, named for the date", async () => {
  rig = await startWeb();
  await turnOn(rig);
  await put(rig, iso(-1), day(iso(-1)));
  await put(rig, iso(0), day(iso(0)));
  const cookie = await rig.signIn(await rig.code());

  const res = await rig.call("GET", "/v1/web/logbook/export", { cookie });
  assert.equal(res.status, 200, res.text);
  assert.match(res.headers.get("content-type") ?? "", /^application\/json/);
  assert.match(res.headers.get("content-disposition") ?? "", /attachment; filename="doddy-logbook-2026-10-22\.json"/);
  const file = JSON.parse(res.text);
  assert.equal(file.exportedAt, "2026-10-22T10:00:00.000Z");
  const { exportedAt: _ignored, ...view } = file;
  assert.deepEqual(LogbookViewSchema.parse(view).days.map((d) => d.day), [iso(-1), iso(0)]);
  // Another person's file has none of these days.
  const other = JSON.parse((await rig.call("GET", "/v1/web/logbook/export", { token: USER_B })).text);
  assert.deepEqual(other.days, []);
});

// ------------------------------------------------------------------ retention and bad rows

test("days older than the window are not shown even before the sweep runs, and the sweep deletes them", async () => {
  rig = await startWeb();
  await turnOn(rig);
  await put(rig, iso(-90), day(iso(-90)));
  await put(rig, iso(0), day(iso(0)));
  rig.clock.advance(DAY); // the oldest day is now 91 days back
  const view = LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { token: USER_A })).body);
  assert.deepEqual(view.days.map((d) => d.day), [iso(0)]);
  assert.equal((await rig.store.logbookDays(ID_A, SINCE_ALWAYS)).length, 2, "still stored");

  await rig.store.pruneLogbook(oldestKeptDay(rig.clock.ms));
  assert.deepEqual((await rig.store.logbookDays(ID_A, SINCE_ALWAYS)).map((r) => r.day), [iso(0)]);
});

test("a stored row that no longer reads is left out of the view, never shown half-read", async () => {
  rig = await startWeb();
  await turnOn(rig);
  await put(rig, iso(0), day(iso(0)));
  await rig.store.putLogbookDay(ID_A, iso(-1), "not json at all", rig.clock.ms);
  await rig.store.putLogbookDay(ID_A, iso(-2), JSON.stringify({ ...day(iso(-2)), surprise: "x" }), rig.clock.ms);
  const view = LogbookViewSchema.parse((await rig.call("GET", "/v1/web/logbook", { token: USER_A })).body);
  assert.deepEqual(view.days.map((d) => d.day), [iso(0)]);
});

test("the table only takes a real day as its key", async () => {
  rig = await startWeb();
  await rig.store.setLogbookEnabled(ID_A, true, rig.clock.ms);
  await assert.rejects(rig.store.putLogbookDay(ID_A, "yesterday", "{}", rig.clock.ms));
});

// ------------------------------------------------------------------ who can ask

test("a guest iPhone (Ask Doddy only) has no Logbook", async () => {
  const guest = { verify: (h: string | undefined) => (h === "Bearer guest-token-1" ? { userId: "00000000-0000-4000-8000-0000000000aa", scope: "ask" as const } : null) };
  rig = await startWeb({ verifier: guest });
  for (const [method, path, body] of [
    ["GET", "/v1/web/logbook", undefined],
    ["PUT", "/v1/web/logbook/state", { enabled: true }],
    ["PUT", `/v1/web/logbook/days/${TODAY}`, day(TODAY)],
    ["DELETE", "/v1/web/logbook", undefined],
    ["GET", "/v1/web/logbook/export", undefined],
  ] as const) {
    const res = await rig.call(method, path, { token: "guest-token-1", ...(body ? { body } : {}) });
    assert.equal(res.status, 503, `${method} ${path}: ${res.text}`);
  }
});
