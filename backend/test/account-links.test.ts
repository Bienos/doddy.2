import assert from "node:assert/strict";
import { once } from "node:events";
import { generateKeyPairSync, type KeyObject, sign } from "node:crypto";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { LINK_TRIES_PER_HOUR } from "../src/accountLinks.js";
import { buildApp } from "../src/app.js";
import type { FetchJson } from "../src/auth.js";
import { loadConfig } from "../src/config.js";
import { deviceUserId } from "../src/deviceSession.js";
import type { Store } from "../src/store.js";

// Decision 2026-11-08-required-account: every user signs in with a Doddy account (a Supabase user:
// Apple, Google or a code by email). An iPhone that used Doddy before links its earlier data to the
// account once, with its own device token as proof; accounts are never merged (ADR-600).

const KEY = Buffer.alloc(32, 7);
const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const ACCOUNT = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const ACCOUNT_2 = "6c1d9a8f-3b52-4d4e-8f70-123456789abc";
const ACCOUNT_3 = "7d2eab90-4c63-4e5f-9a81-23456789abcd";
const PHONE = (n: number) => `1b4e28ba-2fa1-41d2-883f-${String(n).padStart(12, "0")}`;

const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwks: FetchJson = async () => ({ keys: [{ ...ec.publicKey.export({ format: "jwk" }), kid: "k1", alg: "ES256", use: "sig" }] });
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");

/** A Supabase access token signed with the test project's key (as `auth-supabase.test.ts` makes them). */
function account(sub: string, claims: Record<string, unknown> = {}, key: KeyObject = ec.privateKey): string {
  const nowS = Math.floor(Date.now() / 1000);
  const header = b64({ alg: "ES256", kid: "k1", typ: "JWT" });
  const body = b64({
    iss: ISSUER,
    aud: "authenticated",
    role: "authenticated",
    sub,
    iat: nowS - 10,
    exp: nowS + 3600,
    is_anonymous: false,
    app_metadata: { provider: "email", providers: ["email"] },
    amr: [{ method: "otp", timestamp: nowS - 10 }],
    ...claims,
  });
  const signature = sign("sha256", Buffer.from(`${header}.${body}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${signature.toString("base64url")}`;
}

const BASE_ENV = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "supabase",
  SUPABASE_URL: PROJECT,
  DODDY_SESSION_SIGNING_KEY: KEY.toString("base64"),
  DODDY_DEVICE_SIGNUP: "first-device",
  DODDY_OWNER_CLAIM: "open",
  DODDY_DEVICE_INVITE_CODES: "second-phone-code-1",
  DODDY_PUBLIC_BASE_URL: "https://doddy.onrender.com",
  DODDY_DB_PATH: ":memory:",
  MONID_API_KEY: "monid_live_abcdefgh123",
};

const servers: Server[] = [];
const closers: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const s of servers.splice(0)) s.close();
  for (const c of closers.splice(0)) await c();
});

async function app(env: Record<string, string> = {}) {
  const { server, store } = await buildApp(loadConfig({ ...BASE_ENV, ...env }), { webSearch: null, supabaseFetchJson: jwks });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  servers.push(server);
  closers.push(() => store.close());
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = async (method: string, path: string, authorization?: string, body?: unknown) => {
    const headers: Record<string, string> = {};
    if (authorization) headers.authorization = `Bearer ${authorization}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    const res = await fetch(`${base}${path}`, { method, headers, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
    const text = await res.text();
    return { status: res.status, body: text ? (JSON.parse(text) as any) : null };
  };
  return {
    store,
    call,
    signInDevice: async (deviceId: string, extra: Record<string, unknown> = {}) => call("POST", "/v1/session/device", undefined, { deviceId, ...extra }),
    link: (accountToken: string | undefined, deviceToken: unknown) => call("POST", "/v1/account/link-device", accountToken, { deviceToken }),
  };
}

/** Something of this person's on the server, the way a tool switch is stored. */
async function seedSwitch(store: Store, userId: string, tool = "check_email"): Promise<void> {
  await store.db.query("INSERT INTO tool_switches (user_id, tool, enabled, changed_at) VALUES ($1, $2, 1, 1)", [userId, tool]);
}
async function switchesOf(store: Store, userId: string): Promise<number> {
  return Number((await store.db.query<{ n: string }>("SELECT count(*) AS n FROM tool_switches WHERE user_id = $1", [userId])).rows[0]!.n);
}

test("an iPhone's first sign-in links its earlier data to the account, and the device token stops being a key to it", async () => {
  const doddy = await app();
  const device = await doddy.signInDevice(PHONE(1));
  assert.equal(device.status, 200);
  const deviceToken = device.body.token as string;
  const phoneUser = deviceUserId(KEY, PHONE(1));
  await seedSwitch(doddy.store, phoneUser);
  // Before the link both sign-ins work, each on its own data.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", account(ACCOUNT))).status, 200);

  const linked = await doddy.link(account(ACCOUNT), deviceToken);
  assert.equal(linked.status, 200);
  assert.deepEqual(linked.body, { linked: true });
  // A repeat (a lost answer, tried again) is answered the same way.
  assert.deepEqual((await doddy.link(account(ACCOUNT), deviceToken)).body, { linked: true });

  // The device token no longer opens the data, and the device can't get a new one.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 401);
  const again = await doddy.signInDevice(PHONE(1));
  assert.equal(again.status, 409);
  assert.equal(again.body.error.code, "account_conflict");
  assert.match(again.body.error.message, /Sign in with Apple, Google or email/);

  // The account works on the phone's earlier data: deleting it deletes that data, and the account at Supabase.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", account(ACCOUNT))).status, 200);
  const erased = await doddy.call("DELETE", "/v1/account", account(ACCOUNT));
  assert.equal(erased.status, 200);
  assert.equal(erased.body.deleted.tool_switches, 1);
  assert.equal(erased.body.deleted.account_links, 1);
  assert.equal(await switchesOf(doddy.store, phoneUser), 0);
  const owed = (await doddy.store.db.query<{ connection_id: string; provider: string }>("SELECT connection_id, provider FROM cleanups")).rows;
  assert.deepEqual(owed, [{ connection_id: ACCOUNT, provider: "supabase_auth" }], "the Supabase user is owed a removal (no secret key here: pending)");
  // That account's sign-in made before the deletion ends at once (Supabase would let it live up to an hour).
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", account(ACCOUNT, { iat: Math.floor(Date.now() / 1000) - 30 }))).status, 401);
});

test("a new account with no earlier iPhone data just works, and deleting it removes it at Supabase", async () => {
  const doddy = await app();
  const token = account(ACCOUNT_2, { app_metadata: { provider: "apple" }, amr: [{ method: "id_token" }] });
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", token)).status, 200);
  await seedSwitch(doddy.store, ACCOUNT_2);
  const erased = await doddy.call("DELETE", "/v1/account", token);
  assert.equal(erased.status, 200);
  assert.equal(erased.body.deleted.tool_switches, 1);
  const owed = (await doddy.store.db.query<{ connection_id: string }>("SELECT connection_id FROM cleanups WHERE provider = 'supabase_auth'")).rows;
  assert.deepEqual(owed, [{ connection_id: ACCOUNT_2 }]);
});

test("accounts are never merged: each conflict is refused with its reason, and nothing is linked", async () => {
  const doddy = await app();
  const owner = (await doddy.signInDevice(PHONE(1))).body.token as string;
  const second = (await doddy.signInDevice(PHONE(2), { inviteCode: "second-phone-code-1" })).body.token as string;
  assert.ok(owner && second);

  // An account with data of its own can't take over a phone's data.
  await seedSwitch(doddy.store, ACCOUNT_2);
  const hasData = await doddy.link(account(ACCOUNT_2), owner);
  assert.equal(hasData.status, 409);
  assert.equal(hasData.body.error.code, "account_conflict");
  assert.match(hasData.body.error.message, /never merged/);

  // One account per phone's data, and one phone's data per account.
  assert.equal((await doddy.link(account(ACCOUNT), owner)).status, 200);
  const subjectTaken = await doddy.link(account(ACCOUNT), second);
  assert.equal(subjectTaken.status, 409);
  assert.match(subjectTaken.body.error.message, /already has another iPhone's earlier data/);
  const userTaken = await doddy.link(account(ACCOUNT_3), owner);
  assert.equal(userTaken.status, 409);
  assert.match(userTaken.body.error.message, /already belongs to another Doddy account/);

  const links = (await doddy.store.db.query<{ subject: string; user_id: string }>("SELECT subject, user_id FROM account_links ORDER BY subject")).rows;
  assert.deepEqual(links, [{ subject: ACCOUNT, user_id: deviceUserId(KEY, PHONE(1)) }]);
  // The phone that wasn't linked keeps its own device sign-in.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", second)).status, 200);
});

test("linking needs a valid account and a valid device token, each in its place", async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  const other = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const cases: [string, string | undefined, unknown, number][] = [
    ["no account", undefined, deviceToken, 401],
    ["a device token as the account", deviceToken, deviceToken, 401],
    ["an account signed by another key", account(ACCOUNT, {}, other.privateKey), deviceToken, 401],
    ["a password session", account(ACCOUNT, { amr: [{ method: "password" }] }), deviceToken, 401],
    ["an expired account token", account(ACCOUNT, { exp: Math.floor(Date.now() / 1000) - 1 }), deviceToken, 401],
    ["an account token as the device's", account(ACCOUNT), account(ACCOUNT), 400],
    ["no device token", account(ACCOUNT), undefined, 400],
    ["a forged device token", account(ACCOUNT), `${deviceToken.slice(0, -4)}AAAA`, 401],
  ];
  for (const [name, accountToken, device, status] of cases) {
    const res = await doddy.link(accountToken, device);
    assert.equal(res.status, status, name);
  }
  assert.equal(Number((await doddy.store.db.query<{ n: string }>("SELECT count(*) AS n FROM account_links")).rows[0]!.n), 0);
  // The device still works: nothing was linked.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
});

test(`at most ${LINK_TRIES_PER_HOUR} link tries per account per hour`, async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  await seedSwitch(doddy.store, ACCOUNT_2); // every try is a conflict, so each one counts
  for (let i = 0; i < LINK_TRIES_PER_HOUR; i += 1) assert.equal((await doddy.link(account(ACCOUNT_2), deviceToken)).status, 409);
  const limited = await doddy.link(account(ACCOUNT_2), deviceToken);
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error.code, "rate_limited");
});

test("a server with no Supabase project says accounts aren't set up, and device sign-in is unchanged", async () => {
  const doddy = await app({ DODDY_AUTH_MODE: "signed" });
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  const res = await doddy.link(account(ACCOUNT), deviceToken);
  assert.equal(res.status, 503);
  assert.equal(res.body.error.code, "live_not_configured");
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
});
