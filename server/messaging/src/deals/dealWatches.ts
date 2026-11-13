// Deal watches (owner, 13 Nov 2026: "daj znać, gdy masło będzie poniżej 5 zł"; decision
// docs/decisions/2026-11-13-leaflet-results-and-deal-watches.md). A watch is the item's words, an optional price in
// grosze and optional chains. It is checked in code against the leaflet catalog after the catalog's scans, at most once
// a day, with no page read and no model: the same matcher as a search (words, categories, brands), only the item itself
// (never a similar product), only an offer the code stands behind (`check` false) and, with a price, at or below it.
//
// What is kept: the words, encrypted with MEMORY_ENCRYPTION_KEY (associated data "{account}:deal-watch:{id}"); the price,
// the chains and the push's language in plain; the account. Each offer a watch found is kept once, as a keyed hash, so
// its push is queued once (idempotency key "deal-watch:{watch}:{offer}"). The push carries a kind only ("deal-watch"),
// never the words, the shop or the price: the app reads the matches when opened. Quiet hours (Europe/Warsaw, the
// leaflets' country) hold it; a daily cap per account and one push per watch per check keep it rare. Deleted when it
// ends, on DELETE, and with the account (ON DELETE CASCADE). Logs carry ids and counts, never words.
//
// No approval digest: nothing is bought, sent or read outside on the person's behalf; the one effect is a push to the
// person's own device, which the person turns on by making the watch (like On my radar's alerts).
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { z } from "zod";
import { DEFAULT_DEAL_WATCH_SETTINGS, type DealWatchSettings } from "../config.js";
import { hmacSha256, type TextCipher } from "../crypto.js";
import { inTransaction, type Db } from "../db.js";
import { canPush, EncryptionNotConfigured, enqueue } from "../outbox.js";
import type { PushSender } from "../providers/types.js";
import { DEFAULT_TIME_ZONE, inQuietHours, QUIET_HOURS_DEFAULT, type QuietHours } from "../quietHours.js";
import { CATALOG_CHAINS, DbCatalogStore, isCatalogChain, materialFromSnapshot, type CatalogStore } from "./catalog.js";
import { warsawDay } from "./chains/common.js";
import { normalize } from "./match.js";
import { itemOffers, type DealsDeps } from "./service.js";
import type { Offer, ReadChain } from "./types.js";

export const ITEM_MAX = 60;
export const MAX_PRICE_MINOR = 10_000_000;
/** A watch is checked at most this often. */
export const CHECK_EVERY_MS = 24 * 3_600_000;
/** An offer found during quiet hours is pushed when they end, if it is found no more than this long ago. */
export const TELL_WITHIN_MS = 24 * 3_600_000;
/** Found offers are forgotten this long after their last day (or after they were found, with no last day). */
export const KEEP_HITS_DAYS = 30;
/** Matching offers listed per watch, cheapest first. */
export const MAX_OFFERS = 20;
const BATCH = 50;

export const createBody = z.strictObject({
  item: z.string().max(ITEM_MAX).refine((s) => s.trim().length > 0, "empty"),
  maxPriceMinor: z.number().int().min(1).max(MAX_PRICE_MINOR).optional(),
  chains: z.array(z.string().refine(isCatalogChain, "not_a_catalogued_chain")).min(1).max(CATALOG_CHAINS.length)
    .refine((l) => new Set(l).size === l.length, "duplicate_chain").optional(),
  language: z.enum(["pl", "en"]),
});
export type DealWatchBody = z.infer<typeof createBody>;

export interface DealWatchContext {
  db: Db;
  cipher: TextCipher;
  settings: DealWatchSettings;
  catalog: CatalogStore;
  push?: PushSender;
  quietHours: QuietHours;
  /** Routes answer and checks run: the switch is on and the catalog is on. */
  enabled: boolean;
  now: () => Date;
  log: (msg: string, extra?: object) => void;
}

/** Built whenever MEMORY_ENCRYPTION_KEY is set, so ended watches are still tidied away; on only with the switch and the catalog. */
export function dealWatchContext(db: Db, opts: {
  settings: DealWatchSettings; cipher?: TextCipher; push?: PushSender; catalog: CatalogStore; catalogOn: boolean;
  quietHours?: QuietHours; now?: () => Date; log: (msg: string, extra?: object) => void;
}): DealWatchContext | undefined {
  if (!opts.cipher) return undefined;
  return {
    db, cipher: opts.cipher, settings: opts.settings, catalog: opts.catalog, push: opts.push,
    quietHours: opts.quietHours ?? QUIET_HOURS_DEFAULT, enabled: opts.settings.enabled && opts.catalogOn,
    now: opts.now ?? (() => new Date()), log: opts.log,
  };
}

/** The context for a server's deps (web and worker build it the same way), or undefined without MEMORY_ENCRYPTION_KEY. */
export function dealWatchContextFor(deps: {
  db: Db; cipher?: TextCipher; push?: PushSender; deals?: DealsDeps; dealWatches?: { settings: DealWatchSettings; now?: () => Date };
  quietHours?: QuietHours;
}, log: (msg: string, extra?: object) => void): DealWatchContext | undefined {
  const catalogOn = !!(deps.deals?.settings.enabled && deps.deals.settings.catalog?.enabled);
  return dealWatchContext(deps.db, {
    settings: deps.dealWatches?.settings ?? { ...DEFAULT_DEAL_WATCH_SETTINGS, enabled: false }, cipher: deps.cipher, push: deps.push,
    catalog: deps.deals?.catalog ?? new DbCatalogStore(deps.db), catalogOn, quietHours: deps.quietHours, now: deps.dealWatches?.now, log,
  });
}

export const wordsAad = (accountId: string, watchId: string) => `${accountId}:deal-watch:${watchId}`;

export type Refusal =
  | { status: 400; error: "invalid_request"; fields: string[] }
  | { status: 404; error: "not_found" }
  | { status: 409; error: "too_many_watches" | "server_full" }
  | { status: 503; error: "deal_watches_disabled" };

const refuse = (r: Refusal) => ({ refusal: r });

export interface DealWatchSummary {
  id: string; item: string; maxPriceMinor?: number; chains?: ReadChain[]; language: "pl" | "en";
  createdAt: string; endsAt: string; lastCheckedAt?: string;
  /** Offers that turned up after the watch was made (not those already there when it was made). */
  found: number;
}

interface Row {
  id: string; account_id: string; key_version: number; words_ciphertext: Buffer; max_price_minor: number | null; chains: string[] | null;
  language: "pl" | "en"; created_at: Date; ends_at: Date; last_checked_at: Date | null;
}

/** The words as stored, or undefined for a key this server doesn't have or a tampered row. */
function openItem(ctx: Pick<DealWatchContext, "cipher">, r: Pick<Row, "id" | "account_id" | "key_version" | "words_ciphertext">): string | undefined {
  try {
    const parsed = z.strictObject({ item: z.string().min(1).max(ITEM_MAX) }).parse(JSON.parse(ctx.cipher.decrypt(r.words_ciphertext, wordsAad(r.account_id, r.id), r.key_version)));
    return parsed.item;
  } catch {
    return undefined;
  }
}

const watchChains = (r: Pick<Row, "chains">): ReadChain[] => (r.chains ?? []).filter(isCatalogChain);

// ---------- matching against the catalog ----------

export interface ChainState { chain: ReadChain; readAt: string; complete: boolean }

/**
 * The offers in the catalog that are the item now, cheapest first: the item itself (by its words or its brand), an offer
 * the code stands behind, and at or below the price when one is set. With each chain's scan time and completeness.
 */
export async function catalogMatches(catalog: CatalogStore, w: { item: string; maxPriceMinor?: number; chains?: readonly ReadChain[] },
  now: Date, language: string): Promise<{ offers: Offer[]; chains: ChainState[] }> {
  const wanted = w.chains?.length ? w.chains.filter(isCatalogChain) : [...CATALOG_CHAINS];
  const snapshots = await catalog.snapshots(wanted);
  const today = warsawDay(now);
  const offers: Offer[] = [];
  const chains: ChainState[] = [];
  for (const chain of wanted) {
    const s = snapshots.get(chain);
    if (!s) continue;
    const m = materialFromSnapshot(s, today, now);
    if (m === "stale") continue;
    chains.push({ chain, readAt: s.scannedAt, complete: s.complete });
    if (m === "no_leaflet") continue;
    for (const o of itemOffers(w.item, chain, m, today, language)) {
      if (o.check) continue;
      if (w.maxPriceMinor !== undefined && o.price.minor > w.maxPriceMinor) continue;
      offers.push(o);
    }
  }
  offers.sort((a, b) => a.price.minor - b.price.minor || a.chain.localeCompare(b.chain) || a.product.localeCompare(b.product));
  return { offers: offers.slice(0, MAX_OFFERS), chains };
}

/** One offer's key for one watch: an HMAC under a key derived from MEMORY_ENCRYPTION_KEY, 16 bytes. */
export function offerKey(cipher: TextCipher, watchId: string, o: Offer): Buffer {
  const identity = [watchId, o.chain, normalize(o.product), o.price.minor, o.validFrom ?? "", o.validTo ?? "", o.source.url, o.source.page ?? ""].join("|");
  return hmacSha256(cipher.derivedKey("deal-watch-offer"), identity).subarray(0, 16);
}

// ---------- the app's side ----------

export async function createDealWatch(ctx: DealWatchContext, accountId: string, body: unknown) {
  if (!ctx.enabled) return refuse({ status: 503, error: "deal_watches_disabled" });
  const parsed = createBody.safeParse(body);
  if (!parsed.success) return refuse({ status: 400, error: "invalid_request", fields: parsed.error.issues.map((i) => i.path.join(".")) });
  const b = parsed.data;
  const item = b.item.trim();
  const chains = b.chains as ReadChain[] | undefined;
  const now = ctx.now();
  const id = randomUUID();
  const endsAt = new Date(now.getTime() + ctx.settings.days * 86_400_000);
  // What already matches is shown at once and never pushed: a push is for an offer that turns up later.
  const current = await catalogMatches(ctx.catalog, { item, maxPriceMinor: b.maxPriceMinor, chains }, now, b.language);
  const r = await inTransaction(ctx.db, async (c) => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('deal-watches'))");
    const { rows: [n] } = await c.query<{ mine: number; all: number }>(
      "SELECT count(*) FILTER (WHERE account_id = $1)::int AS mine, count(*)::int AS all FROM deal_watches", [accountId]);
    if ((n?.mine ?? 0) >= ctx.settings.maxPerAccount) return refuse({ status: 409, error: "too_many_watches" });
    if ((n?.all ?? 0) >= ctx.settings.maxPerServer) return refuse({ status: 409, error: "server_full" });
    await c.query(
      `INSERT INTO deal_watches (id, account_id, key_version, words_ciphertext, max_price_minor, chains, language, created_at, ends_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [id, accountId, ctx.cipher.keyVersion, ctx.cipher.encrypt(JSON.stringify({ item }), wordsAad(accountId, id)),
        b.maxPriceMinor ?? null, chains ?? null, b.language, now, endsAt]);
    await recordHits(c, ctx, { id, account_id: accountId }, current.offers, now, "app");
    return { ok: true as const };
  });
  if ("refusal" in r) {
    ctx.log("deal watch not made", { reason: r.refusal.error });
    return r;
  }
  ctx.log("deal watch made", { watchId: id, offersNow: current.offers.length });
  return {
    watch: {
      id, item, ...(b.maxPriceMinor !== undefined ? { maxPriceMinor: b.maxPriceMinor } : {}), ...(chains ? { chains } : {}),
      language: b.language, createdAt: now.toISOString(), endsAt: endsAt.toISOString(), found: 0,
    } satisfies DealWatchSummary,
    checkedAt: now.toISOString(),
    offers: current.offers,
    chains: current.chains,
  };
}

/** Newest first, at most the account's cap. A row whose words can't be opened is left out (and logged by id). */
export async function listDealWatches(ctx: DealWatchContext, accountId: string): Promise<DealWatchSummary[]> {
  const { rows } = await ctx.db.query<Row & { found: number }>(
    `SELECT w.*, (SELECT count(*)::int FROM deal_watch_hits h WHERE h.watch_id = w.id AND h.found_at > w.created_at) AS found
     FROM deal_watches w WHERE w.account_id = $1 ORDER BY w.created_at DESC, w.id LIMIT 50`, [accountId]);
  const out: DealWatchSummary[] = [];
  for (const r of rows) {
    const item = openItem(ctx, r);
    if (!item) { ctx.log("deal watch unreadable", { watchId: r.id }); continue; }
    const chains = watchChains(r);
    out.push({
      id: r.id, item, ...(r.max_price_minor !== null ? { maxPriceMinor: r.max_price_minor } : {}), ...(chains.length ? { chains } : {}),
      language: r.language, createdAt: r.created_at.toISOString(), endsAt: r.ends_at.toISOString(),
      ...(r.last_checked_at ? { lastCheckedAt: r.last_checked_at.toISOString() } : {}), found: r.found,
    });
  }
  return out;
}

/** The watch's matches in the catalog now (code only), or undefined when it isn't the account's. */
export async function dealWatchOffers(ctx: DealWatchContext, accountId: string, id: string) {
  if (!ctx.enabled) return refuse({ status: 503, error: "deal_watches_disabled" });
  const { rows: [r] } = await ctx.db.query<Row>("SELECT * FROM deal_watches WHERE id = $1 AND account_id = $2", [id, accountId]);
  if (!r) return refuse({ status: 404, error: "not_found" });
  const item = openItem(ctx, r);
  if (!item) return refuse({ status: 404, error: "not_found" });
  const now = ctx.now();
  const m = await catalogMatches(ctx.catalog, { item, maxPriceMinor: r.max_price_minor ?? undefined, chains: watchChains(r) }, now, r.language);
  return { matches: { id, checkedAt: now.toISOString(), offers: m.offers, chains: m.chains } };
}

/** The row and what it found are gone when this returns. */
export async function deleteDealWatch(ctx: DealWatchContext, accountId: string, id: string) {
  if (!ctx.enabled) return refuse({ status: 503, error: "deal_watches_disabled" });
  const { rowCount } = await ctx.db.query("DELETE FROM deal_watches WHERE id = $1 AND account_id = $2", [id, accountId]);
  if (!rowCount) return refuse({ status: 404, error: "not_found" });
  ctx.log("deal watch deleted", { watchId: id });
  return { ok: true as const };
}

// ---------- the check after the catalog's scans ----------

/** Records each offer once for the watch; returns the keys that are new. `told`: "app" marks them told already. */
async function recordHits(c: pg.PoolClient, ctx: Pick<DealWatchContext, "cipher">, w: Pick<Row, "id" | "account_id">, offers: Offer[], now: Date,
  told?: "app"): Promise<Buffer[]> {
  const fresh: Buffer[] = [];
  for (const o of offers) {
    const key = offerKey(ctx.cipher, w.id, o);
    const r = await c.query(
      `INSERT INTO deal_watch_hits (watch_id, account_id, offer_key, found_at, valid_to, told_at, told_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (watch_id, offer_key) DO NOTHING`,
      [w.id, w.account_id, key, now, o.validTo ?? null, told ? now : null, told ?? null]);
    if (r.rowCount) fresh.push(key);
  }
  return fresh;
}

/**
 * After a pass of the catalog's scans: each watch on a chain just scanned (or on every chain) that wasn't checked in the
 * last day is checked against the catalog, in code. New matching offers are recorded once; telling about them is
 * `tellDealWatches`'s. Due watches are claimed (last_checked_at moved first, SKIP LOCKED) so two workers never check one
 * watch twice. Returns counts only.
 */
export async function checkDealWatches(ctx: DealWatchContext, scanned: readonly ReadChain[]): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  if (!ctx.enabled || scanned.length === 0) return counts;
  const add = (k: string, n = 1) => { if (n) counts[k] = (counts[k] ?? 0) + n; };
  const now = ctx.now();
  for (;;) {
    const claimed = await inTransaction(ctx.db, async (c) => {
      const { rows } = await c.query<Row>(
        `SELECT * FROM deal_watches
         WHERE ends_at > $1 AND (last_checked_at IS NULL OR last_checked_at <= $2) AND (chains IS NULL OR chains && $3::text[])
         ORDER BY last_checked_at NULLS FIRST, id LIMIT ${BATCH} FOR UPDATE SKIP LOCKED`,
        [now, new Date(now.getTime() - CHECK_EVERY_MS), scanned]);
      if (rows.length) await c.query("UPDATE deal_watches SET last_checked_at = $2 WHERE id = ANY($1::uuid[])", [rows.map((r) => r.id), now]);
      return rows;
    });
    if (claimed.length === 0) break;
    for (const w of claimed) {
      try {
        const item = openItem(ctx, w);
        if (!item) { add("unreadable"); ctx.log("deal watch unreadable", { watchId: w.id }); continue; }
        const m = await catalogMatches(ctx.catalog, { item, maxPriceMinor: w.max_price_minor ?? undefined, chains: watchChains(w) }, now, w.language);
        const fresh = await inTransaction(ctx.db, (c) => recordHits(c, ctx, w, m.offers, now));
        add("checked");
        add("new_offers", fresh.length);
      } catch (err) {
        add("failed");
        ctx.log("deal watch check failed", { watchId: w.id, error: err instanceof Error ? err.name : "unknown" });
      }
    }
    if (claimed.length < BATCH) break;
  }
  add("told", (await tellDealWatches(ctx)).pushed ?? 0);
  return counts;
}

/** Deal-watch pushes queued for the account in the last 24 hours. */
async function pushesLastDay(c: pg.PoolClient, accountId: string, now: Date): Promise<number> {
  const { rows } = await c.query<{ n: string }>(
    `SELECT count(*) AS n FROM outbound_messages WHERE account_id = $1 AND channel = 'push' AND idempotency_key LIKE 'deal-watch:%'
     AND created_at > $2`, [accountId, new Date(now.getTime() - 86_400_000)]);
  return Number(rows[0]!.n);
}

/** The push text: a kind of news, never the item, the shop or the price. */
export function pushText(language: "pl" | "en"): string {
  return language === "pl" ? "Coś, czego pilnujesz w gazetkach, jest w promocji." : "Something you're watching is on offer in a leaflet.";
}

/**
 * Tells about new offers: per watch, one push for its earliest untold offer (outside quiet hours, under the account's
 * daily cap, when the account has a device), the rest shown in the app. An offer found more than a day ago is shown in
 * the app only. Runs after each check and in the catalog's loop, so an offer held by quiet hours is told when they end.
 */
export async function tellDealWatches(ctx: DealWatchContext): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  if (!ctx.enabled) return counts;
  const add = (k: string, n = 1) => { if (n) counts[k] = (counts[k] ?? 0) + n; };
  const now = ctx.now();
  const stale = await ctx.db.query(
    "UPDATE deal_watch_hits SET told_at = $1, told_by = 'app' WHERE told_at IS NULL AND found_at < $2", [now, new Date(now.getTime() - TELL_WITHIN_MS)]);
  add("stale", stale.rowCount ?? 0);
  if (inQuietHours(now, DEFAULT_TIME_ZONE, ctx.quietHours)) {
    const { rows: [held] } = await ctx.db.query<{ n: number }>("SELECT count(*)::int AS n FROM deal_watch_hits WHERE told_at IS NULL");
    add("held_quiet_hours", held?.n ?? 0);
    return counts;
  }
  const { rows: watches } = await ctx.db.query<{ watch_id: string }>(
    "SELECT DISTINCT watch_id FROM deal_watch_hits WHERE told_at IS NULL LIMIT 500");
  for (const { watch_id } of watches) {
    try {
      add(await inTransaction(ctx.db, async (c) => {
        const { rows: [w] } = await c.query<{ account_id: string; language: "pl" | "en" }>(
          "SELECT account_id, language FROM deal_watches WHERE id = $1 FOR UPDATE", [watch_id]);
        if (!w) return "gone";
        const { rows: hits } = await c.query<{ offer_key: Buffer }>(
          "SELECT offer_key FROM deal_watch_hits WHERE watch_id = $1 AND told_at IS NULL ORDER BY found_at, offer_key FOR UPDATE", [watch_id]);
        if (hits.length === 0) return "nothing";
        const [first, ...rest] = hits;
        const outcome = await queuePush(c, ctx, w.account_id, w.language, `deal-watch:${watch_id}:${first!.offer_key.toString("hex")}`, now);
        await c.query("UPDATE deal_watch_hits SET told_at = $3, told_by = $4 WHERE watch_id = $1 AND offer_key = $2",
          [watch_id, first!.offer_key, now, outcome === "push" ? "push" : "app"]);
        if (rest.length) {
          await c.query("UPDATE deal_watch_hits SET told_at = $3, told_by = 'app' WHERE watch_id = $1 AND offer_key = ANY($2::bytea[])",
            [watch_id, rest.map((h) => h.offer_key), now]);
        }
        return outcome === "push" ? "pushed" : outcome === "cap" ? "over_cap" : "app_only";
      }));
    } catch (err) {
      add("failed");
      ctx.log("deal watch tell failed", { watchId: watch_id, error: err instanceof Error ? err.name : "unknown" });
    }
  }
  return counts;
}

async function queuePush(c: pg.PoolClient, ctx: DealWatchContext, accountId: string, language: "pl" | "en", key: string, now: Date):
  Promise<"push" | "no_push" | "cap"> {
  if (!ctx.push || !(await canPush(c, accountId))) return "no_push";
  if (await pushesLastDay(c, accountId, now) >= ctx.settings.pushesPerDay) return "cap";
  try {
    await enqueue(c, accountId, ["push"], pushText(language), now, key, { cipher: ctx.cipher });
    return "push";
  } catch (err) {
    if (err instanceof EncryptionNotConfigured) return "no_push";
    throw err;
  }
}

/** Deletes ended watches (with what they found) and found offers a month past their last day. Counts only. */
export async function tidyDealWatches(ctx: DealWatchContext): Promise<Record<string, number>> {
  const now = ctx.now();
  const ended = await ctx.db.query("DELETE FROM deal_watches WHERE ends_at <= $1", [now]);
  const cutoff = new Date(now.getTime() - KEEP_HITS_DAYS * 86_400_000);
  const old = await ctx.db.query(
    `DELETE FROM deal_watch_hits WHERE told_at IS NOT NULL AND (valid_to IS NOT NULL AND valid_to < $1::date OR valid_to IS NULL AND found_at < $2)`,
    [warsawDay(cutoff), cutoff]);
  const out: Record<string, number> = {};
  if (ended.rowCount) out.ended = ended.rowCount;
  if (old.rowCount) out.prunedHits = old.rowCount;
  return out;
}
