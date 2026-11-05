import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { buildApp } from "../src/app.js";
import { defaultRegistry } from "../src/capabilities.js";
import { SignedSessionVerifier } from "../src/auth.js";
import { ConfigError, loadConfig, testLimits } from "../src/config.js";
import { DeviceSessionIssuer, deviceUserId, INVITE_LIMITS, OWNER_UNCLAIMED_LOG_EVERY_MS } from "../src/deviceSession.js";
import { AppError } from "../src/errors.js";
import { createHandler } from "../src/http.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { ConnectedAppsService } from "../src/service.js";
import { Store } from "../src/store.js";

/**
 * Who may claim an empty server (ADR-707) and what one invite code may do (ADR-709), for device
 * sessions (`POST /v1/session/device`).
 */

const KEY = Buffer.alloc(32, 5);
const NOW = new Date("2026-11-04T10:00:00Z");
const HOUR = 3_600_000;
const PHONE = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

let stores: Store[] = [];
let servers: Server[] = [];
let closers: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const server of servers) server.close();
  for (const close of closers) await close();
  for (const store of stores) await store.close();
  stores = [];
  servers = [];
  closers = [];
});

async function freshStore(): Promise<Store> {
  const store = await Store.memory();
  stores.push(store);
  return store;
}

function issuer(store: Store, o: Partial<ConstructorParameters<typeof DeviceSessionIssuer>[1]> & { signup: "first-device" | "open" | "off" }): DeviceSessionIssuer {
  return new DeviceSessionIssuer(KEY, { inviteCodes: [], store, ...o });
}

/** Reads the owner without claiming anything. */
const ownerOf = (store: Store) => store.claimDeviceOwner(PHONE(999), 0, false);
const resetOwner = (store: Store) => store.db.query("DELETE FROM device_owner");
const userOfToken = (token: string, at = NOW) => new SignedSessionVerifier(KEY).verify(`Bearer ${token}`, at)?.userId;

const rejection = async (promise: Promise<unknown>): Promise<AppError> => {
  try {
    await promise;
  } catch (error) {
    assert.ok(error instanceof AppError, String(error));
    return error;
  }
  throw new assert.AssertionError({ message: "expected the sign-in to be refused" });
};

// ------------------------------------------------------------------ the setting (ADR-707)

test("config: the owner claim is open for mock runs and closed for a live server, unless it is set", () => {
  const key = Buffer.alloc(32, 1).toString("base64");
  const mock = { DODDY_MODE: "mock", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: key };
  const live = { DODDY_MODE: "live", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: key, MONID_API_KEY: "monid_live_abcdefghij", DODDY_PUBLIC_BASE_URL: "https://doddy.test" };
  assert.equal(loadConfig({}).ownerClaim, "open", "mock mode with nothing set: tests, demos and e2e work as before");
  assert.equal(loadConfig(mock).ownerClaim, "open");
  assert.equal(loadConfig(live).ownerClaim, "closed", "a live server is closed unless the operator opens it");
  assert.equal(loadConfig({ ...live, DODDY_OWNER_CLAIM: "open" }).ownerClaim, "open");
  assert.equal(loadConfig({ ...mock, DODDY_OWNER_CLAIM: "closed" }).ownerClaim, "closed");
  assert.equal(loadConfig({ ...live, DODDY_OWNER_CLAIM: "" }).ownerClaim, "closed", "a setting left blank is no setting");
  assert.equal(loadConfig({ ...live, DODDY_OWNER_CLAIM: " Open " }).ownerClaim, "open");
  assert.throws(
    () => loadConfig({ ...live, DODDY_OWNER_CLAIM: "maybe" }),
    (e: ConfigError) => e.problems.some((p) => p === "DODDY_OWNER_CLAIM must be open or closed") && !e.message.includes("maybe"),
    "the problem names the setting, never its value",
  );
});

test("config: the invite limits, the document limits and the request size cap have safe defaults", () => {
  const config = loadConfig({});
  assert.deepEqual(config.inviteLimits, { triesPerClientPerHour: 20, sessionsPerCodePerDay: 20, devicesPerCode: 5 });
  assert.deepEqual(config.inviteLimits, { ...INVITE_LIMITS });
  assert.equal(config.limits.documentClaudeUnits, 5);
  assert.equal(config.limits.userDocumentJobs, 1);
  assert.equal(config.limits.serviceDocumentJobs, 3);
  assert.equal(config.limits.maxBodyBytes, 24 * 1024, "every JSON body is capped before it is parsed or validated");
  const set = loadConfig({
    DODDY_INVITE_TRIES_PER_CLIENT: "7",
    DODDY_INVITE_SESSIONS_PER_CODE_PER_DAY: "8",
    DODDY_INVITE_DEVICES_PER_CODE: "2",
    DODDY_DOCUMENT_CLAUDE_UNITS: "9",
    DODDY_LIMIT_USER_DOCUMENT_JOBS: "2",
    DODDY_LIMIT_SERVICE_DOCUMENT_JOBS: "6",
  });
  assert.deepEqual(set.inviteLimits, { triesPerClientPerHour: 7, sessionsPerCodePerDay: 8, devicesPerCode: 2 });
  assert.deepEqual([set.limits.documentClaudeUnits, set.limits.userDocumentJobs, set.limits.serviceDocumentJobs], [9, 2, 6]);
  for (const bad of [{ DODDY_INVITE_DEVICES_PER_CODE: "0" }, { DODDY_DOCUMENT_CLAUDE_UNITS: "x" }, { DODDY_LIMIT_USER_DOCUMENT_JOBS: "0" }]) {
    assert.throws(() => loadConfig(bad), ConfigError, JSON.stringify(bad));
  }
});

// ------------------------------------------------------------------ an empty server (ADR-707)

test("closed, no owner yet: nobody can claim it; first-device refuses clearly, open gives a guest", async () => {
  const store = await freshStore();
  const first = issuer(store, { signup: "first-device", ownerClaim: "closed" });
  const refused = await rejection(first.issue({ deviceId: PHONE(1) }, NOW));
  assert.equal(refused.code, "unauthenticated");
  assert.equal(refused.message, "This Doddy server has no owner yet. The operator must open the owner claim.");
  assert.equal(await ownerOf(store), null, "nothing was claimed");

  const open = issuer(store, { signup: "open", ownerClaim: "closed" });
  const guest = await open.issue({ deviceId: PHONE(1) }, NOW);
  assert.equal(guest.access, "ask", "even the first iPhone is only a guest on a closed, empty server");
  assert.equal(await ownerOf(store), null);
  assert.equal((await open.issue({ deviceId: PHONE(2) }, NOW)).access, "ask");
  assert.equal(await ownerOf(store), null);
});

test("closed, no owner yet: one owner_unclaimed line every ten minutes at most, with nothing about the caller in it", async () => {
  const store = await freshStore();
  const logs: Record<string, unknown>[] = [];
  const open = issuer(store, { signup: "open", ownerClaim: "closed", log: (line) => logs.push(line) });
  for (let n = 1; n <= 6; n++) await open.issue({ deviceId: PHONE(n) }, new Date(NOW.getTime() + n * 1_000), `203.0.113.${n}`);
  const events = () => logs.filter((l) => l.event === "owner_unclaimed");
  assert.equal(events().length, 1, "six sign-ins in a few seconds log once");
  assert.deepEqual(Object.keys(events()[0]!).sort(), ["action", "event", "level", "ownerClaim"]);
  assert.match(String(events()[0]!.action), /DODDY_OWNER_CLAIM=open/);
  assert.match(String(events()[0]!.action), /remove/);
  const text = JSON.stringify(logs);
  for (const secret of [PHONE(1), deviceUserId(KEY, PHONE(1)), "203.0.113"]) assert.ok(!text.includes(secret), `the log names no ${secret}`);

  await open.issue({ deviceId: PHONE(9) }, new Date(NOW.getTime() + OWNER_UNCLAIMED_LOG_EVERY_MS + 5_000), "203.0.113.9");
  assert.equal(events().length, 2, "after ten minutes it says so again");

  // A server that has an owner has nothing to report.
  await store.claimDeviceOwner(deviceUserId(KEY, PHONE(1)), NOW.getTime());
  logs.length = 0;
  await open.issue({ deviceId: PHONE(2) }, new Date(NOW.getTime() + 3 * OWNER_UNCLAIMED_LOG_EVERY_MS), "203.0.113.2");
  assert.deepEqual(logs, []);
});

test("open, no owner yet: the first iPhone owns the server, as before", async () => {
  const store = await freshStore();
  for (const signup of ["first-device", "open"] as const) {
    await resetOwner(store);
    const i = issuer(store, { signup, ownerClaim: "open" });
    const first = await i.issue({ deviceId: PHONE(1) }, NOW);
    assert.equal(first.access, "full");
    assert.equal(userOfToken(first.token), deviceUserId(KEY, PHONE(1)));
    assert.equal(await ownerOf(store), deviceUserId(KEY, PHONE(1)));
    if (signup === "open") assert.equal((await i.issue({ deviceId: PHONE(2) }, NOW)).access, "ask");
    else assert.equal((await rejection(i.issue({ deviceId: PHONE(2) }, NOW))).message, "This Doddy server already belongs to another iPhone.");
    assert.equal(await ownerOf(store), deviceUserId(KEY, PHONE(1)), "a second iPhone never replaces the owner");
  }
});

test("a server that already has an owner behaves the same whether the claim is open or closed", async () => {
  const store = await freshStore();
  for (const ownerClaim of ["open", "closed"] as const) {
    for (const signup of ["first-device", "open"] as const) {
      await resetOwner(store);
      await store.claimDeviceOwner(deviceUserId(KEY, PHONE(1)), NOW.getTime()); // the live server's state
      const i = issuer(store, { signup, ownerClaim });
      assert.equal((await i.issue({ deviceId: PHONE(1) }, NOW)).access, "full", `${ownerClaim}/${signup}: the owner still signs in`);
      if (signup === "open") assert.equal((await i.issue({ deviceId: PHONE(2) }, NOW)).access, "ask", `${ownerClaim}/${signup}`);
      else assert.equal((await rejection(i.issue({ deviceId: PHONE(2) }, NOW))).message, "This Doddy server already belongs to another iPhone.");
      assert.equal(await ownerOf(store), deviceUserId(KEY, PHONE(1)), `${ownerClaim}/${signup}: still the same owner`);
    }
  }
});

test("two first sign-ins at once when the claim is open: exactly one iPhone becomes the owner", async () => {
  const store = await freshStore();
  for (const signup of ["first-device", "open"] as const) {
    await resetOwner(store);
    const i = issuer(store, { signup, ownerClaim: "open" });
    const outcomes = await Promise.allSettled(Array.from({ length: 8 }, (_, n) => i.issue({ deviceId: PHONE(n + 1) }, NOW, `198.51.100.${n}`)));
    const full = outcomes.flatMap((o) => (o.status === "fulfilled" && o.value.access === "full" ? [o.value] : []));
    assert.equal(full.length, 1, `${signup}: one full session`);
    const owner = await ownerOf(store);
    assert.equal(userOfToken(full[0]!.token), owner, "the one with the full session is the stored owner");
    if (signup === "open") assert.equal(outcomes.filter((o) => o.status === "fulfilled" && o.value.access === "ask").length, 7, "everyone else is a guest");
    else assert.equal(outcomes.filter((o) => o.status === "rejected").length, 7, "everyone else is refused");
    const rows = await store.db.query<{ n: number | string }>("SELECT count(*) AS n FROM device_owner");
    assert.equal(Number(rows.rows[0]!.n), 1);
  }
});

test("the store's claim: without permission it only reads, with it the first caller wins and the owner never changes", async () => {
  const store = await freshStore();
  assert.equal(await store.claimDeviceOwner("00000000-0000-4000-8000-0000000000a1", 1, false), null);
  assert.equal(await ownerOf(store), null, "reading wrote nothing");
  assert.equal(await store.claimDeviceOwner("00000000-0000-4000-8000-0000000000a1", 2, true), "00000000-0000-4000-8000-0000000000a1");
  assert.equal(await store.claimDeviceOwner("00000000-0000-4000-8000-0000000000b2", 3, true), "00000000-0000-4000-8000-0000000000a1");
  assert.equal(await store.claimDeviceOwner("00000000-0000-4000-8000-0000000000b2", 4, false), "00000000-0000-4000-8000-0000000000a1");
  assert.equal(await store.claimDeviceOwner("00000000-0000-4000-8000-0000000000c3", 5), "00000000-0000-4000-8000-0000000000a1", "the default is the old behaviour");
});

test("a valid invite code still signs a device in on a closed, empty server, and claims nothing", async () => {
  const store = await freshStore();
  const i = issuer(store, { signup: "first-device", ownerClaim: "closed", inviteCodes: ["right-code-12345"] });
  const invited = await i.issue({ deviceId: PHONE(2), inviteCode: "right-code-12345" }, NOW);
  assert.equal(invited.access, "full");
  assert.equal(await ownerOf(store), null, "an invited device never becomes the owner");
  const wrong = await rejection(i.issue({ deviceId: PHONE(3), inviteCode: "wrong-code-12345" }, NOW));
  assert.match(wrong.message, /no owner yet/);
});

// ------------------------------------------------------------------ the real server (ADR-707)

const LIVE = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "signed",
  DODDY_SESSION_SIGNING_KEY: KEY.toString("base64"),
  DODDY_PUBLIC_BASE_URL: "https://doddy.onrender.com",
  DODDY_DB_PATH: ":memory:",
  MONID_API_KEY: "monid_live_abcdefgh123",
};

async function app(env: Record<string, string>) {
  const { server, store } = await buildApp(loadConfig({ ...LIVE, ...env }), { webSearch: null });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  servers.push(server);
  closers.push(() => store.close());
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return {
    store,
    signIn: async (deviceId: string, extra: Record<string, unknown> = {}) => {
      const res = await fetch(`${base}/v1/session/device`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceId, ...extra }) });
      return { status: res.status, body: (await res.json()) as any };
    },
  };
}

test("the real live server is closed by default: an empty server can't be claimed until the operator opens it", async () => {
  const closed = await app({ DODDY_DEVICE_SIGNUP: "first-device" });
  const refused = await closed.signIn(PHONE(1));
  assert.equal(refused.status, 401);
  assert.equal(refused.body.error.code, "unauthenticated");
  assert.equal(refused.body.error.message, "This Doddy server has no owner yet. The operator must open the owner claim.");
  assert.equal(await ownerOf(closed.store), null);

  const guestOnly = await app({ DODDY_DEVICE_SIGNUP: "open" });
  const guest = await guestOnly.signIn(PHONE(1));
  assert.equal(guest.status, 200);
  assert.equal(guest.body.access, "ask");
  assert.equal(await ownerOf(guestOnly.store), null);

  // The operator opens it for the one sign-in that claims the server.
  const opened = await app({ DODDY_DEVICE_SIGNUP: "first-device", DODDY_OWNER_CLAIM: "open" });
  const owner = await opened.signIn(PHONE(1));
  assert.equal(owner.status, 200, JSON.stringify(owner.body));
  assert.equal(owner.body.access, "full");
  assert.equal(await ownerOf(opened.store), deviceUserId(KEY, PHONE(1)));
  assert.equal((await opened.signIn(PHONE(2))).status, 401, "and nobody else gets in");
});

test("the real live server with an owner already stored is not affected by the closed default", async () => {
  const live = await app({ DODDY_DEVICE_SIGNUP: "open" });
  await live.store.claimDeviceOwner(deviceUserId(KEY, PHONE(1)), NOW.getTime());
  assert.equal((await live.signIn(PHONE(1))).body.access, "full", "the owner signs in as before");
  assert.equal((await live.signIn(PHONE(2))).body.access, "ask", "everyone else is a guest, as before");
});

/** Starts the real `server.js` with these settings and returns its first `listening` line (names and modes only). */
async function startupLine(settings: Record<string, string>, port: number): Promise<Record<string, unknown>> {
  const child = spawn(process.execPath, [new URL("../src/server.js", import.meta.url).pathname], {
    env: { PATH: process.env.PATH ?? "", DODDY_DB_PATH: ":memory:", DODDY_PORT: String(port), ...settings },
    stdio: ["ignore", "pipe", "pipe"],
  });
  try {
    return await new Promise<Record<string, unknown>>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("the server did not say it was listening")), 30_000);
      let seen = "";
      child.stdout.on("data", (chunk: Buffer) => {
        seen += chunk.toString("utf8");
        for (const line of seen.split("\n")) {
          if (!line.includes('"listening"')) continue;
          clearTimeout(timer);
          resolve(JSON.parse(line) as Record<string, unknown>);
          return;
        }
      });
      child.stderr.on("data", (chunk: Buffer) => {
        clearTimeout(timer);
        reject(new Error(`server stderr: ${chunk.toString("utf8").slice(0, 300)}`));
      });
      child.on("exit", (code) => {
        clearTimeout(timer);
        reject(new Error(`the server exited (${code}) before it was listening`));
      });
    });
  } finally {
    child.kill("SIGKILL");
  }
}

/** A free-looking port each time, and a second try if another process took it between the pick and the start. */
async function startupLineOnFreePort(settings: Record<string, string>): Promise<Record<string, unknown>> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await startupLine(settings, 20_000 + Math.floor(Math.random() * 40_000));
    } catch (error) {
      if (attempt >= 3) throw error;
    }
  }
}

test("the startup line says whether an empty server can be claimed (names and modes only)", async () => {
  const mock = await startupLineOnFreePort({});
  assert.equal(mock.event, "listening");
  assert.equal(mock.mode, "mock");
  assert.equal(mock.ownerClaim, "open");
  const live = await startupLineOnFreePort({ ...LIVE, DODDY_DEVICE_SIGNUP: "open", DODDY_HOST: "127.0.0.1" });
  assert.equal(live.mode, "live");
  assert.equal(live.ownerClaim, "closed");
  assert.ok(!JSON.stringify(live).includes(LIVE.DODDY_SESSION_SIGNING_KEY) && !JSON.stringify(live).includes("monid_"), "no secret in the line");
  const opened = await startupLineOnFreePort({ ...LIVE, DODDY_DEVICE_SIGNUP: "first-device", DODDY_OWNER_CLAIM: "open" });
  assert.equal(opened.ownerClaim, "open");
});

// ------------------------------------------------------------------ invite codes (ADR-709)

const CODE = "right-code-12345";
const OTHER_CODE = "other-code-67890";
const WRONG = "wrong-code-12345";

test("invite code tries count per client before the code is looked at: wrong ones run out, and then even the right one waits", async () => {
  const store = await freshStore();
  await store.claimDeviceOwner(deviceUserId(KEY, PHONE(1)), NOW.getTime());
  const i = issuer(store, { signup: "first-device", ownerClaim: "open", inviteCodes: [CODE], inviteLimits: { ...INVITE_LIMITS, triesPerClientPerHour: 3 } });
  const from = "203.0.113.7";
  for (let n = 0; n < 3; n++) {
    const wrong = await rejection(i.issue({ deviceId: PHONE(2), inviteCode: WRONG }, NOW, from));
    assert.equal(wrong.code, "unauthenticated", `try ${n + 1} is looked at`);
  }
  const limited = await rejection(i.issue({ deviceId: PHONE(2), inviteCode: WRONG }, NOW, from));
  assert.equal(limited.code, "rate_limited");
  assert.equal(limited.options.retryAfterSeconds, 3_600);

  // Out of tries: the right code from the same client waits too, or guessing would never stop.
  assert.equal((await rejection(i.issue({ deviceId: PHONE(3), inviteCode: CODE }, NOW, from))).code, "rate_limited");
  // Another network is not affected.
  assert.equal((await i.issue({ deviceId: PHONE(3), inviteCode: CODE }, NOW, "203.0.113.8")).access, "full");
  // The next hour starts afresh.
  assert.equal((await i.issue({ deviceId: PHONE(4), inviteCode: CODE }, new Date(NOW.getTime() + HOUR), from)).access, "full");
  // Signing in with no code is not a try.
  for (let n = 0; n < 5; n++) await rejection(i.issue({ deviceId: PHONE(5) }, NOW, "203.0.113.9"));
  assert.equal((await i.issue({ deviceId: PHONE(6), inviteCode: CODE }, NOW, "203.0.113.9")).access, "full");
});

test("parallel guesses can't get past the tries limit: each is counted before the code is read", async () => {
  const store = await freshStore();
  await store.claimDeviceOwner(deviceUserId(KEY, PHONE(1)), NOW.getTime());
  const i = issuer(store, { signup: "first-device", ownerClaim: "open", inviteCodes: [CODE], inviteLimits: { ...INVITE_LIMITS, triesPerClientPerHour: 3 } });
  const outcomes = await Promise.allSettled(Array.from({ length: 12 }, (_, n) => i.issue({ deviceId: PHONE(10 + n), inviteCode: n === 11 ? CODE : WRONG }, NOW, "203.0.113.7")));
  const codes = outcomes.map((o) => (o.status === "rejected" ? (o.reason as AppError).code : "ok"));
  assert.equal(codes.filter((c) => c === "rate_limited").length, 9, "only three of the twelve were looked at");
  assert.equal(codes.filter((c) => c === "unauthenticated").length + codes.filter((c) => c === "ok").length, 3);
});

test("one valid code makes only so many sessions a UTC day and signs in only so many iPhones, each code on its own", async () => {
  const store = await freshStore();
  const i = issuer(store, {
    signup: "off",
    ownerClaim: "open",
    inviteCodes: [CODE, OTHER_CODE],
    inviteLimits: { triesPerClientPerHour: 1_000, sessionsPerCodePerDay: 4, devicesPerCode: 2 },
  });
  const use = (n: number, code = CODE, at = NOW) => i.issue({ deviceId: PHONE(n), inviteCode: code }, at, "203.0.113.5");

  assert.equal((await use(1)).access, "full");
  assert.equal((await use(2)).access, "full");
  const third = await rejection(use(3));
  assert.equal(third.code, "unauthenticated");
  assert.equal(third.message, "This invite code is already in use on as many iPhones as it allows.");
  assert.equal((await use(1)).access, "full", "an iPhone the code already signed in may sign in again");
  assert.equal((await use(2)).access, "full");
  // Four sessions today (the refused third iPhone did not count): the fifth waits for tomorrow.
  const day = await rejection(use(1));
  assert.equal(day.code, "rate_limited");
  assert.equal(day.options.retryAfterSeconds, 14 * 3_600, "until the next UTC midnight");
  assert.match(day.message, /too many times today/);
  assert.equal(
    Number((await store.db.query<{ n: number | string }>("SELECT count(*) AS n FROM invite_devices WHERE user_id = $1", [deviceUserId(KEY, PHONE(3))])).rows[0]!.n),
    0,
    "an iPhone that was refused is not remembered",
  );

  // The other code has its own counts.
  assert.equal((await use(3, OTHER_CODE)).access, "full");

  // Tomorrow the day's count starts again; the number of iPhones is not a daily limit.
  const tomorrow = new Date(NOW.getTime() + 24 * HOUR);
  assert.equal((await use(1, CODE, tomorrow)).access, "full");
  assert.equal((await rejection(use(3, CODE, tomorrow))).code, "unauthenticated");

  // Deleting an iPhone's account frees its place (ADR-674 erases it).
  await store.eraseUser(deviceUserId(KEY, PHONE(2)), tomorrow.getTime());
  assert.equal((await use(3, CODE, tomorrow)).access, "full");
});

test("several iPhones at once with a code that has one place left: only one gets it", async () => {
  const store = await freshStore();
  const i = issuer(store, {
    signup: "off",
    ownerClaim: "open",
    inviteCodes: [CODE],
    inviteLimits: { triesPerClientPerHour: 1_000, sessionsPerCodePerDay: 100, devicesPerCode: 1 },
  });
  const outcomes = await Promise.allSettled(Array.from({ length: 6 }, (_, n) => i.issue({ deviceId: PHONE(20 + n), inviteCode: CODE }, NOW, `203.0.113.${n}`)));
  assert.equal(outcomes.filter((o) => o.status === "fulfilled").length, 1);
});

test("a valid code with no room left signs nobody more in, but locks out neither the owner nor a guest", async () => {
  const store = await freshStore();
  const owner = deviceUserId(KEY, PHONE(1));
  await store.claimDeviceOwner(owner, NOW.getTime()); // the server has an owner, and its phone sends the same code
  const limits = { triesPerClientPerHour: 1_000, sessionsPerCodePerDay: 100, devicesPerCode: 1 };
  for (const signup of ["open", "first-device"] as const) {
    await store.db.query("DELETE FROM invite_devices");
    const logs: Record<string, unknown>[] = [];
    const i = issuer(store, { signup, ownerClaim: "closed", inviteCodes: [CODE], inviteLimits: limits, log: (line) => logs.push(line) });
    const use = (n: number, at = NOW) => i.issue({ deviceId: PHONE(n), inviteCode: CODE }, at, "203.0.113.5");

    assert.equal((await use(2)).access, "full", `${signup}: the code's one place`);
    // Full now. The owner's own iPhone brings the same code and is still the owner.
    const mine = await use(1);
    assert.equal(mine.access, "full", `${signup}: the owner is not turned away by someone else's use of the code`);
    assert.equal(userOfToken(mine.token), owner);
    // Another iPhone: a guest where there are guests, and a plain refusal where there are none.
    if (signup === "open") assert.equal((await use(3)).access, "ask");
    else assert.equal((await rejection(use(3))).message, "This invite code is already in use on as many iPhones as it allows.");
    // The iPhone that has the place still has it.
    assert.equal((await use(2)).access, "full");

    // The operator hears about it once in a while, and the line names neither the code nor anyone.
    await use(3, new Date(NOW.getTime() + 1_000)).catch(() => undefined);
    const full = logs.filter((l) => l.event === "invite_code_full");
    assert.equal(full.length, 1, `${signup}: one line, not one per sign-in`);
    assert.deepEqual(Object.keys(full[0]!).sort(), ["action", "event", "level", "limit"]);
    assert.equal(full[0]!.limit, "iphones");
    for (const secret of [CODE, PHONE(3), deviceUserId(KEY, PHONE(3)), "203.0.113"]) assert.ok(!JSON.stringify(logs).includes(secret), `no ${secret} in the log`);
  }

  // The day's sessions (a code of its own, so its count starts at none): an iPhone that used them up is a
  // guest for the rest of the day, not an error, and the owner is still the owner.
  const day = issuer(store, { signup: "open", ownerClaim: "closed", inviteCodes: [OTHER_CODE], inviteLimits: { ...limits, devicesPerCode: 5, sessionsPerCodePerDay: 1 } });
  const withOther = (n: number) => day.issue({ deviceId: PHONE(n), inviteCode: OTHER_CODE }, NOW, "203.0.113.6");
  assert.equal((await withOther(4)).access, "full");
  assert.equal((await withOther(4)).access, "ask");
  assert.equal((await withOther(1)).access, "full", "and the owner is the owner");
});

test("the server keeps neither an invite code nor a client address: its counters are keyed with the server's secret or hashed", async () => {
  const store = await freshStore();
  const i = issuer(store, { signup: "off", ownerClaim: "open", inviteCodes: [CODE] });
  await i.issue({ deviceId: PHONE(1), inviteCode: CODE }, NOW, "203.0.113.77");
  await rejection(i.issue({ deviceId: PHONE(2), inviteCode: WRONG }, NOW, "203.0.113.77"));
  const kept = JSON.stringify([
    ...(await store.db.query("SELECT * FROM usage")).rows,
    ...(await store.db.query("SELECT * FROM invite_devices")).rows,
  ]);
  for (const secret of [CODE, WRONG, "203.0.113", PHONE(1)]) assert.ok(!kept.includes(secret), `no ${secret} in the stored counters`);
  assert.match(kept, /invite_sessions:/);
  assert.match(kept, /invite_tries:/);
});

// ------------------------------------------------------------------ over HTTP

async function deviceRoute(i: DeviceSessionIssuer, store: Store, maxBodyBytes = testLimits().maxBodyBytes) {
  const common = { store, limits: testLimits(), publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return" };
  const handler = createHandler({
    service: new ConnectedAppsService({ ...common, provider: new MockCalendarProvider(), registry: defaultRegistry(), completionMode: "mock" }),
    verifier: new SignedSessionVerifier(KEY),
    deviceSessions: i,
    appReturnUrl: common.appReturnUrl,
    maxBodyBytes,
    log: () => {},
  });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  servers.push(server);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return (body: unknown) => fetch(`${base}/v1/session/device`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
}

test("over HTTP: too many tries is a 429 with Retry-After, and an oversized body is refused before it is read", async () => {
  const store = await freshStore();
  await store.claimDeviceOwner(deviceUserId(KEY, PHONE(1)), Date.now());
  const i = issuer(store, { signup: "first-device", ownerClaim: "open", inviteCodes: [CODE], inviteLimits: { ...INVITE_LIMITS, triesPerClientPerHour: 1 } });
  const post = await deviceRoute(i, store, 24 * 1024);
  // The clock is the real one here, so every request falls in the same hour.
  assert.equal((await post({ deviceId: PHONE(2), inviteCode: WRONG })).status, 401);
  const limited = await post({ deviceId: PHONE(2), inviteCode: WRONG });
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "3600");
  assert.equal(((await limited.json()) as any).error.code, "rate_limited");

  // Every body is capped before JSON.parse and before zod sees it (ADR-709 note on the zod advisory).
  const huge = await post({ deviceId: PHONE(3), pad: "x".repeat(25 * 1024) });
  assert.equal(huge.status, 413);
  assert.equal(((await huge.json()) as any).error.code, "payload_too_large");
});
