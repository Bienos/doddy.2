// Adaptive idle polling (research item 7): the back-off, the reset on work, the wake-ups, the bound for jobs that
// are due, and the database notification path. The loops run on a fake clock, so an hour takes milliseconds.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { enqueue } from "../src/outbox.js";
import {
  DEFAULT_IDLE_POLL, IdleBackoff, idlePollFromEnv, runAdaptiveLoop, WakeBus, type IdlePollConfig, type PassResult, type WaitClock,
} from "../src/idlePoll.js";
import type { Db } from "../src/db.js";
import { startWakeListener, WAKE_CHANNEL } from "../src/wake.js";
import { runWorkerLoop } from "../src/workerLoop.js";
import { testCipher } from "./helpers.js";
import { dbSkip, FakePush, freshDb, testApp } from "./helpers.js";

/** Virtual time: `sleep` registers a timer; `runUntil` fires timers in order, letting the loop run between them. */
class FakeClock implements WaitClock {
  t = 0;
  private timers: { at: number; fire: () => void }[] = [];
  now = () => this.t;
  sleep(ms: number) {
    let resolve!: () => void;
    const done = new Promise<void>((r) => { resolve = r; });
    const timer = { at: this.t + ms, fire: () => resolve() };
    this.timers.push(timer);
    return { done, cancel: () => { this.timers = this.timers.filter((x) => x !== timer); resolve(); } };
  }
  private flush = () => new Promise<void>((r) => setImmediate(r));
  async runUntil(end: number) {
    for (;;) {
      await this.flush();
      const next = this.timers.filter((x) => x.at <= end).sort((a, b) => a.at - b.at)[0];
      if (!next) break;
      this.timers = this.timers.filter((x) => x !== next);
      this.t = next.at;
      next.fire();
    }
    this.t = end;
    await this.flush();
  }
}

const HOUR = 3_600_000;
const FIXED: IdlePollConfig = { minMs: 2000, maxMs: 2000, maxMsWithoutWake: 2000, factor: 2 }; // the old behaviour

interface Run { passes: number[]; stop(): void; done: Promise<number> }
function start(clock: FakeClock, bus: WakeBus, config: IdlePollConfig, pass: () => PassResult | Promise<PassResult>): Run {
  let stopping = false;
  const passes: number[] = [];
  const done = runAdaptiveLoop({
    topic: "dispatch", config, bus, clock, shouldStop: () => stopping,
    pass: async () => { passes.push(clock.t); return pass(); },
  });
  return { passes, stop: () => { stopping = true; }, done };
}

describe("settings", () => {
  test("defaults keep the 2 s first look and a 30 s ceiling", () => {
    assert.deepEqual(idlePollFromEnv({}), DEFAULT_IDLE_POLL);
    assert.deepEqual(DEFAULT_IDLE_POLL, { minMs: 2000, maxMs: 30_000, maxMsWithoutWake: 6000, factor: 2 });
  });
  test("environment values are used when in range; nonsense falls back, so a typo can't spin or stall the loop", () => {
    assert.deepEqual(idlePollFromEnv({ IDLE_POLL_MIN_MS: "1000", IDLE_POLL_MAX_MS: "60000", IDLE_POLL_MAX_MS_NO_WAKE: "4000", IDLE_POLL_FACTOR: "3" }),
      { minMs: 1000, maxMs: 60_000, maxMsWithoutWake: 4000, factor: 3 });
    assert.deepEqual(idlePollFromEnv({ IDLE_POLL_MIN_MS: "5", IDLE_POLL_MAX_MS: "abc", IDLE_POLL_FACTOR: "1" }), DEFAULT_IDLE_POLL);
    assert.deepEqual(idlePollFromEnv({ IDLE_POLL_MAX_MS: "9999999" }), DEFAULT_IDLE_POLL);
    // The no-wake cap is never above the main cap.
    assert.equal(idlePollFromEnv({ IDLE_POLL_MAX_MS: "4000", IDLE_POLL_MAX_MS_NO_WAKE: "30000" }).maxMsWithoutWake, 4000);
    // Max equal to min is plain fixed polling.
    assert.equal(idlePollFromEnv({ IDLE_POLL_MAX_MS: "2000" }).maxMs, 2000);
  });
});

describe("the back-off", () => {
  test("2, 4, 8, 16 s and then the 30 s ceiling; work resets it at once", () => {
    const b = new IdleBackoff(DEFAULT_IDLE_POLL, () => true);
    assert.deepEqual([1, 2, 3, 4, 5, 6].map(() => b.idle()), [2000, 4000, 8000, 16_000, 30_000, 30_000]);
    assert.equal(b.reset(), 2000);
    assert.equal(b.idle(), 2000);
    assert.equal(b.idle(), 4000);
  });
  test("without working wake-ups the wait is capped at the short fallback", () => {
    const b = new IdleBackoff(DEFAULT_IDLE_POLL, () => false);
    assert.deepEqual([1, 2, 3, 4, 5].map(() => b.idle()), [2000, 4000, 6000, 6000, 6000]);
  });
});

describe("the adaptive loop on a fake clock", () => {
  test("an idle hour: passes drop from 1800 to about a hundred", async () => {
    const before = new FakeClock();
    const old = start(before, new WakeBus(), FIXED, () => ({ busy: false }));
    await before.runUntil(HOUR);
    old.stop(); await before.runUntil(HOUR + 40_000); await old.done;

    const now = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    const adaptive = start(now, bus, DEFAULT_IDLE_POLL, () => ({ busy: false }));
    await now.runUntil(HOUR);
    adaptive.stop(); await now.runUntil(HOUR + 40_000); await adaptive.done;

    const oldPasses = old.passes.filter((t) => t <= HOUR).length;
    const newPasses = adaptive.passes.filter((t) => t <= HOUR).length;
    console.log(`idle polling, one simulated hour: fixed 2 s = ${oldPasses} passes, adaptive = ${newPasses} passes (${Math.round((1 - newPasses / oldPasses) * 100)}% fewer)`);
    assert.ok(oldPasses >= 1799 && oldPasses <= 1801);
    assert.ok(newPasses <= 125, `got ${newPasses}`);
    assert.deepEqual(adaptive.passes.slice(0, 6), [0, 2000, 6000, 14_000, 30_000, 60_000], "2, 4, 8, 16, 30 s");
  });

  test("a pass that finds work resets the wait to 2 s", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    let busyUntil = 0;
    const run = start(clock, bus, DEFAULT_IDLE_POLL, () => ({ busy: clock.t >= 100_000 && clock.t < busyUntil || clock.t === 90_000 }));
    busyUntil = 110_000;
    await clock.runUntil(150_000);
    run.stop(); await clock.runUntil(300_000); await run.done;
    const gaps = run.passes.slice(1).map((t, i) => t - run.passes[i]!);
    const at90 = run.passes.indexOf(90_000);
    assert.ok(at90 > 0);
    assert.equal(gaps[at90], 2000, "the pass that found work is followed by a 2 s wait");
    assert.equal(gaps[at90 + 1], 2000, "and the wait only grows again if the next pass finds nothing (it stays 2 s while busy)");
  });

  test("a wake ends a long wait at once and resets the back-off, so queued work waits milliseconds, not 30 s", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    const run = start(clock, bus, DEFAULT_IDLE_POLL, () => ({ busy: false }));
    await clock.runUntil(100_000); // well into the 30 s waits
    const before = run.passes.length;
    bus.wake("dispatch"); // something was queued at t = 100 s
    await clock.runUntil(100_000);
    assert.equal(run.passes.length, before + 1, "a pass ran immediately");
    assert.equal(run.passes.at(-1), 100_000, "at the moment of the wake");
    await clock.runUntil(102_000);
    assert.equal(run.passes.at(-1), 102_000, "the next wait is back to 2 s");
    run.stop(); await clock.runUntil(300_000); await run.done;
  });

  test("a wake that arrives while a pass is running is not slept through", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    let first = true;
    const run = start(clock, bus, DEFAULT_IDLE_POLL, async () => {
      if (first) { first = false; bus.wake("dispatch"); } // queued just after this pass looked
      return { busy: false };
    });
    await clock.runUntil(0);
    assert.deepEqual(run.passes, [0, 0], "the second pass ran at once");
    run.stop(); await clock.runUntil(100_000); await run.done;
  });

  test("a wake for another topic does nothing", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    const run = start(clock, bus, DEFAULT_IDLE_POLL, () => ({ busy: false }));
    await clock.runUntil(100_000);
    const n = run.passes.length;
    bus.wake("errand");
    await clock.runUntil(100_000);
    assert.equal(run.passes.length, n);
    run.stop(); await clock.runUntil(300_000); await run.done;
  });

  test("a job already known to be due soon is not waited past: the wait stops at its due time", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    const dueAt = 77_000; // a message queued for later
    const run = start(clock, bus, DEFAULT_IDLE_POLL, () => ({ busy: false, dueInMs: clock.t < dueAt ? dueAt - clock.t : null }));
    await clock.runUntil(80_000);
    assert.ok(run.passes.includes(dueAt), `a pass ran exactly at the due time: ${run.passes.join(",")}`);
    run.stop(); await clock.runUntil(300_000); await run.done;
  });

  test("a due time that is already past (held by another worker) never makes a busy loop", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    const run = start(clock, bus, DEFAULT_IDLE_POLL, () => ({ busy: false, dueInMs: 0 }));
    await clock.runUntil(10_000);
    assert.ok(run.passes.length <= 40 + 1, `${run.passes.length} passes in 10 s`);
    run.stop(); await clock.runUntil(300_000); await run.done;
  });

  test("with the wake listener down the longest wait is the 6 s fallback, so new work waits at most 6 s", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); // never healthy
    const waits: number[] = [];
    let stopping = false;
    const done = runAdaptiveLoop({ topic: "dispatch", config: DEFAULT_IDLE_POLL, bus, clock, shouldStop: () => stopping,
      pass: async () => ({ busy: false }), onWait: (ms) => waits.push(ms) });
    await clock.runUntil(120_000);
    stopping = true; await clock.runUntil(300_000); await done;
    assert.ok(Math.max(...waits) === 6000, `longest wait ${Math.max(...waits)}`);
    bus.setHealthy(true);
  });

  test("a busy pass that asks to go again does not wait at all", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    let n = 0;
    const run = start(clock, bus, DEFAULT_IDLE_POLL, () => (++n < 5 ? { busy: true, again: true } : { busy: false }));
    await clock.runUntil(0);
    assert.deepEqual(run.passes, [0, 0, 0, 0, 0]);
    run.stop(); await clock.runUntil(100_000); await run.done;
  });

  test("shutdown during a long wait is noticed within a second", async () => {
    const clock = new FakeClock();
    const bus = new WakeBus(); bus.setHealthy(true);
    const run = start(clock, bus, DEFAULT_IDLE_POLL, () => ({ busy: false }));
    await clock.runUntil(100_000);
    run.stop();
    await clock.runUntil(101_001);
    assert.equal(typeof (await run.done), "number");
  });
});

describe("database notifications", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  test("queuing a message notifies the dispatch topic when it commits; an errand and a future-dated message behave", async () => {
    const bus = new WakeBus();
    const heard: string[] = [];
    bus.on("dispatch", () => heard.push("dispatch"));
    bus.on("errand", () => heard.push("errand"));
    const listener = startWakeListener(db, bus, () => {}, () => false);
    try {
      for (let i = 0; i < 100 && !bus.isHealthy(); i++) await new Promise((r) => setTimeout(r, 20));
      assert.ok(bus.isHealthy(), "the listener is connected");
      heard.length = 0;
      const { app } = await testApp(db, {});
      const r = await app.inject({ method: "POST", url: "/v1/accounts" });
      const { accountId } = r.json() as { accountId: string };
      await enqueue(db, accountId, ["push"], "hello", new Date(), "wake-test-1", {});
      for (let i = 0; i < 100 && !heard.includes("dispatch"); i++) await new Promise((r) => setTimeout(r, 20));
      assert.ok(heard.includes("dispatch"), "an immediate message wakes the dispatch loop");
      // A notification carries only a topic: a stray payload is ignored.
      heard.length = 0;
      await db.query(`SELECT pg_notify('${WAKE_CHANNEL}', 'drop table accounts')`);
      await new Promise((r) => setTimeout(r, 150));
      assert.deepEqual(heard, []);
    } finally {
      await listener.stop();
    }
    assert.equal(bus.isHealthy(), false, "stopped: back to the short cap");
  });

  test("a listener that can't connect reports unhealthy and does not throw", async () => {
    const bus = new WakeBus();
    const broken = { connect: async () => { throw Object.assign(new Error("down"), { code: "ECONNREFUSED" }); } } as unknown as Db;
    const logs: string[] = [];
    const listener = startWakeListener(broken, bus, (m) => logs.push(m), () => false);
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(bus.isHealthy(), false);
    assert.equal(logs.length, 1);
    await listener.stop();
  });

  test("the real worker loop in a long idle wait sends a message queued by another connection within about a second", { timeout: 20_000 }, async () => {
    const { app } = await testApp(db, {});
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: "10.77.0.1" });
    const { deviceToken } = r.json() as { deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    await app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h, payload: { token: "ab".repeat(32), environment: "sandbox" } });
    const push = new FakePush();
    let stop = false;
    const waits: Record<string, number[]> = { dispatch: [] };
    // First look after 0.5 s, then waits of 4 s and 32 s: without a wake-up the message below would wait several seconds.
    const loop = runWorkerLoop(db, { push, cipher: testCipher, news: { feeds: { fetchFeed: async () => ({ title: "x", items: [] }) } },
      idlePoll: { minMs: 500, maxMs: 60_000, maxMsWithoutWake: 60_000, factor: 8 }, onPass: (l) => waits[l]?.push(Date.now()) }, () => stop);
    await new Promise((res) => setTimeout(res, 1200)); // into the 4 s wait
    const queuedAt = Date.now();
    assert.equal((await app.inject({ method: "POST", url: "/v1/updates", headers: h,
      payload: { text: "woken", channels: ["push"], idempotencyKey: "idle-wake-1" } })).statusCode, 202);
    while (!push.sent.some((p) => p.body === "woken") && Date.now() < queuedAt + 3000) await new Promise((res) => setTimeout(res, 20));
    const delay = Date.now() - queuedAt;
    stop = true;
    await loop;
    assert.ok(push.sent.some((p) => p.body === "woken"), "sent");
    assert.ok(delay < 1500, `sent ${delay} ms after it was queued`);
    assert.ok(waits.dispatch!.length <= 6, "and the loop was not polling at 2 s meanwhile");
  });
});
