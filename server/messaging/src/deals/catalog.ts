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
// Every price in the catalog came from a chain's own data or the reader's read of a page, parsed by the code, exactly
// as in a live read (service.ts); the offers are built from it by the same code (`chainOffers`).
import { createHash } from "node:crypto";
import type { Db } from "../db.js";
import { mapLimit } from "./chains/common.js";
import { CachingFetcher, type PageFetcher } from "./fetcher.js";
import type { ChainMaterial } from "./service.js";
import { prepareImage, readCatalogPage, type ReadProduct, type ReadPromotion } from "./vision.js";
import { pageKey, type ChainAdapter, type DealsModelApi, type LeafletRead, type ModelUsage, type PagesRead, type ReadChain } from "./types.js";

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

export interface CatalogPageRead { products: ReadProduct[]; promotions: ReadPromotion[] }

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
}

/** Where searches read the catalog from. */
export interface CatalogStore {
  snapshots(chains: readonly ReadChain[]): Promise<Map<ReadChain, ChainSnapshot>>;
}

export type StoredPageRead = { kind: "ok"; read: CatalogPageRead } | { kind: "failed"; attempts: number };

/** Where a scan keeps the reads of single pages, so the next scan doesn't pay for them again. */
export interface PageReadStore {
  get(chain: ReadChain, keys: readonly string[]): Promise<Map<string, StoredPageRead>>;
  putOk(chain: ReadChain, key: string, read: CatalogPageRead): Promise<void>;
  putFailed(chain: ReadChain, key: string): Promise<void>;
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
  kept.forEach(({ l, li }, newIndex) => {
    for (const page of l.pages) {
      const r = s.reads[pageKey(li, page.number)];
      if (!r) continue;
      reads.set(pageKey(newIndex, page.number), r.products);
      promos.set(pageKey(newIndex, page.number), r.promotions);
    }
  });
  return {
    leaflets: kept.map(({ l }) => l), reads, promos, complete: s.complete, reasons: new Set(s.reasons),
    ...(s.pages ? { pages: s.pages } : {}), endedBefore: today,
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
}

export interface ScanStats { pagesWanted: number; pagesKnown: number; pagesRead: number; pagesFailed: number; usage: ModelUsage }

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

/** Reads one chain for the catalog: the adapter with no items, then the pages not read before. Never throws. */
export async function scanChain(chain: ReadChain, adapter: ChainAdapter, deps: ScanDeps): Promise<ScanOutcome> {
  // A scan reads page after page for minutes: the search's short-lived cache would only be filled and flushed.
  const fetcher = deps.fetcher instanceof CachingFetcher ? deps.fetcher.inner : deps.fetcher;
  let read;
  try {
    read = await adapter.read({ fetcher, queries: [], today: deps.today, signal: deps.signal });
  } catch {
    return { kind: "failed", reason: "adapter_error" };
  }
  const scannedAt = deps.now().toISOString();
  const stats: ScanStats = { pagesWanted: 0, pagesKnown: 0, pagesRead: 0, pagesFailed: 0, usage: { inputTokens: 0, outputTokens: 0 } };
  if (read.kind === "no_leaflet" || (read.kind === "ok" && read.leaflets.length === 0)) {
    return { kind: "ok", snapshot: { chain, scannedAt, noLeaflet: true, leaflets: [], reads: {}, complete: true, reasons: [] }, stats };
  }
  if (read.kind !== "ok") return { kind: "failed", reason: read.kind === "blocked" ? "blocked" : read.reason.slice(0, 60) };

  const reasons = new Set<string>(read.incomplete ? [read.incomplete] : []);
  const jobs = read.leaflets.flatMap((l, li) => catalogPages(l).map((number) => {
    const page = l.pages.find((p) => p.number === number)!;
    return { li, page, key: catalogPageKey(l, page.imageUrl) };
  }));
  stats.pagesWanted = jobs.length;
  let known = new Map<string, StoredPageRead>();
  try {
    known = await deps.pageReads.get(chain, jobs.map((j) => j.key));
  } catch {
    reasons.add("page_store_error");
  }
  const reads: Record<string, CatalogPageRead> = {};
  const toRead: typeof jobs = [];
  let gaveUp = 0;
  for (const j of jobs) {
    const k = known.get(j.key);
    if (k?.kind === "ok") { reads[pageKey(j.li, j.page.number)] = k.read; stats.pagesKnown++; }
    else if (k?.kind === "failed" && k.attempts >= MAX_PAGE_ATTEMPTS) gaveUp++;
    else toRead.push(j);
  }
  if (gaveUp) reasons.add("pages_unreadable");
  if (toRead.length && !deps.model?.readCatalogPage) reasons.add("no_reader");
  const now = deps.model?.readCatalogPage ? toRead.slice(0, deps.maxPages) : [];
  if (toRead.length > now.length && deps.model?.readCatalogPage) reasons.add("pages_over_cap");

  await mapLimit(now, deps.concurrency, async (j) => {
    if (deps.signal.aborted) { reasons.add("time"); return; }
    const f = await fetcher.fetchPage(j.page.imageUrl, { accept: ACCEPT_IMAGES, aiInput: true, signal: deps.signal });
    if (f.kind !== "ok") {
      reasons.add(`image_${f.kind}`);
      // A page the image host refuses for AI input is never sent to the reader; it isn't the reader's failure either.
      if (f.kind !== "blocked") await deps.pageReads.putFailed(chain, j.key).catch(() => {});
      return;
    }
    const image = prepareImage(f.body);
    if ("error" in image) { reasons.add(`image_${image.error}`); await deps.pageReads.putFailed(chain, j.key).catch(() => {}); return; }
    try {
      const r = await readCatalogPage(deps.model!, image, { chain, signal: deps.signal });
      if (r.usage) { stats.usage.inputTokens += r.usage.inputTokens; stats.usage.outputTokens += r.usage.outputTokens; }
      if (r.kind === "ok") {
        const kept: CatalogPageRead = { products: r.products, promotions: r.promotions };
        reads[pageKey(j.li, j.page.number)] = kept;
        stats.pagesRead++;
        await deps.pageReads.putOk(chain, j.key, kept).catch(() => reasons.add("page_store_error"));
      } else {
        stats.pagesFailed++;
        reasons.add(`read_${r.kind}`);
        await deps.pageReads.putFailed(chain, j.key).catch(() => {});
      }
    } catch {
      stats.pagesFailed++;
      reasons.add(deps.signal.aborted ? "time" : "read_error");
    }
  });

  const got = jobs.filter((j) => reads[pageKey(j.li, j.page.number)]).length;
  // Dino's pages only confirm offers its data already gave (they say `check` until then), so like a live search they
  // don't count as pages that hide offers.
  const hiding = jobs.filter((j) => read.leaflets[j.li]!.strategy !== "confirm");
  const hidingGot = hiding.filter((j) => reads[pageKey(j.li, j.page.number)]).length;
  return {
    kind: "ok",
    snapshot: {
      chain, scannedAt, leaflets: read.leaflets, reads, complete: got === jobs.length && !read.incomplete, reasons: [...reasons].sort(),
      ...(hidingGot < hiding.length ? { pages: { read: hidingGot, of: hiding.length } } : {}),
    },
    stats,
  };
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

export class DbPageReadStore implements PageReadStore {
  constructor(private readonly db: Db) {}

  async get(chain: ReadChain, keys: readonly string[]): Promise<Map<string, StoredPageRead>> {
    const out = new Map<string, StoredPageRead>();
    if (!keys.length) return out;
    const { rows } = await this.db.query<{ page_key: string; read: CatalogPageRead | null; attempts: number }>(
      "SELECT page_key, read, attempts FROM leaflet_page_reads WHERE chain = $1 AND page_key = ANY($2)", [chain, keys]);
    for (const r of rows) out.set(r.page_key, r.read ? { kind: "ok", read: r.read } : { kind: "failed", attempts: r.attempts });
    return out;
  }

  async putOk(chain: ReadChain, key: string, read: CatalogPageRead): Promise<void> {
    await this.db.query(
      `INSERT INTO leaflet_page_reads (chain, page_key, read, attempts, read_at) VALUES ($1, $2, $3, 1, now())
       ON CONFLICT (chain, page_key) DO UPDATE SET read = EXCLUDED.read, read_at = now()`, [chain, key, JSON.stringify(read)]);
  }

  async putFailed(chain: ReadChain, key: string): Promise<void> {
    await this.db.query(
      `INSERT INTO leaflet_page_reads (chain, page_key, read, attempts, read_at) VALUES ($1, $2, NULL, 1, now())
       ON CONFLICT (chain, page_key) DO UPDATE SET attempts = LEAST(leaflet_page_reads.attempts + 1, 10), read_at = now()
       WHERE leaflet_page_reads.read IS NULL`, [chain, key]);
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
  /** One chain's scan stops after this long; what it read is kept for the next. Default 15 minutes. */
  chainTimeLimitMs?: number;
  now: () => Date;
  today: () => string;
  log: (msg: string, extra?: object) => void;
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
  try {
    const { rows: [lock] } = await client.query<{ ok: boolean }>("SELECT pg_try_advisory_lock($1) AS ok", [SCAN_LOCK]);
    if (!lock?.ok) return counts;
    try {
      const { rows } = await ctx.db.query<{ chain: string; attempted_at: Date }>("SELECT chain, attempted_at FROM leaflet_catalog");
      const last = new Map(rows.map((r) => [r.chain, r.attempted_at.getTime()]));
      const due = CATALOG_CHAINS.filter((c) => {
        const at = last.get(c);
        return at === undefined || ctx.now().getTime() - at >= ctx.everyHours * 3600_000;
      });
      const pageReads = new DbPageReadStore(ctx.db);
      for (const chain of due) {
        if (shouldStop()) break;
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), ctx.chainTimeLimitMs ?? 15 * 60_000);
        const stopWatch = setInterval(() => { if (shouldStop()) controller.abort(); }, 1000);
        const started = Date.now();
        let outcome: ScanOutcome;
        try {
          outcome = await scanChain(chain, ctx.adapters[chain], {
            fetcher: ctx.fetcher, model: ctx.model, pageReads, today: ctx.today(), now: ctx.now, maxPages: ctx.maxPagesPerChain,
            concurrency: 4, signal: controller.signal, log: ctx.log,
          });
        } finally {
          clearTimeout(timer);
          clearInterval(stopWatch);
        }
        if (outcome.kind === "ok") {
          const s = outcome.snapshot;
          await ctx.db.query(
            `INSERT INTO leaflet_catalog (chain, snapshot, scanned_at, attempted_at, last_result) VALUES ($1, $2, $3, now(), $4)
             ON CONFLICT (chain) DO UPDATE SET snapshot = EXCLUDED.snapshot, scanned_at = EXCLUDED.scanned_at,
               attempted_at = EXCLUDED.attempted_at, last_result = EXCLUDED.last_result`,
            [chain, JSON.stringify(s), s.scannedAt, s.complete ? "complete" : "partial"]);
          counts[s.complete ? "complete" : "partial"] = (counts[s.complete ? "complete" : "partial"] ?? 0) + 1;
          ctx.log("leaflet catalog scanned", {
            chain, complete: s.complete, reasons: s.reasons.join(",") || undefined, leaflets: s.leaflets.length, ...outcome.stats.usage,
            pagesWanted: outcome.stats.pagesWanted, pagesKnown: outcome.stats.pagesKnown, pagesRead: outcome.stats.pagesRead,
            pagesFailed: outcome.stats.pagesFailed, ms: Date.now() - started,
          });
        } else {
          await ctx.db.query(
            `INSERT INTO leaflet_catalog (chain, attempted_at, last_result) VALUES ($1, now(), $2)
             ON CONFLICT (chain) DO UPDATE SET attempted_at = now(), last_result = EXCLUDED.last_result`, [chain, `failed:${outcome.reason}`.slice(0, 80)]);
          counts.failed = (counts.failed ?? 0) + 1;
          ctx.log("leaflet catalog scan failed", { chain, reason: outcome.reason, ms: Date.now() - started });
        }
      }
      const pruned = await ctx.db.query("DELETE FROM leaflet_page_reads WHERE read_at < now() - make_interval(days => $1)", [PAGE_READS_KEPT_DAYS]);
      if (pruned.rowCount) counts.prunedPages = pruned.rowCount;
    } finally {
      await client.query("SELECT pg_advisory_unlock($1)", [SCAN_LOCK]).catch(() => {});
    }
  } finally {
    client.release();
  }
  return counts;
}
