// Errands, the app's side (ERRANDS.md "Server API"): create a draft, approve it by its digest, read,
// cancel, acknowledge (which deletes the server's copy, with receipts) and delete. The rules:
//   - a draft stores the words, brief and title encrypted, exactly as sent, with their SHA-256;
//   - only a draft can be approved, only with its own digest, only within 10 minutes, and only
//     while the account has fewer than ERRANDS_MAX_OPEN queued or running errands (counted under an
//     advisory lock, so two approvals can't both take the last place);
//   - nothing is created or approved while errands are off or not set up (503 errands_disabled).
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { sameBytes } from "../crypto.js";
import { inTransaction, type Db } from "../db.js";
import { contentAad, resultAad, type ErrandContext } from "./context.js";
import { contentDigest, contentJson, createBody, type ErrandContent, type ErrandResult } from "./schema.js";

export const DRAFT_MINUTES = 10;
export const LIST_LIMIT = 50;

type Q = Pick<pg.PoolClient, "query"> | Db;

export type Refusal =
  | { status: 400; error: "invalid_request"; fields: string[] }
  | { status: 404; error: "not_found" }
  | { status: 409; error: "not_approvable" | "not_cancellable" | "no_result"; state: string }
  | { status: 409; error: "digest_mismatch" | "too_many_open_errands" | "result_mismatch" }
  | { status: 503; error: "errands_disabled" };

const refuse = (r: Refusal) => ({ refusal: r });

export interface ErrandRow {
  id: string; account_id: string; state: string; language: string;
  content_ciphertext: Buffer | null; payload_digest: Buffer;
  result_ciphertext: Buffer | null; result_digest: Buffer | null; failure: string | null;
  searches: number; fetches: number; cancel_requested_at: Date | null;
  created_at: Date; expires_at: Date; approved_at: Date | null; started_at: Date | null; finished_at: Date | null;
  acknowledged_at: Date | null;
}

export function decryptContent(ctx: ErrandContext, accountId: string, id: string, blob: Buffer): ErrandContent | undefined {
  try {
    return createBody.parse(JSON.parse(ctx.cipher.decrypt(blob, contentAad(accountId, id))));
  } catch {
    return undefined; // a key this server doesn't have, or a tampered row
  }
}

function decryptResult(ctx: ErrandContext, accountId: string, id: string, blob: Buffer): ErrandResult | undefined {
  try {
    return JSON.parse(ctx.cipher.decrypt(blob, resultAad(accountId, id))) as ErrandResult;
  } catch {
    return undefined;
  }
}

// ---------- create ----------

export async function createErrand(ctx: ErrandContext, accountId: string, body: unknown) {
  if (!ctx.enabled) return refuse({ status: 503, error: "errands_disabled" });
  const parsed = createBody.safeParse(body);
  if (!parsed.success) return refuse({ status: 400, error: "invalid_request", fields: parsed.error.issues.map((i) => i.path.join(".")) });
  const content = parsed.data;
  const now = ctx.now();
  const id = randomUUID();
  const digest = contentDigest(content);
  const expiresAt = new Date(now.getTime() + DRAFT_MINUTES * 60_000);
  await ctx.db.query(
    `INSERT INTO errands (id, account_id, state, language, content_key_version, content_ciphertext, payload_digest, created_at, expires_at)
     VALUES ($1, $2, 'draft', $3, $4, $5, $6, $7, $8)`,
    [id, accountId, content.language, ctx.cipher.keyVersion, ctx.cipher.encrypt(contentJson(content), contentAad(accountId, id)),
      digest, now, expiresAt]);
  ctx.log("errand drafted", { errandId: id });
  return {
    draft: {
      id, digest: digest.toString("hex"), title: content.title, words: content.words, brief: content.brief,
      language: content.language, expiresAt: expiresAt.toISOString(),
      ...(content.kind ? { kind: content.kind, priorities: content.priorities ?? [] } : {}),
    },
  };
}

// ---------- approve ----------

export async function approveErrand(ctx: ErrandContext, accountId: string, id: string, digestHex: string) {
  if (!ctx.enabled) return refuse({ status: 503, error: "errands_disabled" });
  const now = ctx.now();
  const given = Buffer.from(digestHex, "hex");
  const r = await inTransaction(ctx.db, async (c) => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('errands:' || $1))", [accountId]);
    const { rows } = await c.query<{ state: string; payload_digest: Buffer; expires_at: Date }>(
      "SELECT state, payload_digest, expires_at FROM errands WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const e = rows[0];
    if (!e) return refuse({ status: 404, error: "not_found" });
    if (e.state !== "draft" || e.expires_at <= now) return refuse({ status: 409, error: "not_approvable", state: e.state === "draft" ? "expired" : e.state });
    if (!sameBytes(e.payload_digest, given)) return refuse({ status: 409, error: "digest_mismatch" });
    const { rows: open } = await c.query<{ n: number }>(
      "SELECT count(*)::int AS n FROM errands WHERE account_id = $1 AND state IN ('queued', 'running')", [accountId]);
    if ((open[0]?.n ?? 0) >= ctx.settings.maxOpen) return refuse({ status: 409, error: "too_many_open_errands" });
    await c.query("UPDATE errands SET state = 'queued', approved_at = $2 WHERE id = $1", [id, now]);
    return { approved: { id, state: "queued" as const } };
  });
  if ("approved" in r) ctx.log("errand approved", { errandId: id });
  return r;
}

// ---------- reads ----------

const iso = (d: Date | null) => (d ? d.toISOString() : null);

function view(ctx: ErrandContext, e: ErrandRow) {
  const content = e.content_ciphertext ? decryptContent(ctx, e.account_id, e.id, e.content_ciphertext) : undefined;
  const result = e.state === "done" && e.result_ciphertext ? decryptResult(ctx, e.account_id, e.id, e.result_ciphertext) : undefined;
  return {
    id: e.id,
    // Content fields exist only while the server holds the content (gone after ack, DELETE or 30 days).
    ...(content ? { title: content.title, words: content.words, brief: content.brief, digest: e.payload_digest.toString("hex") } : {}),
    ...(content?.kind ? { kind: content.kind, priorities: content.priorities ?? [] } : {}),
    language: e.language,
    state: e.state,
    createdAt: iso(e.created_at),
    ...(e.state === "draft" ? { expiresAt: iso(e.expires_at) } : {}),
    approvedAt: iso(e.approved_at),
    startedAt: iso(e.started_at),
    finishedAt: iso(e.finished_at),
    acknowledgedAt: iso(e.acknowledged_at),
    cancelRequested: e.cancel_requested_at !== null,
    searches: e.searches,
    fetches: e.fetches,
    ...(result && e.result_digest ? { result, resultDigest: e.result_digest.toString("hex") } : {}),
    ...(e.failure ? { failure: e.failure } : {}),
  };
}

export async function getErrand(ctx: ErrandContext, accountId: string, id: string) {
  const { rows } = await ctx.db.query<ErrandRow>("SELECT * FROM errands WHERE id = $1 AND account_id = $2", [id, accountId]);
  return rows[0] ? view(ctx, rows[0]) : undefined;
}

/** Newest first, drafts left out. The title is null once the server's copy is deleted. */
export async function listErrands(ctx: ErrandContext, accountId: string) {
  const { rows } = await ctx.db.query<ErrandRow>(
    `SELECT * FROM errands WHERE account_id = $1 AND state <> 'draft' ORDER BY created_at DESC, id LIMIT ${LIST_LIMIT}`, [accountId]);
  return rows.map((e) => ({
    id: e.id,
    title: e.content_ciphertext ? decryptContent(ctx, accountId, e.id, e.content_ciphertext)?.title ?? null : null,
    state: e.state,
    createdAt: iso(e.created_at),
    finishedAt: iso(e.finished_at),
    failure: e.failure,
  }));
}

// ---------- cancel ----------

/**
 * A draft is deleted (it was never approved); a queued errand is cancelled and never starts; a
 * running one is marked and the runner stops at its next step. Cancelling again is fine.
 */
export async function cancelErrand(ctx: ErrandContext, accountId: string, id: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string }>("SELECT state FROM errands WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const e = rows[0];
    if (!e) return refuse({ status: 404, error: "not_found" });
    switch (e.state) {
      case "draft":
        await c.query("DELETE FROM errands WHERE id = $1", [id]);
        return { ok: "deleted" as const };
      case "queued":
        await c.query("UPDATE errands SET state = 'cancelled', finished_at = $2 WHERE id = $1", [id, now]);
        return { ok: "cancelled" as const };
      case "running":
        await c.query("UPDATE errands SET cancel_requested_at = coalesce(cancel_requested_at, $2) WHERE id = $1", [id, now]);
        return { ok: "stopping" as const };
      case "cancelled":
        return { ok: "cancelled" as const };
      default:
        return refuse({ status: 409, error: "not_cancellable", state: e.state });
    }
  });
}

// ---------- ack and delete ----------

type Item = "words" | "brief" | "title" | "result";

export async function writeReceipts(c: Q, accountId: string, id: string, items: Item[], reason: "acked" | "expired" | "deleted", now: Date) {
  for (const item of items) {
    await c.query(
      "INSERT INTO errand_deletions (id, account_id, errand_id, item, reason, deleted_at) VALUES ($1, $2, $3, $4, $5, $6)",
      [randomUUID(), accountId, id, item, reason, now]);
  }
}

export async function receiptsFor(c: Q, id: string) {
  const { rows } = await c.query<{ item: string; reason: string; deleted_at: Date }>(
    "SELECT item, reason, deleted_at FROM errand_deletions WHERE errand_id = $1 ORDER BY deleted_at, item", [id]);
  return rows.map((r) => ({ what: r.item, reason: r.reason, deletedAt: r.deleted_at.toISOString() }));
}

/** Wipes the words, brief, title and result of one errand row (already locked) and writes the receipts. */
export async function wipeContent(c: Q, accountId: string, id: string, hadResult: boolean, reason: "acked" | "expired", now: Date) {
  const { rowCount } = await c.query(
    `UPDATE errands SET content_ciphertext = NULL, content_key_version = NULL, content_deleted_at = $2,
       result_ciphertext = NULL, result_key_version = NULL,
       acknowledged_at = CASE WHEN $3 THEN $2::timestamptz ELSE acknowledged_at END
     WHERE id = $1 AND content_ciphertext IS NOT NULL`, [id, now, reason === "acked"]);
  if (rowCount) await writeReceipts(c, accountId, id, hadResult ? ["words", "brief", "title", "result"] : ["words", "brief", "title"], reason, now);
  return (rowCount ?? 0) > 0;
}

/**
 * The app saved the result on the iPhone: the server deletes the words, brief, title and result and
 * keeps the id, state and times. Says what it deleted. Idempotent with the same digest.
 */
export async function ackErrand(ctx: ErrandContext, accountId: string, id: string, resultDigestHex: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; result_digest: Buffer | null; result_ciphertext: Buffer | null; acknowledged_at: Date | null }>(
      "SELECT state, result_digest, result_ciphertext, acknowledged_at FROM errands WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const e = rows[0];
    if (!e) return refuse({ status: 404, error: "not_found" });
    if (e.state !== "done" || !e.result_digest) return refuse({ status: 409, error: "no_result", state: e.state });
    if (!sameBytes(e.result_digest, Buffer.from(resultDigestHex, "hex"))) return refuse({ status: 409, error: "result_mismatch" });
    if (e.result_ciphertext) await wipeContent(c, accountId, id, true, "acked", now);
    else if (!e.acknowledged_at) await c.query("UPDATE errands SET acknowledged_at = $2 WHERE id = $1", [id, now]);
    return { deletions: await receiptsFor(c, id) };
  });
}

/** Deletes the row. A running errand notices at its next step and stops; nothing is stored or pushed. */
export async function deleteErrand(ctx: ErrandContext, accountId: string, id: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ content_ciphertext: Buffer | null; result_ciphertext: Buffer | null }>(
      "SELECT content_ciphertext, result_ciphertext FROM errands WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const e = rows[0];
    if (!e) return refuse({ status: 404, error: "not_found" });
    if (e.content_ciphertext) {
      await writeReceipts(c, accountId, id, e.result_ciphertext ? ["words", "brief", "title", "result"] : ["words", "brief", "title"], "deleted", now);
    }
    await c.query("DELETE FROM errands WHERE id = $1", [id]);
    return { ok: true as const };
  });
}
