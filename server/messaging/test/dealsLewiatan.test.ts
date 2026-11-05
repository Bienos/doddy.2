// Lewiatan's leaflet reader against small synthetic copies of the shape www.lewiatan.pl served on 2026-10-30: a
// FlowPaper viewer page (its config names the page images and a JSON file in chunks of 10 pages) and the first chunk,
// zlib-compressed JSON whose first entry carries the page count. The names, numbers and addresses here are made up;
// no page or image of the chain's is kept in the repository.
import assert from "node:assert/strict";
import zlib from "node:zlib";
import { describe, test } from "node:test";
import {
  datesFromTitle, FLOWPAPER_CHUNK, isCurrent, LEWIATAN_HOSTS, LEWIATAN_MAX_PAGES, LEWIATAN_VIEWER, lewiatan, OPEN_RUN_DAYS, pageAddress,
  pageCountFromChunk, parseViewer,
} from "../src/deals/chains/lewiatan.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const DOCS = "https://www.lewiatan.pl/publikacje/gazetki/egazetka/docs";
const NAME = "7-Gazetka-Testowa-_22-10.pdf";
const img = (page: number) => `${DOCS}/${NAME}_${page}.jpg?reload=123`;
const CHUNK = `${DOCS}/${NAME}_${FLOWPAPER_CHUNK}.bin?reload=123`;

/** The viewer page as FlowPaper's publisher writes it, trimmed to what the reader looks at. */
function viewerHtml(opts: { title?: string; images?: string; json?: string | null; noConfig?: boolean } = {}): string {
  const title = opts.title ?? "7 Gazetka Testowa _22 10";
  const config = opts.noConfig ? "" : `<script type="text/javascript">
    $('#documentViewer').FlowPaperViewer(
            { config : {
                "PDFFile"                 : "docs/${NAME}?reload=123",
                "IMGFiles"                : "${opts.images ?? `docs/${NAME}_{page}.jpg?reload=123`}",
                "HighResIMGFiles"         : "",
                ${opts.json === null ? "" : `"JSONFile"                : "${opts.json ?? `docs/${NAME}_{page}.bin?reload=123`}",`}
                "JSONDataType"            : "lz",
                "ThumbIMGFiles"           : "docs/${NAME}_{page}_thumb.jpg?reload=123",
                "InitViewMode"            : "Zine",
                "UIConfig"                : "UI_Zine.xml?reload=123"
            }}
    );
</script>`;
  return `<!doctype html><html lang="en"><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" />`
    + `<meta property="og:title" content="${title}" /><title>${title}</title></head><body>`
    + `<div id="documentViewer" class="flowpaper_viewer"></div>${config}</body></html>`;
}

/** The first JSON chunk: an entry per page up to the chunk size, each naming the page count; text arrays empty. */
function chunk(pages: number, opts: { plain?: boolean; raw?: unknown } = {}): Buffer {
  const entries = opts.raw ?? Array.from({ length: Math.min(pages, FLOWPAPER_CHUNK - 1) }, (_, i) => ({
    number: i + 1, pages, width: 1022, height: 1513, fonts: [], text: [], detailed: true,
  }));
  const json = Buffer.from(JSON.stringify(entries), "utf8");
  return opts.plain ? json : zlib.deflateSync(json);
}

const web = (html = viewerHtml(), body: Buffer = chunk(12)) => new FakeWeb()
  .on(LEWIATAN_VIEWER, { headers: { "content-type": "text/html" }, body: html })
  .on(CHUNK, { headers: { "content-type": "application/octet-stream" }, body });
const ctx = (w: FakeWeb, today = TODAY): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: w.fetch }), queries: ["masło"], today, signal: new AbortController().signal,
});

describe("Lewiatan: the viewer page and its page list", () => {
  test("the FlowPaper config: the page images, the JSON file and the title", () => {
    const v = parseViewer(viewerHtml())!;
    assert.deepEqual(v, { images: `docs/${NAME}_{page}.jpg?reload=123`, json: `docs/${NAME}_{page}.bin?reload=123`, title: "7 Gazetka Testowa _22 10" });
    assert.equal(pageAddress(v.images, 3, LEWIATAN_VIEWER)!.toString(), img(3));
    assert.equal(pageAddress(v.json!, FLOWPAPER_CHUNK, LEWIATAN_VIEWER)!.toString(), CHUNK);
    assert.equal(parseViewer(viewerHtml({ noConfig: true })), undefined, "no viewer, no config");
    assert.equal(parseViewer(viewerHtml({ images: "docs/static.jpg" })), undefined, "an image address without {page}");
    assert.equal(parseViewer(viewerHtml({ json: null }))!.json, undefined);
  });

  test("only https addresses on lewiatan.pl count", () => {
    assert.equal(pageAddress("https://evil.example/docs/x_{page}.jpg", 1, LEWIATAN_VIEWER), undefined);
    assert.equal(pageAddress("http://www.lewiatan.pl/docs/x_{page}.jpg", 1, LEWIATAN_VIEWER), undefined);
    assert.equal(pageAddress("//cdn.example/x_{page}.jpg", 1, LEWIATAN_VIEWER), undefined);
    assert.equal(pageAddress("https://lewiatan.pl/docs/x_{page}.jpg", 2, LEWIATAN_VIEWER)!.toString(), "https://lewiatan.pl/docs/x_2.jpg");
  });

  test("the page count is the first entry's `pages`, from zlib or plain JSON; anything else is no count", () => {
    assert.equal(pageCountFromChunk(chunk(12)), 12);
    assert.equal(pageCountFromChunk(chunk(4, { plain: true })), 4);
    assert.equal(pageCountFromChunk(chunk(0, { raw: [{ number: 1, pages: "16" }] })), 16);
    assert.equal(pageCountFromChunk(chunk(0, { raw: { e: "U2FsdGVkX1…" } })), undefined, "an encrypted chunk");
    assert.equal(pageCountFromChunk(chunk(0, { raw: [] })), undefined);
    assert.equal(pageCountFromChunk(chunk(0, { raw: [{ number: 1, pages: 0 }] })), undefined);
    assert.equal(pageCountFromChunk(chunk(0, { raw: [{ number: 1, pages: 2.5 }] })), undefined);
    assert.equal(pageCountFromChunk(Buffer.from("<!DOCTYPE html><html>not found</html>")), undefined);
    assert.equal(pageCountFromChunk(Buffer.from([0x78, 0x9c, 0x01, 0x02])), undefined, "a broken stream");
    // A chunk that inflates past 4 MB is not read.
    assert.equal(pageCountFromChunk(zlib.deflateSync(Buffer.concat([Buffer.from('[{"pages":3,"x":"'), Buffer.alloc(5 * 1024 * 1024, 0x61), Buffer.from('"}]')]))), undefined);
  });

  test("dates in the title: the first day only (as on 30 Oct), or a range as the page prints it", () => {
    assert.deepEqual(datesFromTitle("10 Gazetka Mamy TO w Lewiatanie _22 10", TODAY), { validFrom: "2026-10-22" });
    assert.deepEqual(datesFromTitle("Gazetka 22-31.10.2026", TODAY), { validFrom: "2026-10-22", validTo: "2026-10-31" });
    assert.deepEqual(datesFromTitle("Gazetka 22.10-04.11", TODAY), { validFrom: "2026-10-22", validTo: "2026-11-04" });
    assert.deepEqual(datesFromTitle("Gazetka od 29.10", TODAY), { validFrom: "2026-10-29" });
    assert.deepEqual(datesFromTitle("Gazetka 28.12-03.01.2027", "2026-12-30"), { validFrom: "2026-12-28", validTo: "2027-01-03" });
    assert.deepEqual(datesFromTitle("12 Gazetka Mamy TO w Lewiatanie", TODAY), {}, "the leaflet's number is not a date");
    assert.deepEqual(datesFromTitle("Gazetka _31 02", TODAY), {});
    assert.deepEqual(datesFromTitle(undefined, TODAY), {});
  });

  test("this week: a first day alone counts for OPEN_RUN_DAYS; a range by its dates; no dates can't be ruled out", () => {
    assert.equal(OPEN_RUN_DAYS, 9);
    assert.ok(isCurrent({ validFrom: "2026-10-22" }, TODAY));
    assert.ok(isCurrent({ validFrom: "2026-10-21" }, TODAY), "9 days back");
    assert.ok(!isCurrent({ validFrom: "2026-10-20" }, TODAY), "10 days back and never replaced");
    assert.ok(isCurrent({ validFrom: "2026-10-22" }, "2026-10-31"), "the 22 Oct leaflet's last day (it ran 22 to 31 Oct)");
    assert.ok(!isCurrent({ validFrom: "2026-10-22" }, "2026-11-01"), "the day after: its offers have ended (ADR-669)");
    assert.ok(isCurrent({ validFrom: "2026-11-05" }, TODAY), "starts within six days");
    assert.ok(!isCurrent({ validFrom: "2026-11-06" }, TODAY));
    assert.ok(!isCurrent({ validFrom: "2026-10-12", validTo: "2026-10-29" }, TODAY));
    assert.ok(isCurrent({ validFrom: "2026-10-01", validTo: "2026-10-31" }, TODAY), "an end date overrides the open-run limit");
    assert.ok(isCurrent({}, TODAY));
  });
});

describe("Lewiatan: the reader", () => {
  test("this week's national leaflet: two requests (viewer, first chunk), every page in order, as DoddyBot", async () => {
    const w = web();
    const r = await lewiatan.read(ctx(w));
    assert.equal(r.kind, "ok", JSON.stringify(r));
    if (r.kind !== "ok") return;
    assert.equal(r.incomplete, undefined);
    assert.equal(r.leaflets.length, 1);
    const [l] = r.leaflets;
    assert.deepEqual(l!.leaflet, { title: "Gazetka ogólnopolska Lewiatan", url: LEWIATAN_VIEWER, validFrom: "2026-10-22" });
    assert.equal(l!.strategy, "all");
    assert.deepEqual(l!.products, []);
    assert.deepEqual(l!.pages, Array.from({ length: 12 }, (_, i) => ({ number: i + 1, imageUrl: img(i + 1), url: LEWIATAN_VIEWER })));
    assert.deepEqual(w.requests.map((q) => q.url), ["https://www.lewiatan.pl/robots.txt", LEWIATAN_VIEWER, CHUNK]);
    assert.ok(w.requests.every((q) => q.headers["user-agent"] === "DoddyBot/1.0 (+https://doddy.lol/bot)"));
    assert.ok(l!.pages.every((p) => (LEWIATAN_HOSTS as readonly string[]).includes(new URL(p.imageUrl).hostname)));
  });

  test("the site's own robots.txt (a Drupal default) lets /publikacje/ be read", async () => {
    // Observed 2026-10-30 on www.lewiatan.pl and lewiatan.pl alike (trimmed).
    const drupal = "User-agent: *\nAllow: /core/*.css$\nAllow: /core/*.jpg\nDisallow: /core/\nDisallow: /profiles/\nDisallow: /admin/\nDisallow: /search/\nDisallow: /user/login/\n";
    const w = web().robots("https://www.lewiatan.pl", drupal);
    assert.equal((await lewiatan.read(ctx(w))).kind, "ok");
  });

  test("a page count over the cap: the first 80 pages, and the read says it is incomplete", async () => {
    const r = await lewiatan.read(ctx(web(viewerHtml(), chunk(95))));
    assert.equal(r.kind, "ok");
    if (r.kind !== "ok") return;
    assert.equal(r.leaflets[0]!.pages.length, LEWIATAN_MAX_PAGES);
    assert.equal(r.incomplete, "page_cap");
  });

  test("a 403, a challenge or a robots.txt that says no is blocked, and nothing else is tried", async () => {
    const forbidden = new FakeWeb().on(LEWIATAN_VIEWER, { status: 403, body: "no" });
    assert.deepEqual(await lewiatan.read(ctx(forbidden)), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(forbidden.requests.length, 2);
    const robots = web().robots("https://www.lewiatan.pl", "User-agent: *\nDisallow: /publikacje/\n");
    assert.deepEqual(await lewiatan.read(ctx(robots)), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(robots.hits(LEWIATAN_VIEWER), 0);
    const named = web().robots("https://www.lewiatan.pl", "User-agent: DoddyBot\nDisallow: /\n\nUser-agent: *\nAllow: /\n");
    assert.deepEqual(await lewiatan.read(ctx(named)), { kind: "blocked", reason: "disallowed:robots" });
    const tooMany = web().on("https://www.lewiatan.pl/robots.txt", { status: 429 });
    assert.deepEqual(await lewiatan.read(ctx(tooMany)), { kind: "blocked", reason: "blocked:robots_http_429" });
    assert.equal(tooMany.hits(LEWIATAN_VIEWER), 0);
    const challenge = new FakeWeb().on(LEWIATAN_VIEWER, { status: 200, headers: { "content-type": "text/html", "cf-mitigated": "challenge" }, body: "<html></html>" });
    assert.deepEqual(await lewiatan.read(ctx(challenge)), { kind: "blocked", reason: "blocked:challenge" });
    const chunkBlocked = web().on(CHUNK, { status: 403, body: "no" });
    assert.deepEqual(await lewiatan.read(ctx(chunkBlocked)), { kind: "blocked", reason: "blocked:http_403" });
  });

  test("a 404 robots.txt is no file (RFC 9309): the leaflet is read", async () => {
    const w = web().on("https://www.lewiatan.pl/robots.txt", { status: 404, body: "not found" });
    assert.equal((await lewiatan.read(ctx(w))).kind, "ok");
  });

  test("not this week, or an alcohol leaflet: no_leaflet, and the page list isn't fetched", async () => {
    const stale = web();
    assert.deepEqual(await lewiatan.read(ctx(stale, "2026-11-01")), { kind: "no_leaflet" }, "first day 10 days back, never replaced");
    assert.equal(stale.hits(CHUNK), 0);
    assert.deepEqual(await lewiatan.read(ctx(web(viewerHtml({ title: "7 Gazetka Testowa 08-14.10.2026" })))), { kind: "no_leaflet" });
    assert.deepEqual(await lewiatan.read(ctx(web(viewerHtml({ title: "Gazetka alkoholowa _22 10" })))), { kind: "no_leaflet" });
    assert.deepEqual(await lewiatan.read(ctx(web(viewerHtml({ title: "Strefa Wina _22 10" })))), { kind: "no_leaflet" });
  });

  test("a leaflet starting within the week is read; a leaflet with no dates in its title is read without dates", async () => {
    const next = await lewiatan.read(ctx(web(viewerHtml({ title: "8 Gazetka Testowa _05 11" }))));
    assert.equal(next.kind === "ok" && next.leaflets[0]!.leaflet.validFrom, "2026-11-05");
    const undated = await lewiatan.read(ctx(web(viewerHtml({ title: "Gazetka Testowa" }))));
    assert.equal(undated.kind, "ok");
    if (undated.kind === "ok") assert.deepEqual(undated.leaflets[0]!.leaflet, { title: "Gazetka ogólnopolska Lewiatan", url: LEWIATAN_VIEWER });
  });

  test("failures: a broken viewer page, no page list, an unreadable chunk, an address off the chain's hosts", async () => {
    assert.deepEqual(await lewiatan.read(ctx(new FakeWeb().on(LEWIATAN_VIEWER, { status: 500 }))), { kind: "failed", reason: "http_500" });
    assert.deepEqual(await lewiatan.read(ctx(new FakeWeb())), { kind: "failed", reason: "http_404" });
    assert.deepEqual(await lewiatan.read(ctx(web(viewerHtml({ noConfig: true })))), { kind: "failed", reason: "no_viewer_config" });
    assert.deepEqual(await lewiatan.read(ctx(web(viewerHtml({ json: null })))), { kind: "failed", reason: "no_page_list" });
    assert.deepEqual(await lewiatan.read(ctx(web().on(CHUNK, { status: 404, body: "<!DOCTYPE html>" }))), { kind: "failed", reason: "http_404" });
    assert.deepEqual(await lewiatan.read(ctx(web(viewerHtml(), Buffer.from("<!DOCTYPE html><html></html>")))), { kind: "failed", reason: "no_page_count" });
    assert.deepEqual(await lewiatan.read(ctx(web(viewerHtml({ json: "https://evil.example/x_{page}.bin" })))), { kind: "failed", reason: "not_official_host" });
    const offHost = web(viewerHtml({ images: "https://cdn.example/x_{page}.jpg" }));
    assert.deepEqual(await lewiatan.read(ctx(offHost)), { kind: "failed", reason: "no_pages" });
    assert.ok(!offHost.hosts().has("cdn.example"));
    const redirected = new FakeWeb().on(LEWIATAN_VIEWER, { status: 302, headers: { location: "https://elsewhere.example/gazetka.html" } })
      .on("https://elsewhere.example/gazetka.html", { headers: { "content-type": "text/html" }, body: viewerHtml() });
    assert.deepEqual(await lewiatan.read(ctx(redirected)), { kind: "failed", reason: "redirected_off_host" });
  });
});
