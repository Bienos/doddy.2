// Shopping errands without a database (docs/implementation/SHOPPING.md): money parsing and
// formatting, reading a price from a shop page's structured data, the offer registry, the code rules
// on the result (prices only from the registry, unknown ids dropped, sentences with invented amounts
// dropped), and the runner against a fake model, a fake offer source and a fake fetcher. Nothing here
// calls Anthropic, Serper or a shop.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { contentDigest, contentJson, createBody, ErrandResultSchema } from "../src/errands/schema.js";
import type { ErrandResearcher, ErrandTask, ResearchControl, ResearchOutcome } from "../src/errands/researcher.js";
import { budgetBacked, buildShoppingResult, keepBackedSentences, type ShoppingCardOutput } from "../src/shopping/build.js";
import { amountFromData, formatMoney, moneyMentions, parseAmount, parseMoney } from "../src/shopping/money.js";
import { OfferRegistry, SerperOfferSource, type OfferSource, type RawOffer } from "../src/shopping/offers.js";
import { checkOfferPage, fromJsonLd, fromMicrodata, fromOpenGraph, type FetchOutcome, type PageFetcher } from "../src/shopping/pagecheck.js";
import {
  RoutingErrandResearcher, runShopping, ShoppingErrandResearcher,
  type ShoppingCardReply, type ShoppingMessage, type ShoppingModelApi, type ShoppingTurn,
} from "../src/shopping/runner.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = (name: string) => JSON.parse(readFileSync(path.resolve(here, "../../../../schemas/fixtures", name), "utf8"));
const NBSP = " ";
const T0 = new Date("2026-10-24T12:00:00.000Z");

describe("money", () => {
  test("parses the ways shops and Google Shopping write prices, in minor units", () => {
    const cases: Array<[string, number]> = [
      ["1 899,00 zł", 189900], [`1${NBSP}899,00${NBSP}zł`, 189900], ["1.899,00 zł", 189900], ["1899 zł", 189900],
      ["PLN 1,899.00", 189900], ["1 899 zł", 189900], ["4,99 zł", 499], ["12,5 zł", 1250], ["1.899 zł", 189900], ["0,99 zł", 99],
    ];
    for (const [text, minor] of cases) assert.equal(parseAmount(text), minor, text);
    assert.equal(parseAmount("od 1 899 do 2 099 zł"), undefined, "two amounts is not one price");
    assert.equal(parseAmount("bezpłatna"), undefined);
    assert.deepEqual(parseMoney("1 899,00 zł"), { minor: 189900, currency: "PLN" });
    assert.deepEqual(parseMoney("1 899,00", "PLN"), { minor: 189900, currency: "PLN" });
    assert.equal(parseMoney("1 899,00"), undefined, "no currency and no fallback");
  });

  test("structured-data numbers never go through floating point surprises", () => {
    assert.equal(amountFromData(1899), 189900);
    assert.equal(amountFromData(1899.99), 189999);
    assert.equal(amountFromData("1899.00"), 189900);
    assert.equal(amountFromData("1899,5"), 189950);
    assert.equal(amountFromData(0), undefined);
    assert.equal(amountFromData("-5"), undefined);
    assert.equal(amountFromData(0.1 + 0.2), 30);
  });

  test("formats Polish with no-break spaces and English with the code first", () => {
    assert.equal(formatMoney({ minor: 189900, currency: "PLN" }, "pl"), `1${NBSP}899,00${NBSP}zł`);
    assert.equal(formatMoney({ minor: 499, currency: "PLN" }, "pl"), `4,99${NBSP}zł`);
    assert.equal(formatMoney({ minor: 189900, currency: "PLN" }, "en"), "PLN 1,899.00");
    assert.equal(formatMoney({ minor: 123456789, currency: "EUR" }, "pl"), `1${NBSP}234${NBSP}567,89${NBSP}EUR`);
  });

  test("finds money amounts in prose, but not other numbers", () => {
    assert.deepEqual(moneyMentions("Kosztuje 1 899 zł, a montaż 149 zł."), [189900, 14900]);
    assert.deepEqual(moneyMentions("Ma 42 dB i 10 kompletów, szerokość 45 cm."), []);
    assert.deepEqual(moneyMentions("About PLN 1,899.00 today."), [189900]);
  });
});

const page = (ld: unknown, extra = "") =>
  `<html><head><script type="application/ld+json">${JSON.stringify(ld)}</script>${extra}</head><body>Cena 999 zł!</body></html>`;
const product = (offers: unknown, more: object = {}) => ({ "@context": "https://schema.org", "@type": "Product", name: "Zmywarka 45 cm", offers, ...more });

describe("reading a shop page's price", () => {
  test("reads one Offer from JSON-LD, with currency, availability, GTIN and seller", () => {
    const found = fromJsonLd(page(product({ "@type": "Offer", price: "1899.00", priceCurrency: "PLN", availability: "https://schema.org/InStock", seller: { "@type": "Organization", name: "Media Expert" } }, { gtin13: "5901234123457" })));
    assert.deepEqual(found, { name: "Zmywarka 45 cm", price: { minor: 189900, currency: "PLN" }, availability: "in_stock", gtin: "5901234123457", seller: "Media Expert", source: "json_ld" });
  });

  test("finds the Product inside @graph and nested offers", () => {
    const ld = { "@context": "https://schema.org", "@graph": [{ "@type": "WebPage" }, product([{ "@type": "Offer", price: 1449, priceCurrency: "pln" }])] };
    assert.equal(fromJsonLd(page(ld))?.price.minor, 144900);
    assert.equal(fromJsonLd(page(ld))?.price.currency, "PLN");
  });

  test("refuses ambiguity: several different prices, an aggregate of many sellers, no currency", () => {
    assert.equal(fromJsonLd(page(product([{ "@type": "Offer", price: 1899, priceCurrency: "PLN" }, { "@type": "Offer", price: 1999, priceCurrency: "PLN" }]))), undefined);
    assert.equal(fromJsonLd(page(product({ "@type": "AggregateOffer", lowPrice: 1449, highPrice: 2299, offerCount: 7, priceCurrency: "PLN" }))), undefined);
    assert.equal(fromJsonLd(page(product({ "@type": "AggregateOffer", lowPrice: 1449, offerCount: 1, priceCurrency: "PLN" })))?.price.minor, 144900);
    assert.equal(fromJsonLd(page(product({ "@type": "Offer", price: 1899 }))), undefined);
    assert.equal(fromJsonLd("<html><body>Cena: 1 899 zł</body></html>"), undefined, "prose is never read for a price");
  });

  test("falls back to microdata and Open Graph price tags when each is unambiguous", () => {
    assert.equal(fromMicrodata('<span itemprop="price" content="1899.00"></span><meta itemprop="priceCurrency" content="PLN">')?.price.minor, 189900);
    assert.equal(fromMicrodata('<span itemprop="price" content="1"></span><span itemprop="price" content="2"></span><meta itemprop="priceCurrency" content="PLN">'), undefined);
    assert.equal(fromOpenGraph('<meta property="product:price:amount" content="2299"><meta property="product:price:currency" content="PLN">')?.price.minor, 229900);
  });

  test("blocked, disallowed and non-https pages never produce a price", async () => {
    const f = (o: FetchOutcome): PageFetcher => ({ fetchPage: async () => o });
    assert.equal((await checkOfferPage("https://shop.example/p", f({ kind: "blocked", reason: "403" }))).kind, "blocked");
    assert.equal((await checkOfferPage("https://shop.example/p", f({ kind: "disallowed", reason: "robots.txt" }))).kind, "disallowed");
    assert.equal((await checkOfferPage("http://shop.example/p", f({ kind: "failed", reason: "x" }))).kind, "failed");
    const ok = await checkOfferPage("https://shop.example/p", f({ kind: "ok", status: 200, contentType: "text/html; charset=utf-8", body: Buffer.from(page(product({ "@type": "Offer", price: 1899, priceCurrency: "PLN" }))), finalUrl: "https://shop.example/p?x=1" }));
    assert.equal(ok.kind, "ok");
    if (ok.kind === "ok") assert.equal(ok.offer.finalUrl, "https://shop.example/p?x=1");
    const pdf = await checkOfferPage("https://shop.example/p.pdf", f({ kind: "ok", status: 200, contentType: "application/pdf", body: Buffer.from(""), finalUrl: "https://shop.example/p.pdf" }));
    assert.equal(pdf.kind, "not_html");
  });
});

describe("offer registry", () => {
  test("keeps listings only with a title, shop, readable price and link; ids in order; duplicates merged", () => {
    const r = new OfferRegistry();
    const good: RawOffer = { title: "Zmywarka 45 cm 42 dB", shop: "Media Expert", priceText: "1 899,00 zł", link: "https://www.google.com/shopping/product/1" };
    assert.equal(r.addListing(good, T0)?.id, "o1");
    assert.equal(r.addListing(good, T0)?.id, "o1", "the same listing again is the same offer");
    assert.equal(r.addListing({ ...good, priceText: undefined }, T0), undefined);
    assert.equal(r.addListing({ ...good, shop: undefined }, T0), undefined);
    assert.equal(r.addListing({ ...good, link: "javascript:alert(1)" }, T0), undefined);
    assert.equal(r.addListing({ ...good, priceText: "od 1 449 do 1 899 zł" }, T0), undefined);
    assert.equal(r.addListing({ ...good, shop: "x-kom", link: "https://www.google.com/shopping/product/2", priceText: "2 299 zł" }, T0)?.id, "o2");
    assert.equal(r.seen, 7);
    assert.equal(r.size, 2);
    assert.equal(r.shopCount, 2);
    assert.equal(r.get("o1")?.evidence, "listing");
  });

  test("a shop page upgrades the listing with the same address and keeps its id", () => {
    const r = new OfferRegistry();
    r.addListing({ title: "Zmywarka", shop: "Media Expert", priceText: "1 949 zł", link: "https://www.mediaexpert.pl/p/1" }, T0);
    const later = new Date(T0.getTime() + 60_000);
    const up = r.addShopPage({ price: { minor: 189900, currency: "PLN" }, finalUrl: "https://www.mediaexpert.pl/p/1", source: "json_ld", seller: "Media Expert" }, "https://www.mediaexpert.pl/p/1", later);
    assert.equal(up?.id, "o1");
    assert.equal(up?.evidence, "shop_page");
    assert.equal(up?.price.minor, 189900, "the page's price replaces the listing's");
    assert.equal(up?.seenAt, later.toISOString());
    const added = r.addShopPage({ name: "Zmywarka 39 dB", price: { minor: 229900, currency: "PLN" }, finalUrl: "https://www.x-kom.pl/p/9", source: "json_ld" }, "https://www.x-kom.pl/p/9", later);
    assert.equal(added?.id, "o2");
    assert.equal(added?.shop, "x-kom.pl", "with no seller name the site is the shop");
  });
});

const words = "Szukam cichej zmywarki do zabudowy, 45 cm, do 2000 zł";
const brief = "Zmywarka do zabudowy 45 cm, najciszej jak się da w budżecie do 2000 zł; sklepy w Polsce, z dostawą";
const content = { words, brief, language: "pl", priorities: ["Cisza", "Cena", "Gwarancja"] };

function sampleRegistry() {
  const r = new OfferRegistry();
  r.addListing({ title: "Zmywarka do zabudowy 45 cm, 42 dB, 10 kompletów", shop: "Media Expert", priceText: "1 899,00 zł", link: "https://www.mediaexpert.pl/p/45", delivery: "Dostawa jutro, 0 zł" }, T0);
  r.addShopPage({ price: { minor: 189900, currency: "PLN" }, finalUrl: "https://www.mediaexpert.pl/p/45", source: "json_ld", seller: "Media Expert", gtin: "5901234123457" }, "https://www.mediaexpert.pl/p/45", T0);
  r.addListing({ title: "Zmywarka do zabudowy 45 cm, 47 dB, 9 kompletów", shop: "RTV Euro AGD", priceText: "1 449,00 zł", link: "https://www.google.com/shopping/product/1234567890" }, T0);
  r.addShopPage({ name: "Zmywarka do zabudowy 45 cm, 39 dB, 10 kompletów", price: { minor: 229900, currency: "PLN" }, finalUrl: "https://www.x-kom.pl/p/przyklad-zmywarka-45", source: "json_ld", seller: "x-kom" }, "https://www.x-kom.pl/p/przyklad-zmywarka-45", T0);
  return r;
}

function sampleCard(over: Partial<ShoppingCardOutput> = {}): ShoppingCardOutput {
  return {
    picks: [
      { role: "best", offerId: "o1", why: "Najcichsza z ofert do 2000 zł.", tradeoff: "Montaż osobno." },
      { role: "cheapest", offerId: "o2", why: "Najtańsza, która pasuje do wnęki 45 cm.", tradeoff: "O 5 dB głośniejsza." },
      { role: "premium", offerId: "o3", why: "Najcichsza ze wszystkich.", tradeoff: null },
    ],
    offerNotes: [{ offerId: "o1", notes: "42 dB · 10 kompletów · klasa C" }, { offerId: "o2", notes: "47 dB · 9 kompletów · klasa E" }],
    budget: { amount: 2000 },
    recommendation: "Jeśli liczy się cisza, bierz pierwszą.",
    howChosen: ["Odsiałem za duże i oferty bez ceny.", "Ułożyłem po Twojej kolejności: cisza, cena, gwarancja."],
    watchOuts: ["Montaż nie jest w cenie."],
    unknowns: ["Czy cena utrzyma się po niedzieli."],
    rejected: ["1 oferta 60 cm: nie zmieści się we wnęce 45 cm."],
    next: ["Sprawdzić montaż?", "Pilnować ceny?"],
    ...over,
  };
}

describe("the shopping result's code rules", () => {
  test("prices, shops, links and times come from the registry; the result fits the contract", () => {
    const built = buildShoppingResult(sampleCard(), sampleRegistry(), content, T0);
    assert.ok(built);
    const { result } = built;
    assert.ok(ErrandResultSchema.safeParse(result).success);
    const s = result.shopping!;
    assert.deepEqual(s.picks.map((p) => [p.role, p.offerId]), [["best", "o1"], ["cheapest", "o2"], ["premium", "o3"]]);
    assert.deepEqual(s.offers.find((o) => o.id === "o1")?.price, { minor: 189900, currency: "PLN" });
    assert.equal(s.offers.find((o) => o.id === "o1")?.evidence, "shop_page");
    assert.equal(s.offers.find((o) => o.id === "o2")?.evidence, "listing");
    assert.deepEqual(s.budget, { minor: 200000, currency: "PLN" });
    assert.deepEqual(s.picks[2]?.overBudget, { minor: 29900, currency: "PLN" }, "over budget is computed by the code");
    assert.equal(s.picks[0]?.overBudget, undefined);
    assert.deepEqual(s.priorities, ["Cisza", "Cena", "Gwarancja"]);
    assert.equal(result.answer, `Mój wybór: Zmywarka do zabudowy 45 cm, 42 dB, 10 kompletów, 1${NBSP}899,00${NBSP}zł w Media Expert. Najcichsza z ofert do 2000 zł.`);
    assert.equal(result.sections[0]?.items[0]?.price, `1${NBSP}899,00${NBSP}zł`);
    assert.match(result.sections[0]?.items[1]?.detail ?? "", /Cena z listy Google Shopping/u);
    assert.match(result.sections[0]?.items[2]?.detail ?? "", /299,00.zł ponad budżet/u);
    assert.deepEqual(result.budget, { asked: `do 2${NBSP}000,00${NBSP}zł`, within: "yes" });
    assert.equal(result.sources.length, 3);
    assert.equal(s.stats.shops, 3);
  });

  test("the generic fields' shape matches the shared fixture's", () => {
    const fx = fixture("errand_result_shopping_v1.json");
    assert.ok(ErrandResultSchema.safeParse(fx).success, "the fixture itself fits the server's schema");
  });

  test("an unknown id, a second best and a duplicate offer are dropped; no best fails", () => {
    const built = buildShoppingResult(sampleCard({
      picks: [
        { role: "best", offerId: "o9", why: "x", tradeoff: null },
        { role: "best", offerId: "o1", why: "Cicha.", tradeoff: null },
        { role: "best", offerId: "o2", why: "y", tradeoff: null },
        { role: "alternative", offerId: "o1", why: "z", tradeoff: null },
      ],
    }), sampleRegistry(), content, T0);
    assert.deepEqual(built?.result.shopping?.picks.map((p) => p.offerId), ["o1"]);
    assert.equal(built?.stats.droppedPicks, 3);
    assert.equal(buildShoppingResult(sampleCard({ picks: [{ role: "cheapest", offerId: "o2", why: "x", tradeoff: null }] }), sampleRegistry(), content, T0), undefined);
    assert.equal(buildShoppingResult(sampleCard({ picks: [{ role: "best", offerId: "o99", why: "x", tradeoff: null }] }), sampleRegistry(), content, T0), undefined);
  });

  test("'cheapest' must be true among the picks, or it becomes 'alternative'", () => {
    const built = buildShoppingResult(sampleCard({
      picks: [{ role: "best", offerId: "o2", why: "Tania.", tradeoff: null }, { role: "cheapest", offerId: "o1", why: "Też.", tradeoff: null }],
    }), sampleRegistry(), content, T0);
    assert.deepEqual(built?.result.shopping?.picks.map((p) => p.role), ["best", "alternative"]);
    assert.equal(built?.stats.relabelled, 1);
  });

  test("a sentence stating an amount the code can't back is dropped; prices and computed differences stay", () => {
    const built = buildShoppingResult(sampleCard({
      picks: [
        { role: "best", offerId: "o1", why: "Kosztuje 1 899 zł i jest cicha. Za montaż zapłacisz 99 zł.", tradeoff: "O 450 zł droższa od najtańszej." },
        { role: "cheapest", offerId: "o2", why: "Tylko 1 299 zł.", tradeoff: null },
      ],
      watchOuts: ["Montaż kosztuje 149 zł.", "Sprawdź wymiary wnęki."],
      recommendation: "Bierz pierwszą. Dziś jest za 1 799 zł.",
    }), sampleRegistry(), content, T0);
    const s = built!.result.shopping!;
    assert.equal(s.picks[0]?.why, "Kosztuje 1 899 zł i jest cicha.", "the invented 99 zł sentence is gone");
    assert.equal(s.picks[0]?.tradeoff, "O 450 zł droższa od najtańszej.", "a difference between two offers is computable");
    assert.equal(s.picks[1]?.why, "Najtańsza", "a why left empty falls back to the role's label");
    assert.deepEqual(s.watchOuts, ["Sprawdź wymiary wnęki."]);
    assert.equal(built!.result.recommendation, "Bierz pierwszą.");
    assert.ok(built!.stats.droppedSentences >= 4);
  });

  test("a budget the person never gave is not used", () => {
    assert.equal(budgetBacked(200000, words, brief), true);
    assert.equal(budgetBacked(200000, "do 2 tys. zł", ""), true);
    assert.equal(budgetBacked(250000, words, brief), false);
    const built = buildShoppingResult(sampleCard({ budget: { amount: 1500 } }), sampleRegistry(), content, T0);
    assert.equal(built?.result.shopping?.budget, undefined);
    assert.equal(built?.result.budget, undefined);
    assert.equal(built?.result.shopping?.picks.find((p) => p.role === "premium")?.overBudget, undefined);
  });

  test("keepBackedSentences keeps sentences without money as they are", () => {
    let dropped = 0;
    assert.equal(keepBackedSentences("Ma 42 dB. Kosztuje 5 zł.", new Set([100]), () => dropped++), "Ma 42 dB.");
    assert.equal(dropped, 1);
  });
});

describe("the shopping errand's request and digest", () => {
  test("kind and priorities: allowed only together, bounded, no duplicates", () => {
    const base = { words, brief, title: "Cicha zmywarka 45 cm", language: "pl" };
    assert.ok(createBody.safeParse({ ...base, kind: "shopping", priorities: ["Cisza", "Cena"] }).success);
    assert.ok(createBody.safeParse({ ...base, kind: "shopping", priorities: [] }).success);
    for (const bad of [
      { ...base, kind: "shopping" },
      { ...base, priorities: ["Cisza"] },
      { ...base, kind: "research", priorities: [] },
      { ...base, kind: "shopping", priorities: ["Cisza", "cisza"] },
      { ...base, kind: "shopping", priorities: [" Cisza"] },
      { ...base, kind: "shopping", priorities: ["x".repeat(41)] },
      { ...base, kind: "shopping", priorities: ["a", "b", "c", "d", "e", "f"] },
    ]) assert.equal(createBody.safeParse(bad).success, false, JSON.stringify(bad).slice(-80));
  });

  test("the digest matches the shared fixture, and a research errand's digest is unchanged", () => {
    const fx = fixture("errand_create_shopping_v1.json");
    const c = createBody.parse(fx.request);
    assert.equal(contentJson(c), fx.canonical);
    assert.equal(contentDigest(c).toString("hex"), fx.digest);
    const research = createBody.parse({ words: c.words, brief: c.brief, title: c.title, language: c.language });
    assert.equal(contentDigest(research).toString("hex"), fx.researchDigestOfSameWords);
    assert.equal(createHash("sha256").update(fx.canonical, "utf8").digest("hex"), fx.digest);
  });
});

// ---------- the runner ----------

type Script = Array<(messages: ShoppingTurn[]) => ShoppingMessage>;
class FakeShoppingApi implements ShoppingModelApi {
  readonly model = "claude-sonnet-5-5";
  calls: ShoppingTurn[][] = [];
  cardInputs: string[] = [];
  constructor(public script: Script, public cardReply: ShoppingCardReply) {}
  async research(messages: ShoppingTurn[]): Promise<ShoppingMessage> {
    this.calls.push(structuredClone(messages));
    const step = this.script.shift();
    if (!step) throw new Error("script ran out");
    return step(messages);
  }
  async card(input: string): Promise<ShoppingCardReply> {
    this.cardInputs.push(input);
    return this.cardReply;
  }
}

const usage = { input_tokens: 1000, output_tokens: 200 };
const toolUse = (id: string, name: string, input: object) => ({ type: "tool_use", id, name, input });
const fakeSource = (offers: RawOffer[] | "not_set_up"): OfferSource & { queries: string[] } => {
  const queries: string[] = [];
  return {
    name: "fake", queries,
    async search(q: string) {
      queries.push(q);
      return offers === "not_set_up" ? { kind: "not_set_up", reason: "no key" } : { kind: "ok", offers };
    },
  };
};
const fakeFetcher = (pages: Record<string, FetchOutcome>): PageFetcher & { urls: string[] } => {
  const urls: string[] = [];
  return { urls, async fetchPage(url: string) { urls.push(url); return pages[url] ?? { kind: "blocked", reason: "403" }; } };
};
const html = (price: number) => ({ kind: "ok" as const, status: 200, contentType: "text/html", finalUrl: "https://www.mediaexpert.pl/p/45",
  body: Buffer.from(page(product({ "@type": "Offer", price, priceCurrency: "PLN", seller: { name: "Media Expert" } }))) });
const control = (over: Partial<ResearchControl> = {}): ResearchControl => ({ deadline: new Date(Date.now() + 60_000), isCancelled: async () => false, now: () => T0, ...over });
const task: ErrandTask = { id: "e1", words, brief, language: "pl", kind: "shopping", priorities: ["Cisza", "Cena", "Gwarancja"] };

describe("the shopping runner", () => {
  test("offers come from the code's tools; the card's ids become the result; counts include the code's look-ups", async () => {
    const source = fakeSource([
      { title: "Zmywarka 45 cm 42 dB", shop: "Media Expert", priceText: "1 949,00 zł", link: "https://www.mediaexpert.pl/p/45" },
      { title: "Zmywarka 45 cm 47 dB", shop: "RTV Euro AGD", priceText: "1 449,00 zł", link: "https://www.google.com/shopping/product/1" },
    ]);
    const fetcher = fakeFetcher({ "https://www.mediaexpert.pl/p/45": html(1899) });
    const api = new FakeShoppingApi([
      () => ({ content: [{ type: "text", text: "Szukam." }, toolUse("t1", "find_offers", { query: "zmywarka do zabudowy 45 cm cicha" })], stop_reason: "tool_use", usage }),
      () => ({ content: [toolUse("t2", "check_offer_page", { url: "https://www.mediaexpert.pl/p/45" }), toolUse("t3", "check_offer_page", { url: "https://blocked.example/p" })], stop_reason: "tool_use", usage }),
      () => ({ content: [{ type: "text", text: "o1 najcichsza, o2 najtańsza." }], stop_reason: "end_turn", usage }),
    ], { kind: "ok", usage, card: sampleCard({ picks: [{ role: "best", offerId: "o1", why: "Najcichsza.", tradeoff: null }, { role: "cheapest", offerId: "o2", why: "Najtańsza.", tradeoff: null }] }) });
    const out = await runShopping(api, { offers: source, fetcher }, task, control());
    assert.equal(out.kind, "done");
    if (out.kind !== "done") return;
    const s = out.result.shopping!;
    assert.deepEqual(s.offers.find((o) => o.id === "o1")?.price, { minor: 189900, currency: "PLN" }, "the shop page's price, not the listing's");
    assert.equal(s.offers.find((o) => o.id === "o1")?.evidence, "shop_page");
    assert.equal(s.offers.find((o) => o.id === "o2")?.evidence, "listing");
    assert.deepEqual(source.queries, ["zmywarka do zabudowy 45 cm cicha"]);
    assert.deepEqual(fetcher.urls, ["https://www.mediaexpert.pl/p/45", "https://blocked.example/p"]);
    assert.equal(out.searches, 1, "one offer search");
    assert.equal(out.fetches, 2, "two page reads");
    // Tool results of one turn go back in one user message, with the blocked page as an error.
    const second = api.calls[2]!;
    const results = second[second.length - 1]!.content as unknown as Array<{ type: string; tool_use_id: string; is_error?: boolean; content: string }>;
    assert.deepEqual(results.map((r) => [r.tool_use_id, !!r.is_error]), [["t2", false], ["t3", true]]);
    assert.match(results[1]!.content, /blocked/u);
    // The card writer saw the registry with ids and the code's prices.
    const input = JSON.parse(api.cardInputs[0]!);
    assert.deepEqual(input.offers.map((o: { id: string }) => o.id), ["o1", "o2"]);
    assert.deepEqual(input.priorities, ["Cisza", "Cena", "Gwarancja"]);
  });

  test("without an offer source the model is told to use search and page checks; no offers fails", async () => {
    const api = new FakeShoppingApi([
      () => ({ content: [toolUse("t1", "find_offers", { query: "zmywarka" })], stop_reason: "tool_use", usage }),
      () => ({ content: [{ type: "text", text: "Nic." }], stop_reason: "end_turn", usage }),
    ], { kind: "unparsed" });
    const out = await runShopping(api, { offers: fakeSource("not_set_up"), fetcher: fakeFetcher({}) }, task, control());
    assert.equal(out.kind, "failed");
    if (out.kind === "failed") assert.equal(out.code, "unreadable_result");
    const r = (api.calls[1]!.at(-1)!.content as unknown as Array<{ content: string; is_error: boolean }>)[0]!;
    assert.equal(r.is_error, true);
    assert.match(r.content, /not set up/u);
    assert.equal(api.cardInputs.length, 0, "no card without offers");
  });

  test("the offer-search limit holds, and an unknown tool is answered as an error", async () => {
    const source = fakeSource([{ title: "A", shop: "S", priceText: "10 zł", link: "https://s.example/a" }]);
    const api = new FakeShoppingApi([
      () => ({ content: [toolUse("a", "find_offers", { query: "1" }), toolUse("b", "find_offers", { query: "2" }), toolUse("c", "buy_now", {})], stop_reason: "tool_use", usage }),
      () => ({ content: [{ type: "text", text: "ok" }], stop_reason: "end_turn", usage }),
    ], { kind: "ok", usage, card: sampleCard({ picks: [{ role: "best", offerId: "o1", why: "Jedyna.", tradeoff: null }], budget: { amount: null }, offerNotes: [] }) });
    const out = await runShopping(api, { offers: source, fetcher: fakeFetcher({}), maxOfferSearches: 1 }, task, control());
    assert.equal(out.kind, "done");
    const results = api.calls[1]!.at(-1)!.content as unknown as Array<{ is_error?: boolean; content: string }>;
    assert.equal(results[0]!.is_error, undefined);
    assert.match(results[1]!.content, /limit/u);
    assert.match(results[2]!.content, /no tool called buy_now/u);
    assert.deepEqual(source.queries, ["1"]);
  });

  test("a refusal, a provider error and a cancel end the run without a result", async () => {
    const refuse = new FakeShoppingApi([() => ({ content: [], stop_reason: "refusal", usage })], { kind: "unparsed" });
    const r1 = await runShopping(refuse, { offers: fakeSource([]), fetcher: fakeFetcher({}) }, task, control());
    assert.deepEqual([r1.kind, r1.kind === "failed" && r1.code], ["failed", "refused"]);
    const broken = new FakeShoppingApi([() => { throw new Error("boom"); }], { kind: "unparsed" });
    const r2 = await runShopping(broken, { offers: fakeSource([]), fetcher: fakeFetcher({}) }, task, control());
    assert.deepEqual([r2.kind, r2.kind === "failed" && r2.code], ["failed", "provider_error"]);
    const r3 = await runShopping(refuse, { offers: fakeSource([]), fetcher: fakeFetcher({}) }, task, control({ isCancelled: async () => true }));
    assert.equal(r3.kind, "cancelled");
  });

  test("the routing researcher sends shopping errands to the shopping runner and the rest as before", async () => {
    const seen: string[] = [];
    const general: ErrandResearcher = {
      provider: "anthropic", model: "claude-opus-5-5",
      async research(t: ErrandTask): Promise<ResearchOutcome> { seen.push(`general:${t.id}`); return { kind: "cancelled", usage: { inputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0, outputTokens: 0 }, searches: 0, fetches: 0, model: "claude-opus-5-5" }; },
    };
    const shopping = new ShoppingErrandResearcher(new FakeShoppingApi([() => ({ content: [], stop_reason: "refusal", usage })], { kind: "unparsed" }), { offers: fakeSource([]), fetcher: fakeFetcher({}) });
    const routing = new RoutingErrandResearcher(general, shopping);
    await routing.research({ id: "r1", words, brief, language: "pl" }, control());
    const out = await routing.research(task, control());
    assert.deepEqual(seen, ["general:r1"]);
    assert.equal(out.model, "claude-sonnet-5-5");
    assert.equal(routing.model, "claude-opus-5-5");
  });
});

describe("Serper offer source", () => {
  test("asks for Poland in Polish with the key in a header, and maps the shopping list", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fakeFetch = (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return new Response(JSON.stringify({ shopping: [{ title: "Zmywarka", source: "Media Expert", price: "1 899,00 zł", link: "https://www.google.com/shopping/product/1", delivery: "Darmowa dostawa" }] }), { status: 200 });
    }) as unknown as typeof fetch;
    const r = await new SerperOfferSource("k", fakeFetch).search("zmywarka 45");
    assert.deepEqual(r, { kind: "ok", offers: [{ title: "Zmywarka", shop: "Media Expert", priceText: "1 899,00 zł", link: "https://www.google.com/shopping/product/1", delivery: "Darmowa dostawa" }] });
    assert.equal(calls[0]?.url, "https://google.serper.dev/shopping");
    assert.deepEqual(JSON.parse(String(calls[0]?.init.body)), { q: "zmywarka 45", gl: "pl", hl: "pl", num: 20 });
    assert.equal((calls[0]?.init.headers as Record<string, string>)["X-API-KEY"], "k");
    assert.equal((await new SerperOfferSource(undefined, fakeFetch).search("x")).kind, "not_set_up");
    const failing = (async () => new Response("no", { status: 403 })) as unknown as typeof fetch;
    assert.equal((await new SerperOfferSource("k", failing).search("x")).kind, "failed");
  });
});
