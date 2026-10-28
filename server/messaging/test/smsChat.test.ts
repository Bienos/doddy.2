import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { AssistOutcome, AssistantResponder } from "../src/assistant/responder.js";
import type { AssistRequest } from "../src/assistant/request.js";
import { DEFAULT_ASSISTANT_SETTINGS, type AssistantSettings } from "../src/config.js";
import type { Db } from "../src/db.js";
import { dispatchDue } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { fitSms, SMS_CHAT_COPY, SMS_REPLY_MAX, type SmsChatOutcome } from "../src/smsChat.js";
import { BASE_URL, dbSkip, freshDb, testApp, testCipher, TWILIO_TOKEN } from "./helpers.js";

const sid = (n: number) => "SM" + n.toString(16).padStart(32, "0");

class FakeResponder implements AssistantResponder {
  readonly provider = "anthropic" as const;
  readonly model = "claude-haiku-5-5";
  seen: AssistRequest[] = [];
  next: (() => Promise<AssistOutcome>)[] = [];
  async answer(req: AssistRequest): Promise<AssistOutcome> {
    this.seen.push(req);
    const step = this.next.shift();
    return step ? step() : { kind: "ok", answer: "Jutro w Warszawie 12°C.", sources: [], usage: { inputTokens: 50, outputTokens: 9 } };
  }
}

describe("fitSms", () => {
  test("short replies pass unchanged; long ones end on a word and point to the app", () => {
    assert.equal(fitSms("  Krótko.  "), "Krótko.");
    const long = "słowo ".repeat(200);
    const fitted = fitSms(long);
    assert.ok([...fitted].length <= SMS_REPLY_MAX);
    assert.ok(fitted.endsWith(SMS_CHAT_COPY.more));
    assert.ok(!fitted.includes("słow…"), "not cut inside a word");
  });
});

describe("texting Doddy against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  const PHONE = "+48500300400";
  let n = 0;
  let smsIds = 0;

  async function world(opts: { settings?: Partial<AssistantSettings>; responder?: FakeResponder | null; cipher?: boolean } = {}) {
    const responder = opts.responder === null ? undefined : opts.responder ?? new FakeResponder();
    const pending: Promise<SmsChatOutcome>[] = [];
    const logs: { msg: string; extra?: object }[] = [];
    const base = await testApp(db, {
      assistant: { settings: { ...DEFAULT_ASSISTANT_SETTINGS, ...opts.settings }, responder },
      ...(opts.cipher === false ? { cipher: undefined } : {}),
      onSmsChat: (p) => pending.push(p),
      smsChatLog: (msg, extra) => logs.push({ msg, extra }),
    });
    const app: FastifyInstance = base.app;
    // Provider ids are unique across the database; each world's fake would start again at SM1.
    const fakeSend = base.sms.send.bind(base.sms);
    base.sms.send = async (to, body) => {
      const o = await fakeSend(to, body);
      return o.kind === "accepted" ? { ...o, providerId: `SMchat${++smsIds}` } : o;
    };
    const call = (method: "GET" | "PUT" | "POST", url: string, headers: object, payload?: object) =>
      app.inject({ method, url, headers: headers as Record<string, string>, payload });
    const account = async (phone = PHONE) => {
      n++;
      const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.88.${n >> 8}.${n & 255}` });
      const h = { authorization: `Bearer ${(r.json() as { deviceToken: string }).deviceToken}` };
      await call("POST", "/v1/phone/verification", h, { phone });
      assert.equal((await call("POST", "/v1/phone/verification/check", h, { phone, code: "123456" })).statusCode, 200);
      return h;
    };
    const text = async (body: string, messageSid: string, from = PHONE) => {
      const form = { From: from, Body: body, MessageSid: messageSid };
      const url = "/webhooks/twilio/sms";
      const r = await app.inject({
        method: "POST", url, payload: new URLSearchParams(form).toString(),
        headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": twilioSignature(TWILIO_TOKEN, BASE_URL + url, form) },
      });
      assert.equal(r.statusCode, 200);
      assert.equal(r.body, '<?xml version="1.0" encoding="UTF-8"?><Response/>', "the reply is never in the webhook answer");
      const outcomes = await Promise.all(pending.splice(0));
      await dispatchDue(db, { sms: base.sms, cipher: testCipher });
      return outcomes;
    };
    const turnOn = async (h: object) => {
      assert.equal((await call("PUT", "/v1/phone/sms-consent", h, { consent: true, textVersion: "sms-v1" })).statusCode, 204);
      assert.equal((await call("PUT", "/v1/phone/sms-chat", h, { consent: true, textVersion: "sms-chat-v1" })).statusCode, 204);
    };
    return { ...base, responder, logs, call, account, text, turnOn };
  }

  test("needs texts on first; then a text gets one reply by text, with no notes, and nothing kept", async () => {
    const w = await world();
    const h = await w.account();
    assert.equal((await w.call("PUT", "/v1/phone/sms-chat", h, { consent: true, textVersion: "sms-chat-v1" })).statusCode, 409);
    assert.equal((await w.call("GET", "/v1/phone", h)).json().smsChatEnabled, false);
    assert.deepEqual(await w.text("Jaka jutro pogoda?", sid(1)), ["ignored"], "chat off: no reply, no model call");
    assert.equal(w.responder!.seen.length, 0);

    assert.equal((await w.call("PUT", "/v1/phone/sms-consent", h, { consent: true, textVersion: "sms-v1" })).statusCode, 204);
    assert.deepEqual(await w.text("Jaka jutro pogoda?", sid(3)), ["ignored"], "texts on is not enough: texting Doddy has its own yes");
    assert.equal(w.responder!.seen.length, 0);
    await w.turnOn(h);
    assert.equal((await w.call("GET", "/v1/phone", h)).json().smsChatEnabled, true);
    assert.deepEqual(await w.text("Jaka jutro pogoda?", sid(2)), ["answered"]);
    assert.deepEqual(w.sms.sent, [{ to: PHONE, body: "Jutro w Warszawie 12°C." }]);
    const req = w.responder!.seen[0]!;
    assert.equal(req.userText, "Jaka jutro pogoda?");
    assert.deepEqual(req.memories, []);
    assert.equal(req.image, undefined);

    const { rows } = await db.query("SELECT body, body_ciphertext FROM outbound_messages WHERE idempotency_key = $1", [`sms-chat:${sid(2)}`]);
    assert.deepEqual(rows, [{ body: null, body_ciphertext: null }], "reply erased once sent");
    assert.ok(!JSON.stringify(w.logs).includes("pogoda"), "the person's words are never logged");
    await w.app.close();
  });

  test("a retried webhook answers and counts once", async () => {
    const w = await world();
    await w.turnOn(await w.account("+48500300401"));
    assert.deepEqual(await w.text("Ile to 3 mile w km?", sid(10), "+48500300401"), ["answered"]);
    assert.deepEqual(await w.text("Ile to 3 mile w km?", sid(10), "+48500300401"), ["duplicate"]);
    assert.equal(w.sms.sent.length, 1);
    assert.equal(w.responder!.seen.length, 1);
    await w.app.close();
  });

  test("unknown numbers, STOP and texts off get no reply", async () => {
    const w = await world();
    const h = await w.account("+48500300402");
    await w.turnOn(h);
    assert.deepEqual(await w.text("hej", sid(20), "+48999999999"), ["ignored"]);
    await w.text("STOP", sid(21), "+48500300402");
    assert.equal((await w.call("GET", "/v1/phone", h)).json().smsChatEnabled, false);
    assert.deepEqual(await w.text("hej", sid(22), "+48500300402"), ["ignored"]);
    await w.text("START", sid(23), "+48500300402");
    assert.deepEqual(await w.text("hej", sid(24), "+48500300402"), ["answered"], "START brings it back, consent kept");

    assert.equal((await w.call("PUT", "/v1/phone/sms-consent", h, { consent: false })).statusCode, 204);
    assert.deepEqual(await w.text("hej", sid(25), "+48500300402"), ["ignored"]);
    assert.equal((await w.call("PUT", "/v1/phone/sms-consent", h, { consent: true, textVersion: "sms-v1" })).statusCode, 204);
    assert.equal((await w.call("GET", "/v1/phone", h)).json().smsChatEnabled, false, "turning texts off cleared texting Doddy");
    assert.equal(w.responder!.seen.length, 1);
    await w.app.close();
  });

  test("daily cap, a refusal, a provider error and a card each get a fixed honest reply", async () => {
    const w = await world({ settings: { dailyPerAccount: 3 } });
    await w.turnOn(await w.account("+48500300403"));
    const from = "+48500300403";
    w.responder!.next.push(async () => ({ kind: "refused" }));
    w.responder!.next.push(async () => { throw new Error("boom"); });
    w.responder!.next.push(async () => ({
      kind: "ok", answer: "Zrobię prezentację o kotach.", sources: [], usage: { inputTokens: 1, outputTokens: 1 },
      proposal: { kind: "deck", title: "Koty", request: "prezentacja o kotach" },
    }));
    assert.deepEqual(await w.text("a", sid(30), from), ["unavailable"]);
    assert.deepEqual(await w.text("b", sid(31), from), ["unavailable"]);
    assert.deepEqual(await w.text("c", sid(32), from), ["answered"]);
    assert.deepEqual(await w.text("d", sid(33), from), ["limit"]);
    assert.deepEqual(w.sms.sent.map((s) => s.body), [
      SMS_CHAT_COPY.unavailable, SMS_CHAT_COPY.unavailable,
      "Zrobię prezentację o kotach.\n\n" + SMS_CHAT_COPY.needsApp, SMS_CHAT_COPY.limit,
    ]);
    await w.app.close();
  });

  test("with Messages off the person is told once per text; without the key nothing runs", async () => {
    const off = await world({ settings: { enabled: false } });
    await off.turnOn(await off.account("+48500300404"));
    assert.deepEqual(await off.text("hej", sid(40), "+48500300404"), ["off"]);
    assert.deepEqual(off.sms.sent.map((s) => s.body), [SMS_CHAT_COPY.off]);
    await off.app.close();

    const noKey = await world({ cipher: false });
    await noKey.turnOn(await noKey.account("+48500300405"));
    assert.deepEqual(await noKey.text("hej", sid(41), "+48500300405"), ["ignored"]);
    assert.equal(noKey.responder!.seen.length, 0);
    await noKey.app.close();
  });

  test("a new number starts with texting Doddy off", async () => {
    const w = await world();
    const h = await w.account("+48500300406");
    await w.turnOn(h);
    await w.call("POST", "/v1/phone/verification", h, { phone: "+48500300407" });
    await w.call("POST", "/v1/phone/verification/check", h, { phone: "+48500300407", code: "123456" });
    const p = (await w.call("GET", "/v1/phone", h)).json();
    assert.equal(p.phone, "+48500300407");
    assert.equal(p.smsChatEnabled, false);
    await w.app.close();
  });
});
