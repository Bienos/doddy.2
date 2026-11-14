// Every response from the messaging server carries HSTS and nosniff (onSend hook in src/app.ts), and the
// health check answers with its status only.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { SECURITY_HEADERS } from "../src/app.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

describe("security headers and health", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;

  before(async () => {
    db = await freshDb();
    ({ app } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  const expectHeaders = (res: { headers: Record<string, unknown> }, what: string) => {
    assert.equal(res.headers["strict-transport-security"], "max-age=31536000", `${what}: HSTS`);
    assert.equal(res.headers["x-content-type-options"], "nosniff", `${what}: nosniff`);
  };

  test("the two headers are exactly these", () => {
    assert.deepEqual(SECURITY_HEADERS, { "strict-transport-security": "max-age=31536000", "x-content-type-options": "nosniff" });
  });

  test("health: 200 with its status only, and the headers", async () => {
    const res = await app.inject({ method: "GET", url: "/healthz" });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json(), { ok: true }, "no version, configuration or counts");
    expectHeaders(res, "health");
  });

  test("every kind of answer carries them: signed-out, not found, bad request, a webhook refusal", async () => {
    const answers = [
      ["signed out", await app.inject({ method: "GET", url: "/v1/phone" }), 401],
      ["not found", await app.inject({ method: "GET", url: "/no/such/route" }), 404],
      ["bad JSON", await app.inject({ method: "POST", url: "/v1/accounts", headers: { "content-type": "application/json" }, payload: "{" }), 400],
      ["unsigned Twilio webhook", await app.inject({
        method: "POST", url: "/webhooks/twilio/sms", headers: { "content-type": "application/x-www-form-urlencoded" }, payload: "Body=hi",
      }), 403],
    ] as const;
    for (const [what, res, status] of answers) {
      if (status !== undefined) assert.equal(res.statusCode, status, what);
      expectHeaders(res, `${what} (${res.statusCode})`);
    }
  });

  test("a signed-in answer carries them", async () => {
    const account = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: "10.91.0.1" });
    const res = await app.inject({ method: "GET", url: "/v1/phone", headers: { authorization: `Bearer ${(account.json() as { deviceToken: string }).deviceToken}` } });
    assert.equal(res.statusCode, 200);
    expectHeaders(res, "signed in");
  });

  test("health when the database is gone: 503 with its status only, and the headers", async () => {
    const broken = await testApp({ query: async () => { throw new Error("connect ECONNREFUSED 10.0.0.5:5432"); } } as unknown as Db);
    try {
      const res = await broken.app.inject({ method: "GET", url: "/healthz" });
      assert.equal(res.statusCode, 503);
      assert.deepEqual(res.json(), { ok: false });
      assert.ok(!res.body.includes("ECONNREFUSED"));
      expectHeaders(res, "health down");
    } finally {
      await broken.app.close();
    }
  });
});
