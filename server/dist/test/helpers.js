import { buildApp } from "../src/app.js";
import { createPool, migrate } from "../src/db.js";
import { TextCipher } from "../src/crypto.js";
export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
export const dbSkip = TEST_DATABASE_URL ? false : "TEST_DATABASE_URL not set (needs a disposable Postgres database)";
/** Wipes the test database's public schema and re-applies migrations. */
export async function freshDb() {
    const db = createPool(TEST_DATABASE_URL);
    await db.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
    await migrate(db);
    return db;
}
// Test doubles stand in for Apple/Twilio only; database, HTTP layer and dispatcher are real.
export class FakePush {
    sent = [];
    next = [];
    async send(target, alert, messageId) {
        this.sent.push({ target, body: alert.body });
        return this.next.shift() ?? { kind: "accepted", providerId: messageId };
    }
}
export class FakeSms {
    sent = [];
    next = [];
    async send(to, body) {
        this.sent.push({ to, body });
        return this.next.shift() ?? { kind: "accepted", providerId: `SM${this.sent.length}` };
    }
}
export class FakeVerifier {
    started = [];
    async start(to) { this.started.push(to); }
    async check(_to, code) {
        return code === "123456" ? "approved" : code === "000000" ? "expired_or_missing" : "wrong_code";
    }
}
export class FakeOutbound {
    calls = [];
    next = [];
    async placeCall(to, variables) {
        this.calls.push({ to, variables });
        return this.next.shift() ?? { kind: "accepted", conversationId: `conv_${this.calls.length}`, callSid: "CA1" };
    }
}
export const TOOL_SECRET = "test-tool-secret-0123456789";
export const testCipher = new TextCipher(Buffer.alloc(32, 7));
export const TWILIO_TOKEN = "test-auth-token";
export const BASE_URL = "https://doddy.example.test";
export async function testApp(db, extra = {}) {
    const push = new FakePush();
    const sms = new FakeSms();
    const verifier = new FakeVerifier();
    const outbound = new FakeOutbound();
    const app = await buildApp({
        db, push, sms, verifier, outbound, cipher: testCipher, toolSecret: TOOL_SECRET, doddyPhoneNumber: "+48221234567",
        twilioAuthToken: TWILIO_TOKEN, publicBaseUrl: BASE_URL, logger: false, ...extra,
    });
    return { app, push, sms, verifier, outbound };
}
//# sourceMappingURL=helpers.js.map