// Background passes for errands (ERRANDS.md "The runner"), run by their own loop so a 30-minute
// research run never holds back pushes or call cases. Safe in several processes at once: an errand
// is claimed with FOR UPDATE SKIP LOCKED in a committed transaction before any model call, and every
// later write is guarded by `state = 'running'`.
//   - a claimed errand is researched; its result (or failure) and the push go in one transaction;
//   - a running errand older than the time limit + 5 minutes (the worker died) ends `interrupted`
//     and is never re-run by itself;
//   - drafts older than 10 minutes are deleted; content of finished errands that the app never
//     acknowledged is deleted 30 days after they finished, with receipts.
// The push never carries words from the errand, not even its title.
import type pg from "pg";
import { sameBytes } from "../crypto.js";
import { inTransaction } from "../db.js";
import { canPush, enqueue } from "../outbox.js";
import { resultAad, type ErrandContext } from "./context.js";
import type { ResearchOutcome } from "./researcher.js";
import { contentDigest, resultDigest, resultJson } from "./schema.js";
import { decryptContent, wipeContent } from "./service.js";

export const MAX_CONCURRENT_RUNS = 3;
/** A running errand this long past its time limit has lost its worker. */
export const INTERRUPTED_GRACE_MS = 5 * 60_000;
export const UNACKED_DAYS = 30;

export const PUSH_TEXT = {
  done: { pl: "Gotowe. Wynik sprawy czeka w aplikacji.", en: "Done. Your task's result is waiting in the app." },
  failed: { pl: "Nie udało się dokończyć sprawy.", en: "Doddy couldn't finish a task." },
} as const;
export const pushText = (kind: "done" | "failed", language: string) => (language === "pl" ? PUSH_TEXT[kind].pl : PUSH_TEXT[kind].en);

export interface ErrandLoopState {
  runs: Map<string, Promise<void>>;
  /** Aborted on shutdown: running errands end as `interrupted` right away instead of 35 minutes later. */
  shutdown: AbortController;
}
export const newErrandLoopState = (): ErrandLoopState => ({ runs: new Map(), shutdown: new AbortController() });

export interface PassCounts { [pass: string]: number }

/** One pass: tidy, then start queued errands up to MAX_CONCURRENT_RUNS in this process (not awaited). */
export async function runErrandPasses(ctx: ErrandContext, state: ErrandLoopState): Promise<PassCounts> {
  const counts: PassCounts = {};
  const run = async (name: string, fn: () => Promise<number>) => {
    try {
      const n = await fn();
      if (n) counts[name] = n;
    } catch (err) {
      ctx.log("errand pass failed", { pass: name, error: (err as Error).message.slice(0, 200) });
    }
  };
  await run("interrupted", () => reapInterrupted(ctx));
  await run("drafts", () => expireDrafts(ctx));
  await run("unacked", () => expireUnacked(ctx));
  if (ctx.enabled && !state.shutdown.signal.aborted) {
    await run("started", async () => {
      let started = 0;
      while (state.runs.size < MAX_CONCURRENT_RUNS) {
        const claimed = await claimNext(ctx);
        if (!claimed) break;
        const p = runClaimed(ctx, claimed, state.shutdown.signal)
          .then(() => {}, (err) => ctx.log("errand run failed", { errandId: claimed.id, error: (err as Error).message.slice(0, 200) }))
          .finally(() => state.runs.delete(claimed.id));
        state.runs.set(claimed.id, p);
        started++;
      }
      return started;
    });
  }
  return counts;
}

/** Shutdown: running errands stop now and are stored as `interrupted`. */
export async function stopErrandRuns(state: ErrandLoopState): Promise<void> {
  state.shutdown.abort();
  await Promise.allSettled([...state.runs.values()]);
}

/** Claims the oldest queued errand and runs it to the end (tests and one-off runs). */
export async function researchNext(ctx: ErrandContext, shutdown?: AbortSignal): Promise<string | undefined> {
  if (!ctx.enabled) return undefined;
  const claimed = await claimNext(ctx);
  if (!claimed) return undefined;
  await runClaimed(ctx, claimed, shutdown);
  return claimed.id;
}

interface Claimed { id: string; account_id: string; language: string; content_ciphertext: Buffer; payload_digest: Buffer; started_at: Date }

/** Committed before any model call, so no errand runs twice. */
export async function claimNext(ctx: ErrandContext): Promise<Claimed | undefined> {
  const { rows } = await ctx.db.query<Claimed>(
    `UPDATE errands e SET state = 'running', started_at = $1, model = $2
     WHERE e.id = (SELECT id FROM errands WHERE state = 'queued' ORDER BY approved_at, id LIMIT 1 FOR UPDATE SKIP LOCKED)
     RETURNING e.id, e.account_id, e.language, e.content_ciphertext, e.payload_digest, e.started_at`,
    [ctx.now(), ctx.researcher?.model.slice(0, 64) ?? null]);
  return rows[0];
}

export async function runClaimed(ctx: ErrandContext, e: Claimed, shutdown?: AbortSignal): Promise<void> {
  const researcher = ctx.researcher;
  const content = decryptContent(ctx, e.account_id, e.id, e.content_ciphertext);
  // Only exactly what was approved runs.
  if (!researcher || !content || !sameBytes(contentDigest(content), e.payload_digest)) {
    ctx.log("errand content check failed; not run", { errandId: e.id });
    await finish(ctx, e, { kind: "failed", code: "interrupted", ...noStats(researcher?.model) });
    return;
  }
  const deadline = new Date(e.started_at.getTime() + ctx.settings.timeLimitMinutes * 60_000);
  const isCancelled = async () => {
    const { rows } = await ctx.db.query<{ state: string; cancel_requested_at: Date | null }>(
      "SELECT state, cancel_requested_at FROM errands WHERE id = $1", [e.id]);
    const r = rows[0];
    return !r || r.state !== "running" || r.cancel_requested_at !== null;
  };
  ctx.log("errand started", { errandId: e.id, model: researcher.model, timeLimitMinutes: ctx.settings.timeLimitMinutes });
  let outcome: ResearchOutcome;
  try {
    outcome = await researcher.research(
      {
        id: e.id, words: content.words, brief: content.brief, language: content.language,
        ...(content.kind ? { kind: content.kind, priorities: content.priorities ?? [] } : {}),
      },
      { deadline, isCancelled, signal: shutdown, now: ctx.now, cancelPollMs: ctx.cancelPollMs, log: ctx.log });
  } catch (err) {
    ctx.log("errand researcher threw", { errandId: e.id, error: (err as Error).name });
    outcome = { kind: "failed", code: "interrupted", ...noStats(researcher.model) };
  }
  await finish(ctx, e, outcome);
}

const noStats = (model = "unknown") => ({ usage: { inputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0, outputTokens: 0 }, searches: 0, fetches: 0, model });

async function push(c: pg.PoolClient, ctx: ErrandContext, accountId: string, id: string, kind: "done" | "failed", language: string, now: Date) {
  if (ctx.push && await canPush(c, accountId)) {
    await enqueue(c, accountId, ["push"], pushText(kind, language), now, `errand-result:${id}`, { cipher: ctx.cipher });
  }
}

/** Stores the outcome and queues the push in one transaction. A user's Cancel wins over a late result. */
async function finish(ctx: ErrandContext, e: Claimed, outcome: ResearchOutcome): Promise<void> {
  const now = ctx.now();
  const u = outcome.usage;
  const final = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; cancel_requested_at: Date | null }>(
      "SELECT state, cancel_requested_at FROM errands WHERE id = $1 FOR UPDATE", [e.id]);
    const r = rows[0];
    if (!r || r.state !== "running") return r ? `already_${r.state}` : "deleted";
    const stats = [e.id, now, outcome.searches, outcome.fetches, u.inputTokens, u.cacheWriteTokens, u.cacheReadTokens, u.outputTokens, outcome.model.slice(0, 64)];
    // The model that actually ran (a shopping errand runs on the shopping model, not the one claimed).
    const set = `finished_at = $2, searches = $3, fetches = $4, input_tokens = $5, cache_write_tokens = $6, cache_read_tokens = $7, output_tokens = $8, model = $9`;
    if (outcome.kind === "cancelled" || r.cancel_requested_at) {
      await c.query(`UPDATE errands SET state = 'cancelled', ${set} WHERE id = $1`, stats);
      return "cancelled";
    }
    if (outcome.kind === "done") {
      await c.query(
        `UPDATE errands SET state = 'done', ${set}, result_key_version = $10, result_ciphertext = $11, result_digest = $12 WHERE id = $1`,
        [...stats, ctx.cipher.keyVersion, ctx.cipher.encrypt(resultJson(outcome.result), resultAad(e.account_id, e.id)), resultDigest(outcome.result)]);
      await push(c, ctx, e.account_id, e.id, "done", e.language, now);
      return "done";
    }
    await c.query(`UPDATE errands SET state = 'failed', failure = $10, ${set} WHERE id = $1`, [...stats, outcome.code]);
    await push(c, ctx, e.account_id, e.id, "failed", e.language, now);
    return "failed";
  });
  // Cost visibility: ids and counts only.
  ctx.log("errand finished", {
    errandId: e.id, state: final, failure: outcome.kind === "failed" ? outcome.code : undefined, model: outcome.model,
    searches: outcome.searches, fetches: outcome.fetches, inputTokens: u.inputTokens, cacheWriteTokens: u.cacheWriteTokens,
    cacheReadTokens: u.cacheReadTokens, outputTokens: u.outputTokens,
  });
}

/** The worker stopped mid-run: `interrupted` (or `cancelled` if the user had asked), never re-run. */
export async function reapInterrupted(ctx: ErrandContext): Promise<number> {
  const now = ctx.now();
  const before = new Date(now.getTime() - ctx.settings.timeLimitMinutes * 60_000 - INTERRUPTED_GRACE_MS);
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ id: string; account_id: string; language: string; state: string }>(
      `UPDATE errands SET
         state = CASE WHEN cancel_requested_at IS NULL THEN 'failed' ELSE 'cancelled' END,
         failure = CASE WHEN cancel_requested_at IS NULL THEN 'interrupted' END,
         finished_at = $1
       WHERE id IN (SELECT id FROM errands WHERE state = 'running' AND started_at < $2 LIMIT 20 FOR UPDATE SKIP LOCKED)
       RETURNING id, account_id, language, state`, [now, before]);
    for (const r of rows) {
      if (r.state === "failed") await push(c, ctx, r.account_id, r.id, "failed", r.language, now);
      ctx.log("errand interrupted", { errandId: r.id, state: r.state });
    }
    return rows.length;
  });
}

/** A draft never approved is deleted after 10 minutes. */
export async function expireDrafts(ctx: ErrandContext): Promise<number> {
  const { rowCount } = await ctx.db.query("DELETE FROM errands WHERE state = 'draft' AND expires_at <= $1", [ctx.now()]);
  return rowCount ?? 0;
}

/** Content of a finished errand the app never acknowledged (or deleted) goes after 30 days. */
export async function expireUnacked(ctx: ErrandContext): Promise<number> {
  const now = ctx.now();
  const { rows } = await ctx.db.query<{ id: string }>(
    `SELECT id FROM errands WHERE content_ciphertext IS NOT NULL AND finished_at IS NOT NULL
       AND finished_at <= $1::timestamptz - make_interval(days => $2) ORDER BY finished_at LIMIT 50`, [now, UNACKED_DAYS]);
  let n = 0;
  for (const r of rows) {
    const wiped = await inTransaction(ctx.db, async (c) => {
      const { rows: locked } = await c.query<{ account_id: string; result_ciphertext: Buffer | null }>(
        "SELECT account_id, result_ciphertext FROM errands WHERE id = $1 AND content_ciphertext IS NOT NULL FOR UPDATE SKIP LOCKED", [r.id]);
      const e = locked[0];
      return e ? wipeContent(c, e.account_id, r.id, e.result_ciphertext !== null, "expired", now) : false;
    });
    if (wiped) n++;
  }
  return n;
}

