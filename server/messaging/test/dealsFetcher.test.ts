// The polite fetcher (SHOPPING.md §1.2) against a fake web: robots.txt for DoddyBot and `*`, content signals,
// blocks never worked around, HTTPS only, the size cap and the time limit. Nothing here reaches the network.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { DODDY_BOT_UA, looksLikeChallenge, parseRobots, PoliteFetcher, robotsAllows, safeHttpsFetch } from "../src/deals/fetcher.js";
import { FakeWeb, ROBOTS } from "./dealsFakes.js";

const allows = (robots: string, path: string, token = "doddybot") => robotsAllows(parseRobots(robots), token, path).allowed;

describe("robots.txt", () => {
  test("the four chains' files as seen on 2026-10-24: what Doddy may and may not fetch", () => {
    assert.equal(allows(ROBOTS.biedronka, "/pl/w-tym-tygodniu"), true);
    assert.equal(allows(ROBOTS.biedronka, "/pl/search?q=maslo"), false);
    assert.equal(allows(ROBOTS.lidl, "/c/nasze-gazetki/s10008614"), true);
    assert.equal(allows(ROBOTS.lidl, "/q/search?q=maslo"), false, "Disallow: *search?q=*");
    assert.equal(allows(ROBOTS.lidl, "/c/x?id=1"), false, "Disallow: *id=*");
    assert.equal(allows(ROBOTS.lidl, "/c/x?productId=1"), true, "robots.txt paths are case-sensitive");
    assert.equal(allows(ROBOTS.dino, "/gazetki/lista/standard"), true);
    assert.equal(allows(ROBOTS.dino, "/wyszukiwarka/maslo"), false);
    assert.equal(allows(ROBOTS.dinoApi, "/media/pdf/promo_news_pages/page_349_4.webp"), true, "only comments: no rules");
    assert.equal(allows(ROBOTS.rossmann, "/promocje?Search=pieluchy"), true);
    assert.equal(allows(ROBOTS.rossmann, "/?q=pieluchy"), false);
    assert.equal(allows(ROBOTS.rossmann, "/promocje?utm_source=x"), false, "Disallow: /*?utm_source=");
    assert.equal(allows(ROBOTS.rossmann, "/promocje", "mj12bot"), false, "a group naming another bot doesn't apply to DoddyBot");
    assert.equal(allows(ROBOTS.rossmannGazetka, "/gazetka-rossmann-22-28-pazdziernika/"), false, "gazetka.rossmann.pl: Disallow: /");
  });

  test("a group naming DoddyBot replaces `*`; longest rule wins, Allow wins a tie; $ anchors; robots.txt itself is allowed", () => {
    const txt = "User-agent: *\nDisallow: /\n\nUser-agent: DoddyBot\nDisallow: /private\nAllow: /private/leaflets\nDisallow: /*.pdf$\n";
    assert.equal(allows(txt, "/gazetki"), true);
    assert.equal(allows(txt, "/gazetki", "otherbot"), false);
    assert.equal(allows(txt, "/private/x"), false);
    assert.equal(allows(txt, "/private/leaflets/1"), true);
    assert.equal(allows(txt, "/a/b.pdf"), false);
    assert.equal(allows(txt, "/a/b.pdf?x=1"), true);
    assert.equal(allows("User-agent: *\nDisallow: /x\nAllow: /x\n", "/x"), true);
    assert.equal(allows("User-agent: *\nDisallow: /\n", "/robots.txt"), true);
    assert.equal(allows("Disallow: /\n", "/x"), true, "rules outside any group bind nobody");
  });

  test("Content-Signal lines are read per group", () => {
    const g = parseRobots("User-agent: *\nContent-Signal: search=yes, ai-train=no, ai-input=no\nAllow: /\n");
    assert.deepEqual(robotsAllows(g, "doddybot", "/x").signals, { search: "yes", "ai-train": "no", "ai-input": "no" });
  });
});

describe("PoliteFetcher", () => {
  const page = { headers: { "content-type": "text/html" }, body: "<html><body>ok</body></html>" };

  test("sends DoddyBot's user agent and the accept type, no cookie; reads robots.txt once per host", async () => {
    const web = new FakeWeb().robots("https://shop.example", "User-agent: *\nDisallow: /private\n").on("https://shop.example/a", page).on("https://shop.example/b", page);
    const f = new PoliteFetcher({ fetch: web.fetch });
    const r = await f.fetchPage("https://shop.example/a", { accept: "text/html" });
    assert.equal(r.kind, "ok");
    assert.equal(r.kind === "ok" && r.body.toString(), page.body);
    assert.equal(r.kind === "ok" && r.finalUrl, "https://shop.example/a");
    await f.fetchPage("https://shop.example/b");
    assert.deepEqual(web.requests.map((q) => q.url), ["https://shop.example/robots.txt", "https://shop.example/a", "https://shop.example/b"]);
    const sent = web.requests[1]!.headers;
    assert.equal(sent["user-agent"], DODDY_BOT_UA);
    assert.equal(DODDY_BOT_UA, "DoddyBot/1.0 (+https://doddy.lol/bot)");
    assert.equal(sent.accept, "text/html");
    assert.equal(sent.cookie, undefined);
  });

  test("a fetch robots.txt disallows is not made", async () => {
    const web = new FakeWeb().robots("https://shop.example", ROBOTS.rossmannGazetka).on("https://shop.example/a", page);
    const r = await new PoliteFetcher({ fetch: web.fetch }).fetchPage("https://shop.example/a");
    assert.deepEqual(r, { kind: "disallowed", reason: "robots" });
    assert.equal(web.hits("https://shop.example/a"), 0);
  });

  test("robots.txt: 404 allows everything, 5xx or no answer disallows everything (RFC 9309), 429 is a block", async () => {
    const ok = new FakeWeb().on("https://a.example/x", page);
    assert.equal((await new PoliteFetcher({ fetch: ok.fetch }).fetchPage("https://a.example/x")).kind, "ok");
    const down = new FakeWeb().on("https://b.example/robots.txt", { status: 503 }).on("https://b.example/x", page);
    assert.deepEqual(await new PoliteFetcher({ fetch: down.fetch }).fetchPage("https://b.example/x"), { kind: "disallowed", reason: "robots_unreachable" });
    assert.equal(down.hits("https://b.example/x"), 0);
    const limited = new FakeWeb().on("https://c.example/robots.txt", { status: 429 }).on("https://c.example/x", page);
    assert.deepEqual(await new PoliteFetcher({ fetch: limited.fetch }).fetchPage("https://c.example/x"), { kind: "blocked", reason: "robots_http_429" });
    assert.equal(limited.hits("https://c.example/x"), 0);
  });

  test("ai-input=no refuses a fetch meant for the model, and only that one", async () => {
    const web = new FakeWeb().robots("https://img.example", "User-agent: *\nContent-Signal: ai-input=no\n").on("https://img.example/p.png", page);
    const f = new PoliteFetcher({ fetch: web.fetch });
    assert.deepEqual(await f.fetchPage("https://img.example/p.png", { aiInput: true }), { kind: "disallowed", reason: "content_signal" });
    assert.equal(web.hits("https://img.example/p.png"), 0);
    assert.equal((await f.fetchPage("https://img.example/p.png")).kind, "ok");
  });

  test("401, 403, 429 and challenge pages are blocked, once, never retried", async () => {
    for (const [status, reason] of [[401, "http_401"], [403, "http_403"], [429, "http_429"]] as const) {
      const web = new FakeWeb().on("https://s.example/x", { status, body: "no" });
      assert.deepEqual(await new PoliteFetcher({ fetch: web.fetch }).fetchPage("https://s.example/x"), { kind: "blocked", reason });
      assert.equal(web.hits("https://s.example/x"), 1);
    }
    const cf = new FakeWeb().on("https://s.example/x", { status: 403, headers: { "cf-mitigated": "challenge" } });
    assert.deepEqual(await new PoliteFetcher({ fetch: cf.fetch }).fetchPage("https://s.example/x"), { kind: "blocked", reason: "challenge" });
    const moment = new FakeWeb().on("https://s.example/x", { status: 503, headers: { "content-type": "text/html" }, body: "<html><head><title>Just a moment...</title></head></html>" });
    assert.deepEqual(await new PoliteFetcher({ fetch: moment.fetch }).fetchPage("https://s.example/x"), { kind: "blocked", reason: "challenge" });
    const wall = new FakeWeb().on("https://s.example/x", { headers: { "content-type": "text/html" }, body: "<title>Dostęp zablokowany</title>" });
    assert.deepEqual(await new PoliteFetcher({ fetch: wall.fetch }).fetchPage("https://s.example/x"), { kind: "blocked", reason: "challenge" });
    const outage = new FakeWeb().on("https://s.example/x", { status: 503, body: "down" });
    assert.deepEqual(await new PoliteFetcher({ fetch: outage.fetch }).fetchPage("https://s.example/x"), { kind: "failed", reason: "http_503" });
  });

  test("the ordinary Cloudflare beacon on a normal page is not a challenge (Dino, Rossmann and Żabka carry it)", () => {
    const html = Buffer.from('<html><head><title>Gazetki - Dino</title></head><body><script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script></body></html>');
    assert.equal(looksLikeChallenge(new Headers({ "content-type": "text/html" }), html), false);
  });

  test("HTTPS only, on redirects too; redirects are followed (at most 3) and each hop's robots.txt is checked", async () => {
    const f = (web: FakeWeb) => new PoliteFetcher({ fetch: web.fetch });
    assert.deepEqual(await f(new FakeWeb()).fetchPage("http://shop.example/x"), { kind: "failed", reason: "not_https" });
    assert.deepEqual(await f(new FakeWeb()).fetchPage("https://127.0.0.1/x"), { kind: "failed", reason: "unsafe_url" });
    assert.deepEqual(await f(new FakeWeb()).fetchPage("https://localhost/x"), { kind: "failed", reason: "unsafe_url" });
    const toHttp = new FakeWeb().on("https://a.example/x", { status: 301, headers: { location: "http://a.example/y" } });
    assert.deepEqual(await f(toHttp).fetchPage("https://a.example/x"), { kind: "failed", reason: "redirect_not_https" });
    const hop = new FakeWeb().on("https://a.example/x", { status: 307, headers: { location: "https://b.example/y" } })
      .robots("https://b.example", "User-agent: *\nDisallow: /y\n");
    assert.deepEqual(await f(hop).fetchPage("https://a.example/x"), { kind: "disallowed", reason: "robots" });
    assert.equal(hop.hits("https://b.example/y"), 0);
    const loop = new FakeWeb().onPrefix("https://a.example/hop/", (u) => ({ status: 302, headers: { location: `/hop/${Number(u.pathname.split("/")[2]) + 1}` } }));
    assert.deepEqual(await f(loop).fetchPage("https://a.example/hop/0"), { kind: "failed", reason: "too_many_redirects" });
    assert.equal(loop.hits("https://a.example/hop/"), 4, "the first request and three redirects");
  });

  test("the 3 MB cap: a declared or a streamed body over it fails", async () => {
    const big = Buffer.alloc(3 * 1024 * 1024 + 1, 0x61);
    const declared = new FakeWeb().on("https://a.example/x", { headers: { "content-length": String(big.length) }, body: big });
    assert.deepEqual(await new PoliteFetcher({ fetch: declared.fetch }).fetchPage("https://a.example/x"), { kind: "failed", reason: "too_large" });
    const streamed = new FakeWeb().on("https://a.example/x", { body: big }); // Response doesn't set content-length for a buffer body
    assert.deepEqual(await new PoliteFetcher({ fetch: streamed.fetch }).fetchPage("https://a.example/x"), { kind: "failed", reason: "too_large" });
    const exact = new FakeWeb().on("https://a.example/x", { body: Buffer.alloc(3 * 1024 * 1024, 0x61) });
    assert.equal((await new PoliteFetcher({ fetch: exact.fetch }).fetchPage("https://a.example/x")).kind, "ok");
  });

  test("the time limit covers the whole fetch, and the caller can stop it", async () => {
    const hang = (_u: URL, init: RequestInit) => new Promise<never>((_, reject) => {
      init.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
    });
    const web = new FakeWeb().on("https://a.example/x", hang as never);
    const started = Date.now();
    assert.deepEqual(await new PoliteFetcher({ fetch: web.fetch, timeoutMs: 50 }).fetchPage("https://a.example/x"), { kind: "failed", reason: "timeout" });
    assert.ok(Date.now() - started < 2000);
    const caller = new AbortController();
    const p = new PoliteFetcher({ fetch: web.fetch, timeoutMs: 10_000 }).fetchPage("https://a.example/x", { signal: caller.signal });
    setTimeout(() => caller.abort(), 20);
    assert.deepEqual(await p, { kind: "failed", reason: "aborted" });
  });

  test("the default transport refuses plain http and addresses that resolve to this machine", async () => {
    await assert.rejects(safeHttpsFetch("http://example.com/", {}));
    await assert.rejects(safeHttpsFetch("https://localhost:1/", {}), /private address|ECONNREFUSED/);
  });
});
