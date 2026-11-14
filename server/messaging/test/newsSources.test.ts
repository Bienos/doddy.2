// Daily news and On my radar: more publishers, the same story told once, a mix of publishers, the reader's language a
// little first, and fewer fetches (decision 2026-11-13-news-more-sources). Headlines are made up but read like the real
// Polish ones the feeds carried on 13 Nov 2026.
import assert from "node:assert/strict";
import http from "node:http";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { ALL_CATALOG_FEEDS, CATALOG, catalogById } from "../src/news/catalog.js";
import { headlineTokens, sameHeadline, sameWord, StoryIndex, storyKey } from "../src/news/dedupe.js";
import { buildDigest, type NewsDeps } from "../src/news/digest.js";
import { buildFeed } from "../src/news/feed.js";
import type { NewsItem } from "../src/news/feeds.js";
import { matchesKeyword } from "../src/news/match.js";
import { runRadarPass, saveAlerts, type RadarContext } from "../src/news/radar.js";
import { DIVERSITY_PENALTY, LANGUAGE_BONUS, shortlist, type TopicItems } from "../src/news/rank.js";
import { FEED_FETCH_CONCURRENCY, FEED_KEEP_HOURS, FeedReader, fetchSlots, keepRecent } from "../src/news/reader.js";
import { requestOnce, validator, type Validators } from "../src/news/safeFetch.js";
import type { FeedSource, FetchedFeed } from "../src/news/sources.js";
import { dbSkip, FakePush, freshDb, testApp, testCipher } from "./helpers.js";

const NOW = new Date("2026-11-13T09:00:00Z");
const ago = (h: number, from = NOW) => new Date(from.getTime() - h * 3_600_000).toISOString();
const story = (title: string, url: string, source: string, h = 1, extra: Partial<NewsItem> = {}): NewsItem =>
  ({ title, url, source, summary: "", publishedAt: ago(h), ...extra });
const topic = (label: string, items: NewsItem[], keywords: string[] = [], curated = keywords.length === 0): TopicItems =>
  ({ label, keywords, curated, items });
const same = (a: string, b: string) => sameHeadline(headlineTokens(a), headlineTokens(b));

// ── The catalog ──────────────────────────────────────────────────────────────────────────────────────

test("every topic reads Polish and international publishers, Poland mostly Polish; each feed https, named and with a language", () => {
  for (const t of CATALOG) {
    // No Polish publisher had an AI-only feed that answered with recent stories on 13 Nov 2026 (decision); Polish AI
    // stories still reach a word follow such as "sztuczna inteligencja" through the Polish technology feeds.
    if (t.id !== "ai") assert.ok(t.feeds.some((f) => f.lang === "pl"), `${t.id} has a Polish publisher`);
    if (t.id !== "poland") assert.ok(t.feeds.some((f) => f.lang === "en"), `${t.id} has an international publisher`);
    for (const f of t.feeds) {
      assert.match(f.url, /^https:\/\//, f.url);
      assert.ok(["pl", "en"].includes(f.lang), f.url);
      assert.ok(f.name.length > 1 && f.name.length <= 40, f.url);
    }
    assert.equal(new Set(t.feeds.map((f) => f.url)).size, t.feeds.length, `${t.id} lists a feed once`);
  }
  const poland = catalogById.get("poland")!;
  assert.ok(poland.feeds.length >= 8, "Poland reads at least eight publishers");
  assert.ok(poland.feeds.filter((f) => f.lang === "pl").length >= 7);
  for (const name of ["TVN24", "Polsat News", "RMF24", "Onet", "Interia", "Wirtualna Polska", "Gazeta Wyborcza", "Rzeczpospolita"]) {
    assert.ok(poland.feeds.some((f) => f.name === name), name);
  }
  assert.ok(!poland.feeds.some((f) => f.url.endsWith("/wszystkie.xml")), "Polsat's Poland feed, not its everything feed");
  // More than the 33 feeds of 10 Nov 2026; a word follow looks through all of them.
  assert.ok(ALL_CATALOG_FEEDS.length > 60, `${ALL_CATALOG_FEEDS.length} catalog feeds`);
  assert.equal(new Set(ALL_CATALOG_FEEDS.map((f) => f.url)).size, ALL_CATALOG_FEEDS.length);
  // Hosts that refused this server's fetcher from the build machine (bot checks) or whose robots.txt disallows the feed
  // were left out (decision); the two older feeds that refused, Bankier.pl and The Guardian's health feed, are kept.
  for (const host of ["pap.pl", "apnews.com", "reuters.com", "politico.eu", "cnbc.com", "newscientist.com"]) {
    assert.ok(!ALL_CATALOG_FEEDS.some((f) => new URL(f.url).hostname.endsWith(host)), host);
  }
});

// ── Matching a follow ────────────────────────────────────────────────────────────────────────────────

test("follow words in Polish headlines: endings allowed, every word of a phrase in order, short names whole", () => {
  assert.ok(matchesKeyword("Rekordowy zysk Orlenu w III kwartale", "Orlen"));
  assert.ok(matchesKeyword("Kurs Bitcoina spada poniżej 90 tys. dolarów", "bitcoin"));
  assert.ok(matchesKeyword("Dwa gole Lewandowskiego. Barcelona pokonała Real", "Lewandowski"));
  assert.ok(matchesKeyword("Budowa CPK-u ruszyła na dobre", "CPK"));
  assert.ok(!matchesKeyword("CPKO otwiera nowy oddział", "CPK"));
  assert.ok(matchesKeyword("Gol Roberta Lewandowskiego w doliczonym czasie", "Robert Lewandowski"), "a phrase with both endings changed");
  assert.ok(!matchesKeyword("Robert Kubica i Lewandowski na gali", "Robert Lewandowski"), "both words, but not as the phrase");
  assert.ok(!matchesKeyword("Lewandowski w Barcelonie", "Robert Lewandowski"), "every word of a phrase is needed");
});

test("a follow's words in the headline count more than in the summary; a story with neither is not the follow's", () => {
  const items = [
    story("Orlen podnosi ceny paliw", "https://rmf24.pl/1", "RMF24", 3),
    story("Ceny na stacjach rosną", "https://onet.pl/2", "Onet", 1, { summary: "Orlen podał nowe stawki hurtowe." }),
    story("Sejm o budżecie", "https://tvn24.pl/3", "TVN24", 1),
  ];
  const list = shortlist([topic("Orlen", items, ["Orlen"], false)], new Set(), NOW, { perSource: 5 });
  assert.deepEqual(list.map((c) => c.url), ["https://rmf24.pl/1", "https://onet.pl/2"], "the headline match first, though older");
});

// ── One story, many publishers ───────────────────────────────────────────────────────────────────────

test("the same story across publishers is recognised by its headline, allowing for Polish endings", () => {
  assert.ok(same("Orlen podnosi ceny paliw na stacjach", "Orlen podnosi ceny paliw. Kierowcy zapłacą więcej"));
  assert.ok(same("Lewandowski strzelił dwa gole, Barcelona wygrała z Realem", "Dwa gole Lewandowskiego. Barcelona pokonała Real"));
  assert.ok(same("CPK: rząd zatwierdził harmonogram budowy lotniska", "Rząd zatwierdził harmonogram budowy CPK"));
  assert.ok(same("Bitcoin spadł poniżej 90 tys. dolarów", "Kurs bitcoina spada poniżej 90 tys. dolarów"));
  // Different stories that share words stay apart.
  assert.ok(!same("Orlen obniża ceny paliw", "Orlen podnosi ceny paliw"), "opposite news");
  assert.ok(!same("Lewandowski kontuzjowany, nie zagra z Realem", "Lewandowski strzelił dwa gole przeciwko Realowi"));
  assert.ok(!same("Bitcoin spadł poniżej 90 tys. dolarów", "Bitcoin spadł poniżej 80 tys. dolarów"), "different numbers");
  assert.ok(!same("Sejm o budżecie", "Senat o budżecie"));
  assert.ok(!same("Polsat 1", "Polsat 2"));
  assert.ok(sameWord("orlen", "orlenu") && sameWord("tesla", "tesli") && sameWord("cpk", "cpk") && !sameWord("cpk", "cpko"));
  assert.ok(!sameWord("orlen", "orlik") && !sameWord("90", "80"));
  assert.deepEqual(headlineTokens("Czy to już koniec? Nie, to dopiero początek 2026"), ["koniec", "dopiero", "poczatek", "2026"]);
});

test("the same story by its link: www, mobile and AMP addresses, tracking and a trailing slash don't make another story", () => {
  const key = storyKey("https://www.rmf24.pl/fakty/polska/news-cpk,nId,123");
  for (const u of ["https://rmf24.pl/fakty/polska/news-cpk,nId,123/", "http://m.rmf24.pl/fakty/polska/news-cpk,nId,123/amp?utm_source=rss",
    "https://www.rmf24.pl/fakty/polska/news-cpk,nId,123#comments"]) assert.equal(storyKey(u), key, u);
  assert.notEqual(storyKey("https://news.example/a?id=1"), storyKey("https://news.example/a?id=2"), "a query that names the article stays");
  const index = new StoryIndex<string>();
  index.add("a", "Pierwszy", "https://www.x.pl/a/");
  assert.equal(index.add("b", "Zupełnie inny tytuł", "https://x.pl/a"), 0);
  assert.equal(index.stories().length, 1);
});

test("one entry per story: the best publisher's, the others named; the story's follows merged; nothing repeated", () => {
  const poland = topic("Polska", [
    story("Orlen podnosi ceny paliw na stacjach", "https://tvn24.pl/orlen", "TVN24", 2, { lang: "pl" }),
    story("Orlen podnosi ceny paliw. Kierowcy zapłacą więcej", "https://onet.pl/orlen", "Onet", 1, { lang: "pl", imageUrl: "https://onet.pl/o.jpg" }),
    story("Sejm uchwalił budżet na 2027 rok", "https://tvn24.pl/sejm", "TVN24", 3, { lang: "pl" }),
  ]);
  const business = topic("Biznes", [
    story("Orlen podnosi ceny paliw od jutra", "https://interia.pl/orlen", "Interia", 1.5, { lang: "pl" }),
  ]);
  const list = shortlist([poland, business], new Set(), NOW, { language: "pl" });
  assert.equal(list.length, 2, "two stories, not four entries");
  const orlen = list.find((c) => c.title.startsWith("Orlen"))!;
  assert.equal(orlen.source, "Onet", "the copy with a picture is told");
  assert.deepEqual(orlen.alsoFrom.map((a) => a.source).sort(), ["Interia", "TVN24"]);
  assert.deepEqual(orlen.topics, ["Polska", "Biznes"]);
  const cards = buildFeed([poland, business], NOW, 40, "pl");
  assert.equal(cards.filter((c) => c.title.startsWith("Orlen")).length, 1, "one card");
  const card = cards.find((c) => c.title.startsWith("Orlen"))!;
  assert.deepEqual(card.alsoFrom?.map((a) => a.source).sort(), ["Interia", "TVN24"]);
  assert.ok(card.alsoFrom?.every((a) => a.url.startsWith("https://")), "each with the publisher's own link");
  assert.equal("alsoFrom" in cards.find((c) => c.title.startsWith("Sejm"))!, false, "no key when no one else carries it");
  // Sent before by any of its links: gone, with every copy.
  const hashOfTvn =shortlist([topic("x", [story("Orlen podnosi ceny paliw na stacjach", "https://tvn24.pl/orlen", "TVN24", 2)])], new Set(), NOW)[0]!.urlHash.toString("hex");
  const again = shortlist([poland, business], new Set([hashOfTvn]), NOW, { language: "pl" });
  assert.deepEqual(again.map((c) => c.title), ["Sejm uchwalił budżet na 2027 rok"], "the Onet and Interia copies of a sent story are not sent");
});

test("a word follow's story is told by a copy with the word in its headline, even from a publisher used already", () => {
  const items = [
    story("Orlen kupuje nową rafinerię w Czechach", "https://rmf24.pl/rafineria", "RMF24", 0.1),
    story("Orlen: ceny paliw w górę od jutra na stacjach", "https://rmf24.pl/ceny", "RMF24", 8),
    story("Ceny paliw w górę od jutra na stacjach", "https://interia.pl/ceny", "Interia", 7, { summary: "Orlen podał nowe ceny hurtowe." }),
  ];
  const list = shortlist([topic("Orlen", items, ["Orlen"], false)], new Set(), NOW, { limit: 5 });
  assert.equal(list.length, 2, "two stories");
  const prices = list.find((c) => c.url !== "https://rmf24.pl/rafineria")!;
  assert.equal(prices.title, "Orlen: ceny paliw w górę od jutra na stacjach", "not the copy that names Orlen only in its summary");
  assert.deepEqual(prices.alsoFrom.map((a) => a.source), ["Interia"]);
});

test("a story the person was told yesterday isn't told again from another publisher", () => {
  const today = topic("Polska", [
    story("Orlen podnosi ceny paliw. Kierowcy zapłacą więcej", "https://interia.pl/orlen", "Interia", 2),
    story("Lewandowski z rekordem w Lidze Mistrzów", "https://sport.pl/lewy", "Sport.pl", 3),
  ]);
  const list = shortlist([today], new Set(), NOW, { sentTitles: ["Orlen podnosi ceny paliw na stacjach"] });
  assert.deepEqual(list.map((c) => c.source), ["Sport.pl"]);
});

test("publishers alternate: each next story from the same one costs a little, so a busy publisher can't fill the top", () => {
  const items = [
    ...[1, 2, 3, 4].map((h) => story(`TVN24 wiadomość numer ${h}`, `https://tvn24.pl/${h}`, "TVN24", h)),
    story("Polsat wiadomość pierwsza", "https://polsatnews.pl/5", "Polsat News", 5),
    story("Polsat wiadomość druga", "https://polsatnews.pl/6", "Polsat News", 6),
  ];
  const list = shortlist([topic("Polska", items)], new Set(), NOW, { limit: 4 });
  assert.deepEqual(list.map((c) => c.source), ["TVN24", "Polsat News", "TVN24", "Polsat News"]);
  assert.ok(DIVERSITY_PENALTY > 0 && DIVERSITY_PENALTY < 1, "a mix, not a rule: a much fresher story still wins");
  assert.equal(shortlist([topic("Polska", items)], new Set(), NOW, { limit: 10 }).filter((c) => c.source === "TVN24").length, 3, "at most 3 per publisher");
});

test("the reader's language a little first: a Polish story three hours old before an English one an hour old, for a Polish reader", () => {
  const items = [
    story("Ukraine peace talks resume in Dublin", "https://bbc.co.uk/1", "BBC News", 1, { lang: "en" }),
    story("Rozmowy pokojowe w Dublinie wznowione", "https://rmf24.pl/1", "RMF24", 3, { lang: "pl" }),
  ];
  assert.deepEqual(shortlist([topic("Świat", items)], new Set(), NOW, { language: "pl" }).map((c) => c.source), ["RMF24", "BBC News"]);
  assert.deepEqual(shortlist([topic("World", items)], new Set(), NOW, { language: "en" }).map((c) => c.source), ["BBC News", "RMF24"]);
  assert.ok(LANGUAGE_BONUS < 1, "never more than a topic match is worth");
});

test("too old or dated in the future: left out (digest 36 h, feed 48 h, an hour ahead at most)", () => {
  const items = [
    story("Wczorajsza wiadomość rano", "https://x.pl/37", "X", 37), story("Sprzed dwóch dni prawie", "https://x.pl/47", "X", 47),
    story("Sprzed ponad dwóch dni", "https://x.pl/49", "X", 49), story("Z przyszłości", "https://x.pl/f", "X", -2),
    story("Zła data", "https://x.pl/bad", "X", 1, { publishedAt: "not a date" }),
  ];
  assert.deepEqual(shortlist([topic("t", items)], new Set(), NOW, { perSource: 9 }).map((c) => c.url), []);
  assert.deepEqual(buildFeed([topic("t", items)], NOW).map((c) => c.url), ["https://x.pl/37", "https://x.pl/47"]);
});

test("a cached feed keeps the last three days' stories (and undated ones), nothing older", () => {
  const items = [story("a", "https://x.pl/1", "X", 1), story("b", "https://x.pl/2", "X", FEED_KEEP_HOURS + 1), { ...story("c", "https://x.pl/3", "X"), publishedAt: null }];
  assert.deepEqual(keepRecent(items, NOW).map((i) => i.title), ["a", "c"]);
});

// ── Conditional fetches ──────────────────────────────────────────────────────────────────────────────

test("a validator from a publisher is sent back only if it is a plain header value", () => {
  assert.equal(validator('W/"abc-123"'), 'W/"abc-123"');
  assert.equal(validator("Thu, 13 Nov 2026 08:00:00 GMT"), "Thu, 13 Nov 2026 08:00:00 GMT");
  for (const bad of ["a\r\nX-Evil: 1", "ż", "x".repeat(201), "", "   ", 42, undefined]) assert.equal(validator(bad), undefined, String(bad));
});

test("an unchanged feed answers 304 to the validators it gave, with no body", async () => {
  const seen: Record<string, string | undefined>[] = [];
  const server = http.createServer((req, res) => {
    seen.push({ inm: req.headers["if-none-match"], ims: req.headers["if-modified-since"] });
    if (req.headers["if-none-match"] === '"v1"') { res.writeHead(304, { etag: '"v1"' }); res.end(); return; }
    res.writeHead(200, { "content-type": "application/rss+xml", etag: '"v1"', "last-modified": "Thu, 13 Nov 2026 08:00:00 GMT" });
    res.end("<rss><channel><title>T</title></channel></rss>");
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const url = new URL(`http://127.0.0.1:${(server.address() as { port: number }).port}/feed`);
  try {
    const first = await requestOnce(url, Date.now() + 2000, 1024 * 1024);
    assert.deepEqual([first.status, first.etag, first.lastModified], [200, '"v1"', "Thu, 13 Nov 2026 08:00:00 GMT"]);
    const second = await requestOnce(url, Date.now() + 2000, 1024 * 1024, undefined, { etag: first.etag, lastModified: first.lastModified });
    assert.deepEqual([second.status, second.text], [304, ""]);
    assert.deepEqual(seen, [{ inm: undefined, ims: undefined }, { inm: '"v1"', ims: "Thu, 13 Nov 2026 08:00:00 GMT" }]);
    await requestOnce(url, Date.now() + 2000, 1024 * 1024, undefined, { etag: "bad\r\nx: y" });
    assert.equal(seen.at(-1)!.inm, undefined, "a value that isn't a plain header is never sent");
  } finally {
    server.close();
  }
});

// ── Against the database: the reader, Daily news and the radar ───────────────────────────────────────

/** A publisher stand-in: counts fetches, can answer 304, can be slow. */
class Publishers implements FeedSource {
  feeds = new Map<string, NewsItem[]>();
  etags = new Map<string, string>();
  calls: { url: string; conditional?: Validators }[] = [];
  running = 0;
  maxRunning = 0;
  delayMs = 0;
  async fetchFeed(url: string, conditional?: Validators): Promise<FetchedFeed> {
    this.calls.push({ url, conditional });
    this.running++;
    this.maxRunning = Math.max(this.maxRunning, this.running);
    try {
      if (this.delayMs) await new Promise((r) => setTimeout(r, this.delayMs));
      const items = this.feeds.get(url);
      if (!items) throw new Error("404");
      const etag = this.etags.get(url);
      if (etag && conditional?.etag === etag) return { title: "", items: [], notModified: true };
      return { title: `Feed of ${new URL(url).hostname}`, items, etag };
    } finally {
      this.running--;
    }
  }
}

describe("news sources against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  const pubs = new Publishers();
  const news: NewsDeps = { feeds: pubs };

  before(async () => {
    db = await freshDb();
    ({ app } = await testApp(db, { news, radar: { enabled: true } }));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });
  beforeEach(async () => {
    pubs.feeds.clear();
    pubs.etags.clear();
    pubs.calls = [];
    pubs.maxRunning = 0;
    pubs.delayMs = 0;
    await db.query("DELETE FROM news_cache");
  });

  let users = 0;
  async function user(withPush = true) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.88.0.${++users}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    if (withPush) {
      await app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h,
        payload: { token: Math.random().toString(16).slice(2).padEnd(64, "c").slice(0, 64), environment: "sandbox" } });
    }
    return { accountId, h };
  }
  const counting = () => {
    let n = 0;
    const wrapped = { query: (...args: unknown[]) => { n++; return (db.query as (...a: unknown[]) => unknown)(...args); } } as unknown as Db;
    return { db: wrapped, queries: () => n };
  };

  test("a feed is fetched once per pass, and once in the process when two callers want it at the same time", async () => {
    const url = "https://www.rmf24.pl/fakty/polska/feed";
    pubs.feeds.set(url, [story("Orlen podnosi ceny paliw", "https://rmf24.pl/1", "x", 1)]);
    pubs.delayMs = 50;
    const digestPass = new FeedReader(db, pubs, { now: NOW });
    const radarPass = new FeedReader(db, pubs, { now: NOW });
    const [a, b, c] = await Promise.all([digestPass.read(url), radarPass.read(url), digestPass.read(url)]);
    assert.equal(pubs.calls.length, 1, "one request to the publisher");
    assert.deepEqual([a.items.length, b.items.length, c.items.length], [1, 1, 1]);
    assert.equal(digestPass.stats.fetched + radarPass.stats.fetched, 1);
    assert.equal(radarPass.stats.shared + digestPass.stats.shared, 1);
    assert.equal(digestPass.stats.feeds, 1, "read once by its pass, however many times asked");
    const later = new FeedReader(db, pubs, { now: NOW });
    await later.read(url);
    assert.deepEqual([pubs.calls.length, later.stats.fromCache], [1, 1], "fresh in the cache: no request");
  });

  test("a word follow's many feeds: one cache query, and never more than a few fetches at once", async () => {
    const urls = ALL_CATALOG_FEEDS.map((f) => f.url);
    for (const u of urls) pubs.feeds.set(u, [story(`Wiadomość z ${new URL(u).hostname}`, `${u}#1`, "x", 1)]);
    pubs.delayMs = 5;
    const reader = new FeedReader(db, pubs, { now: NOW });
    reader.preload(urls);
    await Promise.all(urls.map((u) => reader.read(u)));
    assert.equal(pubs.calls.length, urls.length);
    assert.ok(pubs.maxRunning <= FEED_FETCH_CONCURRENCY, `${pubs.maxRunning} at once`);
    assert.deepEqual(fetchSlots(), { active: 0, waiting: 0 }, "every slot handed back");
    const c = counting();
    const cachedReader = new FeedReader(c.db, pubs, { now: NOW });
    cachedReader.preload(urls);
    await Promise.all(urls.map((u) => cachedReader.read(u)));
    assert.equal(c.queries(), 1, "all rows in one query");
    assert.equal(cachedReader.stats.fromCache, urls.length);
  });

  test("a stale feed is asked \"changed since?\"; a 304 keeps the stories and the next read is from the cache", async () => {
    const url = "https://wiadomosci.onet.pl/.feed";
    pubs.feeds.set(url, [story("Sejm uchwalił budżet", "https://onet.pl/1", "x", 2), story("Stare", "https://onet.pl/old", "x", FEED_KEEP_HOURS + 5)]);
    pubs.etags.set(url, '"onet-1"');
    await new FeedReader(db, pubs, { now: NOW }).read(url);
    const row = await db.query<{ etag: string; items: NewsItem[] }>("SELECT etag, items FROM news_cache");
    assert.equal(row.rows[0]!.etag, '"onet-1"');
    assert.deepEqual(row.rows[0]!.items.map((i) => i.url), ["https://onet.pl/1"], "older stories are not cached");
    await db.query("UPDATE news_cache SET fetched_at = now() - interval '31 minutes'");
    const reader = new FeedReader(db, pubs, { now: NOW });
    const r = await reader.read(url);
    assert.deepEqual(pubs.calls.at(-1)!.conditional, { etag: '"onet-1"', lastModified: undefined });
    assert.equal(reader.stats.notModified, 1);
    assert.deepEqual([r.ok, r.items.map((i) => i.url)], [true, ["https://onet.pl/1"]]);
    const fresh = await db.query<{ fresh: boolean }>("SELECT fetched_at > now() - interval '1 minute' AS fresh FROM news_cache");
    assert.equal(fresh.rows[0]!.fresh, true);
    // A publisher that fails: the last good stories, said not ok; nothing asked conditionally after a failure.
    pubs.feeds.delete(url);
    await db.query("UPDATE news_cache SET fetched_at = now() - interval '31 minutes'");
    const failing = new FeedReader(db, pubs, { now: NOW });
    const f = await failing.read(url);
    assert.deepEqual([f.ok, f.items.length, failing.stats.failed], [false, 1, 1]);
    pubs.feeds.set(url, [story("Nowa", "https://onet.pl/2", "x", 1)]);
    await db.query("UPDATE news_cache SET fetched_at = now() - interval '31 minutes'");
    await new FeedReader(db, pubs, { now: NOW }).read(url);
    assert.equal(pubs.calls.at(-1)!.conditional, undefined);
  });

  test("Daily news tells a story once, from one publisher, and not again tomorrow from another", async () => {
    const { accountId, h } = await user();
    const poland = catalogById.get("poland")!;
    const byName = (n: string) => poland.feeds.find((f) => f.name === n)!.url;
    const t0 = new Date();
    const fresh = (title: string, url: string, h0: number) => ({ ...story(title, url, "x", 0), publishedAt: new Date(t0.getTime() - h0 * 3_600_000).toISOString() });
    pubs.feeds.set(byName("TVN24"), [fresh("Orlen podnosi ceny paliw na stacjach", "https://tvn24.pl/orlen", 2), fresh("Sejm uchwalił budżet na 2027 rok", "https://tvn24.pl/sejm", 3)]);
    pubs.feeds.set(byName("RMF24"), [fresh("Orlen podnosi ceny paliw. Kierowcy zapłacą więcej", "https://rmf24.pl/orlen", 1)]);
    pubs.feeds.set(byName("Onet"), [fresh("Orlen podnosi ceny paliw od jutra na stacjach", "https://onet.pl/orlen", 1.5)]);
    const put = await app.inject({ method: "PUT", url: "/v1/news/settings", headers: h, payload: {
      enabled: true, sendTime: "08:00", timezone: "Europe/Warsaw", channels: [], language: "pl", topics: [{ catalogId: "poland" }], feeds: [] } });
    assert.equal(put.statusCode, 200);
    const first = await buildDigest(db, news, accountId, "manual", t0);
    assert.equal(first.status, "ready");
    const items = await db.query<{ title: string; source: string }>("SELECT title, source FROM news_digest_items WHERE digest_id = $1 ORDER BY position", [first.digestId]);
    assert.equal(items.rows.filter((r) => r.title.startsWith("Orlen")).length, 1, "the Orlen story once");
    assert.equal(new Set(items.rows.map((r) => r.source)).size, items.rows.length, "from different publishers");
    // The next day the TVN24 and RMF24 copies have left the feeds; Interia carries it now.
    pubs.feeds.set(byName("TVN24"), []);
    pubs.feeds.set(byName("RMF24"), []);
    pubs.feeds.set(byName("Onet"), []);
    pubs.feeds.set(byName("Interia"), [fresh("Orlen podnosi ceny paliw. Kierowcy zapłacą więcej od jutra", "https://interia.pl/orlen", 1),
      fresh("Lewandowski z rekordem w Lidze Mistrzów", "https://interia.pl/lewy", 1)]);
    await db.query("DELETE FROM news_cache");
    const second = await buildDigest(db, news, accountId, "manual", t0);
    const next = await db.query<{ title: string }>("SELECT title FROM news_digest_items WHERE digest_id = $1", [second.digestId]);
    assert.deepEqual(next.rows.map((r) => r.title), ["Lewandowski z rekordem w Lidze Mistrzów"]);
  });

  test("the radar records a story once, though three publishers carry it, and logs counts only", async () => {
    const { accountId } = await user();
    const crypto = catalogById.get("crypto")!;
    const t0 = new Date();
    const fresh = (title: string, url: string, h0: number) => ({ ...story(title, url, "x", 0), publishedAt: new Date(t0.getTime() - h0 * 3_600_000).toISOString() });
    pubs.feeds.set(crypto.feeds[0]!.url, [fresh("SEC approves first spot Solana ETF", "https://coindesk.example/sol", 0.5)]);
    pubs.feeds.set(crypto.feeds[1]!.url, [fresh("SEC approves first spot Solana ETF in landmark decision", "https://cointelegraph.example/sol", 0.4)]);
    await saveAlerts(db, accountId, { language: "en", timeZone: "UTC", alerts: [
      { followKey: "topic:crypto", label: "Crypto", catalogId: "crypto", keywords: [], alertWords: ["ETF"], mode: "instant" }] },
    new Date(t0.getTime() - 2 * 3_600_000));
    await db.query("UPDATE radar_alerts SET next_check_at = $1 WHERE account_id = $2", [new Date(t0.getTime() - 1000), accountId]);
    const logs: object[] = [];
    const ctx: RadarContext = { db, news, push: new FakePush(), cipher: testCipher, quietHours: { start: 0, end: 0 }, now: () => t0,
      log: (msg, extra) => logs.push({ msg, extra }) };
    const counts = await runRadarPass(ctx);
    assert.equal(counts.found, 1, JSON.stringify(counts));
    assert.equal(counts.pushed, 1);
    assert.equal(counts.feeds, crypto.feeds.length, "each feed read once in the pass");
    assert.ok((counts.ms ?? 0) >= 1);
    // A third publisher's copy an hour later: the same story, not a new hit, no second push.
    pubs.feeds.set(crypto.feeds[2]!.url, [fresh("Solana ETF approved by the SEC, a first for spot crypto", "https://decrypt.example/sol", 0.1)]);
    pubs.feeds.set(crypto.feeds[3]!.url, [fresh("SEC approves first spot Solana ETF, analysts react", "https://theblock.example/sol", 0.1)]);
    await db.query("DELETE FROM news_cache");
    pubs.feeds.delete(crypto.feeds[0]!.url);
    pubs.feeds.delete(crypto.feeds[1]!.url);
    await db.query("UPDATE radar_alerts SET next_check_at = $1 WHERE account_id = $2", [new Date(t0.getTime() - 1000), accountId]);
    const again = await runRadarPass(ctx);
    assert.equal(again.found ?? 0, 0, JSON.stringify(again));
    assert.ok((again.same_story ?? 0) >= 1, JSON.stringify(again));
    const hits = await db.query("SELECT 1 FROM radar_hits WHERE account_id = $1", [accountId]);
    assert.equal(hits.rowCount, 1);
    for (const l of logs) assert.doesNotMatch(JSON.stringify(l), /Solana|ETF|Crypto|example/i, "counts, never words");
    for (const k of Object.keys(again)) assert.match(k, /^[a-z_]+$/);
  });

  test("the feed endpoint names the other publishers on a card, and its log line has counts only", async () => {
    const { h } = await user(false);
    const poland = catalogById.get("poland")!;
    const t0 = Date.now();
    const fresh = (title: string, url: string, h0: number): NewsItem => ({ title, url, source: "x", summary: "", publishedAt: new Date(t0 - h0 * 3_600_000).toISOString() });
    pubs.feeds.set(poland.feeds[0]!.url, [fresh("Rząd zatwierdził harmonogram budowy CPK", "https://tvn24.pl/cpk", 2)]);
    pubs.feeds.set(poland.feeds[4]!.url, [fresh("CPK: rząd zatwierdził harmonogram budowy lotniska", "https://rmf24.pl/cpk", 1)]);
    const lines: string[] = [];
    const original = console.log;
    console.log = (...args: unknown[]) => { lines.push(args.map(String).join(" ")); };
    let r;
    try {
      r = await app.inject({ method: "POST", url: "/v1/news/feed", headers: h, payload: { language: "pl", follows: [{ catalogId: "poland" }, { label: "CPK", keywords: ["CPK"] }] } });
    } finally {
      console.log = original;
    }
    assert.equal(r.statusCode, 200);
    const body = r.json() as { cards: { source: string; follows: string[]; alsoFrom?: { source: string; url: string }[] }[] };
    assert.equal(body.cards.length, 1, "one card for the story");
    assert.deepEqual(body.cards[0]!.follows, ["Polska", "CPK"]);
    assert.equal(body.cards[0]!.alsoFrom?.length, 1);
    assert.notEqual(body.cards[0]!.alsoFrom![0]!.source, body.cards[0]!.source);
    const line = lines.find((l) => l.includes("news feed built"));
    assert.ok(line, "a timing line");
    const logged = JSON.parse(line!) as Record<string, unknown>;
    assert.equal(logged.feeds, ALL_CATALOG_FEEDS.length, "every catalog feed read once for the words");
    assert.equal(typeof logged.ms, "number");
    assert.doesNotMatch(line!, /CPK|Polska|rmf24|tvn24|https?:/i, "counts, never words or addresses");
  });
});
