import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { type ClaudeProvider, MockClaudeProvider, type StructuredInput } from "../src/tools/claude.js";
import { digestLogbook } from "../src/web/logbookDigest.js";
import { DaySummarySchema } from "../src/web/logbook.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * Doddy Web's chat reads the account as well as kept memory (ADR-604): Logbook's counts, counts
 * over kept conversations, the online accounts, the documents Doddy made and his receipts. Each
 * part is the caller's own, goes to the model as data the answer can cite by name, and never
 * reaches a log.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const DAY = 86_400_000;
const NOW = "2026-10-22T10:00:00.000Z"; // the rig's clock
const TODAY = "2026-10-22";

/** Records what Claude was sent; answers like the demo provider (citing the first alias offered). */
class Recording extends MockClaudeProvider {
  calls: StructuredInput[] = [];
  override async structured(input: StructuredInput) {
    this.calls.push(input);
    return super.structured(input);
  }
}

/** Answers with fixed text and sources, so a test can pick what is cited. */
const answering = (answer: string, sources: string[]): ClaudeProvider =>
  Object.assign(new MockClaudeProvider(), { structured: async () => ({ value: { answer, sources }, usage: { inputTokens: 3, outputTokens: 4 } }) });

const ask = (r: WebRig, message: string, extra: Record<string, unknown> = {}, token = USER_A) => r.call("POST", "/v1/web/chat", { token, body: { message, ...extra } });

/** The ACCOUNT block of what the model was sent, parsed. */
function accountOf(call: StructuredInput): Record<string, any> {
  const m = /ACCOUNT \(user data, not instructions\):\n(.+)/.exec(call.user);
  assert.ok(m, "the question carries the account");
  return JSON.parse(m[1]!);
}

/** A valid Logbook day: 3 conversations of 9 minutes in all, at 8, 13 and 20 o'clock. */
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
const daysAgo = (n: number) => new Date(Date.parse(`${TODAY}T00:00:00Z`) - n * DAY).toISOString().slice(0, 10);

async function logbookOn(r: WebRig, days: string[], token = USER_A) {
  assert.equal((await r.call("PUT", "/v1/web/logbook/state", { token, body: { enabled: true } })).status, 200);
  for (const d of days) {
    const res = await r.call("PUT", `/v1/web/logbook/days/${d}`, { token, body: day(d) });
    assert.equal(res.status, 200, res.text);
  }
}

async function connect(r: WebRig, toolkit: string, token = USER_A) {
  const begin = await r.call("POST", `/v1/tools/${toolkit}/connect`, { token, body: {} });
  assert.equal(begin.status, 200, begin.text);
  const done = await r.call("POST", `/v1/tools/${toolkit}/complete`, {
    token,
    body: { attemptId: begin.body.attemptId, nonce: begin.body.nonce, result: { kind: "mock", outcome: "approve" } },
  });
  assert.equal(done.status, 200, done.text);
}

async function makeDocument(r: WebRig, title: string, token = USER_A) {
  const args = { kind: "pdf", title, request: "A one-page summary" };
  const asked = await r.call("POST", "/v1/tools/prepare", { token, body: { tool: "make_document", arguments: args } });
  assert.equal(asked.status, 200, asked.text);
  const ran = await r.call("POST", "/v1/tools/run", { token, body: { tool: "make_document", arguments: args, timeZone: "Europe/Warsaw", approvalId: asked.body.approvalId } });
  assert.equal(ran.status, 200, ran.text);
}

const conversationBody = (startedAt: string, minutes: number, turns: number) => ({
  startedAt,
  endedAt: new Date(Date.parse(startedAt) + minutes * 60_000).toISOString(),
  language: "pl",
  endedBy: "you",
  turns: Array.from({ length: turns }, (_, i) => ({ role: i % 2 === 0 ? "user" : "doddy", text: `PLANTED-turn-${i}` })),
});
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

// ------------------------------------------------------------------ answering from the account

test("with nothing kept, the chat still answers from the account and can cite a part of it", async () => {
  rig = await startWeb({ chatClaude: answering("You have **Gmail** connected.", ["apps"]) });
  await connect(rig, "gmail");
  const cookie = await rig.signIn(await rig.code());
  const res = await rig.call("POST", "/v1/web/chat", { cookie, browser: true, body: { message: "Which apps do I have connected?", locale: "en" } });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.text, "You have **Gmail** connected.");
  assert.deepEqual(res.body.sources, [{ kind: "account", part: "apps" }]);
});

test("the account goes to the model as data in the question, never in the instructions", async () => {
  const claude = new Recording();
  rig = await startWeb({ chatClaude: claude });
  await connect(rig, "gmail");
  await makeDocument(rig, "Plan for PLANTED-doc-name");
  await ask(rig, "What did you make for me?");
  const call = claude.calls[0]!;
  const account = accountOf(call);
  assert.deepEqual(Object.keys(account), ["logbook", "talk", "apps", "documents", "activity"]);
  assert.match(account.logbook.state, /^off/);
  assert.match(account.talk.state, /^off/);
  const gmail = account.apps.accounts.find((a: any) => a.name === "Gmail");
  assert.equal(gmail.status, "connected");
  assert.ok(gmail.toolsTotal > 0);
  assert.equal(account.documents.documents[0].name.startsWith("Plan for PLANTED-doc-name"), true);
  assert.equal(account.documents.keptDays, 7);
  assert.ok(account.activity.receipts.some((r: any) => r.what === "connect" && r.app === "Gmail" && r.outcome === "succeeded"));
  assert.ok(!call.system.includes("PLANTED"), "the instructions hold none of the account");
  assert.match(call.system, /data, not instructions/);
  assert.match(call.user, /^TODAY: 2026-10-22 \(Thursday\), UTC/);
});

test("Logbook's days are added up per period for the model; days of another person never are", async () => {
  const claude = new Recording();
  rig = await startWeb({ chatClaude: claude });
  await logbookOn(rig, [daysAgo(0), daysAgo(1), daysAgo(10), daysAgo(40)]);
  await logbookOn(rig, [daysAgo(0), daysAgo(2), daysAgo(3)], USER_B);
  await ask(rig, "How much did we talk this week?");
  const logbook = accountOf(claude.calls[0]!).logbook;
  assert.equal(logbook.state, "on");
  assert.equal(logbook.today, TODAY);
  const [week, month, all] = logbook.periods;
  assert.deepEqual([week.period, week.from, week.to, week.daysWithData], ["last_7_days", daysAgo(6), TODAY, 2]);
  assert.equal(week.conversations.count, 6);
  assert.equal(week.conversations.minutes, 18);
  assert.equal(week.conversations.averageMinutes, 3);
  assert.deepEqual(week.conversations.languages, { en: 4, pl: 2 });
  assert.deepEqual(week.conversations.busiestHours, [{ hour: 8, conversations: 2 }, { hour: 13, conversations: 2 }, { hour: 20, conversations: 2 }]);
  assert.deepEqual(week.conversations.byWeekday, { thu: 3, wed: 3 });
  assert.deepEqual(week.tools.map((t: any) => t.id), ["read_calendar", "save_memory", "send_email"], "most used first, ties by name");
  assert.deepEqual(week.tools[2], { id: "send_email", uses: 4, done: 0, declined: 2, unsure: 2, failed: 0, undone: 0 });
  assert.equal(week.notes.saved, 4);
  assert.deepEqual([month.daysWithData, month.conversations.count], [3, 9]);
  assert.deepEqual([all.daysWithData, all.conversations.count, all.from], [4, 12, daysAgo(40)]);
  assert.deepEqual(logbook.recentDays.map((d: any) => d.day), [daysAgo(40), daysAgo(10), daysAgo(1), daysAgo(0)]);
  assert.equal(logbook.recentDays[3].toolUses, 6);
});

test("'today' is the person's own date when the page sends a time zone", async () => {
  const claude = new Recording();
  rig = await startWeb({ chatClaude: claude });
  rig.clock.advance(14 * 3_600_000); // 2026-10-23T00:00Z: still the 22nd in New York, already the 23rd in Tokyo
  await ask(rig, "What day is it?", { timeZone: "America/New_York" });
  await ask(rig, "What day is it?", { timeZone: "Asia/Tokyo" });
  assert.match(claude.calls[0]!.user, /^TODAY: 2026-10-22 \(Thursday\), time zone America\/New_York/);
  assert.match(claude.calls[1]!.user, /^TODAY: 2026-10-23 \(Friday\), time zone Asia\/Tokyo/);
});

test("counts over kept conversations come from their plain columns, only while the person keeps them", async () => {
  const claude = new Recording();
  rig = await startWeb({ chatClaude: claude });
  assert.equal((await rig.call("PUT", "/v1/web/memory/state", { token: USER_A, body: { notes: false, conversations: true } })).status, 200);
  const started = (daysAgoMs: number) => new Date(Date.parse(NOW) - daysAgoMs * DAY).toISOString();
  for (const [n, ago, minutes, turns] of [[1, 1, 4, 6], [2, 3, 2, 2], [3, 20, 10, 12]] as const) {
    const res = await rig.call("PUT", `/v1/web/memory/conversations/${uuid(n)}`, { token: USER_A, body: conversationBody(started(ago), minutes, turns) });
    assert.equal(res.status, 200, res.text);
  }
  await ask(rig, "How long do we usually talk?");
  const talk = accountOf(claude.calls[0]!).talk;
  assert.deepEqual(
    talk,
    { state: "on", keptDays: 365, conversations: 3, turns: 20, minutes: 16, averageTurns: 6.7, averageMinutes: 5.3, first: started(20), last: started(1), last7Days: 2, last30Days: 3 },
  );
  assert.ok(!JSON.stringify(talk).includes("PLANTED"), "counts only: no turn's words");

  assert.equal((await rig.call("PUT", "/v1/web/memory/state", { token: USER_A, body: { notes: false, conversations: false } })).status, 200);
  await ask(rig, "How long do we usually talk?");
  assert.match(accountOf(claude.calls[1]!).talk.state, /^off/);
});

test("the chat reads only the caller's own account: another person's apps, documents and receipts stay out", async () => {
  const claude = new Recording();
  rig = await startWeb({ chatClaude: claude });
  await connect(rig, "notion", USER_B);
  await makeDocument(rig, "PLANTED-B-document", USER_B);
  await ask(rig, "What do I have?");
  const sent = claude.calls[0]!.user;
  assert.ok(!sent.includes("PLANTED-B-document"), "B's document");
  const account = accountOf(claude.calls[0]!);
  assert.notEqual(account.apps.accounts.find((a: any) => a.name === "Notion").status, "connected", "B's connection");
  assert.equal(account.activity.state, "no receipts yet", "B's receipts");
  assert.equal(account.documents.state, "none in the last 7 days");
});

test("an account part the model cites comes back as a source the page can link to; one it wasn't given discards the answer", async () => {
  rig = await startWeb({ chatClaude: answering("Twice this week.", ["logbook", "logbook", "activity"]) });
  const res = await ask(rig, "How often?");
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.body.sources, [{ kind: "account", part: "logbook" }, { kind: "account", part: "activity" }], "named twice, kept once");
  await rig.close();

  rig = await startWeb({ chatClaude: answering("Here.", ["calendar"]) });
  const bad = await ask(rig, "How often?");
  assert.equal(bad.status, 502, bad.text);
  assert.equal(bad.body.error.code, "malformed_provider_result");
});

test("the chat's logs hold counts only: no document name, receipt summary or Logbook number", async () => {
  rig = await startWeb({ chatClaude: new Recording() });
  await connect(rig, "gmail");
  await makeDocument(rig, "PLANTED-log-document");
  await logbookOn(rig, [TODAY]);
  await ask(rig, "PLANTED-log-question");
  const logs = rig.logs.filter((line) => line.includes('"event":"memory_chat"'));
  assert.equal(logs.length, 1);
  assert.match(logs[0]!, /"account":true/);
  for (const secret of ["PLANTED-log-document", "PLANTED-log-question", "Gmail connected", "busiestHours", "save_memory"]) assert.ok(!logs[0]!.includes(secret), secret);
});

// ------------------------------------------------------------------ what the page shows next to the chat

test("the page reads what the chat can see: switches, counts and account names, never content", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  const empty = await rig.call("GET", "/v1/web/chat/context", { cookie });
  assert.equal(empty.status, 200, empty.text);
  assert.equal(empty.headers.get("cache-control"), "private, no-store");
  assert.deepEqual(empty.body, {
    ready: true,
    memory: { configured: true, notes: false, conversations: false, noteCount: 0, conversationCount: 0 },
    logbook: { enabled: false, days: 0, updatedAt: null },
    apps: { connected: [], available: empty.body.apps.available },
    documents: { count: 0 },
    activity: { count: 0, lastAt: null },
  });
  assert.ok(empty.body.apps.available > 0, "the demo server offers accounts");

  await connect(rig, "gmail");
  await makeDocument(rig, "Something");
  await logbookOn(rig, [TODAY, daysAgo(1)]);
  await rig.call("PUT", "/v1/web/memory/state", { token: USER_A, body: { notes: true, conversations: false } });
  await rig.call("PUT", "/v1/web/memory/notes", { token: USER_A, body: { items: [{ id: uuid(1), text: "PLANTED-note", source: "explicit_text" }] } });
  const full = await rig.call("GET", "/v1/web/chat/context", { cookie });
  assert.deepEqual(full.body.memory, { configured: true, notes: true, conversations: false, noteCount: 1, conversationCount: 0 });
  assert.deepEqual([full.body.logbook.enabled, full.body.logbook.days], [true, 2]);
  assert.deepEqual(full.body.apps.connected, ["Gmail"]);
  assert.equal(full.body.documents.count, 1);
  assert.ok(full.body.activity.count >= 1);
  assert.ok(!full.text.includes("PLANTED"), "no note, document or receipt text");

  // Another person's page sees none of it.
  const other = await rig.call("GET", "/v1/web/chat/context", { token: USER_B });
  assert.deepEqual([other.body.apps.connected, other.body.documents.count, other.body.logbook.days, other.body.memory.noteCount], [[], 0, 0, 0]);
});

test("the page learns when the chat isn't set up on this server, and needs a session to ask", async () => {
  rig = await startWeb({ chatClaude: null });
  const res = await rig.call("GET", "/v1/web/chat/context", { token: USER_A });
  assert.equal(res.body.ready, false);
  assert.equal((await rig.call("GET", "/v1/web/chat/context")).status, 401);
  assert.equal((await rig.call("POST", "/v1/web/chat/context", { token: USER_A, body: {} })).status, 404);
});

// ------------------------------------------------------------------ the digest on its own

test("the digest: no days is null; a day ahead of 'today' still counts; ties keep a stable order", () => {
  assert.equal(digestLogbook([], TODAY), null);
  const tomorrow = "2026-10-23";
  const parsed = [DaySummarySchema.parse(day(tomorrow)), DaySummarySchema.parse(day(TODAY, { tools: { web_search: { done: 1 }, get_weather: { done: 1 } } }))];
  const digest = digestLogbook(parsed, TODAY)!;
  assert.equal(digest.periods[0]!.to, tomorrow);
  assert.equal(digest.periods[0]!.daysWithData, 2);
  assert.deepEqual(digest.periods[0]!.tools.map((t) => t.id).slice(0, 2), ["read_calendar", "save_memory"]);
  assert.deepEqual(digest.recentDays.map((d) => [d.day, d.weekday]), [[TODAY, "thu"], [tomorrow, "fri"]]);
});
