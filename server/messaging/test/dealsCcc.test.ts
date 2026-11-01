// CCC's sale pages against small synthetic pages in the shape ccc.eu served on 30 Oct 2026 (the tile markup,
// the Omnibus block, the stickers, the pagination). No CCC page is kept here: the brands, models and prices are
// made up for the tests.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { ccc, CCC_MAX_PAGES, CCC_SALE, cccCategories, parseCccPage, stickerCondition, zloty } from "../src/deals/chains/ccc.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext, ChainRead, LeafletRead } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const ORIGIN = "https://ccc.eu";
const ROBOTS = "User-agent: *\nAllow: /\n\nDisallow: */visual-search/*\nDisallow: /pl/pl/*kolor:\nDisallow: */cart\nDisallow: */search\n";
const pln = (minor: number) => ({ minor, currency: "PLN" as const });

interface Tile {
  slug?: string;
  href?: string;
  brand?: string;
  model?: string;
  prices?: { text: string; struck?: boolean }[];
  lowest30d?: string;
  first?: string;
  stickers?: string[];
}

let n = 0;
/** One product tile, in CCC's markup (Angular's attributes and comments included, trimmed). */
function tile(t: Tile): string {
  const i = n++;
  const href = t.href ?? `/pl/pl/p/${t.slug ?? `sneakers-test-${i}`}`;
  const prices = (t.prices ?? [{ text: "149,99&nbsp;zł" }])
    .map((p) => `<span class="${p.struck ? "line-through text-gray-500" : "no-underline text-negative-300"}"> ${p.text} </span>`).join("");
  const omnibus = t.lowest30d || t.first
    ? `<shared-atoms-omnibus-pricing class="block" id="omnibus-${i}" ngskiphydration><div class="smallbody-titlecase-regular py-1">`
      + (t.lowest30d ? `<span>Najniższa cena z 30 dni przed obniżką:</span><span> ${t.lowest30d} </span><br>` : "")
      + (t.first ? `<span>Cena pierwsza:</span><span> ${t.first} </span>` : "")
      + `<div class="flex pr-1 pl-2"></div></div></shared-atoms-omnibus-pricing>`
    : "";
  const stickers = (t.stickers ?? []).map((s) => `<shared-molecules-sticker _ngcontent-ng-c1 size="md"><div class="pointer-events-auto flex" style="color: #0b0a0aff;"><span class="text"><div _ngcontent-ng-c1>${s}</div></span><div class="a-sticker-icon hidden"></div></div></shared-molecules-sticker>`).join("");
  return `<o-product-box tabindex="-1" _nghost-ng-c1 data-product-id="${1000 + i}"><div _ngcontent-ng-c1 class="relative">`
    + `<shared-atoms-link _ngcontent-ng-c1><a class="no-underline" tabindex="-1" href="${href}" jsaction="click:;"><div _ngcontent-ng-c1 internaltext>`
    + `<img class="flex object-cover" src="https://imagedelivery.net/x/${i}_1/mobile" alt="But widziany z boku.">`
    + `<div _ngcontent-ng-c1 role="group" aria-labelledby="trademark-${i} model-${i} price-${i} omnibus-${i}">`
    + (t.brand === "" ? "" : `<strong _ngcontent-ng-c1 class="bodycopy-titlecase-medium line-clamp-2 block" id="trademark-${i}"> ${t.brand ?? "Testmark"} </strong>`)
    + (t.model === "" ? "" : `<span _ngcontent-ng-c1 class="product-name bodycopy-titlecase-regular" id="model-${i}"> ${t.model ?? "MODEL ONE"} </span>`)
    + `</div></div></a></shared-atoms-link>`
    + `<m-product-pricing _ngcontent-ng-c1 pricing aria-hidden="true"><div><div class="flex"><shared-atoms-pricing class="block" id="price-${i}"><div class="bodycopy-titlecase-medium flex items-center">${prices}</div></shared-atoms-pricing><app-exchange-info-button></app-exchange-info-button></div>${omnibus}</div></m-product-pricing>`
    + `<div _ngcontent-ng-c1 class="pointer-events-none absolute"><div class="flex flex-row flex-wrap gap-1 pt-2 pl-2">${stickers}</div></div>`
    + `</div></o-product-box>`;
}

/** A listing page: the pagination ("Jesteś na stronie 1 z N") and the product grid. */
function page(tiles: string[], pages = 1): string {
  const pagination = `<m-pagination-page-selector ngskiphydration><div class="flex h-10"><div class="flex"><span class="sr-only p-2">Jesteś na stronie</span>`
    + `<div class="h-10"><input type="number" value="1"></div></div><div class="p-2 font-medium text-gray-400">z</div><div class="p-2 font-medium text-gray-400"> ${pages} </div></div></m-pagination-page-selector>`;
  return `<!DOCTYPE html><html lang="pl"><head><title>Wyprzedaż</title></head><body><h1>Sneakersy damskie WYPRZEDAŻ</h1>${pagination}`
    + `<section><product-grid><div class="grid">${tiles.join("")}</div></product-grid></section></body></html>`;
}

const html = { "content-type": "text/html;charset=UTF-8" };
const ctx = (web: FakeWeb, queries: string[]): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: web.fetch }), queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead[] => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? r.leaflets : [];
};
const cat = (path: string) => `${ORIGIN}/pl/pl/c/${path}`;
const p1 = (path: string) => `${cat(path)}?pageSize=100`;
const pN = (path: string, no: number) => `${cat(path)}?pageSize=100&page=${no}`;
/** CCC as a fake web: robots.txt, then the given category pages; anything else 404. */
const cccWeb = (pages: Record<string, string>) => {
  const web = new FakeWeb().robots(ORIGIN, ROBOTS);
  for (const [url, body] of Object.entries(pages)) web.on(url, { headers: html, body });
  return web;
};
/** What reached CCC apart from robots.txt. */
const pageRequests = (web: FakeWeb) => web.requests.map((r) => r.url).filter((u) => !u.endsWith("/robots.txt"));

describe("CCC: which sale pages fit the items", () => {
  const paths = (...q: string[]) => cccCategories(q).map((c) => c.path);

  test("a shoe word and a gender choose one of CCC's sale categories, with the label that goes into the names", () => {
    assert.deepEqual(cccCategories(["sneakersy damskie"]), [
      { path: "damskie/wyprzedaz/sneakersy", label: "sneakersy damskie", url: "https://ccc.eu/pl/pl/c/damskie/wyprzedaz/sneakersy" },
    ]);
    assert.deepEqual(paths("Klapki męskie"), ["meskie/wyprzedaz/klapki"]);
    assert.deepEqual(paths("sandałki dla dziewczynki"), ["dzieciece/wyprzedaz/sandaly"]);
    assert.deepEqual(paths("trampki dla mężczyzn"), ["meskie/wyprzedaz/trampki"]);
    assert.deepEqual(paths("czółenka"), ["damskie/wyprzedaz/szpilki-czolenka"], "heels: CCC has a women's sale page only");
    assert.deepEqual(paths("buty sportowe dziecięce"), ["dzieciece/wyprzedaz/buty-sportowe"]);
    assert.deepEqual(paths("kapcie"), ["dzieciece/wyprzedaz/kapcie"], "only children's slippers have a sale page");
  });

  test("no gender: every gender's page for the kind; several items: each page once, in the items' order", () => {
    assert.deepEqual(paths("sneakersy"), ["damskie/wyprzedaz/sneakersy", "meskie/wyprzedaz/sneakersy", "dzieciece/wyprzedaz/sneakersy"]);
    assert.deepEqual(paths("sneakersy damskie", "klapki męskie", "Sneakersy damskie 38"), ["damskie/wyprzedaz/sneakersy", "meskie/wyprzedaz/klapki"]);
    assert.deepEqual(cccCategories(["sneakersy męskie"])[0]!.label, "sneakersy męskie");
  });

  test("no fitting page: shoes CCC has no sale page for, a gender without one, anything not a shoe", () => {
    assert.deepEqual(paths("kozaki damskie"), []);
    assert.deepEqual(paths("botki", "półbuty męskie", "śniegowce", "kalosze", "mokasyny", "baleriny"), []);
    assert.deepEqual(paths("kapcie damskie"), [], "women's slippers: no sale page");
    assert.deepEqual(paths("buty sportowe damskie"), [], "women's sports shoes: no sale page");
    assert.deepEqual(paths("buty damskie"), [], "no kind named");
    assert.deepEqual(paths("masło", "kawa mielona"), []);
  });
});

describe("CCC: a sale page's tiles as data products", () => {
  test("brand and model with the category as the name; shelf price; the 30-day and first price; the basket discount as a condition", () => {
    const r = parseCccPage(page([tile({
      slug: "sneakers-testmark-c-model-one-czarny-5900000000001", brand: "Testmark", model: "MODEL ONE",
      prices: [{ text: "149,99&nbsp;zł" }], lowest30d: "199,99&nbsp;zł", first: "259,99&nbsp;zł", stickers: ["-30% w koszyku", "Nowa kolekcja"],
    })], 4), "sneakersy damskie")!;
    assert.equal(r.tiles, 1);
    assert.equal(r.pages, 4);
    assert.deepEqual(r.products, [{
      name: "Testmark MODEL ONE, sneakersy damskie",
      price: pln(14999),
      url: "https://ccc.eu/pl/pl/p/sneakers-testmark-c-model-one-czarny-5900000000001",
      conditions: [{ kind: "other", text: "−30% w koszyku" }],
      regularPrice: pln(25999),
      lowest30d: pln(19999),
    }], "the price stays the shelf price; −30% is taken off at the basket; no size, no dates");
    assert.equal("sizeText" in r.products[0]!, false);
  });

  test("the 30-day price and the first price are told apart; a first price not above the shelf price is no regular price", () => {
    const [same, cut, equal] = parseCccPage(page([
      tile({ prices: [{ text: "199,99 zł" }], lowest30d: "259,99 zł", first: "259,99 zł" }),
      tile({ prices: [{ text: "149,99 zł" }], lowest30d: "199,99 zł", first: "259,99 zł" }),
      tile({ prices: [{ text: "99,99 zł" }], lowest30d: "129,99 zł", first: "99,99 zł" }),
    ]), "sneakersy damskie")!.products;
    assert.deepEqual([same!.lowest30d, same!.regularPrice], [pln(25999), pln(25999)]);
    assert.deepEqual([cut!.lowest30d, cut!.regularPrice], [pln(19999), pln(25999)], "cut before: the 30-day price is the lower one");
    assert.deepEqual(equal!.lowest30d, pln(12999));
    assert.equal(equal!.regularPrice, undefined);
  });

  test("a struck price, if CCC shows one, is the regular price; two unstruck prices are not guessed between", () => {
    const [struck, ...rest] = parseCccPage(page([
      tile({ prices: [{ text: "299,99 zł", struck: true }, { text: "1 199,99 zł" }], lowest30d: "1 299,99 zł", first: "1 499,99 zł" }),
      tile({ prices: [{ text: "199,99 zł" }, { text: "149,99 zł" }], lowest30d: "259,99 zł" }),
    ]), "kozaki damskie")!.products;
    assert.deepEqual(struck!.price, pln(119999), "thousands with a space");
    assert.equal(struck!.regularPrice, undefined, "the struck price is not above the shelf price: kept out");
    assert.deepEqual(struck!.lowest30d, pln(129999));
    assert.equal(rest.length, 0);
    const [plain] = parseCccPage(page([tile({ prices: [{ text: "259,99 zł", struck: true }, { text: "149,99 zł" }], lowest30d: "199,99 zł", first: "289,99 zł" })]), "x")!.products;
    assert.deepEqual(plain!.regularPrice, pln(25999), "the struck price wins over the first price");
  });

  test("code and basket stickers become conditions that name the code; other stickers don't; money amounts are never stated", () => {
    assert.deepEqual(stickerCondition("-30% w koszyku"), { kind: "other", text: "−30% w koszyku" });
    assert.deepEqual(stickerCondition("-20% z kodem JESIEN20"), { kind: "other", text: "−20% z kodem JESIEN20" });
    assert.deepEqual(stickerCondition("Kod: CCC15 -15% w koszyku"), { kind: "other", text: "−15% w koszyku z kodem CCC15" });
    assert.deepEqual(stickerCondition("-50 zł z kodem EXTRA50"), { kind: "other", text: "rabat z kodem EXTRA50" });
    assert.deepEqual(stickerCondition("Dodatkowe 10% w koszyku"), { kind: "other", text: "−10% w koszyku" });
    for (const s of ["Okazja", "Nowa kolekcja", "AI", "-30%", "Bestseller", "z kodem"]) assert.equal(stickerCondition(s), undefined, s);
    const [p] = parseCccPage(page([tile({ lowest30d: "199,99 zł", stickers: ["Okazja", "-20% z kodem JESIEN20", "-20% z kodem JESIEN20"] })]), "x")!.products;
    assert.deepEqual(p!.conditions, [{ kind: "other", text: "−20% z kodem JESIEN20" }]);
  });

  test("only promoted tiles; a tile without a product page on ccc.eu, a name or a price is left out", () => {
    const r = parseCccPage(page([
      tile({ prices: [{ text: "149,99 zł" }] }),
      tile({ prices: [{ text: "149,99 zł" }], stickers: ["Nowa kolekcja"] }),
      tile({ prices: [{ text: "149,99 zł" }], stickers: ["-30% w koszyku"] }),
      tile({ href: "https://evil.example/pl/pl/p/x", lowest30d: "199,99 zł" }),
      tile({ href: "/pl/pl/c/damskie", lowest30d: "199,99 zł" }),
      tile({ brand: "", model: "", lowest30d: "199,99 zł" }),
      tile({ prices: [{ text: "Brak" }], lowest30d: "199,99 zł" }),
      tile({ brand: "", model: "Sneakersy zamszowe", lowest30d: "199,99 zł" }),
    ]), "sneakersy damskie")!;
    assert.equal(r.tiles, 8);
    assert.deepEqual(r.products.map((p) => [p.name, p.conditions.length, p.lowest30d?.minor]), [
      ["Testmark MODEL ONE, sneakersy damskie", 1, undefined],
      ["Sneakersy zamszowe, sneakersy damskie", 0, 19999],
    ]);
  });

  test("a page without product tiles is not read; money in CCC's text", () => {
    assert.equal(parseCccPage("<html><body><h1>Nie znaleziono</h1></body></html>", "x"), undefined);
    assert.deepEqual(zloty(" 149,99&nbsp;zł "), pln(14999));
    assert.deepEqual(zloty("1 299,99 zł"), pln(129999));
    assert.equal(zloty("od 149,99 zł"), undefined);
  });
});

describe("CCC: the adapter", () => {
  const SNEAKERS = "damskie/wyprzedaz/sneakersy";

  test("reads the fitting category's pages from ccc.eu only, never a search, never the person's words, at most three", async () => {
    const tiles = (no: number) => [1, 2].map((k) => tile({ slug: `sneakers-p${no}-${k}`, lowest30d: "199,99 zł", first: "259,99 zł", stickers: ["-30% w koszyku"] }));
    const web = cccWeb({
      [p1(SNEAKERS)]: page(tiles(1), 6), [pN(SNEAKERS, 2)]: page(tiles(2), 6), [pN(SNEAKERS, 3)]: page(tiles(3), 6), [pN(SNEAKERS, 4)]: page(tiles(4), 6),
    });
    const r = await ccc.read(ctx(web, ["sneakersy damskie biało-czarne"]));
    const [l, ...rest] = ok(r);
    assert.equal(rest.length, 0);
    assert.deepEqual(l!.leaflet, { title: "Promocje CCC", url: cat(SNEAKERS) });
    assert.equal(l!.strategy, "none");
    assert.deepEqual(l!.pages, []);
    assert.equal(l!.products.length, 6);
    assert.ok(l!.products.every((p) => p.url.startsWith("https://ccc.eu/pl/pl/p/sneakers-p") && p.name.endsWith(", sneakersy damskie")));
    assert.equal(r.kind === "ok" && r.incomplete, "some_pages_not_read", "6 pages, 3 read: a cheaper pair may be on the rest");
    const asked = pageRequests(web);
    assert.deepEqual([...asked].sort(), [p1(SNEAKERS), pN(SNEAKERS, 2), pN(SNEAKERS, 3)].sort());
    assert.ok(asked.length <= CCC_MAX_PAGES);
    assert.deepEqual([...web.hosts()], ["ccc.eu"]);
    assert.ok(asked.every((u) => !/search|bia|czarn/i.test(u)), "no search page, none of the item's other words");
  });

  test("several categories: each first page first, while requests are left; the link is CCC's whole sale", async () => {
    const one = (slug: string) => [tile({ slug, lowest30d: "99,99 zł" })];
    const web = cccWeb({
      [p1("damskie/wyprzedaz/sneakersy")]: page(one("a1"), 3), [pN("damskie/wyprzedaz/sneakersy", 2)]: page(one("a2"), 3),
      [p1("meskie/wyprzedaz/sneakersy")]: page(one("b1"), 1),
      [p1("dzieciece/wyprzedaz/sneakersy")]: page(one("c1"), 1),
    });
    const r = await ccc.read(ctx(web, ["sneakersy"]));
    const [l] = ok(r);
    assert.equal(l!.leaflet.url, CCC_SALE);
    assert.deepEqual(l!.products.map((p) => `${p.url.split("/").pop()} ${p.name.split(", ")[1]}`).sort(),
      ["a1 sneakersy damskie", "b1 sneakersy męskie", "c1 sneakersy dziecięce"]);
    assert.equal(pageRequests(web).length, 3, "every gender's first page before any second page");
    assert.equal(r.kind === "ok" && r.incomplete, "some_pages_not_read", "women's pages 2 and 3 weren't read");
  });

  test("more fitting categories than requests: three read, the rest said", async () => {
    const web = new FakeWeb().robots(ORIGIN, ROBOTS).onPrefix(`${ORIGIN}/pl/pl/c/`, { headers: html, body: page([tile({ lowest30d: "99,99 zł" })]) });
    const r = await ccc.read(ctx(web, ["sneakersy", "trampki"]));
    ok(r);
    assert.equal(pageRequests(web).length, CCC_MAX_PAGES);
    assert.equal(r.kind === "ok" && r.incomplete, "some_categories_not_read");
  });

  test("no fitting category: no_leaflet, and nothing is fetched, not even robots.txt", async () => {
    const web = cccWeb({});
    assert.deepEqual(await ccc.read(ctx(web, ["masło", "kozaki damskie"])), { kind: "no_leaflet" });
    assert.equal(web.requests.length, 0);
  });

  test("a page with tiles but nothing promoted is no_leaflet; a page without tiles is failed", async () => {
    const plain = cccWeb({ [p1(SNEAKERS)]: page([tile({ stickers: ["Nowa kolekcja"] })]) });
    assert.deepEqual(await ccc.read(ctx(plain, ["sneakersy damskie"])), { kind: "no_leaflet" });
    const changed = cccWeb({ [p1(SNEAKERS)]: "<html><body><div class=\"grid\"></div></body></html>" });
    assert.deepEqual(await ccc.read(ctx(changed, ["sneakersy damskie"])), { kind: "failed", reason: "no_products" });
  });

  test("a block is blocked and stops the rest; robots.txt disallowing is blocked with no page fetched; a missing page is failed", async () => {
    const blocked = cccWeb({}).onPrefix(`${ORIGIN}/pl/pl/c/`, { status: 403 });
    assert.deepEqual(await ccc.read(ctx(blocked, ["sneakersy damskie"])), { kind: "blocked", reason: "blocked:http_403" });
    const many = cccWeb({}).onPrefix(`${ORIGIN}/pl/pl/c/`, { status: 429 });
    assert.equal((await ccc.read(ctx(many, ["sneakersy"]))).kind, "blocked");
    assert.ok(pageRequests(many).length <= 2, "at most the requests already in flight");
    const shut = cccWeb({ [p1(SNEAKERS)]: page([tile({ lowest30d: "99,99 zł" })]) }).robots(ORIGIN, "User-agent: *\nDisallow: /pl/pl/c/\n");
    assert.deepEqual(await ccc.read(ctx(shut, ["sneakersy damskie"])), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(pageRequests(shut).length, 0);
    assert.deepEqual(await ccc.read(ctx(cccWeb({}), ["sneakersy damskie"])), { kind: "failed", reason: "http_404" });
  });

  test("one category missing, another read: the products, with the read marked incomplete", async () => {
    const web = cccWeb({ [p1("meskie/wyprzedaz/klapki")]: page([tile({ slug: "klapki-x", lowest30d: "59,99 zł", first: "79,99 zł" })]) });
    const r = await ccc.read(ctx(web, ["sneakersy damskie", "klapki męskie"]));
    const [l] = ok(r);
    assert.deepEqual(l!.leaflet.url, cat("meskie/wyprzedaz/klapki"), "only one category was read: its page is the link");
    assert.deepEqual(l!.products.map((p) => p.name), ["Testmark MODEL ONE, klapki męskie"]);
    assert.equal(r.kind === "ok" && r.incomplete, "some_pages_failed");
  });
});
