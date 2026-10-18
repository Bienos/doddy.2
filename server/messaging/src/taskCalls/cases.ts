// Reading a case, acknowledging its result (which deletes the server's copies, with receipts), and
// cancelling. The app keeps the result, transcript, cost and receipts on the iPhone.
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { sameBytes } from "../crypto.js";
import { inTransaction } from "../db.js";
import type { TaskCallContext } from "./context.js";
import { previewOf } from "./payload.js";
import { decryptPayload, phaseOf, resultAad } from "./service.js";

type Client = Pick<pg.PoolClient, "query">;

export interface CostItem {
  attemptId: string; component: string; ref: string; status: string; amountMicros: number | null; currency: string | null;
  quantity: number | null; unit: string | null;
}

/** Sum of the known parts; says whether anything is still pending or unknown, or estimated. */
export function costSummary(items: CostItem[]) {
  const known = items.filter((i) => ["reported", "estimated", "zero"].includes(i.status) && i.currency === "USD");
  return {
    currency: "USD",
    totalMicros: known.reduce((s, i) => s + (i.amountMicros ?? 0), 0),
    complete: items.length > 0 && items.every((i) => ["reported", "estimated", "zero"].includes(i.status)),
    approximate: items.some((i) => i.status === "estimated"),
    pending: items.some((i) => i.status === "pending"),
    unknownParts: items.filter((i) => i.status === "unknown").map((i) => i.component),
    items,
  };
}

async function costItems(c: Client, caseId: string): Promise<CostItem[]> {
  const { rows } = await c.query<{ attempt_id: string; component: string; ref: string; status: string; amount_micros: string | null; currency: string | null; quantity: string | null; unit: string | null }>(
    `SELECT i.attempt_id, i.component, i.ref, i.status, i.amount_micros, i.currency, i.quantity, i.unit
     FROM call_cost_items i JOIN call_attempts a ON a.id = i.attempt_id WHERE a.case_id = $1 ORDER BY a.attempt_no, i.component, i.ref`, [caseId]);
  return rows.map((r) => ({
    attemptId: r.attempt_id, component: r.component, ref: r.ref, status: r.status, amountMicros: r.amount_micros === null ? null : Number(r.amount_micros),
    currency: r.currency, quantity: r.quantity === null ? null : Number(r.quantity), unit: r.unit,
  }));
}

export async function receipts(c: Client, caseId: string) {
  const { rows } = await c.query<{ item: string; location: string; reason: string; result: string; requested_at: Date; settled_at: Date | null; row_count: number | null }>(
    `SELECT item, location, reason, result, requested_at, settled_at, row_count FROM server_data_deletions
     WHERE case_id = $1 ORDER BY requested_at, item`, [caseId]);
  return rows.map((r) => ({ item: r.item, location: r.location, reason: r.reason, result: r.result, requestedAt: r.requested_at, settledAt: r.settled_at, rows: r.row_count }));
}

export async function getCase(ctx: TaskCallContext, accountId: string, caseId: string) {
  const { rows } = await ctx.db.query<{ id: string; state: string; payload_ciphertext: Buffer | null; payload_digest: Buffer; approvable_until: Date; created_at: Date; max_duration_secs: number }>(
    "SELECT * FROM call_cases WHERE id = $1 AND account_id = $2", [caseId, accountId]);
  const kase = rows[0];
  if (!kase) return undefined;
  const { rows: attempts } = await ctx.db.query<{
    id: string; attempt_no: number; state: string; dial_not_before: Date; dial_started_at: Date | null; answered_at: Date | null;
    ended_at: Date | null; end_reason: string | null; taken_over_at: Date | null; ending_at: Date | null; settled_at: Date | null; error_code: string | null;
  }>("SELECT * FROM call_attempts WHERE case_id = $1 ORDER BY attempt_no", [caseId]);
  const { rows: results } = await ctx.db.query<{ attempt_id: string; state: string; outcome: string | null; confidence: string | null; ciphertext: Buffer | null; result_digest: Buffer | null; expires_at: Date | null }>(
    `SELECT r.attempt_id, r.state, r.outcome, r.confidence, r.ciphertext, r.result_digest, r.expires_at
     FROM call_results r JOIN call_attempts a ON a.id = r.attempt_id WHERE a.case_id = $1 ORDER BY a.attempt_no`, [caseId]);
  const items = await costItems(ctx.db, caseId);
  return {
    caseId: kase.id,
    state: kase.state,
    approvableUntil: kase.approvable_until,
    preview: kase.payload_ciphertext
      ? previewOf(decryptPayload(ctx, accountId, kase.id, kase.payload_ciphertext), kase.payload_digest, kase.approvable_until)
      : null,
    attempts: attempts.map((a) => ({
      id: a.id, attemptNo: a.attempt_no, state: a.state, phase: phaseOf(a), dialNotBefore: a.dial_not_before, dialStartedAt: a.dial_started_at,
      answeredAt: a.answered_at, endedAt: a.ended_at, endReason: a.end_reason, takenOverAt: a.taken_over_at,
      cost: costSummary(items.filter((i) => i.attemptId === a.id)),
    })),
    results: results.map((r) => ({
      attemptId: r.attempt_id, state: r.state, outcome: r.outcome, confidence: r.confidence, expiresAt: r.expires_at,
      resultDigest: r.result_digest?.toString("hex") ?? null,
      result: r.ciphertext ? safeDecrypt(ctx, r.ciphertext, resultAad(accountId, r.attempt_id)) : null,
    })),
    cost: costSummary(items),
    deletions: await receipts(ctx.db, caseId),
  };
}

function safeDecrypt(ctx: TaskCallContext, blob: Buffer, aad: string): unknown {
  try {
    return JSON.parse(ctx.cipher.decrypt(blob, aad));
  } catch {
    return null;
  }
}

export async function listCases(ctx: TaskCallContext, accountId: string) {
  const { rows } = await ctx.db.query(
    `SELECT c.id AS "caseId", c.state, c.created_at AS "createdAt",
       (SELECT r.outcome FROM call_results r JOIN call_attempts a ON a.id = r.attempt_id WHERE a.case_id = c.id ORDER BY a.attempt_no DESC LIMIT 1) AS outcome
     FROM call_cases c WHERE c.account_id = $1 ORDER BY c.created_at DESC LIMIT 30`, [accountId]);
  return rows;
}

const RETRYABLE = new Set(["no_answer", "busy", "failed", "not_placed", "voicemail", "voice_unavailable", "unknown"]);

/**
 * The app has saved the result on the iPhone: delete the server's copy of the result and the live
 * lines, and the payload unless a retry is still possible. Each delete writes its receipt in the same
 * transaction. Idempotent.
 */
export async function ackResult(ctx: TaskCallContext, accountId: string, caseId: string, attemptId: string, digestHex: string) {
  const now = ctx.now();
  const outcome = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; result_digest: Buffer | null; outcome: string | null; attempt_no: number }>(
      `SELECT r.state, r.result_digest, r.outcome, a.attempt_no FROM call_results r JOIN call_attempts a ON a.id = r.attempt_id
       WHERE r.attempt_id = $1 AND a.case_id = $2 AND r.account_id = $3 FOR UPDATE OF r`, [attemptId, caseId, accountId]);
    const r = rows[0];
    if (!r) return "not_found" as const;
    if (r.state === "acked") return "ok" as const;
    if (r.state !== "ready" || !r.result_digest || !sameBytes(r.result_digest, Buffer.from(digestHex, "hex"))) return "mismatch" as const;
    await c.query("UPDATE call_results SET state = 'acked', ciphertext = NULL, key_version = NULL, settled_at = $2 WHERE attempt_id = $1", [attemptId, now]);
    await receipt(c, accountId, caseId, attemptId, "call_result", "acked", 1, now);
    const lines = await c.query("DELETE FROM call_live_lines WHERE attempt_id = $1", [attemptId]);
    if (lines.rowCount) await receipt(c, accountId, caseId, attemptId, "live_lines", "acked", lines.rowCount, now);
    const retry = RETRYABLE.has(r.outcome ?? "") && r.attempt_no < 3;
    if (!retry) await purgePayload(c, accountId, caseId, "finished", "acked", now);
    return "ok" as const;
  });
  if (outcome !== "ok") return outcome;
  return { deletions: await receipts(ctx.db, caseId) };
}

/** Drops a case's payload (the brief) and closes it. */
export async function purgePayload(c: Client, accountId: string, caseId: string, state: "finished" | "cancelled" | "expired",
  reason: "acked" | "cancelled" | "expired", now: Date): Promise<boolean> {
  const { rowCount } = await c.query(
    `UPDATE call_cases SET payload_ciphertext = NULL, payload_key_version = NULL, payload_purged_at = $3, state = $2, updated_at = $3
     WHERE id = $1 AND payload_ciphertext IS NOT NULL`, [caseId, state, now]);
  if (rowCount) await receipt(c, accountId, caseId, null, "call_payload", reason, 1, now);
  return (rowCount ?? 0) > 0;
}

export async function receipt(c: Client, accountId: string | null, caseId: string | null, attemptId: string | null,
  item: "call_payload" | "live_lines" | "call_input" | "call_result", reason: "acked" | "expired" | "processed" | "cancelled" | "account_deleted",
  rows: number, now: Date) {
  await c.query(
    `INSERT INTO server_data_deletions (id, account_id, case_id, attempt_id, item, location, reason, result, row_count, requested_at, settled_at)
     VALUES ($1, $2, $3, $4, $5, 'doddy_server', $6, 'deleted', $7, $8, $8)`,
    [randomUUID(), accountId, caseId, attemptId, item, reason, rows, now]);
}

/** The user doesn't want this call (any more): scheduled attempts are cancelled and the brief deleted. */
export async function cancelCase(ctx: TaskCallContext, accountId: string, caseId: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string }>("SELECT state FROM call_cases WHERE id = $1 AND account_id = $2 FOR UPDATE", [caseId, accountId]);
    if (!rows[0]) return "not_found" as const;
    const { rows: live } = await c.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM call_attempts WHERE case_id = $1
       AND (state IN ('dialing','ringing','connecting','in_progress','taken_over') OR (state = 'unknown' AND settled_at IS NULL))`, [caseId]);
    if ((live[0]?.n ?? 0) > 0) return "live" as const; // end the call first (Zakończ)
    await c.query(
      `UPDATE call_attempts SET state = 'cancelled', end_reason = 'canceled', settled_at = $2, updated_at = $2 WHERE case_id = $1 AND state = 'scheduled'`,
      [caseId, now]);
    await purgePayload(c, accountId, caseId, "cancelled", "cancelled", now);
    await c.query("UPDATE call_cases SET state = 'cancelled', updated_at = $2 WHERE id = $1 AND state IN ('awaiting_approval', 'active')", [caseId, now]);
    return "ok" as const;
  });
}

export async function setLiveActivityToken(ctx: TaskCallContext, accountId: string, caseId: string, token: string | null, env: "sandbox" | "production" | null) {
  const { rowCount } = await ctx.db.query(
    "UPDATE call_cases SET live_activity_token = $3, live_activity_env = $4, updated_at = $5 WHERE id = $1 AND account_id = $2",
    [caseId, accountId, token, token ? env : null, ctx.now()]);
  return (rowCount ?? 0) > 0;
}
