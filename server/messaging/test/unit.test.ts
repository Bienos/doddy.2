import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import http from "node:http";
import { createServer, type Socket } from "node:net";
import { test } from "node:test";
import twilio from "twilio";
import { createPool, dbErrorFields } from "../src/db.js";
import { loadConfig } from "../src/config.js";
import { apnsJwt } from "../src/providers/apns.js";
import { ElevenLabsCallRegistrar } from "../src/providers/elevenlabs.js";
import { isValidTwilioSignature, TwilioClient, TwilioVoiceCaller, twilioSignature } from "../src/providers/twilio.js";
import { approvalHash, textApprovalHash } from "../src/approval.js";
import { OUTBOUND_DAILY_LIMIT, OUTBOUND_HOURLY_LIMIT } from "../src/calls.js";
import { APPROVED_TEXTS_PER_DAY, APPROVED_TEXTS_SERVER_PER_DAY, TEXT_MAX_LENGTH } from "../src/routes/texts.js";
import { readFileSync } from "node:fs";
import { connectTwiml, sayAndHangUp, type FixedLine } from "../src/voiceTwiml.js";
import { classifySms, smsSegments } from "../src/sms.js";
import {
  AI_REPLIES_PER_DAY, AI_REPLY_BUDGET_USD_PER_DAY, AI_REPLY_MAX_SEGMENTS, AI_REPLY_WINDOW_MINUTES, FIXED, INBOUND_TEXTS_PER_HOUR,
} from "../src/textReplies.js";

test("Twilio signature matches the official twilio library", () => {
  const url = "https://doddy.example.test/webhooks/twilio/sms";
  const params = { From: "+48500100200", To: "+48600000000", Body: "STOP ąę", MessageSid: "SM123", AccountSid: "AC1" };
  const ours = twilioSignature("secret", url, params);
  assert.equal(ours, twilio.getExpectedTwilioSignature("secret", url, params));
  assert.ok(isValidTwilioSignature("secret", url, params, ours));
  assert.ok(!isValidTwilioSignature("secret", url, { ...params, Body: "START" }, ours));
  assert.ok(!isValidTwilioSignature("other", url, params, ours));
  assert.ok(!isValidTwilioSignature("secret", url, params, undefined));
});

test("APNs provider token is a valid ES256 JWT", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwt = apnsJwt("TEAM123456", "KEY1234567", privateKey, 1_700_000_000);
  const [h, p, s] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(h!, "base64url").toString()), { alg: "ES256", kid: "KEY1234567" });
  assert.deepEqual(JSON.parse(Buffer.from(p!, "base64url").toString()), { iss: "TEAM123456", iat: 1_700_000_000 });
  assert.ok(verify("sha256", Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(s!, "base64url")));
});

test("SMS keywords", () => {
  assert.equal(classifySms(" stop "), "opt_out");
  assert.equal(classifySms("Unsubscribe"), "opt_out");
  assert.equal(classifySms("START"), "opt_in");
  assert.equal(classifySms("help"), "help");
  assert.equal(classifySms("please stop texting"), "other");
});

/** A local HTTP stand-in for a provider API: records each request and answers with `reply`. */
async function standIn(reply: () => { status: number; type: string; body: string; delayMs?: number }) {
  const requests: { url: string; method: string; headers: http.IncomingHttpHeaders; body: string }[] = [];
  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => { body += c; });
    req.on("end", () => {
      requests.push({ url: req.url ?? "", method: req.method ?? "", headers: req.headers, body });
      const r = reply();
      setTimeout(() => res.writeHead(r.status, { "content-type": r.type }).end(r.body), r.delayMs ?? 0);
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  return { base, requests, close: () => { server.closeAllConnections(); server.close(); } };
}

test("Doddy's call through Twilio: the request rings with status callbacks and no recording; a 5xx is unknown", async () => {
  let answer = { status: 201, type: "application/json", body: JSON.stringify({ sid: "CA123", status: "queued" }) };
  const api = await standIn(() => answer);
  const caller = new TwilioVoiceCaller({ accountSid: "AC1", authToken: "tok" }, 2000, api.base);
  const call = { to: "+48500000000", from: "+48730000000", answerUrl: "https://d.test/a", statusCallbackUrl: "https://d.test/s" };
  try {
    assert.deepEqual(await caller.placeCall(call), { kind: "accepted", callSid: "CA123" });
    const sent = api.requests.at(-1)!;
    assert.equal(sent.url, "/2010-04-01/Accounts/AC1/Calls.json");
    assert.equal(sent.headers.authorization, "Basic " + Buffer.from("AC1:tok").toString("base64"));
    const form = new URLSearchParams(sent.body);
    assert.deepEqual([form.get("To"), form.get("From"), form.get("Url"), form.get("Method")],
      ["+48500000000", "+48730000000", "https://d.test/a", "POST"]);
    assert.deepEqual([form.get("StatusCallback"), form.get("StatusCallbackMethod"), form.get("Timeout")], ["https://d.test/s", "POST", "30"]);
    assert.deepEqual(form.getAll("StatusCallbackEvent"), ["initiated", "ringing", "answered", "completed"]);
    assert.ok(![...form.keys()].some((k) => /record/i.test(k)), "never asks Twilio to record");

    for (const s of [500, 502, 503, 504]) {
      answer = { status: s, type: "application/json", body: "{}" };
      assert.deepEqual(await caller.placeCall(call), { kind: "unknown", code: `twilio_${s}` });
    }
    answer = { status: 400, type: "application/json", body: JSON.stringify({ code: 21215, message: "Geo permission" }) };
    assert.deepEqual(await caller.placeCall(call), { kind: "rejected", code: "twilio_21215" });
    answer = { status: 429, type: "application/json", body: "{}" };
    assert.deepEqual(await caller.placeCall(call), { kind: "rejected", code: "twilio_429" });
  } finally {
    api.close();
  }
  const unreachable = new TwilioVoiceCaller({ accountSid: "AC1", authToken: "tok" }, 500, "http://127.0.0.1:9");
  assert.deepEqual(await unreachable.placeCall(call), { kind: "unknown", code: "twilio_network" });
});

test("register-call: sends the agent, numbers and variables; accepts TwiML as XML or a JSON string, nothing else", async () => {
  const twiml = '<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="wss://x"/></Connect></Response>';
  let answer: { status: number; type: string; body: string; delayMs?: number } = { status: 200, type: "application/xml", body: twiml };
  const api = await standIn(() => answer);
  const registrar = new ElevenLabsCallRegistrar({ apiKey: "xi", agentId: "agent_1" }, 300, api.base);
  const call = { from: "+48500000000", to: "+48730000000", direction: "inbound" as const, variables: { secret__doddy_session: "s", doddy_caller: "known" } };
  try {
    assert.deepEqual(await registrar.register(call), { kind: "twiml", twiml });
    const sent = api.requests.at(-1)!;
    assert.equal(sent.url, "/v1/convai/twilio/register-call");
    assert.equal(sent.headers["xi-api-key"], "xi");
    assert.deepEqual(JSON.parse(sent.body), {
      agent_id: "agent_1", from_number: "+48500000000", to_number: "+48730000000", direction: "inbound",
      conversation_initiation_client_data: { dynamic_variables: { secret__doddy_session: "s", doddy_caller: "known" } },
    });

    answer = { status: 200, type: "application/json", body: JSON.stringify(twiml) };
    assert.deepEqual(await registrar.register(call), { kind: "twiml", twiml });
    for (const body of ["<html>Bad gateway</html>", '<Response><Record maxLength="60"/></Response>']) {
      answer = { status: 200, type: "text/html", body };
      assert.deepEqual(await registrar.register(call), { kind: "failed", code: "elevenlabs_bad_twiml" }, body);
    }
    answer = { status: 422, type: "application/json", body: JSON.stringify({ detail: [] }) };
    assert.deepEqual(await registrar.register(call), { kind: "failed", code: "elevenlabs_422" });
    answer = { status: 200, type: "application/xml", body: twiml, delayMs: 1000 };
    assert.deepEqual(await registrar.register(call), { kind: "failed", code: "elevenlabs_network" }, "too slow for Twilio");
  } finally {
    api.close();
  }
});

test("register-call TwiML check", () => {
  const doc = "<Response><Connect><Stream url=\"wss://x\"/></Connect></Response>";
  assert.equal(connectTwiml(`  ${doc}\n`, "application/xml"), doc);
  assert.equal(connectTwiml(JSON.stringify(doc), "application/json; charset=utf-8"), doc);
  assert.equal(connectTwiml(JSON.stringify({ twiml: doc }), "application/json"), undefined);
  assert.equal(connectTwiml("not json", "application/json"), undefined);
  assert.equal(connectTwiml("<Responses></Responses>", "text/xml"), undefined);
  assert.equal(connectTwiml("<Response><Record/></Response>", "text/xml"), undefined);
});

test("fixed call lines say Doddy is an AI, in Polish then English, hang up, and never record", () => {
  const lines: FixedLine[] = ["unknown_caller", "calls_off", "not_set_up", "cant_talk", "unavailable"];
  for (const line of lines) {
    const xml = sayAndHangUp(line);
    assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?><Response><Say language="pl-PL" voice="Polly\.Ola-Neural">Tu Doddy, asystent AI\./, line);
    assert.match(xml, /<Say language="en-US" voice="Polly\.Joanna">This is Doddy, an AI assistant\./, line);
    assert.match(xml, /<Hangup\/><\/Response>$/, line);
    assert.doesNotMatch(xml, /record/i, line);
    assert.doesNotMatch(xml, /&/, `${line}: the text needs no XML escaping`);
  }
});

test("approval hashes reproduce the shared vectors (contracts/phone/approval-vectors.json)", () => {
  const file = JSON.parse(readFileSync(new URL("../../../../contracts/phone/approval-vectors.json", import.meta.url), "utf8")) as
    { vectors: { description: string; fields: string[]; sha256: string }[] };
  assert.ok(file.vectors.length >= 8);
  for (const v of file.vectors) {
    assert.equal(approvalHash(v.fields).toString("hex"), v.sha256, v.description);
    const [version, kind, to, body] = v.fields;
    if (version === "doddy-approval-1" && kind === "text") assert.equal(textApprovalHash(to!, body!).toString("hex"), v.sha256, v.description);
  }
});

test("a text through Twilio: a server error after the request may have been sent is unknown, never retried", async () => {
  let answer = { status: 201, type: "application/json", body: JSON.stringify({ sid: "SM1" }) };
  const api = await standIn(() => answer);
  const twilio = new TwilioClient({ accountSid: "AC1", authToken: "t", messagingServiceSid: "MG1", verifyServiceSid: "VA1" },
    "https://d.test/webhooks/twilio/status", 2000, api.base);
  try {
    assert.deepEqual(await twilio.send("+48500000000", "Hi"), { kind: "accepted", providerId: "SM1" });
    for (const s of [500, 502, 504]) {
      answer = { status: s, type: "application/json", body: "{}" };
      assert.deepEqual(await twilio.send("+48500000000", "Hi"), { kind: "unknown", code: `twilio_${s}` }, String(s));
    }
    for (const s of [429, 503]) {
      answer = { status: s, type: "application/json", body: "{}" };
      assert.deepEqual(await twilio.send("+48500000000", "Hi"), { kind: "transient", code: `twilio_${s}` }, String(s));
    }
    answer = { status: 400, type: "application/json", body: JSON.stringify({ code: 21610 }) };
    assert.deepEqual(await twilio.send("+48500000000", "Hi"), { kind: "rejected", code: "twilio_21610", unsubscribed: true });

    answer = { status: 200, type: "application/json", body: JSON.stringify({ messages: [
      { sid: "SM9", body: "Kup mleko", date_created: "Sat, 17 Oct 2026 10:00:00 +0000", status: "delivered" },
      { sid: "SM8", date_created: "Sat, 17 Oct 2026 09:00:00 +0000", status: "sent" },
    ] }) };
    const list = await twilio.recentMessagesTo("+48500000000");
    assert.deepEqual(list, [{ sid: "SM9", body: "Kup mleko", createdAt: new Date("2026-10-17T10:00:00Z"), status: "delivered" }],
      "a record without a body (redacted) is left out");
    const asked = api.requests.at(-1)!;
    assert.equal(asked.url, "/2010-04-01/Accounts/AC1/Messages.json?To=%2B48500000000&PageSize=50");
    answer = { status: 500, type: "application/json", body: "{}" };
    assert.equal(await twilio.recentMessagesTo("+48500000000"), undefined);
  } finally {
    api.close();
  }
});

test("the contact policy in doddy_rules.yaml matches what the server enforces", () => {
  const yaml = readFileSync(new URL("../../../../docs/trust/config/doddy_rules.yaml", import.meta.url), "utf8");
  // The contact_policy block: its indented lines up to the next top-level key.
  const block = yaml.split("\ncontact_policy:\n")[1]?.split(/\n(?=\S)/)[0];
  assert.ok(block, "contact_policy missing from doddy_rules.yaml");
  const value = (key: string) => block.match(new RegExp(`^\\s+${key}: (\\S+)`, "m"))?.[1];
  assert.deepEqual(
    [value("text_max_length"), value("calls_per_hour"), value("calls_per_day"), value("approved_texts_per_day"), value("approved_texts_server_per_day")].map(Number),
    [TEXT_MAX_LENGTH, OUTBOUND_HOURLY_LIMIT, OUTBOUND_DAILY_LIMIT, APPROVED_TEXTS_PER_DAY, APPROVED_TEXTS_SERVER_PER_DAY]);
  assert.deepEqual([value("approval"), value("recording"), value("allowlist_max_numbers")], ["exact_payload_hash", "off", "1"]);
  // Texts to Doddy (U3, ADR-494).
  assert.deepEqual(
    [value("inbound_texts_per_hour"), value("ai_replies_per_day"), value("ai_reply_budget_usd_per_day"),
      value("ai_reply_window_minutes"), value("ai_reply_max_segments"), value("ai_replies_per_text")].map(Number),
    [INBOUND_TEXTS_PER_HOUR, AI_REPLIES_PER_DAY, AI_REPLY_BUDGET_USD_PER_DAY, AI_REPLY_WINDOW_MINUTES, AI_REPLY_MAX_SEGMENTS, 1]);
  assert.deepEqual([value("texts_to_doddy"), value("ai_replies"), value("ai_reply_memories"), value("inbound_text_is_instructions")],
    ["off_by_default", "off_by_default", "off_by_default", "false"]);
  assert.doesNotMatch(block, /\+\d{6,}/, "no phone number in the rules file");
});

test("a database that never answers fails within the connect timeout, not minutes later", async () => {
  // A TCP server that accepts and then stays silent, like an unreachable or wrong DATABASE_URL.
  const sockets: Socket[] = [];
  const server = createServer((s) => { sockets.push(s); });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  const db = createPool(`postgres://u:secret@127.0.0.1:${port}/x`, 300);
  const started = Date.now();
  try {
    await assert.rejects(db.query("SELECT 1"), /timeout/i);
    assert.ok(Date.now() - started < 3_000, `took ${Date.now() - started} ms`);
  } finally {
    await db.end().catch(() => {});
    for (const s of sockets) s.destroy();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test("database errors are logged without the connection string", () => {
  const fields = dbErrorFields(Object.assign(new Error("bad postgresql://u:hunter2@db.example:5432/x here"), { code: "ETIMEDOUT" }));
  assert.equal(fields.code, "ETIMEDOUT");
  assert.ok(!fields.error.includes("hunter2"));
  assert.equal(fields.error, "bad <url> here");
  assert.deepEqual(dbErrorFields("boom"), { code: "unknown", error: "boom" });
});

test("Twilio records: deleted with DELETE on the record, 'not final yet' is tried again, anything but a Twilio id is refused", async () => {
  let answer = { status: 204, type: "application/json", body: "" };
  const api = await standIn(() => answer);
  const twilio = new TwilioClient({ accountSid: "AC1", authToken: "t", messagingServiceSid: "MG1", verifyServiceSid: "VA1" },
    undefined, 2000, api.base);
  const sm = "SM" + "a".repeat(32);
  const ca = "CA" + "b".repeat(32);
  try {
    assert.deepEqual(await twilio.deleteRecord("message", sm), { kind: "deleted" });
    assert.deepEqual([api.requests.at(-1)!.method, api.requests.at(-1)!.url], ["DELETE", `/2010-04-01/Accounts/AC1/Messages/${sm}.json`]);
    assert.deepEqual(await twilio.deleteRecord("call", ca), { kind: "deleted" });
    assert.equal(api.requests.at(-1)!.url, `/2010-04-01/Accounts/AC1/Calls/${ca}.json`);
    answer = { status: 404, type: "application/json", body: JSON.stringify({ code: 20404 }) };
    assert.deepEqual(await twilio.deleteRecord("message", sm), { kind: "deleted" }, "already gone");
    answer = { status: 409, type: "application/json", body: JSON.stringify({ code: 20009 }) };
    assert.deepEqual(await twilio.deleteRecord("message", sm), { kind: "retry", code: "twilio_20009" });
    answer = { status: 503, type: "application/json", body: "{}" };
    assert.deepEqual(await twilio.deleteRecord("call", ca), { kind: "retry", code: "twilio_503" });
    answer = { status: 403, type: "application/json", body: JSON.stringify({ code: 20003 }) };
    assert.deepEqual(await twilio.deleteRecord("call", ca), { kind: "failed", code: "twilio_20003" });
    const before = api.requests.length;
    for (const [kind, sid] of [["message", "../Calls/x"], ["call", sm], ["message", ca], ["message", sm + "0"]] as const) {
      assert.deepEqual(await twilio.deleteRecord(kind, sid), { kind: "failed", code: "bad_sid" }, sid);
    }
    assert.equal(api.requests.length, before, "nothing that isn't a Twilio id reaches Twilio");
  } finally {
    api.close();
  }
});

test("SMS parts are counted as the iPhone counts them (Smart Encoding off)", () => {
  // The same cases as DoddyCore's ApprovedTextTests.testSegments.
  const cases: [string, number][] = [
    ["a".repeat(160), 1], ["a".repeat(161), 2], ["a".repeat(306), 2], ["a".repeat(307), 3],
    ["€".repeat(80), 1], ["€".repeat(81), 2],
    ["ż".repeat(70), 1], ["ż".repeat(71), 2], ["ż".repeat(134), 2], ["ż".repeat(135), 3], ["📦", 1],
  ];
  for (const [text, parts] of cases) assert.equal(smsSegments(text), parts, `${text.slice(0, 3)}… x${[...text].length}`);
});

test("POMOC is a help word, so it never becomes a note or a reply", () => {
  for (const word of ["POMOC", "pomoc", " Pomoc "]) assert.equal(classifySms(word), "help", word);
  assert.equal(classifySms("pomoc z zakupami"), "other");
});

test("Doddy's fixed texts fit the reply limit in both languages", () => {
  for (const lang of ["en", "pl"] as const) {
    for (const [name, text] of Object.entries(FIXED[lang])) {
      assert.ok(smsSegments(text) <= AI_REPLY_MAX_SEGMENTS, `${lang}.${name} is ${smsSegments(text)} parts`);
    }
  }
});

test("Twilio records wait 24 hours by default before deletion; an empty setting is the default, not zero", () => {
  const hours = (v?: string) => loadConfig({ DATABASE_URL: "postgres://x", ...(v === undefined ? {} : { TWILIO_RECORD_DELETE_AFTER_HOURS: v }) })
    .twilioRecordDeleteAfterHours;
  assert.deepEqual([hours(), hours(""), hours("0"), hours("2")], [24, 24, 0, 2]);
  assert.throws(() => hours("-1"));
});
