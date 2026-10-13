import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { CLEANUP_RETRY, Store } from "../src/store.js";
import { CAL, FakeComposio, type Harness, harness, liveProvider } from "./helpers.js";
import { type Rig, start as startTools } from "./toolsRig.js";

// Audit 2026-10-12 §5 #4: a sign-in that ends without being completed through Doddy (superseded,
// abandoned, or finished at the provider after the attempt expired) must not leave a live grant
// that no one tracks. Each case below fails on the code before the fix.

let h: Harness | undefined;
let rig: Rig | undefined;
afterEach(async () => {
  await h?.close();
  await rig?.close();
  h = undefined;
  rig = undefined;
});

const TTL_MS = 600_000;
const HOUR = 3_600_000;

async function begin(h: Harness, fake: FakeComposio) {
  const res = await h.call("POST", `${CAL}/connect`, { body: {} });
  assert.equal(res.status, 200, res.text);
  const pending = [...fake.accounts.keys()].at(-1)!;
  return { ...res.body, pending } as { attemptId: string; nonce: string; pending: string };
}

const complete = (h: Harness, s: { attemptId: string; nonce: string; pending: string }) =>
  h.call("POST", `${CAL}/complete`, {
    body: { attemptId: s.attemptId, nonce: s.nonce, result: { kind: "callback", status: "success", connectedAccountId: s.pending } },
  });

const cleanupRows = (store: Store) => store.db.prepare("SELECT * FROM cleanups").all() as { connection_id: string; state: string; attempts: number }[];

test("finished at Google after the attempt expired: the late completion is refused and the grant removed", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await begin(h, fake);
  h.clock.advance(TTL_MS + 1_000);
  fake.activate(s.pending); // the user finished consent late
  const late = await complete(h, s);
  assert.equal(late.body.error.code, "attempt_invalid");
  assert.ok(!fake.accounts.has(s.pending), "the late grant is gone at the provider");
  assert.equal((await h.call("GET", CAL)).body.status, "disconnected");
  assert.equal(cleanupRows(h.store).length, 0);
});

test("abandoned: the user never comes back to Doddy; the hourly sweep removes the grant before prune forgets it", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await begin(h, fake);
  fake.activate(s.pending); // finished in the browser, but the app never completed
  h.clock.advance(TTL_MS + 1_000);
  await h.service.sweepAbandoned();
  assert.ok(!fake.accounts.has(s.pending));
  // A day later prune drops the attempt row; nothing is left queued or live.
  h.clock.advance(25 * HOUR);
  h.store.prune(h.clock.ms);
  assert.equal(cleanupRows(h.store).length, 0);
  assert.equal(h.store.db.prepare("SELECT COUNT(*) AS n FROM attempts").get()!.n, 0);
});

test("the sweep leaves open attempts and recorded connections alone", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await begin(h, fake);
  await h.service.sweepAbandoned(); // not expired yet
  assert.ok(fake.accounts.has(s.pending), "an attempt still open keeps its link");
  fake.activate(s.pending);
  assert.equal((await complete(h, s)).status, 200);
  h.clock.advance(TTL_MS + HOUR);
  await h.service.sweepAbandoned();
  assert.ok(fake.accounts.has(s.pending), "a completed connection is never swept");
  assert.equal((await h.call("GET", CAL)).body.status, "connected");
  assert.ok(!fake.calls.includes("delete"));
});

test("a removal that fails stays queued and visible, and the sweep retries it until it works", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await begin(h, fake);
  fake.activate(s.pending);
  h.clock.advance(TTL_MS + 1_000);
  fake.deleteFails = true;
  await h.service.sweepAbandoned();
  assert.ok(fake.accounts.has(s.pending));
  assert.equal((await h.call("GET", CAL)).body.remoteCleanup, "failed");
  fake.deleteFails = false;
  h.clock.advance(HOUR);
  await h.service.sweepAbandoned();
  assert.ok(!fake.accounts.has(s.pending), "retried on the next sweep");
  assert.equal((await h.call("GET", CAL)).body.remoteCleanup, "none");
});

test("the sweep stops retrying a removal after a day of failures; the row stays visible", () => {
  const store = new Store(":memory:");
  try {
    store.queueCleanup("ca_stuck", "u1", "google_calendar", 0);
    for (let i = 0; i < CLEANUP_RETRY.maxTries; i++) store.failCleanup("ca_stuck", "remote_cleanup_failed");
    assert.deepEqual(store.cleanupsToRetry(["google_calendar"], HOUR, CLEANUP_RETRY.maxTries, 20), []);
    assert.equal(store.cleanupFor("u1", "google_calendar")?.state, "failed");
  } finally {
    store.close();
  }
});

test("a link made for an attempt that was superseded meanwhile is queued for removal, never stored on it", () => {
  const store = new Store(":memory:");
  try {
    store.composioUserId("u1", 0);
    const a = store.createAttempt({ userId: "u1", provider: "google_calendar", authConfigId: "ac", now: 0, ttlSeconds: 600 });
    const b = store.createAttempt({ userId: "u1", provider: "google_calendar", authConfigId: "ac", now: 1, ttlSeconds: 600 });
    assert.deepEqual(b.superseded, [], "a had no link yet");
    assert.equal(store.setPendingConnection(a.attemptId, "ca_late_link", 2), false);
    assert.deepEqual(cleanupRows(store).map((r) => r.connection_id), ["ca_late_link"]);
    assert.equal(store.setPendingConnection(b.attemptId, "ca_b", 3), true);
  } finally {
    store.close();
  }
});

test("online-account tools: a superseded Gmail sign-in and an abandoned one are both removed", async () => {
  rig = await startTools();
  const first = await rig.call("POST", "/v1/tools/gmail/connect", { body: {} });
  assert.equal(first.status, 200, first.text);
  const second = await rig.call("POST", "/v1/tools/gmail/connect", { body: {} });
  assert.equal(second.status, 200, second.text);
  assert.equal(rig.provider.calls.filter((c) => c === "removeConnection").length, 1, "the superseded link was removed");
  rig.clock.advance(TTL_MS + 1_000);
  await rig.tools.sweepAbandoned();
  assert.equal(rig.provider.calls.filter((c) => c === "removeConnection").length, 2, "the abandoned one too");
  assert.equal(cleanupRows(rig.store).length, 0);
});
