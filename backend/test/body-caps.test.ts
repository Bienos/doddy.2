import assert from "node:assert/strict";
import { test } from "node:test";
import { cappedArray } from "../src/cappedArray.js";
import { ASSIST_MAX_BODY_BYTES } from "../src/assist.js";
import { ConversationUpload, MEMORY_MAX_NOTES, MEMORY_MAX_TURNS, MEMORY_NOTES_MAX_BODY_BYTES, MEMORY_CONVERSATION_MAX_BODY_BYTES, NotesSnapshot } from "../src/memory/contract.js";
import { THREAD_MAX_BODY_BYTES, THREAD_MAX_MESSAGES, ThreadSnapshot } from "../src/messages/contract.js";
import { LOGBOOK_MAX_BODY_BYTES } from "../src/web/logbook.js";
import { type Route, WebRoutes } from "../src/web/routes.js";
import { z } from "zod";

/**
 * Request bodies are capped before they are parsed, and a list that is too long is refused for its
 * length before any item is checked (ADR-711): the reason zod is not upgraded for its memory advisory
 * (GHSA-mrhx-c7xc-m3w5) in this change.
 */

const NOTE = { id: "0f9c7a2e-3b4d-4c5e-8f60-7a8b9c0d1e2f", text: "Buy oat milk", source: "explicit_text" };
const TURN = { role: "user", text: "Hello" };
const MESSAGE = { id: "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d", sender: "user", text: "Hi", createdAt: "2026-11-04T10:00:00Z" };
const empties = (n: number) => Array.from({ length: n }, () => ({}));

test("an over-long list is refused for its length alone: one issue, however many items it has", () => {
  for (const [name, schema, field, body, limit] of [
    ["kept notes", NotesSnapshot, "items", (items: unknown[]) => ({ items }), MEMORY_MAX_NOTES],
    ["a conversation", ConversationUpload, "turns", (turns: unknown[]) => ({ startedAt: "2026-11-04T10:00:00Z", endedAt: "2026-11-04T10:05:00Z", turns }), MEMORY_MAX_TURNS],
    ["the Messages copy", ThreadSnapshot, "messages", (messages: unknown[]) => ({ messages }), THREAD_MAX_MESSAGES],
  ] as const) {
    for (const n of [limit + 1, 20_000, 200_000]) {
      const result = schema.safeParse(body(empties(n)));
      assert.equal(result.success, false, `${name} with ${n} items`);
      assert.equal(result.error!.issues.length, 1, `${name} with ${n} items: one issue, not one per item`);
      assert.equal(result.error!.issues[0]!.code, "too_big");
      assert.deepEqual(result.error!.issues[0]!.path, [field], "the refusal still names the section (memory's refuse() reports it)");
    }
  }
});

test("a list of the right length is still checked item by item, and keeps its transforms and cross-checks", () => {
  const ok = NotesSnapshot.safeParse({ items: [{ ...NOTE, id: NOTE.id.toUpperCase() }] });
  assert.equal(ok.success, true);
  assert.equal(ok.success && ok.data.items[0]!.id, NOTE.id, "the id is lower-cased as before");
  assert.equal(NotesSnapshot.safeParse({ items: [NOTE, NOTE] }).success, false, "the same note twice is still refused");
  const bad = NotesSnapshot.safeParse({ items: [NOTE, { ...NOTE, id: "not-an-id" }, { ...NOTE, source: "nope" }] });
  assert.equal(bad.success, false);
  assert.deepEqual([...new Set(bad.error!.issues.map((i) => i.path[1]))], [1, 2], "the items that are wrong are named");
  assert.equal(NotesSnapshot.safeParse({ items: [] }).success, true, "an empty list is a list (it clears the notes)");

  const conversation = { startedAt: "2026-11-04T10:00:00Z", endedAt: "2026-11-04T10:05:00Z", turns: [TURN] };
  assert.equal(ConversationUpload.safeParse(conversation).success, true);
  const none = ConversationUpload.safeParse({ ...conversation, turns: [] });
  assert.equal(none.success, false, "a conversation needs at least one turn");
  assert.equal(none.error!.issues[0]!.code, "too_small");
  assert.equal(ConversationUpload.safeParse({ ...conversation, turns: [{ role: "robot", text: "x" }] }).success, false);

  assert.equal(ThreadSnapshot.safeParse({ messages: [MESSAGE] }).success, true);
  assert.equal(ThreadSnapshot.safeParse({ messages: [MESSAGE, MESSAGE] }).success, false, "the same message twice is still refused");
  assert.equal(ThreadSnapshot.safeParse({ messages: [{ ...MESSAGE, sender: "bot" }] }).success, false);
});

test("an over-long list of junk is refused, not read: the cross-checks after it never run on unvalidated items", () => {
  // A cross-check that reads each item (the "appears twice" check) would throw on null if it ran on a list
  // that was never validated; the refusal must stay a refusal, never an exception.
  for (const junk of [null, 7, "x", [], [[]]]) {
    const notes = NotesSnapshot.safeParse({ items: Array.from({ length: MEMORY_MAX_NOTES + 1 }, () => junk) });
    assert.equal(notes.success, false);
    assert.equal(notes.error!.issues.length, 1);
    const thread = ThreadSnapshot.safeParse({ messages: Array.from({ length: THREAD_MAX_MESSAGES + 1 }, () => junk) });
    assert.equal(thread.success, false);
    assert.equal(thread.error!.issues.length, 1);
  }
  // And a short list of junk is refused as before (also without throwing).
  assert.equal(NotesSnapshot.safeParse({ items: [null] }).success, false);
  assert.equal(ThreadSnapshot.safeParse({ messages: [null, 3] }).success, false);
  assert.equal(NotesSnapshot.safeParse({ items: "many" }).success, false);
  assert.equal(NotesSnapshot.safeParse({}).success, false);
});

test("the helper itself: bounds, order of the checks, and the output type of the items", () => {
  const schema = z.object({ n: cappedArray(z.string().transform((s) => s.length), 3, 1) });
  assert.deepEqual(schema.parse({ n: ["a", "bb"] }), { n: [1, 2] });
  const codes = (value: unknown) => {
    const result = schema.safeParse(value);
    return result.success ? "ok" : result.error.issues.map((i) => `${i.code}@${i.path.join(".")}`).join(",");
  };
  assert.equal(codes({ n: [] }), "too_small@n");
  assert.equal(codes({ n: ["a", "b", "c", "d"] }), "too_big@n");
  assert.equal(codes({ n: "abc" }), "invalid_type@n");
  assert.equal(codes({ n: [1] }), "invalid_type@n.0", "an item of the wrong kind");
  assert.equal(codes({ n: ["a", "b", "c"] }), "ok", "the limits themselves are allowed");
  // A list that is both too long and full of bad items is refused for its length only.
  assert.equal(codes({ n: [1, 2, 3, 4, 5] }), "too_big@n");
});

test("only three web routes read more than 128 KB of body, and each has a length-first list (a new big route has to say so here)", () => {
  // The router only keeps its dependencies for later, so stand-ins are enough to read its route table.
  const dummy = {} as never;
  const web = new WebRoutes(dummy, dummy, dummy, 24 * 1024, { service: dummy, chat: dummy }, dummy);
  const routes = (web as unknown as { routes: Route[] }).routes;
  assert.ok(routes.length > 20, "the whole table was read");
  const big = routes.filter((r) => (r.maxBodyBytes ?? 0) > ASSIST_MAX_BODY_BYTES).map((r) => `${r.template} ${r.maxBodyBytes}`);
  assert.deepEqual(big.sort(), [
    `PUT /v1/web/memory/conversations/:id ${MEMORY_CONVERSATION_MAX_BODY_BYTES}`,
    `PUT /v1/web/memory/notes ${MEMORY_NOTES_MAX_BODY_BYTES}`,
    `PUT /v1/web/messages ${THREAD_MAX_BODY_BYTES}`,
  ].sort());
  // Everything else: 24 KB by default, Ask Doddy 128 KB, Logbook 16 KB.
  assert.equal(ASSIST_MAX_BODY_BYTES, 128 * 1024);
  assert.equal(LOGBOOK_MAX_BODY_BYTES, 16 * 1024);
});
