import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { textApprovalHash } from "../src/approval.js";
import { DEFAULT_ABUSE_LIMITS, type SmsCaps } from "../src/config.js";
import { sha256 } from "../src/crypto.js";
import type { Db } from "../src/db.js";
import { dispatchDue, enqueue, reconcileUnknownSms, SmsDailyLimit } from "../src/outbox.js";
import { estimateSmsSegments } from "../src/smsSegments.js";
import { dbSkip, FakeSms, freshDb, testApp, testCipher, twilioRequest } from "./helpers.js";
import { polish } from "./smsSamples.js";

// Segment-aware reservations (research item #4): a text reserves its estimated segments, not one slot.
describe("SMS segment reservations against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  const caps = (over: Partial<SmsCaps> = {}): SmsCaps => ({
    perAccount: 1000, perServer: 1000, segmentsPerAccount: 1000, segmentsPerServer: 1000, ...over,
  });
  const newAccount = async () => {
    const id = randomUUID();
    await db.query("INSERT INTO accounts (id) VALUES ($1)", [id]);
    return id;
  };
  const acctKey = (id: string) => sha256(id).toString("hex");
  const counter = async (scope: string, id: string) =>
    (await db.query<{ n: number }>("SELECT n FROM daily_counters WHERE scope = $1 AND key = $2 AND day = (now() AT TIME ZONE 'utc')::date", [scope, acctKey(id)])).rows[0]?.n ?? 0;
  const server = async (feature: string) =>
    (await db.query<{ requests: number }>("SELECT requests FROM server_daily_usage WHERE feature = $1 AND day = (now() AT TIME ZONE 'utc')::date", [feature])).rows[0]?.requests ?? 0;
  const put = (id: string, text: string, key: string, c: SmsCaps) => enqueue(db, id, ["sms"], text, new Date(), key, { cipher: testCipher, smsCaps: c });
  const reset = () => db.query("DELETE FROM daily_counters; DELETE FROM server_daily_usage; DELETE FROM outbound_messages");

  test("a 600-character Polish reply reserves 9 segments, a 134-character one 2, a short one 1; the estimate is stored", async () => {
    await reset();
    const id = await newAccount();
    await put(id, polish(600), "long", caps());
    await put(id, polish(134), "mid", caps());
    await put(id, "Cześć", "short", caps());
    assert.equal(await counter("sms_account", id), 3, "per-text count unchanged: one per text");
    assert.equal(await counter("sms_segments_account", id), 9 + 2 + 1);
    assert.equal(await server("sms"), 3);
    assert.equal(await server("sms_segments"), 12);
    const { rows } = await db.query<{ idempotency_key: string; est_segments: number }>("SELECT idempotency_key, est_segments FROM outbound_messages ORDER BY idempotency_key");
    assert.deepEqual(rows.map((r) => [r.idempotency_key, r.est_segments]), [["long", 9], ["mid", 2], ["short", 1]]);
  });

  test("the per-account segment cap refuses the text that would pass it and gives back everything that call took", async () => {
    await reset();
    const id = await newAccount();
    await put(id, polish(600), "a", caps({ segmentsPerAccount: 10 }));
    await assert.rejects(put(id, polish(134), "b", caps({ segmentsPerAccount: 10 })),
      (e: unknown) => e instanceof SmsDailyLimit && e.scope === "account" && e.unit === "segments");
    assert.equal(await counter("sms_account", id), 1, "the text slot was given back");
    assert.equal(await server("sms"), 1);
    assert.equal(await counter("sms_segments_account", id), 9);
    assert.equal(await server("sms_segments"), 9);
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [id])).rowCount, 1, "the refused text was not queued");
    // One segment still fits: the cap is on segments, not on texts.
    await put(id, "ok", "c", caps({ segmentsPerAccount: 10 }));
    assert.equal(await counter("sms_segments_account", id), 10);
  });

  test("the server segment cap refuses too, and the account's segments and texts come back", async () => {
    await reset();
    const a = await newAccount();
    const b = await newAccount();
    await put(a, polish(600), "a1", caps({ segmentsPerServer: 10 }));
    await assert.rejects(put(b, polish(134), "b1", caps({ segmentsPerServer: 10 })),
      (e: unknown) => e instanceof SmsDailyLimit && e.scope === "server" && e.unit === "segments");
    assert.deepEqual([await counter("sms_account", b), await counter("sms_segments_account", b), await server("sms"), await server("sms_segments")], [0, 0, 1, 9]);
  });

  test("a single text bigger than the whole cap is refused outright and counts nothing", async () => {
    await reset();
    const id = await newAccount();
    await assert.rejects(put(id, polish(600), "big", caps({ segmentsPerAccount: 5 })), SmsDailyLimit);
    assert.deepEqual([await counter("sms_account", id), await counter("sms_segments_account", id), await server("sms_segments")], [0, 0, 0]);
  });

  test("the per-text caps still work on their own, with the unit named", async () => {
    await reset();
    const id = await newAccount();
    await put(id, "a", "t1", caps({ perAccount: 2 }));
    await put(id, "b", "t2", caps({ perAccount: 2 }));
    await assert.rejects(put(id, "c", "t3", caps({ perAccount: 2 })),
      (e: unknown) => e instanceof SmsDailyLimit && e.scope === "account" && e.unit === "texts");
    assert.equal(await counter("sms_segments_account", id), 2, "refused at the first step: no segments taken");
  });

  test("a replay of a key already queued takes no segments", async () => {
    await reset();
    const id = await newAccount();
    await put(id, polish(600), "same", caps({ segmentsPerAccount: 9 }));
    await put(id, polish(600), "same", caps({ segmentsPerAccount: 9 }));
    assert.deepEqual([await counter("sms_account", id), await counter("sms_segments_account", id), await server("sms_segments")], [1, 9, 9]);
  });

  test("parallel texts cannot pass the segment cap together", async () => {
    await reset();
    const id = await newAccount();
    const c = caps({ segmentsPerAccount: 10 });
    const results = await Promise.allSettled(Array.from({ length: 12 }, (_, i) => put(id, polish(134), `p${i}`, c)));
    assert.equal(results.filter((r) => r.status === "fulfilled").length, 5, "5 texts of 2 segments fill 10");
    assert.ok(results.filter((r) => r.status === "rejected").every((r) => (r as PromiseRejectedResult).reason instanceof SmsDailyLimit));
    assert.equal(await counter("sms_segments_account", id), 10);
    assert.equal(await counter("sms_account", id), 5);
    assert.equal(await server("sms_segments"), 10);
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [id])).rowCount, 5);
  });

  test("a text queued without a transaction gives its segments back when the insert fails", async () => {
    await reset();
    const id = randomUUID(); // not in accounts: the insert fails on its foreign key
    await assert.rejects(put(id, polish(600), "fk", caps()));
    assert.deepEqual([await counter("sms_account", id), await counter("sms_segments_account", id), await server("sms"), await server("sms_segments")], [0, 0, 0, 0]);
  });

  test("push costs no segments", async () => {
    await reset();
    const id = await newAccount();
    await enqueue(db, id, ["push"], polish(600), new Date(), "push1", { cipher: testCipher, smsCaps: caps() });
    assert.deepEqual([await counter("sms_segments_account", id), await server("sms_segments")], [0, 0]);
    const { rows } = await db.query<{ est_segments: number | null }>("SELECT est_segments FROM outbound_messages WHERE account_id = $1", [id]);
    assert.equal(rows[0]!.est_segments, null);
  });

  test("the defaults are one text = up to 4 segments on average: 120 an account and 1,200 for the server a day", () => {
    assert.deepEqual([DEFAULT_ABUSE_LIMITS.smsSegmentsPerAccountDay, DEFAULT_ABUSE_LIMITS.smsSegmentsPerServerDay], [120, 1200]);
  });

  test("the day is the UTC day: yesterday's segments do not count against today", async () => {
    await reset();
    const id = await newAccount();
    await put(id, polish(600), "y1", caps({ segmentsPerAccount: 9 }));
    await assert.rejects(put(id, "x", "y2", caps({ segmentsPerAccount: 9 })), SmsDailyLimit);
    await db.query("UPDATE daily_counters SET day = day - 1; UPDATE server_daily_usage SET day = day - 1");
    await put(id, "x", "y3", caps({ segmentsPerAccount: 9 }));
    assert.equal(await counter("sms_segments_account", id), 1);
  });
});

// Twilio's own count, for reconciling the estimate with the bill.
describe("reported SMS segments against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let sms: FakeSms;
  before(async () => {
    db = await freshDb();
    ({ app, sms } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  let n = 0;
  async function texter(phone: string) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.2.0.${++n}` });
    const { deviceToken } = r.json() as { deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    assert.equal((await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } })).statusCode, 200);
    assert.equal((await app.inject({ method: "PUT", url: "/v1/phone/sms-consent", headers: h, payload: { consent: true, textVersion: "sms-v1" } })).statusCode, 204);
    return h;
  }
  const send = async (h: Record<string, string>, phone: string, body: string) => {
    const r = await app.inject({ method: "POST", url: "/v1/texts", headers: h,
      payload: { body, approvalHash: textApprovalHash(phone, body).toString("hex"), idempotencyKey: randomUUID() } });
    assert.equal(r.statusCode, 202, r.body);
    return r.json().messages[0].id as string;
  };
  const row = async (id: string) => (await db.query<{ est_segments: number; reported_segments: number | null; provider_message_id: string }>(
    "SELECT est_segments, reported_segments, provider_message_id FROM outbound_messages WHERE id = $1", [id])).rows[0]!;

  test("the estimate is kept after the text is erased; a final status with NumSegments records Twilio's count, other values are ignored", async () => {
    const phone = "+48500400001";
    const h = await texter(phone);
    const body = polish(600);
    const id = await send(h, phone, body);
    await dispatchDue(db, { sms, cipher: testCipher });
    const sent = await row(id);
    assert.equal(sent.est_segments, estimateSmsSegments(body).segments);
    assert.equal(sent.reported_segments, null);
    const hook = (form: Record<string, string>) => app.inject(twilioRequest("/webhooks/twilio/status", { MessageSid: sent.provider_message_id, ...form }));
    assert.equal((await hook({ MessageStatus: "queued", NumSegments: "1" })).statusCode, 204);
    assert.equal((await row(id)).reported_segments, null, "not final yet: not recorded");
    for (const bad of ["0", "abc", "999", "-3", ""]) {
      assert.equal((await hook({ MessageStatus: "delivered", NumSegments: bad })).statusCode, 204);
      assert.equal((await row(id)).reported_segments, null, JSON.stringify(bad));
    }
    assert.equal((await hook({ MessageStatus: "delivered" })).statusCode, 204, "a callback without NumSegments (the usual one) is fine");
    assert.equal((await hook({ MessageStatus: "delivered", NumSegments: "9" })).statusCode, 204);
    assert.deepEqual([(await row(id)).est_segments, (await row(id)).reported_segments], [9, 9]);
  });

  test("a text whose outcome was unknown gets Twilio's num_segments from the message lookup", async () => {
    const phone = "+48500400002";
    const h = await texter(phone);
    const body = "Segmenty do uzgodnienia";
    const id = await send(h, phone, body);
    sms.next = [{ kind: "unknown", code: "twilio_500" }];
    await dispatchDue(db, { sms, cipher: testCipher });
    await db.query("UPDATE outbound_messages SET updated_at = now() - interval '3 minutes' WHERE id = $1", [id]);
    sms.recent = [{ sid: "SMsegfound", body, createdAt: new Date(), status: "delivered", numSegments: 1 }];
    assert.equal(await reconcileUnknownSms(db, sms), 1);
    const r = await row(id);
    assert.deepEqual([r.provider_message_id, r.est_segments, r.reported_segments], ["SMsegfound", estimateSmsSegments(body).segments, 1]);
    sms.recent = [];
  });
});
