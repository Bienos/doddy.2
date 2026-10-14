import { randomUUID } from "node:crypto";
import type pg from "pg";
import { log } from "./log.js";
import type { Db } from "./db.js";
import type { LiveActivitySender, SendOutcome } from "./providers/types.js";

type Queryable = pg.Pool | pg.PoolClient;

export const MAX_TIMER_ATTEMPTS = 3;
/** A timer may be set this far ahead at most (a day). */
export const MAX_TIMER_SECONDS = 24 * 3600;

/** Seconds since 2001-01-01 (the reference date ActivityKit uses for Date in content-state). */
export const toActivityDate = (d: Date) => d.getTime() / 1000 - 978307200;

export interface TimerInput {
  activityToken: string;
  environment: "sandbox" | "production";
  endsAt: Date;
  label?: string;
}

/** The content the finished timer shows: the same ContentState keys the app's focus timer uses. */
export function finishedContent(input: { endsAt: Date; label?: string }): Record<string, unknown> {
  return {
    isPaused: false,
    endsAt: toActivityDate(input.endsAt),
    remaining: 0,
    label: input.label ?? null,
    isFinished: true,
  };
}

/** Queues the Live Activity update for a timer. Returns its id. */
export async function scheduleTimer(db: Queryable, accountId: string, input: TimerInput, now = new Date()): Promise<string> {
  const seconds = (input.endsAt.getTime() - now.getTime()) / 1000;
  if (!(seconds > 0 && seconds <= MAX_TIMER_SECONDS)) throw new Error("timer_out_of_range");
  const id = randomUUID();
  await db.query(
    `INSERT INTO live_activity_timers (id, account_id, activity_token, environment, label, send_at, state)
     VALUES ($1, $2, $3, $4, $5, $6, 'queued')`,
    [id, accountId, input.activityToken, input.environment, input.label ?? null, input.endsAt]);
  return id;
}

/** Cancels a timer that has not been sent. Returns false when it was already sent or never existed. */
export async function cancelTimer(db: Queryable, accountId: string, id: string): Promise<boolean> {
  const { rowCount } = await db.query(
    `UPDATE live_activity_timers SET state = 'cancelled', activity_token = NULL
     WHERE id = $1 AND account_id = $2 AND state = 'queued'`,
    [id, accountId]);
  return (rowCount ?? 0) > 0;
}

/** What to do with one send result. Transient failures wait for the next pass, a few times at most. */
export function nextState(outcome: SendOutcome, attempts: number): { state: "sent" | "queued" | "failed"; error?: string } {
  if (outcome.kind === "accepted") return { state: "sent" };
  if (outcome.kind === "transient" && attempts < MAX_TIMER_ATTEMPTS) return { state: "queued", error: outcome.code };
  return { state: "failed", error: outcome.code };
}

interface Due { id: string; activity_token: string; environment: "sandbox" | "production"; label: string | null; send_at: Date; attempts: number }

/**
 * Sends the due timers. Each row is claimed with FOR UPDATE SKIP LOCKED so two workers never send
 * the same one. A row left in 'sending' by a crash mid-send is not retried: the send may have
 * happened, and a second alert would be worse than none.
 */
export async function dispatchDueTimers(db: Db, sender: LiveActivitySender | undefined, batch = 20): Promise<{ processed: number }> {
  if (!sender) return { processed: 0 };
  const client = await db.connect();
  let rows: Due[];
  try {
    await client.query("BEGIN");
    ({ rows } = await client.query<Due>(
      `UPDATE live_activity_timers SET state = 'sending', attempts = attempts + 1
       WHERE id IN (
         SELECT id FROM live_activity_timers
         WHERE state = 'queued' AND send_at <= now() AND activity_token IS NOT NULL
         ORDER BY send_at LIMIT $1 FOR UPDATE SKIP LOCKED)
       RETURNING id, activity_token, environment, label, send_at, attempts`,
      [batch]));
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw err;
  } finally {
    client.release();
  }
  for (const t of rows) {
    const outcome = await sender.sendLiveActivity(
      { activityToken: t.activity_token, environment: t.environment },
      { event: "update", contentState: finishedContent({ endsAt: t.send_at, label: t.label ?? undefined }),
        alert: { title: t.label ?? "Time's up", body: "Your timer is done." } },
      t.id);
    const next = nextState(outcome, t.attempts);
    // The token is erased once the timer is final, so it does not outlive its use.
    const keepToken = next.state === "queued";
    await db.query(
      `UPDATE live_activity_timers SET state = $2, last_error = $3,
         activity_token = CASE WHEN $4 THEN activity_token ELSE NULL END,
         send_at = CASE WHEN $4 THEN now() + interval '30 seconds' ELSE send_at END
       WHERE id = $1`,
      [t.id, next.state, next.error ?? null, keepToken]);
  }
  if (rows.length) log("live activity timers", { processed: rows.length });
  return { processed: rows.length };
}
