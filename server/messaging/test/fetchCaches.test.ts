// Bounded caches in front of fetched content: the polite fetcher's robots.txt cache (rules kept per file, total
// size, oldest out) and the shared news cache (URL lengths, the size of a cached row).
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { parseRobots, PoliteFetcher, robotsAllows, robotsRulesFor, ROBOTS_MAX_RULES, ROBOTS_TOKEN } from "../src/deals/fetcher.js";
import { httpUrl, imageUrl, MAX_URL_CHARS, parseFeed, type NewsItem } from "../src/news/feeds.js";
import { cached, fitForCache, NEWS_CACHE_MAX_ROW_BYTES } from "../src/news/sources.js";
import { FakeWeb, ROBOTS } from "./dealsFakes.js";
import { dbSkip, freshDb } from "./helpers.js";

const page = { headers: { "content-type": "text/html" }, body: "<html><body>ok</body></html>" };
const disallows = (n: number, prefix = "/p") => Array.from({ length: n }, (_, i) => `Disallow: ${prefix}${i}/`).join("\n");

describe("robots.txt: what the fetcher keeps", () => {
  test("only DoddyBot's groups (else *), with the same answers as the whole file", () => {
    const files = [...Object.values(ROBOTS),
      "User-agent: *\nDisallow: /a\nUser-agent: DoddyBot/1.0\nAllow: /a/b\nDisallow: /c\nContent-Signal: ai-input=no, search=yes, x-other=1\n",
      "User-agent: googlebot\nUser-agent: *\nDisallow: /private\nAllow: /private/ok$\nUser-agent: otherbot\nDisallow: /\n"];
    const paths = ["/", "/a", "/a/b", "/c", "/private", "/private/ok", "/pl/search?q=x", "/promocje?utm_source=x", "/robots.txt", "/x/y"];
    for (const file of files) {
      const all = parseRobots(file);
      const kept = robotsRulesFor(all, ROBOTS_TOKEN);
      assert.ok(kept, file);
      for (const p of paths) {
        const a = robotsAllows(all, ROBOTS_TOKEN, p);
        const b = robotsAllows(kept, ROBOTS_TOKEN, p);
        assert.equal(b.allowed, a.allowed, `${p} in ${file.slice(0, 40)}`);
        assert.equal(b.signals["ai-input"], a.signals["ai-input"]);
      }
      assert.ok(kept.every((g) => g.agents.every((x) => x === "*" || x.split("/")[0] === ROBOTS_TOKEN)), "other agents' names are not kept");
    }
  });

  test("other agents' rules and rules that can never match don't count toward the cap", () => {
    const file = `User-agent: otherbot\n${disallows(ROBOTS_MAX_RULES * 3)}\nUser-agent: *\nDisallow: /${"x".repeat(2000)}\nDisallow: /private\n`;
    const kept = robotsRulesFor(parseRobots(file), ROBOTS_TOKEN);
    assert.deepEqual(kept?.flatMap((g) => g.rules), [{ allow: false, pattern: "/private" }]);
  });

  test(`up to ${ROBOTS_MAX_RULES} rules are kept; a file with more for DoddyBot disallows every fetch`, async () => {
    const atCap = robotsRulesFor(parseRobots(`User-agent: *\n${disallows(ROBOTS_MAX_RULES)}`), ROBOTS_TOKEN);
    assert.equal(atCap?.flatMap((g) => g.rules).length, ROBOTS_MAX_RULES);
    assert.equal(robotsRulesFor(parseRobots(`User-agent: *\n${disallows(ROBOTS_MAX_RULES + 1)}`), ROBOTS_TOKEN), undefined);

    const web = new FakeWeb()
      .robots("https://big.example", `User-agent: *\n${disallows(ROBOTS_MAX_RULES + 1)}`).on("https://big.example/free", page)
      .robots("https://fits.example", `User-agent: *\n${disallows(ROBOTS_MAX_RULES)}`).on("https://fits.example/free", page);
    const f = new PoliteFetcher({ fetch: web.fetch });
    assert.deepEqual(await f.fetchPage("https://big.example/free"), { kind: "disallowed", reason: "robots_too_large" });
    assert.equal((await f.fetchPage("https://fits.example/free")).kind, "ok");
    assert.deepEqual(await f.fetchPage("https://fits.example/p7/x"), { kind: "disallowed", reason: "robots" });
    assert.equal(web.hits("https://big.example/free"), 0, "the page itself is never asked for");
  });
});

describe("robots.txt cache: bounded by size, oldest out", () => {
  test("files are kept until their total passes the budget; then the oldest go first", async () => {
    const web = new FakeWeb();
    for (let i = 0; i < 10; i++) web.robots(`https://s${i}.example`, `User-agent: *\n${disallows(1000, `/${"d".repeat(40)}`)}`).on(`https://s${i}.example/ok`, page);
    const probe = new PoliteFetcher({ fetch: web.fetch });
    await probe.fetchPage("https://s0.example/ok");
    const one = probe.robotsCacheStats().bytes;
    assert.ok(one > 50_000, `a 1,000-rule file is counted (${one} bytes)`);

    const budget = Math.floor(one * 3.5);
    const f = new PoliteFetcher({ fetch: web.fetch, robotsCacheBytes: budget });
    for (let i = 0; i < 10; i++) {
      assert.equal((await f.fetchPage(`https://s${i}.example/ok`)).kind, "ok");
      const s = f.robotsCacheStats();
      assert.ok(s.bytes <= budget, `after ${i + 1} sites: ${s.bytes} > ${budget}`);
    }
    assert.equal(f.robotsCacheStats().origins, 3);
    const robotsReads = (i: number) => web.hits(`https://s${i}.example/robots.txt`);
    const [newest, oldest] = [robotsReads(9), robotsReads(0)];
    await f.fetchPage("https://s9.example/ok");
    assert.equal(robotsReads(9), newest, "the newest file is still cached");
    await f.fetchPage("https://s0.example/ok");
    assert.equal(robotsReads(0), oldest + 1, "the oldest was dropped and is read again");
  });

  test("small files are all kept, and an expired file is read again and counted once", async () => {
    let now = 0;
    const web = new FakeWeb();
    for (let i = 0; i < 20; i++) web.robots(`https://t${i}.example`, "User-agent: *\nDisallow: /private\n").on(`https://t${i}.example/ok`, page);
    const f = new PoliteFetcher({ fetch: web.fetch, now: () => now, robotsTtlMs: 1000 });
    for (let i = 0; i < 20; i++) await f.fetchPage(`https://t${i}.example/ok`);
    const full = f.robotsCacheStats();
    assert.equal(full.origins, 20);
    now = 5000;
    await f.fetchPage("https://t0.example/ok");
    assert.equal(web.hits("https://t0.example/robots.txt"), 2);
    assert.deepEqual(f.robotsCacheStats(), full, "the expired copy's size was given back");
  });
});

describe("news: URL lengths", () => {
  const long = `https://a.example/${"p".repeat(MAX_URL_CHARS)}`;

  test(`addresses over ${MAX_URL_CHARS} characters are not kept`, () => {
    assert.equal(httpUrl(long), null);
    assert.equal(imageUrl(long), undefined);
    const ok = `https://a.example/${"p".repeat(MAX_URL_CHARS - 40)}`;
    assert.equal(httpUrl(ok), ok);
  });

  test("an item whose link is too long is dropped before it is cached; a too-long picture just goes", () => {
    const rss = `<rss><channel><title>T</title>
      <item><title>Long guid</title><guid>${long}</guid></item>
      <item><title>Fine</title><link>https://a.example/1</link><enclosure url="${long}" type="image/jpeg"/></item>
      <item><title>Fine too</title><guid isPermaLink="true">https://a.example/2</guid><media:content url="https://a.example/2.jpg" medium="image"/></item>
    </channel></rss>`;
    const items = parseFeed(rss, "x").items;
    assert.deepEqual(items.map((i) => [i.title, i.url, i.imageUrl]), [["Fine", "https://a.example/1", undefined], ["Fine too", "https://a.example/2", "https://a.example/2.jpg"]]);
    const atom = `<feed><title>T</title><entry><title>Long</title><link href="${long}"/></entry><entry><title>Ok</title><link href="https://a.example/3"/></entry></feed>`;
    assert.deepEqual(parseFeed(atom, "x").items.map((i) => i.url), ["https://a.example/3"]);
  });
});

describe("news cache: the size of a row", () => {
  const item = (n: number, summary = "s".repeat(300)): NewsItem => ({
    title: `Title ${n} ${"t".repeat(150)}`, url: `https://a.example/${n}/${"u".repeat(1900)}`, source: "Src", summary, publishedAt: null,
    imageUrl: `https://a.example/${n}.jpg?${"i".repeat(1900)}`,
  });
  const bytes = (items: NewsItem[]) => Buffer.byteLength(JSON.stringify(items));

  test(`a row is cut to ${NEWS_CACHE_MAX_ROW_BYTES / 1024} KB of JSON, the first items kept in order`, () => {
    const many = Array.from({ length: 200 }, (_, i) => item(i));
    const fit = fitForCache(many);
    assert.ok(fit.length > 10 && fit.length < many.length);
    assert.ok(bytes(fit) <= NEWS_CACHE_MAX_ROW_BYTES);
    assert.deepEqual(fit, many.slice(0, fit.length));
    const few = [item(1), item(2)];
    assert.deepEqual(fitForCache(few), few, "a row that fits is kept whole");
  });

  describe("in the database", { skip: dbSkip }, () => {
    let db: Db;
    before(async () => { db = await freshDb(); });
    after(async () => { await db?.end(); });

    test("what is stored is what is returned, and it fits", async () => {
      const many = Array.from({ length: 200 }, (_, i) => item(i));
      const r = await cached(db, "feed:https://big.example/rss", 30, async () => ({ title: "Big", items: many }));
      assert.ok(r.ok && r.items.length < many.length);
      const row = await db.query<{ items: NewsItem[] }>("SELECT items FROM news_cache");
      assert.equal(row.rows.length, 1);
      assert.ok(bytes(row.rows[0]!.items) <= NEWS_CACHE_MAX_ROW_BYTES, `${bytes(row.rows[0]!.items)} bytes stored`);
      assert.deepEqual(row.rows[0]!.items, r.items);
      const again = await cached(db, "feed:https://big.example/rss", 30, async () => { throw new Error("not asked again"); });
      assert.deepEqual(again.items, r.items);
    });
  });
});
