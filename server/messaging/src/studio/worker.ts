// Studio's background passes (ADR-584, STUDIO.md), in their own loop like errands. A queued item is
// claimed with FOR UPDATE SKIP LOCKED before any model call, so no job runs twice. The outcome is
// stored in steps: files first (stage `store`), then each file is read back and compared by SHA-256,
// and only then the item becomes ready and the push is queued. The push never carries words.
import type pg from "pg";
import { sameBytes } from "../crypto.js";
import { inTransaction } from "../db.js";
import { canPush, enqueue } from "../outbox.js";
import { sha256, type MadeFile } from "./checks.js";
import { fileAad, resultAad, type StudioContext } from "./context.js";
import { runStudio, type StudioOutcome } from "./pipeline.js";
import { FILE_SPECS, jobDigest, type Stage } from "./schema.js";
import { decryptJob } from "./service.js";

export const MAX_CONCURRENT_RUNS = 2;
export const INTERRUPTED_GRACE_MS = 5 * 60_000;
const TIDY_BATCH = 20;

export const PUSH_TEXT = {
  ready: { pl: "Gotowe. Twój materiał czeka w Studiu.", en: "Ready. Your Studio item is waiting in the app." },
  needs_look: { pl: "Gotowe, ale coś wymaga sprawdzenia. Zajrzyj do Studia.", en: "Ready, but something needs a look. It's in Studio." },
  failed: { pl: "Nie udało się przygotować materiału.", en: "Doddy couldn't finish a Studio item." },
} as const;
export const pushText = (kind: keyof typeof PUSH_TEXT, language: string) => (language === "pl" ? PUSH_TEXT[kind].pl : PUSH_TEXT[kind].en);

export interface StudioLoopState { runs: Map<string, Promise<void>>; shutdown: AbortController }
export const newStudioLoopState = (): StudioLoopState => ({ runs: new Map(), shutdown: new AbortController() });

export async function runStudioPasses(ctx: StudioContext, state: StudioLoopState): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  const run = async (name: string, fn: () => Promise<number>) => {
    try {
      const n = await fn();
      if (n) counts[name] = n;
    } catch (err) {
      ctx.log("studio pass failed", { pass: name, error: (err as Error).message.slice(0, 200) });
    }
  };
  await run("interrupted", () => reapInterrupted(ctx));
  await run("drafts", () => expireDrafts(ctx));
  await run("anthropic_files", () => tidyAnthropicFiles(ctx));
  if (ctx.enabled && !state.shutdown.signal.aborted) {
    await run("started", async () => {
      let started = 0;
      while (state.runs.size < MAX_CONCURRENT_RUNS) {
        const claimed = await claimNext(ctx);
        if (!claimed) break;
        const p = runClaimed(ctx, claimed, state.shutdown.signal)
          .then(() => {}, (err) => ctx.log("studio run failed", { itemId: claimed.id, error: (err as Error).message.slice(0, 200) }))
          .finally(() => state.runs.delete(claimed.id));
        state.runs.set(claimed.id, p);
        started++;
      }
      return started;
    });
  }
  return counts;
}

export async function stopStudioRuns(state: StudioLoopState): Promise<void> {
  state.shutdown.abort();
  await Promise.allSettled([...state.runs.values()]);
}

interface Claimed { id: string; account_id: string; language: string; job_ciphertext: Buffer; payload_digest: Buffer; started_at: Date }

export async function claimNext(ctx: StudioContext): Promise<Claimed | undefined> {
  const { rows } = await ctx.db.query<Claimed>(
    `UPDATE studio_items s SET state = 'running', stage = 'plan', started_at = $1, model = $2
     WHERE s.id = (SELECT id FROM studio_items WHERE state = 'queued' ORDER BY approved_at, id LIMIT 1 FOR UPDATE SKIP LOCKED)
     RETURNING s.id, s.account_id, s.language, s.job_ciphertext, s.payload_digest, s.started_at`,
    [ctx.now(), ctx.api?.model.slice(0, 64) ?? null]);
  return rows[0];
}

/** Claims the oldest queued item and runs it to the end (tests and one-off runs). */
export async function runNext(ctx: StudioContext, shutdown?: AbortSignal): Promise<string | undefined> {
  if (!ctx.enabled) return undefined;
  const claimed = await claimNext(ctx);
  if (!claimed) return undefined;
  await runClaimed(ctx, claimed, shutdown);
  return claimed.id;
}

const noStats = (model = "unknown") => ({
  usage: { inputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0, outputTokens: 0 }, searches: 0, fetches: 0, containerSeconds: 0, costUsd: 0, model,
});

export async function runClaimed(ctx: StudioContext, e: Claimed, shutdown?: AbortSignal): Promise<void> {
  const api = ctx.api;
  const job = decryptJob(ctx, e.account_id, e.id, e.job_ciphertext);
  // Only exactly what was approved runs.
  if (!api || !job || !sameBytes(jobDigest(job), e.payload_digest)) {
    ctx.log("studio job check failed; not run", { itemId: e.id });
    await finish(ctx, e, { kind: "failed", code: "interrupted", pending: [], ...noStats(api?.model) });
    return;
  }
  const deadline = new Date(e.started_at.getTime() + ctx.settings.timeLimitMinutes * 60_000);
  const isCancelled = async () => {
    const { rows } = await ctx.db.query<{ state: string; cancel_requested_at: Date | null }>(
      "SELECT state, cancel_requested_at FROM studio_items WHERE id = $1", [e.id]);
    const r = rows[0];
    return !r || r.state !== "running" || r.cancel_requested_at !== null;
  };
  const setStage = async (stage: Stage) => {
    await ctx.db.query("UPDATE studio_items SET stage = $2 WHERE id = $1 AND state = 'running'", [e.id, stage]);
  };
  ctx.log("studio started", { itemId: e.id, model: api.model, timeLimitMinutes: ctx.settings.timeLimitMinutes });
  let outcome: StudioOutcome;
  try {
    outcome = await runStudio(api, job, {
      deadline, isCancelled, setStage, signal: shutdown, jobLimitUsd: ctx.settings.jobLimitUsd,
      now: ctx.now, cancelPollMs: ctx.cancelPollMs, log: ctx.log,
    });
  } catch (err) {
    ctx.log("studio pipeline threw", { itemId: e.id, error: (err as Error).name });
    outcome = { kind: "failed", code: "interrupted", pending: [], ...noStats(api.model) };
  }
  await finish(ctx, e, outcome);
}

async function push(c: pg.PoolClient, ctx: StudioContext, accountId: string, id: string, kind: keyof typeof PUSH_TEXT, language: string, now: Date) {
  if (ctx.push && await canPush(c, accountId)) {
    await enqueue(c, accountId, ["push"], pushText(kind, language), now, `studio-result:${id}`, { cipher: ctx.cipher });
  }
}

/** Reads every stored file back and compares it with what was made. */
async function readBack(ctx: StudioContext, e: Claimed, files: MadeFile[]): Promise<boolean> {
  const { rows } = await ctx.db.query<{ name: string; sha256: Buffer; ciphertext: Buffer }>(
    "SELECT name, sha256, ciphertext FROM studio_files WHERE item_id = $1", [e.id]);
  if (rows.length !== files.length) return false;
  for (const f of files) {
    const row = rows.find((r) => r.name === f.name);
    if (!row) return false;
    try {
      const bytes = ctx.cipher.decryptBytes(row.ciphertext, fileAad(e.account_id, e.id, f.name));
      if (!sameBytes(sha256(bytes), sha256(f.bytes)) || !sameBytes(row.sha256, sha256(f.bytes))) return false;
    } catch {
      return false;
    }
  }
  return true;
}

async function finish(ctx: StudioContext, e: Claimed, outcome: StudioOutcome): Promise<void> {
  const now = ctx.now();
  const u = outcome.usage;
  const stats = [e.id, outcome.searches, outcome.fetches, u.inputTokens, u.cacheWriteTokens, u.cacheReadTokens, u.outputTokens,
    outcome.containerSeconds, outcome.costUsd, outcome.pending];
  const setStats = `searches = $2, fetches = $3, input_tokens = $4, cache_write_tokens = $5, cache_read_tokens = $6, output_tokens = $7,
    container_seconds = $8, cost_usd = $9, anthropic_files_pending = $10`;

  // Step 1: files stored (still running, stage `store`), unless the user cancelled or deleted meanwhile.
  let stored = false;
  if (outcome.kind === "made") {
    stored = await inTransaction(ctx.db, async (c) => {
      const { rows } = await c.query<{ state: string; cancel_requested_at: Date | null }>(
        "SELECT state, cancel_requested_at FROM studio_items WHERE id = $1 FOR UPDATE", [e.id]);
      const r = rows[0];
      if (!r || r.state !== "running" || r.cancel_requested_at) return false;
      await c.query("DELETE FROM studio_files WHERE item_id = $1", [e.id]);
      for (const f of outcome.files) {
        const spec = FILE_SPECS[f.name];
        await c.query(
          `INSERT INTO studio_files (item_id, name, role, mime, bytes, sha256, key_version, ciphertext, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
          [e.id, f.name, spec.role, spec.mime, f.bytes.length, sha256(f.bytes), ctx.cipher.keyVersion,
            ctx.cipher.encryptBytes(f.bytes, fileAad(e.account_id, e.id, f.name)), now]);
      }
      await c.query(`UPDATE studio_items SET stage = 'store', ${setStats} WHERE id = $1`, stats);
      return true;
    });
  }
  const readOk = stored && outcome.kind === "made" ? await readBack(ctx, e, outcome.files) : false;

  // Step 2: the final state and the push, in one transaction. A user's Cancel wins over a late result.
  const final = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; cancel_requested_at: Date | null }>(
      "SELECT state, cancel_requested_at FROM studio_items WHERE id = $1 FOR UPDATE", [e.id]);
    const r = rows[0];
    if (!r || r.state !== "running") return r ? `already_${r.state}` : "deleted";
    const end = `stage = NULL, finished_at = $11, ${setStats}`;
    if (outcome.kind === "cancelled" || r.cancel_requested_at) {
      await c.query("DELETE FROM studio_files WHERE item_id = $1", [e.id]);
      await c.query(`UPDATE studio_items SET state = 'cancelled', ${end} WHERE id = $1`, [...stats, now]);
      return "cancelled";
    }
    if (outcome.kind === "made" && readOk) {
      await c.query(
        `UPDATE studio_items SET state = $12, result_key_version = $13, result_ciphertext = $14, ${end} WHERE id = $1`,
        [...stats, now, outcome.state, ctx.cipher.keyVersion, ctx.cipher.encrypt(JSON.stringify(outcome.result), resultAad(e.account_id, e.id))]);
      await push(c, ctx, e.account_id, e.id, outcome.state, e.language, now);
      return outcome.state;
    }
    const code = outcome.kind === "failed" ? outcome.code : "unreadable_result";
    await c.query("DELETE FROM studio_files WHERE item_id = $1", [e.id]);
    await c.query(`UPDATE studio_items SET state = 'failed', failure = $12, ${end} WHERE id = $1`, [...stats, now, code]);
    await push(c, ctx, e.account_id, e.id, "failed", e.language, now);
    return "failed";
  });
  ctx.log("studio finished", {
    itemId: e.id, state: final, failure: outcome.kind === "failed" ? outcome.code : undefined, model: outcome.model,
    searches: outcome.searches, fetches: outcome.fetches, inputTokens: u.inputTokens, outputTokens: u.outputTokens,
    cacheReadTokens: u.cacheReadTokens, cacheWriteTokens: u.cacheWriteTokens, containerSeconds: outcome.containerSeconds,
    costUsd: outcome.costUsd, anthropicPending: outcome.pending.length,
  });
}

/** The worker stopped mid-run: `interrupted` (or `cancelled` if the user had asked), never re-run. */
export async function reapInterrupted(ctx: StudioContext): Promise<number> {
  const now = ctx.now();
  const before = new Date(now.getTime() - ctx.settings.timeLimitMinutes * 60_000 - INTERRUPTED_GRACE_MS);
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ id: string; account_id: string; language: string; state: string }>(
      `UPDATE studio_items SET
         state = CASE WHEN cancel_requested_at IS NULL THEN 'failed' ELSE 'cancelled' END,
         failure = CASE WHEN cancel_requested_at IS NULL THEN 'interrupted' END,
         stage = NULL, finished_at = $1
       WHERE id IN (SELECT id FROM studio_items WHERE state = 'running' AND started_at < $2 LIMIT 20 FOR UPDATE SKIP LOCKED)
       RETURNING id, account_id, language, state`, [now, before]);
    for (const r of rows) {
      await c.query("DELETE FROM studio_files WHERE item_id = $1", [r.id]);
      if (r.state === "failed") await push(c, ctx, r.account_id, r.id, "failed", r.language, now);
      ctx.log("studio interrupted", { itemId: r.id, state: r.state });
    }
    return rows.length;
  });
}

export async function expireDrafts(ctx: StudioContext): Promise<number> {
  const { rowCount } = await ctx.db.query("DELETE FROM studio_items WHERE state = 'draft' AND expires_at <= $1", [ctx.now()]);
  return rowCount ?? 0;
}

/** Keeps deleting copies left at Anthropic, on items and orphans, until each reads back as gone. */
export async function tidyAnthropicFiles(ctx: StudioContext): Promise<number> {
  const api = ctx.api;
  if (!api) return 0;
  let confirmed = 0;
  const gone = async (id: string) => {
    try {
      await api.deleteFile(id, AbortSignal.timeout(20_000)).catch(() => {});
      return await api.fileGone(id, AbortSignal.timeout(20_000));
    } catch {
      return false;
    }
  };
  const { rows: items } = await ctx.db.query<{ id: string; anthropic_files_pending: string[] }>(
    `SELECT id, anthropic_files_pending FROM studio_items WHERE anthropic_files_pending <> '{}' LIMIT ${TIDY_BATCH}`);
  for (const item of items) {
    const left: string[] = [];
    for (const id of item.anthropic_files_pending) {
      if (await gone(id)) confirmed++;
      else left.push(id);
    }
    await ctx.db.query("UPDATE studio_items SET anthropic_files_pending = $2 WHERE id = $1", [item.id, left]);
  }
  const { rows: orphans } = await ctx.db.query<{ file_id: string }>(`SELECT file_id FROM studio_orphan_files ORDER BY since LIMIT ${TIDY_BATCH}`);
  for (const o of orphans) {
    if (await gone(o.file_id)) {
      await ctx.db.query("DELETE FROM studio_orphan_files WHERE file_id = $1", [o.file_id]);
      confirmed++;
    }
  }
  return confirmed;
}
