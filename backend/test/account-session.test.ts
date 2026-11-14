import assert from "node:assert/strict";
import { once } from "node:events";
import { generateKeyPairSync, type KeyObject, sign } from "node:crypto";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { accountSubjectOf } from "../src/accountLinks.js";
import { buildApp } from "../src/app.js";
import { type FetchJson, RevocableSessionVerifier, SignedSessionVerifier, SupabaseSessionVerifier, TokenFloors } from "../src/auth.js";
import { loadConfig } from "../src/config.js";
import { DeviceRegistry } from "../src/devices.js";
import { deviceUserId } from "../src/deviceSession.js";
import { createHandler } from "../src/http.js";
import { PurposeKeys } from "../src/signingKeys.js";
import { Store } from "../src/store.js";
import { DeviceListSchema } from "../src/web/contracts.js";

/**
 * `POST /v1/session/account` (decision 2026-11-12-one-token-per-server, the backend's half): the Doddy account's
 * Supabase token is taken once, and the backend answers with a session of its own for this iPhone. Every key,
 * token and id here is a fake test value.
 */

const KEY = Buffer.alloc(32, 7);
const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const ACCOUNT = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const ACCOUNT_2 = "6c1d9a8f-3b52-4d4e-8f70-123456789abc";
const PHONE = (n: number) => `1b4e28ba-2fa1-41d2-883f-${String(n).padStart(12, "0")}`;
const DAY_S = 86_400;

const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const other = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwks: FetchJson = async () => ({ keys: [{ ...ec.publicKey.export({ format: "jwk" }), kid: "k1", alg: "ES256", use: "sig" }] });
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
const claimsOf = (token: string) =>
  JSON.parse(Buffer.from(token.split(".")[1]!, "base64url").toString("utf8")) as { v: number; sub: string; iat: number; exp: number; dev?: string; acc?: number; scp?: string };

/** A Supabase access token signed with the test project's key (as `account-links.test.ts` makes them). */
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
    app_metadata: { provider: "google", providers: ["google"] },
    amr: [{ method: "oauth", timestamp: nowS - 10 }],
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
  DODDY_PUBLIC_BASE_URL: "https://doddy.onrender.com",
  DODDY_DB_PATH: ":memory:",
  DODDY_WEB_ORIGIN: "http://127.0.0.1:8787",
  MONID_API_KEY: "monid_live_abcdefgh123",
};

const servers: Server[] = [];
const closers: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const s of servers.splice(0)) s.close();
  for (const c of closers.splice(0)) await c();
});

/** The server as it runs, with the helpers a test needs. */
async function doddy(env: Record<string, string> = {}) {
  const built = await buildApp(loadConfig({ ...BASE_ENV, ...env }), { webSearch: null, supabaseFetchJson: jwks });
  built.server.listen(0, "127.0.0.1");
  await once(built.server, "listening");
  servers.push(built.server);
  closers.push(() => built.store.close());
  const base = `http://127.0.0.1:${(built.server.address() as AddressInfo).port}`;
  const store = built.store;
  const call = async (method: string, path: string, authorization?: string, body?: unknown, headers: Record<string, string> = {}) => {
    const h: Record<string, string> = { ...headers };
    if (authorization) h.authorization = `Bearer ${authorization}`;
    if (body !== undefined) h["content-type"] = "application/json";
    const res = await fetch(`${base}${path}`, { method, headers: h, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
    const text = await res.text();
    return { status: res.status, body: text ? (JSON.parse(text) as any) : null, text, headers: res.headers };
  };
  const exchange = (supabaseToken: string | undefined, deviceId: unknown = PHONE(1), headers: Record<string, string> = {}) =>
    call("POST", "/v1/session/account", supabaseToken, { deviceId }, headers);
  const signedIn = async (sub: string, deviceId = PHONE(1)) => {
    const res = await exchange(account(sub), deviceId);
    assert.equal(res.status, 200, res.text);
    return res.body as { token: string; expiresAt: string; access: "full"; deviceListId: string };
  };
  const rows = async () => (await store.db.query<Record<string, any>>("SELECT * FROM devices ORDER BY first_seen_at, device_id")).rows;
  const logbookOn = (token: string) => call("PUT", "/v1/web/logbook/state", token, { enabled: true });
  const logbook = async (token: string) => (await call("GET", "/v1/web/logbook", token)).body?.enabled as boolean | undefined;
  const devices = async (token: string) => {
    const res = await call("GET", "/v1/web/devices", token);
    assert.equal(res.status, 200, res.text);
    return DeviceListSchema.parse(res.body).devices;
  };
  const revoke = (token: string, id: string) => call("DELETE", `/v1/web/devices/${id}`, token);
  return { base, store, call, exchange, signedIn, rows, logbookOn, logbook, devices, revoke };
}

// ------------------------------------------------------------------ the exchange

test("the exchange takes the account's Supabase token and the iPhone's device id, and answers a session for this iPhone", async () => {
  const d = await doddy();
  const before = Math.floor(Date.now() / 1000);
  const res = await d.exchange(account(ACCOUNT), PHONE(1));
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(Object.keys(res.body).sort(), ["access", "deviceListId", "expiresAt", "token"]);
  assert.equal(res.body.access, "full");
  const token = res.body.token as string;
  assert.match(token, /^ds1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{51}$/, "the same ds1 shape the app accepts, with a key id and a MAC");
  assert.ok(token.length <= 2048);
  assert.equal(PurposeKeys.shapeOf(token.split(".")[2]!), "keyed", "signed with the session key's own id, never the master directly");

  const claims = claimsOf(token);
  assert.equal(claims.sub, ACCOUNT, "the session is the Doddy account's");
  assert.equal(claims.acc, 1, "it says it was made for an account");
  assert.ok(claims.iat >= before && claims.iat <= before + 5);
  assert.equal(claims.exp - claims.iat, 30 * DAY_S, "30 days");
  assert.equal(res.body.expiresAt, new Date(claims.exp * 1000).toISOString(), "the expiry the server wrote, nothing else");
  assert.equal(claims.scp, undefined);

  // The iPhone's stored row: the token names it, and the answer gives the id the list and a revoke use.
  const rows = await d.rows();
  assert.equal(rows.length, 1);
  assert.equal(claims.dev, rows[0]!.device_id);
  assert.equal(res.body.deviceListId, rows[0]!.device_id);
  assert.equal(rows[0]!.account_id, ACCOUNT);
  assert.equal(rows[0]!.revoked_at, null);
  assert.ok(Math.abs(Number(rows[0]!.first_seen_at) - Date.now()) < 5_000);

  // Ids and times only: no token, no device id, no hash of either.
  const dump = JSON.stringify(rows);
  assert.ok(!dump.includes(token) && !dump.includes(PHONE(1)) && !dump.includes(token.split(".")[2]!));
  assert.ok(!dump.includes(deviceUserId(KEY, PHONE(1))), "not the id the device-session path derives either");
});

test("a token that isn't the account's own Supabase token is refused the same plain way, and stores nothing", async () => {
  const d = await doddy();
  const nowS = Math.floor(Date.now() / 1000);
  const phoneSession = (await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(9) })).body.token as string;
  const owner = new SignedSessionVerifier(KEY).mint(ACCOUNT, new Date(), 3600);
  const session = await d.signedIn(ACCOUNT, PHONE(2));
  const kinds: Record<string, string | undefined> = {
    "no token": undefined,
    "not a token": "not-a-token-at-all",
    "another project's key": account(ACCOUNT, {}, other.privateKey),
    expired: account(ACCOUNT, { iat: nowS - 7200, exp: nowS - 10 }),
    "another audience": account(ACCOUNT, { aud: "someone-else" }),
    "another issuer": account(ACCOUNT, { iss: "https://zzzzzzzzzzzzzzzzzzzz.supabase.co/auth/v1" }),
    anonymous: account(ACCOUNT, { is_anonymous: true }),
    "a password sign-in": account(ACCOUNT, { amr: [{ method: "password" }] }),
    "another sign-in method": account(ACCOUNT, { app_metadata: { provider: "phone" } }),
    "an iPhone's device session": phoneSession,
    "an owner-minted token": owner,
    "an account session (a session is not exchanged for another)": session.token,
  };
  const rowsBefore = (await d.rows()).length;
  for (const [kind, token] of Object.entries(kinds)) {
    const res = await d.exchange(token, PHONE(3));
    assert.equal(res.status, 401, kind);
    assert.equal(res.body.error.code, "unauthenticated", kind);
    assert.equal(res.body.error.message, "Sign-in is required.", `${kind}: no detail about why`);
    assert.deepEqual(Object.keys(res.body.error).sort(), ["code", "correlationId", "message"], kind);
    assert.ok(!res.text.includes(PHONE(3)), kind);
  }
  assert.equal((await d.rows()).length, rowsBefore, "a refused exchange stores no iPhone");
});

test("a body that isn't exactly one device id is refused before anything is stored", async () => {
  const d = await doddy();
  const token = account(ACCOUNT);
  for (const body of [{}, { deviceId: "not-a-uuid" }, { deviceId: 5 }, { deviceId: PHONE(1), extra: true }, { deviceId: PHONE(1), inviteCode: "x" }, []]) {
    const res = await d.call("POST", "/v1/session/account", token, body);
    assert.equal(res.status, 400, JSON.stringify(body));
    assert.equal(res.body.error.code, "invalid_request");
  }
  assert.equal((await d.rows()).length, 0);
  assert.equal((await d.call("GET", "/v1/session/account", token)).status, 404, "only POST");
});

test("an upper-case device id is the same iPhone as its lower-case one", async () => {
  const d = await doddy();
  const first = await d.signedIn(ACCOUNT, PHONE(1));
  const again = await d.exchange(account(ACCOUNT), PHONE(1).toUpperCase());
  assert.equal(again.status, 200);
  assert.equal(again.body.deviceListId, first.deviceListId);
  assert.equal((await d.rows()).length, 1);
});

// ------------------------------------------------------------------ the session on everyday routes

test("the session is the same account as its Supabase token on everyday routes, and never another account", async () => {
  const d = await doddy();
  const a = await d.signedIn(ACCOUNT, PHONE(1));
  const b = await d.signedIn(ACCOUNT_2, PHONE(2));

  assert.equal((await d.logbookOn(a.token)).status, 200);
  assert.equal(await d.logbook(a.token), true, "the session reads what it wrote");
  assert.equal(await d.logbook(account(ACCOUNT)), true, "the account's Supabase token reads the same data");
  assert.equal(await d.logbook(account(ACCOUNT_2)), false, "another account does not");
  assert.equal(await d.logbook(b.token), false, "another account's session does not either");

  // What the Supabase token writes, the session reads.
  assert.equal((await d.call("PUT", "/v1/web/logbook/state", account(ACCOUNT_2), { enabled: true })).status, 200);
  assert.equal(await d.logbook(b.token), true);
  assert.equal(await d.logbook(a.token), true);

  // A session never reaches another account's iPhones: the list shows its own, a revoke of another's is the plain 404.
  const mine = await d.devices(a.token);
  assert.deepEqual(mine.map((x) => x.id), [a.deviceListId]);
  assert.equal((await d.revoke(a.token, b.deviceListId)).status, 404);
  assert.equal((await d.revoke(account(ACCOUNT), b.deviceListId)).status, 404);
  assert.equal(await d.logbook(b.token), true, "b's session still works");
  // Nor does a session of one account name another's row.
  const forged = new SignedSessionVerifier(KEY).mintAccount(ACCOUNT, b.deviceListId, new Date(), 3600);
  assert.equal((await d.call("GET", "/v1/web/logbook", forged)).status, 401, "a token that names another account's iPhone is refused");
});

test("both tokens work this release: the Supabase token still reaches every route, before and after a session exists", async () => {
  const d = await doddy();
  assert.equal((await d.call("GET", "/v1/tools/receipts", account(ACCOUNT))).status, 200, "an older build, no session");
  const session = await d.signedIn(ACCOUNT);
  assert.equal((await d.call("GET", "/v1/tools/receipts", account(ACCOUNT))).status, 200, "the Supabase token after the exchange");
  assert.equal((await d.call("GET", "/v1/tools/receipts", session.token)).status, 200, "the session");
  assert.equal((await d.call("GET", "/v1/web/devices", account(ACCOUNT))).status, 200);
  // The session ends; the Supabase token is not touched by it (this pull request stops accepting it nowhere).
  assert.equal((await d.revoke(session.token, session.deviceListId)).status, 200);
  assert.equal((await d.call("GET", "/v1/tools/receipts", session.token)).status, 401);
  assert.equal((await d.call("GET", "/v1/tools/receipts", account(ACCOUNT))).status, 200);
  // Ask Doddy takes either too.
  assert.notEqual((await d.call("POST", "/v1/assist", account(ACCOUNT), { question: "hi" })).status, 401);
});

test("an account that took over an iPhone's earlier data: the session works on that data, like its Supabase token, even when linked later", async () => {
  const d = await doddy();
  const phoneUser = deviceUserId(KEY, PHONE(1));
  const earlier = await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) });
  assert.equal(earlier.status, 200);
  const deviceToken = earlier.body.token as string;
  await d.store.setLogbookEnabled(phoneUser, true, Date.now());

  // A session made before the link starts on the account's own (empty) data ...
  const before = await d.signedIn(ACCOUNT, PHONE(1));
  assert.equal(await d.logbook(before.token), false);
  assert.equal(await d.logbook(account(ACCOUNT)), false);

  // ... and follows the account to the earlier data once it is linked, as the Supabase token does.
  const started = await d.call("POST", "/v1/account/link-device/start", deviceToken);
  assert.equal(started.status, 200);
  assert.equal((await d.call("POST", "/v1/account/link-device", account(ACCOUNT), { linkCode: started.body.linkCode })).status, 200);
  assert.equal(await d.logbook(account(ACCOUNT)), true);
  assert.equal(await d.logbook(before.token), true, "the same account, so the same data");
  assert.equal(await d.logbook(account(ACCOUNT_2)), false);

  // A session made after the link is the same.
  const after = await d.signedIn(ACCOUNT, PHONE(1));
  assert.equal(await d.logbook(after.token), true);
  // The earlier device token is retired by the link; the session is the way in now.
  assert.equal((await d.call("GET", "/v1/web/logbook", deviceToken)).status, 401);
  // Account sessions are listed for the account that owns the data.
  assert.ok((await d.devices(after.token)).some((x) => x.id === after.deviceListId && x.current));
});

// ------------------------------------------------------------------ the list, sign-out and revoke

test("the session's iPhone is in the account's device list, and only there", async () => {
  const d = await doddy();
  const first = await d.signedIn(ACCOUNT, PHONE(1));
  const second = await d.signedIn(ACCOUNT, PHONE(2));
  await d.signedIn(ACCOUNT_2, PHONE(3));

  const listed = await d.devices(first.token);
  assert.deepEqual(listed.map((x) => x.id).sort(), [first.deviceListId, second.deviceListId].sort());
  assert.equal(listed.find((x) => x.id === first.deviceListId)!.current, true);
  assert.equal(listed.find((x) => x.id === second.deviceListId)!.current, false);
  assert.ok(listed.every((x) => x.joined === null && x.revokedAt === null && x.label === null));
  // The Supabase token lists the same iPhones, none of them "this one".
  const viaAccount = await d.devices(account(ACCOUNT));
  assert.deepEqual(viaAccount.map((x) => x.id).sort(), listed.map((x) => x.id).sort());
  assert.ok(viaAccount.every((x) => !x.current));
  assert.deepEqual((await d.devices(account(ACCOUNT_2))).length, 1);
});

test("signing out is the existing revoke, called with the iPhone's own session: it ends at once, and the account's other iPhones go on", async () => {
  const d = await doddy();
  const mine = await d.signedIn(ACCOUNT, PHONE(1));
  const spare = await d.signedIn(ACCOUNT, PHONE(2));
  assert.equal((await d.call("GET", "/v1/tools/receipts", mine.token)).status, 200);

  const out = await d.revoke(mine.token, mine.deviceListId);
  assert.equal(out.status, 200, out.text);
  assert.equal(out.body.revoked, true);
  const stored = (await d.rows()).find((r) => r.device_id === mine.deviceListId)!;
  assert.equal(out.body.revokedAt, new Date(Number(stored.revoked_at)).toISOString(), "said only after the store has it");

  assert.equal((await d.call("GET", "/v1/tools/receipts", mine.token)).status, 401, "the very next request is refused");
  assert.equal((await d.call("PUT", "/v1/web/logbook/state", mine.token, { enabled: true })).status, 401);
  assert.equal((await d.call("GET", "/v1/tools/receipts", spare.token)).status, 200, "the account's other iPhone is not touched");
  const shown = (await d.devices(account(ACCOUNT))).find((x) => x.id === mine.deviceListId)!;
  assert.equal(shown.revokedAt, out.body.revokedAt);
  // A repeat answers the first moment.
  assert.equal((await d.revoke(spare.token, mine.deviceListId)).body.revokedAt, out.body.revokedAt);
  // A revoke writes no cut-off: other iPhones' sessions name their rows, so nothing else needs ending.
  assert.equal((await d.store.db.query("SELECT 1 FROM device_cutoffs")).rows.length, 0);
});

test("the way back after a revoke is a fresh exchange with a fresh Supabase token: a new row, and the old session stays dead", async () => {
  const d = await doddy();
  const first = await d.signedIn(ACCOUNT, PHONE(1));
  assert.equal((await d.revoke(first.token, first.deviceListId)).status, 200);
  assert.equal((await d.call("GET", "/v1/tools/receipts", first.token)).status, 401);

  // A session can't bring itself back: it is not a Supabase token.
  assert.equal((await d.exchange(first.token, PHONE(1))).status, 401);
  assert.equal((await d.rows()).length, 1);

  // The deliberate way: the account's own fresh token, from this iPhone.
  const again = await d.signedIn(ACCOUNT, PHONE(1));
  assert.notEqual(again.deviceListId, first.deviceListId, "a new row id: what named the old one stays dead");
  assert.equal((await d.call("GET", "/v1/tools/receipts", again.token)).status, 200);
  assert.equal((await d.call("GET", "/v1/tools/receipts", first.token)).status, 401, "the revoked session does not come back with it");
  assert.equal((await d.call("GET", "/v1/web/devices", first.token)).status, 401);
  const rows = await d.rows();
  assert.equal(rows.length, 1, "one iPhone, one row");
  assert.equal(rows[0]!.device_id, again.deviceListId);
  assert.equal(rows[0]!.revoked_at, null);
  const shown = await d.devices(account(ACCOUNT));
  assert.deepEqual(shown.map((x) => [x.id, x.revokedAt]), [[again.deviceListId, null]]);
});

test("a revoke ends the iPhone's account session only: the device-session path keeps its own rule (a revoked iPhone stays revoked there)", async () => {
  const d = await doddy();
  const owner = await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) });
  assert.equal(owner.status, 200);
  const deviceRow = (await d.rows())[0]!;
  assert.equal(deviceRow.account_id, null, "a device-session row belongs to no account");

  // The iPhone is revoked on the device-session path, as #485 does it.
  const revokedAt = Date.now() - 1_000;
  await d.store.db.query("UPDATE devices SET revoked_at = $2 WHERE device_id = $1", [deviceRow.device_id, revokedAt]);
  assert.equal((await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) })).status, 401, "refused");
  // A fresh exchange with the account's token works, and does not touch that row: the device-session path stays closed.
  const session = await d.signedIn(ACCOUNT, PHONE(1));
  assert.equal((await d.call("GET", "/v1/tools/receipts", session.token)).status, 200);
  const rows = await d.rows();
  assert.equal(rows.length, 2, "a row for the account session, and the device-session row as it was");
  assert.equal(Number(rows.find((r) => r.device_id === deviceRow.device_id)!.revoked_at), revokedAt);
  assert.equal((await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) })).status, 401, "still revoked there");
  // And the other way round: ending the account session leaves the device-session row alone.
  assert.equal((await d.revoke(session.token, session.deviceListId)).status, 200);
  assert.equal(Number((await d.rows()).find((r) => r.device_id === deviceRow.device_id)!.revoked_at), revokedAt);
});

// ------------------------------------------------------------------ rows

test("one iPhone exchanged twice is one row; another iPhone, and another account on the same iPhone, are rows of their own", async () => {
  const d = await doddy();
  const first = await d.signedIn(ACCOUNT, PHONE(1));
  const t0 = Number((await d.rows())[0]!.first_seen_at);
  const again = await d.signedIn(ACCOUNT, PHONE(1));
  assert.equal(again.deviceListId, first.deviceListId);
  assert.equal(claimsOf(again.token).dev, claimsOf(first.token).dev);
  assert.equal((await d.rows()).length, 1);
  assert.equal(Number((await d.rows())[0]!.first_seen_at), t0, "first seen stays");

  // Renewing is the same exchange: the new token is dated later, and the one before still runs until it expires.
  assert.ok(claimsOf(again.token).exp >= claimsOf(first.token).exp);
  assert.equal((await d.call("GET", "/v1/tools/receipts", first.token)).status, 200);
  assert.equal((await d.call("GET", "/v1/tools/receipts", again.token)).status, 200);

  const second = await d.signedIn(ACCOUNT, PHONE(2));
  assert.notEqual(second.deviceListId, first.deviceListId);
  assert.equal((await d.rows()).length, 2);

  // Someone else signing in to Doddy on the same iPhone is their row, and the first account's iPhone is not theirs to revoke.
  const theirs = await d.signedIn(ACCOUNT_2, PHONE(1));
  assert.notEqual(theirs.deviceListId, first.deviceListId);
  assert.equal((await d.rows()).length, 3);
  assert.deepEqual((await d.devices(theirs.token)).map((x) => x.id), [theirs.deviceListId]);
  assert.equal((await d.revoke(theirs.token, first.deviceListId)).status, 404);
  assert.equal((await d.call("GET", "/v1/tools/receipts", first.token)).status, 200);
  assert.equal((await d.revoke(theirs.token, theirs.deviceListId)).status, 200);
  assert.equal((await d.call("GET", "/v1/tools/receipts", first.token)).status, 200, "revoking one account's session on the iPhone ends only that one");
});

test("a session lasts 30 days from its exchange and is refused after, and another exchange renews it", async () => {
  const d = await doddy();
  const session = await d.signedIn(ACCOUNT, PHONE(1));
  const { iat, exp } = claimsOf(session.token);
  const registry = new DeviceRegistry(d.store);
  const verifier = new RevocableSessionVerifier(new SignedSessionVerifier(KEY), new TokenFloors(d.store), registry);
  const header = `Bearer ${session.token}`;
  const user = await verifier.verify(header, new Date((exp - 10) * 1000));
  assert.equal(user?.userId, ACCOUNT);
  assert.equal(user?.account, ACCOUNT);
  assert.equal(user?.deviceId, session.deviceListId);
  assert.equal(await verifier.verify(header, new Date((exp + 1) * 1000)), null, "expired");
  assert.equal(exp, iat + 30 * DAY_S);
  // A token dated in the future is not valid yet.
  assert.equal(await verifier.verify(header, new Date((iat - 120) * 1000)), null);
});

// ------------------------------------------------------------------ account deletion

test("deleting the account ends its sessions at once, and the Supabase user is owed a removal", async () => {
  const d = await doddy();
  const mine = await d.signedIn(ACCOUNT, PHONE(1));
  const spare = await d.signedIn(ACCOUNT, PHONE(2));
  const stranger = await d.signedIn(ACCOUNT_2, PHONE(3));
  await d.logbookOn(mine.token);

  // The iPhone deletes the account with its own session.
  const erased = await d.call("DELETE", "/v1/account", mine.token);
  assert.equal(erased.status, 200, erased.text);
  assert.equal(erased.body.deleted.logbook_state, 1);
  assert.equal((await d.call("GET", "/v1/tools/receipts", mine.token)).status, 401);
  assert.equal((await d.call("GET", "/v1/tools/receipts", spare.token)).status, 401, "the account's other iPhone too");
  assert.equal((await d.call("GET", "/v1/tools/receipts", account(ACCOUNT))).status, 401, "and a Supabase token dated before the deletion");
  assert.equal((await d.exchange(account(ACCOUNT), PHONE(1))).status, 401, "a token dated before the deletion can't be exchanged either");
  assert.equal((await d.rows()).filter((r) => r.account_id === ACCOUNT).length, 0, "the iPhones' rows go with the account");
  const owed = (await d.store.db.query<{ connection_id: string; provider: string }>("SELECT connection_id, provider FROM cleanups")).rows;
  assert.deepEqual(owed, [{ connection_id: ACCOUNT, provider: "supabase_auth" }], "the account's Supabase user is owed a removal, though a session (not a Supabase token) asked");
  // Another account is not touched.
  assert.equal((await d.call("GET", "/v1/tools/receipts", stranger.token)).status, 200);
  assert.equal((await d.devices(stranger.token)).length, 1);
});

test("deleting the account with the Supabase token ends the iPhones' sessions too", async () => {
  const d = await doddy();
  const mine = await d.signedIn(ACCOUNT, PHONE(1));
  assert.equal((await d.call("GET", "/v1/tools/receipts", mine.token)).status, 200);
  assert.equal((await d.call("DELETE", "/v1/account", account(ACCOUNT))).status, 200);
  assert.equal((await d.call("GET", "/v1/tools/receipts", mine.token)).status, 401);
  assert.equal((await d.rows()).length, 0);
  // Not even a session dated after the deletion: the row it names is gone.
  const later = new SignedSessionVerifier(KEY).mintAccount(ACCOUNT, mine.deviceListId, new Date(Date.now() + 5_000), 3600);
  assert.equal((await d.call("GET", "/v1/tools/receipts", later)).status, 401);
});

test("the hourly sweep drops an idle account-session row, revoked or not, and still keeps a revoked device-session row", async () => {
  const d = await doddy();
  const live = await d.signedIn(ACCOUNT, PHONE(1));
  const gone = await d.signedIn(ACCOUNT, PHONE(2));
  const recent = await d.signedIn(ACCOUNT, PHONE(3));
  await d.revoke(account(ACCOUNT), gone.deviceListId);
  await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(4) });
  const deviceRow = (await d.rows()).find((r) => r.account_id === null)!;
  await d.store.db.query("UPDATE devices SET revoked_at = $2 WHERE device_id = $1", [deviceRow.device_id, Date.now()]);
  const old = Date.now() - 200 * 86_400_000;
  await d.store.db.query("UPDATE devices SET last_seen_at = $1 WHERE device_id <> $2", [old, recent.deviceListId]);

  assert.equal(await d.store.pruneDevices(Date.now() - 180 * 86_400_000), 2, "the idle live row and the idle revoked account-session row");
  const left = (await d.rows()).map((r) => r.device_id).sort();
  assert.deepEqual(left, [recent.deviceListId, deviceRow.device_id].sort(), "a revoked device-session row is kept, so waiting never brings it back");
  assert.equal(left.includes(live.deviceListId), false);
});

// ------------------------------------------------------------------ what a session can't do

test("a session is not an iPhone's earlier device session: it starts no account link and takes none back", async () => {
  const d = await doddy();
  const session = await d.signedIn(ACCOUNT, PHONE(1));
  const started = await d.call("POST", "/v1/account/link-device/start", session.token);
  assert.equal(started.status, 401);
  assert.equal((await d.call("POST", "/v1/account/link-device/undo", session.token)).status, 401);
  assert.equal((await d.store.db.query("SELECT 1 FROM account_link_codes")).rows.length, 0);
});

test("a token that names a row the session doesn't own is refused: a device-session row, an unknown row", async () => {
  const d = await doddy();
  const device = await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) });
  const deviceRow = (await d.rows())[0]!.device_id as string;
  const signer = new SignedSessionVerifier(KEY);
  const mint = (dev: string, sub = ACCOUNT) => signer.mintAccount(sub, dev, new Date(), 3600);
  assert.equal((await d.call("GET", "/v1/tools/receipts", mint(deviceRow))).status, 401, "a device-session row is not an account session's");
  assert.equal((await d.call("GET", "/v1/tools/receipts", mint("00000000-0000-4000-8000-000000000042"))).status, 401, "no such row");
  assert.equal((await d.call("GET", "/v1/tools/receipts", device.body.token)).status, 200, "the device session itself is as it was");
});

// ------------------------------------------------------------------ limits

test("the exchange is limited per account and per address, counted before the token is trusted", async () => {
  const { AccountSessionIssuer, ACCOUNT_SESSION_LIMITS } = await import("../src/accountSession.js");
  assert.deepEqual({ ...ACCOUNT_SESSION_LIMITS }, { perClientPerHour: 20, perAccountPerHour: 20, maxDevicesPerAccount: 20 }, "the numbers the guest, invite and link routes use, and 20 iPhones");
  const store = await Store.memory();
  try {
    const registry = new DeviceRegistry(store);
    const floors = new TokenFloors(store);
    const supabase = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson: jwks });
    const issuer = new AccountSessionIssuer({ accounts: supabase, keys: KEY, identifierKey: KEY, store, floors, devices: registry, limits: { perClientPerHour: 3, perAccountPerHour: 2, maxDevicesPerAccount: 50 } });
    const now = new Date();
    const bearer = (t: string) => `Bearer ${t}`;
    // Per account: two succeed, the third is refused, whatever the address.
    assert.ok(await issuer.issue(bearer(account(ACCOUNT)), { deviceId: PHONE(1) }, now, "10.0.0.1"));
    assert.ok(await issuer.issue(bearer(account(ACCOUNT)), { deviceId: PHONE(2) }, now, "10.0.0.2"));
    await assert.rejects(issuer.issue(bearer(account(ACCOUNT)), { deviceId: PHONE(3) }, now, "10.0.0.3"), (e: any) => e.code === "rate_limited" && e.options.retryAfterSeconds === 3600);
    // Another account on its own: not limited by the first.
    assert.ok(await issuer.issue(bearer(account(ACCOUNT_2)), { deviceId: PHONE(4) }, now, "10.0.0.4"));
    // Per address: every try counts, bad tokens included, so guessing from one place runs out.
    for (let n = 0; n < 3; n++) await assert.rejects(issuer.issue(bearer("junk-token-not-real"), { deviceId: PHONE(5) }, now, "10.9.9.9"), (e: any) => e.code === "unauthenticated");
    await assert.rejects(issuer.issue(bearer(account(ACCOUNT_2)), { deviceId: PHONE(6) }, now, "10.9.9.9"), (e: any) => e.code === "rate_limited");
    // An IPv6 address counts by its /64, as the other sign-in routes do.
    for (let n = 0; n < 3; n++) await assert.rejects(issuer.issue(undefined, { deviceId: PHONE(5) }, now, `2001:db8:1:2:${n}::1`), (e: any) => e.code === "unauthenticated");
    await assert.rejects(issuer.issue(undefined, { deviceId: PHONE(5) }, now, "2001:db8:1:2:ffff::9"), (e: any) => e.code === "rate_limited");
    // The next hour counts afresh.
    const later = new Date(now.getTime() + 61 * 60_000);
    assert.ok(await issuer.issue(bearer(account(ACCOUNT, { iat: Math.floor(later.getTime() / 1000) - 10, exp: Math.floor(later.getTime() / 1000) + 3600 })), { deviceId: PHONE(1) }, later, "10.0.0.1"));
  } finally {
    await store.close();
  }
});

test("over HTTP a flood of exchanges ends in a 429 with a retry time, and nothing else is refused meanwhile", async () => {
  const d = await doddy();
  const token = account(ACCOUNT);
  let limited: Awaited<ReturnType<typeof d.exchange>> | null = null;
  for (let n = 1; n <= 25 && !limited; n++) {
    const res = await d.exchange(token, PHONE(1));
    if (res.status === 429) limited = res;
    else assert.equal(res.status, 200, res.text);
  }
  assert.ok(limited, "the 21st try inside the hour is refused");
  assert.equal(limited.body.error.code, "rate_limited");
  assert.equal(limited.headers.get("retry-after"), "3600");
  assert.equal((await d.call("GET", "/v1/tools/receipts", token)).status, 200, "everyday requests don't count against the exchange");
});

test("no account holds an unbounded number of iPhones: at the limit a new iPhone is refused, a known one still renews, and revoked ones are freed", async () => {
  const { AccountSessionIssuer } = await import("../src/accountSession.js");
  const store = await Store.memory();
  try {
    const registry = new DeviceRegistry(store);
    const issuer = new AccountSessionIssuer({
      accounts: new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson: jwks }),
      keys: KEY,
      identifierKey: KEY,
      store,
      floors: new TokenFloors(store),
      devices: registry,
      limits: { perClientPerHour: 1000, perAccountPerHour: 1000, maxDevicesPerAccount: 3 },
    });
    const now = new Date();
    const go = (sub: string, n: number) => issuer.issue(`Bearer ${account(sub)}`, { deviceId: PHONE(n) }, now, `10.1.0.${n}`);
    const a = await go(ACCOUNT, 1);
    await go(ACCOUNT, 2);
    await go(ACCOUNT, 3);
    await assert.rejects(go(ACCOUNT, 4), (e: any) => e.code === "quota_exceeded" && /as many iPhones as it allows/.test(e.message) && e.status === 429);
    assert.equal((await store.db.query("SELECT 1 FROM devices WHERE account_id = $1", [ACCOUNT])).rows.length, 3, "nothing stored for the refused one");
    assert.ok(await go(ACCOUNT, 2), "an iPhone the account already has still renews at the limit");
    assert.ok(await go(ACCOUNT_2, 4), "another account has its own room");

    // A revoked iPhone no longer takes a place: its row is cleared to make room, and its old session stays dead.
    await registry.revoke(ACCOUNT, a.deviceListId, now);
    const fourth = await go(ACCOUNT, 4);
    assert.ok(fourth.token);
    assert.equal((await store.db.query("SELECT 1 FROM devices WHERE account_id = $1", [ACCOUNT])).rows.length, 3);
    assert.equal(await store.deviceState(a.deviceListId), null, "the revoked row is gone; a token that names it is refused");
    await assert.rejects(go(ACCOUNT, 5), (e: any) => e.code === "quota_exceeded");
  } finally {
    await store.close();
  }
});

// ------------------------------------------------------------------ what is written and what is not

test("no token, key, device id or account id in a log line or an answer", async () => {
  const { AccountSessionIssuer } = await import("../src/accountSession.js");
  const store = await Store.memory();
  const logs: string[] = [];
  const log = (line: Record<string, unknown>) => logs.push(JSON.stringify(line));
  try {
    const floors = new TokenFloors(store);
    const registry = new DeviceRegistry(store, { log });
    const supabase = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson: jwks });
    const issuer = new AccountSessionIssuer({ accounts: supabase, keys: KEY, identifierKey: KEY, store, floors, devices: registry, log });
    const verifier = new RevocableSessionVerifier(new SignedSessionVerifier(KEY), floors, registry);
    const handler = createHandler({
      service: undefined as never,
      verifier,
      accountSessions: issuer,
      appReturnUrl: "doddy-dev://connected-apps/return",
      maxBodyBytes: 8 * 1024,
      log,
    });
    const server = createServer((req, res) => void handler(req, res));
    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    servers.push(server);
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const post = async (token: string, body: unknown) => {
      const res = await fetch(`${base}/v1/session/account`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(body) });
      return { status: res.status, text: await res.text() };
    };
    const good = account(ACCOUNT);
    const bad = account(ACCOUNT, {}, other.privateKey);
    const ok = await post(good, { deviceId: PHONE(1) });
    assert.equal(ok.status, 200);
    const issued = JSON.parse(ok.text) as { token: string; deviceListId: string };
    // The same iPhone again, after a revoke (the way back), and refusals of every kind.
    await registry.revoke(ACCOUNT, issued.deviceListId, new Date());
    assert.equal((await post(good, { deviceId: PHONE(1) })).status, 200);
    const refusals = [await post(bad, { deviceId: PHONE(1) }), await post(good, { deviceId: "nope" })];
    assert.deepEqual(refusals.map((r) => r.status), [401, 400]);

    const everything = [...logs, ...refusals.map((r) => r.text)].join("\n");
    const secrets = [good, bad, issued.token, issued.token.split(".")[2]!, KEY.toString("base64"), KEY.toString("hex"), ACCOUNT, PHONE(1), deviceUserId(KEY, PHONE(1)), issued.deviceListId];
    for (const secret of secrets) assert.ok(!everything.includes(secret), `a log line or an error answer holds ${secret.slice(0, 8)}…`);
    assert.ok(logs.some((l) => l.includes("account_session")), "the exchange says that it happened, and how");
    assert.ok(logs.every((l) => !/"(token|userId|deviceId|sub)"/.test(l)));
  } finally {
    await store.close();
  }
});

// ------------------------------------------------------------------ where the route exists

test("the route exists only where the server can check a Supabase token and sign a session", async () => {
  // Without Supabase sign-in: not found.
  const signedOnly = await doddy({ DODDY_AUTH_MODE: "signed" });
  assert.equal((await signedOnly.exchange(account(ACCOUNT))).status, 404);
  // Without a session key: not found, nothing stored.
  const noKey = await doddy({ DODDY_SESSION_SIGNING_KEY: "", DODDY_DEVICE_SIGNUP: "off" });
  assert.equal((await noKey.exchange(account(ACCOUNT))).status, 404);
  assert.equal((await noKey.rows()).length, 0);
  // Production loads no owner-token key (`signingKeys`). Since decision 2026-11-14-production-rules it does load the key of
  // account sessions, file links and the link proof (`accountKeys`), so the route is served there: `production-rules.test.ts`.
  const production = loadConfig({ ...BASE_ENV, DODDY_ENV: "production", DATABASE_URL: "postgres://doddy:doddy@db.example.test/doddy", DODDY_DEVICE_SIGNUP: "off" });
  assert.equal(production.signingKeys, null);
});

// ------------------------------------------------------------------ small reads

test("accountSubjectOf reads the account behind an account session, and nothing from a device session", async () => {
  const signer = new SignedSessionVerifier(KEY);
  const row = "00000000-0000-4000-8000-000000000042";
  assert.equal(accountSubjectOf(`Bearer ${signer.mintAccount(ACCOUNT, row, new Date(), 3600)}`), ACCOUNT);
  assert.equal(accountSubjectOf(`Bearer ${signer.mint(deviceUserId(KEY, PHONE(1)), new Date(), 3600, undefined, row)}`), null, "a device session names no account");
  assert.equal(accountSubjectOf(`Bearer ${account(ACCOUNT)}`), ACCOUNT, "a Supabase token still does");
  assert.equal(accountSubjectOf(undefined), null);
});

test("an account session's claims can't be mixed with a guest's, and need an iPhone", async () => {
  const signer = new SignedSessionVerifier(KEY);
  const row = "00000000-0000-4000-8000-000000000042";
  const now = new Date();
  const token = signer.mintAccount(ACCOUNT, row, now, 3600);
  assert.deepEqual(signer.verify(`Bearer ${token}`, now), { userId: ACCOUNT, deviceId: row, account: ACCOUNT });
  assert.throws(() => signer.mintAccount("not-a-uuid", row, now, 3600));
  assert.throws(() => signer.mintAccount(ACCOUNT, "not-a-uuid", now, 3600));
  // A device token minted the earlier way is byte for byte what it was, and carries no account claim.
  const device = signer.mint(deviceUserId(KEY, PHONE(1)), now, 3600);
  assert.equal(claimsOf(device).acc, undefined);
  assert.equal(signer.verify(`Bearer ${device}`, now)?.account, undefined);
});
