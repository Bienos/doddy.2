// On my radar (decision 2026-11-10-radar-alerts): keyword matching that allows for Polish endings, the
// feed's fair share per follow, own feeds, per-follow sources, and the alerts a person lets the server check.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { ALL_CATALOG_FEEDS, CATALOG, catalogById } from "../src/news/catalog.js";
import type { NewsDeps } from "../src/news/digest.js";
import { buildFeed } from "../src/news/feed.js";
import type { NewsItem } from "../src/news/feeds.js";
import { matchesKeyword, matchedKeywords } from "../src/news/match.js";
import {
  dailyBody, instantBody, matchingStories, PUSHES_PER_DAY, runRadarPass, saveAlerts, type RadarBody, type RadarContext,
} from "../src/news/radar.js";
import { shortlist } from "../src/news/rank.js";
import type { FeedSource } from "../src/news/sources.js";
import { reserveWriter } from "../src/news/usage.js";
import type { DigestLine, DigestWriter, WriterInput } from "../src/news/writer.js";
import { dbSkip, FakePush, freshDb, testApp, testCipher } from "./helpers.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(readFileSync(path.resolve(here, "../../../../schemas/fixtures/radar_match_v1.json"), "utf8")) as {
  cases: { text: string; keyword: string; match: boolean }[];
};

const T0 = new Date();
const hoursAgo = (h: number, from = T0) => new Date(from.getTime() - h * 3_600_000).toISOString();
const story = (title: string, url: string, source = "Feed", h = 1, summary = ""): NewsItem => ({ title, url, source, summary, publishedAt: hoursAgo(h) });

test("keyword matching allows for Polish and English endings (shared fixture with DoddyCore)", () => {
  for (const c of fixture.cases) {
    assert.equal(matchesKeyword(c.text, c.keyword), c.match, `${c.keyword} in "${c.text}"`);
  }
  assert.deepEqual(matchedKeywords("Rynek kryptowalut: Bitcoina kupują banki", ["bitcoin", "ETF", "kryptowaluty"]), ["bitcoin", "kryptowaluty"]);
});

test("the owner's crypto follow: words find stories in other publishers, not only exact spellings", () => {
  // Before 10 Nov a keyword follow matched a plain substring, so "kryptowaluty" missed "kryptowalut".
  const pool = { label: "Krypto", keywords: ["kryptowaluty"], curated: false, items: [
    story("Rynek kryptowalut w panice po decyzji Fed", "https://bankier.example/1", "Bankier.pl", 2),
    story("Sejm o podatkach", "https://tvn24.example/2", "TVN24", 1),
  ] };
  const cards = buildFeed([pool], T0);
  assert.deepEqual(cards.map((c) => c.url), ["https://bankier.example/1"]);
});

test("crypto has more than one publisher, every catalog feed has a short name, and the catalog lists each feed once", () => {
  const crypto = catalogById.get("crypto")!;
  assert.ok(crypto.feeds.length >= 4, "crypto had only CoinDesk");
  assert.ok(crypto.feeds.some((f) => f.name === "Bitcoin.pl"), "one Polish crypto publisher");
  for (const t of CATALOG) for (const f of t.feeds) {
    assert.match(f.url, /^https:\/\//, f.url);
    assert.ok(f.name.length > 1 && f.name.length <= 40, f.url);
  }
  assert.equal(new Set(ALL_CATALOG_FEEDS.map((f) => f.url)).size, ALL_CATALOG_FEEDS.length);
});

test("the feed gives every follow its best few before a busy topic fills the rest", () => {
  const busy = { label: "Polska", keywords: [], curated: true, items:
    Array.from({ length: 60 }, (_, i) => story(`Wiadomość ${i}`, `https://p${i % 10}.example/${i}`, `Wydawca ${i % 10}`, 0.1 + i * 0.01)) };
  const quiet = { label: "Krypto", keywords: [], curated: true, items: [
    story("Bitcoin falls", "https://coindesk.example/1", "CoinDesk", 30), story("Ether rises", "https://coindesk.example/2", "CoinDesk", 31)] };
  const cards = buildFeed([busy, quiet], T0, 10);
  assert.equal(cards.length, 10);
  assert.equal(cards.filter((c) => c.follows.includes("Krypto")).length, 2, "the quiet follow's two stories make the cut");
});

test("alert stories: only after the alert was turned on, and only those mentioning its words", () => {
  const items = [
    story("Tesla cuts prices in Poland", "https://x.example/1", "X", 1),
    story("Tesla opens a factory", "https://x.example/2", "X", 30),
    story("Ford recalls cars", "https://x.example/3", "X", 1),
    story("Tesla's recall widens", "https://x.example/4", "X", 2, "A recall of 10,000 cars"),
  ];
  const candidates = shortlist([{ label: "Tesla", keywords: ["Tesla"], curated: false, items }], new Set(), T0, { limit: 50, perSource: 50, windowHours: 48 });
  const watchFrom = new Date(T0.getTime() - 5 * 3_600_000);
  const any = matchingStories({ keywords: ["Tesla"], alert_words: [], watch_from: watchFrom }, candidates);
  assert.deepEqual(any.map((m) => m.candidate.url).sort(), ["https://x.example/1", "https://x.example/4"], "older than the alert: never");
  const recall = matchingStories({ keywords: ["Tesla"], alert_words: ["recall"], watch_from: watchFrom }, candidates);
  assert.deepEqual(recall.map((m) => m.candidate.url), ["https://x.example/4"]);
  assert.deepEqual(recall[0]!.matched, ["recall"]);
});

test("push texts: the publisher's headline quoted and named, short, and an AI line says so", () => {
  const one = instantBody("Tesla", [{ title: "Tesla cuts prices", source: "Reuters" }], "en");
  assert.equal(one, "On your radar · Tesla: “Tesla cuts prices” (Reuters)");
  const three = instantBody("CPK", [{ title: "Budowa CPK ruszyła", source: "TVN24" }, { title: "b", source: "x" }, { title: "c", source: "y" }], "pl");
  assert.equal(three, "Na radarze · CPK: „Budowa CPK ruszyła” (TVN24)\n+2 więcej w Doddy");
  assert.ok(instantBody("x", [{ title: "t".repeat(2000), source: "s" }], "en").length <= 600);
  const daily = dailyBody("Krypto", 5, ["Bitcoin spada (CoinDesk)", "ETF zatwierdzony (Decrypt)"], true, "pl");
  assert.equal(daily, "Na radarze · Krypto, dziś: 5 artykułów\n• Bitcoin spada (CoinDesk)\n• ETF zatwierdzony (Decrypt)\n+3 więcej w Doddy\nZdania napisała AI z nagłówków wydawców.");
  assert.match(dailyBody("Krypto", 3, ["a"], false, "pl"), /3 artykuły/);
  assert.match(dailyBody("Krypto", 22, [], false, "pl"), /22 artykuły/);
  assert.match(dailyBody("Krypto", 12, [], false, "pl"), /12 artykułów/);
  assert.doesNotMatch(dailyBody("Tesla", 1, ["Tesla cuts prices (Reuters)"], false, "en"), /AI/);
});

class FakeFeeds implements FeedSource {
  feeds = new Map<string, NewsItem[]>();
  async fetchFeed(url: string) {
    const items = this.feeds.get(url);
    if (!items) throw new Error("404");
    return { title: `Feed of ${new URL(url).hostname}`, items };
  }
}

class FakeWriter implements DigestWriter {
  readonly provider = "anthropic" as const;
  inputs: WriterInput[] = [];
  next: ((i: WriterInput) => DigestLine[]) | "throw" = (i) => [
    { id: i.candidates[0]!.id, line: `Summary of ${i.candidates[0]!.title}` }, { id: "s999", line: "Made up story" }];
  async write(input: WriterInput) {
    this.inputs.push(input);
    if (this.next === "throw") throw new Error("down");
    return this.next(input);
  }
}

describe("radar against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let off: FastifyInstance;
  const feeds = new FakeFeeds();
  const writer = new FakeWriter();
  const news: NewsDeps = { feeds };
  const logs: { msg: string; extra?: object }[] = [];
  const COINDESK = catalogById.get("crypto")!.feeds[0]!.url;
  const OWN = "https://blog.example.com/feed.xml";

  before(async () => {
    db = await freshDb();
    ({ app } = await testApp(db, { news, radar: { enabled: true } }));
    ({ app: off } = await testApp(db, { news }));
  });
  after(async () => {
    await app?.close();
    await off?.close();
    await db?.end();
  });
  beforeEach(async () => {
    feeds.feeds.clear();
    logs.length = 0;
    await db.query("DELETE FROM news_cache");
    await db.query("DELETE FROM radar_alerts"); // each test counts only its own alerts' passes
  });

  let users = 0;
  async function user(withPush = true) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.77.0.${++users}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    if (withPush) {
      await app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h,
        payload: { token: Math.random().toString(16).slice(2).padEnd(64, "b").slice(0, 64), environment: "sandbox" } });
    }
    return { accountId, h };
  }
  const ctx = (over: Partial<RadarContext> = {}): RadarContext => ({
    db, news, push: new FakePush(), cipher: testCipher, now: () => T0, log: (msg, extra) => logs.push({ msg, extra }), ...over,
  });
  const body = (alerts: RadarBody["alerts"], timeZone = "UTC"): RadarBody => ({ language: "en", timeZone, alerts });
  const radarPushes = async (accountId: string) =>
    (await db.query("SELECT id FROM outbound_messages WHERE account_id = $1 AND idempotency_key LIKE 'radar:%'", [accountId])).rowCount;
  // Every alert due now, as if its time had come.
  const dueNow = () => db.query("UPDATE radar_alerts SET next_check_at = $1", [new Date(T0.getTime() - 1000)]);
  // Outside quiet hours whatever the clock says: an empty window.
  const noQuiet = { start: 0, end: 0 };

  test("while the switch is off, nothing new is stored, but turning alerts off always works", async () => {
    const { h } = await user();
    const put = (payload: object) => off.inject({ method: "PUT", url: "/v1/news/radar", headers: h, payload });
    const one = { followKey: "words:tesla", label: "Tesla", keywords: ["Tesla"], mode: "instant" };
    assert.equal((await put({ language: "en", timeZone: "Europe/Warsaw", alerts: [one] })).statusCode, 503);
    const r = await put({ language: "en", timeZone: "Europe/Warsaw", alerts: [] });
    assert.equal(r.statusCode, 200);
    assert.equal((r.json() as { available: boolean }).available, false);
  });

  test("alerts are validated: https public feeds only, words for as-it-happens, a time for daily, ten at most", async () => {
    const { h } = await user();
    const put = (alerts: object[]) => app.inject({ method: "PUT", url: "/v1/news/radar", headers: h, payload: { language: "pl", timeZone: "Europe/Warsaw", alerts } });
    const base = { followKey: "k", label: "L", mode: "daily", dailyTime: "08:00" };
    for (const bad of [
      { ...base, feedUrl: "http://blog.example.com/feed" },
      { ...base, feedUrl: "https://127.0.0.1/feed" },
      { ...base, feedUrl: "https://localhost/feed" },
      { ...base, catalogId: "crypto", mode: "instant", dailyTime: undefined },
      { ...base, keywords: ["Tesla"], dailyTime: undefined },
      { ...base, catalogId: "nope" },
      { ...base },
      { ...base, catalogId: "crypto", feedUrl: OWN },
    ]) assert.equal((await put([bad])).statusCode, 400, JSON.stringify(bad));
    const many = Array.from({ length: 11 }, (_, i) => ({ ...base, followKey: `k${i}`, keywords: ["abc"] }));
    assert.equal((await put(many)).statusCode, 400);
    assert.equal((await put([{ ...base, keywords: ["ab"] }, { ...base, keywords: ["cd"] }])).statusCode, 400, "the same follow twice");
    const ok = await put([{ ...base, catalogId: "crypto", alertWords: ["ETF"] }, { followKey: "words:cpk", label: "CPK", keywords: ["CPK"], mode: "instant" }]);
    assert.equal(ok.statusCode, 200);
    const state = ok.json() as { available: boolean; alerts: { followKey: string; mode: string; dailyTime: string | null }[] };
    assert.equal(state.available, true);
    assert.deepEqual(state.alerts.map((a) => [a.followKey, a.mode, a.dailyTime]), [["k", "daily", "08:00"], ["words:cpk", "instant", null]]);
  });

  test("as it happens: one push for a new matching story, quoted and named; never twice; older stories never", async () => {
    const { accountId } = await user();
    feeds.feeds.set(COINDESK, [
      story("SEC approves a bitcoin ETF", "https://coindesk.example/etf", "x", 0.5, "Spot ETF"),
      story("Bitcoin mining in Texas", "https://coindesk.example/mining", "x", 0.4),
      story("Old ETF story", "https://coindesk.example/old", "x", 30),
    ]);
    await saveAlerts(db, accountId, body([{ followKey: "topic:crypto", label: "Crypto", catalogId: "crypto", keywords: [], alertWords: ["ETF"], mode: "instant" }]),
      new Date(T0.getTime() - 2 * 3_600_000));
    await dueNow();
    const c = ctx({ quietHours: noQuiet });
    const counts = await runRadarPass(c);
    assert.equal(counts.found, 1, JSON.stringify({ counts, logs }));
    assert.equal(counts.pushed, 1);
    const queued = await db.query("SELECT body_ciphertext, id FROM outbound_messages WHERE account_id = $1 AND idempotency_key LIKE 'radar:%'", [accountId]);
    assert.equal(queued.rowCount, 1);
    const text = testCipher.decrypt(queued.rows[0].body_ciphertext, `${accountId}:outbound:${queued.rows[0].id}`);
    assert.equal(text, "On your radar · Crypto: “SEC approves a bitcoin ETF” (CoinDesk)");
    // The next pass finds the same story: no second row, no second push.
    await dueNow();
    const again = await runRadarPass(c);
    assert.equal(again.found ?? 0, 0);
    assert.equal(await radarPushes(accountId), 1);
    const hits = await db.query("SELECT url, told_by FROM radar_hits WHERE account_id = $1", [accountId]);
    assert.deepEqual(hits.rows, [{ url: "https://coindesk.example/etf", told_by: "push" }]);
    for (const l of logs) assert.doesNotMatch(JSON.stringify(l), /ETF|bitcoin|Crypto/i, "logs carry counts, never words");
  });

  test("quiet hours hold a push; a story that waited too long is listed in the app only", async () => {
    const { accountId } = await user();
    feeds.feeds.set(COINDESK, [story("ETF day", "https://coindesk.example/q1", "x", 0.2)]);
    await saveAlerts(db, accountId, body([{ followKey: "topic:crypto", label: "Crypto", catalogId: "crypto", keywords: [], alertWords: ["ETF"], mode: "instant" }]),
      new Date(T0.getTime() - 3_600_000));
    await dueNow();
    const m = T0.getUTCHours() * 60 + T0.getUTCMinutes();
    const quiet = { start: (m + 1440 - 30) % 1440, end: (m + 30) % 1440 };
    const held = await runRadarPass(ctx({ quietHours: quiet }));
    assert.equal(held.held_quiet_hours, 1, JSON.stringify(held));
    assert.equal(await radarPushes(accountId), 0);
    assert.equal((await db.query("SELECT 1 FROM radar_hits WHERE account_id = $1 AND told_at IS NULL", [accountId])).rowCount, 1);
    // Seven hours later, quiet hours over: too old to push, shown in the app.
    const later = new Date(T0.getTime() + 7 * 3_600_000);
    await db.query("UPDATE radar_alerts SET next_check_at = $1 WHERE account_id = $2", [T0, accountId]);
    const after7 = await runRadarPass(ctx({ quietHours: noQuiet, now: () => later }));
    assert.equal(after7.app_only, 1, JSON.stringify(after7));
    assert.equal(await radarPushes(accountId), 0);
    const row = await db.query("SELECT told_by FROM radar_hits WHERE account_id = $1", [accountId]);
    assert.equal(row.rows[0].told_by, "app");
  });

  test("no notification possible: the story is recorded for the app and nothing is queued", async () => {
    const { accountId, h } = await user(false);
    feeds.feeds.set(COINDESK, [story("ETF news", "https://coindesk.example/np", "x", 0.2)]);
    await saveAlerts(db, accountId, body([{ followKey: "topic:crypto", label: "Crypto", catalogId: "crypto", keywords: [], alertWords: ["ETF"], mode: "instant" }]),
      new Date(T0.getTime() - 3_600_000));
    await dueNow();
    const counts = await runRadarPass(ctx({ quietHours: noQuiet }));
    assert.equal(counts.app_only, 1, JSON.stringify(counts));
    assert.equal(await radarPushes(accountId), 0);
    const state = (await app.inject({ method: "GET", url: "/v1/news/radar", headers: h })).json() as {
      push: boolean; hits: { id: string; title: string; source: string; toldBy: string; seen: boolean; followKey: string }[];
    };
    assert.equal(state.push, false);
    assert.equal(state.hits.length, 1);
    assert.deepEqual([state.hits[0]!.title, state.hits[0]!.source, state.hits[0]!.toldBy, state.hits[0]!.seen, state.hits[0]!.followKey],
      ["ETF news", "CoinDesk", "app", false, "topic:crypto"]);
    const seen = await app.inject({ method: "POST", url: "/v1/news/radar/seen", headers: h, payload: { ids: [state.hits[0]!.id] } });
    assert.equal((seen.json() as { marked: number }).marked, 1);
    const after = (await app.inject({ method: "GET", url: "/v1/news/radar", headers: h })).json() as { hits: { seen: boolean }[] };
    assert.equal(after.hits[0]!.seen, true);
  });

  test("at most a few pushes a day per account; past it, stories go to the app list", async () => {
    const { accountId } = await user();
    const words = Array.from({ length: PUSHES_PER_DAY + 2 }, (_, i) => `slowo${i}x`);
    feeds.feeds.set(OWN, words.map((w, i) => story(`News about ${w}`, `https://blog.example.com/${i}`, "x", 0.1)));
    await saveAlerts(db, accountId, body(words.map((w) => ({ followKey: `feed:${w}`, label: w, feedUrl: OWN, keywords: [], alertWords: [w], mode: "instant" as const }))),
      new Date(T0.getTime() - 3_600_000));
    await dueNow();
    const c = ctx({ quietHours: noQuiet });
    await runRadarPass(c);
    assert.equal(await radarPushes(accountId), PUSHES_PER_DAY);
    const appOnly = await db.query("SELECT count(*)::int AS n FROM radar_hits WHERE account_id = $1 AND told_by = 'app'", [accountId]);
    assert.equal(appOnly.rows[0].n, 2);
  });

  test("once a day: a summary at the person's time; AI lines only for real stories, said to be AI; late means not sent", async () => {
    const { accountId } = await user();
    feeds.feeds.set(COINDESK, [story("Bitcoin falls", "https://coindesk.example/d1", "x", 0.5, "BTC down 5%"),
      story("Ether rises", "https://coindesk.example/d2", "x", 0.6)]);
    const withWriter: NewsDeps = { feeds, writer };
    await saveAlerts(db, accountId, body([{ followKey: "topic:crypto", label: "Crypto", catalogId: "crypto", keywords: [], alertWords: [], mode: "daily", dailyTime: "08:00" }]),
      new Date(T0.getTime() - 3_600_000));
    // Collect first (summary not due yet): stories are recorded, nobody is told.
    await dueNow();
    await db.query("UPDATE radar_alerts SET next_tell_at = $1 WHERE account_id = $2", [new Date(T0.getTime() + 3_600_000), accountId]);
    const collected = await runRadarPass(ctx({ news: withWriter }));
    assert.equal(collected.found, 2);
    assert.equal(await radarPushes(accountId), 0);
    // The summary's time comes.
    await db.query("UPDATE radar_alerts SET next_check_at = $1, next_tell_at = $1 WHERE account_id = $2", [new Date(T0.getTime() - 60_000), accountId]);
    const told = await runRadarPass(ctx({ news: withWriter }));
    assert.equal(told.summarised, 1, JSON.stringify(told));
    const q = await db.query("SELECT body_ciphertext, id FROM outbound_messages WHERE account_id = $1 AND idempotency_key LIKE 'radar:%'", [accountId]);
    const text = testCipher.decrypt(q.rows[0].body_ciphertext, `${accountId}:outbound:${q.rows[0].id}`);
    assert.match(text, /^On your radar · Crypto, today: 2 stories\n• Summary of .+ \(CoinDesk\)\n\+1 more in Doddy\nLines written by AI from the publishers' headlines\.$/);
    assert.doesNotMatch(text, /Made up story/, "a line for a story that isn't in the list is dropped");
    const next = await db.query("SELECT next_tell_at FROM radar_alerts WHERE account_id = $1", [accountId]);
    assert.ok(next.rows[0].next_tell_at > T0, "the next summary is tomorrow");
    // A summary three hours late (the server slept) is not sent.
    feeds.feeds.set(COINDESK, [story("Solana news", "https://coindesk.example/d3", "x", 0.2)]);
    await db.query("DELETE FROM news_cache");
    await db.query("UPDATE radar_alerts SET next_check_at = $1, next_tell_at = $2 WHERE account_id = $3",
      [new Date(T0.getTime() - 60_000), new Date(T0.getTime() - 3 * 3_600_000), accountId]);
    const late = await runRadarPass(ctx({ news: withWriter }));
    assert.equal(late.daily_too_late, 1, JSON.stringify(late));
    assert.equal(await radarPushes(accountId), 1);
  });

  test("the daily summary's writer counts against the digests' daily caps; past one, the headlines", async () => {
    const { accountId } = await user();
    feeds.feeds.set(COINDESK, [story("Bitcoin falls", "https://coindesk.example/c1", "x", 0.5)]);
    const caps = { perAccount: 1, perServer: 1000, newAccountPool: 1000 };
    const capped: NewsDeps = { feeds, writer, writerCaps: caps };
    // The account's one digest by the writer today has gone (its scheduled digest, say).
    assert.equal(await reserveWriter(db, accountId, caps, T0), "ok");
    await saveAlerts(db, accountId, body([{ followKey: "topic:crypto", label: "Crypto", catalogId: "crypto", keywords: [], alertWords: [], mode: "daily", dailyTime: "08:00" }]),
      new Date(T0.getTime() - 3_600_000));
    await db.query("UPDATE radar_alerts SET next_check_at = $1, next_tell_at = $1 WHERE account_id = $2", [new Date(T0.getTime() - 60_000), accountId]);
    const asked = writer.inputs.length;
    const told = await runRadarPass(ctx({ news: capped }));
    assert.equal(told.summarised, 1, JSON.stringify(told));
    assert.equal(writer.inputs.length, asked, "the writer wasn't asked");
    assert.ok(logs.some((l) => l.msg === "radar summary writer skipped, daily limit"));
    const q = await db.query("SELECT body_ciphertext, id FROM outbound_messages WHERE account_id = $1 AND idempotency_key LIKE 'radar:%'", [accountId]);
    const text = testCipher.decrypt(q.rows[0].body_ciphertext, `${accountId}:outbound:${q.rows[0].id}`);
    assert.equal(text, "On your radar · Crypto, today: 1 story\n• Bitcoin falls (CoinDesk)");
  });

  test("turning an alert off deletes it and its stories; so does deleting the account", async () => {
    const { accountId, h } = await user();
    feeds.feeds.set(COINDESK, [story("ETF", "https://coindesk.example/x1", "x", 0.2)]);
    await saveAlerts(db, accountId, body([{ followKey: "topic:crypto", label: "Crypto", catalogId: "crypto", keywords: [], alertWords: ["ETF"], mode: "instant" }]),
      new Date(T0.getTime() - 3_600_000));
    await dueNow();
    await runRadarPass(ctx({ quietHours: noQuiet }));
    assert.equal((await db.query("SELECT 1 FROM radar_hits WHERE account_id = $1", [accountId])).rowCount, 1);
    const offNow = await app.inject({ method: "PUT", url: "/v1/news/radar", headers: h, payload: { language: "en", timeZone: "UTC", alerts: [] } });
    assert.equal(offNow.statusCode, 200);
    for (const t of ["radar_alerts", "radar_hits"]) assert.equal((await db.query(`SELECT 1 FROM ${t} WHERE account_id = $1`, [accountId])).rowCount, 0, t);
    await saveAlerts(db, accountId, body([{ followKey: "words:cpk", label: "CPK", keywords: ["CPK"], alertWords: [], mode: "instant" }]), T0);
    await app.inject({ method: "DELETE", url: "/v1/account", headers: h });
    assert.equal((await db.query("SELECT 1 FROM radar_alerts WHERE account_id = $1", [accountId])).rowCount, 0);
  });

  test("the feed: an own https feed, a word follow found across the catalog, each follow's sources and count", async () => {
    const { h, accountId } = await user(false);
    feeds.feeds.set(COINDESK, [story("Bitcoin hits a record", "https://coindesk.example/r1", "x", 1)]);
    feeds.feeds.set(catalogById.get("business")!.feeds[2]!.url, [story("Kurs Bitcoina bije rekord", "https://bankier.example/b1", "x", 2)]);
    feeds.feeds.set(OWN, [story("My post", "https://blog.example.com/p1", "My blog", 3)]);
    const post = (payload: object) => app.inject({ method: "POST", url: "/v1/news/feed", headers: h, payload });
    assert.equal((await post({ follows: [{ label: "Blog", feedUrl: "http://blog.example.com/feed.xml" }] })).statusCode, 400, "http refused");
    assert.equal((await post({ follows: [{ label: "Blog", feedUrl: "https://10.0.0.1/feed.xml" }] })).statusCode, 400, "private refused");
    const r = await post({ language: "pl", follows: [{ catalogId: "crypto" }, { label: "Bitcoin", keywords: ["bitcoin"] }, { label: "Blog", feedUrl: OWN }] });
    assert.equal(r.statusCode, 200);
    const page = r.json() as {
      cards: { url: string; source: string; follows: string[] }[];
      follows: { label: string; sources: { name: string; ok: boolean }[]; searchedFeeds?: number; cards: number }[];
    };
    const byUrl = new Map(page.cards.map((c) => [c.url, c]));
    assert.deepEqual(byUrl.get("https://coindesk.example/r1")?.follows, ["Kryptowaluty", "Bitcoin"]);
    assert.equal(byUrl.get("https://coindesk.example/r1")?.source, "CoinDesk", "a catalog story carries the publisher's short name");
    assert.deepEqual(byUrl.get("https://bankier.example/b1")?.follows, ["Bitcoin"], "found in a feed the person doesn't follow, with its Polish ending");
    assert.deepEqual(byUrl.get("https://blog.example.com/p1")?.follows, ["Blog"]);
    const crypto = page.follows.find((f) => f.label === "Kryptowaluty")!;
    assert.deepEqual(crypto.sources.map((s) => [s.name, s.ok]),
      catalogById.get("crypto")!.feeds.map((f) => [f.name, f.url === COINDESK]), "each publisher, and whether it answered");
    assert.equal(crypto.cards, 1);
    const words = page.follows.find((f) => f.label === "Bitcoin")!;
    assert.deepEqual(words.sources, []);
    assert.equal(words.searchedFeeds, ALL_CATALOG_FEEDS.length + 1);
    assert.deepEqual(page.follows.find((f) => f.label === "Blog")!.sources, [{ name: "Feed of blog.example.com", ok: true }]);
    assert.equal((await db.query("SELECT 1 FROM radar_alerts WHERE account_id = $1", [accountId])).rowCount, 0, "the feed stores no follow");
  });

  test("the catalog lists each topic's publishers", async () => {
    const { h } = await user(false);
    const r = await app.inject({ method: "GET", url: "/v1/news/catalog?lang=pl", headers: h });
    const crypto = (r.json() as { topics: { id: string; label: string; sources: string[] }[] }).topics.find((t) => t.id === "crypto")!;
    assert.equal(crypto.label, "Kryptowaluty");
    assert.deepEqual(crypto.sources, ["CoinDesk", "Cointelegraph", "Decrypt", "The Block", "Bitcoin.pl"]);
  });
});
