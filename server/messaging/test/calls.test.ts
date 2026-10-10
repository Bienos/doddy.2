import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { isAcceptablePin } from "../src/crypto.js";
import type { Db } from "../src/db.js";
import { searchMemories } from "../src/memorySearch.js";
import { dispatchDue } from "../src/outbox.js";
import { dbSkip, FakeOutbound, FakePush, FakeSms, freshDb, testApp, TOOL_SECRET } from "./helpers.js";

test("PIN rules reject trivial PINs", () => {
  for (const bad of ["123", "1111", "1234", "9876", "0123", "12a4", "123456789"]) assert.equal(isAcceptablePin(bad), false, bad);
  for (const ok of ["2580", "1357", "904216"]) assert.equal(isAcceptablePin(ok), true, ok);
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

  before(async () => {
    db = await freshDb();
    ({ app, push, sms, outbound } = await testApp(db));
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
  async function user(phone: string, opts: { pin?: string; inbound?: boolean; memories?: string[] } = {}) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
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

  async function ring(caller: string) {
    const r = await el("/webhooks/elevenlabs/call-start", { caller_id: caller, called_number: "+48221234567", call_sid: "CAx", conversation_id: "conv_in" });
    assert.equal(r.statusCode, 200);
    const body = r.json() as { type: string; dynamic_variables: Record<string, string> };
    assert.equal(body.type, "conversation_initiation_client_data");
    return body.dynamic_variables;
  }

  test("webhook and tools refuse requests without the shared secret", async () => {
    assert.equal((await el("/webhooks/elevenlabs/call-start", { caller_id: "+48500000001" }, undefined, "wrong")).statusCode, 401);
    assert.equal((await el("/webhooks/elevenlabs/tools/search-memories", { query: "x" }, "abc", "")).statusCode, 401);
  });

  test("unknown numbers and numbers with calls off get no session", async () => {
    const unknown = await ring("+48500000099");
    assert.equal(unknown.doddy_caller, "unknown");
    assert.equal(unknown.secret__doddy_session, "none");
    await user("+48500000002");
    const off = await ring("+48500000002");
    assert.equal(off.doddy_caller, "calls_off");
    assert.equal(off.secret__doddy_session, "none");
    // Every variable the agent defines is always present.
    assert.deepEqual(Object.keys(off).sort(), ["doddy_caller", "doddy_direction", "doddy_memory", "doddy_pin", "secret__doddy_session"]);
  });

  test("inbound: memories only after the right PIN; wrong PINs lock", async () => {
    await user("+48500000003", { pin: "2580", inbound: true, memories: ["Klucze do piwnicy są u pani Łucji", "Dentist on Tuesday at 15:00"] });
    const v = await ring("+48500000003");
    assert.deepEqual([v.doddy_caller, v.doddy_memory, v.doddy_pin], ["known", "on", "set"]);
    const s = v.secret__doddy_session!;

    assert.deepEqual((await el("/webhooks/elevenlabs/tools/search-memories", { query: "klucze" }, s)).json(), { status: "pin_required" });
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "1111" }, s)).json(), { status: "wrong_pin", attemptsLeft: 4 });
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "2 5 8 0" }, s)).json(), { status: "verified" });

    const found = (await el("/webhooks/elevenlabs/tools/search-memories", { query: "gdzie są klucze?" }, s)).json();
    assert.equal(found.status, "ok");
    assert.deepEqual(found.results, [{ text: "Klucze do piwnicy są u pani Łucji", saved: "2026-09-01" }]);
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/search-memories", { query: "passport" }, s)).json(), { status: "no_match" });

    // A fresh call is not verified, and five wrong PINs lock the account's PIN.
    const s2 = (await ring("+48500000003")).secret__doddy_session!;
    let last;
    for (let i = 0; i < 5; i++) last = (await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "0000" }, s2)).json();
    assert.deepEqual(last, { status: "locked", minutes: 15 });
    assert.equal((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "2580" }, s2)).json().status, "locked");
  });

  test("memory text is encrypted at rest", async () => {
    await user("+48500000004", { pin: "2580", inbound: true, memories: ["Hasło do wifi: zielony-kot-77"] });
    const { rows } = await db.query<{ ciphertext: Buffer }>("SELECT ciphertext FROM memory_copies");
    for (const r of rows) assert.ok(!r.ciphertext.toString("utf8").includes("zielony"));
  });

  test("notes from a call wait in the inbox, trigger a push without content, and need the PIN", async () => {
    const { h } = await user("+48500000005", { pin: "2580", inbound: true });
    await call("PUT", "/v1/device/push-token", h, { token: "12".repeat(32), environment: "sandbox" });
    const s = (await ring("+48500000005")).secret__doddy_session!;
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/save-note", { text: "Buy milk" }, s)).json(), { status: "pin_required" });
    await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "2580" }, s);
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/save-note", { text: "Call Anna about Friday" }, s)).json(), { status: "saved_for_confirmation" });

    const notes = (await call("GET", "/v1/call-notes", h)).json().notes;
    assert.equal(notes.length, 1);
    assert.equal(notes[0].text, "Call Anna about Friday");
    push.sent = [];
    await dispatchDue(db, { push, sms });
    assert.equal(push.sent.length, 1);
    assert.ok(!push.sent[0]!.body.includes("Anna"), "push must not contain the note");

    assert.equal((await call("DELETE", `/v1/call-notes/${notes[0].id}`, h)).statusCode, 204);
    assert.equal((await call("GET", "/v1/call-notes", h)).json().notes.length, 0);
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

  test("outbound: needs consent, calls only the verified number, passes a session", async () => {
    const { h } = await user("+48500000007", { pin: "2580" });
    assert.equal((await call("POST", "/v1/calls/outbound", h)).json().error, "outbound_not_enabled");
    assert.equal((await call("PUT", "/v1/calls/settings", h, { outboundConsent: true })).statusCode, 400, "needs the wording version");
    assert.equal((await call("PUT", "/v1/calls/settings", h, { outboundConsent: true, outboundConsentTextVersion: "calls-v1" })).statusCode, 204);

    const r = await call("POST", "/v1/calls/outbound", h);
    assert.equal(r.statusCode, 202);
    const placed = outbound.calls.at(-1)!;
    assert.equal(placed.to, "+48500000007");
    assert.equal(placed.variables.doddy_direction, "outbound");
    const s = placed.variables.secret__doddy_session!;
    assert.deepEqual((await el("/webhooks/elevenlabs/tools/verify-pin", { pin: "2580" }, s)).json(), { status: "verified" });

    outbound.next = [{ kind: "unknown", code: "elevenlabs_network" }];
    assert.equal((await call("POST", "/v1/calls/outbound", h)).json().status, "unknown");
    const list = (await call("GET", "/v1/calls", h)).json().calls;
    assert.deepEqual(list.map((c: { status: string }) => c.status), ["unknown", "requested"]);
  });

  test("settings report what exists; account deletion removes call data", async () => {
    const { accountId, h } = await user("+48500000008", { pin: "2580", inbound: true, memories: ["x"] });
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
    const bare = await testApp(db, { cipher: undefined, toolSecret: undefined, outbound: undefined });
    const r = await bare.app.inject({ method: "POST", url: "/v1/accounts" });
    const h = { authorization: `Bearer ${r.json().deviceToken}` };
    assert.deepEqual((await bare.app.inject({ method: "GET", url: "/v1/calls/settings", headers: h })).json().available, { inbound: false, outbound: false });
    assert.equal((await bare.app.inject({ method: "PUT", url: "/v1/memory-copy", headers: h, payload: { enabled: true } })).statusCode, 503);
    assert.equal((await bare.app.inject({ method: "POST", url: "/webhooks/elevenlabs/call-start", payload: {} })).statusCode, 503);
    await bare.app.close();
  });
});
