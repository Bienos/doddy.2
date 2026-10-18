import { buildApp, type Deps } from "../src/app.js";
import { createPool, migrate, type Db } from "../src/db.js";
import { TextCipher } from "../src/crypto.js";
import { twilioSignature } from "../src/providers/twilio.js";
import type {
  CallOutcome, CallRegistrar, DeleteOutcome, OutboundCall, OutboundCaller, PhoneVerifier, PushSender, PushTarget, RecordDeleter,
  RegisterOutcome, SendOutcome, SmsSender, TextReplyOutcome, TextReplyRequest, TextReplyTools, TextReplyWriter, VerifyCheck,
} from "../src/providers/types.js";

export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
export const dbSkip = TEST_DATABASE_URL ? false : "TEST_DATABASE_URL not set (needs a disposable Postgres database)";

/** Wipes the test database's public schema and re-applies migrations. */
export async function freshDb(): Promise<Db> {
  const db = createPool(TEST_DATABASE_URL!);
  await db.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
  await migrate(db);
  return db;
}

// Test doubles stand in for Apple/Twilio only; database, HTTP layer and dispatcher are real.
export class FakePush implements PushSender {
  sent: { target: PushTarget; body: string }[] = [];
  next: SendOutcome[] = [];
  async send(target: PushTarget, alert: { body: string }, messageId: string): Promise<SendOutcome> {
    this.sent.push({ target, body: alert.body });
    return this.next.shift() ?? { kind: "accepted", providerId: messageId };
  }
}

export class FakeSms implements SmsSender {
  sent: { to: string; body: string }[] = [];
  next: SendOutcome[] = [];
  /** Twilio's message list for any number; undefined means Twilio couldn't be asked. */
  recent: { sid: string; body: string; createdAt: Date; status: string }[] | undefined = [];
  lookups: string[] = [];
  async send(to: string, body: string): Promise<SendOutcome> {
    this.sent.push({ to, body });
    return this.next.shift() ?? { kind: "accepted", providerId: `SM${this.sent.length}` };
  }
  async recentMessagesTo(to: string) {
    this.lookups.push(to);
    return this.recent;
  }
}

export class FakeVerifier implements PhoneVerifier {
  started: string[] = [];
  async start(to: string) { this.started.push(to); }
  async check(_to: string, code: string): Promise<VerifyCheck> {
    return code === "123456" ? "approved" : code === "000000" ? "expired_or_missing" : "wrong_code";
  }
}

/** Stands in for Twilio's Calls API. */
export class FakeOutbound implements OutboundCaller {
  calls: OutboundCall[] = [];
  next: CallOutcome[] = [];
  async placeCall(call: OutboundCall): Promise<CallOutcome> {
    this.calls.push(call);
    return this.next.shift() ?? { kind: "accepted", callSid: `CAout${this.calls.length}` };
  }
}

export const CONNECT_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="wss://agent.example.test"/></Connect></Response>';

/** Stands in for ElevenLabs register-call: records each call it is asked to connect. */
export class FakeRegistrar implements CallRegistrar {
  calls: Parameters<CallRegistrar["register"]>[0][] = [];
  next: RegisterOutcome[] = [];
  async register(call: Parameters<CallRegistrar["register"]>[0]): Promise<RegisterOutcome> {
    this.calls.push(call);
    return this.next.shift() ?? { kind: "twiml", twiml: CONNECT_TWIML };
  }
}

/**
 * Stands in for Claude writing a reply. `script` decides the outcome and may use the tools, as
 * the real writer lets Claude do; every request and the tools it was given are recorded.
 */
export class FakeReplyWriter implements TextReplyWriter {
  readonly provider = "anthropic" as const;
  requests: { request: TextReplyRequest; tools: TextReplyTools }[] = [];
  script: (request: TextReplyRequest, tools: TextReplyTools) => Promise<TextReplyOutcome> =
    async (r) => ({ kind: "reply", text: `Reply to: ${r.text}`, costMicroUsd: 6000 });
  async reply(request: TextReplyRequest, tools: TextReplyTools): Promise<TextReplyOutcome> {
    this.requests.push({ request, tools });
    return this.script(request, tools);
  }
}

/** Stands in for Twilio's DELETE on a message or call record. */
export class FakeDeleter implements RecordDeleter {
  deleted: { kind: string; sid: string }[] = [];
  next: DeleteOutcome[] = [];
  async deleteRecord(kind: "message" | "call", sid: string): Promise<DeleteOutcome> {
    this.deleted.push({ kind, sid });
    return this.next.shift() ?? { kind: "deleted" };
  }
}

export const TOOL_SECRET = "test-tool-secret-0123456789";
export const testCipher = new TextCipher(Buffer.alloc(32, 7));

export const TWILIO_TOKEN = "test-auth-token";
export const BASE_URL = "https://doddy.example.test";

export async function testApp(db: Db, extra: Partial<Deps> = {}) {
  const push = new FakePush();
  const sms = new FakeSms();
  const verifier = new FakeVerifier();
  const outbound = new FakeOutbound();
  const registrar = new FakeRegistrar();
  const replyWriter = new FakeReplyWriter();
  const app = await buildApp({
    db, push, sms, verifier, outbound, registrar, cipher: testCipher, toolSecret: TOOL_SECRET, replyWriter,
    doddyPhoneNumber: DODDY_NUMBER, twilioAuthToken: TWILIO_TOKEN, publicBaseUrl: BASE_URL, logger: false, ...extra,
  });
  return { app, push, sms, verifier, outbound, registrar, replyWriter };
}

export const DODDY_NUMBER = "+48221234567";

/** A webhook request signed the way Twilio signs it (form body, X-Twilio-Signature). */
export function twilioRequest(url: string, form: Record<string, string>,
  signature = twilioSignature(TWILIO_TOKEN, BASE_URL + url, form)) {
  return {
    method: "POST" as const, url, payload: new URLSearchParams(form).toString(),
    headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": signature },
  };
}
