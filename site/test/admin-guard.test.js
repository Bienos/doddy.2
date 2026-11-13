// Sign-in attempts on the waitlist admin routes are limited per client address (api/_admin-guard.js),
// counted in the waitlist's Blob store before any password is compared.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { beforeEach, test } from "node:test";
import { basic, hooks, reset, store } from "./fake-blob.js";

const RIGHT = "correct-horse-battery";
process.env.WAITLIST_ADMIN_PASSWORD = RIGHT;
process.env.VERCEL = "1";
const admin = await import("../api/waitlist-admin.js");
const { GET: exportCsv } = await import("../api/waitlist-export.js");
const guard = await import("../api/_admin-guard.js");

const START = Date.parse("2026-11-12T10:00:00Z");
const A = "203.0.113.7";
const B = "198.51.100.20";

const request = (address, password, { url = "/api/waitlist-admin", method = "GET" } = {}) => {
  const headers = {};
  if (address) headers["x-vercel-forwarded-for"] = address;
  if (password !== undefined) headers.authorization = basic(password);
  return new Request(`https://doddy.test${url}`, { method, headers });
};
const list = (address, password) => admin.GET(request(address, password));
const quiet = () => new Promise((resolve) => setImmediate(resolve));
const guardRecords = () => [...store.keys()].filter((key) => key.startsWith(guard.PREFIX));

// Fake clock and timers; the wrong-password delay (750 ms) runs out by itself, moving the clock with it.
function clock(t) {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: START });
  const warnings = [];
  t.mock.method(console, "warn", (...args) => warnings.push(JSON.parse(args.join(" "))));
  const answer = async (pending) => {
    let response;
    pending.then((r) => { response = r; });
    for (let i = 0; i < 50 && !response; i++) {
      await quiet();
      t.mock.timers.runAll();
    }
    assert.ok(response, "answered");
    return response;
  };
  const events = () => warnings.map((w) => w.event);
  return { answer, warnings, events, tick: (ms) => t.mock.timers.tick(ms) };
}

beforeEach(reset);

test("five wrong passwords lock that address out for 15 minutes, and then even the right one is not compared", async (t) => {
  const { answer, events, tick } = clock(t);
  for (let i = 1; i <= 4; i++) assert.equal((await answer(list(A, `wrong-${i}`))).status, 401, `try ${i}`);
  const fifth = await answer(list(A, "wrong-5"));
  assert.equal(fifth.status, 429);
  assert.equal(fifth.headers.get("retry-after"), "900");
  assert.deepEqual(await fifth.json(), { ok: false, error: "too_many_attempts", retryAfter: 900 });

  // Locked: answered at once (nothing to slow down: no password is compared), and the right one doesn't help.
  const locked = await Promise.race([list(A, RIGHT), quiet().then(() => "still waiting")]);
  assert.notEqual(locked, "still waiting");
  assert.equal(locked.status, 429);
  assert.ok(Number(locked.headers.get("retry-after")) <= 900 && Number(locked.headers.get("retry-after")) >= 899);
  assert.deepEqual(events(), [...Array(5).fill("waitlist_admin_login_failed"), "waitlist_admin_locked_out"]);

  // Another address is not affected.
  assert.equal((await answer(list(B, RIGHT))).status, 200);

  // Still locked a second before the 15 minutes are up; open after them.
  tick(15 * 60 * 1000 - 1000);
  assert.equal((await answer(list(A, RIGHT))).status, 429);
  tick(1000);
  assert.equal((await answer(list(A, RIGHT))).status, 200);
  assert.deepEqual(guardRecords(), [], "the right password removes the address's record");
});

test("the export and the admin list share one count per address", async (t) => {
  const { answer } = clock(t);
  for (let i = 1; i <= 4; i++) {
    assert.equal((await answer(exportCsv(request(A, "wrong", { url: "/api/waitlist-export" })))).status, 401);
  }
  const last = await answer(admin.DELETE(request(A, "wrong", { url: `/api/waitlist-admin?id=${"a".repeat(64)}`, method: "DELETE" })));
  assert.equal(last.status, 429);
  const exported = await answer(exportCsv(request(A, RIGHT, { url: "/api/waitlist-export" })));
  assert.equal(exported.status, 429);
});

test("the right password starts the count again", async (t) => {
  const { answer } = clock(t);
  for (let i = 0; i < 4; i++) assert.equal((await answer(list(A, "wrong"))).status, 401);
  assert.equal((await answer(list(A, RIGHT))).status, 200);
  for (let i = 0; i < 4; i++) assert.equal((await answer(list(A, "wrong"))).status, 401, "four more wrong ones are still allowed");
  assert.equal((await answer(list(A, "wrong"))).status, 429, "the fifth since the right one locks");
});

test("wrong passwords older than 15 minutes stop counting", async (t) => {
  const { answer, tick } = clock(t);
  for (let i = 0; i < 4; i++) assert.equal((await answer(list(A, "wrong"))).status, 401);
  tick(15 * 60 * 1000);
  for (let i = 0; i < 4; i++) assert.equal((await answer(list(A, "wrong"))).status, 401, "the old four have left the window");
  assert.equal((await answer(list(A, "wrong"))).status, 429);
});

test("attempts sent at once from one address are each counted before their password is compared", async (t) => {
  const { answer, events } = clock(t);
  const responses = await Promise.all(Array.from({ length: 20 }, (_, i) => answer(list(A, `wrong-${i}`))));
  const compared = events().filter((e) => e === "waitlist_admin_login_failed").length;
  const [record] = guardRecords();
  const { tries } = JSON.parse(store.get(record).body);
  assert.ok(compared >= 1 && compared <= guard.MAX_TRIES, `${compared} passwords compared`);
  assert.equal(tries.length, compared, "every compared password was counted first");
  for (const response of responses) assert.ok([401, 429].includes(response.status), `status ${response.status}`);
  assert.equal(responses.filter((r) => r.status === 401).length + responses.filter((r) => r.status === 429).length, 20);
});

test("when the attempt can't be counted, nothing is compared: 503 at once, with no delay", async (t) => {
  const { events } = clock(t);
  hooks.beforeGet = () => { throw new Error("store down"); };
  for (const password of [RIGHT, "wrong"]) {
    const response = await Promise.race([list(A, password), quiet().then(() => "still waiting")]);
    assert.notEqual(response, "still waiting");
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { ok: false, error: "unavailable" });
  }
  assert.deepEqual(events(), ["waitlist_admin_guard_unavailable", "waitlist_admin_guard_unavailable"]);
});

test("a request without credentials is not counted and touches nothing", async (t) => {
  const { answer } = clock(t);
  for (let i = 0; i < 10; i++) assert.equal((await answer(list(A))).status, 401);
  assert.deepEqual(guardRecords(), []);
  assert.equal((await answer(list(A, RIGHT))).status, 200);
});

test("the store holds neither the address nor the password: an HMAC for a name, times for a body", async (t) => {
  const { answer, warnings } = clock(t);
  await answer(list(A, "wrong-password-xyz"));
  const [name, ...others] = guardRecords();
  assert.deepEqual(others, []);
  assert.equal(name, guard.recordName(RIGHT, A));
  assert.match(name, /^admin-guard\/[0-9a-f]{64}\.json$/);
  const plainHash = createHash("sha256").update(A).digest("hex");
  const body = store.get(name).body;
  for (const secret of [A, plainHash, RIGHT, "wrong-password-xyz"]) {
    assert.ok(!name.includes(secret) && !body.includes(secret), `stored ${secret}`);
  }
  assert.deepEqual(JSON.parse(body), { tries: [START], lockedUntil: 0 });
  assert.ok(!JSON.stringify(warnings).includes(A), "no address in the log");
});

test("an IPv6 /64 is one address, an IPv4 address seen through IPv6 is that address, and off Vercel nobody has one", () => {
  const at = (header, env = { VERCEL: "1" }) =>
    guard.clientAddress(new Request("https://doddy.test/", { headers: header ? { "x-vercel-forwarded-for": header } : {} }), env);
  assert.equal(at("2001:db8:1:2:aaaa::1"), "2001:db8:1:2::/64");
  assert.equal(at("2001:0db8:0001:0002:bbbb:cccc:dddd:eeee"), "2001:db8:1:2::/64");
  assert.equal(at("::ffff:203.0.113.7"), A);
  assert.equal(at(`${A}, 10.0.0.1`), A, "the first address Vercel lists");
  assert.equal(at("not an address"), "unknown");
  assert.equal(at(undefined), "unknown");
  assert.equal(at(A, {}), "unknown", "the header means nothing off Vercel");
});

test("addresses in one IPv6 /64 share a count", async (t) => {
  const { answer } = clock(t);
  for (let i = 1; i <= 4; i++) assert.equal((await answer(list(`2001:db8:1:2::${i}`, "wrong"))).status, 401);
  assert.equal((await answer(list("2001:db8:1:2:ffff::9", "wrong"))).status, 429);
});

test("without a usable address everyone shares one bucket, with ten times the limit", async () => {
  let at = START;
  const now = () => at++;
  for (let i = 1; i < 50; i++) assert.equal((await guard.takeAttempt(RIGHT, "unknown", now)).locked, false, `try ${i}`);
  const last = await guard.takeAttempt(RIGHT, "unknown", now);
  assert.equal(last.locked, false);
  assert.equal(last.lockedNow, true);
  assert.equal((await guard.takeAttempt(RIGHT, "unknown", now)).locked, true);
});

test("a signed-in list deletes attempt records nobody wrote to for 30 minutes, and nothing else", async (t) => {
  const { answer } = clock(t);
  const old = new Date(START - 31 * 60 * 1000);
  store.set(`${guard.PREFIX}old.json`, { body: "{}", etag: '"o"', uploadedAt: old });
  store.set(`${guard.PREFIX}recent.json`, { body: "{}", etag: '"r"', uploadedAt: new Date(START - 60 * 1000) });
  store.set(`waitlist/${"a".repeat(64)}.json`, {
    body: JSON.stringify({ email: "ana@example.com", createdAt: "2026-10-11T10:00:00.000Z" }), etag: '"w"', uploadedAt: old,
  });
  const response = await answer(list(A, RIGHT));
  assert.equal(response.status, 200);
  const { records } = await response.json();
  assert.deepEqual(records.map((r) => r.email), ["ana@example.com"], "attempt records are never listed as signups");
  assert.deepEqual([...store.keys()].sort(), [`${guard.PREFIX}recent.json`, `waitlist/${"a".repeat(64)}.json`]);
});
