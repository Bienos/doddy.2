import { buildApp, type Deps } from "../src/app.js";
import { createPool, migrate, type Db } from "../src/db.js";
import type { PhoneVerifier, PushSender, PushTarget, SendOutcome, SmsSender, VerifyCheck } from "../src/providers/types.js";

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
  async send(to: string, body: string): Promise<SendOutcome> {
    this.sent.push({ to, body });
    return this.next.shift() ?? { kind: "accepted", providerId: `SM${this.sent.length}` };
  }
}

export class FakeVerifier implements PhoneVerifier {
  started: string[] = [];
  async start(to: string) { this.started.push(to); }
  async check(_to: string, code: string): Promise<VerifyCheck> {
    return code === "123456" ? "approved" : code === "000000" ? "expired_or_missing" : "wrong_code";
  }
}

export const TWILIO_TOKEN = "test-auth-token";
export const BASE_URL = "https://doddy.example.test";

export async function testApp(db: Db, extra: Partial<Deps> = {}) {
  const push = new FakePush();
  const sms = new FakeSms();
  const verifier = new FakeVerifier();
  const app = await buildApp({
    db, push, sms, verifier, twilioAuthToken: TWILIO_TOKEN, publicBaseUrl: BASE_URL, logger: false, ...extra,
  });
  return { app, push, sms, verifier };
}
