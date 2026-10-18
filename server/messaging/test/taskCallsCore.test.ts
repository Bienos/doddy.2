// Pure rules of call cases: destinations, hours, brief content, payload and digest. No database.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { TextCipher } from "../src/crypto.js";
import { briefSchema, checkBriefContent, commits, isBankAccount, isCardNumber, isPesel, type BriefInput } from "../src/taskCalls/brief.js";
import { callFits, warsawClock } from "../src/taskCalls/hours.js";
import { openingLine } from "../src/taskCalls/opening.js";
import { AGENT_VARIABLE_NAMES, canonicalJson, caseKeys, compilePayload, payloadDigest, previewOf } from "../src/taskCalls/payload.js";
import { classifyDestination, GEOGRAPHIC_PREFIXES, MOBILE_PREFIXES } from "../src/taskCalls/phone.js";
import { sampleBrief, VALID_PESEL } from "./helpers.js";

describe("destinations", () => {
  test("every two-digit prefix: only mobile and geographic ranges are allowed", () => {
    for (let p = 10; p <= 99; p++) {
      const prefix = String(p);
      const r = classifyDestination(`+48${prefix}1234567`);
      const expected = MOBILE_PREFIXES.has(prefix) || GEOGRAPHIC_PREFIXES.has(prefix);
      assert.equal(r.ok, expected, `prefix ${prefix}`);
      if (r.ok) assert.equal(r.kind, MOBILE_PREFIXES.has(prefix) ? "mobile" : "geographic");
    }
  });

  test("emergency and short numbers are refused in any spelling", () => {
    for (const n of ["112", "+48112", "+48 112", "0048112", "48112", "997", "+48 997", "998", "999", "986", "116111", "+48116123",
      "118913", "19115", "0112", "1 1 2", "(112)"]) {
      const r = classifyDestination(n);
      assert.equal(r.ok, false, n);
      assert.equal(!r.ok && r.reason, "short_number", n);
    }
  });

  test("premium, shared-cost, special and foreign numbers are refused", () => {
    const cases: [string, string][] = [
      ["700123456", "premium"], ["+48 701 234 567", "premium"], ["708123456", "premium"],
      ["801123456", "shared_cost"], ["804123456", "shared_cost"], ["802123456", "special"], ["808123456", "special"],
      ["391234567", "special"], ["641234567", "special"], ["261234567", "special"], ["471234567", "special"],
      ["+441234567890", "foreign"], ["+1 202 555 0100", "foreign"], ["0049301234567", "foreign"],
      ["", "not_a_number"], ["abc", "not_a_number"], ["+48 600 100 2000", "not_a_number"], ["600 100 20a", "not_a_number"],
      ["301234567", "unknown_range"],
    ];
    for (const [n, reason] of cases) {
      const r = classifyDestination(n);
      assert.equal(r.ok, false, n);
      assert.equal(!r.ok && r.reason, reason, n);
    }
  });

  test("allowed numbers are normalised to E.164", () => {
    for (const n of ["+48 600 100 200", "600-100-200", "0048600100200", "48600100200", "600 100 200", "+48 (60) 0100200"]) {
      const r = classifyDestination(n);
      assert.ok(r.ok, n);
      assert.equal(r.ok && r.e164, "+48600100200", n);
    }
    const free = classifyDestination("800 123 456");
    assert.ok(free.ok && free.kind === "freephone");
    const geo = classifyDestination("22 123 45 67");
    assert.ok(geo.ok && geo.kind === "geographic" && geo.e164 === "+48221234567");
  });
});

describe("calling hours (Warsaw)", () => {
  const max = 240; // + 25 s ring + 20 s grace = 285 s

  test("starts at 8:00 local, on both sides of the change to winter time", () => {
    // Saturday 24 Oct 2026 is CEST (UTC+2); Sunday 25 Oct is CET (UTC+1).
    assert.equal(callFits(new Date("2026-10-24T05:59:59Z"), max), false);
    assert.equal(callFits(new Date("2026-10-24T06:00:00Z"), max), true);
    assert.equal(callFits(new Date("2026-10-25T06:30:00Z"), max), false); // 7:30 CET
    assert.equal(callFits(new Date("2026-10-25T07:00:00Z"), max), true);  // 8:00 CET
    assert.equal(warsawClock(new Date("2026-10-25T07:00:00Z")).seconds, 8 * 3600);
  });

  test("the whole call must end by 20:00", () => {
    assert.equal(callFits(new Date("2026-10-24T17:55:15Z"), max), true);  // ends 20:00:00 CEST
    assert.equal(callFits(new Date("2026-10-24T17:55:16Z"), max), false);
    assert.equal(callFits(new Date("2026-10-26T18:55:15Z"), max), true);  // 19:55:15 CET
    assert.equal(callFits(new Date("2026-10-26T18:55:16Z"), max), false);
    assert.equal(callFits(new Date("2026-10-26T22:00:00Z"), max), false); // 23:00
  });
});

describe("brief content", () => {
  const parse = (over: Partial<BriefInput> = {}) => briefSchema.parse(sampleBrief(over));

  test("checksums", () => {
    assert.equal(isPesel(VALID_PESEL), true);
    assert.equal(isPesel("44051401358"), false);
    assert.equal(isPesel("12345678901"), false);
    assert.equal(isBankAccount("61109010140000071219812874"), true);
    assert.equal(isBankAccount("61109010140000071219812875"), false);
    assert.equal(isCardNumber("4111111111111111"), true);
    assert.equal(isCardNumber("4111111111111112"), false);
  });

  test("a clean brief passes", () => {
    assert.equal(checkBriefContent(parse()), undefined);
  });

  test("PESEL only in a fact ticked as PESEL", () => {
    assert.deepEqual(checkBriefContent(parse({ goal: `Sprawa dla PESEL ${VALID_PESEL}` })), { field: "goal", reason: "pesel_not_ticked" });
    assert.deepEqual(checkBriefContent(parse({ facts: [{ kind: "general", text: `PESEL ${VALID_PESEL}` }] })), { field: "facts.0", reason: "pesel_not_ticked" });
    assert.equal(checkBriefContent(parse({ facts: [{ kind: "pesel", text: VALID_PESEL }] })), undefined);
    assert.deepEqual(checkBriefContent(parse({ facts: [{ kind: "pesel", text: "12345" }] })), { field: "facts.0", reason: "pesel_invalid" });
  });

  test("addresses only in a fact ticked as an address", () => {
    assert.deepEqual(checkBriefContent(parse({ facts: [{ kind: "general", text: "Mieszkam przy ul. Marszałkowskiej 1" }] })), { field: "facts.0", reason: "address_not_ticked" });
    assert.deepEqual(checkBriefContent(parse({ goal: "Odbiór w 00-950 Warszawa" })), { field: "goal", reason: "address_not_ticked" });
    assert.equal(checkBriefContent(parse({ facts: [{ kind: "address", text: "ul. Marszałkowska 1, 00-950 Warszawa" }] })), undefined);
  });

  test("bank accounts and card numbers are never sent", () => {
    assert.equal(checkBriefContent(parse({ facts: [{ kind: "general", text: "Konto PL61 1090 1014 0000 0712 1981 2874" }] }))?.reason, "bank_account");
    assert.equal(checkBriefContent(parse({ facts: [{ kind: "reference", text: "61 1090 1014 0000 0712 1981 2874" }] }))?.reason, "bank_account");
    assert.equal(checkBriefContent(parse({ facts: [{ kind: "general", text: "Karta 4111 1111 1111 1111" }] }))?.reason, "card_number");
  });

  test("braces can't smuggle template variables", () => {
    assert.equal(checkBriefContent(parse({ goal: "Zapytaj o {{doddy_facts}}" }))?.reason, "braces");
    assert.equal(checkBriefContent(parse({ callee: { name: "Serwis {x}", phone: "221234567", source: "typed" } }))?.reason, "braces");
  });

  test("an ASK question asks; it doesn't commit", () => {
    for (const q of ["Czy zamówienie jest gotowe?", "Czy umowa jest gotowa do podpisu?", "Czy można zarezerwować stolik na jutro?",
      "Czy mogą Państwo potwierdzić termin odbioru?", "Do której godziny jest otwarta placówka?", "Czy laptop z serwisu jest gotowy?"]) {
      assert.equal(commits(q), false, q);
    }
    for (const q of ["Potwierdzam wizytę na jutro?", "Chciałbym zamówić pizzę", "Proszę zarezerwować stolik", "Zapłacę przy odbiorze?",
      "Biorę ten termin?", "Chcę odwołać wizytę"]) {
      assert.equal(commits(q), true, q);
    }
    assert.equal(checkBriefContent(parse({ question: "Proszę zarezerwować stolik na 19" }))?.reason, "question_commits");
  });

  test("the schema is strict and bounded", () => {
    assert.equal(briefSchema.safeParse({ ...sampleBrief(), extra: 1 }).success, false);
    assert.equal(briefSchema.safeParse({ ...sampleBrief(), callee: { ...sampleBrief().callee, to: "+48600100200" } }).success, false);
    assert.equal(briefSchema.safeParse({ ...sampleBrief(), maxDurationSecs: 301 }).success, false);
    assert.equal(briefSchema.safeParse({ ...sampleBrief(), maxDurationSecs: 59 }).success, false);
    assert.equal(briefSchema.safeParse({ ...sampleBrief(), facts: Array.from({ length: 6 }, (_, i) => ({ kind: "general", text: `fakt ${i}` })) }).success, false);
    assert.equal(briefSchema.safeParse({ ...sampleBrief(), principal: { name: "Anna1", genitive: "Anny" } }).success, false);
    assert.equal(parse().maxDurationSecs, 240);
  });

  test("control and bidi characters are removed", () => {
    const b = parse({ goal: "Zapytać‮ o\u0007   laptop\n\nteraz" });
    assert.equal(b.goal, "Zapytać o laptop teraz");
  });
});

describe("payload", () => {
  const cipher = new TextCipher(Buffer.alloc(32, 9));
  const keys = caseKeys(cipher);
  const compile = (over: Partial<BriefInput> = {}, notice: "off" | "nagrywana" | "zapisywana" = "off") => compilePayload({
    caseId: "8a4c2a9e-0000-4000-8000-000000000001",
    brief: briefSchema.parse(sampleBrief(over)),
    destination: { e164: "+48221234567", kind: "geographic" },
    fromNumber: "+48221112233",
    notice,
  });

  test("the opening line says it is an AI, in Polish, word for word", () => {
    assert.equal(openingLine("Anny", "off", "Czy laptop z serwisu jest gotowy?"),
      "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: Czy laptop z serwisu jest gotowy?");
    assert.equal(openingLine("Anny", "nagrywana", "Czy laptop z serwisu jest gotowy"),
      "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Rozmowa jest nagrywana. Chciałbym zapytać: Czy laptop z serwisu jest gotowy?");
    assert.match(compile().agent.variables.doddy_opening_line, /^Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny\. Chciałbym zapytać: Czy laptop z serwisu jest gotowy\?$/);
  });

  test("the agent gets exactly the declared variables, and the Twilio part never records", () => {
    const p = compile();
    assert.deepEqual(Object.keys(p.agent.variables).sort(), [...AGENT_VARIABLE_NAMES].sort());
    assert.deepEqual(p.twilio, { to: "+48221234567", from: "+48221112233", timeLimitSecs: 260, timeoutSecs: 25, record: false });
    assert.equal(p.agent.variables.doddy_callback_line, "Sprawdzę to u Anny i oddzwonię.");
    assert.ok(p.display.forbidden.includes("Nie podaje numeru PESEL."));
    assert.ok(p.display.forbidden.includes("Nie podaje adresu."));
    // The card label of the number's source is never sent to a provider.
    assert.equal(JSON.stringify(p.agent).includes("Mokotów"), false);
  });

  test("ticking PESEL changes what may be said and what the card forbids", () => {
    const p = compile({ facts: [{ kind: "pesel", text: VALID_PESEL }] });
    assert.equal(p.agent.variables.doddy_facts, `- PESEL: ${VALID_PESEL}`);
    assert.equal(p.display.forbidden.includes("Nie podaje numeru PESEL."), false);
    const none = compile({ facts: [] });
    assert.match(none.agent.variables.doddy_facts, /^\(brak/);
  });

  test("the digest is stable, and any change to the payload changes it", () => {
    const a = compile();
    const shuffled = JSON.parse(JSON.stringify(a), (_k, v) => (v && typeof v === "object" && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).reverse()) : v));
    assert.equal(canonicalJson(a), canonicalJson(shuffled));
    assert.deepEqual(payloadDigest(keys, a), payloadDigest(keys, shuffled));
    const variants = [
      compile({ facts: [{ kind: "reference", text: "Numer zlecenia 12346" }] }),
      compile({ question: "Czy laptop jest gotowy" }),
      compile({ maxDurationSecs: 180 }),
      compile({}, "zapisywana"),
      compile({ principal: { name: "Anna", genitive: "Ani" } }),
    ];
    for (const v of variants) assert.notDeepEqual(payloadDigest(keys, v), payloadDigest(keys, a));
    // A different server key gives a different digest (HMAC, not a bare hash).
    assert.notDeepEqual(payloadDigest(caseKeys(new TextCipher(Buffer.alloc(32, 8))), a), payloadDigest(keys, a));
  });

  test("the preview is built from the payload itself", () => {
    const p = compile();
    const digest = payloadDigest(keys, p);
    const preview = previewOf(p, digest, new Date("2026-10-18T12:00:00Z"));
    assert.equal(preview.openingLine, p.agent.variables.doddy_opening_line);
    assert.equal(preview.digest, digest.toString("hex"));
    assert.equal(preview.callee.phone, "22 123 45 67");
    assert.equal(preview.recordsAudio, false);
  });
});
