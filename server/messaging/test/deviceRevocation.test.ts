import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { dispatchDue, enqueue } from "../src/outbox.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";

// Security audit 2026-11-09, finding 1: signing out only deleted the iPhone's copy of its token. The
// device row here stayed, so a copied token kept working and the signed-out iPhone kept receiving the
// account's private notifications. DELETE /v1/device ends both, for that iPhone only.

const ALICE = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const BOB = "6c1d9a8f-3b52-4d4e-8f70-123456789abc";

describe("DELETE /v1/device: signing out of one iPhone (real Postgres)", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let push: Awaited<ReturnType<typeof testApp>>["push"];

  before(async () => {
    db = await freshDb();
    // Any bearer is a Doddy account whose subject is the bearer itself: the sign-in check is not what is tested here.
    ({ app, push } = await testApp(db, { accounts: { verify: async (token) => ({ sub: token }) } }));
  });
  after(async () => {
    await app.close();
    await db.end();
  });

  let address = 0;
  const signIn = async (subject: string) => {
    address += 1;
    const r = await app.inject({ method: "POST", url: "/v1/accounts/sign-in", remoteAddress: `10.77.0.${address}`, headers: { authorization: `Bearer ${subject}` }, payload: {} });
    assert.equal(r.statusCode, 200, r.body);
    return r.json() as { accountId: string; deviceToken: string };
  };
  const call = (method: "GET" | "PUT" | "DELETE", url: string, deviceToken: string, payload?: Record<string, unknown>) =>
    app.inject({ method, url, headers: { authorization: `Bearer ${deviceToken}` }, ...(payload ? { payload } : {}) });
  const works = async (deviceToken: string) => (await call("GET", "/v1/calls/settings", deviceToken)).statusCode === 200;
  const register = async (deviceToken: string, apns: string) =>
    assert.equal((await call("PUT", "/v1/device/push-token", deviceToken, { token: apns.repeat(32), environment: "sandbox" })).statusCode, 204);
  const pushTo = async (accountId: string, words: string) => {
    push.sent.length = 0;
    await enqueue(db, accountId, ["push"], words, new Date(Date.now() - 3600_000), `k-${words}`, { cipher: testCipher });
    await dispatchDue(db, { push, cipher: testCipher });
    return push.sent.map((p) => ({ apns: p.target.deviceToken, body: p.body }));
  };

  test("the signed-out iPhone's token is refused afterwards, and the answer for a repeat is the same refusal", async () => {
    const phone = await signIn(ALICE);
    assert.ok(await works(phone.deviceToken));
    assert.equal((await call("DELETE", "/v1/device", phone.deviceToken)).statusCode, 204);
    assert.equal((await call("GET", "/v1/calls/settings", phone.deviceToken)).statusCode, 401, "a copied token no longer works");
    // Safe to repeat (a lost answer, an offline retry): the token is already gone, which is what the caller wants.
    assert.equal((await call("DELETE", "/v1/device", phone.deviceToken)).statusCode, 401);
  });

  test("the signed-out iPhone gets no later private push, and another iPhone of the account still does", async () => {
    const first = await signIn(BOB);
    const second = await signIn(BOB);
    assert.equal(second.accountId, first.accountId);
    await register(first.deviceToken, "aa");
    await register(second.deviceToken, "bb");
    assert.deepEqual((await pushTo(first.accountId, "before")).map((p) => p.apns).sort(), ["aa".repeat(32), "bb".repeat(32)]);

    assert.equal((await call("DELETE", "/v1/device", first.deviceToken)).statusCode, 204);

    const after = await pushTo(first.accountId, "after");
    assert.deepEqual(after, [{ apns: "bb".repeat(32), body: "after" }], "only the iPhone still signed in");
    assert.equal((await db.query("SELECT 1 FROM devices WHERE apns_token = $1", ["aa".repeat(32)])).rowCount, 0, "its APNs binding went with it");
    assert.ok(await works(second.deviceToken), "the other iPhone keeps working");
    assert.equal((await call("PUT", "/v1/device/push-token", second.deviceToken, { token: "bb".repeat(32), environment: "sandbox" })).statusCode, 204, "and can still register for push");
  });

  test("signing in again on the same iPhone makes a new token; the revoked one stays dead; the account and its data stay", async () => {
    const SUB = "7d2eab90-4c63-4e5f-9a81-23456789abcd";
    const before = await signIn(SUB);
    await db.query("INSERT INTO phone_numbers (account_id, e164, verified_at) VALUES ($1, '+48600100201', now())", [before.accountId]);
    assert.equal((await call("DELETE", "/v1/device", before.deviceToken)).statusCode, 204);
    const again = await signIn(SUB);
    assert.equal(again.accountId, before.accountId);
    assert.notEqual(again.deviceToken, before.deviceToken);
    assert.ok(await works(again.deviceToken));
    assert.equal(await works(before.deviceToken), false);
    assert.equal((await db.query("SELECT 1 FROM phone_numbers WHERE account_id = $1", [before.accountId])).rowCount, 1);
  });

  test("an iPhone of one account can't sign out another's", async () => {
    const alice = await signIn("8e3fbca1-5d74-4f60-ab92-3456789abcde");
    const bob = await signIn("9f40cdb2-6e85-4071-bca3-456789abcdef");
    assert.equal((await call("DELETE", "/v1/device", alice.deviceToken)).statusCode, 204);
    assert.ok(await works(bob.deviceToken));
    // The route takes no id: it only ever acts on the caller's own device, so there is nothing to aim at Bob's.
    assert.equal((await call("DELETE", "/v1/device", alice.deviceToken)).statusCode, 401);
  });

  test("no token, a malformed token or an unknown one is refused, and nothing is deleted", async () => {
    const phone = await signIn("a051dec3-7f96-4182-8cb4-56789abcdef0");
    const count = async () => Number((await db.query<{ n: string }>("SELECT count(*) AS n FROM devices")).rows[0]!.n);
    const before = await count();
    assert.equal((await app.inject({ method: "DELETE", url: "/v1/device" })).statusCode, 401);
    assert.equal((await call("DELETE", "/v1/device", "short")).statusCode, 401);
    assert.equal((await call("DELETE", "/v1/device", "A".repeat(43))).statusCode, 401);
    assert.equal(await count(), before);
    assert.ok(await works(phone.deviceToken));
  });

  test("the only device of an anonymous account is never deleted this way: it is the only way back into that account", async () => {
    const anon = (await app.inject({ method: "POST", url: "/v1/accounts" })).json() as { accountId: string; deviceToken: string };
    const refused = await call("DELETE", "/v1/device", anon.deviceToken);
    assert.equal(refused.statusCode, 409);
    assert.deepEqual(refused.json(), { error: "device_not_signed_in_to_an_account" });
    assert.ok(await works(anon.deviceToken));
  });

  test("push-token removal still works as before, and leaves the token valid", async () => {
    const phone = await signIn("b162efd4-80a7-4293-9dc5-6789abcdef01");
    await register(phone.deviceToken, "cc");
    assert.equal((await call("DELETE", "/v1/device/push-token", phone.deviceToken)).statusCode, 204);
    assert.ok(await works(phone.deviceToken));
    assert.deepEqual(await pushTo(phone.accountId, "none"), []);
  });
});
