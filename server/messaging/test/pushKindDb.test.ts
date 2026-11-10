import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { dispatchDue, enqueue } from "../src/outbox.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";

// The worker queues a finished call's push under `call-result:<attempt>`; the dispatcher must hand the
// sender a kind for it (so a tap can open the recap); an errand's push opens Messages.
describe("a call's push carries its kind (real Postgres)", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  test("call-result and an errand's push get their kinds, and neither carries words or ids", async () => {
    const base = await testApp(db, {});
    const made = (await base.app.inject({ method: "POST", url: "/v1/accounts" })).json() as { accountId: string; deviceToken: string };
    const token = await base.app.inject({
      method: "PUT", url: "/v1/device/push-token", headers: { authorization: `Bearer ${made.deviceToken}` },
      payload: { token: "ab".repeat(32), environment: "sandbox" },
    });
    assert.equal(token.statusCode, 204, token.body);

    const due = new Date(Date.now() - 3600_000);
    await enqueue(db, made.accountId, ["push"], "Doddy skończył rozmowę. Odpowiedź czeka w aplikacji.", due, "call-result:attempt-1", { cipher: testCipher });
    await enqueue(db, made.accountId, ["push"], "Gotowe. Wynik czeka w Wiadomościach.", due, "errand-result:e-1", { cipher: testCipher });
    await dispatchDue(db, { push: base.push, cipher: testCipher });

    const byBody = new Map(base.push.sent.map((p) => [p.body, p.data]));
    assert.deepEqual(byBody.get("Doddy skończył rozmowę. Odpowiedź czeka w aplikacji."), { kind: "call-result" });
    assert.deepEqual(byBody.get("Gotowe. Wynik czeka w Wiadomościach."), { kind: "errand-result" });
    assert.equal(base.push.sent.length, 2);
  });
});
