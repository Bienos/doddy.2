import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES } from "../src/auth.js";
import { AppError } from "../src/errors.js";
import { MemoryCipher } from "../src/memory/crypto.js";
import { THREAD_MAX_MESSAGES } from "../src/messages/contract.js";
import { ThreadService } from "../src/messages/service.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * Messages on the web (owner, 28 Oct 2026, "sync always on"): the iPhone sends its thread as a snapshot, the
 * browser reads it, only the iPhone can change or delete it, and it is encrypted at rest.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const ID_A = DEV_IDENTITIES[USER_A]!;
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const msg = (n: number, sender: "user" | "doddy", text: string, extra: Record<string, unknown> = {}) => ({
  id: uuid(n), sender, text, createdAt: `2026-10-22T09:0${n % 10}:00.000Z`, ...extra,
});
const thread = [
  msg(2, "doddy", "Urodziny Anny są 14 marca."),
  msg(1, "user", "Kiedy są urodziny Anny?", { delivery: "sent" }),
  msg(3, "user", "Co to za paragon?", { hasPhoto: true, delivery: "sent" }),
  msg(4, "doddy", "Plan bety", { file: { name: "Plan bety", kind: "deck" } }),
];
const put = (r: WebRig, body: unknown, token = USER_A) => r.call("PUT", "/v1/web/messages", { token, body });

test("the iPhone sends the thread; the browser reads it oldest first; nothing is readable in the database", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  assert.deepEqual((await rig.call("GET", "/v1/web/messages", { cookie })).body, { messages: [], syncedAt: null });

  const sent = await put(rig, { messages: thread });
  assert.equal(sent.status, 200, sent.text);
  assert.deepEqual(sent.body, { stored: true, count: 4 });

  const read = await rig.call("GET", "/v1/web/messages", { cookie });
  assert.equal(read.status, 200, read.text);
  assert.deepEqual(read.body.messages.map((m: { text: string }) => m.text), [
    "Kiedy są urodziny Anny?", "Urodziny Anny są 14 marca.", "Co to za paragon?", "Plan bety",
  ]);
  assert.equal(read.body.messages[2].hasPhoto, true);
  assert.deepEqual(read.body.messages[3].file, { name: "Plan bety", kind: "deck" });
  assert.equal(typeof read.body.syncedAt, "string");

  const row = await rig.store.messageThread(ID_A);
  assert.ok(row);
  assert.ok(!row.ciphertext.toString("utf8").includes("Anny"), "encrypted at rest");
  assert.ok(rig.logs.every((line) => !line.includes("Anny")), "the log has counts only");
});

test("a new snapshot replaces the old one, so a message deleted on the iPhone is gone here too; an empty one deletes", async () => {
  rig = await startWeb();
  await put(rig, { messages: thread });
  await put(rig, { messages: thread.slice(0, 2) });
  assert.equal((await rig.call("GET", "/v1/web/messages", { token: USER_A })).body.messages.length, 2);
  await put(rig, { messages: [] });
  assert.equal(await rig.store.messageThread(ID_A), null);
});

test("only the iPhone sends or deletes; a browser only reads", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  await put(rig, { messages: thread });
  for (const method of ["PUT", "DELETE"]) {
    const res = await rig.call(method, "/v1/web/messages", { cookie, browser: true, body: { messages: [] } });
    assert.ok(res.status === 403 || res.status === 401 || res.status === 405, `${method} from a browser: ${res.status} ${res.text}`);
  }
  assert.ok(await rig.store.messageThread(ID_A), "still there");
});

test("deleting from the iPhone removes the copy and says so only once it reads back gone", async () => {
  rig = await startWeb();
  await put(rig, { messages: thread });
  const res = await rig.call("DELETE", "/v1/web/messages", { token: USER_A });
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.body, { deleted: true });
  assert.equal(await rig.store.messageThread(ID_A), null);
});

test("each person sees only their own thread", async () => {
  rig = await startWeb();
  await put(rig, { messages: thread });
  const other = await rig.call("GET", "/v1/web/messages", { token: USER_B });
  assert.deepEqual(other.body, { messages: [], syncedAt: null });
});

test("anything outside the shape is refused and nothing is stored", async () => {
  rig = await startWeb();
  const bad = [
    { messages: [msg(1, "user", "   ")] },
    { messages: [msg(1, "user", "x"), msg(1, "doddy", "y")] },
    { messages: [{ ...msg(1, "user", "x"), photo: "base64…" }] },
    { messages: [msg(1, "user", "x", { file: { name: "a", kind: "deck", url: "https://x" } })] },
    { messages: [{ ...msg(1, "user", "x"), sender: "system" }] },
    { messages: Array.from({ length: THREAD_MAX_MESSAGES + 1 }, (_, i) => msg(i, "user", "x")) },
    { items: [] },
  ];
  for (const body of bad) {
    const res = await put(rig, body);
    assert.ok(res.status === 400 || res.status === 413, `${JSON.stringify(body).slice(0, 80)}: ${res.status}`);
  }
  assert.equal(await rig.store.messageThread(ID_A), null);
});

test("a thread over the most is refused before any message in it is read; one at the most is stored", async () => {
  rig = await startWeb();
  let touched = 0;
  const trap = new Proxy({}, { get: () => { touched += 1; return undefined; } });
  const service = new ThreadService({ store: rig.store, cipher: new MemoryCipher(Buffer.alloc(32, 5)) });
  await assert.rejects(service.replace(ID_A, { messages: Array.from({ length: THREAD_MAX_MESSAGES + 1 }, () => trap) }), (e: unknown) => e instanceof AppError && e.code === "invalid_request");
  assert.equal(touched, 0, "no message was looked at");

  const over = await put(rig, { messages: Array.from({ length: THREAD_MAX_MESSAGES + 1 }, (_, i) => msg(i, "user", "x")) });
  assert.equal(over.status, 400, over.text.slice(0, 200));
  assert.equal(over.body.error.code, "invalid_request");
  assert.equal(over.body.error.message, "That wasn't valid (messages). Nothing was stored.");
  const atMost = await put(rig, { messages: Array.from({ length: THREAD_MAX_MESSAGES }, (_, i) => msg(i, "user", "x")) });
  assert.equal(atMost.status, 200, atMost.text.slice(0, 200));
  assert.equal((await rig.call("GET", "/v1/web/messages", { token: USER_A })).body.messages.length, THREAD_MAX_MESSAGES);
});

test("without the key the routes say it isn't set up and store nothing", async () => {
  rig = await startWeb({ memoryKey: null });
  const res = await put(rig, { messages: thread });
  assert.equal(res.status, 503, res.text);
  assert.equal(await rig.store.messageThread(ID_A), null);
});
