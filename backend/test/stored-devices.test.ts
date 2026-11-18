import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { afterEach, test } from "node:test";
import { RevocableSessionVerifier, SignedSessionVerifier, TokenFloors } from "../src/auth.js";
import { ConfigError, loadConfig } from "../src/config.js";
import { DAY_MS, DEVICE_JOIN_DAYS, DEVICE_KEPT_DAYS, DEVICE_SEEN_EVERY_MS, DeviceRegistry } from "../src/devices.js";
import { DeviceSessionIssuer, deviceUserId } from "../src/deviceSession.js";
import { SCHEMA_SQL, Store } from "../src/store.js";
import { DeviceListSchema } from "../src/web/contracts.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * Stored iPhones, a list and a revoke, and joins that expire and end on unlink (decision
 * 2026-11-12-account-and-device-tokens, part c). Every key, token and id here is a fake test value.
 */

const KEY = Buffer.alloc(32, 9);
const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const HOUR = 3_600_000;
const SECOND_PHONE_ACCOUNT = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const GOOGLE = SECOND_PHONE_ACCOUNT;
const APPLE = "7d1e9a0b-3c52-4d6e-8f70-123456789abc";
const OTHER_ACCOUNT = "9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d";
const OTHER_IDENTITY = OTHER_ACCOUNT;

/** Device ids as the app makes them: a UUID per iPhone. */
const phone = (n: number) => `${String(n).repeat(8)}-${String(n).repeat(4)}-4${String(n).repeat(3)}-8${String(n).repeat(3)}-${String(n).repeat(12)}`;
const OWNER = phone(1);
const SECOND = phone(2);
const THIRD = phone(3);
const FOURTH = phone(4);
const userIdOf = (deviceId: string) => deviceUserId(KEY, deviceId);
const claims = (token: string) => JSON.parse(Buffer.from(token.split(".")[1]!, "base64url").toString("utf8")) as { sub: string; iat: number; exp: number; scp?: string; dev?: string };

let rigs: WebRig[] = [];
let stores: Store[] = [];
afterEach(async () => {
  for (const r of rigs) await r.close();
  for (const s of stores) await s.close();
  rigs = [];
  stores = [];
});

/** The server as it runs: stored iPhones, Apple and Google sign-in (against nothing: the tests link by hand), the owner is the first iPhone. */
async function rig(o: { joinDays?: number } = {}): Promise<WebRig> {
  const r = await startWeb({
    devices: KEY,
    storedDevices: o.joinDays === undefined ? {} : { joinDays: o.joinDays },
    social: { projectUrl: PROJECT, postJson: async () => ({ status: 500, body: {} }), fetchJson: async () => ({ keys: [] }) },
  });
  rigs.push(r);
  return r;
}

async function signIn(r: WebRig, deviceId: string) {
  return r.call("POST", "/v1/session/device", { body: { deviceId } });
}
async function token(r: WebRig, deviceId: string): Promise<string> {
  const res = await signIn(r, deviceId);
  assert.equal(res.status, 200, res.text);
  return res.body.token as string;
}

/** A web account with a Google sign-in, and an iPhone that joined it with that sign-in. */
async function webAccount(r: WebRig, account = GOOGLE, identity = GOOGLE) {
  await r.store.createWebAccount({ userId: account, identityId: identity, provider: "google", now: r.clock.ms });
}
async function join(r: WebRig, deviceId: string, account = GOOGLE, identity: string | null = GOOGLE, provider = "google") {
  await r.store.setDeviceJoin(userIdOf(deviceId), account, provider, r.clock.ms, identity);
}

const devicesOf = async (r: WebRig, bearer: string) => {
  const res = await r.call("GET", "/v1/web/devices", { token: bearer });
  assert.equal(res.status, 200, res.text);
  return DeviceListSchema.parse(res.body).devices;
};
const revoke = (r: WebRig, bearer: string, id: string) => r.call("DELETE", `/v1/web/devices/${id}`, { token: bearer });
const rowOf = async (r: WebRig, deviceId: string) =>
  (await r.store.db.query<{ device_id: string; first_seen_at: number; last_seen_at: number; revoked_at: number | null }>("SELECT * FROM devices WHERE device_user_id = $1", [userIdOf(deviceId)])).rows[0];
const asks = (r: WebRig, bearer: string) => r.call("GET", "/v1/web/identities", { token: bearer });

// ------------------------------------------------------------------ rows

test("a sign-in stores the iPhone: its user id, first and last seen, and the token names its row", async () => {
  const r = await rig();
  const t0 = r.clock.ms;
  const owner = await token(r, OWNER);
  const row = (await rowOf(r, OWNER))!;
  assert.equal(row.first_seen_at, t0);
  assert.equal(row.last_seen_at, t0);
  assert.equal(row.revoked_at, null);
  assert.match(row.device_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(claims(owner).dev, row.device_id, "a signed claim of the token says which row it belongs to");
  assert.equal(claims(owner).sub, userIdOf(OWNER));

  // Signing in again later is the same iPhone: the same row, first seen kept, last seen moved.
  r.clock.advance(2 * HOUR);
  const again = await token(r, OWNER);
  const later = (await rowOf(r, OWNER))!;
  assert.equal(later.device_id, row.device_id);
  assert.equal(later.first_seen_at, t0);
  assert.equal(later.last_seen_at, t0 + 2 * HOUR);
  assert.equal(claims(again).dev, row.device_id);
  assert.equal((await r.store.db.query("SELECT 1 FROM devices")).rows.length, 1);

  // No content: the row holds ids and times, never the token, the device id or a hash of either.
  const dump = JSON.stringify((await r.store.db.query("SELECT * FROM devices")).rows);
  for (const secret of [owner, again, OWNER, createHash("sha256").update(OWNER).digest("hex")]) assert.ok(!dump.includes(secret));
});

test("a sign-in that is not made stores nothing", async () => {
  const r = await rig();
  // Nothing is stored for a request that is not a device sign-in at all.
  assert.equal((await r.call("POST", "/v1/session/device", { body: { deviceId: "not-a-device" } })).status, 400);
  assert.equal((await r.store.db.query("SELECT 1 FROM devices")).rows.length, 0);
});

test("last seen is written at most about once an hour, not on every request", async () => {
  const r = await rig();
  const t0 = r.clock.ms;
  const owner = await token(r, OWNER);
  const writes: string[] = [];
  const query = r.store.db.query.bind(r.store.db) as typeof r.store.db.query;
  r.store.db.query = (async (sql: string, params?: readonly unknown[]) => {
    if (/UPDATE devices SET last_seen_at/i.test(sql)) writes.push(sql);
    return query(sql, params);
  }) as typeof r.store.db.query;

  for (let minute = 5; minute <= 55; minute += 5) {
    r.clock.ms = t0 + minute * 60_000;
    assert.equal((await asks(r, owner)).status, 200);
  }
  assert.equal(writes.length, 0, "eleven requests inside the hour write nothing");
  assert.equal((await rowOf(r, OWNER))!.last_seen_at, t0);

  r.clock.ms = t0 + DEVICE_SEEN_EVERY_MS + 60_000;
  assert.equal((await asks(r, owner)).status, 200);
  assert.equal(writes.length, 1, "the first request after the hour writes once");
  assert.equal((await rowOf(r, OWNER))!.last_seen_at, t0 + DEVICE_SEEN_EVERY_MS + 60_000);
  for (let n = 1; n <= 5; n++) {
    r.clock.advance(n * 60_000);
    await asks(r, owner);
  }
  assert.equal(writes.length, 1, "and not again for another hour");
});

// ------------------------------------------------------------------ the list

/** Account A is the owner's iPhone. Account B is a web account with two iPhones that joined it. */
async function twoAccounts(r: WebRig) {
  const owner = await token(r, OWNER);
  await webAccount(r);
  await join(r, SECOND);
  await join(r, THIRD);
  const second = await token(r, SECOND);
  const third = await token(r, THIRD);
  assert.equal(claims(second).sub, GOOGLE, "the joined iPhone signs in to the web account");
  return { owner, second, third };
}

test("the list shows only the account's own iPhones, with the one asking marked and how each joined", async () => {
  const r = await rig();
  const { owner, second, third } = await twoAccounts(r);

  const ownerSees = await devicesOf(r, owner);
  assert.equal(ownerSees.length, 1);
  assert.equal(ownerSees[0]!.current, true);
  assert.equal(ownerSees[0]!.joined, null, "its own account");
  assert.equal(ownerSees[0]!.revokedAt, null);
  assert.equal(ownerSees[0]!.label, null, "the app sends no name, so there is none");

  const secondSees = await devicesOf(r, second);
  assert.equal(secondSees.length, 2, "the account's two iPhones, not the owner's");
  assert.equal(secondSees.filter((d) => d.current).length, 1);
  assert.equal(secondSees.find((d) => d.current)!.id, claims(second).dev);
  assert.equal(secondSees.find((d) => d.id === claims(third).dev)!.current, false);
  for (const d of secondSees) {
    assert.equal(d.joined?.provider, "google");
    assert.equal(d.joined?.since, new Date(r.clock.ms).toISOString());
    assert.equal(d.joined?.expiresAt, new Date(r.clock.ms + DEVICE_JOIN_DAYS * DAY_MS).toISOString());
  }
  const ids = new Set([...ownerSees, ...secondSees].map((d) => d.id));
  assert.equal(ids.size, 3, "three iPhones, three rows");

  // A browser signed in to the web account sees the same two, and none is "this one".
  const cookie = await r.signIn(await r.code(second));
  const web = DeviceListSchema.parse((await r.call("GET", "/v1/web/devices", { cookie })).body).devices;
  assert.deepEqual(web.map((d) => d.id).sort(), secondSees.map((d) => d.id).sort());
  assert.ok(web.every((d) => !d.current));
});

test("the list says nothing without a session, for a guest, or for an unknown method", async () => {
  const r = await rig();
  await token(r, OWNER);
  const guest = await token(r, FOURTH);
  assert.equal(claims(guest).scp, "ask");
  assert.equal((await r.call("GET", "/v1/web/devices")).status, 401);
  assert.notEqual((await r.call("GET", "/v1/web/devices", { token: guest })).status, 200, "a guest has Ask Doddy only");
  assert.equal((await r.call("POST", "/v1/web/devices", { token: guest, body: {} })).status, 404);
});

// ------------------------------------------------------------------ revoking

test("a revoke ends that iPhone's tokens at once, leaves the others, and says so only once it is stored", async () => {
  const r = await rig();
  const { owner, second, third } = await twoAccounts(r);
  const thirdId = claims(third).dev!;
  assert.equal((await asks(r, third)).status, 200);

  const done = await revoke(r, second, thirdId);
  assert.equal(done.status, 200, done.text);
  assert.equal(done.body.revoked, true);
  assert.equal(done.body.revokedAt, new Date(r.clock.ms).toISOString());
  assert.notEqual((await rowOf(r, THIRD))!.revoked_at, null, "what the answer says is what is stored");

  // The very next request, same millisecond: that iPhone's token is dead, and the others still work.
  const refused = await asks(r, third);
  assert.equal(refused.status, 401);
  assert.equal(refused.body.error.code, "unauthenticated");
  assert.equal((await asks(r, second)).status, 200);
  assert.equal((await asks(r, owner)).status, 200);

  // It can't sign in by itself again, and says why in words.
  const back = await signIn(r, THIRD);
  assert.equal(back.status, 401);
  assert.match(back.body.error.message, /removed/i);
  assert.equal(back.body.token, undefined);

  // The list keeps it, marked.
  const listed = await devicesOf(r, second);
  assert.equal(listed.length, 2);
  assert.equal(listed.find((d) => d.id === thirdId)!.revokedAt, new Date(r.clock.ms).toISOString());
  assert.equal(listed.filter((d) => d.revokedAt === null).length, 1);
});

test("revoking twice is fine and the second answer is the first one", async () => {
  const r = await rig();
  const { second, third } = await twoAccounts(r);
  const id = claims(third).dev!;
  const first = await revoke(r, second, id);
  r.clock.advance(5_000);
  const repeat = await revoke(r, second, id);
  assert.equal(repeat.status, 200);
  assert.deepEqual(repeat.body, first.body, "the moment of the first revoke, not a new one");
  assert.equal((await asks(r, third)).status, 401);
});

test("an iPhone may revoke itself, and a browser signed in to the account may revoke one", async () => {
  const r = await rig();
  const { second, third } = await twoAccounts(r);
  const cookie = await r.signIn(await r.code(second));
  const byBrowser = await r.call("DELETE", `/v1/web/devices/${claims(third).dev}`, { cookie, browser: true });
  assert.equal(byBrowser.status, 200, byBrowser.text);
  assert.equal((await asks(r, third)).status, 401);
  const self = await revoke(r, second, claims(second).dev!);
  assert.equal(self.status, 200);
  assert.equal((await asks(r, second)).status, 401, "its own revoke ends its own token too");
});

test("an unknown or foreign id is a plain 404 that changes nothing, and says the same for both", async () => {
  const r = await rig();
  const { owner, second, third } = await twoAccounts(r);
  const foreign = claims(owner).dev!;
  const unknown = "00000000-0000-4000-8000-000000000000";
  const a = await revoke(r, second, foreign);
  const b = await revoke(r, second, unknown);
  assert.equal(a.status, 404);
  assert.equal(b.status, 404);
  assert.equal(a.body.error.code, "not_found");
  assert.equal(a.body.error.message, b.body.error.message, "no detail tells a foreign id from an unknown one");
  assert.deepEqual(Object.keys(a.body.error).sort(), Object.keys(b.body.error).sort());
  assert.equal((await r.call("DELETE", "/v1/web/devices/not-an-id", { token: second })).status, 404);
  assert.equal((await rowOf(r, OWNER))!.revoked_at, null, "the owner's iPhone is untouched");
  assert.equal((await asks(r, owner)).status, 200);
  // The other way round: the owner can't touch the account's iPhones.
  assert.equal((await revoke(r, owner, claims(third).dev!)).status, 404);
  assert.equal((await asks(r, third)).status, 200);
  // And a browser of another account sees none of them either.
  const other = await r.signIn(await r.code(owner));
  assert.equal((await r.call("DELETE", `/v1/web/devices/${claims(third).dev}`, { cookie: other, browser: true })).status, 404);
});

test("a revoke the store did not confirm is not reported as done", async () => {
  const r = await rig();
  const { second, third } = await twoAccounts(r);
  const id = claims(third).dev!;
  const real = r.store.revokeDevice.bind(r.store);
  r.store.revokeDevice = async () => {
    throw new Error("database unreachable");
  };
  const failed = await revoke(r, second, id);
  assert.ok(failed.status >= 500, failed.text);
  assert.equal(failed.body.revoked, undefined);
  assert.equal((await rowOf(r, THIRD))!.revoked_at, null);
  assert.equal((await asks(r, third)).status, 200, "nothing was ended");
  r.store.revokeDevice = real;
  assert.equal((await revoke(r, second, id)).status, 200);
});

test("a revoked iPhone stays revoked: no automatic sign-in, no join, no renewal brings it back", async () => {
  const r = await rig();
  const { second, third } = await twoAccounts(r);
  await revoke(r, second, claims(third).dev!);
  r.clock.advance(60 * DAY_MS);
  assert.equal((await signIn(r, THIRD)).status, 401);
  // Its tokens can't start a join either: the join routes need a working session.
  assert.equal((await r.call("POST", "/v1/web/oauth/join-tickets", { token: third, body: { provider: "google" } })).status, 401);
  assert.notEqual((await rowOf(r, THIRD))!.revoked_at, null, "the row says revoked after all that");
});

test("a token that names an iPhone the database no longer has is refused, and signing in again makes a new row", async () => {
  const r = await rig();
  const owner = await token(r, OWNER);
  const old = claims(owner).dev;
  await r.store.db.query("DELETE FROM devices");
  assert.equal((await asks(r, owner)).status, 401, "a database that lost its rows (restored, replaced) does not vouch for old tokens");
  const again = await token(r, OWNER);
  assert.notEqual(claims(again).dev, old);
  assert.equal((await asks(r, again)).status, 200);
  assert.equal((await devicesOf(r, again)).length, 1);
});

test("the sign-in's own write refuses a revoked iPhone, so a revoke landing between the check and the write still holds", async () => {
  const r = await rig();
  await token(r, OWNER);
  const { second } = await twoAccounts(r);
  const row = (await rowOf(r, SECOND))!;
  const lastSeen = row.last_seen_at;
  assert.equal((await revoke(r, second, row.device_id)).status, 200);
  r.clock.advance(5 * HOUR);
  assert.equal(await r.store.registerDevice(userIdOf(SECOND), r.clock.ms, "00000000-0000-4000-8000-0000000000aa"), null, "the write itself says no");
  assert.equal((await rowOf(r, SECOND))!.last_seen_at, lastSeen, "and changes nothing");
  assert.equal(await r.store.isDeviceRevoked(userIdOf(SECOND)), true);
});

test("a store that can't be read answers 'can't check', never a 401 that sends the app round in a loop", async () => {
  const r = await rig();
  const owner = await token(r, OWNER);
  // Forget what is cached, then make the lookup fail.
  r.clock.advance(5 * 60_000);
  r.store.deviceState = async () => {
    throw new Error("database unreachable");
  };
  const res = await asks(r, owner);
  assert.equal(res.status, 502);
  assert.equal(res.body.error.code, "provider_unavailable");
});

// ------------------------------------------------------------------ joins expire

test("a join expires after 90 days and the iPhone goes back to its own account", async () => {
  const r = await rig();
  await token(r, OWNER);
  await webAccount(r);
  await join(r, SECOND);
  const joinedAt = r.clock.ms;
  r.clock.ms = joinedAt + 80 * DAY_MS;
  const session = await token(r, SECOND);
  assert.equal(claims(session).sub, GOOGLE);
  assert.equal((await asks(r, session)).status, 200);

  r.clock.ms = joinedAt + 90 * DAY_MS - 1;
  assert.equal((await asks(r, session)).status, 200, "still the last millisecond of day 90");
  r.clock.ms = joinedAt + 90 * DAY_MS + 1;
  const refused = await asks(r, session);
  assert.equal(refused.status, 401, "the account's token of an iPhone whose join ended is refused like a revoked one");

  // The app signs in again by itself: its own account, as after Leave. Nothing is lost on either side.
  const own = await signIn(r, SECOND);
  assert.equal(own.status, 200);
  assert.equal(own.body.access, "ask");
  assert.equal(claims(own.body.token).sub, userIdOf(SECOND));
  assert.equal(claims(own.body.token).dev, claims(session).dev, "the same iPhone, the same row");
  const deviceAccount = await r.call("POST", "/v1/web/device-account", { token: own.body.token, body: { deviceId: SECOND } });
  assert.deepEqual(deviceAccount.body, { joined: null });

  // The account no longer lists it, and the join is not valid any more.
  assert.deepEqual(await r.registry!.list(GOOGLE, null, new Date(r.clock.ms)), []);
  assert.equal(await r.store.deviceJoin(userIdOf(SECOND), r.clock.ms - DEVICE_JOIN_DAYS * DAY_MS), null);
});

test("the number of days is DODDY_DEVICE_JOIN_DAYS", async () => {
  const r = await rig({ joinDays: 30 });
  await token(r, OWNER);
  await webAccount(r);
  await join(r, SECOND);
  const start = r.clock.ms;
  const session = await token(r, SECOND);
  const listed = await devicesOf(r, session);
  assert.equal(listed[0]!.joined?.expiresAt, new Date(start + 30 * DAY_MS).toISOString());
  r.clock.ms = start + 29 * DAY_MS;
  // (the token itself lives 30 days: it is the join, not the token, that ends at 30)
  assert.equal((await asks(r, session)).status, 200);
  r.clock.ms = start + 30 * DAY_MS + 1;
  assert.equal((await asks(r, session)).status, 401);
});

test("signing in again with the same Apple or Google renews the join, and says when it ends now", async () => {
  const r = await rig();
  await token(r, OWNER);
  await webAccount(r);
  await join(r, SECOND);
  const joinedAt = r.clock.ms;
  r.clock.ms = joinedAt + 80 * DAY_MS;
  const session = await token(r, SECOND);

  // The sheet again with the same Google sign-in: a fresh one-time code, redeemed by this iPhone's session.
  const code = "A".repeat(43);
  await r.store.createPendingLink({
    codeHash: createHash("sha256").update(`doddy-web-oauth:v1:join:${code}`).digest("hex"),
    userId: claims(session).sub,
    identityId: GOOGLE,
    provider: "google",
    now: r.clock.ms,
    ttlMs: 300_000,
    intent: "join",
  });
  const renewed = await r.call("POST", "/v1/web/oauth/join", { token: session, body: { code, deviceId: SECOND } });
  assert.equal(renewed.status, 200, renewed.text);
  assert.deepEqual(renewed.body, { result: "joined", provider: "google" });

  const where = await r.call("POST", "/v1/web/device-account", { token: session, body: { deviceId: SECOND } });
  assert.equal(where.body.joined.provider, "google");
  assert.equal(where.body.joined.since, new Date(joinedAt).toISOString(), "it still says since the first join");
  assert.equal(where.body.joined.expiresAt, new Date(r.clock.ms + 90 * DAY_MS).toISOString());

  r.clock.ms = joinedAt + 91 * DAY_MS;
  assert.equal((await asks(r, session)).status, 200, "past the first 90 days, inside the renewed ones");
  r.clock.ms = joinedAt + 80 * DAY_MS + 90 * DAY_MS + 1;
  assert.equal((await asks(r, session)).status, 401);
});

test("after a join has ended the same sign-in joins again, and a sign-in that was unlinked can't", async () => {
  const r = await rig();
  await token(r, OWNER);
  await webAccount(r);
  await join(r, SECOND);
  r.clock.advance(91 * DAY_MS);
  const own = await token(r, SECOND);
  const joinWith = async (code: string, identity: string) => {
    await r.store.createPendingLink({
      codeHash: createHash("sha256").update(`doddy-web-oauth:v1:join:${code}`).digest("hex"),
      userId: userIdOf(SECOND),
      identityId: identity,
      provider: "google",
      now: r.clock.ms,
      ttlMs: 300_000,
      intent: "join",
    });
    return r.call("POST", "/v1/web/oauth/join", { token: own, body: { code, deviceId: SECOND } });
  };
  assert.equal((await joinWith("B".repeat(43), GOOGLE)).body.result, "joined");
  const joined = await token(r, SECOND);
  assert.equal(claims(joined).sub, GOOGLE);

  // The person unlinks that Google sign-in: this iPhone's join goes with it, and a sheet with it can't bring it back.
  assert.equal((await r.call("DELETE", `/v1/web/identities/${GOOGLE}`, { token: joined })).status, 200);
  assert.equal((await asks(r, joined)).status, 401);
  const ownAgain = await token(r, SECOND);
  assert.equal(claims(ownAgain).sub, userIdOf(SECOND));
  const sheet = async (code: string) => {
    await r.store.createPendingLink({
      codeHash: createHash("sha256").update(`doddy-web-oauth:v1:join:${code}`).digest("hex"),
      userId: userIdOf(SECOND),
      identityId: GOOGLE,
      provider: "google",
      now: r.clock.ms,
      ttlMs: 300_000,
      intent: "join",
    });
    return r.call("POST", "/v1/web/oauth/join", { token: ownAgain, body: { code, deviceId: SECOND } });
  };
  assert.equal((await sheet("C".repeat(43))).status, 404, "that sign-in is linked to no account now, so there is nothing to join");
  assert.equal(await r.store.deviceJoin(userIdOf(SECOND)), null);
});

// ------------------------------------------------------------------ unlinking ends joins

test("unlinking a sign-in ends every join made with it, at once, and only those", async () => {
  const r = await rig();
  const owner = await token(r, OWNER);
  await webAccount(r);
  await r.store.linkWebIdentity(APPLE, GOOGLE, "apple", r.clock.ms);
  await join(r, SECOND, GOOGLE, GOOGLE, "google");
  await join(r, THIRD, GOOGLE, GOOGLE, "google");
  await join(r, FOURTH, GOOGLE, APPLE, "apple");
  const second = await token(r, SECOND);
  const third = await token(r, THIRD);
  const fourth = await token(r, FOURTH);
  for (const t of [second, third, fourth]) assert.equal(claims(t).sub, GOOGLE);
  assert.equal((await devicesOf(r, fourth)).length, 3);

  const unlinked = await r.call("DELETE", `/v1/web/identities/${GOOGLE}`, { token: fourth });
  assert.equal(unlinked.status, 200, unlinked.text);
  assert.deepEqual(unlinked.body, { unlinked: true });

  assert.equal((await asks(r, second)).status, 401, "joined with Google: ended");
  assert.equal((await asks(r, third)).status, 401, "joined with Google: ended");
  assert.equal((await asks(r, fourth)).status, 200, "joined with Apple: untouched");
  assert.equal((await asks(r, owner)).status, 200);
  const left = await devicesOf(r, fourth);
  assert.deepEqual(left.map((d) => d.id), [claims(fourth).dev]);
  assert.equal(left[0]!.joined?.provider, "apple");

  // The two iPhones fall back to their own accounts at their next sign-in, and the rows stay theirs.
  const own = await signIn(r, SECOND);
  assert.equal(claims(own.body.token).sub, userIdOf(SECOND));
  assert.equal(await r.store.deviceJoin(userIdOf(SECOND)), null);
  assert.equal(await r.store.deviceJoin(userIdOf(THIRD)), null);
  assert.notEqual(await r.store.deviceJoin(userIdOf(FOURTH)), null);
  assert.equal((await r.store.db.query("SELECT 1 FROM devices")).rows.length, 4, "no iPhone row was deleted");
});

test("a join from before iPhones were stored (no sign-in recorded) ends with a sign-in of the same kind", async () => {
  const r = await rig();
  await webAccount(r);
  await r.store.linkWebIdentity(APPLE, GOOGLE, "apple", r.clock.ms);
  // Joins as the earlier version wrote them: no identity, and a provider.
  await r.store.db.query("INSERT INTO device_joins (device_user_id, user_id, provider, created_at, renewed_at) VALUES ($1, $2, 'google', 1, $3)", [userIdOf(SECOND), GOOGLE, r.clock.ms]);
  await r.store.db.query("INSERT INTO device_joins (device_user_id, user_id, provider, created_at, renewed_at) VALUES ($1, $2, 'apple', 1, $3)", [userIdOf(THIRD), GOOGLE, r.clock.ms]);
  const second = await token(r, SECOND);
  const third = await token(r, THIRD);
  assert.equal((await r.call("DELETE", `/v1/web/identities/${GOOGLE}`, { token: third })).status, 200);
  assert.equal((await asks(r, second)).status, 401, "its Google join ended");
  assert.equal((await asks(r, third)).status, 200, "its Apple join did not");
});

test("unlinking a sign-in that is not the account's changes nothing", async () => {
  const r = await rig();
  await token(r, OWNER);
  await webAccount(r);
  await webAccount(r, OTHER_ACCOUNT, OTHER_IDENTITY);
  await join(r, SECOND, OTHER_ACCOUNT, OTHER_IDENTITY);
  await join(r, THIRD);
  const other = await token(r, SECOND);
  const mine = await token(r, THIRD);
  assert.equal(claims(other).sub, OTHER_ACCOUNT);
  assert.equal(claims(mine).sub, GOOGLE);
  assert.equal((await r.call("DELETE", `/v1/web/identities/${OTHER_IDENTITY}`, { token: mine })).status, 404);
  assert.equal((await asks(r, other)).status, 200, "the other account's iPhone keeps its join");
  assert.equal((await asks(r, mine)).status, 200);
});

// ------------------------------------------------------------------ a version that stored nothing

function issuerFor(store: Store, registry: DeviceRegistry | null, joinMs = DEVICE_JOIN_DAYS * DAY_MS) {
  return new DeviceSessionIssuer(KEY, { signup: "open", inviteCodes: [], store, ...(registry ? { devices: registry, joinMs } : {}) });
}
const bearerOf = (token: string) => `Bearer ${token}`;

/** A store as the earlier version left it: no iPhone rows, no cut-offs, joins without a renewal time or a sign-in. */
async function earlierStore(): Promise<Store> {
  const store = await Store.memoryForTests();
  stores.push(store);
  await store.db.query("DROP TABLE devices");
  await store.db.query("DROP TABLE device_cutoffs");
  await store.db.query("ALTER TABLE device_joins DROP COLUMN identity_id");
  await store.db.query("ALTER TABLE device_joins DROP COLUMN renewed_at");
  return store;
}
/** What the server does at every start: the schema, idempotent, in one transaction. */
async function start(store: Store): Promise<void> {
  await store.db.transaction(async (tx) => {
    for (const statement of SCHEMA_SQL.split(";").map((s) => s.trim()).filter(Boolean)) await tx.query(statement);
  });
}

test("the first start over an earlier database signs nobody out: tokens without a device id work, joins count from that start", async () => {
  const store = await earlierStore();
  const account = GOOGLE;
  const joinedPhone = userIdOf(SECOND);
  // A join made a year ago, a token made yesterday by the earlier code, and an owner who has signed in.
  await store.db.query("INSERT INTO device_joins (device_user_id, user_id, provider, created_at) VALUES ($1, $2, 'google', $3)", [joinedPhone, account, Date.now() - 365 * DAY_MS]);
  const signer = new SignedSessionVerifier(KEY);
  const yesterday = new Date(Date.now() - DAY_MS);
  const legacyJoined = signer.mint(account, yesterday, 30 * 86_400);
  const legacyOwner = signer.mint(userIdOf(OWNER), yesterday, 30 * 86_400);
  assert.equal(claims(legacyJoined).dev, undefined);

  await start(store);

  const registry = new DeviceRegistry(store, {});
  const verifier = new RevocableSessionVerifier(new SignedSessionVerifier(KEY), new TokenFloors(store), registry);
  assert.deepEqual(await verifier.verify(bearerOf(legacyJoined), new Date()), { userId: account }, "a joined iPhone's older token still works");
  assert.deepEqual(await verifier.verify(bearerOf(legacyOwner), new Date()), { userId: userIdOf(OWNER) }, "so does the owner's");

  const joinRow = (await store.db.query<{ renewed_at: number }>("SELECT renewed_at FROM device_joins")).rows[0]!;
  assert.ok(Math.abs(Number(joinRow.renewed_at) - Date.now()) < 120_000, "the join's 90 days count from this start, not from a year ago");
  assert.ok(await store.deviceJoin(joinedPhone, Date.now() - 90 * DAY_MS), "the year-old join is valid");
  assert.equal(await store.deviceJoin(joinedPhone, Number(joinRow.renewed_at) + 1), null, "and runs out 90 days after the start");

  const rows = (await store.db.query<{ device_user_id: string; first_seen_at: number; last_seen_at: number; revoked_at: number | null }>("SELECT * FROM devices")).rows;
  assert.equal(rows.length, 1, "the joined iPhone is listed from the start; the owner's and guests' are added when they sign in");
  const joinedRowId = (await store.db.query<{ device_id: string }>("SELECT device_id FROM devices")).rows[0]!.device_id;
  assert.equal(rows[0]!.device_user_id, joinedPhone);
  assert.equal(Number(rows[0]!.first_seen_at), Number(rows[0]!.last_seen_at));
  assert.ok(Math.abs(Number(rows[0]!.first_seen_at) - Date.now()) < 120_000, "first and last seen are the start");
  assert.equal(rows[0]!.revoked_at, null);
  assert.equal((await registry.list(account, null, new Date())).length, 1);

  // Every later start changes nothing.
  const before = JSON.stringify((await store.db.query("SELECT * FROM devices ORDER BY device_user_id")).rows) + JSON.stringify((await store.db.query("SELECT * FROM device_joins")).rows);
  await start(store);
  assert.equal(JSON.stringify((await store.db.query("SELECT * FROM devices ORDER BY device_user_id")).rows) + JSON.stringify((await store.db.query("SELECT * FROM device_joins")).rows), before);

  // The owner signs in with the new code: a row is made, with the same user id, and the token names it.
  const issuer = issuerFor(store, registry);
  const owner = await issuer.issue({ deviceId: OWNER }, new Date());
  assert.equal(owner.access, "full");
  assert.ok(claims(owner.token).dev);
  assert.equal((await store.db.query("SELECT 1 FROM devices")).rows.length, 2);
  // The joined iPhone signs in: still the account, and the same row it was given at the start.
  const joined = await issuer.issue({ deviceId: SECOND }, new Date());
  assert.equal(claims(joined.token).sub, account);
  assert.equal(claims(joined.token).dev, joinedRowId);
});

test("a token made before iPhones were stored ends when an iPhone on its account is revoked; later tokens are not touched", async () => {
  const store = await earlierStore();
  await start(store);
  const registry = new DeviceRegistry(store, {});
  const verifier = new RevocableSessionVerifier(new SignedSessionVerifier(KEY), new TokenFloors(store), registry);
  const issuer = issuerFor(store, registry);
  const account = GOOGLE;
  await store.createWebAccount({ userId: account, identityId: GOOGLE, provider: "google", now: Date.now() });
  await store.setDeviceJoin(userIdOf(SECOND), account, "google", Date.now(), GOOGLE);
  await store.setDeviceJoin(userIdOf(THIRD), account, "google", Date.now(), GOOGLE);

  const signer = new SignedSessionVerifier(KEY);
  const legacy = signer.mint(account, new Date(Date.now() - 2 * HOUR), 30 * 86_400);
  const thirdToken = (await issuer.issue({ deviceId: THIRD }, new Date())).token;
  assert.ok(await verifier.verify(bearerOf(legacy), new Date()));

  const target = (await store.db.query<{ device_id: string }>("SELECT device_id FROM devices WHERE device_user_id = $1", [userIdOf(SECOND)])).rows[0]!.device_id;
  await registry.revoke(account, target, new Date());

  assert.equal(await verifier.verify(bearerOf(legacy), new Date()), null, "an older token that could be the revoked iPhone's is ended, so the revoke ends it too");
  assert.deepEqual(await verifier.verify(bearerOf(thirdToken), new Date()), { userId: account, deviceId: claims(thirdToken).dev }, "a token that names another iPhone is not");
  // The ended older token's iPhone signs in again by itself and gets one that names it.
  const fresh = await issuerFor(store, registry).issue({ deviceId: THIRD }, new Date(Date.now() + 2_000));
  assert.ok(await verifier.verify(bearerOf(fresh.token), new Date(Date.now() + 2_000)));
});

// ------------------------------------------------------------------ erasing, pruning

test("deleting an account removes its own iPhone's row and the account's cut-offs, and leaves other accounts' iPhones", async () => {
  const r = await rig();
  const { owner, second, third } = await twoAccounts(r);
  await revoke(r, second, claims(third).dev!);
  assert.ok((await r.store.db.query("SELECT 1 FROM device_cutoffs")).rows.length >= 1, "the revoke left a cut-off for the account");
  const erasedOwner = await r.store.eraseUser(userIdOf(OWNER), r.clock.ms);
  assert.equal(erasedOwner.remaining, 0);
  assert.equal((await asks(r, owner)).status, 401, "its tokens are cut off by the erasure as before");
  assert.equal(await rowOf(r, OWNER), undefined, "the erased account's own iPhone row is gone");
  assert.ok(await rowOf(r, SECOND), "the account B's iPhones are not touched");
  const erasedB = await r.store.eraseUser(GOOGLE, r.clock.ms);
  assert.equal(erasedB.remaining, 0);
  assert.equal((await r.store.db.query("SELECT 1 FROM device_cutoffs WHERE user_id = $1", [GOOGLE])).rows.length, 0);
  assert.equal((await r.store.deviceJoin(userIdOf(SECOND))), null, "its joins went with it");
  assert.ok(await rowOf(r, SECOND), "the iPhone's own row stays: it is not this account's data");
});

test("iPhones not seen for a long time are dropped, revoked ones are kept", async () => {
  const r = await rig();
  const { second, third } = await twoAccounts(r);
  await revoke(r, second, claims(third).dev!);
  r.clock.advance((DEVICE_KEPT_DAYS + 1) * DAY_MS);
  const dropped = await r.store.pruneDevices(r.clock.ms - DEVICE_KEPT_DAYS * DAY_MS);
  assert.equal(dropped, 2, "the owner's and the second iPhone, unseen since");
  assert.equal(await rowOf(r, OWNER), undefined);
  assert.ok(await rowOf(r, THIRD), "a revoked one stays, so nobody gets back in by waiting");
  assert.equal((await signIn(r, THIRD)).status, 401);
});

// ------------------------------------------------------------------ what is logged and answered

test("no token, key or device id appears in a log line or an answer", async () => {
  const r = await rig();
  const answers: string[] = [];
  const keep = async (p: ReturnType<WebRig["call"]>) => {
    const res = await p;
    answers.push(res.text, JSON.stringify([...res.headers.entries()].filter(([k]) => k !== "set-cookie")));
    return res;
  };
  // A successful sign-in's answer is the token itself, on purpose: it is not scanned. Everything else is.
  const owner = (await signIn(r, OWNER)).body.token as string;
  await webAccount(r);
  await join(r, SECOND);
  const second = (await signIn(r, SECOND)).body.token as string;
  const secondId = claims(second).dev!;
  await keep(r.call("GET", "/v1/web/devices", { token: owner }));
  await keep(r.call("GET", "/v1/web/devices", { token: second }));
  await keep(revoke(r, owner, secondId));
  await keep(revoke(r, second, secondId));
  await keep(signIn(r, SECOND));
  await keep(r.call("DELETE", `/v1/web/identities/${GOOGLE}`, { token: owner }));
  await keep(r.call("GET", "/v1/web/devices", { token: second }));

  const text = r.logs.join("\n") + answers.join("\n");
  const secrets = [owner, second, owner.split(".")[2]!, second.split(".")[2]!, OWNER, SECOND, userIdOf(OWNER), userIdOf(SECOND), ...[KEY.toString("base64"), KEY.toString("base64url"), KEY.toString("hex")]];
  for (const secret of secrets) assert.ok(!text.includes(secret), `no ${secret.slice(0, 12)}… in logs or answers`);
  assert.ok(r.logs.some((line) => line.includes("device_revoked")), "the revoke is logged, without who");
});

// ------------------------------------------------------------------ the setting

test("config: DODDY_DEVICE_JOIN_DAYS is a plain number of days, 90 by default", () => {
  assert.equal(loadConfig({}).deviceJoinDays, 90);
  assert.equal(loadConfig({ DODDY_DEVICE_JOIN_DAYS: "30" }).deviceJoinDays, 30);
  assert.equal(loadConfig({ DODDY_DEVICE_JOIN_DAYS: "" }).deviceJoinDays, 90);
  for (const bad of ["0", "-1", "x", "1.5", "4000"]) assert.throws(() => loadConfig({ DODDY_DEVICE_JOIN_DAYS: bad }), ConfigError, bad);
});
