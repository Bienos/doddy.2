import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { TRAVEL_GMAIL_QUERY, type TravelReader } from "../src/travel/reader.js";
import { TRAVEL_SCAN } from "../src/tools/service.js";
import { USER_A, USER_B } from "./helpers.js";
import { connect, off, type Rig, start } from "./toolsRig.js";

/**
 * The trip screen's Gmail search (decision 2026-11-11-travel-agent-plan, TRAVEL_EMAILS.md): the same
 * gates as read_email, its own ask-first card, one search per yes, nothing kept, counts-only logs.
 * Mock Gmail and mock Claude (or a scripted reader) only: nothing here ran against a real mailbox or model.
 */
let rig: Rig;
afterEach(async () => rig?.close());

const prepare = (r: Rig, token = USER_A) => r.call("POST", "/v1/travel/prepare", { token, body: { timeZone: "Europe/Warsaw" } });
const scan = (r: Rig, approvalId: string, token = USER_A) => r.call("POST", "/v1/travel/scan", { token, body: { approvalId, timeZone: "Europe/Warsaw" } });

test("asked and approved: one Gmail search, the demo booking found, the bank email set aside", async () => {
  rig = await start();
  await connect(rig, "gmail");
  const card = await prepare(rig);
  assert.equal(card.status, 200, card.text);
  assert.equal(card.body.tool, TRAVEL_SCAN);
  assert.equal(card.body.preview.confirmLabel, "Search Gmail");
  assert.match(card.body.preview.lines.join(" "), /Anthropic/);
  assert.equal(rig.provider.executed.length, 0, "the card reads nothing");

  const res = await scan(rig, card.body.approvalId);
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(rig.provider.executed.map((e) => e.slug), ["GMAIL_FETCH_EMAILS"]);
  assert.equal(rig.provider.executed[0]!.arguments.query, TRAVEL_GMAIL_QUERY);
  assert.equal(rig.provider.executed[0]!.arguments.verbose, true);
  assert.equal(res.body.emailsFound, 2);
  assert.equal(res.body.emailsNotTravel, 1);
  assert.equal(res.body.emailsUnreadable, 0);
  assert.deepEqual(res.body.bookings.map((b: any) => [b.reference, b.state, b.kind]), [["DEMO12", "booked", "flight"]]);
  assert.equal(res.body.bookings[0].facts.segments[0].departDate, "2027-05-12");
  assert.equal(res.body.receipt.status, "succeeded");

  // One yes, one search.
  const again = await scan(rig, card.body.approvalId);
  assert.equal(again.status, 403);
  assert.equal(again.body.error.code, "capability_disabled");
  assert.equal(again.body.error.receipt.errorCode, "ask_first_required");
  assert.equal(rig.provider.executed.length, 1);

  // Counts only in the log.
  const line = rig.logs.find((l) => l.includes('"travel_scan"'));
  assert.ok(line);
  assert.doesNotMatch(line!, /DEMO12|Lizbona|Ryanair|ryanair/);
});

test("no card, a made-up approval or another user's approval reads nothing", async () => {
  rig = await start();
  await connect(rig, "gmail");
  await connect(rig, "gmail", USER_B);
  const made = await scan(rig, "6f1c0f4e-1b1a-4c2e-9a77-0d3c1d2e3f40");
  assert.equal(made.status, 403);
  assert.equal(made.body.error.receipt.errorCode, "ask_first_required");
  const bCard = await prepare(rig, USER_B);
  assert.equal((await scan(rig, bCard.body.approvalId, USER_A)).status, 403);
  assert.equal(rig.provider.executed.length, 0);
});

test("Gmail not connected, or the user's read_email switch off: refused before anything is read", async () => {
  rig = await start();
  const none = await prepare(rig);
  assert.equal(none.body.error.code, "not_connected");
  await connect(rig, "gmail");
  assert.equal((await off(rig, "read_email")).status, 200);
  const switched = await prepare(rig);
  assert.equal(switched.status, 403);
  assert.equal(switched.body.error.code, "capability_disabled");
  assert.equal(rig.provider.executed.length, 0);
});

test("without a model the search says 'not set up' and never reads the mailbox", async () => {
  rig = await start({}, { claude: null });
  await connect(rig, "gmail");
  const card = await prepare(rig);
  assert.equal(card.body.error.code, "live_not_configured");
  assert.equal(rig.provider.executed.length, 0);
});

test("the reader gets cleaned text, and an email it can't read is counted, not guessed", async () => {
  const seen: string[] = [];
  const reader: TravelReader = {
    async read(input) {
      seen.push(input.text);
      if (input.text.includes("statement")) throw new Error("timeout");
      return { kind: "not_travel", status: "other", provider: null, reference: null, segments: [], stay: null, destination: null, bags: [], total: null, freeCancellationUntil: null, nonRefundable: null, payOnSite: [], deposit: null, notes: [] };
    },
  };
  rig = await start({}, { travelReader: reader });
  await connect(rig, "gmail");
  const res = await scan(rig, (await prepare(rig)).body.approvalId);
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.emailsUnreadable, 1);
  assert.deepEqual(res.body.bookings, []);
  assert.equal(seen.length, 2);
});

test("the daily Claude limit counts one unit per five emails and refuses a search over it", async () => {
  rig = await start({ userDailyClaude: 0 });
  await connect(rig, "gmail");
  const res = await scan(rig, (await prepare(rig)).body.approvalId);
  assert.equal(res.status, 429, res.text);
  assert.equal(res.body.error.code, "quota_exceeded");
});
