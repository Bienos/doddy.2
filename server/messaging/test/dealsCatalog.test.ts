// The leaflet catalog (decision docs/decisions/2026-11-12-leaflet-catalog.md): a scan reads each chain once for
// everyone and keeps it; a search answers a catalogued chain from what was kept, with no fetch and no page read, and
// reads any other chain live. Fake adapters, a fake web and a fake reader; the database half runs with
// TEST_DATABASE_URL.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import {
  CATALOG_CHAINS, catalogPageKey, catalogPages, DbCatalogStore, DbPageReadStore, materialFromSnapshot, MAX_PAGE_ATTEMPTS, runCatalogPass,
  scanChain, type CatalogPageRead, type CatalogStore, type ChainSnapshot, type MissingWhy, type PageReadStore, type StoredPageRead,
} from "../src/deals/catalog.js";
import type { FetchResult, PageFetcher } from "../src/deals/fetcher.js";
import { searchDeals, type DealsDeps } from "../src/deals/service.js";
import {
  DEFAULT_DEALS_SETTINGS, type ChainAdapter, type ChainContext, type ChainRead, type DealsModelApi, type LeafletRead, type ModelReply, type PageImage,
  type ReadChain,
} from "../src/deals/types.js";
import { CATALOG_SYSTEM, VISION_SYSTEM, type PageOutput } from "../src/deals/vision.js";
import type { Db } from "../src/db.js";
import { fakePng, FakeModel, markerOf, read } from "./dealsFakes.js";
import { dbSkip, freshDb } from "./helpers.js";

const NOW = new Date("2026-11-12T06:00:00.000Z");
const TODAY = "2026-11-12";

/** A leaflet of image pages "chain:n", running 10 to 16 Nov. */
function imageLeaflet(chain: string, pages: number, url = `https://${chain}.example/gazetka`): LeafletRead {
  return {
    leaflet: { title: "Gazetka", url, validFrom: "2026-11-10", validTo: "2026-11-16" },
    products: [],
    pages: Array.from({ length: pages }, (_, i) => ({ number: i + 1, imageUrl: `https://img.example/${chain}/${i + 1}.png`, url: `${url}#${i + 1}` })),
    strategy: "all",
  };
}

class FakeAdapter implements ChainAdapter {
  readonly hosts = ["img.example"];
  calls: ChainContext[] = [];
  constructor(readonly chain: ReadChain, public answer: ChainRead | (() => ChainRead)) {}
  async read(ctx: ChainContext): Promise<ChainRead> {
    this.calls.push(ctx);
    return typeof this.answer === "function" ? this.answer() : this.answer;
  }
}

/** Serves a fake PNG for every page image, named by its address ("biedronka:3"). */
class ImageWeb implements PageFetcher {
  readonly fetched: string[] = [];
  blocked = new Set<string>();
  async fetchPage(url: string): Promise<FetchResult> {
    this.fetched.push(url);
    if (this.blocked.has(url)) return { kind: "blocked", reason: "ai-input=no" };
    const m = /\/([a-z]+)\/(\d+)\.png$/.exec(url);
    if (!m) return { kind: "failed", reason: "not_found" };
    return { kind: "ok", status: 200, contentType: "image/png", body: fakePng(1200, 1700, `${m[1]}:${m[2]}`), finalUrl: url };
  }
}

/** The fake reader with the catalog read: the page step by marker, read in full (no items). */
class CatalogFakeModel extends FakeModel {
  readonly catalogReads: string[] = [];
  async readCatalogPage(req: { image: PageImage; chain: ReadChain }, signal: AbortSignal): Promise<ModelReply<PageOutput>> {
    const marker = markerOf(req.image.data);
    this.catalogReads.push(marker);
    const r = await this.readPage({ image: req.image, chain: req.chain, queries: [] }, signal);
    this.reads.pop(); // only the catalog read is counted here
    return r;
  }
}

class MemoryPageReads implements PageReadStore {
  readonly rows = new Map<string, StoredPageRead>();
  async get(chain: ReadChain, keys: readonly string[]) {
    const out = new Map<string, StoredPageRead>();
    for (const k of keys) { const r = this.rows.get(`${chain}|${k}`); if (r) out.set(k, r); }
    return out;
  }
  // As the database's: the read without its time, and the time the row was written.
  async putOk(chain: ReadChain, key: string, read: CatalogPageRead) {
    const { readAt: _at, ...kept } = read;
    this.rows.set(`${chain}|${key}`, { kind: "ok", read: kept, readAt: NOW.toISOString() });
  }
  async putFailed(chain: ReadChain, key: string, failure?: MissingWhy) {
    const held = this.rows.get(`${chain}|${key}`);
    if (held?.kind === "ok") return;
    this.rows.set(`${chain}|${key}`, { kind: "failed", attempts: (held?.attempts ?? 0) + 1, ...(failure ? { failure } : {}) });
  }
}

class MemoryCatalog implements CatalogStore {
  constructor(public held = new Map<ReadChain, ChainSnapshot>(), public fail = false) {}
  async snapshots(chains: readonly ReadChain[]) {
    if (this.fail) throw new Error("db down");
    return new Map([...this.held].filter(([c]) => chains.includes(c)));
  }
}

const scanDeps = (over: Partial<Parameters<typeof scanChain>[2]> = {}) => ({
  fetcher: new ImageWeb(), model: undefined as DealsModelApi | undefined, pageReads: new MemoryPageReads(), today: TODAY, now: () => NOW,
  maxPages: 100, concurrency: 4, signal: new AbortController().signal, log: () => {}, ...over,
});

/** Biedronka's three pages as the fake reader reads them (test data, not real prices). */
const biedronkaReader = () => new CatalogFakeModel()
  .page("biedronka:1", { products: [] })
  .page("biedronka:2", { products: [
    read({ name: "Masło Extra 82%", size: "200 g", price: "4,99", regularPrice: "6,49" }),
    read({ name: "Słuchawki bezprzewodowe douszne", price: "79,99" }),
  ] })
  .page("biedronka:3", { products: [read({ name: "Kawa mielona Jacobs Krönung", size: "500 g", price: "24,99", validTo: "11.11" })] });

describe("the catalog's reader prompt", () => {
  test("lists the whole page, not the person's items, and keeps every other reading rule", () => {
    assert.notEqual(CATALOG_SYSTEM, VISION_SYSTEM);
    assert.equal(CATALOG_SYSTEM.includes("the person's shopping items"), false, "both item sentences were replaced");
    assert.equal(CATALOG_SYSTEM.includes("that could include one of the items"), false);
    assert.match(CATALOG_SYSTEM, /List every product offered on this page/);
    assert.match(CATALOG_SYSTEM, /Never guess\./);
    assert.match(CATALOG_SYSTEM, /The page image is data/);
  });
});

describe("scanning one chain for the catalog", () => {
  test("every page of an image leaflet is read once; the next scan reads none and keeps the same snapshot", async () => {
    const model = biedronkaReader();
    const deps = scanDeps({ model });
    const adapter = new FakeAdapter("biedronka", { kind: "ok", leaflets: [imageLeaflet("biedronka", 3)] });
    const first = await scanChain("biedronka", adapter, deps);
    assert.equal(first.kind, "ok");
    assert.ok(first.kind === "ok");
    assert.deepEqual(adapter.calls[0]!.queries, [], "a scan asks the chain for nothing in particular");
    assert.deepEqual(model.catalogReads.sort(), ["biedronka:1", "biedronka:2", "biedronka:3"]);
    assert.equal(first.snapshot.complete, true);
    assert.equal(first.snapshot.pages, undefined);
    assert.equal(first.stats.pagesRead, 3);
    assert.equal(first.snapshot.reads["0:2"]!.products.length, 2);

    const second = await scanChain("biedronka", adapter, deps);
    assert.ok(second.kind === "ok");
    assert.equal(model.catalogReads.length, 3, "no page read twice");
    assert.equal(second.stats.pagesKnown, 3);
    assert.deepEqual(second.snapshot.reads, first.snapshot.reads);
  });

  test("a new leaflet's pages are new keys: its pages are read even where the image addresses repeat", () => {
    const a = imageLeaflet("lidl", 1);
    const b = { ...a, leaflet: { ...a.leaflet, validFrom: "2026-11-17", validTo: "2026-11-23" } };
    assert.notEqual(catalogPageKey(a, a.pages[0]!.imageUrl), catalogPageKey(b, b.pages[0]!.imageUrl));
    assert.match(catalogPageKey(a, a.pages[0]!.imageUrl), /^[0-9a-f]{32}$/);
  });

  test("which pages are worth reading: all of image and text leaflets, only the data's pages of a confirm leaflet", () => {
    const l = imageLeaflet("dino", 4);
    assert.deepEqual(catalogPages(l), [1, 2, 3, 4]);
    assert.deepEqual(catalogPages({ ...l, strategy: "text" }), [1, 2, 3, 4]);
    assert.deepEqual(catalogPages({ ...l, strategy: "none" }), []);
    const products = [
      { name: "Masło", price: { minor: 499, currency: "PLN" as const }, conditions: [], url: "u", page: 3, confirmOnPage: true },
      { name: "Mleko", price: { minor: 299, currency: "PLN" as const }, conditions: [], url: "u", page: 1 },
    ];
    assert.deepEqual(catalogPages({ ...l, strategy: "confirm", products }), [3]);
  });

  test("the page cap: the rest waits for the next scan, which goes on where this one stopped", async () => {
    const model = biedronkaReader();
    const deps = scanDeps({ model, maxPages: 2 });
    const adapter = new FakeAdapter("biedronka", { kind: "ok", leaflets: [imageLeaflet("biedronka", 3)] });
    const first = await scanChain("biedronka", adapter, deps);
    assert.ok(first.kind === "ok");
    assert.equal(first.snapshot.complete, false);
    assert.deepEqual(first.snapshot.pages, { read: 2, of: 3 });
    assert.ok(first.snapshot.reasons.includes("pages_over_cap"));
    const second = await scanChain("biedronka", adapter, deps);
    assert.ok(second.kind === "ok");
    assert.equal(second.snapshot.complete, true);
    assert.equal(model.catalogReads.length, 3);
  });

  test("a page the reader can't read is tried twice, then left until its leaflet changes", async () => {
    const model = biedronkaReader().page("biedronka:2", "unparsed");
    const deps = scanDeps({ model });
    const adapter = new FakeAdapter("biedronka", { kind: "ok", leaflets: [imageLeaflet("biedronka", 3)] });
    for (let i = 0; i < 4; i++) await scanChain("biedronka", adapter, deps);
    assert.equal(model.catalogReads.filter((m) => m === "biedronka:2").length, MAX_PAGE_ATTEMPTS);
    const last = await scanChain("biedronka", adapter, deps);
    assert.ok(last.kind === "ok");
    assert.equal(last.snapshot.complete, false);
    assert.ok(last.snapshot.reasons.includes("pages_unreadable"));
  });

  test("an image host that refuses AI input: the page never reaches the reader, and isn't counted as a failed read", async () => {
    const model = biedronkaReader();
    const web = new ImageWeb();
    web.blocked.add("https://img.example/biedronka/2.png");
    const deps = scanDeps({ model, fetcher: web });
    const r = await scanChain("biedronka", new FakeAdapter("biedronka", { kind: "ok", leaflets: [imageLeaflet("biedronka", 3)] }), deps);
    assert.ok(r.kind === "ok");
    assert.equal(model.catalogReads.includes("biedronka:2"), false);
    assert.equal((deps.pageReads as MemoryPageReads).rows.size, 2, "nothing stored for the refused page");
    assert.ok(r.snapshot.reasons.includes("image_blocked"));
  });

  test("without a reader: the chain's own data is kept, image pages are not read, and the snapshot says so", async () => {
    const leaflet: LeafletRead = { ...imageLeaflet("aldi", 2), strategy: "none", products: [
      { name: "Masło ekstra 200 g", price: { minor: 549, currency: "PLN" }, conditions: [], url: "https://aldi.example/p/1" },
    ] };
    const r = await scanChain("aldi", new FakeAdapter("aldi", { kind: "ok", leaflets: [leaflet] }), scanDeps());
    assert.ok(r.kind === "ok");
    assert.equal(r.snapshot.complete, true, "a data-only leaflet needs no reader");
    const images = await scanChain("biedronka", new FakeAdapter("biedronka", { kind: "ok", leaflets: [imageLeaflet("biedronka", 2)] }), scanDeps());
    assert.ok(images.kind === "ok");
    assert.equal(images.snapshot.complete, false);
    assert.ok(images.snapshot.reasons.includes("no_reader"));
  });

  test("a blocked or failing chain keeps its last good snapshot; no leaflet is a snapshot of its own", async () => {
    assert.deepEqual(await scanChain("lidl", new FakeAdapter("lidl", { kind: "blocked", reason: "403" }), scanDeps()), { kind: "failed", reason: "blocked" });
    const thrower = new FakeAdapter("lidl", () => { throw new Error("boom"); });
    assert.deepEqual(await scanChain("lidl", thrower, scanDeps()), { kind: "failed", reason: "adapter_error" });
    const none = await scanChain("lidl", new FakeAdapter("lidl", { kind: "no_leaflet" }), scanDeps());
    assert.ok(none.kind === "ok");
    assert.equal(none.snapshot.noLeaflet, true);
  });
});

describe("a snapshot in a search", () => {
  const snapshot = async (): Promise<ChainSnapshot> => {
    const r = await scanChain("biedronka", new FakeAdapter("biedronka", { kind: "ok", leaflets: [imageLeaflet("biedronka", 3)] }), scanDeps({ model: biedronkaReader() }));
    assert.ok(r.kind === "ok");
    return r.snapshot;
  };

  test("too old, or every leaflet in it ended: stale, so the chain is read live", async () => {
    const s = await snapshot();
    assert.equal(materialFromSnapshot(s, TODAY, new Date(NOW.getTime() + 9 * 24 * 3600_000)), "stale");
    assert.equal(materialFromSnapshot(s, "2026-11-17", NOW), "stale");
    const m = materialFromSnapshot(s, TODAY, NOW);
    assert.ok(typeof m === "object");
    assert.equal(m.endedBefore, TODAY);
    assert.equal(m.reads.get("0:2")?.length, 2);
  });

  test("an ended leaflet is dropped and the rest keep their reads under their new places", async () => {
    const s = await snapshot();
    const ended: LeafletRead = { ...imageLeaflet("biedronka", 1, "https://biedronka.example/old"), leaflet: { url: "https://biedronka.example/old", validFrom: "2026-11-03", validTo: "2026-11-09" } };
    const both: ChainSnapshot = { ...s, leaflets: [ended, ...s.leaflets], reads: Object.fromEntries(Object.entries(s.reads).map(([k, v]) => [`1:${k.split(":")[1]}`, v])) };
    const m = materialFromSnapshot(both, TODAY, NOW);
    assert.ok(typeof m === "object");
    assert.equal(m.leaflets.length, 1);
    assert.equal(m.reads.get("0:2")?.length, 2);
  });

  async function catalogSearch(items: string[], catalog: CatalogStore, live?: Partial<Record<ReadChain, ChainAdapter>>, chains: ReadChain[] = ["biedronka"]) {
    const web = new ImageWeb();
    const model = new CatalogFakeModel();
    const deps: DealsDeps = {
      settings: DEFAULT_DEALS_SETTINGS, fetcher: web, model, now: () => NOW, catalog,
      adapters: { biedronka: new FakeAdapter("biedronka", { kind: "ok", leaflets: [imageLeaflet("biedronka", 3)] }), ...live },
    };
    const r = await searchDeals(deps, { items, chains, language: "pl" });
    return { ...r, web, model };
  }

  test("a catalogued chain answers from the snapshot: no fetch, no page read, the stored price, and Apple-style items too", async () => {
    const s = await snapshot();
    const { response, stats, web, model } = await catalogSearch(["masło", "słuchawki"], new MemoryCatalog(new Map([["biedronka", s]])));
    assert.equal(web.fetched.length, 0, "nothing fetched");
    assert.equal(model.reads.length, 0, "no page read for the search");
    assert.equal(stats.fromCatalog, 1);
    assert.equal(stats.pagesRead, 0);
    // 13 Nov 2026: the row says when the catalog read the chain and that it read all of it.
    assert.deepEqual(response.chains, [{ chain: "biedronka", status: "checked", leaflet: s.leaflets[0]!.leaflet, readAt: s.scannedAt, complete: true }]);
    const butter = response.items[0]!.offers[0]!;
    assert.equal(butter.product, "Masło Extra 82%");
    assert.equal(butter.price.minor, 499);
    assert.equal(butter.readBy, "page_image");
    assert.equal(butter.match, "exact");
    assert.deepEqual(butter.leafletRead, { readAt: NOW.toISOString(), validFrom: "2026-11-10", validTo: "2026-11-16", complete: true });
    assert.equal(response.items[1]!.offers[0]?.product, "Słuchawki bezprzewodowe douszne");
  });

  test("an offer whose last day has passed is left out", async () => {
    const s = await snapshot();
    const { response } = await catalogSearch(["kawa mielona"], new MemoryCatalog(new Map([["biedronka", s]])));
    assert.deepEqual(response.items[0]!.offers, [], "Jacobs ran until 11 Nov");
  });

  test("a stale snapshot, or a catalog that can't be read: the chain is read live, as before", async () => {
    const s = { ...(await snapshot()), scannedAt: "2026-10-01T06:00:00.000Z" };
    const stale = await catalogSearch(["masło"], new MemoryCatalog(new Map([["biedronka", s]])));
    assert.equal(stale.stats.fromCatalog, 0);
    assert.ok(stale.web.fetched.length > 0, "read live");
    const down = await catalogSearch(["masło"], new MemoryCatalog(new Map(), true));
    assert.equal(down.stats.fromCatalog, 0);
    assert.ok(down.web.fetched.length > 0);
  });

  test("a chain the catalog doesn't hold is read live next to one it does; a no-leaflet snapshot is that chain's row", async () => {
    assert.equal(CATALOG_CHAINS.includes("rossmann"), false, "Rossmann reads by the item: never catalogued");
    const s = await snapshot();
    const lidlNone: ChainSnapshot = { chain: "lidl", scannedAt: NOW.toISOString(), noLeaflet: true, leaflets: [], reads: {}, complete: true, reasons: [] };
    const rossmann = new FakeAdapter("rossmann", { kind: "no_leaflet" });
    const { response, stats } = await catalogSearch(["masło"], new MemoryCatalog(new Map<ReadChain, ChainSnapshot>([["biedronka", s], ["lidl", lidlNone]])),
      { rossmann }, ["biedronka", "lidl", "rossmann"]);
    assert.equal(stats.fromCatalog, 2);
    assert.equal(rossmann.calls.length, 1);
    assert.deepEqual(response.chains.map((c) => [c.chain, c.status]), [["biedronka", "checked"], ["lidl", "no_leaflet"], ["rossmann", "no_leaflet"]]);
  });
});

describe("the catalog in the database", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  test("a pass scans each due chain once, keeps its snapshot, and a search store reads it back", async () => {
    const model = biedronkaReader();
    const adapters = Object.fromEntries(CATALOG_CHAINS.map((c) => [c, new FakeAdapter(c, c === "biedronka"
      ? { kind: "ok", leaflets: [imageLeaflet("biedronka", 3)] } : { kind: "no_leaflet" })])) as unknown as Record<ReadChain, ChainAdapter>;
    const logs: { msg: string; extra?: object }[] = [];
    const ctx = {
      db, adapters, fetcher: new ImageWeb(), model, everyHours: 6, maxPagesPerChain: 50, now: () => NOW, today: () => TODAY,
      log: (msg: string, extra?: object) => logs.push({ msg, extra }),
    };
    const counts = await runCatalogPass(ctx);
    assert.equal(counts.complete, CATALOG_CHAINS.length);
    assert.equal(model.catalogReads.length, 3);
    assert.equal(JSON.stringify(logs).includes("Masło"), false, "logs carry codes and counts, never products");

    const again = await runCatalogPass(ctx);
    assert.deepEqual(again, {}, "nothing is due within everyHours");

    const store = new DbCatalogStore(db);
    const held = await store.snapshots(["biedronka", "lidl", "rossmann"]);
    assert.deepEqual([...held.keys()].sort(), ["biedronka", "lidl"]);
    assert.equal(held.get("biedronka")!.reads["0:2"]!.products[0]!.price.minor, 499);
    assert.equal(held.get("lidl")!.noLeaflet, true);

    // Six hours later a failed scan keeps the last good snapshot.
    (adapters.biedronka as FakeAdapter).answer = { kind: "blocked", reason: "403" };
    const later = { ...ctx, now: () => new Date(NOW.getTime() + 6 * 3600_000 + 1000) };
    const failed = await runCatalogPass(later);
    assert.equal(failed.failed, 1);
    const kept = await new DbCatalogStore(db).snapshots(["biedronka"]);
    assert.equal(kept.get("biedronka")!.reads["0:2"]!.products.length, 2);
    const { rows } = await db.query("SELECT last_result FROM leaflet_catalog WHERE chain = 'biedronka'");
    assert.equal(rows[0].last_result, "failed:blocked");
  });

  test("page reads: an ok read is kept, a failure counts its attempts and never replaces an ok read", async () => {
    const store = new DbPageReadStore(db);
    const key = "0123456789abcdef0123456789abcdef";
    await store.putFailed("dino", key);
    await store.putFailed("dino", key);
    assert.deepEqual((await store.get("dino", [key])).get(key), { kind: "failed", attempts: 2 });
    await store.putOk("dino", key, { products: [], promotions: [] });
    await store.putFailed("dino", key);
    const ok = (await store.get("dino", [key])).get(key);
    assert.ok(ok?.kind === "ok");
    assert.deepEqual(ok.read, { products: [], promotions: [] });
    assert.match(ok.readAt ?? "", /^\d{4}-\d{2}-\d{2}T/, "an ok read carries when it was read");
    // 13 Nov 2026: a failure keeps why, so a snapshot can say which pages are missing and why.
    const other = "fedcba9876543210fedcba9876543210";
    await store.putFailed("dino", other, "image_too_large");
    assert.deepEqual((await store.get("dino", [other])).get(other), { kind: "failed", attempts: 1, failure: "image_too_large" });
  });
});
