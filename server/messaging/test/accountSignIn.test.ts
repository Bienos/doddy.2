import assert from "node:assert/strict";
import { generateKeyPairSync, type KeyObject, sign } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { createAccountVerifier, madeWithPassword } from "../src/doddyAccount.js";
import { MAX_DEVICES_PER_ACCOUNT } from "../src/routes/account.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

// Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account (a Supabase
// user: Apple, Google or a code by email). POST /v1/accounts/sign-in checks it against the project's
// keys, finds or makes this server's account for it, and gives this iPhone its device token. An
// iPhone's earlier anonymous account is linked once, never merged.

const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const ALICE = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const BOB = "6c1d9a8f-3b52-4d4e-8f70-123456789abc";
const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const other = generateKeyPairSync("ec", { namedCurve: "P-256" });
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");

function account(sub: string, claims: Record<string, unknown> = {}, key: KeyObject = ec.privateKey): string {
  const nowS = Math.floor(Date.now() / 1000);
  const header = b64({ alg: "ES256", kid: "k1", typ: "JWT" });
  const body = b64({
    iss: ISSUER, aud: "authenticated", role: "authenticated", sub, iat: nowS - 10, exp: nowS + 3600, is_anonymous: false,
    app_metadata: { provider: "email", providers: ["email"] }, amr: [{ method: "otp", timestamp: nowS - 10 }], ...claims,
  });
  const signature = sign("sha256", Buffer.from(`${header}.${body}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${signature.toString("base64url")}`;
}

function keys() {
  const state = { fail: false, fetches: 0 };
  const fetch = async () => {
    state.fetches += 1;
    if (state.fail) throw new Error("unreachable");
    return { ok: true, json: async () => ({ keys: [{ ...ec.publicKey.export({ format: "jwk" }), kid: "k1", alg: "ES256", use: "sig" }] }) };
  };
  return { state, fetch };
}

test("passwords are found in either amr shape", () => {
  assert.equal(madeWithPassword([{ method: "password" }]), true);
  assert.equal(madeWithPassword(["Password"]), true);
  for (const amr of [undefined, [], [{ method: "otp" }], ["oauth"]]) assert.equal(madeWithPassword(amr), false);
});

describe("POST /v1/accounts/sign-in", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  const jwks = keys();

  before(async () => {
    db = await freshDb();
    ({ app } = await testApp(db, { accounts: createAccountVerifier({ projectUrl: PROJECT, fetch: jwks.fetch }) }));
  });
  after(async () => {
    await app.close();
    await db.end();
  });

  // Each sign-in from its own address unless a test names one: the route allows 30 an hour per address.
  let nextAddress = 0;
  const signIn = async (token: string | undefined, body?: unknown, remoteAddress?: string) => {
    nextAddress += 1;
    const r = await app.inject({
      method: "POST", url: "/v1/accounts/sign-in",
      remoteAddress: remoteAddress ?? `10.88.${nextAddress >> 8}.${nextAddress & 255}`,
      headers: token ? { authorization: `Bearer ${token}` } : {},
      ...(body !== undefined ? { payload: body as Record<string, unknown> } : {}),
    });
    return { status: r.statusCode, body: r.json() as any };
  };
  const anonymous = async () => (await app.inject({ method: "POST", url: "/v1/accounts" })).json() as { accountId: string; deviceToken: string };
  const works = async (deviceToken: string) =>
    (await app.inject({ method: "GET", url: "/v1/calls/settings", headers: { authorization: `Bearer ${deviceToken}` } })).statusCode === 200;
  const subjectOf = async (accountId: string) =>
    (await db.query<{ auth_subject: string | null }>("SELECT auth_subject FROM accounts WHERE id = $1", [accountId])).rows[0]?.auth_subject;

  test("a Doddy account gets one account here, and each iPhone its own device token", async () => {
    const first = await signIn(account(ALICE));
    assert.equal(first.status, 200);
    assert.match(first.body.deviceToken, /^[A-Za-z0-9_-]{43}$/);
    assert.equal(await subjectOf(first.body.accountId), ALICE);
    assert.ok(await works(first.body.deviceToken));
    // Another iPhone (or this one after a reinstall): the same account, a new token; both work.
    const second = await signIn(account(ALICE, { app_metadata: { provider: "apple" }, amr: [{ method: "id_token" }] }));
    assert.equal(second.body.accountId, first.body.accountId);
    assert.notEqual(second.body.deviceToken, first.body.deviceToken);
    assert.ok(await works(first.body.deviceToken) && await works(second.body.deviceToken));
  });

  test("an iPhone's anonymous account is linked to the Doddy account once, keeping its token and its data", async () => {
    const anon = await anonymous();
    await db.query("INSERT INTO phone_numbers (account_id, e164, verified_at) VALUES ($1, '+48600100200', now())", [anon.accountId]);
    const linked = await signIn(account(BOB), { deviceToken: anon.deviceToken });
    assert.equal(linked.status, 200);
    assert.deepEqual(linked.body, { accountId: anon.accountId, deviceToken: anon.deviceToken });
    assert.equal(await subjectOf(anon.accountId), BOB);
    assert.equal((await db.query("SELECT 1 FROM phone_numbers WHERE account_id = $1", [anon.accountId])).rowCount, 1, "its data stays");
    // A repeat (a lost answer) is answered the same way.
    assert.deepEqual((await signIn(account(BOB), { deviceToken: anon.deviceToken })).body, linked.body);
    // Signing in later without the token reaches the same account.
    assert.equal((await signIn(account(BOB))).body.accountId, anon.accountId);
  });

  test("an unused anonymous account moves into the Doddy account's existing one; one with data is never merged", async () => {
    const SUB = "7d2eab90-4c63-4e5f-9a81-23456789abcd";
    const home = (await signIn(account(SUB))).body.accountId as string;

    const fresh = await anonymous();
    const moved = await signIn(account(SUB), { deviceToken: fresh.deviceToken });
    assert.equal(moved.status, 200);
    assert.deepEqual(moved.body, { accountId: home, deviceToken: fresh.deviceToken });
    assert.equal((await db.query("SELECT 1 FROM accounts WHERE id = $1", [fresh.accountId])).rowCount, 0, "the empty account is gone");
    assert.ok(await works(fresh.deviceToken));

    const used = await anonymous();
    await db.query("INSERT INTO phone_numbers (account_id, e164, verified_at) VALUES ($1, '+48600300400', now())", [used.accountId]);
    const refused = await signIn(account(SUB), { deviceToken: used.deviceToken });
    assert.equal(refused.status, 409);
    assert.deepEqual(refused.body, { error: "account_conflict", reason: "device_account_has_data" });
    assert.equal(await subjectOf(used.accountId), null, "nothing changed");
    assert.ok(await works(used.deviceToken));
  });

  test("a device token already signed in to another Doddy account is refused", async () => {
    const carol = "8e3fbca1-5d74-4f60-ab92-3456789abcde";
    const dave = "9f40cdb2-6e85-4071-bca3-456789abcdef";
    const c = await signIn(account(carol));
    const refused = await signIn(account(dave), { deviceToken: c.body.deviceToken });
    assert.equal(refused.status, 409);
    assert.equal(refused.body.reason, "device_signed_in_to_another_account");
    assert.equal(await subjectOf(c.body.accountId), carol);
  });

  test("bad sign-ins are refused before anything is written", async () => {
    const before = (await db.query("SELECT count(*)::int AS n FROM accounts")).rows[0].n as number;
    const anon = await anonymous();
    const cases: [string, string | undefined, unknown, number][] = [
      ["no token", undefined, undefined, 401],
      ["a device token as the account", anon.deviceToken, undefined, 401],
      ["another key", account(ALICE, {}, other.privateKey), undefined, 401],
      ["a password session", account(ALICE, { amr: [{ method: "password" }] }), undefined, 401],
      ["phone sign-in", account(ALICE, { app_metadata: { provider: "phone" } }), undefined, 401],
      ["expired", account(ALICE, { exp: Math.floor(Date.now() / 1000) - 1 }), undefined, 401],
      ["a malformed device token", account(ALICE), { deviceToken: "short" }, 400],
      ["an extra field", account(ALICE), { deviceToken: anon.deviceToken, accountId: anon.accountId }, 400],
    ];
    for (const [name, token, body, status] of cases) assert.equal((await signIn(token, body)).status, status, name);
    assert.equal((await db.query("SELECT count(*)::int AS n FROM accounts")).rows[0].n, before + 1, "only the anonymous account was made");
    assert.equal(await subjectOf(anon.accountId), null);
  });

  test(`an account keeps at most ${MAX_DEVICES_PER_ACCOUNT} iPhones: a new one replaces the one unseen longest`, async () => {
    const SUB = "a0b1c2d3-7f96-4182-8cd4-56789abcdef0";
    const first = await signIn(account(SUB));
    await db.query("UPDATE devices SET last_seen_at = now() - interval '30 days' WHERE account_id = $1", [first.body.accountId]);
    for (let i = 1; i < MAX_DEVICES_PER_ACCOUNT; i += 1) await signIn(account(SUB));
    assert.ok(await works(first.body.deviceToken), "ten iPhones fit");
    // The request above marked the first iPhone as seen now; make it the oldest again.
    await db.query("UPDATE devices SET last_seen_at = now() - interval '30 days' WHERE token_hash = (SELECT token_hash FROM devices WHERE account_id = $1 ORDER BY created_at LIMIT 1)", [first.body.accountId]);
    await signIn(account(SUB));
    const n = (await db.query("SELECT count(*)::int AS n FROM devices WHERE account_id = $1", [first.body.accountId])).rows[0].n;
    assert.equal(n, MAX_DEVICES_PER_ACCOUNT);
    assert.equal(await works(first.body.deviceToken), false, "the iPhone unseen longest made room");
  });

  test("deleting the account frees the Doddy account, which then gets a fresh, empty one", async () => {
    const SUB = "b1c2d3e4-8a07-4293-9de5-6789abcdef01";
    const first = await signIn(account(SUB));
    const del = await app.inject({ method: "DELETE", url: "/v1/account", headers: { authorization: `Bearer ${first.body.deviceToken}` } });
    assert.equal(del.statusCode, 204);
    const again = await signIn(account(SUB));
    assert.equal(again.status, 200);
    assert.notEqual(again.body.accountId, first.body.accountId);
  });

  test("at most 30 sign-ins an hour from one address", async () => {
    const SUB = "c2d3e4f5-9b18-43a4-8ef6-789abcdef012";
    for (let i = 0; i < 30; i += 1) assert.equal((await signIn(account(SUB), undefined, "10.99.0.1")).status, 200);
    const limited = await signIn(account(SUB), undefined, "10.99.0.1");
    assert.equal(limited.status, 429);
    assert.equal((await signIn(account(SUB), undefined, "10.99.0.2")).status, 200, "another address is not affected");
  });

  test("keys that can't be read are a 503 'try again', never a 401", async () => {
    const down = keys();
    down.state.fail = true;
    const { app: offline } = await testApp(db, { accounts: createAccountVerifier({ projectUrl: PROJECT, fetch: down.fetch }) });
    try {
      const r = await offline.inject({ method: "POST", url: "/v1/accounts/sign-in", headers: { authorization: `Bearer ${account(ALICE)}` } });
      assert.equal(r.statusCode, 503);
      assert.deepEqual(r.json(), { error: "account_check_unavailable" });
    } finally {
      await offline.close();
    }
  });

  test("a server with no Supabase project says it isn't set up", async () => {
    const { app: plain } = await testApp(db);
    try {
      const r = await plain.inject({ method: "POST", url: "/v1/accounts/sign-in", headers: { authorization: `Bearer ${account(ALICE)}` } });
      assert.equal(r.statusCode, 503);
      assert.deepEqual(r.json(), { error: "not_configured" });
    } finally {
      await plain.close();
    }
  });
});
