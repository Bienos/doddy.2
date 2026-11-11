// Recaps of calls to Doddy's phone line (decision 2026-11-09-conversation-recaps, step 5): the post-call webhook,
// what is stored (the three lists, encrypted; never the transcript), and what the iPhone reads and deletes.
// Real Postgres, a fake writer; nothing here calls Anthropic or ElevenLabs.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import type { RecapInput, RecapOutcome, RecapWriter } from "../src/assistant/recap.js";
import { DEFAULT_ASSISTANT_SETTINGS } from "../src/config.js";
import type { Db } from "../src/db.js";
import { onPhonePostCall, type PhoneRecapContext } from "../src/phoneRecaps.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";

const AGENT = "agent_phone_1";
const SECRET = "phone-recap-webhook-secret-123";
const PHRASE = "Hala Koszyki w czwartek o osiemnastej";
const CALLER_WORDS = `Dzień dobry, chciałbym się umówić na spotkanie z Anną. Najlepiej w czwartek wieczorem, ${PHRASE}, bo mam wtedy wolne i mogę przyjść spokojnie. Proszę zapisać to u siebie i przypomnieć mi dzień wcześniej, dziękuję bardzo.`;

class FakeWriter implements RecapWriter {
  readonly model = "claude-haiku-5-5";
  seen: RecapInput[] = [];
  steps: (() => Promise<RecapOutcome>)[] = [];
  async write(req: RecapInput): Promise<RecapOutcome> {
    this.seen.push(req);
    const step = this.steps.shift();
    return step ? step() : {
      kind: "ok", usage: { inputTokens: 400, outputTokens: 50 },
      recap: { discussed: ["Spotkanie z Anną"], agreed: ["Czwartek wieczorem"], to_do: ["Przypomnieć dzień wcześniej"] },
    };
  }
}

const payload = (over: { agent?: string; conv?: string; sid?: string | null; said?: string } = {}) => ({
  type: "post_call_transcription",
  data: {
    agent_id: over.agent ?? AGENT, conversation_id: over.conv ?? "conv_1",
    transcript: [
      { role: "agent", message: "Cześć, tu Doddy. W czym mogę pomóc?", time_in_call_secs: 0 },
      { role: "user", message: over.said ?? CALLER_WORDS, time_in_call_secs: 4 },
      { role: "agent", message: "Zapisałem, czwartek wieczorem.", time_in_call_secs: 20 },
    ],
    metadata: { call_duration_secs: 95, phone_call: over.sid === null ? null : { call_sid: over.sid ?? "CA111" } },
  },
});

describe("phone-line recaps against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => {
    await db.query("DELETE FROM phone_recaps; DELETE FROM calls; DELETE FROM call_settings; DELETE FROM assistant_usage; DELETE FROM server_daily_usage");
  });

  async function world(over: { writer?: FakeWriter | null; phoneAgentId?: string | null; settings?: Partial<typeof DEFAULT_ASSISTANT_SETTINGS> } = {}) {
    const writer = over.writer === null ? undefined : over.writer ?? new FakeWriter();
    const deps = {
      phoneAgentId: over.phoneAgentId === null ? undefined : over.phoneAgentId ?? AGENT, webhookSecret: SECRET, writer,
      settings: { ...DEFAULT_ASSISTANT_SETTINGS, enabled: true, ...over.settings },
    };
    const base = await testApp(db, { phoneRecaps: deps });
    const logs: [string, object | undefined][] = [];
    const ctx: PhoneRecapContext = { db, cipher: testCipher, deps, log: (m, e) => logs.push([m, e]) };
    const account = async () => {
      const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
      const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
      return { accountId, h: { authorization: `Bearer ${deviceToken}` } };
    };
    const call = async (accountId: string, sid = "CA111", direction: "inbound" | "outbound" = "inbound") => {
      const id = randomUUID();
      await db.query("INSERT INTO calls (id, account_id, direction, status, call_sid) VALUES ($1, $2, $3, 'started', $4)", [id, accountId, direction, sid]);
      return id;
    };
    const setRecaps = (h: Record<string, string>, enabled: boolean) =>
      base.app.inject({ method: "PUT", url: "/v1/calls/recaps/settings", headers: { ...h, "content-type": "application/json" }, payload: JSON.stringify({ enabled }) });
    const list = (h: Record<string, string>) => base.app.inject({ method: "GET", url: "/v1/calls/recaps", headers: h });
    return { ...base, writer, ctx, logs, account, call, setRecaps, list };
  }

  test("nothing is made while recaps are off, and the writer is never asked", async () => {
    const w = await world();
    const a = await w.account();
    await w.call(a.accountId);
    assert.equal(await onPhonePostCall(w.ctx, payload()), "off");
    assert.equal((await db.query("SELECT 1 FROM phone_recaps")).rowCount, 0);
    assert.equal(w.writer!.seen.length, 0, "the transcript went nowhere");
    assert.deepEqual((await w.list(a.h)).json(), { schemaVersion: 1, enabled: false, recaps: [], unreadable: [] });
  });

  test("a call of an account with recaps on becomes three lists, stored encrypted, and not one word of the call", async () => {
    const w = await world();
    const a = await w.account();
    const callId = await w.call(a.accountId, "CA111", "outbound");
    assert.deepEqual((await w.setRecaps(a.h, true)).json(), { schemaVersion: 1, enabled: true });

    assert.equal(await onPhonePostCall(w.ctx, payload()), "stored");
    assert.equal(await onPhonePostCall(w.ctx, payload()), "duplicate", "one recap per call");

    const input = w.writer!.seen[0]!;
    assert.equal(input.kind, "phone_line");
    assert.deepEqual(input.lines.map((l) => l.speaker), ["doddy", "person", "doddy"], "the caller is the person, the agent is Doddy");

    const res = await w.list(a.h);
    assert.equal(res.statusCode, 200, res.body);
    const body = res.json();
    assert.equal(body.enabled, true);
    assert.equal(body.recaps.length, 1);
    assert.deepEqual({ ...body.recaps[0], endedAt: "x" }, {
      callId, discussed: ["Spotkanie z Anną"], agreed: ["Czwartek wieczorem"], to_do: ["Przypomnieć dzień wcześniej"],
      endedAt: "x", durationSecs: 95, direction: "outbound",
    });

    // The transcript is nowhere: no table holds a word of it, and the log carries counts only.
    const { rows: tables } = await db.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'");
    for (const { table_name } of tables) {
      const dump = JSON.stringify((await db.query(`SELECT * FROM "${table_name}"`)).rows);
      assert.ok(!dump.includes("Koszyki") && !dump.includes("Spotkanie z Ann") && !dump.includes("Czwartek wieczorem"), table_name);
    }
    assert.ok(!JSON.stringify(w.logs).includes("Koszyki"));
    const { rows } = await db.query("SELECT requests, input_tokens, output_tokens FROM assistant_usage WHERE account_id = $1", [a.accountId]);
    assert.deepEqual(rows.map((r) => [r.requests, Number(r.input_tokens), Number(r.output_tokens)]), [[1, 400, 50]], "one Messages request");
  });

  test("the iPhone's save is the end of it: delete once, then it is gone; nobody else can read or delete it", async () => {
    const w = await world();
    const a = await w.account();
    const b = await w.account();
    const callId = await w.call(a.accountId);
    await w.setRecaps(a.h, true);
    await onPhonePostCall(w.ctx, payload());
    assert.equal((await w.list(b.h)).json().recaps.length, 0, "another account reads none");
    const foreign = await w.app.inject({ method: "DELETE", url: `/v1/calls/recaps/${callId}`, headers: b.h });
    assert.equal(foreign.statusCode, 404);
    assert.equal((await w.list(a.h)).json().recaps.length, 1);
    assert.equal((await w.app.inject({ method: "DELETE", url: `/v1/calls/recaps/${callId}`, headers: a.h })).statusCode, 204);
    assert.equal((await w.app.inject({ method: "DELETE", url: `/v1/calls/recaps/${callId}`, headers: a.h })).statusCode, 404);
    assert.equal((await w.list(a.h)).json().recaps.length, 0);
    assert.equal((await w.app.inject({ method: "DELETE", url: "/v1/calls/recaps/not-a-uuid", headers: a.h })).statusCode, 400);
    assert.equal((await w.app.inject({ method: "GET", url: "/v1/calls/recaps" })).statusCode, 401);
  });

  test("turning recaps off deletes the ones waiting, and stops new ones", async () => {
    const w = await world();
    const a = await w.account();
    await w.call(a.accountId);
    await w.setRecaps(a.h, true);
    await onPhonePostCall(w.ctx, payload());
    assert.equal((await db.query("SELECT 1 FROM phone_recaps")).rowCount, 1);
    await w.setRecaps(a.h, false);
    assert.equal((await db.query("SELECT 1 FROM phone_recaps")).rowCount, 0);
    await w.call(a.accountId, "CA222");
    assert.equal(await onPhonePostCall(w.ctx, payload({ sid: "CA222", conv: "conv_2" })), "off");
    assert.equal((await w.app.inject({ method: "PUT", url: "/v1/calls/recaps/settings", headers: { ...a.h, "content-type": "application/json" }, payload: JSON.stringify({ enabled: "yes" }) })).statusCode, 400);
  });

  test("a call that isn't matched, another agent's call, a short call and a failed model have no recap", async () => {
    const w = await world();
    const a = await w.account();
    await w.call(a.accountId);
    await w.setRecaps(a.h, true);
    assert.equal(await onPhonePostCall(w.ctx, payload({ sid: "CA-unknown", conv: "conv_x" })), "unmatched");
    assert.equal(await onPhonePostCall(w.ctx, payload({ agent: "agent_other" })), "ignored");
    assert.equal(await onPhonePostCall(w.ctx, payload({ said: "Cześć, to ja." })), "tooShort");
    assert.equal(await onPhonePostCall(w.ctx, { type: "post_call_audio", data: {} }), "unreadable");
    assert.equal(await onPhonePostCall(w.ctx, { type: "post_call_transcription", data: { agent_id: AGENT } }), "unreadable");
    assert.equal(w.writer!.seen.length, 0);

    w.writer!.steps.push(async () => ({ kind: "refused" }));
    assert.equal(await onPhonePostCall(w.ctx, payload()), "failed");
    w.writer!.steps.push(async () => { throw new Error("network"); });
    assert.equal(await onPhonePostCall(w.ctx, payload()), "failed");
    assert.equal((await db.query("SELECT 1 FROM phone_recaps")).rowCount, 0);
    assert.equal(await onPhonePostCall(w.ctx, payload()), "stored", "a failed one can be made when ElevenLabs sends it again");
  });

  test("the Messages daily cap stops recaps; without a writer or an agent there are none", async () => {
    const capped = await world({ settings: { dailyPerAccount: 1 } });
    const a = await capped.account();
    await capped.call(a.accountId, "CA1");
    await capped.call(a.accountId, "CA2");
    await capped.setRecaps(a.h, true);
    assert.equal(await onPhonePostCall(capped.ctx, payload({ sid: "CA1", conv: "c1" })), "stored");
    assert.equal(await onPhonePostCall(capped.ctx, payload({ sid: "CA2", conv: "c2" })), "cap");
    assert.equal(capped.writer!.seen.length, 1);

    const none = await world({ writer: null });
    const b = await none.account();
    await none.call(b.accountId);
    await none.setRecaps(b.h, true);
    assert.equal(await onPhonePostCall(none.ctx, payload()), "off");
    const noAgent = await world({ phoneAgentId: null });
    assert.equal(await onPhonePostCall(noAgent.ctx, payload()), "ignored");
  });

  test("a recap older than 30 days is gone when the app next asks", async () => {
    const w = await world();
    const a = await w.account();
    const callId = await w.call(a.accountId);
    await w.setRecaps(a.h, true);
    await onPhonePostCall(w.ctx, payload());
    await db.query("UPDATE phone_recaps SET created_at = now() - interval '31 days' WHERE call_id = $1", [callId]);
    assert.equal((await w.list(a.h)).json().recaps.length, 0);
    assert.equal((await db.query("SELECT 1 FROM phone_recaps")).rowCount, 0);
  });

  test("a recap that won't decrypt is listed apart and can still be deleted", async () => {
    const w = await world();
    const a = await w.account();
    const callId = await w.call(a.accountId);
    await w.setRecaps(a.h, true);
    await db.query("INSERT INTO phone_recaps (call_id, account_id, key_version, ciphertext) VALUES ($1, $2, 1, $3)", [callId, a.accountId, Buffer.alloc(40, 1)]);
    const body = (await w.list(a.h)).json();
    assert.deepEqual([body.recaps, body.unreadable], [[], [callId]]);
    assert.equal((await w.app.inject({ method: "DELETE", url: `/v1/calls/recaps/${callId}`, headers: a.h })).statusCode, 204);
  });

  test("the workspace webhook: signed or nothing, answered at once, and the recap follows", async () => {
    const w = await world();
    const a = await w.account();
    await w.call(a.accountId);
    await w.setRecaps(a.h, true);
    const body = JSON.stringify(payload());
    const post = (sig: string | undefined, b = body) => w.app.inject({
      method: "POST", url: "/webhooks/elevenlabs/post-call", payload: b,
      headers: { "content-type": "application/json", ...(sig ? { "elevenlabs-signature": sig } : {}) },
    });
    assert.equal((await post(undefined)).statusCode, 401);
    assert.equal((await post(signElevenLabs("another-secret-another-secret", body))).statusCode, 401);
    assert.equal(w.writer!.seen.length, 0);

    assert.equal((await post(signElevenLabs(SECRET, body))).statusCode, 200);
    for (let i = 0; i < 50 && (await w.list(a.h)).json().recaps.length === 0; i++) await new Promise((r) => setTimeout(r, 40));
    assert.equal((await w.list(a.h)).json().recaps.length, 1);

    const other = JSON.stringify(payload({ agent: "agent_task_or_other", conv: "conv_9" }));
    assert.equal((await post(signElevenLabs(SECRET, other), other)).statusCode, 200, "always 200 once verified");
    assert.equal(w.writer!.seen.length, 1, "another agent's call is not read");
  });
});
