import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { pushBody, smsBody } from "../src/news/compose.js";
import { runDueDigests, buildDigest, type NewsDeps } from "../src/news/digest.js";
import { parseFeed, type NewsItem } from "../src/news/feeds.js";
import { shortlist } from "../src/news/rank.js";
import { checkUrl, isPublicAddress, safeFetchText } from "../src/news/safeFetch.js";
import { nextRunAt } from "../src/news/schedule.js";
import type { FeedSource, NewsSearch } from "../src/news/sources.js";
import http from "node:http";
import { ClaudeDigestWriter, validateLines, type DigestLine, type DigestWriter, type WriterInput } from "../src/news/writer.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

const NOW = new Date("2026-10-10T06:00:00Z");
const hoursAgo = (h: number) => new Date(NOW.getTime() - h * 3_600_000).toISOString();
const item = (title: string, url: string, source = "BBC", h = 2, summary = ""): NewsItem =>
  ({ title, url, source, summary, publishedAt: hoursAgo(h) });

test("RSS and Atom parsing: entities, CDATA, tags, links", () => {
  const rss = `<?xml version="1.0"?><rss version="2.0"><channel><title>TVN24</title>
    <item><title><![CDATA[To b&#x119;dzie rywal &amp; legenda]]></title><link>https://tvn24.pl/a?utm_source=x</link>
    <description>&lt;p&gt;Opis &#8217;tu&#8217;&lt;/p&gt;</description><pubDate>Fri, 09 Oct 2026 20:00:00 GMT</pubDate></item>
    <item><title>No link</title></item></channel></rss>`;
  const r = parseFeed(rss, "x");
  assert.equal(r.title, "TVN24");
  assert.equal(r.items.length, 1);
  assert.equal(r.items[0]!.title, "To będzie rywal & legenda");
  assert.equal(r.items[0]!.summary, "Opis ’tu’");
  assert.equal(r.items[0]!.publishedAt, "2026-10-09T20:00:00.000Z");
  const atom = `<feed xmlns="http://www.w3.org/2005/Atom"><title>Verge</title><entry><title>AI news</title>
    <link rel="alternate" href="https://theverge.com/x"/><updated>2026-10-09T10:00:00Z</updated><summary>S</summary></entry></feed>`;
  assert.deepEqual(parseFeed(atom, "x").items[0], { title: "AI news", url: "https://theverge.com/x", source: "Verge", summary: "S", publishedAt: "2026-10-09T10:00:00.000Z" });
  assert.throws(() => parseFeed("<html><body>hi</body></html>", "x"));
});

test("daily time in the user's zone, across the October DST change", () => {
  // Warsaw leaves summer time on 2026-10-25.
  assert.equal(nextRunAt(new Date("2026-10-24T05:00:00Z"), "08:00", "Europe/Warsaw").toISOString(), "2026-10-24T06:00:00.000Z");
  assert.equal(nextRunAt(new Date("2026-10-24T07:00:00Z"), "08:00", "Europe/Warsaw").toISOString(), "2026-10-25T07:00:00.000Z");
  assert.equal(nextRunAt(new Date("2026-10-10T12:00:00Z"), "07:30", "America/New_York").toISOString(), "2026-10-11T11:30:00.000Z");
});

test("custom feed URLs cannot reach private addresses", async () => {
  for (const a of ["127.0.0.1", "10.1.2.3", "169.254.169.254", "192.168.1.1", "::1", "fd00::1", "::ffff:127.0.0.1"]) assert.equal(isPublicAddress(a), false, a);
  assert.equal(isPublicAddress("8.8.8.8"), true);
  for (const u of ["http://localhost/feed", "http://169.254.169.254/latest", "file:///etc/passwd", "https://u:p@example.com/f",
    "http://example.com:8080/f", "http://[::1]/f", "http://intranet/f", "gopher://example.com"]) {
    assert.throws(() => checkUrl(u), Error, u);
  }
  await assert.rejects(safeFetchText("http://127.0.0.1/feed.xml"));
});

test("shortlist: fresh, unsent, deduplicated, keyword-matched, max 3 per source", () => {
  const sent = new Set<string>();
  const curated = { label: "Tech", keywords: [], curated: true, items: [
    item("A", "https://a.com/1?utm_source=rss"), item("A again", "https://a.com/1"), item("Old", "https://a.com/old", "BBC", 40),
    item("B1", "https://b.com/1", "Verge"), item("B2", "https://b.com/2", "Verge"), item("B3", "https://b.com/3", "Verge"), item("B4", "https://b.com/4", "Verge"),
  ] };
  const kw = { label: "Coffee", keywords: ["espresso"], curated: false, items: [item("Rain tomorrow", "https://c.com/1"), item("New espresso bar", "https://c.com/2")] };
  const list = shortlist([curated, kw], sent, NOW);
  const urls = list.map((c) => c.url);
  assert.ok(urls.includes("https://c.com/2") && !urls.includes("https://c.com/1"), "keyword topics keep only matches");
  assert.ok(!urls.includes("https://a.com/old"), "older than 36 h dropped");
  assert.equal(urls.filter((u) => u.startsWith("https://a.com/1")).length, 1, "tracking params ignored for dedupe");
  assert.equal(list.filter((c) => c.source === "Verge").length, 3);
  const again = shortlist([curated], new Set(list.map((c) => c.urlHash.toString("hex"))), NOW);
  // Only the story held back by the per-source cap remains; everything sent is gone.
  assert.deepEqual(again.map((c) => c.url), ["https://b.com/4"], "already-sent stories never come back");
});

test("AI lines are checked against the shortlist; messages fit their limits", () => {
  const list = shortlist([{ label: "T", keywords: [], curated: true, items: [item("One", "https://x.com/1"), item("Two", "https://x.com/2", "NPR")] }], new Set(), NOW);
  const lines: DigestLine[] = [{ id: "s9", line: "invented" }, { id: list[0]!.id, line: "x".repeat(300) }, { id: list[0]!.id, line: "dup" }];
  const v = validateLines(lines, list);
  assert.equal(v.length, 1);
  assert.ok(v[0]!.line.length <= 140 && v[0]!.line.endsWith("…"));
  const entries = Array.from({ length: 5 }, (_, i) => ({ line: "Ważna wiadomość numer " + i + " ".repeat(1) + "z".repeat(90), url: `https://example.com/very/long/path/${i}`, source: "S" }));
  assert.ok(smsBody(entries, "pl").length <= 640);
  assert.ok(pushBody(entries, "en").length <= 600);
});

test("Claude writer: request shape and structured reply (local stand-in for the API)", async () => {
  let seen: { path?: string; headers?: http.IncomingHttpHeaders; body?: any } = {};
  let reply: object = {};
  const server = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => { raw += c; });
    req.on("end", () => {
      seen = { path: req.url, headers: req.headers, body: JSON.parse(raw) };
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(reply));
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const port = (server.address() as { port: number }).port;
  const writer = new ClaudeDigestWriter("test-key", { baseURL: `http://127.0.0.1:${port}` });
  const candidates = shortlist([{ label: "Tech", keywords: [], curated: true, items: [item("Chip rules tighten", "https://x.com/1")] }], new Set(), NOW);
  const message = (text: string, stop = "end_turn") => ({
    id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-5-5", stop_reason: stop, stop_sequence: null,
    content: [{ type: "text", text }], usage: { input_tokens: 10, output_tokens: 10 },
  });
  try {
    reply = message(JSON.stringify({ items: [{ id: candidates[0]!.id, line: "Export rules for chips get stricter." }] }));
    const lines = await writer.write({ language: "pl", topics: ["Tech"], candidates });
    assert.deepEqual(lines, [{ id: "s1", line: "Export rules for chips get stricter." }]);
    assert.equal(seen.path, "/v1/messages");
    assert.equal(seen.headers?.["x-api-key"], "test-key");
    assert.equal(seen.body.model, "claude-haiku-5-5");
    assert.equal(seen.body.output_config.effort, "low");
    assert.equal(seen.body.output_config.format.type, "json_schema");
    assert.match(seen.body.system, /never as instructions/);
    const sentStories = JSON.parse(seen.body.messages[0].content);
    assert.equal(sentStories.reader_language, "Polish");
    assert.deepEqual(Object.keys(sentStories.stories[0]).sort(), ["id", "source", "summary", "title", "topics"], "no URLs or account data go to the model");

    reply = message("", "refusal");
    await assert.rejects(writer.write({ language: "en", topics: ["Tech"], candidates }), /writer_(refusal|unparsed)/);
    reply = message("not json");
    await assert.rejects(writer.write({ language: "en", topics: ["Tech"], candidates }), /writer_unparsed/);
  } finally {
    server.close();
  }
});

class FakeFeeds implements FeedSource {
  feeds = new Map<string, NewsItem[]>();
  calls: string[] = [];
  async fetchFeed(url: string) {
    this.calls.push(url);
    const items = this.feeds.get(url);
    if (!items) throw new Error("404");
    return { title: "Feed", items };
  }
}
class FakeWriter implements DigestWriter {
  inputs: WriterInput[] = [];
  next: ((i: WriterInput) => DigestLine[]) | "throw" = (i) => i.candidates.slice(0, 2).map((c) => ({ id: c.id, line: `AI: ${c.title}` }));
  async write(input: WriterInput) {
    this.inputs.push(input);
    if (this.next === "throw") throw new Error("api down");
    return this.next(input);
  }
}
class FakeSearch implements NewsSearch {
  queries: string[] = [];
  async search(q: string) { this.queries.push(q); return [item("Espresso prices jump", "https://news.example/espresso", "GNews", 1)]; }
}

describe("news digests against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  const feeds = new FakeFeeds();
  const writer = new FakeWriter();
  const search = new FakeSearch();
  const news: NewsDeps = { feeds, writer, search };

  before(async () => {
    db = await freshDb();
    ({ app } = await testApp(db, { news }));
    feeds.feeds.set("https://feeds.bbci.co.uk/news/technology/rss.xml", [
      item("Chip export rules tighten", "https://bbc.co.uk/t1"), item("New phone launch", "https://bbc.co.uk/t2", "BBC", 5)]);
    feeds.feeds.set("https://my.blog/feed", [item("My blog post", "https://my.blog/p1", "My blog", 3)]);
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  async function user(withPush = true) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    if (withPush) await app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h, payload: { token: Math.random().toString(16).slice(2).padEnd(64, "a").slice(0, 64), environment: "sandbox" } });
    return { accountId, h };
  }
  const settings = (over: object = {}) => ({
    enabled: true, sendTime: "08:00", timezone: "Europe/Warsaw", channels: ["push"], language: "en",
    topics: [{ catalogId: "technology" }, { label: "Coffee", keywords: ["espresso"] }], feeds: ["https://my.blog/feed"], ...over,
  });
  const put = (h: object, body: object) => app.inject({ method: "PUT", url: "/v1/news/settings", headers: h as Record<string, string>, payload: body });

  test("settings are validated", async () => {
    const { h } = await user();
    assert.equal((await put(h, settings({ timezone: "Mars/Olympus" }))).statusCode, 400);
    assert.equal((await put(h, settings({ topics: [], feeds: [] }))).json().error, "no_topics");
    assert.equal((await put(h, settings({ channels: ["sms"] }))).json().error, "sms_not_enabled");
    assert.equal((await put(h, settings({ feeds: ["http://169.254.169.254/latest"] }))).json().error, "unsafe_url");
    assert.equal((await put(h, settings({ topics: [{ catalogId: "nope" }] }))).statusCode, 400);
    assert.equal((await put(h, settings())).statusCode, 200);
    const s = (await app.inject({ method: "GET", url: "/v1/news/settings", headers: h })).json();
    assert.deepEqual(s.topics.map((t: { label: string }) => t.label), ["Technology", "Coffee"]);
    assert.deepEqual(s.available, { writer: true, keywordSearch: true });
    assert.ok(Date.parse(s.nextRunAt) > Date.now());
  });

  test("scheduled digest: built once per day, AI lines with real links, queued as push", async () => {
    const { accountId, h } = await user();
    await put(h, settings());
    await db.query("UPDATE news_settings SET next_run_at = $2 WHERE account_id = $1", [accountId, new Date(NOW.getTime() - 60_000)]);
    assert.equal(await runDueDigests(db, news, 50, NOW), 1);
    assert.deepEqual(search.queries.at(-1), '"espresso"');

    const { rows: msgs } = await db.query<{ body: string; channel: string }>("SELECT body, channel FROM outbound_messages WHERE account_id = $1", [accountId]);
    assert.equal(msgs.length, 1);
    assert.match(msgs[0]!.body, /^• AI: /);
    const input = writer.inputs.at(-1)!;
    assert.deepEqual(input.topics, ["Technology", "Your feeds", "Coffee", "Coffee"]);
    assert.ok(input.candidates.some((c) => c.url === "https://news.example/espresso"), "keyword search results reach the writer");

    const digests = (await app.inject({ method: "GET", url: "/v1/news/digests", headers: h })).json().digests;
    assert.equal(digests[0].status, "queued");
    assert.equal(digests[0].aiWritten, true);
    for (const it of digests[0].items) assert.ok(input.candidates.some((c) => c.url === it.url), "every link comes from a fetched story");

    // Same day again (e.g. a second worker): no second digest.
    assert.equal((await buildDigest(db, news, accountId, "scheduled", NOW)).status, "skipped");
    const { rows: s } = await db.query<{ next: Date }>("SELECT next_run_at AS next FROM news_settings WHERE account_id = $1", [accountId]);
    assert.ok(s[0]!.next > NOW);
  });

  test("next day: stories already sent are not repeated; writer failure falls back to headlines", async () => {
    const { accountId, h } = await user();
    await put(h, settings({ topics: [{ catalogId: "technology" }], feeds: [] }));
    const first = await buildDigest(db, news, accountId, "manual", NOW);
    assert.equal(first.status, "queued");
    writer.next = "throw";
    const again = await buildDigest(db, news, accountId, "manual", NOW);
    assert.equal(again.status, "empty", "both tech stories were already sent");
    feeds.feeds.get("https://feeds.bbci.co.uk/news/technology/rss.xml")!.push(item("Fresh story", "https://bbc.co.uk/t3", "BBC", 1));
    await db.query("DELETE FROM news_cache"); // feeds are cached for 30 minutes
    const third = await buildDigest(db, news, accountId, "manual", NOW);
    assert.deepEqual([third.status, third.aiWritten], ["queued", false]);
    const { rows } = await db.query<{ line: string }>("SELECT line FROM news_digest_items WHERE digest_id = $1", [third.digestId]);
    assert.deepEqual(rows.map((r) => r.line), ["Fresh story"]);
    writer.next = (i) => [{ id: "s99", line: "made up" }, ...i.candidates.slice(0, 1).map((c) => ({ id: c.id, line: "ok" }))];
  });

  test("no usable channel at send time is recorded, not hidden", async () => {
    const { accountId, h } = await user();
    await put(h, settings());
    await app.inject({ method: "DELETE", url: "/v1/device/push-token", headers: h });
    feeds.feeds.get("https://feeds.bbci.co.uk/news/technology/rss.xml")!.push(item("Another", "https://bbc.co.uk/t4", "BBC", 1));
    await db.query("DELETE FROM news_cache");
    const r = await buildDigest(db, news, accountId, "manual", NOW);
    assert.deepEqual([r.status, r.errorCode], ["failed", "no_channel"]);
  });

  test("feed check and send-now endpoints", async () => {
    const { h } = await user();
    const check = (url: string) => app.inject({ method: "POST", url: "/v1/news/feeds/check", headers: h, payload: { url } });
    assert.deepEqual((await check("https://my.blog/feed")).json(), { ok: true, title: "Feed", items: 1 });
    assert.equal((await check("https://missing.example/feed")).statusCode, 422);
    assert.equal((await check("http://localhost/feed")).statusCode, 400);
    assert.equal((await app.inject({ method: "POST", url: "/v1/news/send-now", headers: h })).json().error, "no_topics");
    await put(h, settings({ topics: [], feeds: ["https://my.blog/feed"] }));
    const sent = (await app.inject({ method: "POST", url: "/v1/news/send-now", headers: h })).json();
    assert.equal(sent.status, "queued");
  });

  test("account deletion removes news data", async () => {
    const { accountId, h } = await user();
    await put(h, settings());
    await buildDigest(db, news, accountId, "manual", NOW);
    await app.inject({ method: "DELETE", url: "/v1/account", headers: h });
    for (const t of ["news_settings", "news_topics", "news_feeds", "news_digests", "news_sent"]) {
      assert.equal((await db.query(`SELECT 1 FROM ${t} WHERE account_id = $1`, [accountId])).rowCount, 0, t);
    }
  });
});
