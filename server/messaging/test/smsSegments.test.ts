import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { fitSms, SMS_CHAT_COPY, SMS_REPLY_MAX, SMS_REPLY_MAX_SEGMENTS } from "../src/smsChat.js";
import { estimateSmsSegments, isGsm7, reservedSegments } from "../src/smsSegments.js";
import { reportedSegments } from "../src/routes/twilioWebhooks.js";

import { polish } from "./smsSamples.js";

describe("SMS segment estimate (Twilio: 160/153 GSM-7, 70/67 UCS-2)", () => {
  test("the research samples: 600 Polish characters are 9 segments, 134 are 2", () => {
    const long = estimateSmsSegments(polish(600));
    assert.deepEqual([long.encoding, long.units, long.segments], ["UCS-2", 600, 9]);
    const short = estimateSmsSegments(polish(134));
    assert.deepEqual([short.encoding, short.units, short.segments], ["UCS-2", 134, 2]);
    // The old reply cap sat at the worst case.
    assert.equal(estimateSmsSegments(polish(SMS_REPLY_MAX)).segments, 9);
  });

  test("GSM-7: 160 in one segment, 153 a segment after that", () => {
    for (const [n, segments] of [[1, 1], [160, 1], [161, 2], [306, 2], [307, 3], [459, 3], [460, 4]] as const) {
      assert.equal(estimateSmsSegments("a".repeat(n)).segments, segments, `${n} characters`);
    }
    assert.equal(estimateSmsSegments("a".repeat(161)).encoding, "GSM-7");
  });

  test("UCS-2: 70 in one segment, 67 a segment after that", () => {
    for (const [n, segments] of [[1, 1], [70, 1], [71, 2], [134, 2], [135, 3], [201, 3], [202, 4]] as const) {
      assert.equal(estimateSmsSegments("ą".repeat(n)).segments, segments, `${n} characters`);
    }
  });

  test("one character outside GSM-7 turns the whole text into UCS-2", () => {
    const t = "a".repeat(139) + "ł";
    assert.deepEqual([estimateSmsSegments(t).encoding, estimateSmsSegments(t).segments], ["UCS-2", 3]);
    // Twilio's page says "a message of 140 characters that includes one non-GSM character gets split into two segments".
    // By the limits on the same page (UCS-2: 70, then 67 a segment) 140 UCS-2 characters are 3 segments (2 x 67 = 134), so
    // that sentence is loose (it reads as bytes, or as a count below 135). The estimate follows the stated limits, which
    // is the higher, safe number; the reported num_segments is what settles it (outbox.ts).
    assert.equal(estimateSmsSegments("a".repeat(100) + "ł").segments, 2);
    // A curly quote is not GSM-7 either.
    assert.equal(estimateSmsSegments("It’s fine").encoding, "UCS-2");
    assert.equal(estimateSmsSegments("It's fine").encoding, "GSM-7");
  });

  test("GSM-7 extension characters cost two septets, and their pair is never split", () => {
    assert.deepEqual([estimateSmsSegments("€".repeat(80)).units, estimateSmsSegments("€".repeat(80)).segments], [160, 1]);
    assert.equal(estimateSmsSegments("€".repeat(81)).segments, 2);
    for (const ch of "^{}\\[~]|€\f") assert.equal(estimateSmsSegments(ch).units, 2, JSON.stringify(ch));
    // 152 plain septets, then an escape pair: it does not fit in the 153rd and moves whole to the next segment.
    const edge = estimateSmsSegments("a".repeat(152) + "€" + "a".repeat(152));
    assert.equal(edge.units, 152 + 2 + 152);
    assert.equal(edge.segments, 3, "naive 306/153 would say 2");
    assert.equal(estimateSmsSegments("a".repeat(159) + "€").segments, 2, "160 characters but 161 septets");
  });

  test("an emoji is a surrogate pair: two UTF-16 units, and a pair is never split", () => {
    assert.deepEqual([estimateSmsSegments("😀").units, estimateSmsSegments("😀").segments], [2, 1]);
    assert.equal(estimateSmsSegments("😀".repeat(35)).segments, 1, "70 units");
    assert.equal(estimateSmsSegments("😀".repeat(36)).segments, 2, "72 units");
    assert.equal(estimateSmsSegments("😀".repeat(33)).units, 66);
    // 66 units, a pair, 66 units: 134 units would fit in two 67s, but the pair cannot straddle the boundary.
    const t = "ą".repeat(66) + "😀" + "ą".repeat(66);
    assert.equal(t.length, 134);
    assert.equal(estimateSmsSegments(t).segments, 3);
    assert.equal([...t].length, 133, "code points differ from UTF-16 units");
  });

  test("empty text is 0 segments but reserves 1; isGsm7", () => {
    assert.equal(estimateSmsSegments("").segments, 0);
    assert.equal(reservedSegments(""), 1);
    assert.equal(reservedSegments(polish(600)), 9);
    assert.ok(isGsm7("Hello, world! \n£$@"));
    assert.ok(!isGsm7("zażółć"));
    assert.ok(isGsm7("ä ö ü ñ à é è ù ì ò Å å Ø ø Æ æ ß É Ä Ö Ñ Ü §"), "the accented letters GSM-7 has");
    assert.ok(!isGsm7("ó"), "but Polish ó is not one of them");
  });
});

describe("fitSms: a reply within a segment budget", () => {
  const budget = SMS_REPLY_MAX_SEGMENTS;

  test("a short reply passes unchanged", () => {
    assert.equal(fitSms("  Jutro w Warszawie 12°C.  "), "Jutro w Warszawie 12°C.");
    assert.equal(estimateSmsSegments("Jutro w Warszawie 12°C.").segments, 1);
  });

  test("600 Polish characters shrink from 9 segments to the budget, the spelling untouched, ending on a sentence", () => {
    const answer = polish(600);
    assert.equal(estimateSmsSegments(answer).segments, 9);
    const reply = fitSms(answer);
    assert.ok(estimateSmsSegments(reply).segments <= budget, `${estimateSmsSegments(reply).segments} segments`);
    assert.equal(estimateSmsSegments(reply).encoding, "UCS-2", "Polish letters stay Polish letters");
    assert.ok(reply.includes("Zażółć gęślą jaźń."), "diacritics kept");
    assert.ok(reply.endsWith(SMS_CHAT_COPY.moreAfterSentence), reply);
    assert.ok(answer.startsWith(reply.slice(0, reply.indexOf(" " + SMS_CHAT_COPY.moreAfterSentence))), "a prefix of the answer, nothing rewritten");
  });

  test("with no sentence end it cuts on a word and says where to ask for the rest", () => {
    const reply = fitSms("słowo ".repeat(200));
    assert.ok(estimateSmsSegments(reply).segments <= budget);
    assert.ok(reply.endsWith(SMS_CHAT_COPY.more));
    assert.ok(!/słow[^o]*\.\.\./.test(reply.replace(/słowo/g, "")), "not cut inside a word");
    assert.ok(reply.replace(` ${SMS_CHAT_COPY.more}`, "").trimEnd().endsWith("słowo"));
  });

  test("a reply in plain GSM-7 gets the larger budget (153 a segment) and stays GSM-7", () => {
    const english = "The forecast for tomorrow is sunny with a light breeze and a high of twelve degrees. ".repeat(10);
    const reply = fitSms(english);
    const est = estimateSmsSegments(reply);
    assert.equal(est.encoding, "GSM-7", "the tail is ASCII, so it does not tip the text into UCS-2");
    assert.ok(est.segments <= budget && est.units > 160, `${est.units} septets in ${est.segments}`);
  });

  test("a fixed suffix survives the cut and still fits (the card line)", () => {
    const suffix = "\n\n" + SMS_CHAT_COPY.needsApp;
    const reply = fitSms(polish(600), { suffix });
    assert.ok(reply.endsWith(suffix));
    assert.ok(estimateSmsSegments(reply).segments <= budget);
    assert.equal(fitSms("Dobrze.", { suffix }), "Dobrze." + suffix);
  });

  test("never splits an emoji, and an answer of one huge word still fits", () => {
    const reply = fitSms("😀".repeat(500));
    assert.ok(estimateSmsSegments(reply).segments <= budget);
    assert.ok(!/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/.test(reply), "no lone surrogate");
    const word = fitSms("x".repeat(2000), { segments: 2 });
    assert.ok(estimateSmsSegments(word).segments <= 2);
  });

  test("the character ceiling still applies on top", () => {
    const reply = fitSms("a ".repeat(500), { segments: 100, maxChars: 100 });
    assert.ok([...reply].length <= 100);
  });
});

describe("Twilio's reported segment count", () => {
  test("only a whole number from 1 to 255 is taken", () => {
    assert.deepEqual(["1", "9", "255", "0", "256", "", "abc", "-1", "1.5", "0009"].map(reportedSegments),
      [1, 9, 255, undefined, undefined, undefined, undefined, undefined, undefined, undefined]);
  });
});
