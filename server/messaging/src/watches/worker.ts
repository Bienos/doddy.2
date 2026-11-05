// Background passes for price watches (SHOPPING_WATCH.md section 2), run by their own loop so a slow shop
// never holds back pushes or errands. Safe in several processes at once: due watches are claimed with
// FOR UPDATE SKIP LOCKED in a committed transaction before any page is read, and the claim moves each
// watch's due time forward (a lease), so a second worker neither sees it as due nor checks it again.
//   - a tick claims up to 10 due active watches and checks them one at a time, leaving at least 2 seconds
//     between two requests to one host; each check is written (and its push queued) in one transaction
//     that only applies if the watch is still active and still held by this claim;
//   - a watch that is never recorded (the worker died) is due again when its lease ends, 15 minutes later;
//   - drafts older than 10 minutes are deleted; a watch that finished 30 days ago is deleted, content and all.
// The push never carries words from the watch, not even its title. Logs carry ids, outcomes and counts only.
import type pg from "pg";
import { inTransaction } from "../db.js";
import { canPush, enqueue } from "../outbox.js";
import { checkOfferPage, type PageCheck } from "../shopping/pagecheck.js";
import type { WatchContext } from "./context.js";
import { decide, judge, pushText, type Verdict } from "./rules.js";
import { openContent } from "./service.js";

/** Watches claimed (and checked) per tick. */
export const BATCH = 10;
/** The least time between two requests to one host. */
export const HOST_GAP_MS = 2000;
/** How long a claim holds a watch; far above the longest batch (10 checks of at most about 20 s each). */
export const CLAIM_MINUTES = 15;
/** A watch that ended is kept this long, then deleted. */
export const FINISHED_DAYS = 30;
/** After a failed write the claim is given back with a pause, so a broken database isn't hammered with page reads. */
const RETRY_AFTER_ERROR_MS = 5 * 60_000;

export interface WatchLoopState {
  /** When the last request to each host ended (ms on the context's clock): the 2-second gap. */
  lastRequestAt: Map<string, number>;
  /** Aborted on shutdown: the check in flight is given back unrecorded and no further watch is started. */
  shutdown: AbortController;
}
export const newWatchLoopState = (): WatchLoopState => ({ lastRequestAt: new Map(), shutdown: new AbortController() });

export interface PassCounts { [pass: string]: number }

/** One pass: tidy (drafts, finished watches), then check what is due. */
export async function runWatchPasses(ctx: WatchContext, state: WatchLoopState): Promise<PassCounts> {
  const counts: PassCounts = {};
  const add = (name: string, n: number) => { if (n) counts[name] = (counts[name] ?? 0) + n; };
  const run = async (name: string, fn: () => Promise<number>) => {
    try {
      add(name, await fn());
    } catch (err) {
      ctx.log("watch pass failed", { pass: name, error: (err as Error).message.slice(0, 200) });
    }
  };
  await run("drafts", () => expireDrafts(ctx));
  await run("swept", () => sweepFinished(ctx));
  if (ctx.enabled && !state.shutdown.signal.aborted) {
    try {
      const due = await checkDue(ctx, state);
      for (const [k, n] of Object.entries(due)) add(k, n);
    } catch (err) {
      ctx.log("watch pass failed", { pass: "checks", error: (err as Error).message.slice(0, 200) });
    }
  }
  return counts;
}

/** A draft never approved is deleted after 10 minutes. */
export async function expireDrafts(ctx: WatchContext): Promise<number> {
  const { rowCount } = await ctx.db.query("DELETE FROM price_watches WHERE state = 'draft' AND expires_at <= $1", [ctx.now()]);
  return rowCount ?? 0;
}

/** A watch that ended (any end) is deleted, content and all, 30 days after it ended. */
export async function sweepFinished(ctx: WatchContext): Promise<number> {
  const cutoff = new Date(ctx.now().getTime() - FINISHED_DAYS * 86_400_000);
  const { rowCount } = await ctx.db.query(
    `DELETE FROM price_watches WHERE id IN (
       SELECT id FROM price_watches WHERE finished_at IS NOT NULL AND finished_at <= $1
       ORDER BY finished_at LIMIT 200 FOR UPDATE SKIP LOCKED)`, [cutoff]);
  return rowCount ?? 0;
}

export interface Claimed {
  id: string; account_id: string; language: string; content_ciphertext: Buffer; payload_digest: Buffer;
  threshold_minor: string; currency: string;
  /** When the check was due, and the end of this claim (the due time while the watch is held). */
  due_at: Date; lease: Date;
}

/**
 * Takes up to `limit` due active watches, oldest due first, and moves each one's due time to the end of the
 * claim. Committed before any page is read, so a watch is never checked twice for one due time.
 */
export async function claimDue(ctx: WatchContext, limit = BATCH): Promise<Claimed[]> {
  const now = ctx.now();
  const lease = new Date(now.getTime() + CLAIM_MINUTES * 60_000);
  const { rows } = await ctx.db.query<Claimed>(
    `WITH due AS (
       SELECT id, next_check_at AS due_at FROM price_watches
       WHERE state = 'active' AND next_check_at <= $1
       ORDER BY next_check_at, id LIMIT $3 FOR UPDATE SKIP LOCKED)
     UPDATE price_watches w SET next_check_at = $2
     FROM due WHERE w.id = due.id
     RETURNING w.id, w.account_id, w.language, w.content_ciphertext, w.payload_digest, w.threshold_minor, w.currency,
       due.due_at, w.next_check_at AS lease`,
    [now, lease, limit]);
  return rows.sort((a, b) => a.due_at.getTime() - b.due_at.getTime() || (a.id < b.id ? -1 : 1));
}

/** Gives claims back unrecorded (shutdown, or a failed write), if they are still held by that claim. */
async function release(ctx: WatchContext, claims: Claimed[], at: (c: Claimed) => Date): Promise<void> {
  for (const c of claims) {
    await ctx.db.query("UPDATE price_watches SET next_check_at = $3 WHERE id = $1 AND state = 'active' AND next_check_at = $2",
      [c.id, c.lease, at(c)]);
  }
}

export interface DueCounts { [outcome: string]: number }

/** Claims a batch and checks it one watch at a time. Whatever isn't recorded is given back. */
export async function checkDue(ctx: WatchContext, state: WatchLoopState): Promise<DueCounts> {
  const counts: DueCounts = {};
  const claimed = await claimDue(ctx);
  if (!claimed.length) return counts;
  counts.claimed = claimed.length;
  const pending = new Map(claimed.map((c) => [c.id, c]));
  const stamp = ctx.now().getTime();
  for (const [host, at] of state.lastRequestAt) if (at < stamp - 60_000) state.lastRequestAt.delete(host);
  let failedWrite = false;
  try {
    for (const w of claimed) {
      if (state.shutdown.signal.aborted) break;
      try {
        const outcome = await checkClaimed(ctx, state, w);
        if (outcome !== "released") pending.delete(w.id);
        counts[outcome] = (counts[outcome] ?? 0) + 1;
      } catch (err) {
        failedWrite = true;
        ctx.log("watch check failed", { watchId: w.id, error: (err as Error).message.slice(0, 200) });
      }
    }
  } finally {
    if (pending.size) {
      const at = failedWrite ? new Date(ctx.now().getTime() + RETRY_AFTER_ERROR_MS) : undefined;
      await release(ctx, [...pending.values()], (c) => at ?? c.due_at).catch((err: Error) =>
        ctx.log("watch release failed", { error: err.message.slice(0, 200) }));
    }
  }
  return counts;
}

const hostOf = (url: string): string => {
  try { return new URL(url).hostname.toLowerCase(); } catch { return ""; }
};

/** Waits until at least HOST_GAP_MS have passed since the last request to this host ended. */
export async function politeWait(clock: Pick<WatchContext, "now" | "sleep">, state: Pick<WatchLoopState, "lastRequestAt">, host: string): Promise<void> {
  const last = state.lastRequestAt.get(host);
  if (last === undefined) return;
  const wait = last + HOST_GAP_MS - clock.now().getTime();
  if (wait > 0) await clock.sleep(wait);
}

/** What reading the page says, or "aborted" when shutdown stopped it (nothing is recorded then). */
export async function verdictFor(
  ctx: Pick<WatchContext, "cipher" | "fetcher" | "now" | "sleep" | "log">, state: WatchLoopState, w: Claimed,
): Promise<Verdict | "aborted"> {
  // Only exactly what was approved is read: words from the blob, numbers from their columns, one digest.
  const content = openContent(ctx, w);
  if (!content) {
    ctx.log("watch content check failed; not read", { watchId: w.id });
    return { kind: "failed", cause: "content" };
  }
  const host = hostOf(content.url);
  await politeWait(ctx, state, host);
  if (state.shutdown.signal.aborted) return "aborted";
  let check: PageCheck;
  try {
    check = await checkOfferPage(content.url, ctx.fetcher!, state.shutdown.signal);
  } catch {
    check = { kind: "failed", reason: "error" };
  }
  state.lastRequestAt.set(host, ctx.now().getTime());
  if (state.shutdown.signal.aborted) return "aborted";
  return judge(check, content.thresholdMinor, content.currency);
}

/** One check, from the claim to the recorded outcome: "checked", "triggered", "failed", "expired", "released" or "superseded". */
export async function checkClaimed(ctx: WatchContext, state: WatchLoopState, w: Claimed): Promise<string> {
  const verdict = await verdictFor(ctx, state, w);
  if (verdict === "aborted") return "released";
  return record(ctx, w, verdict);
}

/**
 * Writes the outcome, and the one push it may queue, in one transaction. It applies only if the watch is
 * still active and still held by this claim: a Stop, a DELETE or a later claim wins over a late result.
 */
async function record(ctx: WatchContext, w: Claimed, verdict: Verdict): Promise<string> {
  const interval = ctx.settings.checkHours * 3_600_000;
  const now = ctx.now();
  const out = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; next_check_at: Date | null; checks_done: number; consecutive_failures: number; ends_at: Date }>(
      "SELECT state, next_check_at, checks_done, consecutive_failures, ends_at FROM price_watches WHERE id = $1 FOR UPDATE", [w.id]);
    const r = rows[0];
    if (!r) return { result: "superseded", state: "deleted" };
    if (r.state !== "active" || !r.next_check_at || r.next_check_at.getTime() !== w.lease.getTime()) return { result: "superseded", state: r.state };
    const d = decide({ checksDone: r.checks_done, consecutiveFailures: r.consecutive_failures, endsAt: r.ends_at }, verdict, now, interval, ctx.jitterMs(interval));
    const ended = d.state !== "active";
    await c.query(
      `UPDATE price_watches SET state = $2, next_check_at = $3, checks_done = $4, consecutive_failures = $5,
         last_checked_at = $6, last_price_minor = coalesce($7, last_price_minor),
         triggered_at = $8, triggered_price_minor = $9, finished_at = $10, failure = $11
       WHERE id = $1`,
      [w.id, d.state, d.nextCheckAt ?? null, d.checksDone, d.consecutiveFailures, now, d.priceMinor ?? null,
        d.state === "triggered" ? now : null, d.state === "triggered" ? d.priceMinor : null,
        ended ? now : null, d.state === "failed" ? "unreadable" : null]);
    if (d.push) await queuePush(c, ctx, w, d.push, now);
    return { result: d.state === "active" ? "checked" : d.state, state: d.state, checksDone: d.checksDone, failures: d.consecutiveFailures };
  });
  ctx.log("watch checked", {
    watchId: w.id, result: out.result, verdict: verdict.kind, cause: verdict.kind === "failed" ? verdict.cause : undefined,
    state: out.state, checksDone: out.checksDone, consecutiveFailures: out.failures,
  });
  return out.result;
}

/** The push is queued in the same transaction as the state change, once per watch (the key is the watch and the kind). */
async function queuePush(c: pg.PoolClient, ctx: WatchContext, w: Claimed, kind: "triggered" | "failed", now: Date): Promise<void> {
  if (!ctx.push || !(await canPush(c, w.account_id))) return; // the watch is still triggered/failed: the app shows it when opened
  await enqueue(c, w.account_id, ["push"], pushText(kind, w.language), now, `watch-${kind}:${w.id}`, { cipher: ctx.cipher });
}
