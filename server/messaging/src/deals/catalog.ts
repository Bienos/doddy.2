// The leaflet catalog (owner, 12 Nov 2026; decision docs/decisions/2026-11-12-leaflet-catalog.md): Doddy reads each
// chain's current leaflets once, in the background, for everyone, and keeps what it read; a search then matches the
// person's items against what was kept, in code, in well under a second. Before this, every search read up to 16
// chains' leaflets again within 25 s, and 6 to 9 of 10 chains timed out on every search (log of 10 and 11 Nov 2026).
//
// What is kept is the shops' own published leaflets and the reader's read of their pages: nothing about any person,
// no item anyone asked for. A page is read once (its key is the leaflet's address and dates and the page image's
// address), so a scan every few hours reads only pages it hasn't read yet. A chain whose adapter reads by the item
// itself (Rossmann's search, CCC's and Deichmann's categories, Maxi Zoo's and zooplus's animal pages) isn't
// catalogued: a search still reads it live, as before.
//
// Every page, eventually (owner, 13 Nov 2026; decision 2026-11-13-leaflet-results-and-deal-watches): a scan sends the
// reader the pages never tried first, those of leaflets already running before those that start later, and stops at
// `maxPages` or at the day's token budget (per chain and in all); the rest are read by the next scans. A page image
// that comes over the size cap is asked for once more a moment later (Biedronka's image host sends a cold page as a
// 6 MB PNG and the same page as a 0.2 MB WebP once it has made one) and then, if the chain publishes one, in its
// smaller rendition. The snapshot records which pages are missing and why, so a search says the leaflet was read in
// part.
//
// Every price in the catalog came from a chain's own data or the reader's read of a page, parsed by the code, exactly
// as in a live read (service.ts); the offers are built from it by the same code (`chainOffers`).
import { createHash } from "node:crypto";
import type { Db } from "../db.js";
import { mapLimit } from "./chains/common.js";
import { CachingFetcher, type FetchResult, type PageFetcher } from "./fetcher.js";
import type { ChainMaterial } from "./service.js";
import { prepareImage, readCatalogPage, type ReadProduct, type ReadPromotion } from "./vision.js";
import {
  pageKey, type ChainAdapter, type DealsModelApi, type LeafletPage, type LeafletRead, type ModelUsage, type PageImage, type PagesRead, type ReadChain,
} from "./types.js";

/** The chains a scan reads. The rest are read live by each search, because their adapters need the item. */
export const CATALOG_CHAINS: readonly ReadChain[] = [
  "biedronka", "lidl", "dino", "aldi", "zabka", "delikatesy", "leclerc", "komfort", "lewiatan", "natura", "action",
];
export const isCatalogChain = (c: string): c is ReadChain => (CATALOG_CHAINS as readonly string[]).includes(c);

/** A snapshot older than this is not used: the search reads that chain live instead. */
export const DEFAULT_MAX_AGE_HOURS = 8 * 24;
/** A page whose read failed this many times is left unread until its leaflet changes. */
export const MAX_PAGE_ATTEMPTS = 2;
/** Page reads not used for this long are deleted (a leaflet runs a week, sometimes two). */
export const PAGE_READS_KEPT_DAYS = 30;
/** Input plus output tokens the scans may spend in one day (Warsaw), per chain and in all, unless set
 * (DEALS_CATALOG_DAILY_TOKENS_PER_CHAIN, DEALS_CATALOG_DAILY_TOKENS). The first scans of 12 Nov 2026 spent about 5,000
 * a page (Lidl: 800,000 for 160 pages), so a chain's whole leaflet set fits in a day and the eleven chains together
 * about 4 million. */
export const DEFAULT_DAILY_TOKENS_PER_CHAIN = 1_500_000;
export const DEFAULT_DAILY_TOKENS = 6_000_000;
/** What a page is reckoned to cost before this scan has read one. */
export const PAGE_TOKEN_ESTIMATE = 6_000;
/** How long to wait before asking once more for a page image that came over the size cap. */
export const IMAGE_RETRY_WAIT_MS = 2_000;
/** Missing pages kept in a snapshot, at most (a leaflet set rarely passes 300 pages). */
const MAX_MISSING = 400;

/** What the reader read on one page; `readAt` (ISO) since 13 Nov 2026, absent in older snapshots. */
export interface CatalogPageRead { products: ReadProduct[]; promotions: ReadPromotion[]; readAt?: string }

/**
 * Why a page worth reading isn't in the snapshot: not read yet (the page cap, the day's budget, the time limit, no
 * reader: a later scan reads it), its image too large even after the retry and the smaller rendition, its image not
 * fetched, its image host refusing AI input, or the reader not reading it. `gaveUp`: tried MAX_PAGE_ATTEMPTS times, left
 * until its leaflet changes.
 */
export type MissingWhy = "not_read_yet" | "image_too_large" | "image_failed" | "image_refused" | "read_failed";
export interface MissingPage { leaflet: number; page: number; why: MissingWhy; gaveUp?: true }

/** One chain as the last successful scan found it. */
export interface ChainSnapshot {
  chain: ReadChain;
  scannedAt: string;
  /** The chain published no current leaflet. */
  noLeaflet?: boolean;
  leaflets: LeafletRead[];
  /** What the reader read, per "leaflet index:page number". */
  reads: Record<string, CatalogPageRead>;
  /** Every page worth reading was read, and the adapter read everything it should. */
  complete: boolean;
  reasons: string[];
  /** Fewer pages read than were worth reading. */
  pages?: PagesRead;
  /** The pages worth reading that aren't in `reads`, and why (13 Nov 2026). */
  missing?: MissingPage[];
}

/** Where searches read the catalog from. */
export interface CatalogStore {
  snapshots(chains: readonly ReadChain[]): Promise<Map<ReadChain, ChainSnapshot>>;
}

export type StoredPageRead =
  | { kind: "ok"; read: CatalogPageRead; readAt?: string }
  | { kind: "failed"; attempts: number; failure?: MissingWhy };

/** Where a scan keeps the reads of single pages, so the next scan doesn't pay for them again. */
export interface PageReadStore {
  get(chain: ReadChain, keys: readonly string[]): Promise<Map<string, StoredPageRead>>;
  putOk(chain: ReadChain, key: string, read: CatalogPageRead): Promise<void>;
  putFailed(chain: ReadChain, key: string, failure?: MissingWhy): Promise<void>;
}

/** The day's token budget a scan may spend: what is left for this chain and in all, and where each page's cost goes. */
export interface TokenBudget {
  chainLeft: number;
  allLeft: number;
  spend(tokens: number): Promise<void>;
}

// ---------- using a snapshot in a search ----------

/** A leaflet still running on `today`: its last day isn't past (or isn't known). */
const running = (l: LeafletRead, today: string) => !l.leaflet.validTo || l.leaflet.validTo >= today;

/**
 * What a search builds its offers from, or why it can't: "stale" (too old, or every leaflet in it has ended: the
 * search reads the chain live), "no_leaflet" (the chain published none at the last scan).
 */
export function materialFromSnapshot(s: ChainSnapshot, today: string, now: Date, maxAgeHours = DEFAULT_MAX_AGE_HOURS):
  ChainMaterial | "stale" | "no_leaflet" {
  const scanned = Date.parse(s.scannedAt);
  if (!Number.isFinite(scanned) || now.getTime() - scanned > maxAgeHours * 3600_000) return "stale";
  if (s.noLeaflet) return "no_leaflet";
  const kept = s.leaflets.map((l, li) => ({ l, li })).filter(({ l }) => running(l, today));
  if (kept.length === 0) return "stale";
  const reads = new Map<string, ReadProduct[]>();
  const promos = new Map<string, ReadPromotion[]>();
  const pageReadAt = new Map<string, string>();
  kept.forEach(({ l, li }, newIndex) => {
    for (const page of l.pages) {
      const r = s.reads[pageKey(li, page.number)];
      if (!r) continue;
      reads.set(pageKey(newIndex, page.number), r.products);
      promos.set(pageKey(newIndex, page.number), r.promotions);
      if (r.readAt) pageReadAt.set(pageKey(newIndex, page.number), r.readAt);
    }
  });
  return {
    leaflets: kept.map(({ l }) => l), reads, promos, complete: s.complete, reasons: new Set(s.reasons),
    ...(s.pages ? { pages: s.pages } : {}), endedBefore: today, readAt: s.scannedAt, pageReadAt, fromCatalog: true,
  };
}

// ---------- scanning one chain ----------

export interface ScanDeps {
  fetcher: PageFetcher;
  model?: DealsModelApi;
  pageReads: PageReadStore;
  /** Today in Warsaw, YYYY-MM-DD. */
  today: string;
  now: () => Date;
  /** Pages sent to the reader in one scan of one chain; the rest wait for the next scan. */
  maxPages: number;
  /** Pages read at once. */
  concurrency: number;
  signal: AbortSignal;
  log: (msg: string, extra?: object) => void;
  /** The day's token budget. Absent: no budget (tests, and a scan run by hand). */
  tokens?: TokenBudget;
  /** For tests: the wait before an image is asked for again. Default: a real timer. */
  sleep?: (ms: number) => Promise<void>;
}

export interface ScanStats {
  pagesWanted: number; pagesKnown: number; pagesRead: number; pagesFailed: number; usage: ModelUsage;
  /** Pages not read in this scan because the day's token budget was spent. */
  pagesOverBudget: number;
}

export type ScanOutcome =
  | { kind: "ok"; snapshot: ChainSnapshot; stats: ScanStats }
  /** Nothing usable was read (blocked, failed): the last good snapshot stays. */
  | { kind: "failed"; reason: string };

/** The key a page's read is kept under: its leaflet's address and dates, and the page image's address. */
export function catalogPageKey(l: LeafletRead, imageUrl: string): string {
  return createHash("sha256").update(`${l.leaflet.url}|${l.leaflet.validFrom ?? ""}|${l.leaflet.validTo ?? ""}|${imageUrl}`).digest("hex").slice(0, 32);
}

/** The pages of a leaflet worth reading for the catalog: all of an image leaflet, all of one whose pages carry text
 * (the catalog has no items to choose pages by), and the pages that hold data products to be confirmed. */
export function catalogPages(l: LeafletRead): number[] {
  if (l.strategy === "all" || l.strategy === "text") return l.pages.map((p) => p.number);
  if (l.strategy === "confirm") {
    const wanted = new Set(l.products.filter((p) => p.confirmOnPage && p.page).map((p) => p.page!));
    return l.pages.filter((p) => wanted.has(p.number)).map((p) => p.number);
  }
  return [];
}

const ACCEPT_IMAGES = "image/avif;q=0,image/webp,image/png,image/jpeg,image/*;q=0.8";

type ImageOutcome = { image: PageImage } | { fail: Exclude<MissingWhy, "not_read_yet" | "read_failed">; reason: string };

const isTooLarge = (f: FetchResult) => f.kind === "failed" && f.reason === "too_large";

/**
 * One page image for the reader: fetched (robots.txt and its content signals checked by the fetcher), asked for once
 * more after a short wait when it came over the size cap, then in the chain's smaller rendition when there is one and
 * the image was still too large to fetch or to send. Never resized or changed by Doddy.
 */
export async function fetchPageImage(fetcher: PageFetcher, page: LeafletPage, signal: AbortSignal,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms))): Promise<ImageOutcome> {
  const get = (url: string) => fetcher.fetchPage(url, { accept: ACCEPT_IMAGES, aiInput: true, signal });
  let f = await get(page.imageUrl);
  if (isTooLarge(f) && !signal.aborted) {
    await sleep(IMAGE_RETRY_WAIT_MS);
    f = await get(page.imageUrl);
  }
  let prepared = f.kind === "ok" ? prepareImage(f.body) : undefined;
  const tooLarge = isTooLarge(f) || (prepared !== undefined && "error" in prepared && prepared.error === "too_large");
  if (tooLarge && page.smallerImageUrl && !signal.aborted) {
    f = await get(page.smallerImageUrl);
    prepared = f.kind === "ok" ? prepareImage(f.body) : undefined;
  }
  if (f.kind === "blocked" || f.kind === "disallowed") return { fail: "image_refused", reason: `image_${f.kind}` };
  if (f.kind !== "ok") return isTooLarge(f) ? { fail: "image_too_large", reason: "image_too_large" } : { fail: "image_failed", reason: `image_${f.kind}` };
  if (!prepared || "error" in prepared) {
    const error = prepared && "error" in prepared ? prepared.error : "not_an_image";
    return error === "too_large" ? { fail: "image_too_large", reason: "image_too_large" } : { fail: "image_failed", reason: `image_${error}` };
  }
  return { image: prepared };
}

interface Job { li: number; page: LeafletPage; key: string; tried: boolean }

/**
 * The order pages go to the reader (13 Nov 2026): pages never tried before pages that failed once, pages of leaflets
 * already running before those that start later, then the leaflet's order and the page's. The cap takes the front.
 */
export function readingOrder<T extends Pick<Job, "li" | "page" | "tried">>(jobs: readonly T[], leaflets: readonly LeafletRead[], today: string): T[] {
  const later = (li: number) => { const from = leaflets[li]?.leaflet.validFrom; return from && from > today ? 1 : 0; };
  return [...jobs].sort((a, b) => Number(a.tried) - Number(b.tried) || later(a.li) - later(b.li) || a.li - b.li || a.page.number - b.page.number);
}

/** Reads one chain for the catalog: the adapter with no items, then the pages not read before. Never throws. */
export async function scanChain(chain: ReadChain, adapter: ChainAdapter, deps: ScanDeps): Promise<ScanOutcome> {
  // A scan reads page after page for minutes: the search's short-lived cache would only be filled and flushed.
  const fetcher = deps.fetcher instanceof CachingFetcher ? deps.fetcher.inner : deps.fetcher;
  let read;
  try {
    read = await adapter.read({ fetcher, queries: [], today: deps.today, signal: deps.signal, forCatalog: true });
  } catch {
    return { kind: "failed", reason: "adapter_error" };
  }
  const scannedAt = deps.now().toISOString();
  const stats: ScanStats = { pagesWanted: 0, pagesKnown: 0, pagesRead: 0, pagesFailed: 0, pagesOverBudget: 0, usage: { inputTokens: 0, outputTokens: 0 } };
  if (read.kind === "no_leaflet" || (read.kind === "ok" && read.leaflets.length === 0)) {
    return { kind: "ok", snapshot: { chain, scannedAt, noLeaflet: true, leaflets: [], reads: {}, complete: true, reasons: [] }, stats };
  }
  if (read.kind !== "ok") return { kind: "failed", reason: read.kind === "blocked" ? "blocked" : read.reason.slice(0, 60) };

  const reasons = new Set<string>(read.incomplete ? [read.incomplete] : []);
  const jobs: Job[] = read.leaflets.flatMap((l, li) => catalogPages(l).map((number) => {
    const page = l.pages.find((p) => p.number === number)!;
    return { li, page, key: catalogPageKey(l, page.imageUrl), tried: false };
  }));
  stats.pagesWanted = jobs.length;
  let known = new Map<string, StoredPageRead>();
  try {
    known = await deps.pageReads.get(chain, jobs.map((j) => j.key));
  } catch {
    reasons.add("page_store_error");
  }
  const reads: Record<string, CatalogPageRead> = {};
  const missing = new Map<string, MissingPage>();
  const miss = (j: Job, why: MissingWhy, gaveUp = false) =>
    missing.set(pageKey(j.li, j.page.number), { leaflet: j.li, page: j.page.number, why, ...(gaveUp ? { gaveUp: true as const } : {}) });
  const toRead: Job[] = [];
  for (const j of jobs) {
    const k = known.get(j.key);
    if (k?.kind === "ok") { reads[pageKey(j.li, j.page.number)] = { ...k.read, ...(k.readAt ? { readAt: k.readAt } : {}) }; stats.pagesKnown++; }
    else if (k?.kind === "failed" && k.attempts >= MAX_PAGE_ATTEMPTS) { reasons.add("pages_unreadable"); miss(j, k.failure ?? "read_failed", true); }
    else toRead.push({ ...j, tried: k?.kind === "failed" });
  }
  const reader = deps.model?.readCatalogPage ? deps.model : undefined;
  if (toRead.length && !reader) reasons.add("no_reader");
  const ordered = readingOrder(toRead, read.leaflets, deps.today);
  const now = reader ? ordered.slice(0, deps.maxPages) : [];
  if (ordered.length > now.length && reader) reasons.add("pages_over_cap");
  for (const j of ordered.slice(now.length)) miss(j, "not_read_yet");

  // The day's budget: a page isn't started when what was spent, plus what the pages in flight are reckoned to cost,
  // would pass what is left for this chain or in all.
  const limit = deps.tokens ? Math.max(0, Math.min(deps.tokens.chainLeft, deps.tokens.allLeft)) : Infinity;
  let spent = 0;
  let inFlight = 0;
  const estimate = () => (stats.pagesRead + stats.pagesFailed > 0 ? Math.ceil(spent / (stats.pagesRead + stats.pagesFailed)) : PAGE_TOKEN_ESTIMATE);
  const fits = () => spent + (inFlight + 1) * estimate() <= limit;
  // A page that doesn't fit while others are in flight waits for them: their real cost may leave room for it.
  const waiting: (() => void)[] = [];
  const settled = () => { for (const w of waiting.splice(0)) w(); };

  await mapLimit(now, deps.concurrency, async (j) => {
    while (!fits() && inFlight > 0 && !deps.signal.aborted) await new Promise<void>((r) => waiting.push(r));
    if (deps.signal.aborted) { reasons.add("time"); miss(j, "not_read_yet"); return; }
    if (!fits()) { reasons.add("token_budget"); stats.pagesOverBudget++; miss(j, "not_read_yet"); return; }
    inFlight++;
    try {
      const img = await fetchPageImage(fetcher, j.page, deps.signal, deps.sleep);
      if ("fail" in img) {
        reasons.add(img.reason);
        miss(j, img.fail, img.fail !== "image_refused" && j.tried);
        // A page the image host refuses for AI input is never sent to the reader; it isn't the reader's failure either.
        if (img.fail !== "image_refused") await deps.pageReads.putFailed(chain, j.key, img.fail).catch(() => {});
        return;
      }
      try {
        const r = await readCatalogPage(reader!, img.image, { chain, signal: deps.signal });
        const cost = r.usage ? r.usage.inputTokens + r.usage.outputTokens : 0;
        if (r.usage) { stats.usage.inputTokens += r.usage.inputTokens; stats.usage.outputTokens += r.usage.outputTokens; }
        spent += cost;
        if (cost && deps.tokens) await deps.tokens.spend(cost).catch(() => reasons.add("budget_store_error"));
        if (r.kind === "ok") {
          const kept: CatalogPageRead = { products: r.products, promotions: r.promotions, readAt: deps.now().toISOString() };
          reads[pageKey(j.li, j.page.number)] = kept;
          stats.pagesRead++;
          await deps.pageReads.putOk(chain, j.key, kept).catch(() => reasons.add("page_store_error"));
        } else {
          stats.pagesFailed++;
          reasons.add(`read_${r.kind}`);
          miss(j, "read_failed", j.tried);
          await deps.pageReads.putFailed(chain, j.key, "read_failed").catch(() => {});
        }
      } catch {
        stats.pagesFailed++;
        reasons.add(deps.signal.aborted ? "time" : "read_error");
        miss(j, deps.signal.aborted ? "not_read_yet" : "read_failed");
      }
    } finally {
      inFlight--;
      settled();
    }
  });

  const got = jobs.filter((j) => reads[pageKey(j.li, j.page.number)]).length;
  // Dino's pages only confirm offers its data already gave (they say `check` until then), so like a live search they
  // don't count as pages that hide offers.
  const hiding = jobs.filter((j) => read.leaflets[j.li]!.strategy !== "confirm");
  const hidingGot = hiding.filter((j) => reads[pageKey(j.li, j.page.number)]).length;
  const missingList = [...missing.values()].filter((m) => !reads[pageKey(m.leaflet, m.page)])
    .sort((a, b) => a.leaflet - b.leaflet || a.page - b.page).slice(0, MAX_MISSING);
  return {
    kind: "ok",
    snapshot: {
      chain, scannedAt, leaflets: read.leaflets, reads, complete: got === jobs.length && !read.incomplete, reasons: [...reasons].sort(),
      ...(hidingGot < hiding.length ? { pages: { read: hidingGot, of: hiding.length } } : {}),
      ...(missingList.length ? { missing: missingList } : {}),
    },
    stats,
  };
}

/** "image_too_large:1,not_read_yet:12": the missing pages of a snapshot by why, for the log (codes and counts only). */
export function missingSummary(missing: readonly MissingPage[] | undefined): string | undefined {
  if (!missing?.length) return undefined;
  const counts = new Map<string, number>();
  for (const m of missing) { const k = m.gaveUp ? `${m.why}_gave_up` : m.why; counts.set(k, (counts.get(k) ?? 0) + 1); }
  return [...counts].sort((a, b) => a[0].localeCompare(b[0])).map(([k, n]) => `${k}:${n}`).join(",");
}

// ---------- the database ----------

/** Snapshots from Postgres, held in memory and fetched again only when a scan changed them. */
export class DbCatalogStore implements CatalogStore {
  private readonly held = new Map<ReadChain, { scannedAt: string; snapshot: ChainSnapshot }>();

  constructor(private readonly db: Db) {}

  async snapshots(chains: readonly ReadChain[]): Promise<Map<ReadChain, ChainSnapshot>> {
    const wanted = chains.filter(isCatalogChain);
    const out = new Map<ReadChain, ChainSnapshot>();
    if (!wanted.length) return out;
    const { rows } = await this.db.query<{ chain: ReadChain; scanned_at: Date }>(
      "SELECT chain, scanned_at FROM leaflet_catalog WHERE chain = ANY($1) AND scanned_at IS NOT NULL", [wanted]);
    const stale = rows.filter((r) => this.held.get(r.chain)?.scannedAt !== r.scanned_at.toISOString()).map((r) => r.chain);
    if (stale.length) {
      const full = await this.db.query<{ chain: ReadChain; scanned_at: Date; snapshot: ChainSnapshot }>(
        "SELECT chain, scanned_at, snapshot FROM leaflet_catalog WHERE chain = ANY($1) AND scanned_at IS NOT NULL", [stale]);
      for (const r of full.rows) this.held.set(r.chain, { scannedAt: r.scanned_at.toISOString(), snapshot: r.snapshot });
    }
    for (const r of rows) {
      const h = this.held.get(r.chain);
      if (h) out.set(r.chain, h.snapshot);
    }
    return out;
  }
}

const FAILURES: readonly MissingWhy[] = ["image_too_large", "image_failed", "image_refused", "read_failed"];

export class DbPageReadStore implements PageReadStore {
  constructor(private readonly db: Db) {}

  async get(chain: ReadChain, keys: readonly string[]): Promise<Map<string, StoredPageRead>> {
    const out = new Map<string, StoredPageRead>();
    if (!keys.length) return out;
    const { rows } = await this.db.query<{ page_key: string; read: CatalogPageRead | null; attempts: number; read_at: Date; failure: string | null }>(
      "SELECT page_key, read, attempts, read_at, failure FROM leaflet_page_reads WHERE chain = $1 AND page_key = ANY($2)", [chain, keys]);
    for (const r of rows) {
      const failure = FAILURES.find((f) => f === r.failure);
      out.set(r.page_key, r.read ? { kind: "ok", read: r.read, readAt: r.read_at.toISOString() }
        : { kind: "failed", attempts: r.attempts, ...(failure ? { failure } : {}) });
    }
    return out;
  }

  /** The read's own time (`readAt`, the scan's clock) is the row's `read_at`; without one, the database's now. */
  async putOk(chain: ReadChain, key: string, read: CatalogPageRead): Promise<void> {
    const { readAt, ...kept } = read;
    await this.db.query(
      `INSERT INTO leaflet_page_reads (chain, page_key, read, attempts, read_at) VALUES ($1, $2, $3, 1, COALESCE($4::timestamptz, now()))
       ON CONFLICT (chain, page_key) DO UPDATE SET read = EXCLUDED.read, read_at = EXCLUDED.read_at, failure = NULL`,
      [chain, key, JSON.stringify(kept), readAt ?? null]);
  }

  async putFailed(chain: ReadChain, key: string, failure?: MissingWhy): Promise<void> {
    await this.db.query(
      `INSERT INTO leaflet_page_reads (chain, page_key, read, attempts, read_at, failure) VALUES ($1, $2, NULL, 1, now(), $3)
       ON CONFLICT (chain, page_key) DO UPDATE SET attempts = LEAST(leaflet_page_reads.attempts + 1, 10), read_at = now(),
         failure = EXCLUDED.failure
       WHERE leaflet_page_reads.read IS NULL`, [chain, key, failure ?? null]);
  }
}

/** Tokens the catalog's scans spent per chain and Warsaw day (migration 038), for the daily budget. */
export class DbTokenLedger {
  constructor(private readonly db: Db) {}

  /** Spent today by this chain, and by every chain together. */
  async spent(chain: ReadChain, day: string): Promise<{ chain: number; all: number }> {
    const { rows } = await this.db.query<{ chain_tokens: string | null; all_tokens: string | null }>(
      `SELECT sum(tokens) FILTER (WHERE chain = $1) AS chain_tokens, sum(tokens) AS all_tokens
       FROM leaflet_catalog_tokens WHERE day = $2::date`, [chain, day]);
    return { chain: Number(rows[0]?.chain_tokens ?? 0), all: Number(rows[0]?.all_tokens ?? 0) };
  }

  async add(chain: ReadChain, day: string, tokens: number): Promise<void> {
    if (!(tokens > 0)) return;
    await this.db.query(
      `INSERT INTO leaflet_catalog_tokens (chain, day, tokens) VALUES ($1, $2::date, $3)
       ON CONFLICT (chain, day) DO UPDATE SET tokens = leaflet_catalog_tokens.tokens + EXCLUDED.tokens`, [chain, day, Math.round(tokens)]);
  }

  /** Days older than a week are of no use to the budget. */
  async prune(day: string): Promise<number> {
    const r = await this.db.query("DELETE FROM leaflet_catalog_tokens WHERE day < $1::date - 7", [day]);
    return r.rowCount ?? 0;
  }
}

// ---------- the background pass ----------

export interface CatalogContext {
  db: Db;
  adapters: Record<ReadChain, ChainAdapter>;
  fetcher: PageFetcher;
  model?: DealsModelApi;
  /** How often each chain is scanned. A scan reads only pages it hasn't read, so most cost nothing. */
  everyHours: number;
  maxPagesPerChain: number;
  /** Input plus output tokens per Warsaw day, per chain and in all. Absent: the defaults above. */
  dailyTokensPerChain?: number;
  dailyTokens?: number;
  /** One chain's scan stops after this long; what it read is kept for the next. Default 15 minutes. */
  chainTimeLimitMs?: number;
  now: () => Date;
  today: () => string;
  log: (msg: string, extra?: object) => void;
  /** Runs after a pass that scanned at least one chain, with the chains whose new snapshot was kept (deal watches). */
  afterScans?: (chains: ReadChain[]) => Promise<Record<string, number>>;
  /** For tests: the wait before an image is asked for again. */
  sleep?: (ms: number) => Promise<void>;
}

/** Only one process scans at a time (the web process and a worker may both run the loop). */
const SCAN_LOCK = 4242027;

/**
 * Scans each catalogued chain whose last attempt is older than `everyHours`, one after another, and keeps its snapshot;
 * a failed scan keeps the last good one. Deletes page reads unused for a month. Logs codes and counts only.
 */
export async function runCatalogPass(ctx: CatalogContext, shouldStop: () => boolean = () => false): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  const client = await ctx.db.connect();
  const scanned: ReadChain[] = [];
  try {
    const { rows: [lock] } = await client.query<{ ok: boolean }>("SELECT pg_try_advisory_lock($1) AS ok", [SCAN_LOCK]);
    if (!lock?.ok) return counts;
    try {
      // attempted_at is written with ctx.now() below, so "due" compares one clock with itself.
      const { rows } = await ctx.db.query<{ chain: string; attempted_at: Date }>("SELECT chain, attempted_at FROM leaflet_catalog");
      const last = new Map(rows.map((r) => [r.chain, r.attempted_at.getTime()]));
      const due = CATALOG_CHAINS.filter((c) => {
        const at = last.get(c);
        return at === undefined || ctx.now().getTime() - at >= ctx.everyHours * 3600_000;
      });
      const pageReads = new DbPageReadStore(ctx.db);
      const ledger = new DbTokenLedger(ctx.db);
      const perChain = ctx.dailyTokensPerChain ?? DEFAULT_DAILY_TOKENS_PER_CHAIN;
      const overall = ctx.dailyTokens ?? DEFAULT_DAILY_TOKENS;
      for (const chain of due) {
        if (shouldStop()) break;
        const day = ctx.today();
        let tokens: TokenBudget | undefined;
        try {
          const spent = await ledger.spent(chain, day);
          tokens = { chainLeft: perChain - spent.chain, allLeft: overall - spent.all, spend: (n) => ledger.add(chain, day, n) };
        } catch {
          // Without the ledger the day's spend can't be known: nothing new is read in this scan.
          tokens = { chainLeft: 0, allLeft: 0, spend: async () => {} };
        }
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), ctx.chainTimeLimitMs ?? 15 * 60_000);
        const stopWatch = setInterval(() => { if (shouldStop()) controller.abort(); }, 1000);
        const started = Date.now();
        let outcome: ScanOutcome;
        try {
          outcome = await scanChain(chain, ctx.adapters[chain], {
            fetcher: ctx.fetcher, model: ctx.model, pageReads, today: day, now: ctx.now, maxPages: ctx.maxPagesPerChain,
            concurrency: 4, signal: controller.signal, log: ctx.log, tokens, ...(ctx.sleep ? { sleep: ctx.sleep } : {}),
          });
        } finally {
          clearTimeout(timer);
          clearInterval(stopWatch);
        }
        if (outcome.kind === "ok") {
          const s = outcome.snapshot;
          await ctx.db.query(
            `INSERT INTO leaflet_catalog (chain, snapshot, scanned_at, attempted_at, last_result) VALUES ($1, $2, $3, $5, $4)
             ON CONFLICT (chain) DO UPDATE SET snapshot = EXCLUDED.snapshot, scanned_at = EXCLUDED.scanned_at,
               attempted_at = EXCLUDED.attempted_at, last_result = EXCLUDED.last_result`,
            [chain, JSON.stringify(s), s.scannedAt, s.complete ? "complete" : "partial", ctx.now()]);
          scanned.push(chain);
          counts[s.complete ? "complete" : "partial"] = (counts[s.complete ? "complete" : "partial"] ?? 0) + 1;
          const used = outcome.stats.usage.inputTokens + outcome.stats.usage.outputTokens;
          ctx.log("leaflet catalog scanned", {
            chain, complete: s.complete, reasons: s.reasons.join(",") || undefined, leaflets: s.leaflets.length, ...outcome.stats.usage,
            pagesWanted: outcome.stats.pagesWanted, pagesKnown: outcome.stats.pagesKnown, pagesRead: outcome.stats.pagesRead,
            pagesFailed: outcome.stats.pagesFailed, pagesOverBudget: outcome.stats.pagesOverBudget || undefined,
            missing: missingSummary(s.missing),
            tokensLeftChain: Math.max(0, tokens.chainLeft - used), tokensLeftAll: Math.max(0, tokens.allLeft - used),
            ms: Date.now() - started,
          });
        } else {
          await ctx.db.query(
            `INSERT INTO leaflet_catalog (chain, attempted_at, last_result) VALUES ($1, $3, $2)
             ON CONFLICT (chain) DO UPDATE SET attempted_at = EXCLUDED.attempted_at, last_result = EXCLUDED.last_result`,
            [chain, `failed:${outcome.reason}`.slice(0, 80), ctx.now()]);
          counts.failed = (counts.failed ?? 0) + 1;
          ctx.log("leaflet catalog scan failed", { chain, reason: outcome.reason, ms: Date.now() - started });
        }
      }
      // On the scan's clock, which wrote read_at.
      const pruned = await ctx.db.query("DELETE FROM leaflet_page_reads WHERE read_at < $1",
        [new Date(ctx.now().getTime() - PAGE_READS_KEPT_DAYS * 86_400_000)]);
      if (pruned.rowCount) counts.prunedPages = pruned.rowCount;
      await ledger.prune(ctx.today()).catch(() => 0);
    } finally {
      await client.query("SELECT pg_advisory_unlock($1)", [SCAN_LOCK]).catch(() => {});
    }
  } finally {
    client.release();
  }
  // Deal watches are checked against what was just kept, with no page read (decision 2026-11-13-leaflet-results-and-deal-watches).
  if (scanned.length && ctx.afterScans) {
    try {
      for (const [k, n] of Object.entries(await ctx.afterScans(scanned))) if (n) counts[`watch_${k}`] = n;
    } catch (err) {
      ctx.log("deal watch checks failed", { error: err instanceof Error ? err.name : "unknown" });
    }
  }
  return counts;
}
