// Delikatesy Centrum's leaflet reader against small synthetic copies of the shape www.delikatesy.pl/gazetki served
// on 2026-10-30 (Next.js __NEXT_DATA__ → props.pageProps.booklets). The names, ids and image addresses here are
// made up; no page of the chain's is kept in the repository.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { bookletDay, bookletPages, DELIKATESY_HOSTS, DELIKATESY_LISTING, delikatesy, parseGazetki } from "../src/deals/chains/delikatesy.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const STATIC = "https://static.delikatesy.pl";
const img = (leaflet: number, page: number) => `${STATIC}/booklet_pages/test${leaflet}p${page}-flipbook.jpg`;

interface BookletSpec { id: number; name: string; from: string; to: string; adult?: boolean | null; pages: number }
function booklet(b: BookletSpec): Record<string, unknown> {
  const pages = Array.from({ length: b.pages }, (_, i) => ({
    src: img(b.id, i + 1), thumb: `${STATIC}/booklet_pages/test${b.id}p${i + 1}-thumbnail.jpg`, title: String(i + 1),
  }));
  return {
    id: b.id, name: b.name, type: "2 ", types: ["1 FRESH"],
    ...(b.adult === null ? {} : { requires_age_of_consent: b.adult ?? false }),
    tile_h3_content: "Do końca tylko<br /><strong>5 dni</strong>", date_from: b.from, date_to: b.to, bookmarks: [],
    first_page: `${STATIC}/booklet_pages/test${b.id}p1.jpg`, pages, pdf_src: `${STATIC}/booklet_pdfs/test${b.id}.pdf`, url: null, url_name: null,
  };
}
function listingHtml(booklets: unknown[]): string {
  const data = { props: { pageProps: { booklets }, __N_SSG: true }, page: "/gazetki", buildId: "test", isFallback: false, gsp: true };
  return `<!DOCTYPE html><html lang="pl-PL"><head><title>Gazetki promocyjne Delikatesy Centrum</title></head><body><div id="__next"></div>`
    + `<script id="__NEXT_DATA__" type="application/json">${JSON.stringify(data)}</script></body></html>`;
}

const WEEK = { id: 101, name: "Franczyza DC44 Czwartek", from: "29.10.2026", to: "04.11.2026", pages: 4 };
const ALCOHOL = { id: 102, name: "Delibarek DC44-DC45", from: "29.10.2026", to: "11.11.2026", adult: true, pages: 3 };

const web = (html: string) => new FakeWeb().on(DELIKATESY_LISTING, { headers: { "content-type": "text/html; charset=utf-8" }, body: html });
const ctx = (w: FakeWeb): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: w.fetch }), queries: ["masło"], today: TODAY, signal: new AbortController().signal,
});

describe("Delikatesy Centrum: the list page's data", () => {
  test("this week's leaflet: dates from DD.MM.YYYY, every page image in order, linked to the list page", () => {
    assert.equal(bookletDay("29.10.2026"), "2026-10-29");
    assert.equal(bookletDay("4.11.2026"), "2026-11-04");
    assert.equal(bookletDay("2026-11-04"), "2026-11-04");
    assert.equal(bookletDay("31.02.2026"), undefined);
    const listing = parseGazetki(listingHtml([booklet(WEEK)]), TODAY)!;
    assert.equal(listing.leaflets.length, 1);
    const [l] = listing.leaflets;
    assert.deepEqual(l!.leaflet, { title: "Gazetka Delikatesy Centrum", url: DELIKATESY_LISTING, validFrom: "2026-10-29", validTo: "2026-11-04" });
    assert.equal(l!.strategy, "all");
    assert.deepEqual(l!.products, []);
    assert.deepEqual(l!.pages, [1, 2, 3, 4].map((n) => ({ number: n, imageUrl: img(101, n), url: DELIKATESY_LISTING })));
  });

  test("the alcohol leaflet (age flag, or its name) is skipped; one without the flag can't be told apart and is skipped too", () => {
    const listing = parseGazetki(listingHtml([booklet(ALCOHOL), booklet(WEEK)]), TODAY)!;
    assert.deepEqual(listing.leaflets.map((l) => l.pages[0]!.imageUrl), [img(101, 1)]);
    assert.equal(listing.skipped.adult, 1);
    const byName = parseGazetki(listingHtml([booklet({ ...ALCOHOL, adult: false })]), TODAY)!;
    assert.deepEqual(byName.leaflets, [], "an unflagged Delibarek is still alcohol");
    const unflagged = parseGazetki(listingHtml([booklet({ ...WEEK, adult: null })]), TODAY)!;
    assert.deepEqual(unflagged.leaflets, []);
    assert.equal(unflagged.skipped.unflagged, 1);
  });

  test("leaflets outside this week are skipped; the one already running comes first", () => {
    const ended = { ...WEEK, id: 103, from: "22.10.2026", to: "28.10.2026" };
    const later = { ...WEEK, id: 104, from: "12.11.2026", to: "18.11.2026" };
    const next = { ...WEEK, id: 105, from: "05.11.2026", to: "11.11.2026" };
    const listing = parseGazetki(listingHtml([booklet(ended), booklet(next), booklet(later), booklet(WEEK)]), TODAY)!;
    assert.deepEqual(listing.leaflets.map((l) => [l.leaflet.validFrom, l.leaflet.validTo]), [["2026-10-29", "2026-11-04"], ["2026-11-05", "2026-11-11"]]);
  });

  test("only https images on static.delikatesy.pl count; page numbers are the site's", () => {
    const pages = bookletPages([
      { src: "https://evil.example/p.jpg", title: "1" },
      { src: `http://static.delikatesy.pl/booklet_pages/x-flipbook.jpg`, title: "2" },
      { thumb: `${STATIC}/booklet_pages/y-thumbnail.jpg`, title: "3" },
      { src: `${STATIC}/booklet_pages/z-flipbook.jpg`, title: "4" },
      { src: `${STATIC}/booklet_pages/w-flipbook.jpg`, title: "4" },
      { src: `${STATIC}/booklet_pages/v-flipbook.jpg` },
      "not a page",
    ]);
    assert.deepEqual(pages.map((p) => [p.number, p.imageUrl]), [[4, `${STATIC}/booklet_pages/z-flipbook.jpg`], [6, `${STATIC}/booklet_pages/v-flipbook.jpg`]]);
    assert.equal(parseGazetki("<html><body>no data</body></html>", TODAY), undefined);
    assert.equal(parseGazetki('<script id="__NEXT_DATA__" type="application/json">{"props":</script>', TODAY), undefined);
  });
});

describe("Delikatesy Centrum: the reader", () => {
  test("reads the list page only (the service fetches the images), from the chain's hosts", async () => {
    const w = web(listingHtml([booklet(ALCOHOL), booklet(WEEK)]));
    const r = await delikatesy.read(ctx(w));
    assert.equal(r.kind, "ok", JSON.stringify(r));
    if (r.kind !== "ok") return;
    assert.equal(r.leaflets.length, 1);
    assert.equal(r.leaflets[0]!.pages.length, 4);
    assert.equal(r.incomplete, undefined);
    assert.deepEqual(w.requests.map((q) => q.url), ["https://www.delikatesy.pl/robots.txt", DELIKATESY_LISTING]);
    assert.equal(w.requests[1]!.headers["user-agent"], "DoddyBot/1.0 (+https://doddy.lol/bot)");
    assert.ok(r.leaflets[0]!.pages.every((p) => (DELIKATESY_HOSTS as readonly string[]).includes(new URL(p.imageUrl).hostname)));
  });

  test("a 403 or a robots.txt that says no is blocked and nothing else is tried", async () => {
    const forbidden = new FakeWeb().on(DELIKATESY_LISTING, { status: 403, body: "no" });
    assert.deepEqual(await delikatesy.read(ctx(forbidden)), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(forbidden.requests.length, 2);
    const robots = web(listingHtml([booklet(WEEK)])).robots("https://www.delikatesy.pl", "User-agent: *\nDisallow: /gazetki\n");
    assert.deepEqual(await delikatesy.read(ctx(robots)), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(robots.hits(DELIKATESY_LISTING), 0);
    const challenge = new FakeWeb().on(DELIKATESY_LISTING, { status: 200, headers: { "content-type": "text/html", "cf-mitigated": "challenge" }, body: "<html></html>" });
    assert.deepEqual(await delikatesy.read(ctx(challenge)), { kind: "blocked", reason: "blocked:challenge" });
  });

  test("only the alcohol leaflet this week is no_leaflet; no data or no pages is failed", async () => {
    assert.deepEqual(await delikatesy.read(ctx(web(listingHtml([booklet(ALCOHOL)])))), { kind: "no_leaflet" });
    assert.deepEqual(await delikatesy.read(ctx(web(listingHtml([])))), { kind: "no_leaflet" });
    assert.deepEqual(await delikatesy.read(ctx(web("<html><body>Gazetki</body></html>"))), { kind: "failed", reason: "no_payload" });
    assert.deepEqual(await delikatesy.read(ctx(web(listingHtml([booklet({ ...WEEK, pages: 0 })])))), { kind: "failed", reason: "no_pages" });
    assert.deepEqual(await delikatesy.read(ctx(web(listingHtml([booklet({ ...WEEK, adult: null })])))), { kind: "failed", reason: "no_age_flag" });
    assert.deepEqual(await delikatesy.read(ctx(new FakeWeb().on(DELIKATESY_LISTING, { status: 500 }))), { kind: "failed", reason: "http_500" });
  });

  test("the image host's robots.txt answers 403 (as S3 does for any missing object): no rules, so a page image may be read", async () => {
    // Observed 2026-10-30: static.delikatesy.pl/robots.txt → 403 AccessDenied, the same answer as for a missing image.
    // The polite fetcher reads a 4xx robots.txt as no file (RFC 9309); a 403 on the image itself would be a block.
    const w = new FakeWeb()
      .on(`${STATIC}/robots.txt`, { status: 403, headers: { "content-type": "application/xml" }, body: "<Error><Code>AccessDenied</Code></Error>" })
      .on(img(101, 1), { headers: { "content-type": "image/jpeg" }, body: Buffer.from([0xff, 0xd8, 0xff]) })
      .on(img(101, 2), { status: 403, body: "<Error><Code>AccessDenied</Code></Error>" });
    const f = new PoliteFetcher({ fetch: w.fetch });
    assert.equal((await f.fetchPage(img(101, 1), { aiInput: true })).kind, "ok");
    assert.deepEqual(await f.fetchPage(img(101, 2), { aiInput: true }), { kind: "blocked", reason: "http_403" });
  });
});
