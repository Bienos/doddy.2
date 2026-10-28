import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { pushBody, smsBody } from "../src/news/compose.js";
import { runDueDigests, buildDigest, type NewsDeps } from "../src/news/digest.js";
import { itemImage, parseFeed, type NewsItem } from "../src/news/feeds.js";
import { buildFeed } from "../src/news/feed.js";
import { shortlist } from "../src/news/rank.js";
import { checkUrl, isPublicAddress, requestOnce, safeFetchText } from "../src/news/safeFetch.js";
import { nextRunAt } from "../src/news/schedule.js";
import { GNewsSearch, type FeedSource, type NewsSearch } from "../src/news/sources.js";
import http from "node:http";
import { ClaudeDigestWriter, OpenAIDigestWriter, validateLines, type DigestLine, type DigestWriter, type WriterInput } from "../src/news/writer.js";
import { dbSkip, FakePush, freshDb, testApp, testCipher } from "./helpers.js";
import { runWorkerLoop } from "../src/workerLoop.js";

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

test("entity bombs in a feed are refused, not expanded", () => {
  // Nested entities are not expanded recursively (billion laughs).
  let nested = '<!ENTITY a0 "lollollollol">';
  for (let i = 1; i <= 9; i++) nested += `<!ENTITY a${i} "${`&a${i - 1};`.repeat(10)}">`;
  const laughs = parseFeed(`<?xml version="1.0"?><!DOCTYPE rss [${nested}]><rss><channel><title>t</title>`
    + "<item><title>&a9;</title><link>https://x.com/1</link></item></channel></rss>", "x");
  assert.ok((laughs.items[0]?.title.length ?? 0) < 1000);
  // Many references to one large entity hit the parser's expansion cap (fast-xml-parser 5.x).
  const wide = `<?xml version="1.0"?><!DOCTYPE rss [<!ENTITY a0 "${"x".repeat(9_999)}">]><rss><channel><title>t</title>`
    + `<item><title>${"&a0;".repeat(400_000)}</title><link>https://x.com/1</link></item></channel></rss>`;
  assert.throws(() => parseFeed(wide, "x"), /limit exceeded/);
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
  // IPv6 forms that can carry an IPv4 address (IPv4-compatible, NAT64, 6to4, Teredo).
  for (const a of ["::7f00:1", "64:ff9b:1::a00:1", "2002:7f00:1::1", "2001:0:4136:e378::1"]) assert.equal(isPublicAddress(a), false, a);
  assert.equal(isPublicAddress("2606:4700:4700::1111"), true);
});

test("a feed that drips bytes is cut off at the overall deadline", { timeout: 5000 }, async () => {
  const server = http.createServer((_req, res) => {
    res.writeHead(200, { "content-type": "application/rss+xml" });
    const timer = setInterval(() => res.write("<"), 100); // never idle long enough for a socket timeout
    res.on("close", () => clearInterval(timer));
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const port = (server.address() as { port: number }).port;
  const started = Date.now();
  try {
    await assert.rejects(requestOnce(new URL(`http://127.0.0.1:${port}/feed`), Date.now() + 600, 2 * 1024 * 1024), /timeout/);
    assert.ok(Date.now() - started < 3000, "stopped near the deadline");
  } finally {
    server.closeAllConnections();
    server.close();
  }
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

test("a story's picture comes from the enclosure, media tags or the first <img>, https only", () => {
  const rss = `<?xml version="1.0"?><rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>TVN24</title>
    <item><title>One</title><link>https://tvn24.pl/1</link><pubDate>Fri, 09 Oct 2026 20:00:00 GMT</pubDate>
      <enclosure url="https://cdn.tvn24.pl/1.jpg" type="image/jpeg" length="1"/></item>
    <item><title>Two</title><link>https://tvn24.pl/2</link><pubDate>Fri, 09 Oct 2026 20:00:00 GMT</pubDate>
      <media:content url="https://cdn.tvn24.pl/2.jpg" medium="image"/></item>
    <item><title>Three</title><link>https://tvn24.pl/3</link><pubDate>Fri, 09 Oct 2026 20:00:00 GMT</pubDate>
      <description>&lt;p&gt;&lt;img src="https://cdn.tvn24.pl/3.jpg" alt=""&gt;Opis&lt;/p&gt;</description></item>
    <item><title>Four</title><link>https://tvn24.pl/4</link><pubDate>Fri, 09 Oct 2026 20:00:00 GMT</pubDate>
      <enclosure url="https://cdn.tvn24.pl/4.mp3" type="audio/mpeg"/><media:thumbnail url="http://cdn.tvn24.pl/4.jpg"/></item>
    </channel></rss>`;
  const r = parseFeed(rss, "x");
  assert.deepEqual(r.items.map((i) => i.imageUrl), ["https://cdn.tvn24.pl/1.jpg", "https://cdn.tvn24.pl/2.jpg", "https://cdn.tvn24.pl/3.jpg", undefined]);
  assert.equal(r.items[2]!.summary, "Opis", "the <img> never reaches the summary text");
  assert.equal("imageUrl" in r.items[3]!, false, "an audio enclosure and an http picture give no imageUrl key at all");
  const atom = `<feed xmlns="http://www.w3.org/2005/Atom"><title>Verge</title><entry><title>AI news</title>
    <link rel="alternate" href="https://theverge.com/x"/><link rel="enclosure" type="image/png" href="https://cdn.verge.com/x.png"/>
    <updated>2026-10-09T10:00:00Z</updated></entry></feed>`;
  assert.equal(parseFeed(atom, "x").items[0]!.imageUrl, "https://cdn.verge.com/x.png");
  assert.equal(itemImage({ enclosure: { "@url": "javascript:alert(1)", "@type": "image/png" } }, undefined), undefined);
});

test("feed cards: two days, newest first, up to six per publisher, keyword follows only where the words appear, no AI", () => {
  const poland = { label: "Polska", keywords: [], curated: true, items: [
    item("Sejm uchwalił budżet", "https://tvn24.pl/1?utm_source=rss", "TVN24", 1, "", ),
    item("Sejm uchwalił budżet", "https://tvn24.pl/1", "TVN24", 1),
    item("Pogoda na weekend", "https://tvn24.pl/2", "TVN24", 40),
    item("Sprzed trzech dni", "https://tvn24.pl/3", "TVN24", 60),
    ...[1, 2, 3, 4, 5, 6, 7].map((n) => item(`Polsat ${n}`, `https://polsatnews.pl/${n}`, "Polsat News", 2 + n)),
  ] };
  const kw = { label: "CPK", keywords: ["CPK", "lotnisko"], curated: false, items: [
    item("Rusza budowa CPK", "https://rp.pl/1", "Rzeczpospolita", 5), item("Mecz Legii", "https://rp.pl/2", "Rzeczpospolita", 4),
  ] };
  const undated: NewsItem = { title: "Bez daty", url: "https://x.pl/1", source: "X", summary: "", publishedAt: null };
  const cards = buildFeed([poland, kw, { label: "X", keywords: [], curated: true, items: [undated] }], NOW);
  const urls = cards.map((c) => c.url);
  assert.ok(urls.includes("https://tvn24.pl/2"), "40 hours old is still in a feed (48 h window)");
  assert.ok(!urls.includes("https://tvn24.pl/3"), "older than two days is out");
  assert.equal(urls.filter((u) => u.startsWith("https://tvn24.pl/1")).length, 1, "one card per story");
  assert.equal(cards.filter((c) => c.source === "Polsat News").length, 6);
  assert.ok(urls.includes("https://rp.pl/1") && !urls.includes("https://rp.pl/2"), "a keyword follow shows only matching stories");
  assert.ok(!urls.includes("https://x.pl/1"), "a story without a date is never a card");
  const times = cards.map((c) => Date.parse(c.publishedAt));
  assert.deepEqual(times, [...times].sort((a, b) => b - a), "newest first");
  const cpk = cards.find((c) => c.url === "https://rp.pl/1")!;
  assert.deepEqual(cpk.follows, ["CPK"]);
  assert.match(cpk.id, /^[0-9a-f]{64}$/);
  assert.equal(cpk.title, "Rusza budowa CPK", "the headline is the publisher's, word for word");
  assert.equal(buildFeed([poland], NOW, 3).length, 3, "the limit holds");
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

test("keyword search keeps only http(s) links (local stand-in for GNews)", async () => {
  const articles = [
    { title: "Good", description: null, url: "https://news.example/a", publishedAt: "2026-10-10T05:00:00Z", source: { name: "Ex" } },
    { title: "Script", description: null, url: "javascript:alert(1)", publishedAt: "2026-10-10T05:00:00Z", source: { name: "Ex" } },
    { title: "Broken", description: null, url: "not a url", publishedAt: "2026-10-10T05:00:00Z", source: { name: "Ex" } },
  ];
  const server = http.createServer((_req, res) => res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ articles })));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  try {
    const gnews = new GNewsSearch("k", 2000, `http://127.0.0.1:${(server.address() as { port: number }).port}`);
    const found = await gnews.search('"x"', "en", NOW);
    assert.deepEqual(found.map((f) => f.url), ["https://news.example/a"]);
  } finally {
    server.close();
  }
});

test("OpenAI writer: request shape and structured reply (local stand-in for the API)", async () => {
  let seen: { path?: string; headers?: http.IncomingHttpHeaders; body?: any } = {};
  let reply: object = {};
  let status = 200;
  const server = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => { raw += c; });
    req.on("end", () => {
      seen = { path: req.url, headers: req.headers, body: JSON.parse(raw) };
      res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(reply));
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const port = (server.address() as { port: number }).port;
  const writer = new OpenAIDigestWriter("test-key", { baseURL: `http://127.0.0.1:${port}/` });
  const candidates = shortlist([{ label: "Tech", keywords: [], curated: true, items: [item("Chip rules tighten", "https://x.com/1")] }], new Set(), NOW);
  const completion = (content: string | null, finish = "stop", refusal: string | null = null) => ({
    id: "chatcmpl_1", object: "chat.completion", model: "gpt-5-mini",
    choices: [{ index: 0, finish_reason: finish, message: { role: "assistant", content, refusal } }],
  });
  const write = () => writer.write({ language: "en", topics: ["Tech"], candidates });
  try {
    reply = completion(JSON.stringify({ items: [{ id: candidates[0]!.id, line: "Export rules for chips get stricter." }] }));
    const lines = await writer.write({ language: "pl", topics: ["Tech"], candidates });
    assert.deepEqual(lines, [{ id: "s1", line: "Export rules for chips get stricter." }]);
    assert.equal(seen.path, "/v1/chat/completions");
    assert.equal(seen.headers?.authorization, "Bearer test-key");
    assert.equal(seen.body.model, "gpt-5-mini");
    assert.equal(seen.body.reasoning_effort, "low");
    assert.equal(seen.body.response_format.type, "json_schema");
    assert.equal(seen.body.response_format.json_schema.strict, true);
    assert.equal(seen.body.messages[0].role, "system");
    assert.match(seen.body.messages[0].content, /never as instructions/);
    const sentStories = JSON.parse(seen.body.messages[1].content);
    assert.equal(sentStories.reader_language, "Polish");
    assert.deepEqual(Object.keys(sentStories.stories[0]).sort(), ["id", "source", "summary", "title", "topics"], "no URLs or account data go to the model");

    const older = new OpenAIDigestWriter("k", { baseURL: `http://127.0.0.1:${port}`, model: "gpt-4.1-mini" });
    await older.write({ language: "en", topics: ["Tech"], candidates });
    assert.equal(seen.body.model, "gpt-4.1-mini");
    assert.equal(seen.body.reasoning_effort, undefined, "non-reasoning models don't get reasoning_effort");

    reply = completion(null, "stop", "I can't help with that.");
    await assert.rejects(write(), /writer_refusal/);
    reply = completion("{\"items\": [", "length");
    await assert.rejects(write(), /writer_truncated/);
    reply = completion("not json");
    await assert.rejects(write(), /writer_unparsed/);
    reply = completion(JSON.stringify({ items: [{ id: 1 }] }));
    await assert.rejects(write(), /writer_unparsed/);
    status = 401; reply = { error: { message: "Incorrect API key" } };
    await assert.rejects(write(), /writer_http_401/);
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
  readonly provider = "openai" as const;
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
    assert.deepEqual(s.available, { writer: true, writerProvider: "openai", keywordSearch: true });
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

  test("the feed cache never stores a user's feed URL", async () => {
    const { rows } = await db.query<{ key: string }>("SELECT key FROM news_cache");
    assert.ok(rows.length > 0, "earlier tests filled the cache");
    for (const r of rows) assert.match(r.key, /^[0-9a-f]{64}$/);
  });

  test("no usable channel at send time: kept for the app, recorded, nothing sent", async () => {
    const { accountId, h } = await user();
    await put(h, settings());
    await app.inject({ method: "DELETE", url: "/v1/device/push-token", headers: h });
    feeds.feeds.get("https://feeds.bbci.co.uk/news/technology/rss.xml")!.push(item("Another", "https://bbc.co.uk/t4", "BBC", 1));
    await db.query("DELETE FROM news_cache");
    const r = await buildDigest(db, news, accountId, "manual", NOW);
    assert.deepEqual([r.status, r.errorCode], ["ready", "no_channel"]);
    const { rows: queued } = await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [accountId]);
    assert.equal(queued.length, 0, "nothing goes to the outbox");
    const list = (await app.inject({ method: "GET", url: "/v1/news/digests", headers: h })).json();
    assert.equal(list.digests[0].status, "ready");
    assert.ok(list.digests[0].items.length > 0, "the app can read it");
  });

  test("in the app only: no channels needed, no push token needed, digest readable", async () => {
    const { accountId, h } = await user(false);
    assert.equal((await put(h, settings({ channels: [] }))).statusCode, 200);
    const s = (await app.inject({ method: "GET", url: "/v1/news/settings", headers: h })).json();
    assert.deepEqual(s.channels, []);
    feeds.feeds.get("https://feeds.bbci.co.uk/news/technology/rss.xml")!.push(item("In-app story", "https://bbc.co.uk/t5", "BBC", 1));
    await db.query("DELETE FROM news_cache");
    const r = await buildDigest(db, news, accountId, "manual", NOW);
    assert.deepEqual([r.status, r.errorCode], ["ready", undefined]);
    const { rows: queued } = await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [accountId]);
    assert.equal(queued.length, 0);
    const list = (await app.inject({ method: "GET", url: "/v1/news/digests", headers: h })).json();
    assert.deepEqual([list.digests[0].status, list.digests[0].errorCode], ["ready", null]);
    assert.ok(list.digests[0].items.length > 0, "the app can read it");
  });

  test("feed check and send-now endpoints", async () => {
    const { h } = await user();
    const check = (url: string) => app.inject({ method: "POST", url: "/v1/news/feeds/check", headers: h, payload: { url } });
    assert.deepEqual((await check("https://my.blog/feed")).json(), { ok: true, title: "Feed", items: 1 });
    assert.equal((await check("https://missing.example/feed")).statusCode, 422);
    assert.equal((await check("http://localhost/feed")).statusCode, 400);
    assert.equal((await app.inject({ method: "POST", url: "/v1/news/send-now", headers: h })).json().error, "no_topics");
    await put(h, settings({ topics: [], feeds: ["https://my.blog/feed"] }));
    // send-now builds with the real clock (36 h window), so the post must be recent in real time,
    // not 3 hours before NOW (that went stale on 2026-10-11). The feed cache is cleared both ways
    // so neither this post nor the earlier tests' copy leaks across.
    const fixed = feeds.feeds.get("https://my.blog/feed")!;
    feeds.feeds.set("https://my.blog/feed", [{ ...fixed[0]!, publishedAt: new Date(Date.now() - 3 * 3_600_000).toISOString() }]);
    await db.query("DELETE FROM news_cache");
    try {
      const sent = (await app.inject({ method: "POST", url: "/v1/news/send-now", headers: h })).json();
      assert.equal(sent.status, "queued");
    } finally {
      feeds.feeds.set("https://my.blog/feed", fixed);
      await db.query("DELETE FROM news_cache");
    }
  });

  test("the feed endpoint: follows travel with the request, nothing of them is stored, cards carry pictures", async () => {
    const { h, accountId } = await user(false);
    const post = (payload: object) => app.inject({ method: "POST", url: "/v1/news/feed", headers: h, payload });
    assert.equal((await post({ follows: [] })).statusCode, 400);
    assert.equal((await post({ follows: [{ catalogId: "nope" }] })).statusCode, 400);
    const fixed = feeds.feeds.get("https://feeds.bbci.co.uk/news/technology/rss.xml")!;
    const fresh = (title: string, url: string, hoursAgo: number, extra: Partial<NewsItem> = {}): NewsItem =>
      ({ title, url, source: "BBC", summary: "", publishedAt: new Date(Date.now() - hoursAgo * 3_600_000).toISOString(), ...extra });
    feeds.feeds.set("https://feeds.bbci.co.uk/news/technology/rss.xml", [
      fresh("Chip export rules tighten", "https://bbc.co.uk/t1", 1, { imageUrl: "https://ichef.bbci.co.uk/t1.jpg" }),
      fresh("Espresso machines get smarter", "https://bbc.co.uk/t2", 3)]);
    await db.query("DELETE FROM news_cache");
    try {
      const r = await post({ language: "pl", follows: [{ catalogId: "technology" }, { label: "Kawa", keywords: ["espresso"] }] });
      assert.equal(r.statusCode, 200);
      const body = r.json() as { cards: { url: string; follows: string[]; imageUrl?: string }[]; keywordSearch: boolean; fetchedAt: string };
      assert.equal(body.keywordSearch, true);
      assert.deepEqual(body.cards.map((c) => c.url), ["https://bbc.co.uk/t1", "https://bbc.co.uk/t2"]);
      assert.equal(body.cards[0]!.imageUrl, "https://ichef.bbci.co.uk/t1.jpg");
      assert.deepEqual(body.cards[0]!.follows, ["Technologia"], "a catalog follow is labelled in the asked language");
      assert.deepEqual(body.cards[1]!.follows, ["Technologia", "Kawa"], "a story in a catalog follow that also matches a keyword follow says both");
      const stored = await db.query("SELECT count(*)::int AS n FROM news_topics WHERE account_id = $1", [accountId]);
      assert.equal(stored.rows[0].n, 0, "the feed never writes follows to the database");
      const kept = await db.query("SELECT count(*)::int AS n FROM news_settings WHERE account_id = $1", [accountId]);
      assert.equal(kept.rows[0].n, 0);
    } finally {
      feeds.feeds.set("https://feeds.bbci.co.uk/news/technology/rss.xml", fixed);
      await db.query("DELETE FROM news_cache");
    }
  });

  test("if queueing fails, the stories are not marked as sent", async () => {
    const { accountId, h } = await user();
    await put(h, settings());
    await db.query(`CREATE FUNCTION test_refuse_outbound() RETURNS trigger LANGUAGE plpgsql AS
      $$ BEGIN RAISE EXCEPTION 'refused for test'; END $$`);
    await db.query(`CREATE TRIGGER test_refuse BEFORE INSERT ON outbound_messages FOR EACH ROW
      WHEN (NEW.account_id = '${accountId}') EXECUTE FUNCTION test_refuse_outbound()`);
    try {
      const r = await buildDigest(db, news, accountId, "manual", NOW);
      assert.equal(r.status, "failed");
      for (const t of ["news_sent", "outbound_messages"]) {
        assert.equal((await db.query(`SELECT 1 FROM ${t} WHERE account_id = $1`, [accountId])).rowCount, 0, t);
      }
      assert.equal((await db.query("SELECT 1 FROM news_digest_items WHERE digest_id = $1", [r.digestId])).rowCount, 0);
    } finally {
      await db.query("DROP TRIGGER test_refuse ON outbound_messages; DROP FUNCTION test_refuse_outbound()");
    }
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

  // Last in this suite: the worker loop may build digests for any account still due.
  test("a slow digest does not hold back queued pushes", { timeout: 15_000 }, async () => {
    const { accountId, h } = await user();
    await put(h, settings({ topics: [], feeds: ["https://slow.example/feed"] }));
    await db.query("UPDATE news_settings SET next_run_at = now() - interval '1 minute' WHERE account_id = $1", [accountId]);
    let release!: () => void;
    const gate = new Promise<void>((r) => { release = r; });
    let fetching = false;
    const slowFeeds: FeedSource = {
      async fetchFeed() { fetching = true; await gate; return { title: "Slow", items: [] }; },
    };
    const push = new FakePush();
    let stop = false;
    const loop = runWorkerLoop(db, { push, cipher: testCipher, news: { feeds: slowFeeds } }, () => stop);
    const until = async (ok: () => boolean) => {
      const end = Date.now() + 5000;
      while (!ok() && Date.now() < end) await new Promise((r) => setTimeout(r, 100));
    };
    await until(() => fetching);
    // Queued only once the digest is stuck, so the old single loop could not have sent it.
    assert.equal((await app.inject({ method: "POST", url: "/v1/updates", headers: h,
      payload: { text: "PIN alert stand-in", channels: ["push"], idempotencyKey: "slow-digest" } })).statusCode, 202);
    const deadline = Date.now() + 5000;
    while (!push.sent.some((p) => p.body === "PIN alert stand-in") && Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(fetching, "the digest is still waiting on its feed");
    assert.ok(push.sent.some((p) => p.body === "PIN alert stand-in"), "push went out while the digest was stuck");
    stop = true;
    release();
    await loop;
  });
});
