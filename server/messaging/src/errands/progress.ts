import type pg from "pg";
import type { Db } from "../db.js";

export const STAGES = ["running", "waiting_for_service", "researching", "writing_report", "completed", "failed", "cancelled"] as const;
export type ProgressStage = typeof STAGES[number];
export interface ProgressUpdate { stage: ProgressStage; requests: number; searches: number; fetches: number }
export interface ProgressEvent extends ProgressUpdate { at: string }
export interface ErrandProgress extends ProgressUpdate { updatedAt: string; events: ProgressEvent[] }
type Q = Pick<pg.PoolClient, "query"> | Db;

/** Fixed stages and provider-derived counts only; no task words, model text, URLs or percentages. */
export async function recordProgress(db: Q, accountId: string, id: string, update: ProgressUpdate, now: Date,
                                     finishing = false): Promise<void> {
  if (!STAGES.includes(update.stage) || ![update.requests, update.searches, update.fetches]
    .every((n) => Number.isSafeInteger(n) && n >= 0 && n <= 100_000)) return;
  const { rows } = await db.query<{ progress: ErrandProgress | null }>(
    "SELECT progress FROM errands WHERE id = $1 AND account_id = $2 AND state = 'running'", [id, accountId]);
  if (!rows[0]) return;
  const previous = rows[0].progress;
  const at = now.toISOString();
  const counted = { stage: update.stage, requests: Math.max(previous?.requests ?? 0, update.requests),
    searches: Math.max(previous?.searches ?? 0, update.searches), fetches: Math.max(previous?.fetches ?? 0, update.fetches) };
  const event = { ...counted, at };
  const progress: ErrandProgress = { ...counted, updatedAt: at, events: [...(previous?.events ?? []), event].slice(-24) };
  // Cancellation and terminal state always win over a late provider callback. The compare-and-set avoids
  // overwriting another update; the normal worker awaits each progress operation in order.
  await db.query(
    `UPDATE errands SET progress = $3::jsonb WHERE id = $1 AND account_id = $2 AND state = 'running'
     AND ($4::boolean OR cancel_requested_at IS NULL) AND progress IS NOT DISTINCT FROM $5::jsonb`,
    [id, accountId, JSON.stringify(progress), finishing, previous === null ? null : JSON.stringify(previous)]);
}
