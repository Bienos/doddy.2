// Price watches without a database (docs/implementation/SHOPPING_WATCH.md): the request and its digest against the
// shared fixture, the check's decisions (judge and decide), the push words, the 2-second gap between requests to one
// host and what a claimed watch is allowed to read, with a fake shop and a fake clock. Nothing here reaches a shop.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { describe, test } from "node:test";
import { checkOfferPage, type PageCheck } from "../src/shopping/pagecheck.js";
import { TextCipher } from "../src/crypto.js";
import { contentAad, defaultJitterMs } from "../src/watches/context.js";
import { decide, judge, PUSH_TEXT, pushText, type Verdict } from "../src/watches/rules.js";
import {
  blobJson, CHECKS_PER_DAY, contentDigest, contentJson, createBody, DAYS, LIMITS, MAX_FAILURES,
} from "../src/watches/schema.js";
import { HOST_GAP_MS, newWatchLoopState, politeWait, verdictFor } from "../src/watches/worker.js";
import { blocked, claimedFor, FakeShop, FX_URL, noPricePage, pdfPage, productPage, watchFixture as fx } from "./watchesFakes.js";
import { testCipher } from "./helpers.js";

const T0 = new Date("2026-10-24T12:00:00.000Z");
const HOUR = 3_600_000;
const SIX = 6 * HOUR;
const ENDS = new Date(T0.getTime() + DAYS * 86_400_000);

async function readOnce(page: ReturnType<typeof productPage> | typeof blocked): Promise<PageCheck> {
  return checkOfferPage(FX_URL, { fetchPage: async () => page });
}

describe("the request and its digest", () => {
  test("the canonical text and digest are exactly the fixture's (computed with Python)", () => {
    const c = createBody.parse(fx.request);
    assert.equal(contentJson(c), fx.canonical);
    assert.equal(contentDigest(c).toString("hex"), fx.digest);
    // Independently: the plain SHA-256 of the fixture's text.
    assert.equal(createHash("sha256").update(fx.canonical, "utf8").digest("hex"), fx.digest);
    assert.equal(DAYS, 30);
    assert.equal(CHECKS_PER_DAY, 4);
  });

  test("the digest binds every field the user approved, and not the price read just now", () => {
    const base = createBody.parse(fx.request);
    const d = (over: object) => contentDigest(createBody.parse({ ...fx.request, ...over })).toString("hex");
    for (const over of [
      { title: base.title + "!" }, { shop: "RTV Euro AGD" }, { url: base.url + "?x=1" }, { thresholdMinor: base.thresholdMinor + 1 },
      { currency: "EUR" }, { language: "en" },
    ]) assert.notEqual(d(over), fx.digest, JSON.stringify(over));
    assert.equal(d({}), fx.digest);
    assert.equal(contentJson(base).includes("currentMinor"), false);
  });

  test("the words are kept exactly as sent: never trimmed, normalised or rewritten", () => {
    const c = createBody.parse({ ...fx.request, title: "  Zmywarka  ", shop: "Media  Expert " });
    assert.equal(c.title, "  Zmywarka  ");
    assert.equal(c.shop, "Media  Expert ");
    assert.ok(contentJson(c).includes(JSON.stringify("  Zmywarka  ")));
  });

  test("the encrypted blob holds only the words and the address, never the numbers", () => {
    const c = createBody.parse(fx.request);
    const blob = blobJson({ language: c.language, shop: c.shop, title: c.title, url: c.url });
    assert.deepEqual(Object.keys(JSON.parse(blob)), ["language", "shop", "title", "url"]);
    assert.equal(/180000|PLN/u.test(blob), false);
  });

  test("a good request is accepted at every limit", () => {
    for (const over of [
      { title: "x".repeat(LIMITS.title) }, { shop: "y".repeat(LIMITS.shop) }, { thresholdMinor: 1 }, { thresholdMinor: 1_000_000_000 },
      { url: "https://shop.example/" + "a".repeat(LIMITS.url - "https://shop.example/".length) },
      { url: "https://www.mediaexpert.pl:443/p/45?x=1&y=%C5%BC#frag" }, { currency: "EUR", language: "en" },
    ]) assert.equal(createBody.safeParse({ ...fx.request, ...over }).success, true, JSON.stringify(over).slice(0, 80));
  });

  test("every field is validated, and the failing field is named (never its value)", () => {
    const bad: Array<[object, string]> = [
      [{ title: "" }, "title"], [{ title: "   " }, "title"], [{ title: "x".repeat(LIMITS.title + 1) }, "title"], [{ title: 5 }, "title"],
      [{ shop: "" }, "shop"], [{ shop: " \n " }, "shop"], [{ shop: "y".repeat(LIMITS.shop + 1) }, "shop"],
      [{ url: "http://shop.example/p" }, "url"], [{ url: "ftp://shop.example/p" }, "url"], [{ url: "https://" }, "url"],
      [{ url: "https:///path" }, "url"], [{ url: "not a url" }, "url"], [{ url: "shop.example/p" }, "url"],
      [{ url: "https://user:pass@shop.example/p" }, "url"], [{ url: "https://shop.example/a b" }, "url"],
      [{ url: "https://shop.example/" + "a".repeat(LIMITS.url) }, "url"], [{ url: "javascript:alert(1)" }, "url"],
      [{ thresholdMinor: 0 }, "thresholdMinor"], [{ thresholdMinor: -5 }, "thresholdMinor"], [{ thresholdMinor: 1.5 }, "thresholdMinor"],
      [{ thresholdMinor: 1_000_000_001 }, "thresholdMinor"], [{ thresholdMinor: "180000" }, "thresholdMinor"], [{ thresholdMinor: null }, "thresholdMinor"],
      [{ thresholdMinor: Number.NaN }, "thresholdMinor"], [{ thresholdMinor: Number.POSITIVE_INFINITY }, "thresholdMinor"],
      [{ currency: "pln" }, "currency"], [{ currency: "PL" }, "currency"], [{ currency: "PLNN" }, "currency"], [{ currency: 5 }, "currency"],
      [{ language: "PL" }, "language"], [{ language: "pol" }, "language"], [{ language: "p" }, "language"], [{ language: "" }, "language"],
    ];
    for (const [over, field] of bad) {
      const r = createBody.safeParse({ ...fx.request, ...over });
      assert.equal(r.success, false, JSON.stringify(over).slice(0, 80));
      assert.deepEqual([...new Set(r.error!.issues.map((i) => i.path.join(".")))], [field], JSON.stringify(over).slice(0, 80));
    }
    for (const key of Object.keys(fx.request)) {
      const { [key as keyof typeof fx.request]: _gone, ...rest } = fx.request;
      assert.equal(createBody.safeParse(rest).success, false, `missing ${key}`);
    }
    for (const extra of [{ currentMinor: 1 }, { digest: "a" }, { days: 30 }, { id: "x" }]) {
      assert.equal(createBody.safeParse({ ...fx.request, ...extra }).success, false, `extra ${Object.keys(extra)}`);
    }
    for (const notAnObject of [undefined, null, "x", 5, [], [fx.request]]) assert.equal(createBody.safeParse(notAnObject).success, false);
  });
});

describe("reading a page: only a confirmed price counts", () => {
  const judged = async (page: Parameters<typeof readOnce>[0], threshold = 180000, currency = "PLN"): Promise<Verdict> =>
    judge(await readOnce(page), threshold, currency);

  test("a confirmed in-stock read in the user's currency at or below the number triggers; above it does not", async () => {
    assert.deepEqual(await judged(productPage(1799)), { kind: "triggered", priceMinor: 179900 });
    assert.deepEqual(await judged(productPage(1800)), { kind: "triggered", priceMinor: 180000 }, "equal to the number is at the number");
    assert.deepEqual(await judged(productPage("1800.01")), { kind: "above", priceMinor: 180001 });
    assert.deepEqual(await judged(productPage(1899)), { kind: "above", priceMinor: 189900 });
    assert.deepEqual(await judged(productPage(1500, { availability: "InStock" })), { kind: "triggered", priceMinor: 150000 });
    assert.deepEqual(await judged(productPage(1500, { availability: "PreOrder" })), { kind: "triggered", priceMinor: 150000 },
      "the contract stops only a page that says out of stock");
  });

  test("a page that says out of stock never triggers, and its price is not recorded", async () => {
    for (const availability of ["OutOfStock", "SoldOut", "Discontinued"]) {
      assert.deepEqual(await judged(productPage(1500, { availability })), { kind: "unavailable" }, availability);
      assert.deepEqual(await judged(productPage(2500, { availability })), { kind: "unavailable" }, availability);
    }
  });

  test("a price in another currency never triggers, however low the number", async () => {
    assert.deepEqual(await judged(productPage(15, { currency: "EUR" })), { kind: "other_currency" });
    assert.deepEqual(await judged(productPage(1, { currency: "USD" }), 180000, "PLN"), { kind: "other_currency" });
    assert.deepEqual(await judged(productPage(1500), 180000, "EUR"), { kind: "other_currency" });
  });

  test("a read that fails or finds no price is a failed check, never a price", async () => {
    const cases: Array<[Parameters<typeof readOnce>[0], string]> = [
      [blocked, "blocked"], [{ kind: "disallowed", reason: "robots" }, "disallowed"], [{ kind: "failed", reason: "timeout" }, "failed"],
      [noPricePage, "no_price"], [pdfPage, "not_html"],
    ];
    for (const [page, cause] of cases) assert.deepEqual(await judged(page), { kind: "failed", cause }, cause);
    // An address that isn't https is never read at all.
    const http = await checkOfferPage("http://shop.example/p", { fetchPage: async () => productPage(1) });
    assert.deepEqual(judge(http, 180000, "PLN"), { kind: "failed", cause: "failed" });
  });

  test("a price that isn't a positive whole number of minor units is not a price", () => {
    const odd = (minor: number): PageCheck => ({ kind: "ok", offer: { price: { minor, currency: "PLN" }, finalUrl: FX_URL, source: "json_ld" } });
    for (const minor of [0, -1, 1.5, Number.NaN, Number.MAX_SAFE_INTEGER + 2]) {
      assert.deepEqual(judge(odd(minor), 180000, "PLN"), { kind: "failed", cause: "bad_price" }, String(minor));
    }
  });
});

describe("what one check does to a watch", () => {
  const fresh = { checksDone: 0, consecutiveFailures: 0, endsAt: ENDS };
  const at = (ms: number) => new Date(T0.getTime() + ms);
  const failed: Verdict = { kind: "failed", cause: "blocked" };

  test("a drop ends the watch as triggered, with the price, queueing the one push", () => {
    assert.deepEqual(decide(fresh, { kind: "triggered", priceMinor: 179900 }, at(SIX), SIX, 0), {
      state: "triggered", checksDone: 1, consecutiveFailures: 0, priceMinor: 179900, push: "triggered",
    });
    // Failures before it are forgotten; it wins even on the last day.
    const d = decide({ checksDone: 5, consecutiveFailures: 5, endsAt: ENDS }, { kind: "triggered", priceMinor: 1 }, ENDS, SIX, 0);
    assert.equal(d.state, "triggered");
    assert.equal(d.consecutiveFailures, 0);
    assert.equal(d.checksDone, 6);
  });

  test("a confirmed price above the number is recorded and the next check is one interval later", () => {
    const d = decide(fresh, { kind: "above", priceMinor: 189900 }, at(SIX), SIX, 0);
    assert.deepEqual(d, { state: "active", checksDone: 1, consecutiveFailures: 0, priceMinor: 189900, nextCheckAt: at(2 * SIX) });
    assert.equal(d.push, undefined);
  });

  test("out of stock and another currency are checks, not prices and not failures", () => {
    const start = { checksDone: 3, consecutiveFailures: 4, endsAt: ENDS };
    for (const v of [{ kind: "unavailable" }, { kind: "other_currency" }] as Verdict[]) {
      const d = decide(start, v, at(SIX), SIX, 0);
      assert.equal(d.state, "active");
      assert.equal(d.priceMinor, undefined, "no price is recorded");
      assert.equal(d.checksDone, 4);
      assert.equal(d.consecutiveFailures, 0, "a readable page ends the run of failures");
      assert.equal(d.push, undefined);
    }
  });

  test("a failed check is counted, never recorded as a price", () => {
    const d = decide(fresh, failed, at(SIX), SIX, 0);
    assert.deepEqual(d, { state: "active", checksDone: 1, consecutiveFailures: 1, nextCheckAt: at(2 * SIX) });
    assert.equal("priceMinor" in d, false);
  });

  test("8 failed checks in a row end the watch as failed with one push; 7 do not", () => {
    let p = fresh;
    for (let i = 1; i < MAX_FAILURES; i++) {
      const d = decide(p, failed, at(i * SIX), SIX, 0);
      assert.equal(d.state, "active", `after ${i}`);
      assert.equal(d.push, undefined);
      p = { ...p, checksDone: d.checksDone, consecutiveFailures: d.consecutiveFailures };
    }
    assert.equal(p.consecutiveFailures, 7);
    const last = decide(p, failed, at(8 * SIX), SIX, 0);
    assert.deepEqual(last, { state: "failed", checksDone: 8, consecutiveFailures: 8, push: "failed" });
    assert.equal(last.nextCheckAt, undefined);
    assert.equal(MAX_FAILURES, 8);
  });

  test("a readable check in between resets the run: 7 failures, a read, 7 failures is still watching", () => {
    let p = fresh;
    const run = (v: Verdict, n: number) => {
      for (let i = 0; i < n; i++) {
        const d = decide(p, v, at((p.checksDone + 1) * SIX), SIX, 0);
        assert.equal(d.state, "active");
        p = { ...p, checksDone: d.checksDone, consecutiveFailures: d.consecutiveFailures };
      }
    };
    run(failed, 7);
    run({ kind: "above", priceMinor: 189900 }, 1);
    run(failed, 7);
    assert.equal(p.consecutiveFailures, 7);
    assert.equal(p.checksDone, 15);
  });

  test("the last check comes first, then the watch expires; a drop at the last check still triggers", () => {
    const lastDue = decide({ checksDone: 119, consecutiveFailures: 0, endsAt: ENDS }, { kind: "above", priceMinor: 189900 }, ENDS, SIX, 0);
    assert.deepEqual(lastDue, { state: "expired", checksDone: 120, consecutiveFailures: 0, priceMinor: 189900 });
    assert.equal(lastDue.push, undefined, "expiry sends nothing");
    const drop = decide({ checksDone: 119, consecutiveFailures: 0, endsAt: ENDS }, { kind: "triggered", priceMinor: 179900 }, ENDS, SIX, 0);
    assert.equal(drop.state, "triggered");
    // 8 failures on the last day: failed (the more useful word) rather than expired.
    assert.equal(decide({ checksDone: 119, consecutiveFailures: 7, endsAt: ENDS }, failed, ENDS, SIX, 0).state, "failed");
    // Past the end (a worker that was down): still one check, then expired.
    assert.equal(decide(fresh, { kind: "unavailable" }, at(DAYS * 86_400_000 + 5 * HOUR), SIX, 0).state, "expired");
  });

  test("the next check is no later than the end, so the last check is made at the end", () => {
    const near = new Date(ENDS.getTime() - 2 * HOUR);
    assert.deepEqual(decide(fresh, { kind: "above", priceMinor: 1 }, near, SIX, 0).nextCheckAt, ENDS);
    assert.deepEqual(decide(fresh, { kind: "above", priceMinor: 1 }, near, SIX, 600_000).nextCheckAt, ENDS, "a late shift can't pass the end either");
  });

  test("the shift moves the next check either way, and a configured interval is used", () => {
    assert.deepEqual(decide(fresh, failed, at(0), SIX, 120_000).nextCheckAt, at(SIX + 120_000));
    assert.deepEqual(decide(fresh, failed, at(0), SIX, -120_000).nextCheckAt, at(SIX - 120_000));
    assert.deepEqual(decide(fresh, failed, at(0), HOUR, 0).nextCheckAt, at(HOUR));
    for (let i = 0; i < 200; i++) {
      const j = defaultJitterMs(SIX);
      assert.ok(Math.abs(j) <= 15 * 60_000, "at most a quarter of an hour");
      assert.ok(Math.abs(defaultJitterMs(HOUR)) <= HOUR * 0.05, "at most 5% of a short interval");
    }
  });
});

describe("the push words", () => {
  test("exactly the contract's words, in Polish and English, with no product word, shop, address or price", () => {
    assert.equal(pushText("triggered", "pl"), "Cena, której pilnujesz, spadła.");
    assert.equal(pushText("triggered", "en"), "A price you're watching dropped.");
    assert.equal(pushText("triggered", "de"), "A price you're watching dropped.", "any other language gets English");
    assert.equal(pushText("failed", "pl"), "Nie mogę już odczytać ceny, której pilnujesz.");
    assert.equal(pushText("failed", "en"), "Doddy can no longer read a price you're watching.");
    for (const text of [...Object.values(PUSH_TEXT.triggered), ...Object.values(PUSH_TEXT.failed)]) {
      assert.equal(/\d|https?:|zł|PLN|Zmywarka|Media Expert|mediaexpert/iu.test(text), false, text);
    }
  });

  test("the failure words claim nothing about the price", () => {
    for (const text of Object.values(PUSH_TEXT.failed)) assert.equal(/spadła|dropped|cheaper|taniej|niższ|lower/iu.test(text), false, text);
  });
});

describe("one request at a time, two seconds apart per host", () => {
  const clockFor = () => {
    const c = { ms: T0.getTime(), slept: [] as number[] };
    return { c, now: () => new Date(c.ms), sleep: async (ms: number) => { c.slept.push(ms); c.ms += ms; } };
  };

  test("the second request to a host waits out the gap; another host and a late request do not wait", async () => {
    const { c, now, sleep } = clockFor();
    const state = newWatchLoopState();
    await politeWait({ now, sleep }, state, "shop.example");
    assert.deepEqual(c.slept, [], "the first request to a host never waits");
    state.lastRequestAt.set("shop.example", c.ms);
    c.ms += 500;
    await politeWait({ now, sleep }, state, "shop.example");
    assert.deepEqual(c.slept, [HOST_GAP_MS - 500], "500 ms have passed, so 1500 ms remain");
    await politeWait({ now, sleep }, state, "other.example");
    assert.deepEqual(c.slept, [HOST_GAP_MS - 500], "another host has its own gap");
    state.lastRequestAt.set("shop.example", c.ms);
    c.ms += HOST_GAP_MS + 1;
    await politeWait({ now, sleep }, state, "shop.example");
    assert.deepEqual(c.slept, [HOST_GAP_MS - 500], "a request after two seconds goes at once");
    assert.equal(HOST_GAP_MS, 2000);
  });

  test("a check reads the page, records when its request ended and waits for the next one on the same host", async () => {
    const { c, now, sleep } = clockFor();
    const shop = new FakeShop(() => c.ms).set(FX_URL, productPage(1899));
    const state = newWatchLoopState();
    const ctx = { cipher: testCipher, fetcher: shop, now, sleep, log: () => {} };
    const content = createBody.parse(fx.request);
    assert.deepEqual(await verdictFor(ctx, state, claimedFor(testCipher, content)), { kind: "above", priceMinor: 189900 });
    assert.deepEqual(await verdictFor(ctx, state, claimedFor(testCipher, content)), { kind: "above", priceMinor: 189900 });
    assert.deepEqual(c.slept, [HOST_GAP_MS], "the second request waited the full two seconds");
    assert.equal(shop.calls[1]!.at - shop.calls[0]!.at, HOST_GAP_MS);
  });
});

describe("a claimed watch reads only exactly what was approved", () => {
  const content = createBody.parse(fx.request);
  const setup = () => {
    const shop = new FakeShop().set(FX_URL, productPage(1799));
    const logs: { msg: string; extra?: object }[] = [];
    const ctx = { cipher: testCipher, fetcher: shop, now: () => T0, sleep: async () => {}, log: (msg: string, extra?: object) => logs.push({ msg, extra }) };
    return { shop, logs, ctx, state: newWatchLoopState() };
  };

  test("the happy claim reads the address from the blob and judges with the stored numbers", async () => {
    const { shop, ctx, state } = setup();
    assert.deepEqual(await verdictFor(ctx, state, claimedFor(testCipher, content)), { kind: "triggered", priceMinor: 179900 });
    assert.deepEqual(shop.calls.map((x) => x.url), [FX_URL]);
  });

  test("a blob that can't be opened (another key, another row, damage) is a failed check and nothing is requested", async () => {
    const { shop, ctx, state, logs } = setup();
    const row = claimedFor(testCipher, content);
    const otherKey = new TextCipher(Buffer.alloc(32, 9));
    const damaged = Buffer.from(row.content_ciphertext);
    damaged[damaged.length - 1] = damaged[damaged.length - 1]! ^ 1;
    const wrongRow = claimedFor(testCipher, content, { id: "11111111-2222-4333-8444-555555555555" });
    const rows = [
      { ...row, content_ciphertext: otherKey.encrypt("{}", contentAad(row.account_id, row.id)) },
      { ...row, content_ciphertext: damaged },
      { ...row, content_ciphertext: wrongRow.content_ciphertext }, // sealed for another row's AAD
      { ...row, account_id: "99999999-2222-4333-8444-555555555555" }, // moved to another account
    ];
    for (const r of rows) assert.deepEqual(await verdictFor(ctx, state, r), { kind: "failed", cause: "content" });
    assert.equal(shop.calls.length, 0, "nothing was requested");
    assert.equal(JSON.stringify(logs).includes("mediaexpert"), false);
  });

  test("a changed price column or currency no longer matches the digest the user approved: not read", async () => {
    const { shop, ctx, state } = setup();
    const row = claimedFor(testCipher, content);
    for (const r of [{ ...row, threshold_minor: "999999" }, { ...row, currency: "EUR" }, { ...row, payload_digest: Buffer.alloc(32) }]) {
      assert.deepEqual(await verdictFor(ctx, state, r), { kind: "failed", cause: "content" });
    }
    assert.equal(shop.calls.length, 0);
  });

  test("a fetcher that throws is a failed check, not a crash", async () => {
    const { ctx, state } = setup();
    const shop = new FakeShop().set(FX_URL, () => { throw new Error("boom https://mediaexpert.pl"); });
    assert.deepEqual(await verdictFor({ ...ctx, fetcher: shop }, state, claimedFor(testCipher, content)), { kind: "failed", cause: "failed" });
  });

  test("shutdown while a page is being read gives the check back: nothing is recorded, nothing is a failure", async () => {
    const { shop, ctx } = setup();
    const state = newWatchLoopState();
    shop.set(FX_URL, () => { state.shutdown.abort(); return blocked; });
    assert.equal(await verdictFor(ctx, state, claimedFor(testCipher, content)), "aborted");
    const again = newWatchLoopState();
    again.shutdown.abort();
    assert.equal(await verdictFor(ctx, again, claimedFor(testCipher, content)), "aborted");
    assert.equal(shop.calls.length, 1, "a stopped worker doesn't start another request");
  });
});
