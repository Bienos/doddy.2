import type pg from "pg";
import type { Db } from "./db.js";
import { log } from "./log.js";
import { isTwilioSid } from "./providers/twilio.js";
import type { RecordDeleter } from "./providers/types.js";

type Queryable = pg.Pool | pg.PoolClient;

// Doddy deletes its message and call records at Twilio a while after they become final (ADR-753),
// so Twilio's logs don't keep the user's texts and calls. Only Twilio's id is queued here, with the
// account the record lives on: `main` (texts, calls to and from Doddy's number, forwarded call-backs)
// or `task` (the calls Doddy places for the user and their takeover legs, on TWILIO_TASK_*).

/** Default wait before deleting, so the owner can still look at Twilio's logs while testing. */
export const DELETE_AFTER_HOURS_DEFAULT = 24;
/** Twilio refuses to delete a record in its first minute or so (error 20009). */
export const MIN_DELETE_AFTER_MINUTES = 2;
export const MAX_DELETE_ATTEMPTS = 8;

export const deleteAfterMinutes = (hours: number) => Math.max(MIN_DELETE_AFTER_MINUTES, Math.round(hours * 60));

export type TwilioAccount = "main" | "task";
/** One deleter per Twilio account, each with that account's own credentials. */
export interface RecordDeleters { main?: RecordDeleter; task?: RecordDeleter }

/** Queues one Twilio record for deletion. Anything that isn't a Twilio id is ignored. */
export async function scheduleDeletion(
  db: Queryable, kind: "message" | "call", sid: string | undefined, account: TwilioAccount = "main",
): Promise<void> {
  if (!sid || !isTwilioSid(kind, sid)) return;
  await db.query("INSERT INTO provider_deletions (sid, kind, account) VALUES ($1, $2, $3) ON CONFLICT (sid) DO NOTHING", [sid, kind, account]);
}

/**
 * Deletes the records that have been final for `afterMinutes`, each with its own account's deleter; an account
 * without one (not configured) keeps its records queued. A task call's record waits while its price is still being
 * read from it (the cost items settle within a day, as `unknown` at the latest). "Not yet" and network problems are
 * tried again with a growing wait (5, 10, 20… minutes); after MAX_DELETE_ATTEMPTS, or a refusal, the row is closed
 * with its error code so it shows in the database instead of retrying forever. A single deleter is the main account's.
 */
export async function runDueDeletions(
  db: Db, deleters: RecordDeleter | RecordDeleters | undefined, afterMinutes: number, batch = 10,
): Promise<number> {
  const by: RecordDeleters = !deleters ? {} : "deleteRecord" in deleters ? { main: deleters } : deleters;
  const accounts = (["main", "task"] as const).filter((a) => by[a]);
  if (!accounts.length) return 0;
  // Claimed by pushing next_try_at forward, so a second worker skips them meanwhile.
  const { rows } = await db.query<{ sid: string; kind: "message" | "call"; account: TwilioAccount; attempts: number }>(
    `UPDATE provider_deletions SET next_try_at = now() + interval '10 minutes'
     WHERE sid IN (
       SELECT d.sid FROM provider_deletions d
       WHERE d.done_at IS NULL AND d.final_at <= now() - make_interval(mins => $1) AND (d.next_try_at IS NULL OR d.next_try_at <= now())
         AND d.account = ANY($3::text[])
         AND (d.account <> 'task' OR NOT EXISTS (
           SELECT 1 FROM call_cost_items i JOIN call_attempts a ON a.id = i.attempt_id
             LEFT JOIN call_takeovers t ON t.id::text = i.ref
           WHERE i.status = 'pending' AND ((i.component = 'twilio_call' AND a.twilio_call_sid = d.sid)
             OR (i.component = 'twilio_takeover' AND t.twilio_call_sid = d.sid))))
       ORDER BY d.final_at LIMIT $2 FOR UPDATE OF d SKIP LOCKED)
     RETURNING sid, kind, account, attempts`, [afterMinutes, batch, accounts]);
  let deleted = 0;
  let closed = 0;
  for (const r of rows) {
    const deleter = by[r.account]!;
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
