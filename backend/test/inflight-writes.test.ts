import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { AppError } from "../src/errors.js";
import { argumentDigest } from "../src/policy.js";
import type { ExecuteCall } from "../src/tools/provider.js";
import { DEV_IDENTITIES } from "../src/auth.js";
import { USER_A } from "./helpers.js";
import { connect, on, type Rig, runRaw, start } from "./toolsRig.js";

/**
 * A repeated write while the first try is still running (the phone lost the answer and asked again
 * during the lookup, which can take seconds), and repeats of a write with a lookup in general. The
 * repeat is told the first try may or may not go through, never "busy" or "needs a confirmation";
 * the write runs once; a repeat that asks for something else is refused; and a replay repeats only
 * what the first run recorded (ADR-322, DOD-08). Mock provider only.
 */

let rig: Rig;
afterEach(async () => rig?.close());

const prepare = (r: Rig, tool: string, args: Record<string, unknown>) => r.call("POST", "/v1/tools/prepare", { body: { tool, arguments: args } });
const ran = (r: Rig, slug: string) => r.provider.executed.filter((e) => e.slug === slug).length;

/**
 * Holds the next provider call with this slug until `release`: a slow Composio lookup (or write).
 * `entered` resolves once that call is waiting.
 */
function holdNext(r: Rig, slug: string): { entered: Promise<void>; release: () => void } {
  const execute = r.provider.execute.bind(r.provider);
  let armed = true;
  let entered!: () => void;
  let release!: () => void;
  const enteredP = new Promise<void>((resolve) => (entered = resolve));
  const released = new Promise<void>((resolve) => (release = resolve));
  r.provider.execute = async (call: ExecuteCall) => {
    if (armed && call.slug === slug) {
      armed = false;
      entered();
      await released;
    }
    return execute(call);
  };
  return { entered: enteredP, release };
}

async function gmail(r: Rig, tools: string[]) {
  assert.equal((await connect(r, "gmail")).status, 200);
  for (const t of tools) assert.equal((await on(r, t)).status, 200);
}

const FORWARD = { query: "from:anna", to: "bob@example.com", note: "See below" };

for (const userConcurrency of [1, 3]) {
  test(`a repeat during the first try's lookup is 'may or may not', never busy or 'needs a confirmation', and the write runs once (concurrency ${userConcurrency})`, async () => {
    rig = await start({ userConcurrency });
    await gmail(rig, ["forward_email"]);
    const card = await prepare(rig, "forward_email", FORWARD);
    assert.equal(card.status, 200, card.text);
    const approvalId = card.body.approvalId;

    const lookup = holdNext(rig, "GMAIL_FETCH_EMAILS");
    const first = runRaw(rig, "forward_email", FORWARD, { approvalId });
    await lookup.entered;

    // The phone lost the answer and asks again with the same yes, while the first try is still looking.
    const repeat = await runRaw(rig, "forward_email", FORWARD, { approvalId });
    assert.equal(repeat.status, 403, repeat.text);
    assert.notEqual(repeat.body.error.code, "busy");
    assert.equal(repeat.body.error.code, "capability_disabled");
    assert.equal(repeat.body.error.receipt.status, "outcome_unknown");
    assert.equal(repeat.body.error.receipt.errorCode, "earlier_outcome_unknown");
    assert.match(repeat.body.error.receipt.summary, /hasn't finished yet; it may or may not go through/);
    assert.ok(!/bob|anna|See below/.test(repeat.text), "nothing of the request in the answer");

    lookup.release();
    const done = await first;
    assert.equal(done.status, 200, done.text);
    assert.match(done.body.text, /^sent: /);
    assert.equal(ran(rig, "GMAIL_FORWARD_MESSAGE"), 1, "forwarded once");

    // Once it finished, a repeat gets the first answer and nothing runs again.
    const after = await runRaw(rig, "forward_email", FORWARD, { approvalId });
    assert.equal(after.status, 200, after.text);
    assert.equal(after.body.replayed, true);
    assert.equal(ran(rig, "GMAIL_FORWARD_MESSAGE"), 1, "still once");
  });
}

test("a repeat while the write itself is out at the provider is 'may or may not', and a new card for it warns", async () => {
  rig = await start({ userConcurrency: 3 });
  assert.equal((await connect(rig, "todoist")).status, 200);
  assert.equal((await on(rig, "add_todoist_task")).status, 200);
  const args = { content: "Pay rent" };
  const card = await prepare(rig, "add_todoist_task", args);
  const write = holdNext(rig, "TODOIST_CREATE_TASK");
  const first = runRaw(rig, "add_todoist_task", args, { approvalId: card.body.approvalId });
  await write.entered;

  const repeat = await runRaw(rig, "add_todoist_task", args, { approvalId: card.body.approvalId });
  assert.equal(repeat.body.error.receipt.status, "outcome_unknown", repeat.text);
  assert.equal(repeat.body.error.receipt.errorCode, "earlier_outcome_unknown");

  // The same write on a new card while the first is still out: the card says it may have gone through.
  const again = await prepare(rig, "add_todoist_task", args);
  assert.equal(again.body.earlier?.status, "outcome_unknown", again.text);
  assert.match(again.body.preview.lines.at(-1), /may have gone through/);

  write.release();
  assert.equal((await first).status, 200);
  assert.equal(ran(rig, "TODOIST_CREATE_TASK"), 1);
});

test("a repeat that asks for something else than the first try is refused, also for a write with a lookup", async () => {
  rig = await start({ userConcurrency: 3 });
  await gmail(rig, ["forward_email"]);
  const card = await prepare(rig, "forward_email", FORWARD);
  const approvalId = card.body.approvalId;
  const other = { ...FORWARD, to: "eve@evil.example" };

  // While the first try is still looking: the other request hears nothing about it.
  const lookup = holdNext(rig, "GMAIL_FETCH_EMAILS");
  const first = runRaw(rig, "forward_email", FORWARD, { approvalId });
  await lookup.entered;
  const during = await runRaw(rig, "forward_email", other, { approvalId });
  assert.equal(during.status, 403, during.text);
  assert.equal(during.body.error.receipt.status, "blocked");
  assert.equal(during.body.error.receipt.errorCode, "confirmation_required");
  lookup.release();
  assert.equal((await first).status, 200);

  // After it finished: no "forwarded to eve" from the first try's answer, and nothing runs.
  for (const changed of [other, { ...FORWARD, note: "Other words" }, { ...FORWARD, query: "from:bob" }]) {
    const res = await runRaw(rig, "forward_email", changed, { approvalId });
    assert.equal(res.status, 403, JSON.stringify(changed));
    assert.equal(res.body.error.receipt.errorCode, "confirmation_required");
    assert.equal(res.body.replayed, undefined);
    assert.ok(!/eve|forwarded/.test(res.text), res.text);
  }
  assert.equal(ran(rig, "GMAIL_FORWARD_MESSAGE"), 1);
  assert.equal(ran(rig, "GMAIL_FETCH_EMAILS"), 2, "the card's lookup and the first try's; a refused repeat looks nothing up");
});

/** Lookup-bound writes with a word of the user's in their arguments, and what the first run's receipt says. */
const LOOKUP_WRITES: { toolkit: "gmail" | "outlook" | "todoist" | "notion"; tool: string; args: Record<string, unknown>; words: RegExp }[] = [
  { toolkit: "gmail", tool: "forward_email", args: { query: "from:anna", to: "zed-recipient@example.com", note: "Quokka" }, words: /zed-recipient|Quokka|anna/ },
  { toolkit: "gmail", tool: "change_email", args: { query: "from:anna", change: "archive" }, words: /anna|Lunch/ },
  { toolkit: "outlook", tool: "move_outlook_email", args: { query: "budget", to_folder: "deleteditems" }, words: /budget/i },
  { toolkit: "outlook", tool: "forward_outlook_email", args: { query: "budget", to: "zed-recipient@example.com", note: "Quokka" }, words: /zed-recipient|Quokka|budget/i },
  { toolkit: "todoist", tool: "rename_todoist_task", args: { task_id: "t1", content: "Quokka passport" }, words: /Quokka/ },
  { toolkit: "notion", tool: "create_notion_page", args: { query: "trip", title: "Quokka list", text: "Passport" }, words: /Quokka|Passport|trip/ },
];

test("a replay of a write with a lookup repeats only what the first run recorded, never the request's words", async () => {
  rig = await start();
  for (const toolkit of new Set(LOOKUP_WRITES.map((w) => w.toolkit))) assert.equal((await connect(rig, toolkit)).status, 200, toolkit);
  for (const { tool, args, words } of LOOKUP_WRITES) {
    assert.equal((await on(rig, tool)).status, 200, tool);
    const card = await prepare(rig, tool, args);
    assert.equal(card.status, 200, `${tool}: ${card.text}`);
    const done = await runRaw(rig, tool, args, { approvalId: card.body.approvalId });
    assert.equal(done.status, 200, `${tool}: ${done.text}`);
    const word = /^([a-z]+):/.exec(done.body.text)![1];

    const again = await runRaw(rig, tool, args, { approvalId: card.body.approvalId });
    assert.equal(again.status, 200, `${tool}: ${again.text}`);
    assert.equal(again.body.replayed, true, tool);
    assert.equal(again.body.text, `${word}: ${done.body.receipt.summary} Done on the first try; nothing ran again.`, tool);
    assert.ok(!words.test(again.body.text), `${tool}: ${again.body.text}`);
    assert.equal(again.body.receipt.summary, `${done.body.receipt.summary} Answer from the first try; nothing ran again.`, tool);
    if (done.body.externalId) assert.equal(again.body.externalId, done.body.externalId, tool);
  }
  // What the server kept for those answers: fixed words, no names, titles or text.
  const kept = JSON.stringify((await rig.store.db.query("SELECT result_word, result_summary, request_digest FROM approvals")).rows);
  assert.ok(!/Quokka|zed-recipient|anna|budget|Passport/i.test(kept), kept);
});

test("an approval taken by a run that never finished (the server stopped) is 'may or may not' and never runs again", async () => {
  rig = await start();
  await gmail(rig, ["forward_email"]);
  const card = await prepare(rig, "forward_email", FORWARD);
  const userId = DEV_IDENTITIES[USER_A]!;
  const accountId = (await rig.store.getConnection(userId, "gmail"))!.connection_id;
  // Taken, as the first run does before its lookup, and then the process died.
  assert.equal(await rig.store.startApproval({
    approvalId: card.body.approvalId, userId, capability: "forward_email", accountId, argsDigest: null, requestDigest: argumentDigest(FORWARD), now: rig.clock.ms,
  }), true);
  for (let i = 0; i < 2; i++) {
    const res = await runRaw(rig, "forward_email", FORWARD, { approvalId: card.body.approvalId });
    assert.equal(res.status, 403, res.text);
    assert.equal(res.body.error.receipt.status, "outcome_unknown");
  }
  assert.equal(ran(rig, "GMAIL_FORWARD_MESSAGE"), 0);
  assert.equal(ran(rig, "GMAIL_FETCH_EMAILS"), 1, "only the card's lookup");
});

test("a run refused before its write was sent gives the yes back; a provider refusal is the first try's 'failed'", async () => {
  // A Doddy limit after the approval was taken: nothing was sent, so the same yes works once the limit allows.
  rig = await start();
  assert.equal((await connect(rig, "todoist")).status, 200);
  assert.equal((await on(rig, "add_todoist_task")).status, 200);
  const args = { content: "Water plants" };
  const card = await prepare(rig, "add_todoist_task", args);
  const limiter = rig.tools["limiter"] as { reserveToolRun: (userId: string, now: number, units?: number) => Promise<void> };
  const reserve = limiter.reserveToolRun.bind(limiter);
  let refuse = true;
  limiter.reserveToolRun = async (userId, now, units) => {
    if (refuse) throw new AppError("quota_exceeded");
    return reserve(userId, now, units);
  };
  const limited = await runRaw(rig, "add_todoist_task", args, { approvalId: card.body.approvalId });
  assert.equal(limited.status, 429, limited.text);
  assert.equal(limited.body.error.receipt.status, "blocked");
  refuse = false;
  const done = await runRaw(rig, "add_todoist_task", args, { approvalId: card.body.approvalId });
  assert.equal(done.status, 200, done.text);
  assert.equal(ran(rig, "TODOIST_CREATE_TASK"), 1);
  await rig.close();

  // The provider refused the write (rate limited, provably not run): a repeat says so with a `failed`
  // receipt, which the app tells apart from a refusal of the repeat itself (`blocked`).
  rig = await start();
  assert.equal((await connect(rig, "todoist")).status, 200);
  assert.equal((await on(rig, "add_todoist_task")).status, 200);
  const card2 = await prepare(rig, "add_todoist_task", args);
  rig.provider.setScenario(await rig.store.composioUserId(DEV_IDENTITIES[USER_A]!, rig.clock.ms), "rate_limited");
  const refused = await runRaw(rig, "add_todoist_task", args, { approvalId: card2.body.approvalId });
  assert.equal(refused.body.error.receipt.status, "failed", refused.text);
  const repeat = await runRaw(rig, "add_todoist_task", args, { approvalId: card2.body.approvalId });
  assert.equal(repeat.body.error.code, "capability_disabled");
  assert.equal(repeat.body.error.receipt.status, "failed");
  assert.equal(repeat.body.error.receipt.errorCode, "confirmation_required");
  assert.match(repeat.body.error.receipt.summary, /first try with this confirmation didn't go through/);
  // A refusal of the repeat itself (another approval nobody issued) stays `blocked`.
  const forged = await runRaw(rig, "add_todoist_task", args, { approvalId: "00000000-0000-4000-8000-000000000000" });
  assert.equal(forged.body.error.receipt.status, "blocked");
  assert.equal(forged.body.error.receipt.errorCode, "confirmation_required");
});
