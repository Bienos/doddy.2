// Action's weekly promotions, against SYNTHETIC pages built here in the shape www.action.com served on 2026-10-30 (a
// Next.js page whose server components payload, in self.__next_f.push chunks, holds the product tiles and the listing's
// pagination). Names, ids and prices are made up; no copy of the shop's page is kept. Nothing reaches the network.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  ACTION_MAX_PAGES, ACTION_PROMO, action, actionConditions, actionPageUrl, dealDates, flightRows, parseActionPage, sizeAndUnit,
} from "../src/deals/chains/action.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { buildOffer } from "../src/deals/service.js";
import type { ChainContext, ChainRead, LeafletRead, Money } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const PAGE = (n: number) => actionPageUrl(n);
// The rules that matter here, as the shop's robots.txt wrote them on 2026-10-30.
const ROBOTS = "User-Agent: *\nDisallow: /*/search/\nDisallow: *&sort\nDisallow: *sort=\nDisallow: *?filter\nDisallow: *&filter\n"
  + "Disallow: */p/*?page=\nDisallow: /p/\nDisallow: *sortBy=\n";
const zl = (minor: number): Money => ({ minor, currency: "PLN" });

// ---------- a synthetic page in the shop's shape ----------

const amount = (v: number) => ({
  amount: v, formatted: `${v.toFixed(2).replace(".", ",")} zł`, formattedWithCurrencyPosition: v.toFixed(2).replace(".", ","),
  whole: Math.floor(v), fractional: Math.round(v * 100) % 100,
});
const DEAL = (dates: string) => ({ code: "IS_DEAL", value: "Promocja tygodnia", valueAddition: null, subValue: dates });
const NEW = { code: "IS_NEW", value: "Nowości", valueAddition: null, subValue: null };

interface TileInput {
  id: string; title: string; description?: string; brand?: string; current: number; original?: number; unit?: string;
  footnote?: string | null; percentage?: string; dates?: string; stickers?: unknown[]; isDeal?: boolean; href?: string;
  currency?: string; priceRange?: unknown;
}
function tile(t: TileInput): Record<string, unknown> {
  const slug = t.title.toLowerCase().normalize("NFD").replace(/\p{M}+/gu, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  const price = {
    anchoredPrice: null, currencyCode: t.currency ?? "PLN", currencyPosition: "NONE",
    current: amount(t.current), original: t.original ? amount(t.original) : null,
    unitInfo: t.unit ? { formatted: t.unit } : null,
    discount: { percentage: t.percentage ?? "-20%", footnote: t.footnote === undefined ? "Najniższa cena z 30 dni przed obniżką" : t.footnote },
    ...(t.priceRange !== undefined ? { priceRange: t.priceRange } : {}),
  };
  return {
    id: t.id, code: t.id, href: t.href ?? `https://www.action.com/pl-pl/p/${t.id}/${slug}/`, title: t.title, description: t.description ?? "",
    image: `https://asset.example/${t.id}`, assets: [], brand: t.brand ?? null, isAvailable: true, isBiocide: false, isDangerousGood: false,
    isMadeWithBiocide: false, isNew: false, isDeal: t.isDeal ?? true, isPlantProtectionGood: false, storesStockAvailability: null,
    storesStockAvailabilityThreshold: 30, price, priceAbtestData: price, hasWarnings: false, warningLabel: null, labels: { energyLabel: null },
    energyLabel: null, stickers: t.stickers ?? [DEAL(t.dates ?? "28.10 – 03.11")], listerStickers: [{ code: "IS_DEAL", value: "Promocja tygodnia", valueAddition: null }],
    reviewStats: null,
  };
}

/** A promotions page: the first tile in the grid's row, the others as rows of their own (as Next streams them), a promo
 * card that isn't a product, the pagination, all in chunks cut anywhere (mid-row too), "<" escaped as Next does. */
function page(tiles: Record<string, unknown>[], p: { page?: number; pages?: number; items?: number; chunk?: number } = {}): string {
  const n = p.page ?? 1;
  const el = (t: Record<string, unknown>, i: number) => ["$", "$L7a", String(t.id), { order: String(i), children: ["$", "$L7b", null, {
    product: t, imageSizes: "(min-width: 1280px) 33vw", analytics: { position: i + 1, indexName: "Production_products_pl-pl", facets: "$67:props:analytics:facets" },
  }] }];
  const id = (i: number) => (0x100 + i).toString(16);
  const rows = [
    `0:${JSON.stringify({ P: null, b: "synthetic", c: ["", "pl-pl", "promocja-tygodnia"] })}`,
    `1:"$Sreact.fragment"`,
    `2:I[14922,["/_next/static/chunks/a.js"],"default"]`,
    `3:${JSON.stringify(["$", "$L79", "promo-card", { url: "https://www.action.com/pl-pl/aplikacja/", text: "Nie możesz się doczekać nowej Promocji Tygodnia? <b>Pobierz</b>" }])}`,
    `4:${JSON.stringify(["$", "div", null, { id: "product-grid", children: [tiles[0] ? el(tiles[0], 0) : null, ...tiles.slice(1).map((_, i) => `$L${id(i)}`)] }])}`,
    `5:${JSON.stringify(["$", "$Lb2", "1", { pagination: { currentPage: n, numberOfPages: p.pages ?? 1, numberOfItems: p.items ?? tiles.length, limitPerPage: 23 }, page: n }])}`,
    ...tiles.slice(1).map((t, i) => `${id(i)}:${JSON.stringify(el(t, i + 1))}`),
    "6:null",
    "7:E{\"digest\":\"not json in a row\"",
  ];
  const text = `${rows.join("\n")}\n`;
  const size = p.chunk ?? 700;
  const scripts: string[] = [];
  for (let i = 0; i < text.length; i += size) {
    scripts.push(`<script>self.__next_f.push(${JSON.stringify([1, text.slice(i, i + size)]).replace(/</g, "\\u003c")})</script>`);
  }
  return `<!DOCTYPE html><html lang="pl-PL"><head><title>Promocja tygodnia | Action PL</title></head><body><div id="product-grid"></div>`
    + `<script>(self.__next_f=self.__next_f||[]).push([0])</script>${scripts.join("")}</body></html>`;
}

const P1 = [
  tile({ id: "9000001", title: "Placki pszenne", description: "8 sztuk | 320 gramów", current: 3.39, original: 3.99, unit: "10,59 zł/kg" }),
  tile({ id: "9000002", title: "Bokserki Kalmo", brand: "Kalmo", description: "Rozmiar M | 2 sztuki", current: 14.95, original: 19.95, unit: "7,48 zł/szt." }),
  tile({ id: "9000003", title: "Batonik Mini", brand: "Słodka Spółka", description: "10 sztuk", current: 11.95, original: 13.49, unit: "60,35 zł/kg" }),
  tile({ id: "9000004", title: "Choinka z filcu", description: "39 cm | Różne kolory", current: 13.95, original: 17.95, unit: "13,95 zł/szt.", stickers: [DEAL("28.10 – 03.11"), NEW] }),
];
const P2 = [
  tile({ id: "9000011", title: "Ocet do czyszczenia Lawenda", description: "1 litr", current: 3.48, original: 3.98, unit: "3,48 zł/l" }),
  tile({ id: "9000012", title: "Żelki Tarantule Gumiś", brand: "Gumiś", description: "800 g", current: 14.39, original: 17.99, unit: "17,99 zł/kg" }),
];
const P3 = [
  tile({ id: "9000021", title: "Żel do WC Cytryna", description: "750 ml", current: 6.29, original: 6.99, unit: "8,39 zł/l" }),
  tile({ id: "9000022", title: "Ręcznik kąpielowy", description: "70 x 140 cm | Różne kolory", current: 19.95, original: 24.95, unit: "19,95 zł/szt." }),
];

function shopWeb(pages: Record<number, string | undefined> = {
  1: page(P1, { pages: 3, items: 8 }), 2: page(P2, { page: 2, pages: 3, items: 8 }), 3: page(P3, { page: 3, pages: 3, items: 8 }),
}): FakeWeb {
  const web = new FakeWeb().robots("https://www.action.com", ROBOTS);
  for (const [n, body] of Object.entries(pages)) if (body !== undefined) web.on(PAGE(Number(n)), { headers: { "content-type": "text/html; charset=utf-8" }, body });
  return web;
}
const ctx = (web: FakeWeb, queries: string[] = ["ręczniki"]): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: web.fetch }), queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead & { incomplete?: string } => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? { ...r.leaflets[0]!, ...(r.incomplete ? { incomplete: r.incomplete } : {}) } : (undefined as never);
};

// ---------- the parser ----------

describe("Action: a promotions page's own data", () => {
  test("each product: title (and brand), price, the footnoted original price as the 30-day lowest, size, unit price, dates, product page", () => {
    const parsed = parseActionPage(page(P1, { pages: 8, items: 169 }), TODAY)!;
    assert.equal(parsed.page, 1);
    assert.equal(parsed.pages, 8);
    assert.equal(parsed.products.length, 4, "the promo card isn't a product");
    assert.deepEqual(parsed.products[0], {
      name: "Placki pszenne", price: zl(339), url: "https://www.action.com/pl-pl/p/9000001/placki-pszenne/", conditions: [],
      sizeText: "320 g", printedUnitPrice: "10,59 zł/kg", lowest30d: zl(399), validFrom: "2026-10-28", validTo: "2026-11-03",
    });
    assert.deepEqual(parsed.products.map((p) => p.name), ["Placki pszenne", "Bokserki Kalmo", "Batonik Mini Słodka Spółka", "Choinka z filcu"],
      "the page's order; the brand is added only where the title leaves it out");
    assert.ok(parsed.products.every((p) => p.regularPrice === undefined && p.lowest30d), "every original price is footnoted as the 30-day lowest");
    assert.ok(parsed.products.every((p) => p.ean === undefined && p.matchText === undefined), "the data carries no EAN and no category: none made up");
  });

  test("an original price without the 30-day footnote is a regular price (only above the price); with it, the 30-day lowest as written", () => {
    const [plain, same, low] = parseActionPage(page([
      tile({ id: "1", title: "Kubek", description: "1 sztuka", current: 9.99, original: 12.99, footnote: null }),
      tile({ id: "2", title: "Talerz", current: 9.99, original: 9.99, footnote: "Cena regularna" }),
      tile({ id: "3", title: "Miska", current: 9.99, original: 8.99 }),
    ]), TODAY)!.products;
    assert.deepEqual([plain!.regularPrice, plain!.lowest30d], [zl(1299), undefined]);
    assert.deepEqual([same!.regularPrice, same!.lowest30d], [undefined, undefined], "a regular price not above the price isn't kept");
    assert.deepEqual(low!.lowest30d, zl(899), "the shop's 30-day price is passed on as written; the service says it isn't a cut");
    const offer = buildOffer({ chain: "action", name: low!.name, price: low!.price, lowest30d: low!.lowest30d, conditions: [], source: { url: low!.url }, readBy: "leaflet_data", doubts: [] }, "pl");
    assert.equal(offer.offer.check, true);
  });

  test("the pack size is the description's part that agrees with the shop's unit price; a per-article 'zł/szt.' isn't a cross-check", () => {
    const at = (d: string, price: number, unit?: string) => sizeAndUnit(d, zl(Math.round(price * 100)), unit);
    assert.deepEqual(at("21 sztuk | 500 g", 15.95, "31,90 zł/kg"), { sizeText: "500 g", printedUnitPrice: "31,90 zł/kg" });
    assert.deepEqual(at("8 sztuk | 320 gramów", 3.39, "10,59 zł/kg"), { sizeText: "320 g", printedUnitPrice: "10,59 zł/kg" });
    assert.deepEqual(at("Rozmiar M | 2 sztuki", 14.95, "7,48 zł/szt."), { sizeText: "2 sztuki", printedUnitPrice: "7,48 zł/szt." });
    assert.deepEqual(at("18 x 18 gramów", 14.99, "46,27 zł/kg"), { sizeText: "18 x 18 g", printedUnitPrice: "46,27 zł/kg" });
    assert.deepEqual(at("4 x 30 ml", 24.99, "208,25 zł/l"), { sizeText: "4 x 30 ml", printedUnitPrice: "208,25 zł/l" });
    assert.deepEqual(at("1 litr", 3.48, "3,48 zł/l"), { sizeText: "1 l", printedUnitPrice: "3,48 zł/l" });
    assert.deepEqual(at(" 400 gramów", 5.49, "13,73 zł/kg"), { sizeText: "400 g", printedUnitPrice: "13,73 zł/kg" });
    assert.deepEqual(at("10 sztuk", 11.95, "60,35 zł/kg"), { sizeText: "10 sztuk" }, "priced per kg for a pack counted in pieces: no cross-check");
    assert.deepEqual(at("5 x 30 gramów", 7.99, "1,60 zł/szt."), { sizeText: "5 x 30 g" });
    assert.deepEqual(at("10 sztuk", 24.99, "24,99 zł/szt."), { sizeText: "10 sztuk" }, "the set of ten at 24,99 'per piece' is per article");
    assert.deepEqual(at("Ø 25 cm | 15 sztuk", 2.99, "0,25 zł/szt."), { sizeText: "15 sztuk", printedUnitPrice: "0,25 zł/szt." }, "the shop's two figures disagree: the service will say check");
    assert.deepEqual(at("39 cm | Różne kolory", 13.95, "13,95 zł/szt."), {}, "no pack size, so no unit price either");
    assert.deepEqual(at("Różne warianty", 3.49, "116,33 zł/l"), {});
    assert.deepEqual(at("240 x 135 cm", 4.25, "1,31 zł/m2"), {});
    assert.deepEqual(at("3 pary | Rozmiary 35-42", 10.95, "10,95 zł/szt."), {});
    assert.deepEqual(at("200 lumenów | 3,4 W | 12 metrów", 12.49), {});
  });

  test("tiles that aren't this week's deal on a product page of the shop, in złoty at one price, are skipped; alcohol too", () => {
    const products = parseActionPage(page([
      tile({ id: "1", title: "Obcy adres", current: 10, href: "https://evil.example/pl-pl/p/1/x/" }),
      tile({ id: "2", title: "Nie produkt", current: 10, href: "https://www.action.com/pl-pl/promocja-tygodnia/" }),
      tile({ id: "3", title: "Bez promocji", current: 10, isDeal: false }),
      tile({ id: "4", title: "W euro", current: 10, currency: "EUR" }),
      tile({ id: "5", title: "Od ceny", current: 10, priceRange: { min: amount(10), max: amount(20) } }),
      { ...tile({ id: "6", title: "Bez ceny", current: 10 }), price: { currencyCode: "PLN", current: { amount: "dużo" } } },
      tile({ id: "7", title: "Wino czerwone półwytrawne", description: "750 ml", current: 19.99 }),
      tile({ id: "8", title: "Zeszłotygodniowy koc", current: 10, dates: "14.10 – 20.10" }),
      tile({ id: "9", title: "Kieliszki do wina", description: "4 sztuki", current: 19.95 }),
      tile({ id: "10", title: "Koc", current: 29.95, href: "https://www.action.com/pl-pl/p/10/koc/?utm=x#top" }),
      tile({ id: "10", title: "Koc", current: 29.95 }),
      tile({ id: "11", title: "Pianki", current: 4.95, stickers: [] }),
    ]), TODAY)!.products;
    assert.deepEqual(products.map((p) => p.name), ["Kieliszki do wina", "Koc", "Pianki"]);
    assert.equal(products[1]!.url, "https://www.action.com/pl-pl/p/10/koc/", "no query or fragment, and the same product once");
    assert.ok(!("validFrom" in products[2]!), "no deal sticker: no dates made up");
  });

  test("the payload is joined from its chunks; rows that aren't JSON are skipped; a page without it has no payload", () => {
    const tiny = parseActionPage(page(P1, { chunk: 37 }), TODAY)!;
    assert.equal(tiny.products.length, 4, "chunks cut every 37 characters, mid-row and mid-string");
    assert.ok(flightRows(page(P1)).length >= 6);
    assert.equal(parseActionPage("<html><body>Promocja tygodnia</body></html>", TODAY), undefined);
    assert.equal(parseActionPage('<script>self.__next_f.push([1,"0:not json\\n"])</script>', TODAY), undefined);
    const empty = parseActionPage(page([]), TODAY)!;
    assert.deepEqual(empty, { products: [], page: 1, pages: 1, items: 0, ids: [] });
    const counted = parseActionPage(page([...P1, tile({ id: "7", title: "Wino musujące", current: 19.99 })], { pages: 8, items: 169 }), TODAY)!;
    assert.deepEqual([counted.items, counted.ids.length, counted.products.length], [169, 5, 4], "a skipped tile still counts as seen");
  });

  test("the deal's dates, in the year nearest today", () => {
    assert.deepEqual(dealDates([DEAL("28.10 – 03.11")], TODAY), { validFrom: "2026-10-28", validTo: "2026-11-03" });
    assert.deepEqual(dealDates([DEAL("29.12-04.01")], "2026-12-30"), { validFrom: "2026-12-29", validTo: "2027-01-04" });
    assert.deepEqual(dealDates([DEAL("29.12 – 04.01")], "2027-01-02"), { validFrom: "2026-12-29", validTo: "2027-01-04" });
    assert.deepEqual(dealDates([NEW], TODAY), {});
    assert.deepEqual(dealDates([DEAL("03.11 – 28.10")], TODAY), {}, "an end before the start is no date");
    assert.deepEqual(dealDates([DEAL("Tylko w tym tygodniu")], TODAY), {});
  });

  test("mechanics in the discount or a sticker are conditions; a plain percentage, the dates and 'new' are not", () => {
    assert.deepEqual(actionConditions("-25%", [DEAL("28.10 – 03.11"), NEW]), []);
    assert.deepEqual(actionConditions("1+1 gratis", []), [{ kind: "multi_buy", text: "1+1" }]);
    assert.deepEqual(actionConditions("-20% przy zakupie 2 szt.", []), [{ kind: "min_quantity", quantity: 2 }]);
    assert.deepEqual(actionConditions("2 za 10 zł", []), [{ kind: "other", text: "2 za 10 zł" }], "a mechanic the code can't price is kept in the shop's words");
    assert.deepEqual(actionConditions("-30%", [{ code: "IS_APP_DEAL", value: "Tylko w aplikacji", valueAddition: null, subValue: null }]), [{ kind: "app" }]);
    assert.deepEqual(actionConditions("-30%", [{ code: "X", value: "W wybranych sklepach", subValue: "Do wyczerpania zapasów" }]), [{ kind: "selected_stores" }, { kind: "stock" }]);
    const p = parseActionPage(page([tile({ id: "1", title: "Świeczki", current: 5, percentage: "2+1" })]), TODAY)!.products[0]!;
    assert.deepEqual(p.conditions, [{ kind: "multi_buy", text: "2+1" }]);
  });
});

// ---------- the adapter ----------

describe("Action: reading the shop", () => {
  test("robots.txt, the first page, then the others; one leaflet of the shop's data from the earliest to the latest date", async () => {
    const web = shopWeb();
    const l = ok(await action.read(ctx(web)));
    assert.deepEqual(l.leaflet, { title: "Promocja tygodnia Action", url: ACTION_PROMO, validFrom: "2026-10-28", validTo: "2026-11-03" });
    assert.equal(l.strategy, "none");
    assert.deepEqual(l.pages, []);
    assert.equal(l.incomplete, undefined, "all three pages read, as many products as the listing says");
    assert.equal(l.products.length, 8);
    assert.deepEqual(web.requests.slice(0, 2).map((r) => r.url), ["https://www.action.com/robots.txt", ACTION_PROMO]);
    assert.deepEqual(web.requests.slice(2).map((r) => r.url).sort(), [PAGE(2), PAGE(3)]);
    assert.ok(web.requests.every((r) => r.headers["user-agent"] === "DoddyBot/1.0 (+https://doddy.lol/bot)"));
    assert.deepEqual([...web.hosts()], ["www.action.com"]);
    assert.ok(web.requests.every((r) => !/ręcznik|r%C4%99cznik/i.test(r.url)), "nothing of the person's words reaches the shop");
  });

  test("a single page is one request; robots.txt's rules allow ?page=", async () => {
    const one = shopWeb({ 1: page(P1) });
    assert.equal(ok(await action.read(ctx(one))).products.length, 4);
    assert.equal(one.hits(ACTION_PROMO), 1);
    const disallowed = new FakeWeb().robots("https://www.action.com", "User-agent: *\nDisallow: /pl-pl/promocja-tygodnia/\n").on(ACTION_PROMO, { body: page(P1) });
    assert.equal((await action.read(ctx(disallowed))).kind, "blocked");
    assert.equal(disallowed.hits(ACTION_PROMO), 0, "a disallowed page is never asked for");
  });

  test("a block is blocked and never worked around; after a block nothing more is asked; one page failing makes the read incomplete", async () => {
    const blocked = shopWeb({}).on(ACTION_PROMO, { status: 403 });
    assert.deepEqual(await action.read(ctx(blocked)), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(blocked.hits(ACTION_PROMO), 1, "not retried");

    const later = shopWeb({ 1: page(P1, { pages: 4 }), 3: page(P3, { page: 3, pages: 4 }) })
      .on(PAGE(2), { status: 429 })
      .on(PAGE(3), async () => { await new Promise((r) => setTimeout(r, 30)); return { body: page(P3, { page: 3, pages: 4 }) }; });
    const l = ok(await action.read(ctx(later)));
    assert.equal(l.incomplete, "some_pages_failed");
    assert.equal(later.hits(PAGE(2)), 1);
    assert.equal(later.hits(PAGE(4)), 0, "the shop said no: page 4 isn't asked for");
    assert.equal(l.products.length, 6);

    const half = shopWeb({ 1: page(P1, { pages: 2 }) }).on(PAGE(2), { status: 500 });
    assert.equal(ok(await action.read(ctx(half))).incomplete, "some_pages_failed");
  });

  test("more pages than the cap: the cap is read and the read says so; a page that answers as another isn't counted", async () => {
    const many = ACTION_MAX_PAGES + 2;
    const pages: Record<number, string> = {};
    for (let n = 1; n <= many; n++) pages[n] = page([tile({ id: String(100 + n), title: `Koc ${n}`, current: 10 + n })], { page: n, pages: many });
    const web = shopWeb(pages);
    const l = ok(await action.read(ctx(web)));
    assert.equal(l.products.length, ACTION_MAX_PAGES);
    assert.equal(l.incomplete, "pages_capped");
    assert.equal(web.hits(PAGE(ACTION_MAX_PAGES + 1)), 0);

    const same = shopWeb({ 1: page(P1, { pages: 2 }), 2: page(P1, { page: 1, pages: 2 }) });
    assert.equal(ok(await action.read(ctx(same))).incomplete, "some_pages_failed");
  });

  test("pages from different moments: a product on two pages is one product, and fewer than the listing's count is incomplete", async () => {
    // As seen live on 30 Oct (168 of 169): the shop's cache served the pages at different ages.
    const shifted = shopWeb({ 1: page(P1, { pages: 2, items: 6 }), 2: page([P1[3]!, P2[0]!], { page: 2, pages: 2, items: 6 }) });
    const l = ok(await action.read(ctx(shifted)));
    assert.equal(l.products.length, 5);
    assert.equal(l.products.filter((p) => p.name === "Choinka z filcu").length, 1);
    assert.equal(l.incomplete, "listing_changed", "one product was on neither page: 'nothing matched' can't be claimed");
  });

  test("no payload is failed; an empty listing or only last week's deals is no leaflet", async () => {
    assert.deepEqual(await action.read(ctx(shopWeb({ 1: "<html><body>Promocja tygodnia</body></html>" }))), { kind: "failed", reason: "no_payload" });
    assert.deepEqual(await action.read(ctx(shopWeb({ 1: page([]) }))), { kind: "no_leaflet" });
    const old = page([tile({ id: "1", title: "Koc", current: 10, dates: "14.10 – 20.10" })]);
    assert.deepEqual(await action.read(ctx(shopWeb({ 1: old }))), { kind: "no_leaflet" });
    const gone = shopWeb({}).on(ACTION_PROMO, { status: 404 });
    assert.deepEqual(await action.read(ctx(gone)), { kind: "failed", reason: "http_404" });
  });
});
