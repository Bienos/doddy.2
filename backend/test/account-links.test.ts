import assert from "node:assert/strict";
import { once } from "node:events";
import { generateKeyPairSync, type KeyObject, sign } from "node:crypto";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { LINK_CODES_PER_HOUR, LINK_TRIES_PER_HOUR, LINK_UNDO_WINDOW_MS } from "../src/accountLinks.js";
import { buildApp } from "../src/app.js";
import { type FetchJson, SignedSessionVerifier } from "../src/auth.js";
import { loadConfig } from "../src/config.js";
import { deviceUserId } from "../src/deviceSession.js";
import type { Store } from "../src/store.js";

// Decision 2026-11-08-required-account: every user signs in with a Doddy account (a Supabase user:
// Apple, Google or a code by email). An iPhone that used Doddy before links its earlier data to the
// account once; accounts are never merged (ADR-600). The iPhone's own device session starts each link
// with a one-time code, and can take its data back for a day.

const KEY = Buffer.alloc(32, 7);
const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const ACCOUNT = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const ACCOUNT_2 = "6c1d9a8f-3b52-4d4e-8f70-123456789abc";
const ACCOUNT_3 = "7d2eab90-4c63-4e5f-9a81-23456789abcd";
const PHONE = (n: number) => `1b4e28ba-2fa1-41d2-883f-${String(n).padStart(12, "0")}`;
const MADE_UP_CODE = "A".repeat(43);

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
  const start = (deviceToken: string | undefined) => call("POST", "/v1/account/link-device/start", deviceToken);
  const link = (accountToken: string | undefined, linkCode: unknown) => call("POST", "/v1/account/link-device", accountToken, { linkCode });
  return {
    store,
    call,
    signInDevice: async (deviceId: string, extra: Record<string, unknown> = {}) => call("POST", "/v1/session/device", undefined, { deviceId, ...extra }),
    start,
    link,
    undo: (deviceToken: string | undefined) => call("POST", "/v1/account/link-device/undo", deviceToken),
    /** What the iPhone does: its device session asks for a code, then the account links with it. */
    linkPhone: async (accountToken: string, deviceToken: string) => {
      const started = await start(deviceToken);
      assert.equal(started.status, 200, "the iPhone's own session gets a code");
      return link(accountToken, started.body.linkCode);
    },
  };
}

/** Something of this person's on the server, the way a tool switch is stored. */
async function seedSwitch(store: Store, userId: string, tool = "check_email"): Promise<void> {
  await store.db.query("INSERT INTO tool_switches (user_id, tool, enabled, changed_at) VALUES ($1, $2, 1, 1)", [userId, tool]);
}
async function switchesOf(store: Store, userId: string): Promise<number> {
  return Number((await store.db.query<{ n: string }>("SELECT count(*) AS n FROM tool_switches WHERE user_id = $1", [userId])).rows[0]!.n);
}
async function links(store: Store): Promise<{ subject: string; user_id: string }[]> {
  return (await store.db.query<{ subject: string; user_id: string }>("SELECT subject, user_id FROM account_links ORDER BY subject")).rows;
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

  // The iPhone's own session starts: a one-time code, short-lived, kept on the server only as a hash.
  const started = await doddy.start(deviceToken);
  assert.equal(started.status, 200);
  assert.match(started.body.linkCode, /^[A-Za-z0-9_-]{43}$/);
  const expiresIn = Date.parse(started.body.expiresAt) - Date.now();
  assert.ok(expiresIn > 4 * 60_000 && expiresIn <= 5 * 60_000, "about five minutes");
  const kept = (await doddy.store.db.query<{ code_hash: string; user_id: string }>("SELECT code_hash, user_id FROM account_link_codes")).rows;
  assert.equal(kept.length, 1);
  assert.equal(kept[0]!.user_id, phoneUser);
  assert.notEqual(kept[0]!.code_hash, started.body.linkCode);
  assert.ok(!kept[0]!.code_hash.includes(started.body.linkCode));

  const linked = await doddy.link(account(ACCOUNT), started.body.linkCode);
  assert.equal(linked.status, 200);
  assert.deepEqual(linked.body, { linked: true });
  // A repeat (a lost answer, tried again) starts again and is answered the same way.
  assert.deepEqual((await doddy.linkPhone(account(ACCOUNT), deviceToken)).body, { linked: true });

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

test("a device token on its own links nothing: the code must come from the iPhone's own session just before", async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  await seedSwitch(doddy.store, deviceUserId(KEY, PHONE(1)));

  // The one-step form (the device token in the body) is refused, whoever holds the token.
  const oneStep = await doddy.call("POST", "/v1/account/link-device", account(ACCOUNT), { deviceToken });
  assert.equal(oneStep.status, 400);
  assert.equal(oneStep.body.error.code, "invalid_request");
  // So are a code nobody was given, the device token in the code's place, and both together.
  for (const body of [{ linkCode: MADE_UP_CODE }, { linkCode: deviceToken }, { linkCode: MADE_UP_CODE, deviceToken }]) {
    const res = await doddy.call("POST", "/v1/account/link-device", account(ACCOUNT), body);
    assert.equal(res.status, 400, JSON.stringify(Object.keys(body)));
  }
  assert.deepEqual(await links(doddy.store), []);
  // The device still works on its own data.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
  assert.equal((await doddy.signInDevice(PHONE(1))).status, 200);
});

test("a guest's device token gets no code, and links nothing", async () => {
  const doddy = await app({ DODDY_DEVICE_SIGNUP: "open" });
  assert.equal((await doddy.signInDevice(PHONE(1))).body.access, "full", "the owner");
  const guest = await doddy.signInDevice(PHONE(2));
  assert.equal(guest.body.access, "ask");
  const started = await doddy.start(guest.body.token);
  assert.equal(started.status, 403);
  assert.match(started.body.error.message, /guest/);
  assert.equal(Number((await doddy.store.db.query<{ n: string }>("SELECT count(*) AS n FROM account_link_codes")).rows[0]!.n), 0);
  // A guest token minted by hand with the right key is refused the same way.
  const minted = new SignedSessionVerifier(KEY).mint(deviceUserId(KEY, PHONE(3)), new Date(), 3_600, "ask");
  assert.equal((await doddy.start(minted)).status, 403);
  assert.equal((await doddy.undo(guest.body.token)).status, 403);
  assert.deepEqual(await links(doddy.store), []);
});

test("a link code works once, only until it expires, and only the newest one of an iPhone", async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  const second = (await doddy.signInDevice(PHONE(2), { inviteCode: "second-phone-code-1" })).body.token as string;

  // Used once: a second use, even by the same account after a conflict, is refused.
  await seedSwitch(doddy.store, ACCOUNT_2);
  const code = (await doddy.start(deviceToken)).body.linkCode as string;
  assert.equal((await doddy.link(account(ACCOUNT_2), code)).status, 409, "a conflict uses the code up too");
  const reused = await doddy.link(account(ACCOUNT), code);
  assert.equal(reused.status, 400);
  assert.equal(reused.body.error.code, "attempt_invalid");

  // A newer code replaces an older one of the same iPhone.
  const older = (await doddy.start(deviceToken)).body.linkCode as string;
  const newer = (await doddy.start(deviceToken)).body.linkCode as string;
  assert.equal((await doddy.link(account(ACCOUNT), older)).status, 400);

  // Expired: refused, and nothing linked.
  await doddy.store.db.query("UPDATE account_link_codes SET expires_at = $1", [Date.now() - 1]);
  assert.equal((await doddy.link(account(ACCOUNT), newer)).status, 400);
  assert.equal(await doddy.store.pruneAccountLinkCodes(Date.now()), 1, "the hourly sweep drops it");
  assert.deepEqual(await links(doddy.store), []);

  // Another iPhone's code links that iPhone, never the first one.
  assert.equal((await doddy.linkPhone(account(ACCOUNT), second)).status, 200);
  assert.deepEqual(await links(doddy.store), [{ subject: ACCOUNT, user_id: deviceUserId(KEY, PHONE(2)) }]);
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
});

test("within a day the iPhone takes its data back with its own device token, and the account keeps no way in", async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  const phoneUser = deviceUserId(KEY, PHONE(1));
  await seedSwitch(doddy.store, phoneUser);
  assert.equal((await doddy.linkPhone(account(ACCOUNT), deviceToken)).status, 200);
  const linkedAt = Number((await doddy.store.db.query<{ linked_at: string }>("SELECT linked_at FROM account_links")).rows[0]!.linked_at);
  // While linked, the account opened a browser session and linked a Google sign-in to the data; an older
  // browser session (from before the link) is the iPhone's own and stays.
  await doddy.store.db.query(
    `INSERT INTO web_sessions (session_id, user_id, token_hash, browser, os, created_at, last_seen_at, expires_at) VALUES
       ('since', $1, 'th-since', 'Safari', 'macOS', $2, $2, 9999999999999),
       ('before', $1, 'th-before', 'Safari', 'macOS', $3, $3, 9999999999999)`,
    [phoneUser, linkedAt + 1, linkedAt - 1],
  );
  await doddy.store.db.query("INSERT INTO web_identities (identity_id, user_id, provider, created_at) VALUES ($1, $2, 'google', $3)", [ACCOUNT_3, phoneUser, linkedAt + 2]);

  // An account's token can't undo, and neither can nothing at all.
  assert.equal((await doddy.undo(account(ACCOUNT))).status, 401);
  assert.equal((await doddy.undo(undefined)).status, 401);
  const undone = await doddy.undo(deviceToken);
  assert.equal(undone.status, 200);
  assert.deepEqual(undone.body, { linked: false });
  assert.deepEqual(await links(doddy.store), []);
  // A repeat (a lost answer) says the same.
  assert.deepEqual((await doddy.undo(deviceToken)).body, { linked: false });

  // The device token works again, on its own data; the account is its own, empty one.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
  assert.equal((await doddy.signInDevice(PHONE(1))).status, 200);
  assert.equal(await switchesOf(doddy.store, phoneUser), 1);
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", account(ACCOUNT))).status, 200);
  assert.equal(await switchesOf(doddy.store, ACCOUNT), 0);
  const sessions = (await doddy.store.db.query<{ session_id: string; revoked: boolean }>(
    "SELECT session_id, revoked_at IS NOT NULL AS revoked FROM web_sessions ORDER BY session_id",
  )).rows;
  assert.deepEqual(sessions, [{ session_id: "before", revoked: false }, { session_id: "since", revoked: true }]);
  assert.equal(Number((await doddy.store.db.query<{ n: string }>("SELECT count(*) AS n FROM web_identities")).rows[0]!.n), 0);
});

test("after a day the iPhone can't take its data back; the operator can, and the device works again", async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  assert.equal((await doddy.linkPhone(account(ACCOUNT), deviceToken)).status, 200);
  await doddy.store.db.query("UPDATE account_links SET linked_at = $1", [Date.now() - LINK_UNDO_WINDOW_MS - 60_000]);
  const late = await doddy.undo(deviceToken);
  assert.equal(late.status, 409);
  assert.equal(late.body.error.code, "account_conflict");
  assert.equal((await links(doddy.store)).length, 1, "still linked");

  // The operator's unlink (`npm run account:unlink`), by the account or by the data's user id.
  assert.equal(await doddy.store.unlinkAccount(ACCOUNT_2, Date.now()), null, "no such link: nothing changes");
  const ended = await doddy.store.unlinkAccount(deviceUserId(KEY, PHONE(1)), Date.now());
  assert.equal(ended?.subject, ACCOUNT);
  assert.deepEqual(await links(doddy.store), []);
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
  assert.equal((await doddy.linkPhone(account(ACCOUNT), deviceToken)).status, 200, "linking again works");
  assert.equal((await doddy.store.unlinkAccount(ACCOUNT, Date.now()))?.user_id, deviceUserId(KEY, PHONE(1)));
});

test("accounts are never merged: each conflict is refused with its reason, and nothing is linked", async () => {
  const doddy = await app();
  const owner = (await doddy.signInDevice(PHONE(1))).body.token as string;
  const second = (await doddy.signInDevice(PHONE(2), { inviteCode: "second-phone-code-1" })).body.token as string;
  assert.ok(owner && second);

  // An account with data of its own can't take over a phone's data.
  await seedSwitch(doddy.store, ACCOUNT_2);
  const hasData = await doddy.linkPhone(account(ACCOUNT_2), owner);
  assert.equal(hasData.status, 409);
  assert.equal(hasData.body.error.code, "account_conflict");
  assert.match(hasData.body.error.message, /never merged/);

  // One account per phone's data, and one phone's data per account.
  assert.equal((await doddy.linkPhone(account(ACCOUNT), owner)).status, 200);
  const subjectTaken = await doddy.linkPhone(account(ACCOUNT), second);
  assert.equal(subjectTaken.status, 409);
  assert.match(subjectTaken.body.error.message, /already has another iPhone's earlier data/);
  const userTaken = await doddy.linkPhone(account(ACCOUNT_3), owner);
  assert.equal(userTaken.status, 409);
  assert.match(userTaken.body.error.message, /already belongs to another Doddy account/);

  assert.deepEqual(await links(doddy.store), [{ subject: ACCOUNT, user_id: deviceUserId(KEY, PHONE(1)) }]);
  // The phone that wasn't linked keeps its own device sign-in.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", second)).status, 200);
});

test("linking needs a valid account and a code from a valid device session, each in its place", async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  const other = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const code = () => doddy.start(deviceToken).then((r) => r.body.linkCode as string);
  const cases: [string, string | undefined, () => Promise<unknown>, number][] = [
    ["no account", undefined, code, 401],
    ["a device token as the account", deviceToken, code, 401],
    ["an account signed by another key", account(ACCOUNT, {}, other.privateKey), code, 401],
    ["a password session", account(ACCOUNT, { amr: [{ method: "password" }] }), code, 401],
    ["an expired account token", account(ACCOUNT, { exp: Math.floor(Date.now() / 1000) - 1 }), code, 401],
    ["no code", account(ACCOUNT), async () => undefined, 400],
    ["an account token as the code", account(ACCOUNT), async () => account(ACCOUNT), 400],
  ];
  for (const [name, accountToken, makeCode, status] of cases) {
    const res = await doddy.link(accountToken, await makeCode());
    assert.equal(res.status, status, name);
  }
  // The code is asked for with the device's own token only.
  const starts: [string, string | undefined][] = [
    ["no token", undefined],
    ["an account token", account(ACCOUNT)],
    ["a forged device token", `${deviceToken.slice(0, -4)}AAAA`],
    ["an expired device token", new SignedSessionVerifier(KEY).mint(deviceUserId(KEY, PHONE(1)), new Date(Date.now() - 7_200_000), 3_600)],
  ];
  for (const [name, token] of starts) assert.equal((await doddy.start(token)).status, 401, name);
  assert.deepEqual(await links(doddy.store), []);
  // The device still works: nothing was linked.
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
});

test(`at most ${LINK_TRIES_PER_HOUR} link tries per account and ${LINK_CODES_PER_HOUR} codes per iPhone an hour`, async () => {
  const doddy = await app();
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  for (let i = 0; i < LINK_TRIES_PER_HOUR; i += 1) assert.equal((await doddy.link(account(ACCOUNT_2), MADE_UP_CODE)).status, 400);
  const limited = await doddy.link(account(ACCOUNT_2), MADE_UP_CODE);
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error.code, "rate_limited");

  for (let i = 0; i < LINK_CODES_PER_HOUR; i += 1) assert.equal((await doddy.start(deviceToken)).status, 200);
  assert.equal((await doddy.start(deviceToken)).status, 429);
  assert.equal((await doddy.undo(deviceToken)).status, 429, "undo tries count with the codes");
});

test("a server with no Supabase project says accounts aren't set up, and device sign-in is unchanged", async () => {
  const doddy = await app({ DODDY_AUTH_MODE: "signed" });
  const deviceToken = (await doddy.signInDevice(PHONE(1))).body.token as string;
  for (const res of [await doddy.start(deviceToken), await doddy.link(account(ACCOUNT), MADE_UP_CODE), await doddy.undo(deviceToken)]) {
    assert.equal(res.status, 503);
    assert.equal(res.body.error.code, "live_not_configured");
  }
  assert.equal((await doddy.call("GET", "/v1/tools/receipts", deviceToken)).status, 200);
});
