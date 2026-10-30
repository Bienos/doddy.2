// Maxi Zoo's promotions pages, against SYNTHETIC pages built here in the shape www.maxizoo.pl served on 2026-10-30
// (a Nuxt page whose __NUXT_DATA__ holds pinia.main.productListingData.productList). Names, codes and prices are
// made up; no copy of the shop's page is kept. Nothing reaches the network.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { animalPages, badgeConditions, MAXIZOO_PAGES, maxizoo, packSize, parseMaxiZooPage } from "../src/deals/chains/maxizoo.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext, ChainRead, LeafletRead } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const DOG = "https://www.maxizoo.pl/c/pies/promocje/";
const CAT = "https://www.maxizoo.pl/c/kot/promocje/";
const SMALL = "https://www.maxizoo.pl/c/male-zwierzeta/promocje/";
// The rules that matter here, as the shop's robots.txt wrote them on 2026-10-30.
const ROBOTS = "User-agent: *\nAllow: /api/proxy/v1/*\nDisallow: */cart/\nDisallow: /s/\nDisallow: */search\nDisallow: *sort=*\nDisallow: /*?q=%3AtopSeller\n";

// ---------- a synthetic page in the shop's shape ----------

/** A Nuxt wrapper ("ShallowReactive", "Reactive") around a value, as devalue writes it. */
class Wrap { constructor(readonly type: string, readonly value: unknown) {} }

/** devalue's flat array: entry 0 is the root, objects and arrays hold indices of other entries. */
function flatten(value: unknown): unknown[] {
  const flat: unknown[] = [];
  const add = (v: unknown): number => {
    if (v === undefined) return -1;
    const i = flat.length;
    flat.push(null);
    if (v instanceof Wrap) flat[i] = [v.type, add(v.value)];
    else if (Array.isArray(v)) flat[i] = v.map(add);
    else if (v !== null && typeof v === "object") flat[i] = Object.fromEntries(Object.entries(v).map(([k, x]) => [k, add(x)]));
    else flat[i] = v;
    return i;
  };
  add(value);
  return flat;
}

const price = (value: number) => ({ value, formattedValue: `${value.toFixed(2).replace(".", ",")} zł`, priceType: "BUY", currencyIso: "PLN" });

interface TileInput {
  brand?: string; name: string; code: string; current: number; former?: number; perUnit?: string;
  badges?: { type: string; name: string }[]; ean?: string; url?: string; sponsored?: boolean;
}
function tile(t: TileInput): Record<string, unknown> {
  const slug = `${t.brand ?? ""} ${t.name}`.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return {
    tileType: "ProductTile", image: { url: "https://media.example/p.jpg" }, sponsored: t.sponsored ?? false,
    ...(t.ean ? { analytics: { categoryNames: ["Pies", "Karma dla psów"], marketplaceArticle: false, ean: t.ean } } : {}),
    badges: t.badges ?? [{ type: "discount", name: "Specjalna oferta" }],
    brandName: t.brand, code: t.code, name: t.name,
    pricing: {
      current: price(t.current),
      ...(t.former ? { former: price(t.former), savings: price(Math.round((t.former - t.current) * 100) / 100) } : {}),
      savingsRelative: { value: 30, formattedValue: "-30%" },
      ...(t.perUnit ? { perUnit: { value: 1, formattedValue: t.perUnit, priceType: "BUY", currencyIso: "PLN" } } : {}),
    },
    stock: { stockLevelStatus: "inStock" }, totalAvgRating: 0, totalNumberOfReviews: 0,
    url: t.url ?? `/p/${slug}-${t.code}/`, variantAttributeMetas: [],
  };
}
const teaser = { tileType: "TeaserTile", image: { url: "https://media.example/t.png" }, sponsored: false, badges: [], headline: "Zapisuję się!", ctaButton: { title: "Zapisuję się!", url: "/newsletter/" } };

/** A promotions page: the listing's tiles and pages, inside the rest of a Nuxt payload. */
function page(tiles: unknown[], totalPages = 1): string {
  const productList = {
    breadcrumbs: [], facets: [], freeTextSearch: "", products: tiles,
    pagination: { currentPage: 0, pageSize: 48, totalPages, totalResults: Math.max(tiles.length, (totalPages - 1) * 48 + 1) },
    sorts: [{ name: "Największy rabat", code: "savingsRelative", selected: true }],
  };
  const root = new Wrap("ShallowReactive", {
    data: new Wrap("ShallowReactive", { "buy-again-ids": [] }), state: {}, once: [], _errors: {}, serverRendered: true,
    pinia: new Wrap("Reactive", { main: { baseStore: "maxizooPL", hostname: "www.maxizoo.pl", pageTemplate: "product-listing", productListingData: { productList, error: null } }, cart: {} }),
  });
  // Nuxt escapes "/" in its JSON; the tile shows the price, the unit price and the former price struck through.
  const json = JSON.stringify(flatten(root)).replace(/\//g, "\\u002F");
  return `<!DOCTYPE html><html lang="pl"><head><title>Promocje % | MAXI ZOO</title></head><body><div id="__nuxt">`
    + `<div class="pt-price-current">289,38 zł</div><div class="pt-price-former--strike pt-price-former">413,40 zł</div></div>`
    + `<script type="application/json" data-nuxt-data="nuxt-app" data-ssr="true" id="__NUXT_DATA__">${json}</script></body></html>`;
}

const DOG_TILES = [
  tile({ brand: "Psotka", name: "Prime Adult Kurczak 12 kg", code: "1000001", current: 289.38, former: 413.4, perUnit: "24,12 zł/kg", ean: "5900000000017" }),
  teaser,
  tile({ brand: "Psotka", name: "Professional Adult Maxi >25 kg z drobiem 12 kg", code: "1000002", current: 130.34, former: 186.2, perUnit: "10,86 zł/kg" }),
  tile({ brand: "Kłapouch", name: "Smycz odblaskowa M", code: "1000003", current: 48.99, former: 69.99 }),
  tile({ brand: "Fontanna & Co", name: "Poidełko fontanna 1,8 l", code: "1000004", current: 142.59, former: 203.7 }),
];
const CAT_TILES = [
  tile({ brand: "Fontanna & Co", name: "Poidełko fontanna 1,8 l", code: "1000004", current: 142.59, former: 203.7 }),
  tile({ brand: "Mruczek's", name: "Mruczek’s Kitten z indykiem 800 g", code: "2000001", current: 20.86, former: 29.8, perUnit: "26,08 zł/kg" }),
  tile({ brand: "Mruczek's", name: "Sensations w galarecie 24 x 85 g", code: "2000002", current: 34.99, former: 42.8, perUnit: "17,15 zł/kg", badges: [{ type: "Multipacks", name: "Opakowania zbiorcze" }, { type: "discount", name: "Specjalna oferta" }] }),
];
const SMALL_TILES = [
  tile({ brand: "Chrupek", name: "Krakersy dla chomików 2x4 szt", code: "3000001", current: 27.86, former: 39.8, perUnit: "34,40 zł/kg", badges: [{ type: "exclusive", name: "Wyłącznie" }, { type: "discount", name: "Specjalna oferta" }] }),
];

function shopWeb(pages: Partial<Record<string, string>> = { [DOG]: page(DOG_TILES, 7), [CAT]: page(CAT_TILES, 1), [SMALL]: page(SMALL_TILES, 1) }): FakeWeb {
  const web = new FakeWeb().robots("https://www.maxizoo.pl", ROBOTS);
  for (const [url, body] of Object.entries(pages)) if (body !== undefined) web.on(url, { headers: { "content-type": "text/html;charset=utf-8" }, body });
  return web;
}
const ctx = (web: FakeWeb, queries: string[]): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: web.fetch }), queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead & { incomplete?: string } => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? { ...r.leaflets[0]!, ...(r.incomplete ? { incomplete: r.incomplete } : {}) } : (undefined as never);
};

// ---------- the parser ----------

describe("Maxi Zoo: a promotions page's own data", () => {
  test("each tile as a product: brand and name, price, the struck-through price as the regular price, size, unit price, page", () => {
    const listing = parseMaxiZooPage(page(DOG_TILES, 7))!;
    assert.equal(listing.totalPages, 7);
    assert.equal(listing.products.length, 4, "the teaser tile isn't a product");
    assert.deepEqual(listing.products[0], {
      name: "Psotka Prime Adult Kurczak 12 kg", price: { minor: 28938, currency: "PLN" },
      url: "https://www.maxizoo.pl/p/psotka-prime-adult-kurczak-12-kg-1000001/", conditions: [],
      sizeText: "12 kg", printedUnitPrice: "24,12 zł/kg", regularPrice: { minor: 41340, currency: "PLN" }, ean: "5900000000017", matchText: "Pies Karma dla psów",
    });
    const maxi = listing.products[1]!;
    assert.equal(maxi.sizeText, "12 kg", "'>25 kg' is the dog's weight; the pack is the last size in the name");
    assert.equal(listing.products[2]!.sizeText, undefined, "no size in the name, none made up");
    assert.equal(listing.products[2]!.printedUnitPrice, undefined);
  });

  test("the former price is a regular price, never the 30-day lowest: the page doesn't say it is", () => {
    const products = parseMaxiZooPage(page([...DOG_TILES, ...CAT_TILES]))!.products;
    assert.ok(products.every((p) => p.lowest30d === undefined));
    assert.ok(products.every((p) => p.regularPrice && p.regularPrice.minor > p.price.minor));
    const same = parseMaxiZooPage(page([tile({ brand: "B", name: "Gryzak 1 szt.", code: "9", current: 10, former: 10 })]))!.products[0]!;
    assert.equal(same.regularPrice, undefined, "a former price not above the price isn't kept");
    assert.ok(!("validTo" in same) && !("validFrom" in same), "the page shows no dates, so none are given");
  });

  test("the brand isn't written twice; a unit price in another unit than the size is left out", () => {
    const [, kitten, multipack] = parseMaxiZooPage(page(CAT_TILES))!.products;
    assert.equal(kitten!.name, "Mruczek’s Kitten z indykiem 800 g");
    assert.equal(multipack!.name, "Mruczek's Sensations w galarecie 24 x 85 g");
    assert.equal(multipack!.sizeText, "24 x 85 g");
    assert.equal(multipack!.printedUnitPrice, "17,15 zł/kg");
    assert.deepEqual(multipack!.conditions, [], "'Opakowania zbiorcze' is a multipack, not a mechanic");
    const crackers = parseMaxiZooPage(page(SMALL_TILES))!.products[0]!;
    assert.equal(crackers.sizeText, "2x4 szt");
    assert.equal(crackers.printedUnitPrice, undefined, "priced per kg for a pack counted in pieces: no cross-check possible");
    assert.deepEqual(crackers.conditions, [], "'Wyłącznie' (only at Maxi Zoo) is no condition");
  });

  test("pack sizes as the shop writes them in names", () => {
    assert.equal(packSize("Szczenię 12 x 200 g Wołowina z jabłkami 12x200 g"), "12x200 g");
    assert.equal(packSize("HFC Natural Light Meal 4 x 50 g Tuńczyk i kurczak:"), "4 x 50 g");
    assert.equal(packSize("Ocean Mini Adult Dorsz: 7 kg"), "7 kg");
    assert.equal(packSize("ściółka dla małych zwierząt 60 l"), "60 l");
    assert.equal(packSize("Barf 2 Go, Dorosły, Menu z wołowiną 500 g"), "500 g", "'2 Go' is no size");
    assert.equal(packSize("Smycz czarna 20 mm / 100 cm"), undefined);
    assert.equal(packSize("Kräcker dla chomików 3 x 2 sztuki"), "3 x 2 sztuki");
  });

  test("tiles that aren't a product on the shop's host with a price are skipped", () => {
    const products = parseMaxiZooPage(page([
      tile({ brand: "A", name: "Obcy adres 1 kg", code: "1", current: 10, former: 12, url: "https://evil.example/p/x-1/" }),
      tile({ brand: "A", name: "Nie produkt 1 kg", code: "2", current: 10, former: 12, url: "/c/pies/" }),
      tile({ brand: "A", name: "Sponsorowany 1 kg", code: "3", current: 10, former: 12, sponsored: true }),
      { ...tile({ brand: "A", name: "Bez ceny 1 kg", code: "4", current: 10 }), pricing: { current: { value: "dużo" } } },
      { ...tile({ brand: "A", name: "W euro 1 kg", code: "5", current: 10 }), pricing: { current: { ...price(10), currencyIso: "EUR" } } },
      tile({ brand: "A", name: "Dobry 1 kg", code: "6", current: 10, former: 12, url: "https://www.maxizoo.pl/p/dobry-6/?utm=x#top" }),
    ]))!.products;
    assert.deepEqual(products.map((p) => p.url), ["https://www.maxizoo.pl/p/dobry-6/"]);
    assert.equal(parseMaxiZooPage("<html><body>Strona nie została znaleziona</body></html>"), undefined);
    assert.equal(parseMaxiZooPage('<script id="__NUXT_DATA__">not json</script>'), undefined);
  });

  test("a badge naming a mechanic is a condition: multi-buy, minimum quantity, the app, the Friends card", () => {
    assert.deepEqual(badgeConditions([{ type: "discount", name: "Specjalna oferta" }, { type: "exclusive", name: "Wyłącznie" }]), []);
    assert.deepEqual(badgeConditions([{ type: "deal", name: "2+1 gratis" }]), [{ kind: "multi_buy", text: "2+1" }]);
    assert.deepEqual(badgeConditions([{ type: "deal", name: "-20% przy zakupie 3 szt." }]), [{ kind: "min_quantity", quantity: 3 }]);
    assert.deepEqual(badgeConditions([{ type: "app", name: "Cena w aplikacji" }, { type: "loyalty", name: "Cena Friends" }]), [{ kind: "app" }, { kind: "card" }]);
    const p = parseMaxiZooPage(page([tile({ brand: "A", name: "Przysmak 100 g", code: "7", current: 5, former: 7, badges: [{ type: "deal", name: "1+1" }] })]))!.products[0]!;
    assert.deepEqual(p.conditions, [{ kind: "multi_buy", text: "1+1" }]);
  });
});

// ---------- which pages ----------

describe("Maxi Zoo: the animal pages an item picks", () => {
  test("the animal the item names; dog and cat when it names none; at most four pages", () => {
    assert.deepEqual(animalPages(["karma dla psa"]), [DOG]);
    assert.deepEqual(animalPages(["Karma sucha dla psów"]), [DOG]);
    assert.deepEqual(animalPages(["przysmaki dla szczeniaka"]), [DOG]);
    assert.deepEqual(animalPages(["żwirek dla kota"]), [CAT]);
    assert.deepEqual(animalPages(["karma dla kociąt"]), [CAT]);
    assert.deepEqual(animalPages(["siano dla gryzoni"]), [SMALL]);
    assert.deepEqual(animalPages(["karma dla chomika"]), [SMALL]);
    assert.deepEqual(animalPages(["Świnka morska karma"]), [SMALL]);
    assert.deepEqual(animalPages(["smycz"]), [DOG, CAT]);
    assert.deepEqual(animalPages(["karma dla kota", "smycz"]), [DOG, CAT], "an item naming no animal adds dog and cat");
    assert.deepEqual(animalPages(["karma dla psa", "żwirek dla kota", "siano dla królika"]), [DOG, CAT, SMALL]);
    assert.ok(MAXIZOO_PAGES.length <= 4);
  });

  test("birds and fish have no promotions page, so they read none; a flavour isn't an animal", () => {
    assert.deepEqual(animalPages(["pokarm dla ryb"]), []);
    assert.deepEqual(animalPages(["ziarno dla papugi"]), []);
    assert.deepEqual(animalPages(["karma dla ptaków"]), []);
    assert.deepEqual(animalPages(["karma z rybą dla kota"]), [CAT]);
    assert.deepEqual(animalPages(["karma z rybą"]), [DOG, CAT], "'z rybą' is what's in it, not the fish it's for");
    assert.deepEqual(animalPages(["kotlet"]), [DOG, CAT], "no cat in 'kotlet'");
  });
});

// ---------- the adapter ----------

describe("Maxi Zoo: reading the shop", () => {
  test("one page for a dog item: robots.txt and that page only, a listing with more pages says so", async () => {
    const web = shopWeb();
    const l = ok(await maxizoo.read(ctx(web, ["karma dla psa"])));
    assert.deepEqual(l.leaflet, { title: "Promocje Maxi Zoo", url: DOG });
    assert.equal(l.strategy, "none");
    assert.deepEqual(l.pages, []);
    assert.equal(l.products.length, 4);
    assert.equal(l.incomplete, "first_page_only", "only the first of seven pages was read: 'nothing matched' can't be claimed");
    assert.deepEqual(web.requests.map((r) => r.url), ["https://www.maxizoo.pl/robots.txt", DOG]);
    assert.equal(web.requests[1]!.headers["user-agent"], "DoddyBot/1.0 (+https://doddy.lol/bot)");
    assert.equal(web.hits(`${DOG}?currentPage=`), 0);
  });

  test("dog and cat by default; a product on both pages is one product; a single-page listing is complete", async () => {
    const web = shopWeb();
    const l = ok(await maxizoo.read(ctx(web, ["smycz"])));
    assert.equal(l.products.length, 6, "4 on the dog page, 3 on the cat page, the fountain on both");
    assert.equal(l.products.filter((p) => p.name.includes("fontanna")).length, 1);
    assert.equal(l.leaflet.url, DOG);
    assert.deepEqual([...web.hosts()], ["www.maxizoo.pl"]);
    const cat = ok(await maxizoo.read(ctx(shopWeb(), ["żwirek dla kota"])));
    assert.equal(cat.leaflet.url, CAT);
    assert.equal(cat.incomplete, undefined);
  });

  test("birds or fish only: no page, no request, no leaflet", async () => {
    const web = shopWeb();
    assert.deepEqual(await maxizoo.read(ctx(web, ["pokarm dla rybek"])), { kind: "no_leaflet" });
    assert.equal(web.requests.length, 0);
  });

  test("a block is blocked and never worked around; robots.txt that disallows the page means no request", async () => {
    const blocked = shopWeb({ [CAT]: undefined }).on(CAT, { status: 403 });
    assert.deepEqual(await maxizoo.read(ctx(blocked, ["żwirek dla kota"])), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(blocked.hits(CAT), 1, "not retried");
    assert.equal(blocked.hits("https://www.maxizoo.pl/c/kot/promocje/?"), 0);

    const both = shopWeb({}).on(DOG, { status: 429 }).on(CAT, { status: 429 });
    assert.equal((await maxizoo.read(ctx(both, ["smycz"]))).kind, "blocked");

    const disallowed = new FakeWeb().robots("https://www.maxizoo.pl", "User-agent: *\nDisallow: /c/\n").on(CAT, { body: page(CAT_TILES) });
    const r = await maxizoo.read(ctx(disallowed, ["żwirek dla kota"]));
    assert.equal(r.kind, "blocked");
    assert.equal(disallowed.hits(CAT), 0);
  });

  test("no data in the page is failed; an empty listing is no leaflet; one page failing makes the read incomplete", async () => {
    const bare = shopWeb({ [CAT]: "<html><body>Promocje</body></html>" });
    assert.deepEqual(await maxizoo.read(ctx(bare, ["żwirek dla kota"])), { kind: "failed", reason: "no_payload" });
    const empty = shopWeb({ [CAT]: page([teaser]) });
    assert.deepEqual(await maxizoo.read(ctx(empty, ["żwirek dla kota"])), { kind: "no_leaflet" });
    const half = shopWeb({ [DOG]: page(DOG_TILES, 1) }).on(CAT, { status: 500 });
    const l = ok(await maxizoo.read(ctx(half, ["smycz"])));
    assert.equal(l.products.length, 4);
    assert.equal(l.incomplete, "some_pages_failed");
    const gone = shopWeb({}).on(SMALL, { status: 404 });
    assert.deepEqual(await maxizoo.read(ctx(gone, ["siano dla królika"])), { kind: "failed", reason: "http_404" });
  });
});

describe("Maxi Zoo: the kind of product the name leaves out (ADR-667)", () => {
  test("the shop's category path and the page's animal are read by the matcher, never shown", () => {
    const withCategories = tile({ brand: "Farmina", name: "N&D Adult Kurczak 12 kg", code: "77", current: 289.38, former: 413.4, ean: "8010276030405" });
    const plain = tile({ brand: "Trixie", name: "Gryzak 1 szt.", code: "78", current: 10, former: 12 });
    const [food, toy] = parseMaxiZooPage(page([withCategories, plain]), "pies")!.products;
    assert.equal(food!.matchText, "Pies Karma dla psów dla psa");
    assert.equal(toy!.matchText, "dla psa", "no category path: the page's animal alone");
    assert.ok(!food!.name.includes("Karma"), "the name the person sees is the shop's own");
    assert.equal(parseMaxiZooPage(page([plain]))!.products[0]!.matchText, undefined, "no animal and no categories: nothing added");
  });
});
