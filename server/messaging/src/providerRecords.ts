import type pg from "pg";
import type { Db } from "./db.js";
import { log } from "./log.js";
import { isTwilioSid } from "./providers/twilio.js";
import type { RecordDeleter } from "./providers/types.js";

type Queryable = pg.Pool | pg.PoolClient;

// Doddy deletes its message and call records at Twilio a while after they become final (ADR-494),
// so Twilio's logs don't keep the user's texts and calls. Only Twilio's id is queued here.

/** Default wait before deleting, so the owner can still look at Twilio's logs while testing. */
export const DELETE_AFTER_HOURS_DEFAULT = 24;
/** Twilio refuses to delete a record in its first minute or so (error 20009). */
export const MIN_DELETE_AFTER_MINUTES = 2;
export const MAX_DELETE_ATTEMPTS = 8;

export const deleteAfterMinutes = (hours: number) => Math.max(MIN_DELETE_AFTER_MINUTES, Math.round(hours * 60));

/** Queues one Twilio record for deletion. Anything that isn't a Twilio id is ignored. */
export async function scheduleDeletion(db: Queryable, kind: "message" | "call", sid: string | undefined): Promise<void> {
  if (!sid || !isTwilioSid(kind, sid)) return;
  await db.query("INSERT INTO provider_deletions (sid, kind) VALUES ($1, $2) ON CONFLICT (sid) DO NOTHING", [sid, kind]);
}

/**
 * Deletes the records that have been final for `afterMinutes`. "Not yet" and network problems are
 * tried again with a growing wait (5, 10, 20… minutes); after MAX_DELETE_ATTEMPTS, or a refusal,
 * the row is closed with its error code so it shows in the database instead of retrying forever.
 */
export async function runDueDeletions(db: Db, deleter: RecordDeleter | undefined, afterMinutes: number, batch = 10): Promise<number> {
  if (!deleter) return 0;
  // Claimed by pushing next_try_at forward, so a second worker skips them meanwhile.
  const { rows } = await db.query<{ sid: string; kind: "message" | "call"; attempts: number }>(
    `UPDATE provider_deletions SET next_try_at = now() + interval '10 minutes'
     WHERE sid IN (
       SELECT sid FROM provider_deletions
       WHERE done_at IS NULL AND final_at <= now() - make_interval(mins => $1) AND (next_try_at IS NULL OR next_try_at <= now())
       ORDER BY final_at LIMIT $2 FOR UPDATE SKIP LOCKED)
     RETURNING sid, kind, attempts`, [afterMinutes, batch]);
  let deleted = 0;
  let closed = 0;
  for (const r of rows) {
    const outcome = await deleter.deleteRecord(r.kind, r.sid).catch(() => ({ kind: "retry" as const, code: "error" }));
    if (outcome.kind === "deleted") {
      deleted++;
      await db.query("UPDATE provider_deletions SET done_at = now(), last_error = NULL, attempts = attempts + 1 WHERE sid = $1", [r.sid]);
    } else if (outcome.kind === "retry" && r.attempts + 1 < MAX_DELETE_ATTEMPTS) {
      await db.query(
        `UPDATE provider_deletions SET attempts = attempts + 1, last_error = $2,
           next_try_at = now() + make_interval(mins => $3) WHERE sid = $1`,
        [r.sid, outcome.code, 5 * 2 ** r.attempts]);
    } else {
      closed++;
      await db.query(
        "UPDATE provider_deletions SET attempts = attempts + 1, last_error = $2, done_at = now() WHERE sid = $1",
        [r.sid, outcome.code]);
    }
  }
  if (deleted || closed) log("twilio records deleted", { deleted, notDeleted: closed });
  return rows.length;
}

/** Finished rows are only bookkeeping; they go after 30 days. */
export async function pruneDeletions(db: Db): Promise<number> {
  const r = await db.query("DELETE FROM provider_deletions WHERE done_at < now() - interval '30 days'");
  return r.rowCount ?? 0;
}
