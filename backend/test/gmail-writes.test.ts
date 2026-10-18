import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { CHANGE_EMAIL, CLOUD_TOOLS, evaluateToolkitGrant, TOOLKITS, TRASH_EMAIL } from "../src/tools/catalog.js";
import { ProviderError } from "../src/errors.js";
import { USER_A } from "./helpers.js";
import { connect, on, type Rig, runRaw, start } from "./toolsRig.js";

/**
 * Gmail send, reply, forward, label changes and Trash (ADR-485), each behind ASK-01: the card
 * shows exactly what will happen, the approval is bound to it, a tap runs it once, and "done" only
 * on Gmail's answer. Mock provider only: none of this has run against a real account.
 */

let rig: Rig;
afterEach(async () => rig?.close());

const prepare = (r: Rig, tool: string, args: Record<string, unknown>) => r.call("POST", "/v1/tools/prepare", { body: { tool, arguments: args } });

async function gmail(r: Rig, tools: string[], scenario?: "read_compose_only") {
  assert.equal((await connect(r, "gmail", USER_A, scenario)).status, 200);
  for (const t of tools) await on(r, t);
}

/** prepare (the card), then the tap: run with the approval. */
async function tap(r: Rig, tool: string, args: Record<string, unknown>) {
  const card = await prepare(r, tool, args);
  assert.equal(card.status, 200, card.text);
  const done = await runRaw(r, tool, args, { approvalId: card.body.approvalId });
  return { card: card.body, done };
}

test("Doddy now asks Google for send and modify, and accepts them; full access stays too broad", () => {
  const g = TOOLKITS.gmail;
  assert.ok(g.requestedScopes.includes("https://www.googleapis.com/auth/gmail.send"));
  assert.ok(g.requestedScopes.includes("https://www.googleapis.com/auth/gmail.modify"));
  assert.equal(evaluateToolkitGrant(g, [...g.requestedScopes, "openid", "email"]), "ok");
  assert.equal(evaluateToolkitGrant(g, [...g.requestedScopes, "https://mail.google.com/"]), "too_broad", "full access can delete for good");
  assert.ok(CLOUD_TOOLS.every((t) => !/DELETE|EMPTY|PURGE|BATCH/.test(t.composioSlug)), "no permanent or bulk delete");
  assert.match(g.access, /never deletes email for good/);
});

test("send: the card shows recipient, subject and the full text; the tap sends exactly that once", async () => {
  rig = await start();
  await gmail(rig, ["send_email"]);
  const args = { to: "anna@example.com", subject: "Lunch Friday", body: "Yes, 1pm works.\nSee you there." };
  const { card, done } = await tap(rig, "send_email", args);
  assert.deepEqual(card.preview.lines.slice(0, 3), ["To: anna@example.com", "Subject: Lunch Friday", "Yes, 1pm works.\nSee you there."]);
  assert.equal(card.preview.confirmLabel, "Send");
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.text, /^sent: Gmail sent the email to anna@example\.com/);
  assert.equal(done.body.externalId, "18f0b1");
  assert.deepEqual(rig.provider.executed.map((e) => [e.slug, e.arguments]), [
    ["GMAIL_SEND_EMAIL", { user_id: "me", recipient_email: "anna@example.com", subject: "Lunch Friday", body: "Yes, 1pm works.\nSee you there.", is_html: false, include_signature: false }],
  ]);
  // A repeat with the same approval answers from the first try and sends nothing more.
  const again = await runRaw(rig, "send_email", args, { approvalId: card.approvalId });
  assert.equal(again.status, 200);
  assert.equal(again.body.replayed, true);
  assert.equal(rig.provider.executed.length, 1);
});

test("send: no cc, bcc, html or attachment can be slipped in", async () => {
  rig = await start();
  await gmail(rig, ["send_email"]);
  for (const extra of [{ cc: ["x@evil.example"] }, { bcc: ["x@evil.example"] }, { is_html: true }, { attachment: "x" }, { recipient_email: "x@evil.example" }]) {
    assert.equal((await prepare(rig, "send_email", { to: "anna@example.com", subject: "s", body: "b", ...extra })).status, 400, JSON.stringify(extra));
  }
  assert.equal((await prepare(rig, "send_email", { to: "not an address", subject: "s", body: "b" })).status, 400);
  assert.equal(rig.provider.executed.length, 0);
});

test("reply: to Gmail's sender in Gmail's conversation, never an address from the agent", async () => {
  rig = await start();
  await gmail(rig, ["reply_to_email"]);
  const { card, done } = await tap(rig, "reply_to_email", { query: "from:anna", body: "Yes, 1pm works." });
  assert.deepEqual(card.preview.lines.slice(0, 3), ["To: Anna Demo <anna@demo.example>", "Re: Lunch on Friday?", "Yes, 1pm works."]);
  assert.equal(done.status, 200, done.text);
  const sent = rig.provider.executed.find((e) => e.slug === "GMAIL_REPLY_TO_THREAD")!;
  assert.deepEqual(sent.arguments, { user_id: "me", thread_id: "t2", recipient_email: "anna@demo.example", message_body: "Yes, 1pm works.", is_html: false, include_signature: false });
  assert.equal((await prepare(rig, "reply_to_email", { query: "from:anna", body: "x", to: "x@evil.example" })).status, 400);
  // An email whose sender has no address can't be replied to; nothing is sent.
  const none = await prepare(rig, "reply_to_email", { query: "newsletter", body: "x" });
  assert.equal(none.status, 404);
  assert.match(none.body.error.message, /Nothing was sent/);
});

test("forward: the card names the email from Gmail and the recipient; the message id comes from the lookup", async () => {
  rig = await start();
  await gmail(rig, ["forward_email"]);
  const { card, done } = await tap(rig, "forward_email", { query: "from:anna", to: "bob@example.com", note: "FYI" });
  assert.deepEqual(card.preview.lines.slice(0, 4), ["To: bob@example.com", "From: Anna Demo <anna@demo.example>", "Subject: Lunch on Friday?", "Your note: FYI"]);
  assert.equal(done.status, 200, done.text);
  const sent = rig.provider.executed.find((e) => e.slug === "GMAIL_FORWARD_MESSAGE")!;
  assert.deepEqual(sent.arguments, { user_id: "me", message_id: "18f0a2", recipients: ["bob@example.com"], additional_text: "FYI", include_signature: false });
  assert.equal((await prepare(rig, "forward_email", { query: "from:anna", to: "bob@example.com", message_id: "18f0a1" })).status, 400, "no id from the agent");
});

test("archive, read, star: system labels only, done only when Gmail's answer shows the change", async () => {
  rig = await start();
  await gmail(rig, ["change_email"]);
  const { card, done } = await tap(rig, "change_email", { query: "from:anna", change: "archive" });
  assert.equal(card.preview.title, "Archive this email?");
  assert.deepEqual(card.preview.lines, ["From: Anna Demo <anna@demo.example>", "Subject: Lunch on Friday?"]);
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.text, /^changed: Gmail archived the email/);
  const sent = rig.provider.executed.find((e) => e.slug === "GMAIL_ADD_LABEL_TO_EMAIL")!;
  assert.deepEqual(sent.arguments, { user_id: "me", message_id: "18f0a2", add_label_ids: [], remove_label_ids: ["INBOX"] });
  assert.equal((await prepare(rig, "change_email", { query: "from:anna", change: "delete" })).status, 400);
  assert.equal((await prepare(rig, "change_email", { query: "from:anna", change: "archive", add_label_ids: ["TRASH"] })).status, 400);
  // Gmail answers without the change: not "done" (the service turns this into "may or may not").
  const unchanged = { successful: true, error: null, data: { id: "18f0a2", labelIds: ["INBOX", "UNREAD"] } };
  const target = { kind: "email" as const, messageId: "18f0a2", threadId: "t2", to: "", toName: null, subject: "S", from: "A" };
  assert.throws(() => CHANGE_EMAIL.normalize(unchanged, { query: "q", change: "archive" }, { timeZone: "UTC" }, target), (e: unknown) => e instanceof ProviderError);
});

test("Trash: recoverable, said as such, and only when Gmail's answer shows TRASH", async () => {
  rig = await start();
  await gmail(rig, ["trash_email"]);
  const { card, done } = await tap(rig, "trash_email", { query: "from:anna" });
  assert.equal(card.preview.title, "Move this email to Trash?");
  assert.match(card.preview.lines.at(-1), /get it back from Gmail's Trash for 30 days/);
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.text, /^trashed: .*restored from Trash for 30 days/);
  assert.deepEqual(rig.provider.executed.find((e) => e.slug === "GMAIL_MOVE_TO_TRASH")!.arguments, { user_id: "me", message_id: "18f0a2" });
  const target = { kind: "email" as const, messageId: "18f0a2", threadId: "t2", to: "", toName: null, subject: "S", from: "A" };
  assert.throws(() => TRASH_EMAIL.normalize({ successful: true, error: null, data: { id: "18f0a2", labelIds: ["INBOX"] } }, { query: "q" }, { timeZone: "UTC" }, target));
});

test("a grant from before (read and compose only) still drafts and sends, but can't archive or trash", async () => {
  rig = await start();
  await gmail(rig, ["draft_email", "send_email"], "read_compose_only");
  assert.equal((await on(rig, "change_email")).status, 403);
  assert.equal((await on(rig, "trash_email")).status, 403);
  const { done } = await tap(rig, "send_email", { to: "anna@example.com", subject: "s", body: "b" });
  assert.equal(done.status, 200, "Google's compose permission includes sending");
});

test("each new Gmail write: no approval, nothing sent; a changed recipient needs a new tap", async () => {
  rig = await start();
  await gmail(rig, ["send_email", "reply_to_email", "forward_email", "change_email", "trash_email"]);
  const card = await prepare(rig, "forward_email", { query: "from:anna", to: "bob@example.com" });
  const other = await runRaw(rig, "forward_email", { query: "from:anna", to: "eve@example.com" }, { approvalId: card.body.approvalId });
  assert.equal(other.status, 403);
  assert.equal(rig.provider.executed.filter((e) => e.slug !== "GMAIL_FETCH_EMAILS").length, 0);
});

test("the server logs which Gmail permissions were granted, by name only, so a too-broad grant can be fixed", async () => {
  rig = await start();
  assert.equal((await connect(rig, "gmail", USER_A, "broad_scope")).status, 200);
  const line = rig.logs.map((l) => JSON.parse(l)).find((l) => l.event === "grant_checked");
  assert.ok(line, "a grant_checked line");
  assert.equal(line.verdict, "too_broad");
  assert.deepEqual(line.notAllowed, ["https://mail.google.com/"]);
  assert.ok(line.scopes.includes("https://www.googleapis.com/auth/gmail.readonly"));
  assert.deepEqual(Object.keys(line).sort(), ["event", "level", "notAllowed", "scopes", "toolkit", "verdict"], "nothing else: no ids, no tokens");
});
