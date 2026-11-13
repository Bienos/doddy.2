// Studio, the app's side (ADR-740, STUDIO.md "Server API"): create a draft, approve it by its digest
// within the daily cap, read, download a file, cancel and delete. The rules:
//   - a draft stores the job encrypted, exactly as sent, with its SHA-256;
//   - only a draft can be approved, only with its own digest, only within 10 minutes, only while the
//     account has fewer than STUDIO_MAX_OPEN open jobs and today's spend plus a reserve per open job
//     stays within STUDIO_DAILY_CAP_USD (counted under an advisory lock);
//   - the money is capped in code, not in a prompt (ADR-742): per job (STUDIO_JOB_LIMIT_USD, checked by the
//     pipeline after every model request), per account and day, and for the whole server and day. The server's
//     counts (approvals, the new-account pool, committed dollars) live in tables with no account in them, so
//     deleting an item or an account can't give a day back; each approval commits STUDIO_JOB_LIMIT_USD of
//     STUDIO_DAILY_SERVER_CAP_USD and of STUDIO_MONTHLY_SERVER_CAP_USD (the whole server, a UTC calendar month,
//     the hard ceiling), and a job that ends gives back what it didn't spend;
//   - delete says "deleted" only after the item and its files read back as gone.
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { sameBytes } from "../crypto.js";
import { inTransaction } from "../db.js";
import { textLinkFields } from "../errands/links.js";
import { takeServerSlots } from "../serverUsage.js";
import { fileAad, jobAad, resultAad, RESERVE_PER_OPEN_JOB_USD, type StudioContext } from "./context.js";
import { appState, jobBody, jobDigest, jobJson, type ItemState, type Stage, type StudioJob, type StudioResult } from "./schema.js";

export const DRAFT_MINUTES = 10;
export const LIST_LIMIT = 50;

export type Refusal =
  | { status: 400; error: "invalid_request"; fields: string[] }
  | { status: 404; error: "not_found" }
  | { status: 409; error: "not_approvable"; state: string }
  | { status: 409; error: "digest_mismatch" | "too_many_open_items" }
  | { status: 409; error: "daily_cap_reached"; capUsd: number; spentUsd: number }
  | { status: 429; error: "studio_daily_limit"; scope: "account" | "server" }
  | { status: 429; error: "studio_monthly_limit" }
  | { status: 503; error: "studio_disabled" };

const refuse = (r: Refusal) => ({ refusal: r });

interface ItemRow {
  id: string; account_id: string; kind: string; state: ItemState; stage: Stage | null; language: string;
  job_ciphertext: Buffer; payload_digest: Buffer; result_ciphertext: Buffer | null; failure: string | null;
  searches: number; fetches: number; input_tokens: string; cache_write_tokens: string; cache_read_tokens: string;
  output_tokens: string; container_seconds: number; cost_usd: string; model: string | null;
  created_at: Date; expires_at: Date; approved_at: Date | null; started_at: Date | null; finished_at: Date | null;
}

export function decryptJob(ctx: StudioContext, accountId: string, id: string, blob: Buffer): StudioJob | undefined {
  try {
    return jobBody.parse(JSON.parse(ctx.cipher.decrypt(blob, jobAad(accountId, id))));
  } catch {
    return undefined; // a key this server doesn't have, or a tampered row
  }
}

function decryptResult(ctx: StudioContext, accountId: string, id: string, blob: Buffer): StudioResult | undefined {
  try {
    return JSON.parse(ctx.cipher.decrypt(blob, resultAad(accountId, id))) as StudioResult;
  } catch {
    return undefined;
  }
}

const iso = (d: Date | null) => (d ? d.toISOString() : null);
const startOfUtcDay = (d: Date) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));

// ---------- create and approve ----------

export async function createItem(ctx: StudioContext, accountId: string, body: unknown) {
  if (!ctx.enabled) return refuse({ status: 503, error: "studio_disabled" });
  const parsed = jobBody.safeParse(body);
  if (!parsed.success) return refuse({ status: 400, error: "invalid_request", fields: parsed.error.issues.map((i) => i.path.join(".")) });
  const job = parsed.data;
  // No link in the brief's text (ADR-703's rule for errands): the research step can fetch any address that appears
  // in what it was given. Sources are the place for addresses. The field names are answered, never the text.
  const links = textLinkFields({ topic: job.topic, audience: job.audience, details: job.details });
  if (links.length) return refuse({ status: 400, error: "invalid_request", fields: links });
  const now = ctx.now();
  const id = randomUUID();
  const digest = jobDigest(job);
  const expiresAt = new Date(now.getTime() + DRAFT_MINUTES * 60_000);
  await ctx.db.query(
    `INSERT INTO studio_items (id, account_id, kind, state, language, job_key_version, job_ciphertext, payload_digest, created_at, expires_at)
     VALUES ($1, $2, $3, 'draft', $4, $5, $6, $7, $8, $9)`,
    [id, accountId, job.kind, job.language, ctx.cipher.keyVersion, ctx.cipher.encrypt(jobJson(job), jobAad(accountId, id)), digest, now, expiresAt]);
  ctx.log("studio drafted", { itemId: id, kind: job.kind });
  return { draft: { id, digest: digest.toString("hex"), job, expiresAt: expiresAt.toISOString() } };
}

/** Today's spend (UTC) on items approved today, and how many jobs are open. */
async function spend(c: { query: StudioContext["db"]["query"] }, accountId: string, now: Date) {
  const { rows } = await c.query<{ spent: string; open: number }>(
    `SELECT coalesce(sum(cost_usd) FILTER (WHERE approved_at >= $2), 0)::text AS spent,
            count(*) FILTER (WHERE state IN ('queued', 'running'))::int AS open
     FROM studio_items WHERE account_id = $1`, [accountId, startOfUtcDay(now)]);
  return { spent: Number(rows[0]?.spent ?? 0), open: rows[0]?.open ?? 0 };
}

/** Thrown inside the approval's transaction to undo what the earlier checks took (a count, a reservation). */
class Refused extends Error {
  constructor(readonly refusal: Refusal) { super(refusal.error); }
}

export async function approveItem(ctx: StudioContext, accountId: string, id: string, digestHex: string) {
  if (!ctx.enabled) return refuse({ status: 503, error: "studio_disabled" });
  const now = ctx.now();
  const given = Buffer.from(digestHex, "hex");
  try {
    const r = await inTransaction(ctx.db, async (c) => {
      await c.query("SELECT pg_advisory_xact_lock(hashtext('studio:' || $1))", [accountId]);
      const { rows } = await c.query<{ state: string; payload_digest: Buffer; expires_at: Date }>(
        "SELECT state, payload_digest, expires_at FROM studio_items WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
      const e = rows[0];
      if (!e) return refuse({ status: 404, error: "not_found" });
      if (e.state !== "draft" || e.expires_at <= now) return refuse({ status: 409, error: "not_approvable", state: e.state === "draft" ? "expired" : e.state });
      if (!sameBytes(e.payload_digest, given)) return refuse({ status: 409, error: "digest_mismatch" });
      const { spent, open } = await spend(c, accountId, now);
      if (open >= ctx.settings.maxOpen) return refuse({ status: 409, error: "too_many_open_items" });
      // The real cost of open jobs isn't known yet: each holds a reserve, this one included.
      if (spent + (open + 1) * RESERVE_PER_OPEN_JOB_USD > ctx.settings.dailyCapUsd) {
        return refuse({ status: 409, error: "daily_cap_reached", capUsd: ctx.settings.dailyCapUsd, spentUsd: Math.round(spent * 100) / 100 });
      }
      // The limits no deletion can reset (ADR-742), taken in this transaction: a refusal below rolls them all back.
      const day = now.toISOString().slice(0, 10);
      const { rowCount: perAccount } = await c.query(
        `INSERT INTO studio_usage (account_id, day, approvals) VALUES ($1, $2, 1)
         ON CONFLICT (account_id, day) DO UPDATE SET approvals = studio_usage.approvals + 1
           WHERE studio_usage.approvals < $3`, [accountId, day, ctx.settings.dailyPerAccount]);
      if (perAccount !== 1) throw new Refused({ status: 429, error: "studio_daily_limit", scope: "account" });
      const reserve = ctx.settings.jobLimitUsd;
      const { rowCount: dollars } = await c.query(
        `INSERT INTO studio_server_spend (day, committed_usd) SELECT $1::date, $2::numeric WHERE $2::numeric <= $3::numeric
         ON CONFLICT (day) DO UPDATE SET committed_usd = studio_server_spend.committed_usd + $2::numeric
           WHERE studio_server_spend.committed_usd + $2::numeric <= $3::numeric`, [day, reserve, ctx.settings.dailyServerCapUsd]);
      if (dollars !== 1) throw new Refused({ status: 429, error: "studio_daily_limit", scope: "server" });
      // The month's ceiling: the most the whole server can commit to Studio in a UTC calendar month.
      const month = `${day.slice(0, 7)}-01`;
      const { rowCount: monthly } = await c.query(
        `INSERT INTO studio_server_spend_month (month, committed_usd) SELECT $1::date, $2::numeric WHERE $2::numeric <= $3::numeric
         ON CONFLICT (month) DO UPDATE SET committed_usd = studio_server_spend_month.committed_usd + $2::numeric
           WHERE studio_server_spend_month.committed_usd + $2::numeric <= $3::numeric`, [month, reserve, ctx.settings.monthlyServerCapUsd]);
      if (monthly !== 1) throw new Refused({ status: 429, error: "studio_monthly_limit" });
      // An account still new draws from the new-account pool inside the server's count (ADR-702), 0 by default.
      const slots = await takeServerSlots(c, "studio", accountId, {
        perServer: ctx.settings.dailyPerServer, newAccountPool: ctx.settings.dailyForNewAccounts, newAccountHours: ctx.settings.newAccountHours,
      }, day);
      if (!slots.ok) throw new Refused({ status: 429, error: "studio_daily_limit", scope: "server" });
      await c.query("UPDATE studio_items SET state = 'queued', approved_at = $2, reserved_usd = $3 WHERE id = $1", [id, now, reserve]);
      return { approved: { id, state: "queued" as const } };
    });
    if ("approved" in r) ctx.log("studio approved", { itemId: id });
    return r;
  } catch (err) {
    if (err instanceof Refused) {
      ctx.log("studio approval refused", { itemId: id, error: err.refusal.error });
      return refuse(err.refusal);
    }
    throw err;
  }
}

/**
 * Settles an approval's reservation on the server's day and month once the job has ended (ADR-742): the day and month
 * then hold what the job spent instead of what was reserved. The day is the UTC day of the approval.
 *   - spent less than reserved: the rest goes back;
 *   - spent more (the last request went past the job's limit before the check after it): the excess is added, so
 *     spending is never given back;
 *   - `keepReservation` (a request was cut off mid-way, or the job was interrupted, so the real cost isn't known):
 *     nothing goes back; what was counted past the reservation is still added.
 * Never goes below zero.
 */
export async function releaseUnspent(c: Pick<pg.PoolClient, "query">, itemId: string, spentUsd: number, keepReservation = false): Promise<void> {
  // What stays committed for this job, and the change from the reservation (positive: given back).
  const back = `(i.reserved_usd - CASE WHEN $3::boolean THEN greatest(i.reserved_usd, $2::numeric) ELSE $2::numeric END)`;
  await c.query(
    `UPDATE studio_server_spend SET committed_usd = greatest(0, committed_usd - ${back})
     FROM studio_items i WHERE i.id = $1 AND i.approved_at IS NOT NULL AND studio_server_spend.day = (i.approved_at AT TIME ZONE 'utc')::date`,
    [itemId, spentUsd, keepReservation]);
  // The same change for the month the approval was counted in.
  await c.query(
    `UPDATE studio_server_spend_month SET committed_usd = greatest(0, committed_usd - ${back})
     FROM studio_items i WHERE i.id = $1 AND i.approved_at IS NOT NULL
       AND studio_server_spend_month.month = date_trunc('month', i.approved_at AT TIME ZONE 'utc')::date`,
    [itemId, spentUsd, keepReservation]);
}

// ---------- reads ----------

const cost = (e: ItemRow) => ({
  usd: Number(e.cost_usd), inputTokens: Number(e.input_tokens), outputTokens: Number(e.output_tokens),
  cacheReadTokens: Number(e.cache_read_tokens), cacheWriteTokens: Number(e.cache_write_tokens),
  searches: e.searches, fetches: e.fetches, containerSeconds: e.container_seconds,
});

export async function listItems(ctx: StudioContext, accountId: string) {
  const { rows } = await ctx.db.query<ItemRow>(
    `SELECT * FROM studio_items WHERE account_id = $1 AND state <> 'draft' ORDER BY created_at DESC, id LIMIT ${LIST_LIMIT}`, [accountId]);
  return rows.map((e) => {
    const result = e.result_ciphertext ? decryptResult(ctx, accountId, e.id, e.result_ciphertext) : undefined;
    return {
      id: e.id, kind: e.kind, title: result?.title ?? null, state: appState(e.state, e.stage),
      createdAt: iso(e.created_at), finishedAt: iso(e.finished_at), ...(e.failure ? { failure: e.failure } : {}),
      costUsd: Number(e.cost_usd),
    };
  });
}

export async function getItem(ctx: StudioContext, accountId: string, id: string) {
  const { rows } = await ctx.db.query<ItemRow>("SELECT * FROM studio_items WHERE id = $1 AND account_id = $2", [id, accountId]);
  const e = rows[0];
  if (!e || e.state === "draft") return undefined;
  const job = decryptJob(ctx, accountId, id, e.job_ciphertext);
  const result = e.result_ciphertext ? decryptResult(ctx, accountId, id, e.result_ciphertext) : undefined;
  const { rows: files } = await ctx.db.query<{ name: string; role: string; mime: string; bytes: number; sha256: Buffer }>(
    "SELECT name, role, mime, bytes, sha256 FROM studio_files WHERE item_id = $1 ORDER BY name", [id]);
  return {
    id, kind: e.kind, ...(job ? { job } : {}), digest: e.payload_digest.toString("hex"),
    title: result?.title ?? null, state: appState(e.state, e.stage),
    createdAt: iso(e.created_at), approvedAt: iso(e.approved_at), startedAt: iso(e.started_at), finishedAt: iso(e.finished_at),
    ...(result ? { summary: result.summary, sources: result.sources, checks: result.checks, skills: result.skills } : {}),
    files: files.map((f) => ({ name: f.name, role: f.role, mime: f.mime, bytes: f.bytes, sha256: f.sha256.toString("hex") })),
    cost: cost(e), model: e.model, ...(e.failure ? { failure: e.failure } : {}),
  };
}

export async function readFile(ctx: StudioContext, accountId: string, id: string, name: string) {
  const { rows } = await ctx.db.query<{ mime: string; ciphertext: Buffer; sha256: Buffer }>(
    `SELECT f.mime, f.ciphertext, f.sha256 FROM studio_files f JOIN studio_items i ON i.id = f.item_id
     WHERE f.item_id = $1 AND f.name = $2 AND i.account_id = $3`, [id, name, accountId]);
  const f = rows[0];
  if (!f) return undefined;
  try {
    const bytes = ctx.cipher.decryptBytes(f.ciphertext, fileAad(accountId, id, name));
    return { mime: f.mime, bytes };
  } catch {
    return undefined;
  }
}

// ---------- cancel and delete ----------

export async function cancelItem(ctx: StudioContext, accountId: string, id: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string }>("SELECT state FROM studio_items WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const e = rows[0];
    if (!e) return refuse({ status: 404, error: "not_found" });
    switch (e.state) {
      case "draft":
        await c.query("DELETE FROM studio_items WHERE id = $1", [id]);
        return { ok: "deleted" as const };
      case "queued":
        // It never ran, so nothing was spent: the whole reservation goes back to the server's day (ADR-742).
        await releaseUnspent(c, id, 0);
        await c.query("UPDATE studio_items SET state = 'cancelled', finished_at = $2 WHERE id = $1", [id, now]);
        return { ok: "cancelled" as const };
      case "running":
        await c.query("UPDATE studio_items SET cancel_requested_at = coalesce(cancel_requested_at, $2) WHERE id = $1", [id, now]);
        return { ok: "stopping" as const };
      default:
        return { ok: "finished" as const };
    }
  });
}

/** Before an account goes: copies at Anthropic not yet confirmed deleted are kept track of. */
export async function beforeAccountDeleted(db: StudioContext["db"], accountId: string, now: Date): Promise<void> {
  await db.query(
    `INSERT INTO studio_orphan_files (file_id, account_id, since)
     SELECT unnest(anthropic_files_pending), account_id, $2 FROM studio_items WHERE account_id = $1
     ON CONFLICT DO NOTHING`, [accountId, now]);
}

/**
 * Deletes the item and its files. Copies at Anthropic not yet confirmed gone move to
 * studio_orphan_files, where the worker keeps deleting them. Reports only after reading back.
 */
export async function deleteItem(ctx: StudioContext, accountId: string, id: string) {
  const now = ctx.now();
  const r = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ anthropic_files_pending: string[] }>(
      "SELECT anthropic_files_pending FROM studio_items WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const e = rows[0];
    if (!e) return refuse({ status: 404, error: "not_found" });
    const { rows: n } = await c.query<{ n: number }>("SELECT count(*)::int AS n FROM studio_files WHERE item_id = $1", [id]);
    for (const fileId of e.anthropic_files_pending) {
      await c.query("INSERT INTO studio_orphan_files (file_id, account_id, since) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING", [fileId, accountId, now]);
    }
    await c.query("DELETE FROM studio_items WHERE id = $1", [id]);
    return { files: n[0]?.n ?? 0, pending: e.anthropic_files_pending.length };
  });
  if ("refusal" in r) return r;
  const { rows: left } = await ctx.db.query<{ items: number; files: number }>(
    "SELECT (SELECT count(*)::int FROM studio_items WHERE id = $1) AS items, (SELECT count(*)::int FROM studio_files WHERE item_id = $1) AS files", [id]);
  if ((left[0]?.items ?? 1) !== 0 || (left[0]?.files ?? 1) !== 0) throw new Error("studio delete did not read back as gone");
  ctx.log("studio deleted", { itemId: id, files: r.files, anthropicPending: r.pending });
  return { deleted: true as const, files: r.files, anthropicFiles: { pending: r.pending } };
}
