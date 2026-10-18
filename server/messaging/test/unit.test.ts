import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import http from "node:http";
import { createServer, type Socket } from "node:net";
import { test } from "node:test";
import twilio from "twilio";
import { createPool, dbErrorFields } from "../src/db.js";
import { apnsJwt } from "../src/providers/apns.js";
import { ElevenLabsCallRegistrar } from "../src/providers/elevenlabs.js";
import { isValidTwilioSignature, TwilioVoiceCaller, twilioSignature } from "../src/providers/twilio.js";
import { connectTwiml, sayAndHangUp, type FixedLine } from "../src/voiceTwiml.js";
import { classifySms } from "../src/sms.js";

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
  const requests: { url: string; headers: http.IncomingHttpHeaders; body: string }[] = [];
  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => { body += c; });
    req.on("end", () => {
      requests.push({ url: req.url ?? "", headers: req.headers, body });
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
