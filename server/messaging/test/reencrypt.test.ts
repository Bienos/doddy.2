// Rotating MEMORY_ENCRYPTION_KEY: every encrypted column is known to the re-encryption, rows are rewritten to the
// current version and read back, rows that can't be read are counted and left, and scripts/reencrypt.mjs reports
// counts only. Real Postgres.
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import { clearContactOptOut, contactOptedOut, recordContactOptOut } from "../src/contactTexts.js";
import { TextCipher } from "../src/crypto.js";
import type { Db } from "../src/db.js";
import { saveNote } from "../src/inbox.js";
import { enqueue } from "../src/outbox.js";
import { recapAad } from "../src/phoneRecaps.js";
import { countByVersion, ENCRYPTED_COLUMNS, reencryptAll } from "../src/reencrypt.js";
import { dbSkip, freshDb, TEST_DATABASE_URL, testApp } from "./helpers.js";

interface Script {
  run(argv: string[], io?: { env?: Record<string, string | undefined>; stdout?: (s: string) => void; stderr?: (s: string) => void }): Promise<number>;
}
const script = (await import(new URL("../../scripts/reencrypt.mjs", import.meta.url).href)) as Script;

const KEY_1 = Buffer.alloc(32, 11);
const KEY_2 = Buffer.alloc(32, 22);
const v1 = new TextCipher(KEY_1);
const v2only = new TextCipher(KEY_2, 2);
const ring = new TextCipher(KEY_2, 2, { key: KEY_1, version: 1 });

describe("re-encrypting to a new key version against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  test("every encrypted column in the schema is one the re-encryption rewrites", async () => {
    const { rows } = await db.query<{ c: string }>(
      `SELECT table_name || '.' || column_name AS c FROM information_schema.columns
       WHERE table_schema = 'public' AND data_type = 'bytea' AND column_name LIKE '%ciphertext' ORDER BY 1`);
    assert.deepEqual(ENCRYPTED_COLUMNS.map((c) => `${c.table}.${c.column}`).sort(), rows.map((r) => r.c));
  });

  test("rows move to the current version, read back; unreadable ones are counted and left; a second run does nothing", async () => {
    const w = await testApp(db, { cipher: v2only });
    const r = await w.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId: acct, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    // Written by the server before the rotation, with version 1.
    const noteId = (await saveNote(db, v1, acct, "a note from a call", "call"))!;
    const memoryId = randomUUID();
    await db.query("INSERT INTO memory_copies (account_id, memory_id, key_version, ciphertext) VALUES ($1, $2, 1, $3)",
      [acct, memoryId, v1.encrypt("the keys are with Lucja", `${acct}:memory:${memoryId}`)]);
    const [queued] = await enqueue(db, acct, ["push"], "your digest is ready", new Date(Date.now() + 3600_000), "rotation-1", { cipher: v1 });
    const callId = randomUUID();
    await db.query("INSERT INTO calls (id, account_id, direction, status) VALUES ($1, $2, 'inbound', 'completed')", [callId, acct]);
    await db.query("INSERT INTO phone_recaps (call_id, account_id, key_version, ciphertext) VALUES ($1, $2, 1, $3)", [callId, acct,
      v1.encrypt(JSON.stringify({ discussed: ["Thursday"], agreed: [], to_do: [], endedAt: "2026-11-12T10:00:00Z", durationSecs: 60, direction: "inbound" }), recapAad(acct, callId))]);
    const watchId = randomUUID();
    await db.query(
      `INSERT INTO file_watches (id, account_id, document_id, link_ciphertext, language, created_at, expires_at)
       VALUES ($1, $2, 'abcdefghijklmnopqrstuvwx', $3, 'en', now(), now() + interval '1 hour')`,
      [watchId, acct, v1.encrypt("https://docs.example.test/f/abc", `${acct}:file-watch:${watchId}`)]);
    // Already on the new version: untouched. Broken: counted, never rewritten.
    const newNote = (await saveNote(db, ring, acct, "written after the rotation", "text"))!;
    const brokenId = randomUUID();
    const broken = randomBytes(48);
    await db.query("INSERT INTO call_notes (id, account_id, key_version, ciphertext, source) VALUES ($1, $2, 1, $3, 'call')", [brokenId, acct, broken]);
    const before = (await db.query("SELECT ciphertext FROM call_notes WHERE id = $1", [newNote])).rows[0].ciphertext as Buffer;

    assert.deepEqual((await countByVersion(db)).filter((c) => c.total > 0).map((c) => [`${c.table}.${c.column}`, c.versions]), [
      ["memory_copies.ciphertext", { 1: 1 }],
      ["call_notes.ciphertext", { 1: 2, 2: 1 }],
      ["outbound_messages.body_ciphertext", { 1: 1 }],
      ["file_watches.link_ciphertext", { unknown: 1 }],
      ["phone_recaps.ciphertext", { 1: 1 }],
    ]);

    const report = await reencryptAll(db, ring, { batch: 2 });
    const of = (c: string) => report.find((x) => `${x.table}.${x.column}` === c)!;
    assert.deepEqual(of("call_notes.ciphertext"), { table: "call_notes", column: "ciphertext", rewritten: 1, unreadable: 1, left: 1 });
    for (const c of ["memory_copies.ciphertext", "outbound_messages.body_ciphertext", "phone_recaps.ciphertext", "file_watches.link_ciphertext"]) {
      assert.deepEqual([of(c).rewritten, of(c).unreadable, of(c).left], [1, 0, 0], c);
    }

    // Everything now reads with the new key alone, through the server's own read paths too.
    const strict = async (sql: string, id: string, aad: string) => {
      const row = (await db.query(sql, [id])).rows[0];
      return v2only.decrypt(row.ct, aad, row.v ?? 2);
    };
    assert.equal(await strict("SELECT ciphertext AS ct, key_version AS v FROM call_notes WHERE id = $1", noteId, `${acct}:note:${noteId}`), "a note from a call");
    assert.equal(await strict("SELECT body_ciphertext AS ct, body_key_version AS v FROM outbound_messages WHERE id = $1", queued!.id, `${acct}:outbound:${queued!.id}`), "your digest is ready");
    assert.equal(await strict("SELECT link_ciphertext AS ct, NULL AS v FROM file_watches WHERE id = $1", watchId, `${acct}:file-watch:${watchId}`), "https://docs.example.test/f/abc");
    assert.equal(await strict("SELECT ciphertext AS ct, key_version AS v FROM memory_copies WHERE memory_id = $1", memoryId, `${acct}:memory:${memoryId}`), "the keys are with Lucja");
    const recaps = (await w.app.inject({ method: "GET", url: "/v1/calls/recaps", headers: { authorization: `Bearer ${deviceToken}` } })).json();
    assert.deepEqual([recaps.recaps.map((x: { discussed: string[] }) => x.discussed), recaps.unreadable], [[["Thursday"]], []]);
    assert.deepEqual((await db.query("SELECT ciphertext FROM call_notes WHERE id = $1", [newNote])).rows[0].ciphertext, before, "already current: untouched");
    assert.deepEqual((await db.query("SELECT key_version, ciphertext FROM call_notes WHERE id = $1", [brokenId])).rows[0], { key_version: 1, ciphertext: broken });

    const again = await reencryptAll(db, ring, { batch: 2 });
    assert.equal(again.reduce((n, x) => n + x.rewritten, 0), 0, "nothing left to rewrite");
    assert.deepEqual(again.filter((x) => x.left > 0).map((x) => [`${x.table}.${x.column}`, x.left, x.unreadable]), [["call_notes.ciphertext", 1, 1]]);
    await w.app.close();
  });

  test("scripts/reencrypt.mjs: dry run first, counts only, and an exit code that says whether anything is left", async () => {
    await db.query("DELETE FROM call_notes; DELETE FROM memory_copies; DELETE FROM outbound_messages; DELETE FROM file_watches; DELETE FROM phone_recaps");
    const w = await testApp(db);
    const { accountId: acct } = (await w.app.inject({ method: "POST", url: "/v1/accounts" })).json() as { accountId: string };
    await saveNote(db, v1, acct, "secret words in a note", "call");
    const env = {
      DATABASE_URL: TEST_DATABASE_URL, MEMORY_ENCRYPTION_KEY: KEY_2.toString("base64"), MEMORY_ENCRYPTION_KEY_VERSION: "2",
      MEMORY_ENCRYPTION_KEY_PREVIOUS: KEY_1.toString("base64"), MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION: "1",
    };
    const io = () => {
      const out: string[] = [];
      return { out, io: { env, stdout: (s: string) => out.push(s), stderr: (s: string) => out.push(s) } };
    };
    const noSecrets = (lines: string[]) => {
      const all = lines.join("\n");
      for (const s of ["secret words", KEY_1.toString("base64"), KEY_2.toString("base64"), "doddy:doddy"]) assert.ok(!all.includes(s), s);
    };

    const dry = io();
    assert.equal(await script.run(["--dry-run"], dry.io), 1, "a row is still on version 1");
    assert.match(dry.out.join("\n"), /call_notes\.ciphertext: .*version 1: 1/);
    assert.equal((await db.query("SELECT key_version FROM call_notes")).rows[0].key_version, 1, "a dry run changes nothing");
    noSecrets(dry.out);

    const real = io();
    assert.equal(await script.run([], real.io), 0);
    assert.match(real.out.join("\n"), /call_notes\.ciphertext: 1 rewritten, 0 unreadable, 0 left/);
    assert.equal((await db.query("SELECT key_version FROM call_notes")).rows[0].key_version, 2);
    noSecrets(real.out);

    // Without the previous key nothing on version 1 can be read: counted, and the exit code says so.
    await saveNote(db, v1, acct, "another one", "call");
    const missing = io();
    missing.io.env = { ...env, MEMORY_ENCRYPTION_KEY_PREVIOUS: undefined as unknown as string };
    assert.equal(await script.run([], missing.io), 1);
    assert.match(missing.out.join("\n"), /1 unreadable/);
    assert.match(missing.out.join("\n"), /MEMORY_ENCRYPTION_KEY_PREVIOUS/);
    assert.equal(await script.run(["--batch", "0"], io().io), 64, "a bad option is a usage error");
    await w.app.close();
  });
  test("a contact's STOP survives a rotation: found under either key while both are set, re-hashed, then found with the new key alone", async () => {
    await db.query("DELETE FROM contact_text_opt_outs");
    const number = "+48600999001";
    await recordContactOptOut(db, v1, number);
    assert.equal(await contactOptedOut(db, v2only, number), false, "a hash made with the old key is not the new key's hash");
    assert.equal(await contactOptedOut(db, ring, number), true, "while both keys are set the old hash still counts");
    // The same number says STOP again during the rotation: a second row, under the new key.
    await recordContactOptOut(db, ring, number);
    assert.equal((await db.query("SELECT count(*)::int AS n FROM contact_text_opt_outs")).rows[0].n, 2);

    const report = await reencryptAll(db, ring);
    const r = report.find((x) => x.table === "contact_text_opt_outs")!;
    assert.deepEqual([r.column, r.rewritten, r.unreadable, r.left], ["number_ciphertext", 1, 0, 0]);
    const { rows } = await db.query("SELECT key_version, number_ciphertext FROM contact_text_opt_outs");
    assert.equal(rows.length, 1, "one row per number");
    assert.equal(rows[0].key_version, 2);
    assert.ok(!(rows[0].number_ciphertext as Buffer).toString("latin1").includes("600999001"), "the number is kept only encrypted");
    assert.equal(await contactOptedOut(db, v2only, number), true, "after the rewrite the new key alone finds it: the STOP is not forgotten");
    assert.equal(await contactOptedOut(db, v2only, "+48600999002"), false);

    await clearContactOptOut(db, v2only, number);
    assert.equal(await contactOptedOut(db, ring, number), false, "START clears it");
  });
});
