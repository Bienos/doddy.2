import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { AccountEraser } from "../src/account.js";
import { buildApp } from "../src/app.js";
import { type AuthenticatedUser, RevocableSessionVerifier, type SessionVerifier, SignedSessionVerifier, sessionTokenIssuedAt, TokenFloors } from "../src/auth.js";
import { defaultRegistry } from "../src/capabilities.js";
import { loadConfig, testLimits } from "../src/config.js";
import { DeviceSessionIssuer, deviceUserId } from "../src/deviceSession.js";
import { AppError } from "../src/errors.js";
import { createHandler } from "../src/http.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { ConnectedAppsService } from "../src/service.js";
import { ERASED_TABLES, KEPT_ON_ERASE, Store } from "../src/store.js";
import { MockToolsProvider } from "../src/tools/mock.js";
import { CloudToolsService } from "../src/tools/service.js";
import { Clock } from "./helpers.js";

/**
 * Sign-in tokens can be cut off (ADR-709): deleting the account on the server ends every token issued
 * to that person before the deletion, and a new sign-in works at once.
 */

const KEY = Buffer.alloc(32, 7);
const PHONE = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const CODE = "second-phone-code";
const claims = (token: string) => JSON.parse(Buffer.from(token.split(".")[1]!, "base64url").toString("utf8")) as { sub: string; iat: number; exp: number; scp?: string };

let servers: Server[] = [];
let stores: Store[] = [];
afterEach(async () => {
  for (const server of servers) server.close();
  for (const store of stores) await store.close();
  servers = [];
  stores = [];
});

/** The server as the iPhone sees it: sign in with a device ID, call the API, delete the account. */
async function rig() {
  const store = await Store.memory();
  stores.push(store);
  const clock = new Clock(Date.parse("2026-11-04T10:00:00.400Z"));
  const floors = new TokenFloors(store);
  const common = { store, limits: testLimits(), publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return", now: clock.now, sleep: async () => {} };
  const tools = new CloudToolsService({ ...common, provider: new MockToolsProvider(), webSearch: null, claude: null, documentLinks: null, completionMode: "mock" });
  const service = new ConnectedAppsService({ ...common, provider: new MockCalendarProvider(), registry: defaultRegistry(), completionMode: "mock" });
  const account = new AccountEraser({ store, removers: [], timeoutMs: 1_000, floors, now: clock.now });
  const handler = createHandler({
    service,
    tools,
    account,
    verifier: new RevocableSessionVerifier(new SignedSessionVerifier(KEY), floors),
    deviceSessions: new DeviceSessionIssuer(KEY, { signup: "open", inviteCodes: [CODE], store, ownerClaim: "open" }),
    appReturnUrl: common.appReturnUrl,
    maxBodyBytes: 8 * 1024,
    now: () => new Date(clock.ms),
    log: () => {},
  });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  servers.push(server);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const api = async (method: string, path: string, token: string | null, body?: unknown) => {
    const headers: Record<string, string> = {};
    if (token) headers.authorization = `Bearer ${token}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    const res = await fetch(`${base}${path}`, { method, headers, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
    const text = await res.text();
    return { status: res.status, body: text ? (JSON.parse(text) as any) : null };
  };
  const signIn = async (n: number, extra: Record<string, unknown> = {}) => {
    const res = await api("POST", "/v1/session/device", null, { deviceId: PHONE(n), ...extra });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    return res.body as { token: string; expiresAt: string; access: "full" | "ask" };
  };
  return { store, clock, floors, api, signIn };
}

/** A full session can read the catalog; a guest is told it isn't set up (503); a cut-off token is a 401. */
const catalog = (r: Awaited<ReturnType<typeof rig>>, token: string) => r.api("GET", "/v1/tools", token);

test("a token minted before the account was deleted is refused after, and signing in again works at once", async () => {
  const r = await rig();
  const owner = await r.signIn(1);
  assert.equal(owner.access, "full");
  assert.equal((await catalog(r, owner.token)).status, 200);

  const erased = await r.api("DELETE", "/v1/account", owner.token);
  assert.equal(erased.status, 200, JSON.stringify(erased.body));
  assert.equal(erased.body.complete, true);

  // The very next request, in the same second: the old token is dead.
  const refused = await catalog(r, owner.token);
  assert.equal(refused.status, 401);
  assert.equal(refused.body.error.code, "unauthenticated");
  assert.equal((await r.api("DELETE", "/v1/account", owner.token)).status, 401, "it can't delete again either");

  // The same iPhone signs in again in that same second: its new token is dated at the cut-off, not before it.
  const again = await r.signIn(1);
  assert.equal(again.access, "full", "the server is still this iPhone's (the owner row is kept)");
  assert.equal((await catalog(r, again.token)).status, 200);
  assert.ok(claims(again.token).iat > claims(owner.token).iat, "dated after the token it replaces");
  assert.equal(claims(again.token).exp - claims(again.token).iat, 30 * 24 * 3_600);
  assert.equal(again.expiresAt, new Date(claims(again.token).exp * 1000).toISOString());
  assert.equal((await catalog(r, owner.token)).status, 401, "the old token stays dead");

  // Deleting again, later, cuts off the newer token too, and a still later sign-in works.
  r.clock.advance(3_000);
  assert.equal((await r.api("DELETE", "/v1/account", again.token)).status, 200);
  assert.equal((await catalog(r, again.token)).status, 401);
  const later = await r.signIn(1);
  assert.equal((await catalog(r, later.token)).status, 200);
});

test("a person's other tokens, other people and an invited device are not cut off", async () => {
  const r = await rig();
  const owner = await r.signIn(1);
  const invited = await r.signIn(3, { inviteCode: CODE });
  assert.equal(invited.access, "full");
  const guest = await r.signIn(2);
  assert.equal(guest.access, "ask");
  // A second token for the same device (a renewed sign-in, a second later) is the same person: it is cut off with the first.
  r.clock.advance(1_000);
  const guestAgain = await r.signIn(2);
  assert.notEqual(guestAgain.token, guest.token);

  assert.equal((await r.api("DELETE", "/v1/account", guest.token)).status, 200, "a guest may delete its own data");
  assert.equal((await catalog(r, guest.token)).status, 401, "the guest's token is cut off");
  assert.equal((await catalog(r, guestAgain.token)).status, 401, "so is every other token of that guest");
  assert.equal((await catalog(r, owner.token)).status, 200);
  assert.equal((await catalog(r, invited.token)).status, 200);
  assert.equal(await r.store.tokenFloor(deviceUserId(KEY, PHONE(1))), 0);

  // The guest signs in again: a fresh guest token works (guests only get "not set up", never a 401).
  const fresh = await r.signIn(2);
  assert.equal(fresh.access, "ask");
  const probe = await catalog(r, fresh.token);
  assert.equal(probe.status, 503);
  assert.equal(probe.body.error.code, "live_not_configured");
});

test("the cut-off is kept when the person's rows are erased, and never goes back", async () => {
  const r = await rig();
  const id = deviceUserId(KEY, PHONE(1));
  const first = await r.store.eraseUser(id, 5_000_000);
  assert.equal(first.tokensValidAfter, 5_001);
  assert.equal(await r.store.tokenFloor(id), 5_001);
  assert.ok(([...KEPT_ON_ERASE] as string[]).includes("token_floor"), "listed as kept on purpose");
  assert.ok(!([...ERASED_TABLES] as string[]).includes("token_floor"));
  const rows = async () => Number((await r.store.db.query<{ n: number | string }>("SELECT count(*) AS n FROM token_floor WHERE user_id = $1", [id])).rows[0]!.n);
  assert.equal(await rows(), 1, "the erasure that wrote it didn't delete it");
  // An erasure with an earlier clock can't lower it.
  await r.store.eraseUser(id, 1_000_000);
  assert.equal(await r.store.tokenFloor(id), 5_001);
  await r.store.eraseUser(id, 9_000_000);
  assert.equal(await r.store.tokenFloor(id), 9_001);
  assert.equal(await rows(), 1);
});

test("a floor is dropped only when every token it covers has expired", async () => {
  const r = await rig();
  const now = Date.parse("2026-11-04T10:00:00Z");
  const DAY = 86_400_000;
  await r.store.eraseUser("00000000-0000-4000-8000-0000000000a1", now - 40 * DAY);
  await r.store.eraseUser("00000000-0000-4000-8000-0000000000a2", now - 10 * DAY);
  assert.equal(await r.store.pruneTokenFloors(now), 1);
  assert.equal(await r.store.tokenFloor("00000000-0000-4000-8000-0000000000a1"), 0, "older than a token can live");
  assert.ok((await r.store.tokenFloor("00000000-0000-4000-8000-0000000000a2")) > 0, "a recent cut-off still matters");
  assert.deepEqual(Object.keys(await r.store.prune(now)).sort(), ["approvals", "attempts", "receipts", "toolReceipts", "usage"], "prune's own counts are unchanged");
});

// ------------------------------------------------------------------ the verifier itself

class FixedVerifier implements SessionVerifier {
  constructor(private readonly user: AuthenticatedUser | null) {}
  verify(): AuthenticatedUser | null {
    return this.user;
  }
}

const USER = "00000000-0000-4000-8000-0000000000a1";
const signer = new SignedSessionVerifier(KEY);
const at = (seconds: number) => new Date(seconds * 1000);

test("a token dated before the cut-off is refused; one dated at or after it, and tokens of other kinds, are not", async () => {
  const lookups: string[] = [];
  const floors = new TokenFloors({ tokenFloor: async (id) => (lookups.push(id), id === USER ? 1_000 : 0) });
  const verifier = new RevocableSessionVerifier(signer, floors);
  const header = (seconds: number, scope?: "ask") => `Bearer ${signer.mint(USER, at(seconds), 3_600, scope)}`;
  const now = at(1_100);
  assert.equal(await verifier.verify(header(999), now), null, "dated just before");
  assert.deepEqual(await verifier.verify(header(1_000), now), { userId: USER }, "dated at the cut-off");
  assert.deepEqual(await verifier.verify(header(1_050, "ask"), now), { userId: USER, scope: "ask" }, "a guest's token keeps its scope");
  assert.equal(await verifier.verify(header(10), now), null);
  // Somebody else with the same dates is not affected.
  const other = "00000000-0000-4000-8000-0000000000b2";
  assert.deepEqual(await verifier.verify(`Bearer ${signer.mint(other, at(10), 3_600)}`, now), { userId: other });
  // Not a device token (a Supabase access token, say): the inner verifier's answer stands, with no lookup.
  lookups.length = 0;
  const jwtLike = new RevocableSessionVerifier(new FixedVerifier({ userId: USER }), floors);
  assert.deepEqual(await jwtLike.verify("Bearer aaaa.bbbb.cccc", now), { userId: USER });
  assert.deepEqual(lookups, []);
  // Nobody signed in stays nobody.
  assert.equal(await new RevocableSessionVerifier(new FixedVerifier(null), floors).verify("Bearer x.y.z", now), null);
  assert.equal(await verifier.verify(undefined, now), null);
});

test("the cut-off is read through a short memory, and a new cut-off on this instance counts at once", async () => {
  let reads = 0;
  let stored = 0;
  const floors = new TokenFloors({ tokenFloor: async () => (reads++, stored) }, 30_000);
  const verifier = new RevocableSessionVerifier(signer, floors);
  const LONG = 30 * 24 * 3_600;
  const dated = (seconds: number) => `Bearer ${signer.mint(USER, at(seconds), LONG)}`;
  const t0 = 10_000_000; // ms; the tokens below are dated well before it
  for (let n = 0; n < 5; n++) assert.ok(await verifier.verify(dated(1_000), new Date(t0 + n * 1_000)));
  assert.equal(reads, 1, "five requests in five seconds cost one database read");

  // This instance deletes the account: the cut-off is written to the database and told to the memory.
  stored = 2_000;
  floors.remember(USER, 2_000, t0 + 5_000);
  assert.equal(await verifier.verify(dated(1_000), new Date(t0 + 5_000)), null, "refused at once, though the memory was fresh");
  assert.equal(reads, 1, "from the memory, not the database");

  // A change made elsewhere (another instance) is seen when the memory expires, thirty seconds on.
  stored = 3_000;
  assert.ok(await verifier.verify(dated(2_500), new Date(t0 + 5_500)), "still the remembered cut-off");
  assert.equal(reads, 1);
  assert.equal(await verifier.verify(dated(2_500), new Date(t0 + 36_000)), null, "asked again after thirty seconds, and now refused");
  assert.equal(reads, 2);
  assert.deepEqual(await verifier.verify(dated(3_500), new Date(t0 + 36_500)), { userId: USER });
  assert.equal(reads, 2);
  // Remembering never lowers a cut-off.
  floors.remember(USER, 10, t0 + 37_000);
  assert.equal(await floors.floorOf(USER, t0 + 37_000), 3_000);
});

test("the memory of cut-offs is bounded", async () => {
  const floors = new TokenFloors({ tokenFloor: async () => 0 }, 30_000, 3);
  for (let n = 1; n <= 10; n++) floors.remember(`00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, n, 1_000);
  const seen = (floors as unknown as { seen: Map<string, unknown> }).seen;
  assert.equal(seen.size, 3);
  assert.ok(seen.has("00000000-0000-4000-8000-000000000010"), "the newest are kept");
});

test("if the cut-off can't be read, the request is refused as 'can't check right now', never as signed out", async () => {
  const floors = new TokenFloors({ tokenFloor: async () => Promise.reject(new Error("db down")) });
  const verifier = new RevocableSessionVerifier(signer, floors);
  await assert.rejects(
    verifier.verify(`Bearer ${signer.mint(USER, at(1_000), 3_600)}`, at(1_100)),
    (e: AppError) => e.code === "provider_unavailable" && /couldn't check your sign-in/.test(e.message),
  );
});

test("sessionTokenIssuedAt reads the date of a device token and nothing else", () => {
  const token = signer.mint(USER, at(1_234), 3_600);
  assert.equal(sessionTokenIssuedAt(`Bearer ${token}`), 1_234);
  assert.equal(sessionTokenIssuedAt("Bearer aaaa.bbbb.cccc"), undefined, "not a device token");
  assert.equal(sessionTokenIssuedAt(undefined), undefined);
  assert.equal(sessionTokenIssuedAt("Bearer ds1.aaaaaaaa.sigsigsig"), null, "a device token whose claims can't be read");
  assert.equal(sessionTokenIssuedAt(`Bearer ds1.${Buffer.from(JSON.stringify({ iat: "x" })).toString("base64url")}.sigsigsig`), null);
});

test("a device token for a person whose cut-off is in the future is dated at the cut-off by the sign-in", async () => {
  const r = await rig();
  // Cut off for 20 seconds from the clock's second, as if the server's clock had just been behind.
  const id = deviceUserId(KEY, PHONE(4));
  await r.store.eraseUser(id, r.clock.ms + 20_000);
  const floor = await r.store.tokenFloor(id);
  const session = await r.signIn(4);
  assert.equal(claims(session.token).iat, floor, "never dated before the cut-off, so it is not refused");
  assert.equal((await catalog(r, session.token)).status, 200, "the verifier allows a date up to a minute ahead");
});

// ------------------------------------------------------------------ the real server

test("the real server: delete the account, and the old token stops working while a new sign-in works", async () => {
  const config = loadConfig({
    DODDY_MODE: "mock",
    DODDY_AUTH_MODE: "signed",
    DODDY_SESSION_SIGNING_KEY: KEY.toString("base64"),
    DODDY_DEVICE_SIGNUP: "first-device",
    DODDY_DB_PATH: ":memory:",
  });
  const { server, store } = await buildApp(config);
  servers.push(server);
  stores.push(store);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = async (method: string, path: string, token?: string, body?: unknown) => {
    const res = await fetch(`${base}${path}`, {
      method,
      headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { "content-type": "application/json" } : {}) },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
    return { status: res.status, body: (await res.json().catch(() => null)) as any };
  };
  const signIn = async () => {
    const res = await call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    return res.body.token as string;
  };
  const token = await signIn();
  assert.equal((await call("GET", "/v1/tools", token)).status, 200);
  assert.equal((await call("DELETE", "/v1/account", token)).status, 200);
  assert.equal((await call("GET", "/v1/tools", token)).status, 401, "the server built from config refuses the cut-off token");
  const fresh = await signIn();
  assert.equal((await call("GET", "/v1/tools", fresh)).status, 200, "and accepts the new sign-in at once");
  assert.equal((await call("GET", "/v1/tools", token)).status, 401);
});
