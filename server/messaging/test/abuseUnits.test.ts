// The pieces of the abuse limits that need no database (security review 4 Nov 2026, ADR-702 to ADR-706): the country
// list, the client bucket, the link check, the research budget, the cipher's tag handling and the new settings.
import assert from "node:assert/strict";
import { createCipheriv, randomBytes } from "node:crypto";
import { describe, test } from "node:test";
import { DEFAULT_ABUSE_LIMITS, loadConfig } from "../src/config.js";
import { TextCipher } from "../src/crypto.js";
import { clientBucket, counterKey } from "../src/dailyCounters.js";
import { budgetLeft, DEFAULT_RESEARCH_BUDGET, MIN_REQUEST_TOKENS, requestTokens, withMaxUses, type ResearchBudget } from "../src/errands/budget.js";
import { foldForLinks, hasLink, linkFields } from "../src/errands/links.js";
import { DEFAULT_ALLOWED_COUNTRY_CODES, isAllowedNumber, parseCountryCodes } from "../src/phoneCountries.js";

const ENV = { DATABASE_URL: "postgres://x/y" };

describe("phone countries (ADR-704)", () => {
  test("the default list is Poland, the EU and EEA, the UK and Switzerland, and holds no overlapping codes", () => {
    assert.equal(DEFAULT_ALLOWED_COUNTRY_CODES.join(","),
      "30,31,32,33,34,351,352,353,354,356,357,358,359,36,370,371,372,385,386,39,40,41,420,421,423,43,44,45,46,47,48,49");
    assert.deepEqual(parseCountryCodes(DEFAULT_ALLOWED_COUNTRY_CODES.join(",")), [...DEFAULT_ALLOWED_COUNTRY_CODES]);
  });

  test("numbers of the allowed countries pass, matched on the whole calling code", () => {
    const ok = ["+48500100200", "+4930123456", "+441234567890", "+41791234567", "+3598123456", "+420123456789", "+421912345678",
      "+423 6601234".replace(" ", ""), "+35312345678", "+358401234567", "+34612345678", "+39312345678", "+31612345678", "+4740123456"];
    for (const n of ok) assert.equal(isAllowedNumber(n, DEFAULT_ALLOWED_COUNTRY_CODES), true, n);
  });

  test("other countries are refused, including ones whose code starts like an allowed one", () => {
    const refused = [
      "+12125551234", // US: calling code 1
      "+919876543210", // India
      "+79161234567", // Russia
      "+8613812345678", // China
      "+380501234567", // Ukraine (380): 38 is not a code, and 385 and 386 are Croatia and Slovenia
      "+3551234567", // Albania (355): 35x holds six allowed codes, this is not one
      "+3501234567", // Gibraltar (350)
      "+4251234567", // there is no 425, and 42 is not a code although 420, 421 and 423 are
      "+4221234567", // the old 42
      "+2348012345678", // Nigeria
      "+5491123456789", // Argentina
      "+37512345678", // Belarus (375) next to 370, 371, 372
      "+38212345678", // Montenegro (382) next to 385, 386
    ];
    for (const n of refused) assert.equal(isAllowedNumber(n, DEFAULT_ALLOWED_COUNTRY_CODES), false, n);
  });

  test("a string that is not an E.164 number is never allowed", () => {
    for (const n of ["48500100200", "+048500100200", "+48", "+48 500 100 200", "+4850010020a", "", "+999999999999999999"]) {
      assert.equal(isAllowedNumber(n, DEFAULT_ALLOWED_COUNTRY_CODES), false, n);
    }
  });

  test("a configured list is read as given, and a list that cannot be right stops the start", () => {
    assert.deepEqual(parseCountryCodes("48, +49 ,1,48"), ["48", "49", "1"]);
    assert.equal(isAllowedNumber("+12125551234", parseCountryCodes("48,1")), true);
    assert.equal(isAllowedNumber("+4930123456", parseCountryCodes("48,1")), false);
    for (const bad of ["", " , ", "0", "048", "4a", "4800", "42,420", "35,351", "+", "1234"]) {
      assert.throws(() => parseCountryCodes(bad), bad);
    }
  });

  test("PHONE_ALLOWED_COUNTRY_CODES: default list, an explicit one, and a bad one fails loudly", () => {
    assert.deepEqual(loadConfig(ENV).limits.allowedCountryCodes, [...DEFAULT_ALLOWED_COUNTRY_CODES]);
    assert.deepEqual(loadConfig({ ...ENV, PHONE_ALLOWED_COUNTRY_CODES: "" }).limits.allowedCountryCodes, [...DEFAULT_ALLOWED_COUNTRY_CODES], "empty counts as unset");
    assert.deepEqual(loadConfig({ ...ENV, PHONE_ALLOWED_COUNTRY_CODES: "48,44" }).limits.allowedCountryCodes, ["48", "44"]);
    assert.throws(() => loadConfig({ ...ENV, PHONE_ALLOWED_COUNTRY_CODES: "48,4x" }));
    assert.throws(() => loadConfig({ ...ENV, PHONE_ALLOWED_COUNTRY_CODES: "42,420" }));
  });
});

describe("abuse settings (ADR-702, ADR-704, ADR-705)", () => {
  test("defaults are the safe ones, and nothing new is needed to start", () => {
    const c = loadConfig(ENV);
    assert.deepEqual({ ...c.limits, allowedCountryCodes: undefined }, { ...DEFAULT_ABUSE_LIMITS, allowedCountryCodes: undefined });
    assert.deepEqual(
      [c.limits.accountsPerIpDay, c.limits.accountsPerServerDay, c.limits.verifyPerIpDay, c.limits.verifyPerAccountDay,
        c.limits.smsPerAccountDay, c.limits.smsPerServerDay, c.limits.outboundCallsPerServerDay],
      [50, 1000, 20, 6, 30, 300, 20]);
    assert.deepEqual(c.taskCallSettings.blockedNumbers, []);
    assert.equal(c.errandSettings.dailyForNewAccounts, 10);
    assert.equal(c.dealsSettings.dailyForNewAccounts, 200);
    assert.equal(c.assistantSettings.dailyForNewAccounts, 200);
    assert.equal(c.errandSettings.newAccountHours, 24);
  });

  test("each can be set, and values out of range are refused", () => {
    const c = loadConfig({
      ...ENV, ACCOUNTS_DAILY_PER_IP: "5", ACCOUNTS_DAILY_PER_SERVER: "100", VERIFY_DAILY_PER_IP: "3", VERIFY_DAILY_PER_ACCOUNT: "2",
      SMS_DAILY_PER_ACCOUNT: "4", SMS_DAILY_PER_SERVER: "40", OUTBOUND_CALLS_DAILY_PER_SERVER: "7", NEW_ACCOUNT_HOURS: "72",
      ERRANDS_DAILY_NEW_ACCOUNTS: "0", DEALS_DAILY_NEW_ACCOUNTS: "9", ASSISTANT_DAILY_NEW_ACCOUNTS: "8",
    });
    assert.deepEqual([c.limits.accountsPerIpDay, c.limits.accountsPerServerDay, c.limits.verifyPerIpDay, c.limits.verifyPerAccountDay,
      c.limits.smsPerAccountDay, c.limits.smsPerServerDay, c.limits.outboundCallsPerServerDay], [5, 100, 3, 2, 4, 40, 7]);
    assert.equal(c.errandSettings.dailyForNewAccounts, 0, "0 means new accounts can't approve errands");
    assert.equal(c.errandSettings.newAccountHours, 72);
    assert.equal(c.dealsSettings.newAccountHours, 72);
    assert.equal(c.assistantSettings.dailyForNewAccounts, 8);
    for (const bad of [{ ACCOUNTS_DAILY_PER_IP: "0" }, { SMS_DAILY_PER_ACCOUNT: "0" }, { OUTBOUND_CALLS_DAILY_PER_SERVER: "-1" },
      { NEW_ACCOUNT_HOURS: "-1" }, { NEW_ACCOUNT_HOURS: "8761" }, { VERIFY_DAILY_PER_ACCOUNT: "1.5" }, { ERRANDS_DAILY_NEW_ACCOUNTS: "-1" }]) {
      assert.throws(() => loadConfig({ ...ENV, ...bad }), JSON.stringify(bad));
    }
  });

  test("the errand research budget: finite by default, 0 means no limit only when set on purpose", () => {
    assert.deepEqual(loadConfig(ENV).errandSettings.budget, DEFAULT_RESEARCH_BUDGET);
    const unlimited = loadConfig({ ...ENV, ERRAND_MAX_SEARCHES: "0", ERRAND_MAX_FETCHES: "0", ERRAND_MAX_REQUESTS: "0", ERRAND_MAX_OUTPUT_TOKENS: "0" });
    assert.deepEqual(unlimited.errandSettings.budget, { maxSearches: 0, maxFetches: 0, maxRequests: 0, maxOutputTokens: 0 });
    assert.deepEqual(loadConfig({ ...ENV, ERRAND_MAX_SEARCHES: "12", ERRAND_MAX_FETCHES: "9", ERRAND_MAX_REQUESTS: "5", ERRAND_MAX_OUTPUT_TOKENS: "50000" }).errandSettings.budget,
      { maxSearches: 12, maxFetches: 9, maxRequests: 5, maxOutputTokens: 50000 });
    for (const bad of [{ ERRAND_MAX_SEARCHES: "-1" }, { ERRAND_MAX_FETCHES: "1001" }, { ERRAND_MAX_REQUESTS: "2.5" }, { ERRAND_MAX_OUTPUT_TOKENS: "500" }]) {
      assert.throws(() => loadConfig({ ...ENV, ...bad }), JSON.stringify(bad));
    }
  });

  test("TASK_CALL_BLOCKED_NUMBERS: E.164 numbers, tidied; a bad entry stops the start without printing the number", () => {
    assert.deepEqual(loadConfig({ ...ENV, TASK_CALL_BLOCKED_NUMBERS: "+48 22 123-45-67, +48500100200,+48221234567," }).taskCallSettings.blockedNumbers,
      ["+48221234567", "+48500100200"]);
    assert.deepEqual(loadConfig({ ...ENV, TASK_CALL_BLOCKED_NUMBERS: "" }).taskCallSettings.blockedNumbers, []);
    for (const bad of ["500600700", "+48abc", "0048500600700", "+0500600700"]) {
      assert.throws(() => loadConfig({ ...ENV, TASK_CALL_BLOCKED_NUMBERS: `+48221234567,${bad}` }), (err: Error) => {
        assert.match(err.message, /entry 2 is not an E\.164 number/);
        assert.ok(!err.message.includes(bad), "the number is not in the error");
        return true;
      }, bad);
    }
  });
});

describe("client bucket (ADR-702)", () => {
  test("IPv4 is the address; IPv4 written the IPv6 way is read as IPv4", () => {
    assert.equal(clientBucket("203.0.113.7"), "203.0.113.7");
    assert.equal(clientBucket("::ffff:203.0.113.7"), "203.0.113.7");
    assert.equal(clientBucket("::FFFF:203.0.113.7"), "203.0.113.7");
  });

  test("IPv6 is its /64: every spelling of one prefix is one bucket, another prefix is another", () => {
    const one = clientBucket("2001:db8:1:2::1");
    assert.equal(one, "v6:2001:0db8:0001:0002/64");
    for (const same of ["2001:DB8:1:2:ffff:ffff:ffff:ffff", "2001:0db8:0001:0002:0000:0000:0000:0001", "2001:db8:1:2:aaaa::9", "2001:db8:1:2::", "2001:db8:1:2::1%eth0"]) {
      assert.equal(clientBucket(same), one, same);
    }
    assert.notEqual(clientBucket("2001:db8:1:3::1"), one);
    assert.equal(clientBucket("::1"), "v6:0000:0000:0000:0000/64");
    assert.equal(clientBucket("64:ff9b::192.0.2.1"), "v6:0064:ff9b:0000:0000/64");
  });

  test("something that is not an address keeps its own bucket, and the key is a hash, never the address", () => {
    assert.equal(clientBucket("not-an-ip:::"), "not-an-ip:::");
    const secret = randomBytes(32);
    const key = counterKey(secret, "203.0.113.7");
    assert.match(key, /^[0-9a-f]{64}$/);
    assert.ok(!key.includes("203"));
    assert.notEqual(key, counterKey(undefined, "203.0.113.7"), "with a secret the key is an HMAC, not the bare hash");
    assert.equal(key, counterKey(secret, "203.0.113.7"));
    assert.notEqual(key, counterKey(randomBytes(32), "203.0.113.7"));
  });
});

describe("errand text carries no link (ADR-703)", () => {
  const links = [
    "https://evil.example/collect?d=1", "http://evil.example", "HTTP://EVIL.EXAMPLE/X", "HtTpS://evil.example/x", "ftp://files.example/a", "file:///etc/passwd",
    "ws://evil.example:8080", "sprawdź www.sklep.pl", "WWW.SKLEP.PL", "www2.sklep.pl", "(www.sklep.pl)",
    "allegro.pl/oferta/123", "sklep.example/produkt?id=4", "evil.example?x=1", "evil.example#frag", "pl.wikipedia.org/wiki/Rzym", "evil.example:8080/a",
    "żółw.example/x", "sub.domain.co.uk/path", "[kliknij](https://evil.example/x)", "[kliknij](allegro.pl/x)", "<a href=\"evil.example/x\">", "see evil.example/x.",
    "192.168.0.1", "http://192.168.0.1/admin", "169.254.169.254/latest/meta-data", "do 10.0.0.1.", "[::1]", "[2001:db8::1]",
    "javascript:alert(1)", "JaVaScRiPt :alert(1)", "vbscript:x", "data:text/html;base64,PGh0bWw+", "data:text/html,<b>", "data:;base64,AAAA", "data:,hi",
    // Disguises that a parser or a model would open
    "https%3A%2F%2Fevil.example%2Fx", "evil.example%2Fx", "evil%2Eexample/x", "https:%2F%2Fevil.example", "evil.example%252Fx",
    "evil。example/x", "evil．example/x", "evil｡example/x", "ｅｖｉｌ.example/x", "ｈｔｔｐｓ：／／evil.example", "https:／／evil.example", "https:∕∕evil.example",
    "ht\u200Btps://evil.example", "evil\u200B.example/x", "ev\u00ADil.example/x", "https&#58;//evil.example", "https&colon;&sol;&sol;evil.example", "evil&period;example&#x2F;x",
    "http:\\\\evil.example", "https:/\\evil.example",
    // The shapes the app refuses too (ErrandLinks.swift): a trailing slash, punycode, hex IP, markdown to a bare name, written-out dots.
    "example.com/", "xn--p1ai.xn--80asehdb/x", "0x7f.0.0.1/x", "[x](example.com)", "[x](/sciezka)", "[x](mailto:a@b.c)", "example.com%5Cpath",
    "example[.]com/x", "example(.)com/x", "example[dot]com/x", "hxxps[:]//example[.]com", "example.com[/]x", "hxxps://example.com/x",
  ];
  const fine = [
    "chcę jechać do Rzymu w przyszłym miesiącu na 7 dni, sprawdź loty i hotele do 2000 zł", "Loty z Warszawy i hotele w Rzymie, 7 nocy (założenie: z Warszawy).",
    "porównaj ceny na allegro.pl i ceneo.pl", "allegro.pl", "Sprawdź na Allegro.pl lub Ceneo.pl.", "zmywarka 45 cm, cicha, klasa A+++", "Data: 12 listopada", "data: 12.11",
    "Data wyjazdu: 12.11, powrót 19.11", "godz. 12:30/13:00", "od 8:00 do 16:00", "cena 12.50 zł/szt, 1.234,56 zł", "5.5/10 w testach", "km/h oraz m/s",
    "np. cicha, tj. poniżej 42 dB", "m.in. lodówka/zamrażarka", "ul. Marszałkowska 1/3, Warszawa", "tel. 22 123 45 67", "rozmiar 38/39", "Wersja 17.4.1", "1.2.3",
    "tak/nie", "A/B test", "i.e. cheap", "jan.kowalski", "Rzym, Włochy; 7 dni", "http", "https", "www", "text: data", "javascript", "javascript: the good parts", "JavaScript developer", "wi-fi 6E, USB-C", "Czy to jest wizzair.com? Albo ryanair.com?", "zobacz [1] (str. 5)",
    "Opis: 100% bawełna.", "email me later", "2026-11-04T10:00:00Z", "[2] [3]", "[12:30]",
  ];
  test("every spelling of a link is found", () => {
    for (const t of links) assert.equal(hasLink(t), true, JSON.stringify(t));
  });
  test("ordinary text, shop names without a path, times, prices and numbers are not links", () => {
    for (const t of fine) assert.equal(hasLink(t), false, JSON.stringify(t));
  });
  test("a link in the middle of other text is found, whatever surrounds it", () => {
    for (const t of links.slice(0, 20)) assert.equal(hasLink(`Proszę o pomoc. ${t} Dziękuję!`), true, t);
  });
  test("linkFields names the fields only", () => {
    assert.deepEqual(linkFields({ words: "ok", brief: "ok", title: "ok", priorities: ["cicha", "ok"] }), []);
    assert.deepEqual(linkFields({ words: "https://evil.example/x", brief: "ok", title: "www.x.pl", priorities: ["a", "b.example/c", "ok", "10.0.0.1"] }),
      ["words", "title", "priorities.1", "priorities.3"]);
    assert.deepEqual(linkFields({ words: "ok", brief: "ok", title: "ok" }), []);
  });
  test("folding keeps ordinary text readable", () => {
    assert.equal(foldForLinks("Zażółć gęślą jaźń"), "Zażółć gęślą jaźń");
    assert.equal(foldForLinks("a%2Fb%2eC&#47;&#x2e;"), "a/b.C/.");
  });
});

describe("research budget (ADR-702)", () => {
  const b: ResearchBudget = { maxSearches: 5, maxFetches: 3, maxRequests: 4, maxOutputTokens: 100_000 };
  const used = (over: Partial<{ requests: number; searches: number; fetches: number; outputTokens: number }> = {}) =>
    ({ requests: 0, searches: 0, fetches: 0, outputTokens: 0, ...over });

  test("what is left shrinks as the errand uses it, and the first limit reached is named", () => {
    assert.deepEqual(budgetLeft(b, used()), { left: { searches: 5, fetches: 3, outputTokens: 100_000 } });
    assert.deepEqual(budgetLeft(b, used({ requests: 2, searches: 4, fetches: 1, outputTokens: 60_000 })), { left: { searches: 1, fetches: 2, outputTokens: 40_000 } });
    assert.deepEqual(budgetLeft(b, used({ requests: 4 })), { reached: "requests" });
    assert.deepEqual(budgetLeft(b, used({ searches: 5 })), { reached: "searches" });
    assert.deepEqual(budgetLeft(b, used({ fetches: 7 })), { reached: "fetches" });
    assert.deepEqual(budgetLeft(b, used({ outputTokens: 100_000 - MIN_REQUEST_TOKENS + 1 })), { reached: "output_tokens" });
  });

  test("0 means no limit on that count, and leaves it out of what is handed on", () => {
    const none: ResearchBudget = { maxSearches: 0, maxFetches: 0, maxRequests: 0, maxOutputTokens: 0 };
    assert.deepEqual(budgetLeft(none, used({ requests: 999, searches: 999, fetches: 999, outputTokens: 9_999_999 })), { left: {} });
    assert.deepEqual(withMaxUses([{ type: "web_search_20260209", name: "web_search" }, { type: "web_fetch_20260209", name: "web_fetch" }], undefined, none),
      [{ type: "web_search_20260209", name: "web_search" }, { type: "web_fetch_20260209", name: "web_fetch" }]);
    assert.equal(requestTokens({}, none), 64_000);
  });

  test("max_uses is the room left, or the whole limit before anything is counted; other tools are left alone", () => {
    const tools = [{ type: "web_search_20260209", name: "web_search" }, { type: "web_fetch_20260209", name: "web_fetch" }, { type: "custom", name: "other" }];
    assert.deepEqual(withMaxUses(tools, { searches: 2, fetches: 1 }, b).map((t) => (t as { max_uses?: number }).max_uses), [2, 1, undefined]);
    assert.deepEqual(withMaxUses(tools, undefined, b).map((t) => (t as { max_uses?: number }).max_uses), [5, 3, undefined]);
    assert.deepEqual(tools.map((t) => (t as { max_uses?: number }).max_uses), [undefined, undefined, undefined], "the shared definitions are not changed");
  });

  test("max_tokens is the request's usual ceiling, lowered to what is left", () => {
    assert.equal(requestTokens({ outputTokens: 100_000 }, b), 64_000);
    assert.equal(requestTokens({ outputTokens: 10_000 }, b), 10_000);
    assert.equal(requestTokens(undefined, b), 64_000);
    assert.equal(requestTokens({ outputTokens: 10_000 }, b, 32_000), 10_000);
    assert.equal(requestTokens({ outputTokens: 50_000 }, b, 32_000), 32_000);
    assert.equal(requestTokens(undefined, { ...b, maxOutputTokens: 20_000 }), 20_000);
  });
});

describe("TextCipher refuses a ciphertext whose tag is cut short (ADR-706)", () => {
  const key = Buffer.alloc(32, 9);
  const cipher = new TextCipher(key);
  const aad = "acct:note:1";

  test("a round trip still works, also for an empty text", () => {
    assert.equal(cipher.decrypt(cipher.encrypt("Cześć, świecie", aad), aad), "Cześć, świecie");
    const empty = cipher.encrypt("", aad);
    assert.equal(empty.length, 28, "IV and a whole tag, nothing else");
    assert.equal(cipher.decrypt(empty, aad), "");
  });

  test("a blob shorter than the IV and the whole tag is refused", () => {
    const blob = cipher.encrypt("secret", aad);
    for (const cut of [0, 1, 11, 12, 20, 27]) assert.throws(() => cipher.decrypt(blob.subarray(0, cut), aad), /too short/, `cut at ${cut}`);
  });

  test("a blob made with a shortened tag is refused, though its short tag is right for the key", () => {
    // Without the pinned length Node accepts an 8-byte tag, so this blob (a valid 8-byte-tag encryption of "") was read as valid.
    const iv = randomBytes(12);
    const short = createCipheriv("aes-256-gcm", key, iv, { authTagLength: 8 });
    short.setAAD(Buffer.from(aad));
    short.final();
    const blob = Buffer.concat([iv, short.getAuthTag()]);
    assert.equal(blob.length, 20);
    assert.throws(() => cipher.decrypt(blob, aad));
  });

  test("the wrong associated data, a flipped bit and a wrong key still fail", () => {
    const blob = cipher.encrypt("secret", aad);
    assert.throws(() => cipher.decrypt(blob, "acct:note:2"));
    const flipped = Buffer.from(blob);
    flipped[flipped.length - 1]! ^= 1;
    assert.throws(() => cipher.decrypt(flipped, aad));
    assert.throws(() => new TextCipher(Buffer.alloc(32, 1)).decrypt(blob, aad));
  });
});
