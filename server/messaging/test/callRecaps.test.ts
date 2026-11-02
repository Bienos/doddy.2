// Recaps of S2 calls (ADR-693): the rules on their own, then the whole path against real Postgres:
// call-start → note → signed post-call webhook → worker → GET → ack (receipts) → expiry.
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import {
  buildRecap, claimsSaving, PIN_MASK, transcriptFrom,
  type RecapWriter, type RecapWriterInput, type RecapWriterOutput, type StoredInput,
} from "../src/callRecaps/recap.js";
import { runRecapPasses } from "../src/callRecaps/service.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { dbSkip, EL_WEBHOOK_SECRET, freshDb, testApp, TOOL_SECRET } from "./helpers.js";

const PHONE_AGENT = "agent_phone_test";
const NOW = new Date("2026-11-02T12:00:00Z");

const input = (turns: [("doddy" | "caller"), string, string[]?][]): StoredInput => ({
  turns: turns.map(([role, text, tools], i) => ({ role, text, atSecs: i * 3, tools: tools ?? [] })),
  durationSecs: 42, startUnix: Math.floor(NOW.getTime() / 1000) - 60,
});

const SAMPLE = input([
  ["doddy", "Hi, this is Doddy, an AI assistant. How can I help?"],
  ["caller", "Mój PIN to 2 5 8 0 2 5."],
  ["doddy", "", ["verify_pin"]],
  ["doddy", "Dziękuję, PIN się zgadza."],
  ["caller", "Zapisz, że jutro o 10 mam dentystę."],
  ["doddy", "", ["save_note"]],
  ["doddy", "Notatka czeka w aplikacji Doddy na Twoje potwierdzenie."],
  ["caller", "I wyślij SMS do Ani."],
  ["doddy", "Na rozmowie nie mogę wysyłać wiadomości."],
]);

describe("call recap rules", () => {
  test("the caller's PIN is masked before the verify_pin call, and nothing else is", () => {
    const { lines, tools } = transcriptFrom(SAMPLE);
    assert.equal(lines[1]!.text, `Mój PIN to ${PIN_MASK}.`);
    assert.match(lines[3]!.text, /jutro o 10 mam/); // a later caller line keeps its digits
    assert.deepEqual(tools.map((t) => t.name), ["verify_pin", "save_note"]);
    assert.equal(lines.length, 7); // tool-only turns have no line
  });

  test("save claims are caught in English and Polish, requests are not", () => {
    for (const s of ["Doddy saved your note.", "Notatka została zapisana.", "Zapisałem to.", "Doddy zapamiętał, że…"]) {
      assert.equal(claimsSaving(s), true, s);
    }
    for (const s of ["Poprosiłeś, żeby zapisać wizytę u dentysty.", "You asked Doddy to remember the dentist.", "Zapisz to."]) {
      assert.equal(claimsSaving(s), false, s);
    }
  });

  const facts = { callId: "c1", direction: "inbound" as const, input: SAMPLE, notes: [], now: NOW };
  const proposal = (over: Partial<RecapWriterOutput> = {}): RecapWriterOutput => ({
    summary: "Poprosiłeś o notatkę o jutrzejszej wizycie u dentysty i o SMS do Ani.",
    language: "pl",
    agreed: [{ text: "Dentysta jutro o 10", line: 3, quote: "jutro o 10 mam dentystę" }],
    couldNotDo: [{ text: "SMS do Ani", line: 6, quote: "nie mogę wysyłać wiadomości" }],
    nextStep: "Potwierdź notatkę w aplikacji.",
    ...over,
  });

  test("a model proposal is kept only where it matches the transcript", () => {
    const r = buildRecap(facts, proposal({
      agreed: [
        { text: "Dentysta jutro o 10", line: 3, quote: "jutro o 10 mam dentystę" },
        { text: "Made up", line: 3, quote: "pojutrze o 12" }, // not in that line
        { text: "Out of range", line: 99, quote: "x" },
      ],
      couldNotDo: [{ text: "Caller line, not Doddy's", line: 5, quote: "wyślij SMS do Ani" }],
    }), null);
    assert.equal(r.summaryBy, "doddy_model");
    assert.deepEqual(r.agreed.map((a) => a.line), [3]);
    assert.equal(r.couldNotDo.length, 0);
    assert.equal(r.droppedPointers, 3);
    assert.equal(r.transcript[1]!.text.includes("2 5 8"), false);
  });

  test("a summary that says something was saved is replaced by the rules", () => {
    const r = buildRecap(facts, proposal({ summary: "Doddy zapisał notatkę o dentyście." }), null);
    assert.equal(r.summary, null);
    assert.equal(r.summaryBy, "rules");
    assert.equal(r.summaryNote, "save_claim");
    assert.equal(r.agreed.length, 0);
    assert.equal(r.transcript.length, 7);
  });

  test("without a model the recap says why it has no summary", () => {
    const r = buildRecap(facts, null, "no_writer");
    assert.equal(r.summary, null);
    assert.equal(r.summaryNote, "no_writer");
    assert.equal(r.durationSecs, 42);
  });
});

class FakeRecapWriter implements RecapWriter {
  readonly model = "fake";
  inputs: RecapWriterInput[] = [];
  next: (RecapWriterOutput | Error)[] = [];
  async write(i: RecapWriterInput): Promise<RecapWriterOutput> {
    this.inputs.push(i);
    const n = this.next.shift() ?? {
      summary: "Poprosiłeś o notatkę o dentyście.", language: "pl",
      agreed: [{ text: "Dentysta jutro", line: 3, quote: "jutro o 10 mam dentystę" }], couldNotDo: [], nextStep: null,
    };
    if (n instanceof Error) throw n;
    return n;
  }
}

describe("call recaps against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let writer: FakeRecapWriter;
  let clock = NOW;
  const logs: string[] = [];

  before(async () => {
    db = await freshDb();
    writer = new FakeRecapWriter();
    ({ app } = await testApp(db, {
      callRecaps: { phoneAgentId: PHONE_AGENT, webhookSecret: EL_WEBHOOK_SECRET, writer, now: () => clock,
        settings: { dailyPerAccount: 2, dailyPerServer: 100 } },
      callRecapLog: (msg) => logs.push(msg),
    }));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });
  beforeEach(() => { clock = new Date(Date.now()); });

  const ctx = () => app.callRecapContext!;
  const el = (url: string, payload: object, session?: string) => app.inject({
    method: "POST", url, payload, headers: { "x-doddy-tool-secret": TOOL_SECRET, ...(session ? { "x-doddy-session": session } : {}) },
  });
  function postCall(data: object, secret = EL_WEBHOOK_SECRET, type = "post_call_transcription") {
    const body = JSON.stringify({ type, event_timestamp: 1, data });
    return app.inject({
      method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body,
      headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(secret, body) },
    });
  }
  const conversation = (id: string, sid: string | null, turns = SAMPLE.turns) => ({
    agent_id: PHONE_AGENT, conversation_id: id,
    transcript: turns.map((t) => ({
      role: t.role === "doddy" ? "agent" : "user", message: t.text || null, time_in_call_secs: t.atSecs,
      tool_calls: t.tools.map((tool_name) => ({ tool_name, params_as_json: "{\"pin\":\"258025\"}" })),
    })),
    metadata: { call_duration_secs: 42, start_time_unix_secs: 1793600000, phone_call: sid ? { call_sid: sid, external_number: "+48500000001" } : null },
    analysis: { transcript_summary: "ignored" },
  });

  let n = 0;
  async function user(opts: { inbound?: boolean } = { inbound: true }) {
    n++;
    const phone = `+4850000${String(n).padStart(4, "0")}`;
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    assert.equal((await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } })).statusCode, 200);
    assert.equal((await app.inject({ method: "PUT", url: "/v1/calls/pin", headers: h, payload: { pin: "258025" } })).statusCode, 204);
    if (opts.inbound) assert.equal((await app.inject({ method: "PUT", url: "/v1/calls/settings", headers: h, payload: { inboundEnabled: true } })).statusCode, 204);
    return { accountId, h, phone };
  }
  /** An inbound call with a note, as ElevenLabs drives it (no conversation id at call start). */
  async function inboundCallWithNote(phone: string, sid: string) {
    const start = await el("/webhooks/elevenlabs/call-start", { caller_id: phone, called_number: "+48221234567", call_sid: sid });
    const vars = (start.json() as { dynamic_variables: Record<string, string> }).dynamic_variables;
    const session = vars.secret__doddy_session!;
    assert.equal((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, session)).json().status, "verified");
    assert.equal((await el("/webhooks/elevenlabs/tools/save-note", { text: "Jutro o 10 dentysta" }, session)).json().status, "saved_for_confirmation");
  }
  const calls = async (h: object) =>
    ((await app.inject({ method: "GET", url: "/v1/calls", headers: h as Record<string, string> })).json() as { calls: { id: string; recap: string }[] }).calls;

  test("an inbound call gets a recap: summary, checked pointers, its note, masked PIN; ack deletes the server copy", async () => {
    const { h, phone } = await user();
    await inboundCallWithNote(phone, "CA" + "1".repeat(32));
    const [call] = await calls(h);
    assert.equal(call!.recap, "none");

    assert.equal((await postCall(conversation("conv_r1", "CA" + "1".repeat(32)))).statusCode, 200);
    assert.equal((await calls(h))[0]!.recap, "waiting");
    const waiting = await app.inject({ method: "GET", url: `/v1/calls/${call!.id}/recap`, headers: h });
    assert.deepEqual(waiting.json(), { callId: call!.id, state: "waiting" });

    const counts = await runRecapPasses(ctx());
    assert.equal(counts.built_model, 1);
    // The model saw the masked PIN, never the digits.
    assert.equal(JSON.stringify(writer.inputs.at(-1)).includes("2 5 8 0"), false);
    assert.ok(JSON.stringify(writer.inputs.at(-1)).includes(PIN_MASK));

    const got = await app.inject({ method: "GET", url: `/v1/calls/${call!.id.toUpperCase()}/recap`, headers: h });
    assert.equal(got.statusCode, 200);
    const body = got.json() as { state: string; digest: string; recap: { summary: string; summaryBy: string; agreed: unknown[]; notes: { text: string }[]; transcript: { text: string }[] } };
    assert.equal(body.state, "ready");
    assert.equal(body.recap.summaryBy, "doddy_model");
    assert.equal(body.recap.agreed.length, 1);
    assert.deepEqual(body.recap.notes.map((x) => x.text), ["Jutro o 10 dentysta"]);
    assert.equal(body.recap.transcript.some((l) => /2 5 8/.test(l.text)), false);
    // The raw transcript is gone from the database once the recap is built.
    const { rows } = await db.query("SELECT input_ciphertext FROM call_recaps WHERE call_id = $1", [call!.id]);
    assert.equal(rows[0].input_ciphertext, null);

    assert.equal((await app.inject({ method: "POST", url: `/v1/calls/${call!.id}/recap/ack`, headers: h, payload: { digest: "0".repeat(64) } })).statusCode, 409);
    const ack = await app.inject({ method: "POST", url: `/v1/calls/${call!.id}/recap/ack`, headers: h, payload: { digest: body.digest } });
    assert.equal(ack.statusCode, 200);
    assert.deepEqual((ack.json() as { deletions: { what: string; reason: string }[] }).deletions.map((d) => `${d.what}:${d.reason}`),
      ["input:recap_built", "recap:acked"]);
    // A repeated ack (a lost reply) gets the same answer.
    assert.equal((await app.inject({ method: "POST", url: `/v1/calls/${call!.id}/recap/ack`, headers: h, payload: { digest: body.digest } })).statusCode, 200);
    const { rows: after } = await db.query("SELECT state, recap_ciphertext FROM call_recaps WHERE call_id = $1", [call!.id]);
    assert.deepEqual(after[0], { state: "acked", recap_ciphertext: null });
    assert.equal((await calls(h))[0]!.recap, "acked");
  });

  test("Call me now is matched by conversation id; another account can't read or ack it", async () => {
    const a = await user();
    const outbound = await app.inject({ method: "PUT", url: "/v1/calls/settings", headers: a.h, payload: { outboundConsent: true, outboundConsentTextVersion: "calls-v1" } });
    assert.equal(outbound.statusCode, 204);
    const placed = await app.inject({ method: "POST", url: "/v1/calls/outbound", headers: a.h });
    assert.equal(placed.statusCode, 202);
    const { rows } = await db.query<{ conversation_id: string }>("SELECT conversation_id FROM calls WHERE id = $1", [placed.json().callId]);
    assert.equal((await postCall(conversation(rows[0]!.conversation_id, null))).statusCode, 200);
    await runRecapPasses(ctx());
    const callId = placed.json().callId as string;
    const mine = await app.inject({ method: "GET", url: `/v1/calls/${callId}/recap`, headers: a.h });
    assert.equal(mine.json().state, "ready");
    assert.equal(mine.json().recap.direction, "outbound");
    assert.deepEqual(mine.json().recap.notes, []);

    const b = await user();
    assert.equal((await app.inject({ method: "GET", url: `/v1/calls/${callId}/recap`, headers: b.h })).statusCode, 404);
    assert.equal((await app.inject({ method: "POST", url: `/v1/calls/${callId}/recap/ack`, headers: b.h, payload: { digest: mine.json().digest } })).statusCode, 404);
    assert.equal((await app.inject({ method: "DELETE", url: `/v1/calls/${callId}/recap`, headers: b.h })).statusCode, 404);
  });

  test("unknown callers, callers with calls off, other agents and bad signatures leave nothing behind", async () => {
    const before = (await db.query("SELECT count(*)::int AS n FROM call_recaps")).rows[0].n;
    const off = await user({ inbound: false });
    const start = await el("/webhooks/elevenlabs/call-start", { caller_id: off.phone, call_sid: "CA" + "2".repeat(32) });
    assert.equal(start.json().dynamic_variables.doddy_caller, "calls_off");
    assert.equal((await postCall(conversation("conv_off", "CA" + "2".repeat(32)))).statusCode, 200);
    assert.equal((await postCall(conversation("conv_unknown", "CA" + "3".repeat(32)))).statusCode, 200);
    assert.equal((await postCall({ ...conversation("conv_other", "CA" + "1".repeat(32)), agent_id: "agent_someone_else" })).statusCode, 200);
    assert.equal((await postCall(conversation("conv_bad", "CA" + "1".repeat(32)), "wrong-secret-0123456789")).statusCode, 401);
    assert.equal((await postCall(conversation("conv_audio", "CA" + "1".repeat(32)), EL_WEBHOOK_SECRET, "post_call_audio")).statusCode, 200);
    assert.equal((await db.query("SELECT count(*)::int AS n FROM call_recaps")).rows[0].n, before);
  });

  test("a replayed webhook stores nothing twice; a failing writer is retried once, then the rules build it", async () => {
    const { h, phone } = await user();
    const sid = "CA" + "4".repeat(32);
    await inboundCallWithNote(phone, sid);
    assert.equal((await postCall(conversation("conv_r4", sid))).statusCode, 200);
    assert.equal((await postCall(conversation("conv_r4", sid))).statusCode, 200);
    const [call] = await calls(h);
    assert.equal((await db.query("SELECT count(*)::int AS n FROM call_recaps WHERE call_id = $1", [call!.id])).rows[0].n, 1);

    writer.next.push(new Error("overloaded"), new Error("overloaded"));
    assert.equal((await runRecapPasses(ctx())).retry, 1);
    clock = new Date(Date.now() + 4 * 60_000);
    assert.equal((await runRecapPasses(ctx())).built_rules, 1);
    const r = (await app.inject({ method: "GET", url: `/v1/calls/${call!.id}/recap`, headers: h })).json();
    assert.equal(r.recap.summary, null);
    assert.equal(r.recap.summaryNote, "writer_failed");
    assert.equal(r.recap.notes.length, 1);
  });

  test("past the account's daily cap the recap is built without the model; Delete wipes it with a receipt", async () => {
    const { h, phone } = await user();
    const ids: string[] = [];
    for (const k of [5, 6, 7]) {
      const sid = "CA" + String(k).repeat(32);
      await inboundCallWithNote(phone, sid);
      await postCall(conversation(`conv_cap_${k}`, sid));
      await runRecapPasses(ctx());
      ids.push((await calls(h))[0]!.id);
    }
    const notes = [];
    for (const id of ids) notes.push((await app.inject({ method: "GET", url: `/v1/calls/${id}/recap`, headers: h })).json().recap.summaryNote);
    assert.deepEqual(notes, [null, null, "daily_limit"]);

    const del = await app.inject({ method: "DELETE", url: `/v1/calls/${ids[2]}/recap`, headers: h });
    assert.equal(del.statusCode, 200);
    assert.deepEqual(del.json().deletions.map((d: { what: string; reason: string }) => `${d.what}:${d.reason}`), ["input:recap_built", "recap:deleted"]);
    assert.equal((await app.inject({ method: "GET", url: `/v1/calls/${ids[2]}/recap`, headers: h })).json().state, "deleted");
  });

  test("a recap nobody saved is wiped after 30 days; deleting the account removes every row", async () => {
    const { accountId, h, phone } = await user();
    const sid = "CA" + "8".repeat(32);
    await inboundCallWithNote(phone, sid);
    await postCall(conversation("conv_old", sid));
    await runRecapPasses(ctx());
    const [call] = await calls(h);
    clock = new Date(Date.now() + 31 * 24 * 3600_000);
    assert.ok(((await runRecapPasses(ctx())).expired ?? 0) >= 1);
    const { rows } = await db.query("SELECT state, recap_ciphertext FROM call_recaps WHERE call_id = $1", [call!.id]);
    assert.deepEqual(rows[0], { state: "expired", recap_ciphertext: null });

    assert.equal((await app.inject({ method: "DELETE", url: "/v1/account", headers: h })).statusCode < 300, true);
    for (const t of ["call_recaps", "call_recap_deletions", "calls"]) {
      assert.equal((await db.query(`SELECT count(*)::int AS n FROM ${t} WHERE account_id = $1`, [accountId])).rows[0].n, 0, t);
    }
  });
});
