import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES, requireFullAccess } from "../src/auth.js";
import { CALENDAR_LIST_EVENTS, defaultRegistry } from "../src/capabilities.js";
import { AppError } from "../src/errors.js";
import { CLOUD_TOOLS } from "../src/tools/catalog.js";
import type { ExecuteCall } from "../src/tools/provider.js";
import { LOOKUP_FAILED } from "../src/tools/service.js";
import { COOKIE_READABLE } from "../src/web/sessions.js";
import { USER_A, USER_B } from "./helpers.js";
import { connect, off, on, type Rig, ready, runRaw, start } from "./toolsRig.js";

/**
 * ASK-01 and the reads that come before a yes (ADR-708): the one capability with no approval and why,
 * what a write's lookup may tell a caller, a run that never had a card, and the user's switch for the
 * "did the earlier try go through?" look.
 */

let rig: Rig;
afterEach(async () => rig?.close());

const ZONE = "Europe/Warsaw";
const prepare = (r: Rig, tool: string, args: Record<string, unknown>, o: { token?: string; scenario?: "normal" | "provider_error" | "rate_limited" | "malformed" | "expired" } = {}) =>
  r.call("POST", "/v1/tools/prepare", { token: o.token ?? USER_A, body: { tool, arguments: args, timeZone: ZONE }, ...(o.scenario ? { scenario: o.scenario } : {}) });
const idOf = (token: string) => DEV_IDENTITIES[token]!;
const composioUser = (r: Rig, token = USER_A) => r.store.composioUserId(idOf(token), r.clock.ms);
const count = async (r: Rig, sql: string) => Number((await r.store.db.query<{ n: number | string }>(sql)).rows[0]!.n);

/** An error as the caller sees it, without what differs on every call (ids, times). */
function shape(body: any) {
  const { correlationId: _c, receipt, ...error } = body.error;
  const { operationId: _o, timestamp: _t, ...kept } = receipt ?? {};
  return { ...error, receipt: kept };
}

// ------------------------------------------------------------------ the one read with no approval

test("calendar.listEvents is the only capability that runs with no approval, and every write needs a fresh one", () => {
  const all = defaultRegistry().all();
  assert.deepEqual(
    all.filter((c) => c.confirmation === "none").map((c) => c.id),
    ["calendar.listEvents"],
    "a new exemption has to be decided on purpose: add it here with the reason it is safe",
  );
  assert.equal(CALENDAR_LIST_EVENTS.risk, "read");
  assert.ok(all.filter((c) => c.risk === "write").every((c) => c.confirmation === "fresh_per_execution"));
});

test("that read is the Connected Apps screen's own button: no tool a model can ask for reaches it, and a guest or a cookie can't", async () => {
  rig = await start();
  // A model's calendar read is the tool read_google_calendar, which asks first like every other tool.
  const modelTool = CLOUD_TOOLS.find((t) => t.name === "read_google_calendar")!;
  assert.equal(modelTool.risk, "read");
  assert.equal((await prepare(rig, "read_google_calendar", { from: "2026-10-11", to: "2026-10-11" })).status, 409, "asked for through the tools API, it still needs the account and the card");
  assert.ok(!CLOUD_TOOLS.some((t) => /listEvents|connected-apps/.test(t.name)), "no cloud tool is the exempt capability");
  for (const name of ["calendar.listEvents", "listEvents"]) {
    assert.equal((await prepare(rig, name, {})).status, 404, `${name} is not a tool`);
    assert.equal((await runRaw(rig, name, {})).status, 404, `${name} is not a tool`);
  }

  // The route itself: the owner's session in the Authorization header, nothing else.
  const route = "/v1/connected-apps/google-calendar/events";
  const body = { date: "2026-10-11", timeZone: ZONE };
  assert.equal((await rig.call("POST", route, { token: null, body })).status, 401, "no session");
  assert.ok(!COOKIE_READABLE.has(`POST ${route}`), "a browser cookie can read two lists and nothing else");
  assert.throws(() => requireFullAccess({ userId: idOf(USER_A), scope: "ask" }), (e: AppError) => e.code === "live_not_configured", "a guest iPhone is refused");
});

// ------------------------------------------------------------------ a write's lookup before the card

test("a write whose lookup gives no card answers the same whatever the reason, and says nothing it found", async () => {
  rig = await start();
  await ready(rig, "gmail", "reply_to_email");

  // A found email goes into the card (the preview) and nowhere else.
  const card = await prepare(rig, "reply_to_email", { query: "from:anna", body: "Yes." }, { scenario: "normal" });
  assert.equal(card.status, 200, card.text);
  assert.ok(card.body.preview.lines.some((l: string) => /Anna Demo/.test(l)) && card.body.preview.lines.includes("Re: Lunch on Friday?"));
  const approvalsBefore = await count(rig, "SELECT COUNT(*)::int AS n FROM approvals");

  const reasons: [string, string, "normal" | "provider_error" | "rate_limited" | "malformed"][] = [
    ["nothing matched", "nomatch", "normal"],
    ["a match with no address to reply to", "newsletter", "normal"],
    ["the provider failed", "from:anna", "provider_error"],
    ["the provider was busy", "from:anna", "rate_limited"],
    ["an answer that can't be read", "from:anna", "malformed"],
  ];
  const answers: ReturnType<typeof shape>[] = [];
  for (const [why, query, scenario] of reasons) {
    const res = await prepare(rig, "reply_to_email", { query, body: "Yes." }, { scenario });
    assert.equal(res.status, 404, `${why}: ${res.text}`);
    answers.push(shape(res.body));
  }
  for (const [n, answer] of answers.entries()) assert.deepEqual(answer, answers[0], `${reasons[n]![0]} answers as "${reasons[0]![0]}" does`);
  assert.deepEqual(answers[0], {
    code: "not_found",
    message: LOOKUP_FAILED,
    receipt: {
      operation: "write", toolkit: "gmail", tool: "reply_to_email", mode: "mock", status: "blocked",
      summary: `Not done: ${LOOKUP_FAILED}`, errorCode: "not_found", providerReference: null,
    },
  });
  // Nothing the lookup found is in any answer, and no approval was made for any of them.
  const said = JSON.stringify(answers);
  for (const found of ["Anna", "anna@demo", "Lunch", "Newsletter", "newsletter", "nomatch"]) assert.ok(!said.includes(found), `the answer doesn't contain "${found}"`);
  assert.equal(await count(rig, "SELECT COUNT(*)::int AS n FROM approvals"), approvalsBefore);

  // The operator's log keeps the reason as a fixed word (never the search or what was found).
  const kinds = rig.logs.map((l) => JSON.parse(l)).filter((l) => l.event === "lookup_failed").map((l) => `${l.tool}:${l.kind}`);
  assert.deepEqual(kinds, [
    "reply_to_email:not_found",
    "reply_to_email:not_found",
    "reply_to_email:provider_unavailable",
    "reply_to_email:rate_limited",
    "reply_to_email:malformed_provider_result",
  ]);
  assert.ok(!rig.logs.join("\n").includes("newsletter"));
  // The receipts list shows one kind of line, too.
  const receipts = (await rig.call("GET", "/v1/tools/receipts", { scenario: "normal" })).body.receipts.filter((r: any) => r.errorCode === "not_found");
  assert.equal(receipts.length, 5);
  assert.equal(new Set(receipts.map((r: any) => r.summary)).size, 1);
});

test("a calendar write answers alike for no event, several events and an event that isn't an invitation, and doesn't echo the title", async () => {
  rig = await start();
  await ready(rig, "gcalendar", "answer_google_invite");
  const asked = (title: string, start: string) => ({ title, start, answer: "accepted" });

  // One matching invitation shows its card: the lookup's result is in the preview.
  const card = await prepare(rig, "answer_google_invite", asked("Demo: team lunch", "2026-10-13T13:00"));
  assert.equal(card.status, 200, card.text);
  assert.ok(card.body.preview.lines.includes("From: Anna Demo"));

  const duplicate = rig.provider.execute.bind(rig.provider);
  let twice = false;
  rig.provider.execute = async (call: ExecuteCall) => {
    const result = await duplicate(call);
    if (!twice || call.slug !== "GOOGLECALENDAR_EVENTS_LIST") return result;
    const raw = structuredClone(result.raw) as { data: { items: unknown[] } };
    raw.data.items = [...raw.data.items, ...raw.data.items];
    return { ...result, raw };
  };

  const none = await prepare(rig, "answer_google_invite", asked("Demo: team lunch", "2026-10-13T09:00"));
  const own = await prepare(rig, "answer_google_invite", asked("Demo: dentist", "2026-10-12T15:00"));
  twice = true;
  const several = await prepare(rig, "answer_google_invite", asked("Demo: team lunch", "2026-10-13T13:00"));
  for (const res of [none, own, several]) assert.equal(res.status, 404, res.text);
  assert.deepEqual(shape(own.body), shape(none.body), "an event the user made answers as no event does");
  assert.deepEqual(shape(several.body), shape(none.body), "several events answer as no event does");
  assert.equal(none.body.error.message, LOOKUP_FAILED);
  for (const res of [none, own, several]) {
    assert.ok(!res.text.includes("dentist") && !res.text.includes("team lunch") && !res.text.includes("13:00"), "the answer repeats neither the title nor the time");
  }
});

test("a dead connection is still told apart (the app offers Connect for it); it is a fact about the account, not about what is in it", async () => {
  rig = await start();
  await ready(rig, "gmail", "reply_to_email");
  const res = await prepare(rig, "reply_to_email", { query: "from:anna", body: "Yes." }, { scenario: "expired" });
  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, "connection_expired");
  assert.ok(!res.text.includes("Anna"));
  assert.equal((await rig.store.getConnection(idOf(USER_A), "gmail"))?.status, "expired", "and the account is marked expired, as before");
});

// ------------------------------------------------------------------ a run that never had a card

test("a run with no card, a made-up approval, another user's or an expired one looks nothing up", async () => {
  rig = await start();
  await ready(rig, "gmail", "reply_to_email");
  assert.equal((await connect(rig, "gmail", USER_B)).status, 200);
  const args = { query: "from:anna", body: "Yes." };
  const none = { query: "nomatch", body: "Yes." };
  const executed = () => rig.provider.executed.length;
  const fake = "11111111-1111-4111-8111-111111111111";

  // Made-up approvals, for a search that matches and for one that doesn't: the same refusal, and no read.
  const matching = await runRaw(rig, "reply_to_email", args, { approvalId: fake });
  const missing = await runRaw(rig, "reply_to_email", none, { approvalId: fake });
  const bare = await runRaw(rig, "reply_to_email", args);
  for (const res of [matching, missing, bare]) {
    assert.equal(res.status, 403, res.text);
    assert.equal(res.body.error.receipt.errorCode, "confirmation_required");
  }
  assert.deepEqual(shape(matching.body), shape(missing.body), "a search that matches can't be told from one that doesn't");
  assert.equal(executed(), 0, "no lookup ran for any of them");

  // An approval prepare issued, but to another user, for another tool, or two minutes ago: no lookup either.
  const card = await prepare(rig, "reply_to_email", args);
  assert.equal(card.status, 200, card.text);
  const afterCard = executed();
  assert.equal(afterCard, 1, "prepare made its one lookup");
  const asB = await runRaw(rig, "reply_to_email", args, { approvalId: card.body.approvalId }, USER_B);
  assert.equal(asB.status, 403);
  await on(rig, "forward_email");
  const otherTool = await runRaw(rig, "forward_email", { query: "from:anna", to: "bob@example.com" }, { approvalId: card.body.approvalId });
  assert.equal(otherTool.status, 403);
  assert.equal(executed(), afterCard, "not for another user, not for another tool");
  rig.clock.advance(121_000);
  const late = await runRaw(rig, "reply_to_email", args, { approvalId: card.body.approvalId });
  assert.equal(late.status, 403);
  assert.equal(late.body.error.receipt.errorCode, "confirmation_required");
  assert.equal(executed(), afterCard, "and not when it has expired");

  // A real, fresh card still works as before: the lookup, then the write.
  const fresh = await prepare(rig, "reply_to_email", args);
  const done = await runRaw(rig, "reply_to_email", args, { approvalId: fresh.body.approvalId });
  assert.equal(done.status, 200, done.text);
});

// ------------------------------------------------------------------ the look for an earlier try

test("after a lost answer, the list read for an earlier try runs only when the user's own switch for it is on", async () => {
  rig = await start();
  await ready(rig, "todoist", "add_todoist_task");
  const args = { content: "Pay rent" };
  const userId = idOf(USER_A);
  const runs = () => rig.store.usage(`user:${userId}:toolruns`, "day:2026-10-10");
  const lists = () => rig.provider.executed.filter((e) => e.slug === "TODOIST_GET_ALL_TASKS").length;

  const first = await prepare(rig, "add_todoist_task", args);
  rig.provider.setScenario(await composioUser(rig), "lost_answer");
  await runRaw(rig, "add_todoist_task", args, { approvalId: first.body.approvalId });
  rig.provider.setScenario(await composioUser(rig), "normal");

  // Switched off by the user: Doddy doesn't read their tasks, doesn't count a read, and the card only warns.
  assert.equal((await off(rig, "list_todoist_tasks")).status, 200);
  const before = await runs();
  const warned = await prepare(rig, "add_todoist_task", args);
  assert.equal(warned.body.earlier.status, "outcome_unknown");
  assert.equal(lists(), 0, "no read of the user's tasks");
  assert.equal(await runs(), before, "and none counted");

  // On: it looks, counts the read, and the card can say it found it.
  assert.equal((await on(rig, "list_todoist_tasks")).status, 200);
  const found = await prepare(rig, "add_todoist_task", args);
  assert.equal(found.body.earlier.status, "found");
  assert.equal(lists(), 1);
  assert.equal(await runs(), before + 1);
});

