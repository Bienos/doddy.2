import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { CLOUD_TOOLS, evaluateToolkitGrant, notionParagraphs, TOOLKITS } from "../src/tools/catalog.js";
import { USER_A } from "./helpers.js";
import { connect, on, type Rig, runRaw, start } from "./toolsRig.js";

/** Todoist rename, Notion create/append/trash, Drive "create a Google Doc" (ADR-488), behind ASK-01. Mock only. */

let rig: Rig;
afterEach(async () => rig?.close());

async function ready(r: Rig, toolkit: string) {
  assert.equal((await connect(r, toolkit, USER_A)).status, 200);
  for (const t of CLOUD_TOOLS.filter((x) => x.toolkit === toolkit)) assert.equal((await on(r, t.name)).status, 200, t.name);
}
async function tap(r: Rig, tool: string, args: Record<string, unknown>) {
  const card = await r.call("POST", "/v1/tools/prepare", { body: { tool, arguments: args } });
  assert.equal(card.status, 200, card.text);
  return { card: card.body, done: await runRaw(r, tool, args, { approvalId: card.body.approvalId }) };
}
const last = (r: Rig) => r.provider.executed.at(-1)!;

test("no tool deletes for good: no Todoist delete, Drive only files Doddy makes, full Drive access too broad", () => {
  assert.ok(!CLOUD_TOOLS.some((t) => /TODOIST_DELETE|DRIVE_DELETE|DRIVE_TRASH|NOTION_DELETE/.test(t.composioSlug)));
  const drive = TOOLKITS.googledrive;
  assert.ok(drive.requestedScopes.includes("https://www.googleapis.com/auth/drive.file"));
  assert.equal(evaluateToolkitGrant(drive, ["https://www.googleapis.com/auth/drive"]), "too_broad");
  assert.match(TOOLKITS.todoist.access, /can't delete tasks/);
});

test("Todoist rename: the card shows the task as Todoist has it; done only when Todoist has the new text", async () => {
  rig = await start();
  await ready(rig, "todoist");
  const { card, done } = await tap(rig, "rename_todoist_task", { task_id: "t1", content: "Renew passport and visa" });
  assert.equal(card.preview.lines[1], "New name: Renew passport and visa");
  assert.equal(done.status, 200, done.text);
  assert.deepEqual(last(rig).arguments, { task_id: "t1", content: "Renew passport and visa" });
});

test("Notion: create under the page the search found, add text, move to the trash; never an id from the agent", async () => {
  rig = await start();
  await ready(rig, "notion");
  const create = await tap(rig, "create_notion_page", { query: "trip", title: "Packing list", text: "Passport\n\nCharger" });
  assert.deepEqual(create.card.preview.lines, ["Inside: Demo trip plan", "Title: Packing list", "Passport\n\nCharger"]);
  assert.equal(create.done.status, 200, create.done.text);
  assert.equal((last(rig).arguments as any).title, "Packing list");
  assert.match(String((last(rig).arguments as any).parent_id), /^[0-9a-f-]{36}$/);

  const append = await tap(rig, "append_notion_page", { query: "trip", text: "Book the train.\n\nPack light." });
  assert.equal(append.done.status, 200, append.done.text);
  assert.equal((last(rig).arguments as any).children.length, 2);

  const bin = await tap(rig, "trash_notion_page", { query: "trip" });
  assert.match(bin.card.preview.lines[1], /restored from Notion's trash/);
  assert.equal(bin.done.status, 200, bin.done.text);
  assert.deepEqual(Object.keys(last(rig).arguments).sort(), ["archive", "page_id"]);
  assert.equal((await rig.call("POST", "/v1/tools/prepare", { body: { tool: "trash_notion_page", arguments: { query: "trip", page_id: "x" } } })).status, 400);
});

test("Notion paragraphs: blank lines split, 2000 characters at most each", () => {
  assert.equal(notionParagraphs("a\n\nb").length, 2);
  const long = notionParagraphs("x".repeat(4500));
  assert.deepEqual(long.map((p) => p.paragraph.rich_text[0]!.text.content.length), [2000, 2000, 500]);
});

test("Drive: a private Google Doc with exactly the card's name and text", async () => {
  rig = await start();
  await ready(rig, "googledrive");
  const { card, done } = await tap(rig, "create_drive_doc", { name: "Shopping ideas", text: "Milk, eggs." });
  assert.match(card.preview.lines.at(-1), /private to you/);
  assert.equal(done.status, 200, done.text);
  assert.deepEqual(last(rig).arguments, { file_name: "Shopping ideas", text_content: "Milk, eggs.", mime_type: "application/vnd.google-apps.document" });
});
