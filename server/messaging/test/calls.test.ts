import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { isAcceptablePin } from "../src/crypto.js";
import type { Db } from "../src/db.js";
import { searchMemories } from "../src/memorySearch.js";
import { bodyAad, dispatchDue } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import {
  BASE_URL, CONNECT_TWIML, dbSkip, DODDY_NUMBER, FakeOutbound, FakePush, FakeRegistrar, FakeSms, freshDb, testApp,
  testCipher, TOOL_SECRET, TWILIO_TOKEN, twilioRequest,
} from "./helpers.js";

test("PIN rules reject trivial PINs", () => {
  for (const bad of ["123", "2580", "11111", "111111", "123456", "987654", "012345", "12a456", "123456789"]) {
    assert.equal(isAcceptablePin(bad), false, bad);
  }
  for (const ok of ["258025", "135792", "904216", "90421688"]) assert.equal(isAcceptablePin(ok), true, ok);
});

test("memory search folds diacritics and only returns matches", () => {
  const m = [
    { id: "1", text: "Klucze do piwnicy są u pani Łucji", capturedAt: new Date("2026-01-01") },
    { id: "2", text: "Dentist on Tuesday at 15:00", capturedAt: new Date("2026-02-01") },
  ];
  assert.deepEqual(searchMemories(m, "gdzie są klucze lucja").map((h) => h.id), ["1"]);
  assert.deepEqual(searchMemories(m, "when is the dentist?").map((h) => h.id), ["2"]);
  assert.deepEqual(searchMemories(m, "passport"), []);
});

describe("phone calls against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let push: FakePush;
  let sms: FakeSms;
  let outbound: FakeOutbound;
  let registrar: FakeRegistrar;

  before(async () => {
    db = await freshDb();
    ({ app, push, sms, outbound, registrar } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  const call = (method: "GET" | "POST" | "PUT" | "DELETE", url: string, headers: object, payload?: object) =>
    app.inject({ method, url, headers: headers as Record<string, string>, payload });
  const el = (url: string, payload: object, session?: string, secret = TOOL_SECRET) =>
    app.inject({
      method: "POST", url, payload,
      headers: { "x-doddy-tool-secret": secret, ...(session ? { "x-doddy-session": session } : {}) },
    });

  /** Account with a verified number; optionally PIN, inbound calls and a memory copy. */
  let accounts = 0;
  async function user(phone: string, opts: { pin?: string; inbound?: boolean; memories?: string[] } = {}) {
    // Account creation is limited per IP (ADR-175); each test account comes from its own address.
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.0.0.${++accounts}` });
    assert.equal(r.statusCode, 201);
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    assert.equal((await call("POST", "/v1/phone/verification/check", h, { phone, code: "123456" })).statusCode, 200);
    if (opts.pin) assert.equal((await call("PUT", "/v1/calls/pin", h, { pin: opts.pin })).statusCode, 204);
    if (opts.inbound) assert.equal((await call("PUT", "/v1/calls/settings", h, { inboundEnabled: true })).statusCode, 204);
    if (opts.memories) {
      assert.equal((await call("PUT", "/v1/memory-copy", h, { enabled: true })).statusCode, 204);
      // Uppercase ids, as iOS's UUID.uuidString sends them.
      const items = opts.memories.map((text) => ({ id: randomUUID().toUpperCase(), text, capturedAt: "2026-09-01T10:00:00Z" }));
      assert.equal((await call("PUT", "/v1/memory-copy/snapshot", h, { items })).statusCode, 200);
    }
    return { accountId, h };
  }

  let sids = 0;
  /** Calls Doddy's number from `caller` the way Twilio does. `variables` are what the phone agent got, if reached. */
  async function dial(caller: string, on: { app: FastifyInstance; registrar: FakeRegistrar } = { app, registrar }) {
    const reached = on.registrar.calls.length;
    const callSid = `CAin${++sids}`;
    const r = await on.app.inject(twilioRequest("/webhooks/twilio/voice",
      { From: caller, To: DODDY_NUMBER, CallSid: callSid, Direction: "inbound", AccountSid: "AC1" }));
    assert.equal(r.statusCode, 200);
    assert.match(String(r.headers["content-type"]), /text\/xml/);
    const agent = on.registrar.calls.length > reached ? on.registrar.calls.at(-1) : undefined;
    return { twiml: r.body, variables: agent?.variables, agent, callSid };
  }

  /** A call that reaches the phone agent; returns the variables the agent got. */
  async function ring(caller: string) {
    const { twiml, variables } = await dial(caller);
    assert.equal(twiml, CONNECT_TWIML);
    return variables!;
  }

  const countRows = async (table: string) => Number((await db.query(`SELECT count(*) AS n FROM ${table}`)).rows[0].n);

  test("voice webhooks refuse unsigned or forged requests; tools still need the shared secret", async () => {
    for (const url of ["/webhooks/twilio/voice", `/webhooks/twilio/voice/outbound/${randomUUID()}`, "/webhooks/twilio/call-status"]) {
      assert.equal((await app.inject(twilioRequest(url, { From: "+48500000003" }, "forged"))).statusCode, 403, url);
      const signedForOtherForm = twilioSignature(TWILIO_TOKEN, BASE_URL + url, { From: "+48500000003" });
      assert.equal((await app.inject(twilioRequest(url, { From: "+48500000099" }, signedForOtherForm))).statusCode, 403, url);
    }
    assert.equal((await el("/webhooks/elevenlabs/tools/search-memories", { query: "x" }, "abc", "")).statusCode, 401);
  });

  test("strangers, withheld numbers and numbers with calls off hear a fixed line, never the agent", async () => {
    await user("+48500000002");
    const [agentCalls, calls, sessions] = [registrar.calls.length, await countRows("calls"), await countRows("call_sessions")];
    for (const caller of ["+48500000099", "anonymous", ""]) {
      const { twiml, agent } = await dial(caller);
      assert.match(twiml, /This number only works for its owner\. Goodbye\.<\/Say><Hangup\/><\/Response>$/);
      assert.equal(agent, undefined);
    }
    const off = await dial("+48500000002");
    assert.match(off.twiml, /Phone calls are turned off in the Doddy app/);
    assert.equal(registrar.calls.length, agentCalls, "the phone agent was never asked");
    assert.equal(await countRows("calls"), calls);
    assert.equal(await countRows("call_sessions"), sessions);
  });

  test("a call the phone agent can't take hears a fixed line; the call is failed and its session gone", async () => {
    await user("+48500000020", { pin: "258025", inbound: true });
    registrar.next = [{ kind: "failed", code: "elevenlabs_503" }];
    const { twiml, variables, callSid } = await dial("+48500000020");
    assert.match(twiml, /I can't talk right now/);
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, variables!.secret__doddy_session)).json(),
      { status: "not_recognised" });
    assert.deepEqual((await db.query("SELECT status, error_code FROM calls WHERE call_sid = $1", [callSid])).rows[0],
      { status: "failed", error_code: "elevenlabs_503" });
  });

  test("call status only moves forward, and a finished call ends its session", async () => {
    const { accountId } = await user("+48500000022", { pin: "258025", inbound: true });
    const status = async (sid: string) => (await db.query("SELECT status FROM calls WHERE call_sid = $1", [sid])).rows[0].status;
    const report = (sid: string, s: string) => app.inject(twilioRequest("/webhooks/twilio/call-status", { CallSid: sid, CallStatus: s }));

    const inbound = await dial("+48500000022");
    const s = inbound.variables!.secret__doddy_session!;
    for (const [twilio, ours] of [["ringing", "started"], ["in-progress", "started"], ["completed", "completed"],
      ["ringing", "completed"], ["no-answer", "completed"], ["queued", "completed"]]) {
      assert.equal((await report(inbound.callSid, twilio!)).statusCode, 204);
      assert.equal(await status(inbound.callSid), ours, twilio);
    }
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s)).json(), { status: "not_recognised" });

    await db.query("INSERT INTO calls (id, account_id, direction, status, call_sid) VALUES ($1, $2, 'outbound', 'requested', 'CAseq')",
      [randomUUID(), accountId]);
    for (const [twilio, ours] of [["initiated", "requested"], ["ringing", "ringing"], ["in-progress", "answered"],
      ["ringing", "answered"], ["busy", "busy"], ["completed", "busy"]]) {
      await report("CAseq", twilio!);
      assert.equal(await status("CAseq"), ours, twilio);
    }
    assert.equal((await report("CAnobody", "completed")).statusCode, 204);
  });

  test("inbound: memories only after the right PIN; wrong PINs lock", async () => {
    const owner = await user("+48500000003", { pin: "258025", inbound: true, memories: ["Klucze do piwnicy są u pani Łucji", "Dentist on Tuesday at 15:00"] });
    const v = await ring("+48500000003");
    assert.deepEqual([v.doddy_caller, v.doddy_memory, v.doddy_pin], ["known", "on", "set"]);
    const s = v.secret__doddy_session!;

    assert.deepEqual((await el("/webhooks/elevenlabs/tools/search-memories", { query: "klucze" }, s)).json(), { status: "pin_required" });
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "111111" }, s)).json(), { status: "wrong_pin", attemptsLeft: 4 });
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "2 5 8 0 2 5" }, s)).json(), { status: "verified" });

    const found = (await el("/webhooks/elevenlabs/tools/search-memories", { query: "gdzie są klucze?" }, s)).json();
    assert.equal(found.status, "ok");
    assert.deepEqual(found.results, [{ text: "Klucze do piwnicy są u pani Łucji", saved: "2026-09-01" }]);
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/search-memories", { query: "passport" }, s)).json(), { status: "no_match" });

    // A fresh call is not verified, and five wrong PINs lock the account's PIN.
    const s2 = (await ring("+48500000003")).secret__doddy_session!;
    let last;
    for (let i = 0; i < 5; i++) last = (await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "000000" }, s2)).json();
    assert.deepEqual(last, { status: "locked", minutes: 15 });
    assert.equal((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s2)).json().status, "locked");

    // Lockouts escalate: the next five wrong guesses after the lock ends lock for an hour, not 15 min.
    // With notifications on, the owner is told (no caller number in the text).
    await call("PUT", "/v1/device/push-token", owner.h, { token: "c".repeat(64), environment: "sandbox" });
    await db.query(
      `UPDATE call_settings SET pin_locked_until = now() - interval '1 second'
       WHERE account_id = (SELECT account_id FROM phone_numbers WHERE e164 = '+48500000003')`);
    for (let i = 0; i < 4; i++) {
      assert.equal((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "000000" }, s2)).json().status, "wrong_pin");
    }
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "000000" }, s2)).json(), { status: "locked", minutes: 60 });
    const { rows: alerts } = await db.query<{ id: string; channel: string; body: string | null; body_ciphertext: Buffer }>(
      "SELECT id, channel, body, body_ciphertext FROM outbound_messages WHERE account_id = $1", [owner.accountId]);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0]!.channel, "push");
    assert.equal(alerts[0]!.body, null, "queued text is not kept in plain form");
    const text = testCipher.decrypt(alerts[0]!.body_ciphertext, bodyAad(owner.accountId, alerts[0]!.id));
    assert.match(text, /wrong Doddy PIN 5 times.*locked for 1 h/);
    assert.ok(!text.includes("+48"), "no phone number in the alert");
  });

  test("changing or removing the PIN ends memory access for calls already verified", async () => {
    const { h } = await user("+48500000016", { pin: "258025", inbound: true, memories: ["Spare key under the mat"] });
    const s = (await ring("+48500000016")).secret__doddy_session!;
    await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s);
    assert.equal((await el("/webhooks/elevenlabs/tools/search-memories", { query: "key" }, s)).json().status, "ok");
    assert.equal((await call("PUT", "/v1/calls/pin", h, { pin: "369147" })).statusCode, 204);
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/search-memories", { query: "key" }, s)).json(), { status: "pin_required" });
    await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "369147" }, s);
    assert.equal((await call("DELETE", "/v1/calls/pin", h)).statusCode, 204);
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/search-memories", { query: "key" }, s)).json(), { status: "pin_required" });
  });

  test("a PIN lock queues no alert when push isn't configured on the server", async () => {
    const noPush = await testApp(db, { push: undefined });
    const r = await noPush.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const hh = { authorization: `Bearer ${deviceToken}` };
    const inj = (method: "POST" | "PUT", url: string, payload: object, headers: Record<string, string> = hh) =>
      noPush.app.inject({ method, url, headers, payload });
    await inj("POST", "/v1/phone/verification/check", { phone: "+48500000017", code: "123456" });
    await inj("PUT", "/v1/calls/pin", { pin: "258025" });
    await inj("PUT", "/v1/calls/settings", { inboundEnabled: true });
    await inj("PUT", "/v1/device/push-token", { token: "e".repeat(64), environment: "sandbox" });
    const { variables } = await dial("+48500000017", noPush);
    const s = variables!.secret__doddy_session!;
    for (let i = 0; i < 5; i++) {
      await inj("POST", "/webhooks/elevenlabs/tools/verify-pin", { pin: "000000" }, { "x-doddy-tool-secret": TOOL_SECRET, "x-doddy-session": s });
    }
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [accountId])).rowCount, 0);
    await noPush.app.close();
  });

  test("parallel note saves can't overfill the inbox", async () => {
    const { accountId } = await user("+48500000018", { pin: "258025", inbound: true });
    const s = (await ring("+48500000018")).secret__doddy_session!;
    await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s);
    await Promise.all(Array.from({ length: 30 }, (_, i) => el("/webhooks/elevenlabs/tools/save-note", { text: `note ${i}` }, s)));
    const { rows } = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM call_notes WHERE account_id = $1", [accountId]);
    assert.equal(rows[0]!.n, 20);
  });

  test("memory text is encrypted at rest", async () => {
    await user("+48500000004", { pin: "258025", inbound: true, memories: ["Hasło do wifi: zielony-kot-77"] });
    const { rows } = await db.query<{ ciphertext: Buffer }>("SELECT ciphertext FROM memory_copies");
    for (const r of rows) assert.ok(!r.ciphertext.toString("utf8").includes("zielony"));
  });

  test("notes from a call wait in the inbox, trigger a push without content, and need the PIN", async () => {
    const { h } = await user("+48500000005", { pin: "258025", inbound: true });
    await call("PUT", "/v1/device/push-token", h, { token: "12".repeat(32), environment: "sandbox" });
    const s = (await ring("+48500000005")).secret__doddy_session!;
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/save-note", { text: "Buy milk" }, s)).json(), { status: "pin_required" });
    await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s);
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/save-note", { text: "Call Anna about Friday" }, s)).json(), { status: "saved_for_confirmation" });

    const notes = (await call("GET", "/v1/call-notes", h)).json().notes;
    assert.equal(notes.length, 1);
    assert.equal(notes[0].text, "Call Anna about Friday");
    push.sent = [];
    await dispatchDue(db, { push, sms, cipher: testCipher });
    // Only this account's device: other tests may leave their own alerts queued.
    const mine = push.sent.filter((p) => p.target.deviceToken === "12".repeat(32));
    assert.equal(mine.length, 1);
    assert.ok(!mine[0]!.body.includes("Anna"), "push must not contain the note");

    assert.equal((await call("DELETE", `/v1/call-notes/${notes[0].id}`, h)).statusCode, 204);
    assert.equal((await call("GET", "/v1/call-notes", h)).json().notes.length, 0);
  });

  test("a note that won't decrypt is listed apart and can still be discarded", async () => {
    const { accountId, h } = await user("+48500000015", { pin: "258025", inbound: true });
    const s = (await ring("+48500000015")).secret__doddy_session!;
    await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s);
    await el("/webhooks/elevenlabs/tools/save-note", { text: "Readable" }, s);
    await el("/webhooks/elevenlabs/tools/save-note", { text: "Broken" }, s);
    const { rows } = await db.query<{ id: string }>(
      "SELECT id FROM call_notes WHERE account_id = $1 ORDER BY created_at DESC LIMIT 1", [accountId]);
    const broken = rows[0]!.id;
    await db.query("UPDATE call_notes SET ciphertext = $2 WHERE id = $1", [broken, Buffer.alloc(40, 1)]);

    const r = await call("GET", "/v1/call-notes", h);
    assert.equal(r.statusCode, 200);
    assert.deepEqual(r.json().notes.map((n: { text: string }) => n.text), ["Readable"]);
    assert.deepEqual(r.json().unreadable.map((n: { id: string }) => n.id), [broken]);
    assert.equal((await call("DELETE", `/v1/call-notes/${broken}`, h)).statusCode, 204);
    assert.equal((await call("GET", "/v1/call-notes", h)).json().unreadable.length, 0);
  });

  test("memory copy: snapshot replaces everything; turning it off deletes every copy", async () => {
    const { accountId, h } = await user("+48500000006", { memories: ["one", "two", "three"] });
    const count = async () => (await db.query("SELECT 1 FROM memory_copies WHERE account_id = $1", [accountId])).rowCount;
    assert.equal(await count(), 3);
    await call("PUT", "/v1/memory-copy/snapshot", h, { items: [{ id: randomUUID(), text: "only this" }] });
    assert.equal(await count(), 1);
    await call("PUT", "/v1/memory-copy", h, { enabled: false });
    assert.equal(await count(), 0);
    assert.equal((await call("PUT", "/v1/memory-copy/snapshot", h, { items: [] })).statusCode, 409);
  });

  const consent = (h: object, on: boolean) =>
    call("PUT", "/v1/calls/settings", h, on ? { outboundConsent: true, outboundConsentTextVersion: "calls-v1" } : { outboundConsent: false });

  test("Call me now: Twilio rings the verified number; the session opens only when answered, and only once", async () => {
    const { accountId, h } = await user("+48500000007", { pin: "258025" });
    assert.equal((await call("POST", "/v1/calls/outbound", h)).json().error, "outbound_not_enabled");
    assert.equal((await call("PUT", "/v1/calls/settings", h, { outboundConsent: true })).statusCode, 400, "needs the wording version");
    assert.equal((await consent(h, true)).statusCode, 204);

    const r = await call("POST", "/v1/calls/outbound", h);
    assert.equal(r.statusCode, 202);
    const { callId, status } = r.json() as { callId: string; status: string };
    assert.equal(status, "requested");
    const answerPath = `/webhooks/twilio/voice/outbound/${callId}`;
    assert.deepEqual(outbound.calls.at(-1), {
      to: "+48500000007", from: DODDY_NUMBER, answerUrl: BASE_URL + answerPath, statusCallbackUrl: `${BASE_URL}/webhooks/twilio/call-status`,
    });
    assert.equal((await db.query("SELECT 1 FROM call_sessions WHERE account_id = $1", [accountId])).rowCount, 0, "no session before the answer");

    const callSid = `CAout${outbound.calls.length}`;
    const answered = await app.inject(twilioRequest(answerPath, { CallSid: callSid, CallStatus: "in-progress", From: DODDY_NUMBER, To: "+48500000007" }));
    assert.equal(answered.body, CONNECT_TWIML);
    const agent = registrar.calls.at(-1)!;
    assert.deepEqual([agent.direction, agent.from, agent.to, agent.variables.doddy_direction],
      ["outbound", DODDY_NUMBER, "+48500000007", "outbound"]);
    const s = agent.variables.secret__doddy_session!;
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s)).json(), { status: "verified" });

    // The same answer again, or with another CallSid, connects nothing.
    const reached = registrar.calls.length;
    for (const sid of [callSid, "CAother"]) {
      assert.match((await app.inject(twilioRequest(answerPath, { CallSid: sid }))).body, /I can't talk right now/);
    }
    assert.equal(registrar.calls.length, reached);

    // Twilio reports the end: the call is completed and its session no longer works.
    await app.inject(twilioRequest("/webhooks/twilio/call-status", { CallSid: callSid, CallStatus: "completed" }));
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "258025" }, s)).json(), { status: "not_recognised" });

    outbound.next = [{ kind: "unknown", code: "twilio_network" }];
    assert.equal((await call("POST", "/v1/calls/outbound", h)).json().status, "unknown");
    const list = (await call("GET", "/v1/calls", h)).json().calls;
    assert.deepEqual(list.map((c: { status: string }) => c.status), ["unknown", "completed"]);
  });

  test("Call me now: an answer after consent was withdrawn connects nothing; a refused call is failed", async () => {
    const { h } = await user("+48500000021", { pin: "258025" });
    await consent(h, true);
    const { callId } = (await call("POST", "/v1/calls/outbound", h)).json() as { callId: string };
    const callSid = `CAout${outbound.calls.length}`;
    await consent(h, false);
    const reached = registrar.calls.length;
    const late = await app.inject(twilioRequest(`/webhooks/twilio/voice/outbound/${callId}`, { CallSid: callSid }));
    assert.match(late.body, /I can't talk right now/);
    assert.equal(registrar.calls.length, reached);

    await consent(h, true);
    outbound.next = [{ kind: "rejected", code: "twilio_21215" }];
    const refused = await call("POST", "/v1/calls/outbound", h);
    assert.equal(refused.statusCode, 502);
    assert.deepEqual((await db.query("SELECT status, error_code FROM calls WHERE id = $1", [refused.json().callId])).rows[0],
      { status: "failed", error_code: "twilio_21215" });
  });

  test("settings report what exists; account deletion removes call data", async () => {
    const { accountId, h } = await user("+48500000008", { pin: "258025", inbound: true, memories: ["x"] });
    const st = (await call("GET", "/v1/calls/settings", h)).json();
    assert.deepEqual(st, {
      available: { inbound: true, outbound: true }, doddyNumber: "+48221234567", phoneVerified: true,
      inboundEnabled: true, pinSet: true, pinLocked: false, outboundConsent: false, memoryCopy: { enabled: true, count: 1 },
    });
    await ring("+48500000008");
    assert.equal((await call("DELETE", "/v1/account", h)).statusCode, 204);
    for (const t of ["call_settings", "memory_copies", "call_notes", "calls", "call_sessions"]) {
      assert.equal((await db.query(`SELECT 1 FROM ${t} WHERE account_id = $1`, [accountId])).rowCount, 0, t);
    }
  });

  test("without the encryption key or secret, call features say not configured", async () => {
    const bare = await testApp(db, { cipher: undefined, toolSecret: undefined, outbound: undefined, registrar: undefined });
    const r = await bare.app.inject({ method: "POST", url: "/v1/accounts" });
    const h = { authorization: `Bearer ${r.json().deviceToken}` };
    assert.deepEqual((await bare.app.inject({ method: "GET", url: "/v1/calls/settings", headers: h })).json().available, { inbound: false, outbound: false });
    assert.equal((await bare.app.inject({ method: "PUT", url: "/v1/memory-copy", headers: h, payload: { enabled: true } })).statusCode, 503);
    assert.equal((await bare.app.inject({ method: "POST", url: "/v1/calls/outbound", headers: h })).statusCode, 503);
    // Twilio still gets an honest answer: a fixed line, never the agent.
    const answer = await bare.app.inject(twilioRequest("/webhooks/twilio/voice", { From: "+48500000003", To: DODDY_NUMBER, CallSid: "CAbare" }));
    assert.match(answer.body, /Phone calls aren't connected yet/);
    await bare.app.close();
    // Without a way to check Twilio's signature the server answers 503, so Twilio plays the number's fallback.
    const unsigned = await testApp(db, { twilioAuthToken: undefined });
    const noCheck = await unsigned.app.inject(twilioRequest("/webhooks/twilio/voice", { From: "+48500000003", To: DODDY_NUMBER, CallSid: "CAnocheck" }));
    assert.equal(noCheck.statusCode, 503);
    assert.deepEqual((await unsigned.app.inject({ method: "GET", url: "/v1/calls/settings", headers: h })).json().available, { inbound: false, outbound: false });
    await unsigned.app.close();
  });
});
