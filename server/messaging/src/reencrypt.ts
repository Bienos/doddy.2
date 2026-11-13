// Rewrites every encrypted row to the current key version, for a rotation of MEMORY_ENCRYPTION_KEY (README,
// "Rotating MEMORY_ENCRYPTION_KEY"; run by scripts/reencrypt.mjs). Each row is opened with the key of the version
// stored on it, sealed again with the current key under the same associated data, written with the current version,
// and read back in the same transaction: a batch whose read-back differs is rolled back, so nothing is half-written.
// A row that can't be opened (its version has no key here, or it is damaged) is counted and left as it is. Counts and
// names only are reported, never content. Safe beside the running server: rows are locked while they are rewritten
// (FOR UPDATE SKIP LOCKED), and the server opens either version while both keys are set.
import type pg from "pg";
import type { TextCipher } from "./crypto.js";
import { inTransaction, type Db } from "./db.js";
import { payloadAad as deliveryAad } from "./delivery/deliveries.js";
import { contentAad as errandAad, resultAad as errandResultAad } from "./errands/context.js";
import { linkAad } from "./fileWatches.js";
import { bodyAad } from "./outbox.js";
import { recapAad } from "./phoneRecaps.js";
import { reasonAad } from "./scheduledCalls.js";
import { fileAad, jobAad, resultAad as studioResultAad } from "./studio/context.js";
import { payloadAad as callCaseAad } from "./taskCalls/payload.js";
import { inputAad, liveAad, resultAad as callResultAad } from "./taskCalls/service.js";
import { contentAad as watchAad } from "./watches/context.js";
import { wordsAad as dealWatchAad } from "./deals/dealWatches.js";

type Row = Record<string, unknown> & { account_id: string };
const s = (v: unknown) => String(v);

export interface EncryptedColumn {
  table: string;
  column: string;
  /** The column holding the key version; null where none is stored (file_watches: every row is tried). */
  version: string | null;
  /** The primary key, in order. */
  key: string[];
  /** The account a row belongs to, as SQL over `t` (the table) and any join. */
  account: string;
  join?: string;
  aad(row: Row): string;
}

/** Every encrypted column of the schema, with the associated data the server binds it to (test/reencrypt.test.ts). */
export const ENCRYPTED_COLUMNS: EncryptedColumn[] = [
  { table: "memory_copies", column: "ciphertext", version: "key_version", key: ["account_id", "memory_id"], account: "t.account_id",
    aad: (r) => `${r.account_id}:memory:${s(r.memory_id)}` }, // inbox.ts, routes/calls.ts
  { table: "call_notes", column: "ciphertext", version: "key_version", key: ["id"], account: "t.account_id",
    aad: (r) => `${r.account_id}:note:${s(r.id)}` }, // inbox.ts
  { table: "outbound_messages", column: "body_ciphertext", version: "body_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => bodyAad(r.account_id, s(r.id)) },
  { table: "call_cases", column: "payload_ciphertext", version: "payload_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => callCaseAad(r.account_id, s(r.id)) },
  { table: "call_live_lines", column: "ciphertext", version: "key_version", key: ["attempt_id", "transcription_sid", "seq"], account: "t.account_id",
    aad: (r) => liveAad(r.account_id, s(r.attempt_id), s(r.transcription_sid), Number(r.seq)) },
  { table: "call_results", column: "input_ciphertext", version: "input_key_version", key: ["attempt_id"], account: "t.account_id",
    aad: (r) => inputAad(r.account_id, s(r.attempt_id)) },
  { table: "call_results", column: "ciphertext", version: "key_version", key: ["attempt_id"], account: "t.account_id",
    aad: (r) => callResultAad(r.account_id, s(r.attempt_id)) },
  { table: "errands", column: "content_ciphertext", version: "content_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => errandAad(r.account_id, s(r.id)) },
  { table: "errands", column: "result_ciphertext", version: "result_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => errandResultAad(r.account_id, s(r.id)) },
  { table: "price_watches", column: "content_ciphertext", version: "content_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => watchAad(r.account_id, s(r.id)) },
  { table: "studio_items", column: "job_ciphertext", version: "job_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => jobAad(r.account_id, s(r.id)) },
  { table: "studio_items", column: "result_ciphertext", version: "result_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => studioResultAad(r.account_id, s(r.id)) },
  { table: "studio_files", column: "ciphertext", version: "key_version", key: ["item_id", "name"], account: "i.account_id",
    join: "JOIN studio_items i ON i.id = t.item_id", aad: (r) => fileAad(r.account_id, s(r.item_id), s(r.name)) },
  { table: "scheduled_calls", column: "reason_ciphertext", version: "reason_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => reasonAad(r.account_id, s(r.id)) },
  { table: "file_watches", column: "link_ciphertext", version: null, key: ["id"], account: "t.account_id",
    aad: (r) => linkAad(r.account_id, s(r.id)) },
  { table: "phone_recaps", column: "ciphertext", version: "key_version", key: ["call_id"], account: "t.account_id",
    aad: (r) => recapAad(r.account_id, s(r.call_id)) },
  { table: "deliveries", column: "payload_ciphertext", version: "payload_key_version", key: ["id"], account: "t.account_id",
    aad: (r) => deliveryAad(r.account_id, s(r.id)) },
  { table: "deal_watches", column: "words_ciphertext", version: "key_version", key: ["id"], account: "t.account_id",
    aad: (r) => dealWatchAad(r.account_id, s(r.id)) },
];

export interface ColumnReport {
  table: string;
  column: string;
  /** Rows rewritten to the current version and read back. */
  rewritten: number;
  /** Rows that couldn't be opened with the key of their version (or, without a version column, with either key). */
  unreadable: number;
  /** Rows still on another version after the run (for file_watches: the unreadable ones). */
  left: number;
}

export interface ColumnCount {
  table: string;
  column: string;
  total: number;
  /** Rows per stored version; `unknown` for a table that stores none. */
  versions: Record<string, number>;
}

const BATCH_DEFAULT = 100;

/** Rows per key version in every encrypted column: what a rotation still has to rewrite. Changes nothing. */
export async function countByVersion(db: Db): Promise<ColumnCount[]> {
  const out: ColumnCount[] = [];
  for (const c of ENCRYPTED_COLUMNS) {
    const { rows } = await db.query<{ v: string; n: number }>(c.version
      ? `SELECT t.${c.version}::text AS v, count(*)::int AS n FROM ${c.table} t WHERE t.${c.column} IS NOT NULL GROUP BY t.${c.version} ORDER BY t.${c.version}`
      : `SELECT 'unknown' AS v, count(*)::int AS n FROM ${c.table} t WHERE t.${c.column} IS NOT NULL HAVING count(*) > 0`);
    out.push({
      table: c.table, column: c.column, total: rows.reduce((n, r) => n + r.n, 0),
      versions: Object.fromEntries(rows.map((r) => [r.v, r.n])),
    });
  }
  return out;
}

/**
 * Rewrites the rows of every encrypted column that are not on the current key version, `batch` rows per transaction.
 * Returns one report per column. Throws (with that batch rolled back) only when a read-back differs, which would
 * mean the database didn't keep what was written.
 */
export async function reencryptAll(db: Db, cipher: TextCipher, opts: { batch?: number } = {}): Promise<ColumnReport[]> {
  const batch = opts.batch ?? BATCH_DEFAULT;
  if (!Number.isInteger(batch) || batch < 1) throw new Error("batch must be a whole number above 0");
  const reports: ColumnReport[] = [];
  for (const c of ENCRYPTED_COLUMNS) reports.push(await reencryptColumn(db, cipher, c, batch));
  return reports;
}

async function reencryptColumn(db: Db, cipher: TextCipher, c: EncryptedColumn, batch: number): Promise<ColumnReport> {
  const report: ColumnReport = { table: c.table, column: c.column, rewritten: 0, unreadable: 0, left: 0 };
  const keyCols = c.key.map((k) => `t.${k}`).join(", ");
  const keyWhere = c.key.map((k, i) => `${k} = $${i + 1}`).join(" AND ");
  // Keyset paging: rows left behind (unreadable) are passed over, never read again in this run.
  let after: unknown[] | undefined;
  for (;;) {
    const params: unknown[] = [];
    const where = [`t.${c.column} IS NOT NULL`];
    if (c.version) {
      params.push(cipher.keyVersion);
      where.push(`t.${c.version} <> $${params.length}`);
    }
    if (after) {
      const marks = after.map((v) => { params.push(v); return `$${params.length}`; });
      where.push(`(${keyCols}) > (${marks.join(", ")})`);
    }
    params.push(batch);
    const rows = await inTransaction(db, async (tx) => {
      const { rows: claimed } = await tx.query<Row>(
        `SELECT ${keyCols}, ${c.account} AS account_id, t.${c.column} AS ct${c.version ? `, t.${c.version} AS v` : ""}
         FROM ${c.table} t ${c.join ?? ""} WHERE ${where.join(" AND ")}
         ORDER BY ${keyCols} LIMIT $${params.length} FOR UPDATE OF t SKIP LOCKED`, params);
      for (const row of claimed) {
        const aad = c.aad(row);
        const blob = row.ct as Buffer;
        const opened = openRow(cipher, blob, aad, c.version ? Number(row.v) : null);
        if (opened === "unreadable") { report.unreadable++; continue; }
        if (opened === "current") continue; // file_watches: already on the current key
        await rewrite(tx, cipher, c, row, aad, opened, keyWhere);
        report.rewritten++;
      }
      return claimed;
    });
    if (rows.length > 0) after = c.key.map((k) => rows[rows.length - 1]![k]);
    if (rows.length < batch) break;
  }
  if (c.version) {
    const { rows } = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM ${c.table} WHERE ${c.column} IS NOT NULL AND ${c.version} <> $1`, [cipher.keyVersion]);
    report.left = rows[0]?.n ?? 0;
  } else {
    report.left = report.unreadable;
  }
  return report;
}

/** The plaintext of a row that needs rewriting, "current" when it is already on the current key, or "unreadable". */
function openRow(cipher: TextCipher, blob: Buffer, aad: string, version: number | null): Buffer | "current" | "unreadable" {
  if (version !== null) {
    try { return cipher.decryptBytes(blob, aad, version); } catch { return "unreadable"; }
  }
  try {
    cipher.decryptBytes(blob, aad, cipher.keyVersion);
    return "current";
  } catch { /* not the current key: the previous one, if any */ }
  for (const v of cipher.versions.slice(1)) {
    try { return cipher.decryptBytes(blob, aad, v); } catch { /* not this one either */ }
  }
  return "unreadable";
}

async function rewrite(tx: pg.PoolClient, cipher: TextCipher, c: EncryptedColumn, row: Row, aad: string, plain: Buffer, keyWhere: string) {
  const keys = c.key.map((k) => row[k]);
  const sealed = cipher.encryptBytes(plain, aad);
  const n = keys.length;
  const { rowCount } = await tx.query(
    `UPDATE ${c.table} SET ${c.column} = $${n + 1}${c.version ? `, ${c.version} = $${n + 2}` : ""} WHERE ${keyWhere}`,
    c.version ? [...keys, sealed, cipher.keyVersion] : [...keys, sealed]);
  if (rowCount !== 1) throw new Error(`${c.table}.${c.column}: a row changed while it was rewritten`);
  // Read back what was stored, and open it with the current key alone.
  const { rows: [back] } = await tx.query<Record<string, unknown>>(
    `SELECT ${c.column} AS ct${c.version ? `, ${c.version} AS v` : ""} FROM ${c.table} WHERE ${keyWhere}`, keys);
  const ok = back && (!c.version || Number(back.v) === cipher.keyVersion)
    && cipher.decryptBytes(back.ct as Buffer, aad, cipher.keyVersion).equals(plain);
  if (!ok) throw new Error(`${c.table}.${c.column}: read-back after rewriting differs; this batch was rolled back`);
}
