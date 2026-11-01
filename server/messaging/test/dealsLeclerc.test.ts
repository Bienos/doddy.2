// E.Leclerc's reader against small synthetic lists in the shape leclerc.pl/gazetki/ had on 2026-10-30 (an article per
// leaflet with its dates, and a flipbook script with desktop and mobile page sets). Nothing of the chain's own page
// is kept here: the file names, dates and ids are made up.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { datesFromText, LECLERC_LISTING, LECLERC_MAX_PAGES, leclerc, leclercLeaflets, parseListing, type ListedLeaflet } from "../src/deals/chains/leclerc.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext, ChainRead, LeafletRead } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const UP = "https://leclerc.pl/wp-content/uploads/2026/10/";
const ROBOTS = "User-agent: *\nDisallow: /wp-admin/\nAllow: /wp-admin/admin-ajax.php\n\nSitemap: https://leclerc.pl/sitemap.xml\n";

interface Fake {
  id: number;
  dates: string;
  files: string[];
  /** A shop site's copy: one plain `pages: [...]` set of the originals. */
  shop?: boolean;
  alt?: string;
  cls?: string;
  extra?: string;
  /** Page addresses as written, in place of the made-up ones. */
  srcs?: string[];
}

const files = (stem: string, n: number) => Array.from({ length: n }, (_, i) => `${stem}_${String(i + 1).padStart(2, "0")}`);

/** One leaflet's block as the list prints it: the cover, the dates, then the flipbook's page sets. */
function article(a: Fake): string {
  const set = (suffix: string) => (a.srcs ?? a.files.map((f) => `${UP}${f}${suffix}.jpg`))
    .map((src, i) => `\t\t\t\t\t{\n\t\t\t\t\t\tsrc: "${src}",\n\t\t\t\t\t\tthumb: "${UP}${a.files[i] ?? "x"}.jpg",\n\t\t\t\t\t},`).join("\n");
  const pages = a.shop
    ? `pages: [\n${set("")}\n\t\t\t],`
    : `pages: (function() {\n\t\t\t\tvar pagesDesktop = [\n${set("-1047x1600")}\n\t\t\t\t];\n\t\t\t\tvar pagesMobile = [\n${set("-720x1100")}\n\t\t\t\t];\n` +
      `\t\t\t\treturn window.matchMedia && window.matchMedia('(max-width: 767px)').matches ? pagesMobile : pagesDesktop;\n\t\t\t})(),`;
  return `<article class="post-${a.id} gazetki type-gazetki status-publish hentry${a.cls ? ` ${a.cls}` : ""}" id="newspaper-${a.id}">
\t<img width="1240" height="1755" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAdult" class="attachment-newspaper lazyload" alt="${a.alt ?? ""}" data-src="${UP}${a.files[0] ?? "x"}.jpg" />
\t<div class="entry-content">
\t\t<p>${a.dates}</p>
\t\t<button class="btn btn-primary">Zobacz gazetkę</button>${a.extra ?? ""}
\t</div><!-- .entry-content -->
\t<footer class="entry-footer">
\t</footer><!-- .entry-footer -->
</article><!-- #post-## -->
<script type="text/javascript">
\tjQuery(document).ready(function($) {
\t\t$("#newspaper-${a.id}").flipBook({
\t\t\t${pages}
\t\t\tlightBox: true,
\t\t\tlogoUrl: 'https://leclerc.pl',
\t\t});
\t})
</script>`;
}

/** The list page: the blur style for age-gated covers, the list, then the shared age-gate dialog after </main>. */
const listPage = (articles: Fake[]) => `<!DOCTYPE html><html lang="pl-PL"><head><title>Gazetki - E.Leclerc</title>
<style>.inactive-newspaper img { filter: blur(2px); }</style></head><body>
<main class="site-main" id="main">
<header class="page-header"><h1 class="page-title">Gazetki promocyjne</h1></header>
<p><button class="btn btn-tertiary shopChooserNewspapers">Wybierz sklep</button></p>
<div class="newspapers-list">
${articles.map(article).join("\n")}
</div>
</main>
<footer class="site-footer"></footer>
<div class="modal fade hide" id="adultModal"><div class="modal-body">
<p>Materiały zawarte w katalogu dotyczą napojów alkoholowych i są skierowane wyłącznie do osób, które ukończyły 18 lat.</p>
<button type="button" class="btn btn-success adultProceedButton">Potwierdzam</button></div></div>
</body></html>`;

/** This week on 30 Oct: one started leaflet, a card leaflet, one starting on Tuesday, one ended, one too far off. */
const WEEK: Fake[] = [
  { id: 101, dates: "od&nbsp;03.11. do&nbsp;14.11.2026&nbsp;r.", files: files("001_T_45", 3) },
  { id: 102, dates: "od&nbsp;26.10. do&nbsp;02.11.2026&nbsp;r.", files: files("Katalog-centralny-T44", 4) },
  { id: 103, dates: "od&nbsp;20.10. do&nbsp;28.10.2026&nbsp;r.", files: files("001_T_43", 5) },
  { id: 104, dates: "od&nbsp;10.11. do&nbsp;21.11.2026&nbsp;r.", files: files("001_T_46", 2) },
  { id: 105, dates: "od 26.10. do 02.11.2026 r.", files: [...files("T_44_karta", 1), "owoce_winogrona_02"] },
];

const html = (articles: Fake[]) => ({ headers: { "content-type": "text/html; charset=UTF-8" }, body: listPage(articles) });
const web = (articles: Fake[] = WEEK) => new FakeWeb().robots("https://leclerc.pl", ROBOTS).on(LECLERC_LISTING, html(articles));
const ctx = (w: FakeWeb, today = TODAY): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: w.fetch }), queries: ["masło"], today, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead[] => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? r.leaflets : [];
};
const idOf = (l: LeafletRead) => l.leaflet.url.split("#newspaper-")[1];

describe("E.Leclerc: the list", () => {
  test("each leaflet's dates and desktop pages, in order; not the mobile set, not the originals", () => {
    const listed = parseListing(listPage(WEEK), TODAY)!;
    assert.deepEqual(listed.map((l) => [l.id, l.validFrom, l.validTo, l.alcohol, l.images.length]), [
      ["101", "2026-11-03", "2026-11-14", false, 3],
      ["102", "2026-10-26", "2026-11-02", false, 4],
      ["103", "2026-10-20", "2026-10-28", false, 5],
      ["104", "2026-11-10", "2026-11-21", false, 2],
      ["105", "2026-10-26", "2026-11-02", false, 2],
    ]);
    assert.deepEqual(listed[1]!.images, files("Katalog-centralny-T44", 4).map((f) => `${UP}${f}-1047x1600.jpg`));
    assert.equal(listed[4]!.alcohol, false, "'winogrona' is fruit, not wine");
  });

  test("dates as the list prints them, a range over New Year, and none", () => {
    assert.deepEqual(datesFromText("od 03.11. do 14.11.2026 r.", TODAY), { validFrom: "2026-11-03", validTo: "2026-11-14" });
    assert.deepEqual(datesFromText("od 29.12. do 10.01.2027 r.", "2026-12-20"), { validFrom: "2026-12-29", validTo: "2027-01-10" });
    assert.deepEqual(datesFromText("od 26.10.2026 r. do 02.11.2026 r.", TODAY), { validFrom: "2026-10-26", validTo: "2026-11-02" });
    assert.deepEqual(datesFromText("26.10 – 02.11", TODAY), { validFrom: "2026-10-26", validTo: "2026-11-02" });
    assert.deepEqual(datesFromText("Zobacz gazetkę", TODAY), {});
  });

  test("page addresses only over https on leclerc.pl's uploads; a shop site's plain page set is read too", () => {
    const tampered: Fake = {
      id: 201, dates: "od 26.10. do 02.11.2026 r.", files: files("x", 6),
      srcs: [
        `${UP}a-1047x1600.jpg`, "https://evil.example/wp-content/uploads/b.jpg", "http://leclerc.pl/wp-content/uploads/c.jpg",
        "https://leclerc.pl/wp-admin/d.jpg", `${UP}a-1047x1600.jpg`, "https://www.leclerc.pl/wp-content/uploads/2026/10/e.jpg",
      ],
    };
    const shop: Fake = { id: 202, dates: "od 26.10. do 02.11.2026 r.", files: files("T_44_cashback", 1), shop: true };
    const [t, s] = parseListing(listPage([tampered, shop]), TODAY)!;
    assert.deepEqual(t!.images, [`${UP}a-1047x1600.jpg`, "https://www.leclerc.pl/wp-content/uploads/2026/10/e.jpg"]);
    assert.deepEqual(s!.images, [`${UP}T_44_cashback_01.jpg`]);
    assert.equal(parseListing("<html><body>Strona główna</body></html>", TODAY), undefined, "not the list");
    assert.deepEqual(parseListing('<div class="newspapers-list"></div></main>', TODAY), [], "an empty list");
    assert.equal(parseListing('<div class="newspapers-list"><article class="post-1 gazetki">x</article></div></main>', TODAY), undefined,
      "blocks that no longer carry their id: the page changed, not 'no leaflet'");
  });
});

describe("E.Leclerc: the reader", () => {
  test("this week's leaflets, started ones first: page images to read, no product data, nothing else fetched", async () => {
    const w = web();
    const r = await leclerc.read(ctx(w));
    const leaflets = ok(r);
    assert.equal(r.kind === "ok" && r.incomplete, undefined);
    assert.deepEqual(leaflets.map(idOf), ["102", "105", "101"], "ended 103 and 104 (from 10 Nov) left out; 101 from Tuesday comes last");
    const [katalog, karta, next] = leaflets;
    assert.deepEqual(katalog!.leaflet, {
      title: "Gazetka E.Leclerc od 26.10 do 02.11.2026", url: `${LECLERC_LISTING}#newspaper-102`, validFrom: "2026-10-26", validTo: "2026-11-02",
    });
    assert.deepEqual(next!.leaflet.validFrom, "2026-11-03");
    for (const l of leaflets) {
      assert.equal(l.strategy, "all");
      assert.deepEqual(l.products, []);
    }
    assert.deepEqual(karta!.pages, [
      { number: 1, imageUrl: `${UP}T_44_karta_01-1047x1600.jpg`, url: `${LECLERC_LISTING}#newspaper-105` },
      { number: 2, imageUrl: `${UP}owoce_winogrona_02-1047x1600.jpg`, url: `${LECLERC_LISTING}#newspaper-105` },
    ]);
    assert.deepEqual([...w.hosts()], ["leclerc.pl"]);
    assert.deepEqual(w.requests.map((q) => q.url), ["https://leclerc.pl/robots.txt", LECLERC_LISTING], "robots.txt and the list; the service fetches the images");
    assert.ok(w.requests.every((q) => q.headers["user-agent"]?.startsWith("DoddyBot/1.0")));
  });

  test("alcohol leaflets are skipped: by their words, their file names, their alt text or an age gate in their block", () => {
    const week = "od 26.10. do 08.11.2026 r.";
    const listed = parseListing(listPage([
      { id: 301, dates: `Katalog alkoholi ${week}`, files: files("katalog", 2) },
      { id: 302, dates: week, files: files("Swiat_win_T44", 2) },
      { id: 303, dates: week, files: files("katalog_T44", 2), alt: "Piwa regionalne" },
      { id: 304, dates: week, files: files("katalog_T44b", 2), cls: "inactive-newspaper" },
      { id: 305, dates: week, files: files("katalog_T44c", 2), extra: '<button class="btn" data-toggle="modal" data-target="#adultModal">Zobacz</button>' },
      { id: 306, dates: week, files: files("WODKA-T44", 1) },
      { id: 307, dates: week, files: files("hity-cenowe_T44", 2) },
    ]), TODAY)!;
    assert.deepEqual(listed.map((l) => [l.id, l.alcohol]), [
      ["301", true], ["302", true], ["303", true], ["304", true], ["305", true], ["306", true],
      ["307", false],
    ], "the shared age-gate dialog after the list doesn't count against the last leaflet; a placeholder image's bytes don't either");
    assert.deepEqual(leclercLeaflets(listed, TODAY).leaflets.map(idOf), ["307"]);
  });

  test("at most 120 pages in all: started leaflets first, the last one cut, and the read says it is incomplete", async () => {
    const big = (id: number, dates: string, n: number): ListedLeaflet => ({
      id: String(id), ...datesFromText(dates, TODAY), alcohol: false, images: files(`${UP}p${id}`, n).map((f) => `${f}.jpg`),
    });
    const listed = [big(1, "od 03.11. do 14.11.2026", 30), big(2, "od 26.10. do 02.11.2026", 50), big(3, "od 20.10. do 31.10.2026", 50), big(4, "od 26.10. do 02.11.2026", 50)];
    const { leaflets, dropped } = leclercLeaflets(listed, TODAY);
    assert.deepEqual(leaflets.map((l) => [idOf(l), l.pages.length]), [["2", 50], ["3", 50], ["4", 20]]);
    assert.equal(leaflets.reduce((n, l) => n + l.pages.length, 0), LECLERC_MAX_PAGES);
    assert.deepEqual(leaflets[2]!.pages.at(-1)!.number, 20);
    assert.equal(dropped, 60, "30 of the fourth and all 30 of the one starting on Tuesday");

    const many = Array.from({ length: 5 }, (_, i): Fake => ({ id: 400 + i, dates: "od 26.10. do 02.11.2026 r.", files: files(`gazetka${i}`, 30) }));
    const r = await leclerc.read(ctx(web(many)));
    assert.equal(r.kind === "ok" && r.incomplete, "page_cap");
    assert.equal(ok(r).reduce((n, l) => n + l.pages.length, 0), 120);
  });

  test("blocked, disallowed, no leaflet this week, a changed page, a leaflet without readable pages", async () => {
    assert.deepEqual(await leclerc.read(ctx(web().on(LECLERC_LISTING, { status: 403 }))), { kind: "blocked", reason: "blocked:http_403" });

    const shut = web().robots("https://leclerc.pl", "User-agent: *\nDisallow: /gazetki/\n");
    assert.deepEqual(await leclerc.read(ctx(shut)), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(shut.hits(LECLERC_LISTING), 0, "a disallowed list is never fetched");

    const busy = web().on("https://leclerc.pl/robots.txt", { status: 429 });
    assert.deepEqual(await leclerc.read(ctx(busy)), { kind: "blocked", reason: "blocked:robots_http_429" });
    assert.equal(busy.hits(LECLERC_LISTING), 0);

    const wall = web().on(LECLERC_LISTING, { headers: { "content-type": "text/html" }, body: "<html><head><title>Just a moment...</title></head></html>" });
    assert.deepEqual(await leclerc.read(ctx(wall)), { kind: "blocked", reason: "blocked:challenge" });
    assert.equal(wall.hits(LECLERC_LISTING), 1, "a challenge is not retried");

    assert.deepEqual(await leclerc.read(ctx(web(), "2026-12-01")), { kind: "no_leaflet" });
    assert.deepEqual(await leclerc.read(ctx(web().on(LECLERC_LISTING, { headers: { "content-type": "text/html" }, body: "<html></html>" }))),
      { kind: "failed", reason: "unreadable_listing" });
    const offHost: Fake = { id: 501, dates: "od 26.10. do 02.11.2026 r.", files: files("x", 1), srcs: ["https://cdn.example/x.jpg"] };
    assert.deepEqual(await leclerc.read(ctx(web([offHost]))), { kind: "failed", reason: "no_pages" });
    const partly = await leclerc.read(ctx(web([offHost, WEEK[1]!])));
    assert.equal(partly.kind === "ok" && partly.incomplete, "some_leaflets_failed");
  });
});
