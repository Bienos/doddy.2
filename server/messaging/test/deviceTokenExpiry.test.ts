import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { hashToken } from "../src/auth.js";
import { loadConfig } from "../src/config.js";
import type { Db } from "../src/db.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

// Decision 2026-11-12-account-and-device-tokens, part (d): a device token of a Doddy account stops working after
// 60 days unseen or 180 days after it was issued, and `POST /v1/accounts/sign-in` with the current token hands out a
// fresh one while the old one lives on for a few minutes. An anonymous account's token never expires.

const DAY = 86_400_000;

describe("device token expiry and rotation (real Postgres)", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let lax: FastifyInstance;
  let short: FastifyInstance;

  before(async () => {
    db = await freshDb();
    // Any bearer is a Doddy account whose subject is the bearer itself: the sign-in check is not what is tested here.
    const accounts = { verify: async (token: string) => ({ sub: token }) };
    ({ app } = await testApp(db, { accounts }));
    // The switch off: nothing expires, whatever the numbers.
    ({ app: lax } = await testApp(db, { accounts, deviceTokens: { enforce: false } }));
    // Other numbers: one day idle, two days absolute, no overlap.
    ({ app: short } = await testApp(db, { accounts, deviceTokens: { idleDays: 1, maxAgeDays: 2, overlapSeconds: 0 } }));
  });
  after(async () => {
    await app.close();
    await lax.close();
    await short.close();
    await db.end();
  });

  let address = 0;
  const signIn = async (subject: string, deviceToken?: string, on: FastifyInstance = app) => {
    address += 1;
    const r = await on.inject({
      method: "POST", url: "/v1/accounts/sign-in", remoteAddress: `10.66.${address >> 8}.${address & 255}`,
      headers: { authorization: `Bearer ${subject}` }, payload: deviceToken ? { deviceToken } : {},
    });
    return { status: r.statusCode, body: r.json() as any };
  };
  const phone = async (subject: string, on: FastifyInstance = app) => {
    const r = await signIn(subject, undefined, on);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    return r.body as { accountId: string; deviceToken: string; expiresAt: string | null };
  };
  const anonymous = async () =>
    (await app.inject({ method: "POST", url: "/v1/accounts" })).json() as { accountId: string; deviceToken: string };
  const status = async (deviceToken: string, on: FastifyInstance = app) =>
    (await on.inject({ method: "GET", url: "/v1/calls/settings", headers: { authorization: `Bearer ${deviceToken}` } })).statusCode;
  const works = async (deviceToken: string, on: FastifyInstance = app) => (await status(deviceToken, on)) === 200;
  const row = async (deviceToken: string) =>
    (await db.query<{ id: string; last_seen_at: Date; token_issued_at: Date; previous_token_hash: Buffer | null; previous_valid_until: Date | null }>(
      "SELECT id, last_seen_at, token_issued_at, previous_token_hash, previous_valid_until FROM devices WHERE token_hash = $1",
      [hashToken(deviceToken)])).rows[0];
  const devicesOf = async (accountId: string) =>
    Number((await db.query<{ n: string }>("SELECT count(*) AS n FROM devices WHERE account_id = $1", [accountId])).rows[0]!.n);
  /** Moves a token's clocks back in time. */
  const age = (deviceToken: string, over: { seen?: string; issued?: string }) =>
    db.query(
      `UPDATE devices SET last_seen_at = COALESCE(now() - $2::interval, last_seen_at),
                          token_issued_at = COALESCE(now() - $3::interval, token_issued_at) WHERE token_hash = $1`,
      [hashToken(deviceToken), over.seen ?? null, over.issued ?? null]);
  const closeTo = (a: number, b: number, slackMs = 60_000) => Math.abs(a - b) <= slackMs;

  test("idle expiry: unseen for 60 days is refused, 59 is not, and a refusal does not count as being seen", async () => {
    const p = await phone("idle-subject");
    await age(p.deviceToken, { seen: "59 days" });
    assert.ok(await works(p.deviceToken), "59 days unseen still works");
    assert.ok(closeTo((await row(p.deviceToken))!.last_seen_at.getTime(), Date.now()), "and that use counted as seen");

    await age(p.deviceToken, { seen: "61 days" });
    const before = (await row(p.deviceToken))!.last_seen_at.getTime();
    assert.equal(await status(p.deviceToken), 401);
    assert.equal((await row(p.deviceToken))!.last_seen_at.getTime(), before, "a refused token is not marked seen");
    assert.equal(await status(p.deviceToken), 401, "so it stays refused");
  });

  test("absolute expiry: 180 days after it was issued, however recently it was used", async () => {
    const p = await phone("absolute-subject");
    await age(p.deviceToken, { issued: "179 days" });
    assert.ok(await works(p.deviceToken));
    await age(p.deviceToken, { issued: "181 days", seen: "1 minute" });
    assert.equal(await status(p.deviceToken), 401);
  });

  test("an anonymous account's token never expires", async () => {
    const anon = await anonymous();
    await age(anon.deviceToken, { seen: "400 days", issued: "400 days" });
    assert.ok(await works(anon.deviceToken));
  });

  test("linking an anonymous iPhone to a Doddy account starts its lifetime then, and keeps the token", async () => {
    const anon = await anonymous();
    await age(anon.deviceToken, { seen: "400 days", issued: "400 days" });
    const linked = await signIn("linked-subject", anon.deviceToken);
    assert.equal(linked.status, 200);
    assert.equal(linked.body.deviceToken, anon.deviceToken, "the token it had stays");
    assert.ok(closeTo(Date.parse(linked.body.expiresAt), Date.now() + 180 * DAY), "180 days from the link");
    assert.ok(await works(anon.deviceToken), "an old anonymous token is not cut off by being linked");
    assert.ok(closeTo((await row(anon.deviceToken))!.token_issued_at.getTime(), Date.now()));
  });

  test("the account moving into an existing one starts the lifetime then, too", async () => {
    const home = await phone("moving-subject");
    const anon = await anonymous();
    await age(anon.deviceToken, { seen: "400 days", issued: "400 days" });
    const moved = await signIn("moving-subject", anon.deviceToken);
    assert.equal(moved.status, 200);
    assert.equal(moved.body.accountId, home.accountId);
    assert.equal(moved.body.deviceToken, anon.deviceToken);
    assert.ok(await works(anon.deviceToken));
    assert.ok(closeTo((await row(anon.deviceToken))!.token_issued_at.getTime(), Date.now()));
  });

  test("a sign-in tells the iPhone when its token runs out: 180 days from issue", async () => {
    const p = await phone("expires-at-subject");
    assert.match(p.expiresAt ?? "", /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    assert.ok(closeTo(Date.parse(p.expiresAt!), (await row(p.deviceToken))!.token_issued_at.getTime() + 180 * DAY, 1000));
  });

  test("the numbers are settings", async () => {
    const p = await phone("short-subject", short);
    assert.ok(closeTo(Date.parse(p.expiresAt!), Date.now() + 2 * DAY), "absolute: 2 days");
    await age(p.deviceToken, { seen: "23 hours" });
    assert.ok(await works(p.deviceToken, short));
    await age(p.deviceToken, { seen: "25 hours" });
    assert.equal(await status(p.deviceToken, short), 401, "idle: 1 day");
    const q = await phone("short-subject", short);
    await age(q.deviceToken, { issued: "49 hours", seen: "1 minute" });
    assert.equal(await status(q.deviceToken, short), 401, "absolute: 2 days");
  });

  test("with the switch off nothing expires, and the answer says the token has no end date", async () => {
    const p = await phone("lax-subject", lax);
    assert.equal(p.expiresAt, null);
    await age(p.deviceToken, { seen: "500 days", issued: "500 days" });
    assert.ok(await works(p.deviceToken, lax));
    // The same row is refused by a server with the switch on: the setting is the server's, not the row's.
    assert.equal(await status(p.deviceToken, app), 401);
  });

  test("rotation: the current token gets a fresh one and its end date; the old one works only inside the overlap", async () => {
    const first = await phone("rotate-subject");
    const rotated = await signIn("rotate-subject", first.deviceToken);
    assert.equal(rotated.status, 200);
    assert.equal(rotated.body.accountId, first.accountId);
    assert.match(rotated.body.deviceToken, /^[A-Za-z0-9_-]{43}$/);
    assert.notEqual(rotated.body.deviceToken, first.deviceToken);
    assert.ok(closeTo(Date.parse(rotated.body.expiresAt), Date.now() + 180 * DAY));
    assert.equal(await devicesOf(first.accountId), 1, "the same device row: one iPhone, not two");

    assert.ok(await works(rotated.body.deviceToken), "the fresh token works");
    assert.ok(await works(first.deviceToken), "the old one still does, for a few minutes (a lost answer must not sign the iPhone out)");
    const stored = (await row(rotated.body.deviceToken))!;
    assert.ok(stored.previous_valid_until && closeTo(stored.previous_valid_until.getTime(), Date.now() + 300_000), "the overlap is 5 minutes");

    await db.query("UPDATE devices SET previous_valid_until = now() - interval '1 second' WHERE token_hash = $1", [hashToken(rotated.body.deviceToken)]);
    assert.equal(await status(first.deviceToken), 401, "after the overlap the old token is refused");
    assert.ok(await works(rotated.body.deviceToken), "and the fresh one keeps working");
  });

  test("rotation resets the absolute lifetime of the token and keeps the push binding of the iPhone", async () => {
    const first = await phone("rotate-fresh-subject");
    assert.equal((await app.inject({
      method: "PUT", url: "/v1/device/push-token", headers: { authorization: `Bearer ${first.deviceToken}` },
      payload: { token: "ab".repeat(32), environment: "sandbox" },
    })).statusCode, 204);
    await age(first.deviceToken, { issued: "170 days" });
    const rotated = await signIn("rotate-fresh-subject", first.deviceToken);
    assert.ok(closeTo((await row(rotated.body.deviceToken))!.token_issued_at.getTime(), Date.now()), "a new token is issued now");
    assert.ok(closeTo(Date.parse(rotated.body.expiresAt), Date.now() + 180 * DAY));
    const bound = (await db.query<{ apns_token: string }>("SELECT apns_token FROM devices WHERE token_hash = $1", [hashToken(rotated.body.deviceToken)])).rows[0];
    assert.equal(bound?.apns_token, "ab".repeat(32), "pushes still go to this iPhone");
  });

  test("a rotation whose answer was lost: asking again with the old token inside the overlap gets another fresh one", async () => {
    const first = await phone("lost-subject");
    const lost = await signIn("lost-subject", first.deviceToken);
    assert.equal(lost.status, 200);
    // The iPhone never saw `lost` and asks again with the token it still has.
    const again = await signIn("lost-subject", first.deviceToken);
    assert.equal(again.status, 200);
    assert.notEqual(again.body.deviceToken, lost.body.deviceToken);
    assert.equal(again.body.accountId, first.accountId);
    assert.equal(await devicesOf(first.accountId), 1, "still one iPhone");
    assert.ok(await works(again.body.deviceToken));
    assert.ok(await works(first.deviceToken), "the window of the old token is the one the first rotation started");
    assert.equal(await status(lost.body.deviceToken), 401, "the answer the iPhone never saw is replaced by the later one");
    const stored = (await row(again.body.deviceToken))!;
    assert.deepEqual(stored.previous_token_hash, hashToken(first.deviceToken), "the earliest token stays the one that overlaps");
  });

  test("after the overlap an old token is only an unknown token: signing in with it makes a new iPhone, never a rotation", async () => {
    const first = await phone("late-subject");
    const rotated = await signIn("late-subject", first.deviceToken);
    await db.query("UPDATE devices SET previous_valid_until = now() - interval '1 second' WHERE token_hash = $1", [hashToken(rotated.body.deviceToken)]);
    const late = await signIn("late-subject", first.deviceToken);
    assert.equal(late.status, 200);
    assert.notEqual(late.body.deviceToken, first.deviceToken);
    assert.notEqual(late.body.deviceToken, rotated.body.deviceToken);
    assert.equal(await devicesOf(first.accountId), 2);
    assert.equal(await status(first.deviceToken), 401);
    assert.ok(await works(rotated.body.deviceToken), "the iPhone that rotated is untouched");
  });

  test("a token that has run out is not renewed by presenting it: the sign-in makes a new iPhone and the old token stays refused", async () => {
    for (const over of [{ seen: "61 days" }, { issued: "181 days", seen: "1 minute" }]) {
      const subject = `runout-${Object.keys(over).join("-")}`;
      const first = await phone(subject);
      await age(first.deviceToken, over);
      const again = await signIn(subject, first.deviceToken);
      assert.equal(again.status, 200, JSON.stringify(again.body));
      assert.notEqual(again.body.deviceToken, first.deviceToken);
      assert.equal(again.body.accountId, first.accountId, "the same Doddy account, so its data is still there");
      assert.ok(await works(again.body.deviceToken));
      assert.equal(await status(first.deviceToken), 401, "the old token is not brought back to life");
      assert.equal(await devicesOf(first.accountId), 2);
    }
  });

  test("only the same Doddy account rotates a token: another account's sign-in is refused and the token is untouched", async () => {
    const alice = await phone("alice-rot-subject");
    const refused = await signIn("bob-rot-subject", alice.deviceToken);
    assert.equal(refused.status, 409);
    assert.equal(refused.body.reason, "device_signed_in_to_another_account");
    assert.ok(await works(alice.deviceToken));
    assert.equal((await row(alice.deviceToken))!.previous_token_hash, null, "nothing was rotated");
  });

  test("one account's expiry or rotation does not touch another's", async () => {
    const a = await phone("neighbour-a-subject");
    const b = await phone("neighbour-b-subject");
    await age(a.deviceToken, { seen: "61 days" });
    const rotatedB = await signIn("neighbour-b-subject", b.deviceToken);
    assert.equal(await status(a.deviceToken), 401);
    assert.ok(await works(rotatedB.body.deviceToken));
    // A second iPhone of an account is judged by its own clocks.
    const b2 = await phone("neighbour-b-subject");
    await age(rotatedB.body.deviceToken, { seen: "61 days" });
    assert.equal(await status(rotatedB.body.deviceToken), 401);
    assert.ok(await works(b2.deviceToken));
  });

  test("signing out (DELETE /v1/device) ends the fresh token and the one in its overlap together; a revoked token cannot be rotated", async () => {
    const first = await phone("revoke-subject");
    const rotated = await signIn("revoke-subject", first.deviceToken);
    assert.ok(await works(first.deviceToken));
    // Signing out with the old token, inside the overlap.
    const out = await app.inject({ method: "DELETE", url: "/v1/device", headers: { authorization: `Bearer ${first.deviceToken}` } });
    assert.equal(out.statusCode, 204);
    assert.equal(await status(first.deviceToken), 401);
    assert.equal(await status(rotated.body.deviceToken), 401);
    const back = await signIn("revoke-subject", rotated.body.deviceToken);
    assert.equal(back.status, 200);
    assert.notEqual(back.body.deviceToken, rotated.body.deviceToken, "a revoked token is not brought back; this is a new iPhone");
    assert.equal(await status(rotated.body.deviceToken), 401);
  });

  test("signing in again without a token (the iPhone's own recovery) always works and keeps the account", async () => {
    const first = await phone("recover-subject");
    await age(first.deviceToken, { seen: "70 days", issued: "190 days" });
    assert.equal(await status(first.deviceToken), 401);
    const again = await phone("recover-subject");
    assert.equal(again.accountId, first.accountId);
    assert.ok(await works(again.deviceToken));
  });

  test("seen is written at most once an hour, and only for a token that is accepted", async () => {
    const p = await phone("seen-subject");
    const seen = async () => (await row(p.deviceToken))!.last_seen_at.getTime();

    await age(p.deviceToken, { seen: "30 minutes" });
    const thirty = await seen();
    assert.ok(await works(p.deviceToken));
    assert.equal(await seen(), thirty, "within the hour: no write");

    await age(p.deviceToken, { seen: "2 hours" });
    const two = await seen();
    assert.ok(await works(p.deviceToken));
    const updated = await seen();
    assert.ok(updated > two && closeTo(updated, Date.now()), "past the hour: written");
    assert.ok(await works(p.deviceToken));
    assert.equal(await seen(), updated, "and not again on the next request");
  });

  test("the answers never carry a token apart from the one a sign-in hands out", async () => {
    const p = await phone("quiet-subject");
    await age(p.deviceToken, { seen: "61 days" });
    const refused = await app.inject({ method: "GET", url: "/v1/calls/settings", headers: { authorization: `Bearer ${p.deviceToken}` } });
    assert.equal(refused.statusCode, 401);
    assert.deepEqual(refused.json(), { error: "unauthorized" });
    assert.ok(!refused.body.includes(p.deviceToken));
  });
});

test("the code that decides expiry and rotation writes no log line (a token must never reach a log)", () => {
  for (const file of ["../../src/auth.ts", "../../src/routes/account.ts"]) {
    const source = readFileSync(new URL(file, import.meta.url), "utf8");
    assert.ok(!/console\.|\.log\.(info|warn|error|debug)|app\.log|req\.log|reply\.log/.test(source), `${file} logs`);
  }
});

describe("the settings", () => {
  const ENV = { DATABASE_URL: "postgres://x/y" };

  test("60 days idle, 180 absolute, a 5-minute overlap, and on", () => {
    assert.deepEqual(loadConfig(ENV).deviceTokens, { enforce: true, idleDays: 60, maxAgeDays: 180, overlapSeconds: 300 });
    assert.deepEqual(
      loadConfig({ ...ENV, DEVICE_TOKEN_EXPIRY: "", DEVICE_TOKEN_IDLE_DAYS: "", DEVICE_TOKEN_MAX_AGE_DAYS: "", DEVICE_TOKEN_OVERLAP_SECONDS: "" }).deviceTokens,
      { enforce: true, idleDays: 60, maxAgeDays: 180, overlapSeconds: 300 }, "empty counts as unset");
  });

  test("each can be set, and DEVICE_TOKEN_EXPIRY=0 switches enforcement off", () => {
    assert.deepEqual(
      loadConfig({ ...ENV, DEVICE_TOKEN_EXPIRY: "0", DEVICE_TOKEN_IDLE_DAYS: "30", DEVICE_TOKEN_MAX_AGE_DAYS: "90", DEVICE_TOKEN_OVERLAP_SECONDS: "60" }).deviceTokens,
      { enforce: false, idleDays: 30, maxAgeDays: 90, overlapSeconds: 60 });
    assert.equal(loadConfig({ ...ENV, DEVICE_TOKEN_EXPIRY: "1" }).deviceTokens.enforce, true);
  });

  test("bad values stop the start-up; the idle limit may not be longer than the absolute one", () => {
    const bad: Record<string, string>[] = [
      { DEVICE_TOKEN_EXPIRY: "yes" }, { DEVICE_TOKEN_IDLE_DAYS: "0" }, { DEVICE_TOKEN_IDLE_DAYS: "2.5" }, { DEVICE_TOKEN_MAX_AGE_DAYS: "0" },
      { DEVICE_TOKEN_MAX_AGE_DAYS: "4000" }, { DEVICE_TOKEN_OVERLAP_SECONDS: "-1" }, { DEVICE_TOKEN_OVERLAP_SECONDS: "3601" },
      { DEVICE_TOKEN_IDLE_DAYS: "200" },
    ];
    for (const env of bad) assert.throws(() => loadConfig({ ...ENV, ...env }), JSON.stringify(env));
  });
});
