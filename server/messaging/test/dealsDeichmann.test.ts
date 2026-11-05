// Deichmann's sale pages against small synthetic pages in the shape deichmann.com served on 30 Oct 2026 (the tile
// markup with Angular's attributes, the "Cena regularna" and "Najniższa cena" lines, the tags, the pagination). No
// Deichmann page is kept here: the brands, models and prices are made up for the tests.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { deichmann, DEICHMANN_MAX_PAGES, DEICHMANN_SALE, deichmannCategories, parseDeichmannPage } from "../src/deals/chains/deichmann.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext, ChainRead, LeafletRead } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const ORIGIN = "https://www.deichmann.com";
const ROBOTS = "User-agent: *\nDisallow: /search?q=\n\nSitemap: https://www.deichmann.com/sitemap.xml\n";
const pln = (minor: number) => ({ minor, currency: "PLN" as const });

interface Tile {
  slug?: string;
  href?: string;
  brand?: string;
  model?: string;
  /** The shelf prices printed (one on every real tile). */
  prices?: string[];
  regular?: string;
  regularLabel?: string;
  lowest?: string;
  lowestLabel?: string;
  tags?: string[];
  /** Other colours of the product: links to other product pages, after the tile's own. */
  colours?: string[];
}

let n = 0;
const NG = (k: string) => `_ngcontent-ng-c${k}`;
/** One product tile, in Deichmann's markup (Angular's attributes and comments included, trimmed). */
function tile(t: Tile): string {
  const i = n++;
  const href = t.href ?? `/pl-pl/p/${t.slug ?? `testmark-sneakersy-czarny-${9000 + i}`}`;
  const tags = (t.tags ?? ["SALE"]).map((s) => `<span ${NG("13")} style="background-color: #d44141;" class="large" data-testid="${s}"><!----> ${s} <!----><!----></span>`).join("");
  const prices = (t.prices ?? ["127,99&nbsp;zł"]).map((p) => `<span ${NG("24")} data-id="selling-price" class="price text-price-sale"> ${p} </span><!---->`).join("");
  const regular = t.regular
    ? `<div ${NG("24")} class="lowest-prior"><span ${NG("24")}>${t.regularLabel ?? "Cena regularna:"}</span><span ${NG("24")}>${t.regular}</span><strong ${NG("24")} class="discount"> -20% </strong><!----></div><!---->`
    : "";
  const lowest = t.lowest
    ? `<div ${NG("24")} class="lowest-prior"><span ${NG("24")}>${t.lowestLabel ?? "Najniższa cena:"}</span><span ${NG("24")}>${t.lowest}</span><strong ${NG("24")} class="negative"> -20% </strong></div><!---->`
    : "";
  const colours = (t.colours ?? []).map((c) => `<div ${NG("39")} class="color-link"><a ${NG("39")} aria-label="Testmark" href="${c}" jsaction="click:;"></a></div>`).join("");
  return `<deich-lib-product-tile ${NG("38")} role="listitem" _nghost-ng-c39 data-id="0${2600000 + i}" aria-label="product-tile-item-0${2600000 + i}" ngh="36">`
    + `<div ${NG("39")} class="card"><div ${NG("39")} class="icon-action"><deich-lib-add-to-wish-list ${NG("39")} class="pos-upper-right"><deich-lib-hydra-icon-button ${NG("9")} arialabel="toggle-wishlist-for-item"><button ${NG("41")} class="hydra-button color-dark rounded" aria-label="toggle-wishlist-for-item"><i class="icon icon-wishlist"></i><!----></button></deich-lib-hydra-icon-button><!----></deich-lib-add-to-wish-list><!----></div><!----><!---->`
    + `<a ${NG("39")} aria-label="Testmark Sneakersy czarny" href="${href}" jsaction="click:;"></a>`
    + `<deich-lib-hydra-tag-list ${NG("39")} _nghost-ng-c13 class ngh="29">${tags}<!----></deich-lib-hydra-tag-list><!---->`
    + `<deich-image ${NG("39")} ngh="9"><img class="desktop img-cover" alt="Testmark Sneakersy czarny" src="https://asset.deichmann.com/images/x/${i}_1"><!----></deich-image><!----><!---->`
    + `<div ${NG("39")} class="product-attributes"><deich-lib-product-price ${NG("39")} ngh="31"><!----><deich-lib-tile-product-price ${NG("31")} _nghost-ng-c24 ngh="30">`
    + `<div ${NG("24")} class="general"><div ${NG("24")} class="main"><!---->${prices}</div><!----><!---->${regular}${lowest}<!----></div></deich-lib-tile-product-price><!----></deich-lib-product-price><!---->`
    + `<div ${NG("39")} class="brand-details">${t.brand === "" ? "" : `<h2 ${NG("39")} class="brandname"> ${t.brand ?? "Testmark"} </h2>`}<div ${NG("39")} class="set-into-row"><!---->`
    + `${t.model === "" ? "" : `<h3 ${NG("39")} class="taglist"> ${t.model ?? "RUNNER ONE Sneakersy"} </h3>`}</div></div>`
    + (colours ? `<div ${NG("39")} class="color-list">${colours}<!----></div>` : "")
    + `<!----></div></div><!----></deich-lib-product-tile>`;
}

/** A listing page: the pagination ("Strona 1 od N", absent with one page) and the product grid. */
function page(tiles: string[], pages = 1): string {
  const pagination = pages > 1
    ? `<deich-lib-pagination ${NG("22")}><div ${NG("22")}><span ${NG("22")}>Strona</span><span ${NG("22")} class="num">1</span><span ${NG("22")}>od</span><span ${NG("22")} class="num">${pages}</span></div>`
      + `<a ${NG("41")} class="hydra-button" data-testid="switch-to-next-page" href="/pl-pl/c/damskie/wyprzedaz-sneakersy-570?page=2"></a></deich-lib-pagination>`
    : "";
  return `<!DOCTYPE html><html lang="pl-PL"><head><title>Wyprzedaż sneakersy | DEICHMANN</title></head><body><h1>Wyprzedaż sneakersy</h1>`
    + `<section class="product-list"><div class="grid">${tiles.join("<!---->")}</div></section>${pagination}`
    + `<script id="ng-state" type="application/json">{"lang":"pl-pl"}</script></body></html>`;
}

const html = { "content-type": "text/html; charset=utf-8" };
const ctx = (web: FakeWeb, queries: string[]): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: web.fetch }), queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead[] => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? r.leaflets : [];
};
const cat = (path: string) => `${ORIGIN}/pl-pl/c/${path}`;
const pN = (path: string, no: number) => `${cat(path)}?page=${no}`;
/** Deichmann as a fake web: robots.txt, then the given category pages; anything else 404. */
const deichmannWeb = (pages: Record<string, string>) => {
  const web = new FakeWeb().robots(ORIGIN, ROBOTS);
  for (const [url, body] of Object.entries(pages)) web.on(url, { headers: html, body });
  return web;
};
/** What reached Deichmann apart from robots.txt. */
const pageRequests = (web: FakeWeb) => web.requests.map((r) => r.url).filter((u) => !u.endsWith("/robots.txt"));

describe("Deichmann: which sale pages fit the items", () => {
  const paths = (...q: string[]) => deichmannCategories(q).map((c) => c.path);

  test("a shoe word and a gender choose one of Deichmann's sale categories, with the label that goes into the names", () => {
    assert.deepEqual(deichmannCategories(["sneakersy damskie"]), [
      { path: "damskie/wyprzedaz-sneakersy-570", label: "sneakersy damskie", url: "https://www.deichmann.com/pl-pl/c/damskie/wyprzedaz-sneakersy-570" },
    ]);
    assert.deepEqual(paths("Kozaki damskie"), ["damskie/wyprzedaz-kozaki-572"]);
    assert.deepEqual(paths("botki męskie"), ["meskie/wyprzedaz-botki-601"]);
    assert.deepEqual(paths("kozaki męskie"), ["meskie/wyprzedaz-botki-i-kozaki-615"], "men's kozaki are sold under botki i kozaki");
    assert.deepEqual(paths("sandałki dla dziewczynki"), ["dzieciece/wyprzedaz-sandaly-643"]);
    assert.deepEqual(paths("klapki dla mężczyzn"), ["meskie/wyprzedaz-klapki-612"]);
    assert.deepEqual(paths("kapcie dziecięce"), ["dzieciece/wyprzedaz-kapcie-637"]);
    assert.deepEqual(paths("półbuty damskie"), ["damskie/wyprzedaz-polbuty-574"]);
    assert.deepEqual(paths("szpilki"), ["damskie/wyprzedaz-czolenka-577"], "heels: a women's sale page only");
    assert.deepEqual(paths("obuwie sportowe męskie"), ["meskie/wyprzedaz-buty-sportowe-608"]);
    assert.deepEqual(paths("buty eleganckie męskie"), ["meskie/wyprzedaz-eleganckie-buty-616"]);
    assert.deepEqual(paths("kalosze"), ["dzieciece/wyprzedaz-kalosze-650"], "only children's wellies have a sale page");
  });

  test("no gender: every gender's page for the kind; several items: each page once, in the items' order", () => {
    assert.deepEqual(paths("sneakersy"), ["damskie/wyprzedaz-sneakersy-570", "meskie/wyprzedaz-sneakersy-602", "dzieciece/wyprzedaz-sneakersy-634"]);
    assert.deepEqual(paths("kozaki"), ["damskie/wyprzedaz-kozaki-572", "meskie/wyprzedaz-botki-i-kozaki-615", "dzieciece/wyprzedaz-botki-i-kozaki-647"]);
    assert.deepEqual(paths("sneakersy damskie", "klapki męskie", "Sneakersy damskie 38"), ["damskie/wyprzedaz-sneakersy-570", "meskie/wyprzedaz-klapki-612"]);
    assert.equal(deichmannCategories(["kozaki dla chłopca"])[0]!.label, "botki i kozaki dziecięce");
  });

  test("no fitting page: shoes Deichmann has no sale page for, a gender without one, anything not a shoe", () => {
    assert.deepEqual(paths("trampki", "tenisówki", "mokasyny", "śniegowce", "espadryle"), []);
    assert.deepEqual(paths("sandały męskie"), [], "men's sandals: no sale page on 30 Oct");
    assert.deepEqual(paths("kalosze damskie"), []);
    assert.deepEqual(paths("buty damskie"), [], "no kind named");
    assert.deepEqual(paths("masło", "kawa mielona", "karma dla kota"), []);
  });
});

describe("Deichmann: a sale page's tiles as data products", () => {
  test("brand, model and kind with the category as the name; shelf price; the regular and the 30-day price; the page count", () => {
    const r = parseDeichmannPage(page([tile({
      slug: "testmark-runner-one-sneakersy-czarny-150001", brand: "Testmark", model: "RUNNER ONE Sneakersy",
      prices: ["127,99&nbsp;zł"], regular: "159,99&nbsp;zł", lowest: "149,99&nbsp;zł", tags: ["SALE"],
      colours: ["/pl-pl/p/testmark-runner-one-sneakersy-bialy-150002"],
    })], 6), "sneakersy damskie")!;
    assert.equal(r.tiles, 1);
    assert.equal(r.pages, 6);
    assert.deepEqual(r.products, [{
      name: "Testmark RUNNER ONE Sneakersy, sneakersy damskie",
      price: pln(12799),
      url: "https://www.deichmann.com/pl-pl/p/testmark-runner-one-sneakersy-czarny-150001",
      conditions: [],
      regularPrice: pln(15999),
      lowest30d: pln(14999),
    }], "the tile's own page, not the other colour's; no size, no dates");
  });

  test("the 30-day line only when labelled the lowest price; a regular price not above the shelf price is left out", () => {
    const [labelled, pdp, same, unlabelled] = parseDeichmannPage(page([
      tile({ prices: ["223,95 zł"], regular: "319,99 zł", lowest: "223,96 zł" }),
      tile({ prices: ["99,99 zł"], lowest: "129,99 zł", lowestLabel: "Najniższa cena z 30 dni przed obniżką:" }),
      tile({ prices: ["99,99 zł"], regular: "99,99 zł", lowest: "99,99 zł" }),
      tile({ prices: ["99,99 zł"], regular: "149,99 zł", lowest: "129,99 zł", lowestLabel: "Cena w sklepie:" }),
    ]), "x")!.products;
    assert.deepEqual([labelled!.price, labelled!.regularPrice, labelled!.lowest30d], [pln(22395), pln(31999), pln(22396)]);
    assert.deepEqual(pdp!.lowest30d, pln(12999));
    assert.equal(pdp!.regularPrice, undefined);
    assert.equal(same!.regularPrice, undefined, "not above the shelf price");
    assert.deepEqual(same!.lowest30d, pln(9999), "kept as printed: the offer then says it is no cut");
    assert.deepEqual([unlabelled!.regularPrice, unlabelled!.lowest30d], [pln(14999), undefined], "an unknown label is no 30-day price");
    const [first] = parseDeichmannPage(page([tile({ prices: ["89,99 zł"], regular: "119,99 zł", regularLabel: "Cena pierwsza:" })]), "x")!.products;
    assert.deepEqual(first!.regularPrice, pln(11999));
  });

  test("code and basket tags become conditions that name the code; Tylko online is said; SALE and -20% are not conditions", () => {
    const [coded, online, plain] = parseDeichmannPage(page([
      tile({ prices: ["159,99 zł"], tags: ["kod: HALLO20", "Nowość"] }),
      tile({ regular: "159,99 zł", tags: ["SALE", "Tylko online", "-20% w koszyku", "-20% w koszyku"] }),
      tile({ regular: "159,99 zł", lowest: "159,99 zł", tags: ["-20%", "SALE"] }),
    ]), "x")!.products;
    assert.deepEqual(coded!.conditions, [{ kind: "other", text: "rabat z kodem HALLO20" }], "the code as printed; no amount of money");
    assert.deepEqual([coded!.regularPrice, coded!.lowest30d], [undefined, undefined]);
    assert.deepEqual(online!.conditions, [{ kind: "other", text: "−20% w koszyku" }, { kind: "other", text: "tylko online" }]);
    assert.deepEqual(plain!.conditions, []);
  });

  test("only reduced tiles; a tile without a product page on deichmann.com, a name or one shelf price is left out", () => {
    const r = parseDeichmannPage(page([
      tile({ prices: ["159,99 zł"], tags: ["Nowość"] }),
      tile({ prices: ["159,99 zł"], tags: ["Tylko online"] }),
      tile({ regular: "149,99 zł", tags: ["SALE"] }),
      tile({ href: "https://evil.example/pl-pl/p/x-1", lowest: "199,99 zł" }),
      tile({ href: "/pl-pl/c/damskie/wyprzedaz-567", lowest: "199,99 zł" }),
      tile({ href: "http://www.deichmann.com/pl-pl/p/insecure-2", lowest: "199,99 zł" }),
      tile({ brand: "", model: "", lowest: "199,99 zł" }),
      tile({ prices: ["od 99,99 zł"], lowest: "199,99 zł" }),
      tile({ prices: ["129,99 zł", "119,99 zł"], lowest: "199,99 zł" }),
      tile({ prices: [], lowest: "199,99 zł" }),
      tile({ brand: "", model: "Muszkieterki", prices: ["139,95 zł"], regular: "199,99 zł" }),
    ]), "kozaki damskie")!;
    assert.equal(r.tiles, 11);
    assert.deepEqual(r.products.map((p) => [p.name, p.price.minor, p.regularPrice?.minor]), [
      ["Testmark RUNNER ONE Sneakersy, kozaki damskie", 12799, 14999],
      ["Muszkieterki, kozaki damskie", 13995, 19999],
    ]);
    assert.equal(r.pages, undefined, "one page: no pagination");
  });

  test("a page without product tiles is not read; the same product twice is one product", () => {
    assert.equal(parseDeichmannPage("<html><body><h1>Nie znaleziono strony</h1></body></html>", "x"), undefined);
    const twice = tile({ slug: "same-1", regular: "159,99 zł" });
    assert.equal(parseDeichmannPage(page([twice, twice]), "x")!.products.length, 1);
  });
});

describe("Deichmann: the adapter", () => {
  const SNEAKERS = "damskie/wyprzedaz-sneakersy-570";

  test("reads the fitting category's pages from www.deichmann.com only, never a search, never the person's words, at most three", async () => {
    const tiles = (no: number) => [1, 2].map((k) => tile({ slug: `sneakersy-p${no}-${k}`, regular: "159,99 zł", lowest: "159,99 zł", tags: ["SALE", "Tylko online"] }));
    const web = deichmannWeb({
      [cat(SNEAKERS)]: page(tiles(1), 6), [pN(SNEAKERS, 2)]: page(tiles(2), 6), [pN(SNEAKERS, 3)]: page(tiles(3), 6), [pN(SNEAKERS, 4)]: page(tiles(4), 6),
    });
    const r = await deichmann.read(ctx(web, ["sneakersy damskie biało-czarne rozmiar 38"]));
    const [l, ...rest] = ok(r);
    assert.equal(rest.length, 0);
    assert.deepEqual(l!.leaflet, { title: "Wyprzedaż Deichmann", url: cat(SNEAKERS) });
    assert.equal(l!.strategy, "none");
    assert.deepEqual(l!.pages, []);
    assert.equal(l!.products.length, 6);
    assert.ok(l!.products.every((p) => p.url.startsWith("https://www.deichmann.com/pl-pl/p/sneakersy-p") && p.name.endsWith(", sneakersy damskie")));
    assert.equal(r.kind === "ok" && r.incomplete, "some_pages_not_read", "6 pages, 3 read: a cheaper pair may be on the rest");
    const asked = pageRequests(web);
    assert.deepEqual([...asked].sort(), [cat(SNEAKERS), pN(SNEAKERS, 2), pN(SNEAKERS, 3)].sort());
    assert.ok(asked.length <= DEICHMANN_MAX_PAGES);
    assert.deepEqual([...web.hosts()], ["www.deichmann.com"]);
    assert.ok(asked.every((u) => !/search|bia|czarn|rozmiar|38/i.test(u)), "no search page, none of the item's other words");
    assert.ok(web.requests.every((q) => /^DoddyBot\//.test(q.headers["user-agent"] ?? "")), "as DoddyBot");
  });

  test("several categories: each first page first, while requests are left; the link is Deichmann's whole sale", async () => {
    const one = (slug: string) => [tile({ slug, lowest: "99,99 zł", regular: "129,99 zł" })];
    const web = deichmannWeb({
      [cat("damskie/wyprzedaz-sneakersy-570")]: page(one("a1"), 3), [pN("damskie/wyprzedaz-sneakersy-570", 2)]: page(one("a2"), 3),
      [cat("meskie/wyprzedaz-sneakersy-602")]: page(one("b1")),
      [cat("dzieciece/wyprzedaz-sneakersy-634")]: page(one("c1")),
    });
    const r = await deichmann.read(ctx(web, ["sneakersy"]));
    const [l] = ok(r);
    assert.equal(l!.leaflet.url, DEICHMANN_SALE);
    assert.deepEqual(l!.products.map((p) => `${p.url.split("/").pop()} ${p.name.split(", ")[1]}`).sort(),
      ["a1 sneakersy damskie", "b1 sneakersy męskie", "c1 sneakersy dziecięce"]);
    assert.equal(pageRequests(web).length, 3, "every gender's first page before any second page");
    assert.equal(r.kind === "ok" && r.incomplete, "some_pages_not_read", "women's pages 2 and 3 weren't read");
  });

  test("two categories with more pages: the third request is the first category's second page", async () => {
    const one = (slug: string) => [tile({ slug, regular: "129,99 zł" })];
    const web = deichmannWeb({
      [cat("damskie/wyprzedaz-kozaki-572")]: page(one("k1"), 2), [pN("damskie/wyprzedaz-kozaki-572", 2)]: page(one("k2"), 2),
      [cat("damskie/wyprzedaz-botki-569")]: page(one("b1"), 4), [pN("damskie/wyprzedaz-botki-569", 2)]: page(one("b2"), 4),
    });
    const r = await deichmann.read(ctx(web, ["kozaki damskie", "botki damskie"]));
    ok(r);
    assert.deepEqual(pageRequests(web).sort(), [cat("damskie/wyprzedaz-botki-569"), cat("damskie/wyprzedaz-kozaki-572"), pN("damskie/wyprzedaz-kozaki-572", 2)].sort());
    assert.equal(r.kind === "ok" && r.incomplete, "some_pages_not_read");
  });

  test("more fitting categories than requests: three read, the rest said", async () => {
    const web = new FakeWeb().robots(ORIGIN, ROBOTS).onPrefix(`${ORIGIN}/pl-pl/c/`, { headers: html, body: page([tile({ lowest: "99,99 zł" })]) });
    const r = await deichmann.read(ctx(web, ["sneakersy", "klapki"]));
    ok(r);
    assert.equal(pageRequests(web).length, DEICHMANN_MAX_PAGES);
    assert.equal(r.kind === "ok" && r.incomplete, "some_categories_not_read");
  });

  test("no fitting category: no_leaflet, and nothing is fetched, not even robots.txt", async () => {
    const web = deichmannWeb({});
    assert.deepEqual(await deichmann.read(ctx(web, ["masło", "trampki damskie"])), { kind: "no_leaflet" });
    assert.equal(web.requests.length, 0);
  });

  test("a page with tiles but nothing reduced is no_leaflet; a page without tiles is failed", async () => {
    const plain = deichmannWeb({ [cat(SNEAKERS)]: page([tile({ tags: ["Nowość", "Tylko online"] })]) });
    assert.deepEqual(await deichmann.read(ctx(plain, ["sneakersy damskie"])), { kind: "no_leaflet" });
    const changed = deichmannWeb({ [cat(SNEAKERS)]: "<html><body><div class=\"grid\"></div></body></html>" });
    assert.deepEqual(await deichmann.read(ctx(changed, ["sneakersy damskie"])), { kind: "failed", reason: "no_products" });
  });

  test("a block is blocked and stops the rest; robots.txt disallowing is blocked with no page fetched; a missing page is failed", async () => {
    const blocked = deichmannWeb({}).onPrefix(`${ORIGIN}/pl-pl/c/`, { status: 403 });
    assert.deepEqual(await deichmann.read(ctx(blocked, ["sneakersy damskie"])), { kind: "blocked", reason: "blocked:http_403" });
    const many = deichmannWeb({}).onPrefix(`${ORIGIN}/pl-pl/c/`, { status: 429 });
    assert.equal((await deichmann.read(ctx(many, ["sneakersy"]))).kind, "blocked");
    assert.ok(pageRequests(many).length <= 2, "at most the requests already in flight");
    const challenge = deichmannWeb({}).onPrefix(`${ORIGIN}/pl-pl/c/`, { status: 403, headers: { "cf-mitigated": "challenge" }, body: "<html></html>" });
    assert.equal((await deichmann.read(ctx(challenge, ["sneakersy damskie"]))).kind, "blocked");
    const shut = deichmannWeb({ [cat(SNEAKERS)]: page([tile({ lowest: "99,99 zł" })]) }).robots(ORIGIN, "User-agent: *\nDisallow: /pl-pl/c/\n");
    assert.deepEqual(await deichmann.read(ctx(shut, ["sneakersy damskie"])), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(pageRequests(shut).length, 0);
    const bot = deichmannWeb({ [cat(SNEAKERS)]: page([tile({ lowest: "99,99 zł" })]) }).robots(ORIGIN, "User-agent: DoddyBot\nDisallow: /\n");
    assert.equal((await deichmann.read(ctx(bot, ["sneakersy damskie"]))).kind, "blocked");
    assert.equal(pageRequests(bot).length, 0);
    assert.deepEqual(await deichmann.read(ctx(deichmannWeb({}), ["sneakersy damskie"])), { kind: "failed", reason: "http_404" });
  });

  test("a page that a redirect took off www.deichmann.com is not read", async () => {
    const web = deichmannWeb({ "https://evil.example/pl-pl/c/x": page([tile({ lowest: "9,99 zł" })]) })
      .on(cat(SNEAKERS), { status: 302, headers: { location: "https://evil.example/pl-pl/c/x" } });
    assert.deepEqual(await deichmann.read(ctx(web, ["sneakersy damskie"])), { kind: "failed", reason: "redirected_off_host" });
  });

  test("one category missing, another read: the products, with the read marked incomplete", async () => {
    const web = deichmannWeb({ [cat("meskie/wyprzedaz-klapki-612")]: page([tile({ slug: "klapki-x", model: "Klapki", lowest: "59,99 zł", regular: "79,99 zł" })]) });
    const r = await deichmann.read(ctx(web, ["sneakersy damskie", "klapki męskie"]));
    const [l] = ok(r);
    assert.deepEqual(l!.leaflet.url, cat("meskie/wyprzedaz-klapki-612"), "only one category was read: its page is the link");
    assert.deepEqual(l!.products.map((p) => p.name), ["Testmark Klapki, klapki męskie"]);
    assert.equal(r.kind === "ok" && r.incomplete, "some_pages_failed");
  });
});
