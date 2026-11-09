import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES } from "../src/auth.js";
import { MEMORY_MAX_NOTES } from "../src/memory/contract.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * Listing one page of kept notes reads one page of rows from the database, not the whole
 * collection (research item 8). Synthetic notes only; row counts are measured on pglite.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const ID_A = DEV_IDENTITIES[USER_A]!;
const ID_B = DEV_IDENTITIES[USER_B]!;
const DAY = 86_400_000;
const NOW = "2026-10-22T10:00:00.000Z";
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const ago = (days: number) => new Date(Date.parse(NOW) - days * DAY).toISOString();

/** Counts the ciphertext rows every query on the store's database hands back. */
function countRows(r: WebRig) {
  const db = r.store.db as unknown as { query: (sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }> };
  const original = db.query.bind(db);
  const seen: { sql: string; rows: number }[] = [];
  db.query = async (sql, params) => {
    const res = await original(sql, params);
    seen.push({ sql, rows: res.rows.length });
    return res;
  };
  return {
    noteRowsFetched: () => seen.filter((s) => /FROM memory_notes/.test(s.sql) && /ciphertext/.test(s.sql)).reduce((sum, s) => sum + s.rows, 0),
    reset: () => void (seen.length = 0),
  };
}

async function seed(r: WebRig, n: number, o: { sameDay?: boolean } = {}) {
  assert.equal((await r.call("PUT", "/v1/web/memory/state", { token: USER_A, body: { notes: true, conversations: false } })).status, 200);
  const items = Array.from({ length: n }, (_, i) => ({
    id: uuid(i + 1),
    text: `Synthetic note ${i + 1} about topic ${i % 7}`,
    source: "explicit_voice",
    capturedAt: o.sameDay ? ago(1) : ago(1 + i * 0.01),
  }));
  const res = await r.call("PUT", "/v1/web/memory/notes", { token: USER_A, body: { items } });
  assert.equal(res.status, 200, res.text);
  return items;
}

test("a 100-note page reads 100 note rows, not the whole collection", async () => {
  rig = await startWeb();
  await seed(rig, 400);
  const counter = countRows(rig);
  const res = await rig.call("GET", "/v1/web/memory/notes?limit=100&offset=0", { token: USER_A });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.notes.length, 100);
  assert.equal(res.body.total, 400);
  assert.equal(res.body.nextOffset, 100);
  assert.equal(counter.noteRowsFetched(), 100, "rows fetched from memory_notes for one page");
});

test("pages walk the whole list newest first with no gaps or repeats, ties broken by id", async () => {
  rig = await startWeb();
  const items = await seed(rig, 250, { sameDay: true }); // every note ties on capturedAt
  const seenIds: string[] = [];
  let offset: number | null = 0;
  while (offset !== null) {
    const res: any = await rig.call("GET", `/v1/web/memory/notes?limit=100&offset=${offset}`, { token: USER_A });
    assert.equal(res.body.total, 250);
    seenIds.push(...res.body.notes.map((n: { id: string }) => n.id));
    offset = res.body.nextOffset;
  }
  assert.deepEqual(seenIds, items.map((i) => i.id).sort());
  const tail = await rig.call("GET", "/v1/web/memory/notes?limit=100&offset=200", { token: USER_A });
  assert.equal(tail.body.notes.length, 50);
  assert.equal(tail.body.nextOffset, null);
  const past = await rig.call("GET", "/v1/web/memory/notes?limit=100&offset=900", { token: USER_A });
  assert.deepEqual({ n: past.body.notes.length, total: past.body.total, next: past.body.nextOffset }, { n: 0, total: 250, next: null });
});

test("notes without a capture time sort last, and the page order matches the full-list order", async () => {
  rig = await startWeb();
  assert.equal((await rig.call("PUT", "/v1/web/memory/state", { token: USER_A, body: { notes: true, conversations: false } })).status, 200);
  const items = [
    { id: uuid(3), text: "undated c", source: "explicit_voice" },
    { id: uuid(1), text: "dated old", source: "explicit_voice", capturedAt: ago(30) },
    { id: uuid(2), text: "undated b", source: "explicit_voice" },
    { id: uuid(4), text: "dated new", source: "explicit_voice", capturedAt: ago(1) },
  ];
  await rig.call("PUT", "/v1/web/memory/notes", { token: USER_A, body: { items } });
  const full = (await rig.call("GET", "/v1/web/memory/notes?limit=100", { token: USER_A })).body.notes.map((n: { id: string }) => n.id);
  assert.deepEqual(full, [uuid(4), uuid(1), uuid(2), uuid(3)]);
  const pages: string[] = [];
  for (const offset of [0, 1, 2, 3]) pages.push(...(await rig.call("GET", `/v1/web/memory/notes?limit=1&offset=${offset}`, { token: USER_A })).body.notes.map((n: { id: string }) => n.id));
  assert.deepEqual(pages, full);
});

test("another account's notes are never in the page, the count or the rows fetched", async () => {
  rig = await startWeb();
  await seed(rig, 30);
  assert.equal((await rig.call("PUT", "/v1/web/memory/state", { token: USER_B, body: { notes: true, conversations: false } })).status, 200);
  const theirs = Array.from({ length: 5 }, (_, i) => ({ id: uuid(1000 + i), text: `B-only note ${i}`, source: "explicit_voice", capturedAt: ago(0.5) }));
  assert.equal((await rig.call("PUT", "/v1/web/memory/notes", { token: USER_B, body: { items: theirs } })).status, 200);
  const counter = countRows(rig);
  const a = await rig.call("GET", "/v1/web/memory/notes?limit=100", { token: USER_A });
  assert.equal(a.body.total, 30);
  assert.equal(a.body.notes.length, 30);
  assert.ok(a.body.notes.every((n: { text: string }) => !n.text.startsWith("B-only")));
  assert.equal(counter.noteRowsFetched(), 30);
  const b = await rig.call("GET", "/v1/web/memory/notes?limit=100", { token: USER_B });
  assert.deepEqual(b.body.notes.map((n: { id: string }) => n.id).sort(), theirs.map((t) => t.id).sort());
  assert.equal(b.body.total, 5);
  assert.equal((await rig.call("GET", "/v1/web/memory/notes?limit=100&offset=30", { token: USER_A })).body.notes.length, 0);
  assert.equal((await rig.store.memoryNoteRows(ID_B)).length, 5);
  assert.equal((await rig.store.memoryNoteRows(ID_A)).length, 30);
});

test("a row that no longer decrypts still counts in the total and is reported as unreadable", async () => {
  rig = await startWeb();
  await seed(rig, 3);
  const rows = await rig.store.memoryNoteRows(ID_A);
  await rig.store.replaceMemoryNotes(ID_A, [...rows, { note_id: uuid(99), key_version: 1, ciphertext: Buffer.from("not a ciphertext"), captured_at: null, received_at: 1 }], 1);
  const res = await rig.call("GET", "/v1/web/memory/notes?limit=100", { token: USER_A });
  assert.equal(res.body.total, 4);
  assert.equal(res.body.notes.length, 3);
  assert.equal(res.body.unreadable, 1);
});

// Measurement: opt in with DODDY_BENCH=1. Numbers are measured on pglite (in-process), not production.
test("bench: page vs search at the 5,000-note ceiling (set DODDY_BENCH=1)", { skip: process.env.DODDY_BENCH !== "1" }, async () => {
  rig = await startWeb();
  await seed(rig, MEMORY_MAX_NOTES);
  const counter = countRows(rig);
  const time = async (label: string, fn: () => Promise<unknown>, runs = 5) => {
    const ms: number[] = [];
    let rows = 0;
    for (let i = 0; i < runs; i += 1) {
      counter.reset();
      const t = performance.now();
      await fn();
      ms.push(performance.now() - t);
      rows = counter.noteRowsFetched();
    }
    ms.sort((a, b) => a - b);
    console.log(`BENCH ${label}: median ${ms[Math.floor(runs / 2)]!.toFixed(1)} ms, min ${ms[0]!.toFixed(1)} ms, max ${ms[runs - 1]!.toFixed(1)} ms, note rows fetched ${rows}`);
  };
  await time("list page of 100 (offset 0)", () => rig!.call("GET", "/v1/web/memory/notes?limit=100&offset=0", { token: USER_A }));
  await time("list page of 100 (offset 4900)", () => rig!.call("GET", "/v1/web/memory/notes?limit=100&offset=4900", { token: USER_A }));
  await time("search over all notes", () => rig!.call("POST", "/v1/web/memory/notes/search", { token: USER_A, body: { q: "topic 3" } }));
});
