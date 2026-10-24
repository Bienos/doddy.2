// Price watches, the app's side (docs/implementation/SHOPPING_WATCH.md section 3): create a draft after
// reading the page once, approve it by its digest, read, stop and delete. The rules:
//   - a draft exists only for a price Doddy could read just now, in the user's currency, above the
//     user's number; it stores the title, shop and page address encrypted, exactly as sent;
//   - only a draft can be approved, only with its own digest, only within 10 minutes, and only while
//     the account has fewer than WATCHES_MAX_OPEN active watches (counted under an advisory lock, so
//     two approvals can't both take the last place);
//   - nothing is read, created or approved while watches are off or not set up (503 watches_disabled).
// No model is involved. Logs carry ids and counts, never words or addresses.
import { randomUUID } from "node:crypto";
import { sameBytes } from "../crypto.js";
import { inTransaction } from "../db.js";
import { checkOfferPage, type PageCheck } from "../shopping/pagecheck.js";
import { contentAad, type WatchContext } from "./context.js";
import {
  blobJson, blobSchema, CHECKS_PER_DAY, contentDigest, createBody, DAYS, type WatchBlob, type WatchContent, type WatchState,
} from "./schema.js";

export const DRAFT_MINUTES = 10;
export const LIST_LIMIT = 50;
const DAY_MS = 86_400_000;

export type Refusal =
  | { status: 400; error: "invalid_request"; fields: string[] }
  | { status: 404; error: "not_found" }
  | { status: 409; error: "not_approvable" | "not_stoppable"; state: string }
  | { status: 409; error: "digest_mismatch" | "too_many_open_watches" }
  | { status: 422; error: "price_not_readable"; reason: "blocked" | "not_allowed" | "no_price" | "failed" }
  | { status: 422; error: "currency_mismatch" }
  | { status: 422; error: "already_below"; currentMinor: number }
  | { status: 503; error: "watches_disabled" };

const refuse = (r: Refusal) => ({ refusal: r });

export interface WatchRow {
  id: string; account_id: string; state: WatchState; language: string;
  content_ciphertext: Buffer; payload_digest: Buffer;
  threshold_minor: string; currency: string;
  last_price_minor: string | null; triggered_price_minor: string | null;
  checks_done: number; consecutive_failures: number;
  next_check_at: Date | null; last_checked_at: Date | null; ends_at: Date | null; triggered_at: Date | null;
  finished_at: Date | null; failure: string | null;
  created_at: Date; expires_at: Date; approved_at: Date | null;
}

/**
 * The content as approved: the words from the encrypted blob and the numbers from their columns, only if
 * they hash to the digest the user approved. undefined for a key this server doesn't have or a tampered row.
 */
export function openContent(ctx: Pick<WatchContext, "cipher">, r: Pick<WatchRow, "id" | "account_id" | "content_ciphertext" | "payload_digest" | "threshold_minor" | "currency">):
  WatchContent | undefined {
  let blob: WatchBlob;
  try {
    blob = blobSchema.parse(JSON.parse(ctx.cipher.decrypt(r.content_ciphertext, contentAad(r.account_id, r.id))));
  } catch {
    return undefined;
  }
  const content: WatchContent = { ...blob, thresholdMinor: Number(r.threshold_minor), currency: r.currency };
  return sameBytes(contentDigest(content), r.payload_digest) ? content : undefined;
}

// ---------- create ----------

/** What reading the page just now means for a new watch: a refusal, or the price to show on the card. */
function readFor(check: PageCheck, c: WatchContent): Refusal | { currentMinor: number } {
  switch (check.kind) {
    case "ok": {
      const price = check.offer.price;
      if (price.currency !== c.currency) return { status: 422, error: "currency_mismatch" };
      if (price.minor <= c.thresholdMinor) return { status: 422, error: "already_below", currentMinor: price.minor };
      return { currentMinor: price.minor };
    }
    case "blocked": return { status: 422, error: "price_not_readable", reason: "blocked" };
    case "disallowed": return { status: 422, error: "price_not_readable", reason: "not_allowed" };
    // A page that isn't HTML publishes no price either.
    case "no_price":
    case "not_html": return { status: 422, error: "price_not_readable", reason: "no_price" };
    case "failed": return { status: 422, error: "price_not_readable", reason: "failed" };
  }
}

/**
 * Reads the page once (the shared polite fetcher: robots.txt, DoddyBot, no bypass), and only if a price
 * can be read from its published product data makes a draft the user can approve by its digest.
 */
export async function createWatch(ctx: WatchContext, accountId: string, body: unknown, signal?: AbortSignal) {
  if (!ctx.enabled || !ctx.fetcher) return refuse({ status: 503, error: "watches_disabled" });
  const parsed = createBody.safeParse(body);
  if (!parsed.success) return refuse({ status: 400, error: "invalid_request", fields: parsed.error.issues.map((i) => i.path.join(".")) });
  const content = parsed.data;
  let check: PageCheck;
  try {
    check = await checkOfferPage(content.url, ctx.fetcher, signal);
  } catch {
    check = { kind: "failed", reason: "error" };
  }
  const read = readFor(check, content);
  if ("status" in read) {
    ctx.log("watch not drafted", { reason: read.error });
    return refuse(read);
  }
  // The draft's ten minutes start when the card is shown, after the read.
  const now = ctx.now();
  const id = randomUUID();
  const digest = contentDigest(content);
  const expiresAt = new Date(now.getTime() + DRAFT_MINUTES * 60_000);
  const blob: WatchBlob = { language: content.language, shop: content.shop, title: content.title, url: content.url };
  await ctx.db.query(
    `INSERT INTO price_watches (id, account_id, state, content_key_version, content_ciphertext, payload_digest,
       threshold_minor, currency, language, created_at, expires_at)
     VALUES ($1, $2, 'draft', $3, $4, $5, $6, $7, $8, $9, $10)`,
    [id, accountId, ctx.cipher.keyVersion, ctx.cipher.encrypt(blobJson(blob), contentAad(accountId, id)), digest,
      content.thresholdMinor, content.currency, content.language, now, expiresAt]);
  ctx.log("watch drafted", { watchId: id });
  return {
    draft: {
      id, digest: digest.toString("hex"), title: content.title, shop: content.shop, url: content.url,
      thresholdMinor: content.thresholdMinor, currency: content.currency, language: content.language,
      currentMinor: read.currentMinor, checkedAt: now.toISOString(), expiresAt: expiresAt.toISOString(),
      days: DAYS, checksPerDay: CHECKS_PER_DAY,
    },
  };
}

// ---------- approve ----------

/** When the first check is due: one interval after the approval (the page was read minutes ago), shifted a little. */
export const firstCheckAt = (ctx: WatchContext, now: Date): Date => {
  const interval = ctx.settings.checkHours * 3_600_000;
  return new Date(now.getTime() + interval + ctx.jitterMs(interval));
};

export async function approveWatch(ctx: WatchContext, accountId: string, id: string, digestHex: string) {
  if (!ctx.enabled) return refuse({ status: 503, error: "watches_disabled" });
  const now = ctx.now();
  const given = Buffer.from(digestHex, "hex");
  const r = await inTransaction(ctx.db, async (c) => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('watches:' || $1))", [accountId]);
    const { rows } = await c.query<{ state: string; payload_digest: Buffer; expires_at: Date }>(
      "SELECT state, payload_digest, expires_at FROM price_watches WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const w = rows[0];
    if (!w) return refuse({ status: 404, error: "not_found" });
    if (w.state !== "draft" || w.expires_at <= now) return refuse({ status: 409, error: "not_approvable", state: w.state === "draft" ? "expired" : w.state });
    if (!sameBytes(w.payload_digest, given)) return refuse({ status: 409, error: "digest_mismatch" });
    const { rows: open } = await c.query<{ n: number }>(
      "SELECT count(*)::int AS n FROM price_watches WHERE account_id = $1 AND state = 'active'", [accountId]);
    if ((open[0]?.n ?? 0) >= ctx.settings.maxOpen) return refuse({ status: 409, error: "too_many_open_watches" });
    const endsAt = new Date(now.getTime() + DAYS * DAY_MS);
    await c.query(
      "UPDATE price_watches SET state = 'active', approved_at = $2, ends_at = $3, next_check_at = $4 WHERE id = $1",
      [id, now, endsAt, firstCheckAt(ctx, now)]);
    return { approved: { id, state: "active" as const, endsAt: endsAt.toISOString() } };
  });
  if ("approved" in r) ctx.log("watch approved", { watchId: id });
  return r;
}

// ---------- reads ----------

const iso = (d: Date) => d.toISOString();

export interface WatchSummary {
  id: string; state: WatchState; title: string; shop: string; url: string; thresholdMinor: number; currency: string;
  language: string; createdAt: string; expiresAt?: string; endsAt?: string; lastCheckedAt?: string; lastPriceMinor?: number;
  checksDone: number; triggeredAt?: string; triggeredPriceMinor?: number; failure?: string;
}

/** The app's view of a row, or undefined when the content can't be opened. Optional fields are left out, never null. */
export function summaryOf(ctx: WatchContext, r: WatchRow): WatchSummary | undefined {
  const c = openContent(ctx, r);
  if (!c) return undefined;
  return {
    id: r.id, state: r.state, title: c.title, shop: c.shop, url: c.url, thresholdMinor: c.thresholdMinor, currency: c.currency,
    language: c.language, createdAt: iso(r.created_at),
    ...(r.state === "draft" ? { expiresAt: iso(r.expires_at) } : {}),
    ...(r.ends_at ? { endsAt: iso(r.ends_at) } : {}),
    ...(r.last_checked_at ? { lastCheckedAt: iso(r.last_checked_at) } : {}),
    ...(r.last_price_minor !== null ? { lastPriceMinor: Number(r.last_price_minor) } : {}),
    checksDone: r.checks_done,
    ...(r.triggered_at ? { triggeredAt: iso(r.triggered_at) } : {}),
    ...(r.triggered_price_minor !== null ? { triggeredPriceMinor: Number(r.triggered_price_minor) } : {}),
    ...(r.failure ? { failure: r.failure } : {}),
  };
}

export async function getWatch(ctx: WatchContext, accountId: string, id: string): Promise<WatchSummary | undefined> {
  const { rows } = await ctx.db.query<WatchRow>("SELECT * FROM price_watches WHERE id = $1 AND account_id = $2", [id, accountId]);
  return rows[0] ? summaryOf(ctx, rows[0]) : undefined;
}

/** Newest first, drafts left out, at most 50. A row whose content can't be opened (a key this server lacks) is left out too. */
export async function listWatches(ctx: WatchContext, accountId: string): Promise<WatchSummary[]> {
  const { rows } = await ctx.db.query<WatchRow>(
    `SELECT * FROM price_watches WHERE account_id = $1 AND state <> 'draft' ORDER BY created_at DESC, id LIMIT ${LIST_LIMIT}`, [accountId]);
  const out: WatchSummary[] = [];
  for (const r of rows) {
    const s = summaryOf(ctx, r);
    if (s) out.push(s);
    else ctx.log("watch content unreadable", { watchId: r.id });
  }
  return out;
}

// ---------- stop and delete ----------

/** Only an active watch can be stopped. A check already in flight finds the watch stopped and writes nothing. */
export async function stopWatch(ctx: WatchContext, accountId: string, id: string) {
  if (!ctx.enabled) return refuse({ status: 503, error: "watches_disabled" });
  const now = ctx.now();
  const r = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string }>("SELECT state FROM price_watches WHERE id = $1 AND account_id = $2 FOR UPDATE", [id, accountId]);
    const w = rows[0];
    if (!w) return refuse({ status: 404, error: "not_found" });
    if (w.state !== "active") return refuse({ status: 409, error: "not_stoppable", state: w.state });
    await c.query("UPDATE price_watches SET state = 'stopped', next_check_at = NULL, finished_at = $2 WHERE id = $1", [id, now]);
    return { ok: true as const };
  });
  if ("ok" in r) ctx.log("watch stopped", { watchId: id });
  return r;
}

/** In any state: the row, content and all, is gone when this returns. */
export async function deleteWatch(ctx: WatchContext, accountId: string, id: string) {
  if (!ctx.enabled) return refuse({ status: 503, error: "watches_disabled" });
  const { rowCount } = await ctx.db.query("DELETE FROM price_watches WHERE id = $1 AND account_id = $2", [id, accountId]);
  if (!rowCount) return refuse({ status: 404, error: "not_found" });
  ctx.log("watch deleted", { watchId: id });
  return { ok: true as const };
}
