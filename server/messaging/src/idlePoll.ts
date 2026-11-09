// Adaptive idle polling for the worker's queue loops (research item 7).
//
// Before: the dispatch, errand and studio loops each looked at the database every 2 s all day (43,200 passes a
// day per loop) although a quiet server has nothing to do. Now a pass that finds no work doubles the wait
// (2 s, 4, 8, 16, then the configured maximum, 30 s by default); a pass that finds work resets it at once.
//
// What keeps new work from waiting for a long idle wait:
// - Wake-ups. The database tells the worker the moment a message, errand or studio job is queued (migration 027
//   triggers + LISTEN, src/wake.ts), and in-process callers can wake a loop directly. A wake ends the wait and
//   resets the back-off.
// - Known due times. A loop can say how long until the next job it already knows about is due (a message queued
//   for later); the wait never passes it.
// - The fallback bound. When the LISTEN connection is down the wake-ups can't be trusted, so the wait is
//   capped at `maxMsWithoutWake` (default 6 s) until it is back. So new work is delayed by at most:
//     wake-ups working: the notification's delivery time (milliseconds);
//     wake-ups down:    maxMsWithoutWake.
//
// Loops that must stay precise are NOT adaptive: scheduled calls (5 s) and task calls (2 s: dial times, the
// goodbye at the call's time limit, the kill switch, the half-joined watchdog) keep their fixed interval.
import { EventEmitter } from "node:events";

export interface IdlePollConfig {
  /** The wait after a pass that found work, and the first idle wait. Default 2000 (what the loops always used). */
  minMs: number;
  /** The longest idle wait while wake-ups work. Default 30000. */
  maxMs: number;
  /** The longest idle wait while wake-ups are down. Default 6000. */
  maxMsWithoutWake: number;
  /** Each idle pass multiplies the wait by this. Default 2. */
  factor: number;
}

export const DEFAULT_IDLE_POLL: IdlePollConfig = { minMs: 2_000, maxMs: 30_000, maxMsWithoutWake: 6_000, factor: 2 };

/** A setting that is not a plain number in range is ignored, so a typo can't make the loop spin or sleep for an hour. */
function intIn(raw: string | undefined, min: number, max: number, fallback: number): number {
  if (raw === undefined || raw.trim() === "" || !/^\d+$/.test(raw.trim())) return fallback;
  const n = Number(raw.trim());
  return n >= min && n <= max ? n : fallback;
}

/**
 * IDLE_POLL_MIN_MS (500..60000), IDLE_POLL_MAX_MS (min..300000), IDLE_POLL_MAX_MS_NO_WAKE (min..60000),
 * IDLE_POLL_FACTOR (2..8). IDLE_POLL_MAX_MS equal to IDLE_POLL_MIN_MS turns the back-off off: fixed polling as before.
 */
export function idlePollFromEnv(env: Record<string, string | undefined> = process.env): IdlePollConfig {
  const minMs = intIn(env.IDLE_POLL_MIN_MS, 500, 60_000, DEFAULT_IDLE_POLL.minMs);
  const maxMs = intIn(env.IDLE_POLL_MAX_MS, minMs, 300_000, Math.max(minMs, DEFAULT_IDLE_POLL.maxMs));
  const maxMsWithoutWake = Math.min(maxMs, intIn(env.IDLE_POLL_MAX_MS_NO_WAKE, minMs, 60_000, Math.max(minMs, DEFAULT_IDLE_POLL.maxMsWithoutWake)));
  return { minMs, maxMs, maxMsWithoutWake, factor: intIn(env.IDLE_POLL_FACTOR, 2, 8, DEFAULT_IDLE_POLL.factor) };
}

/** The wait after each pass. Pure state; the loop decides what "found work" means. */
export class IdleBackoff {
  private idleMs: number;
  constructor(private readonly cfg: IdlePollConfig, private readonly wakeHealthy: () => boolean = () => false) {
    this.idleMs = cfg.minMs;
  }

  /** A pass found work (or a wake arrived): the next wait is the shortest. */
  reset(): number {
    this.idleMs = this.cfg.minMs;
    return this.idleMs;
  }

  /** A pass found nothing: this wait, then a longer one next time, up to the maximum that is safe right now. */
  idle(): number {
    const cap = this.wakeHealthy() ? this.cfg.maxMs : this.cfg.maxMsWithoutWake;
    const wait = Math.min(this.idleMs, cap);
    this.idleMs = Math.min(this.idleMs * this.cfg.factor, this.cfg.maxMs);
    return wait;
  }
}

/** The shortest wait for a known due time. */
const DUE_FLOOR_MS = 250;

export type WakeTopic = "dispatch" | "errand" | "studio";

/** Wake-ups by topic, in this process: the LISTEN connection (src/wake.ts) and direct callers both end up here. */
export class WakeBus {
  private readonly events = new EventEmitter();
  /** Whether database notifications are being received. Until a listener says so, the short fallback cap applies. */
  private healthy = false;
  constructor() { this.events.setMaxListeners(50); }

  wake(topic: WakeTopic): void { this.events.emit(topic); }
  setHealthy(healthy: boolean): void { this.healthy = healthy; }
  isHealthy = (): boolean => this.healthy;
  on(topic: WakeTopic, fn: () => void): () => void {
    this.events.on(topic, fn);
    return () => this.events.off(topic, fn);
  }
}

/** The clock the loops wait with. The real one is `setTimeout`; tests drive a fake. */
export interface WaitClock {
  now(): number;
  /** Resolves after `ms`, or earlier when `cancel` is called. */
  sleep(ms: number): { done: Promise<void>; cancel(): void };
}

export const realClock: WaitClock = {
  now: () => Date.now(),
  sleep(ms) {
    let timer: ReturnType<typeof setTimeout>;
    let resolve!: () => void;
    const done = new Promise<void>((r) => { resolve = r; timer = setTimeout(r, ms); });
    return { done, cancel: () => { clearTimeout(timer); resolve(); } };
  },
};

/** What one pass of an adaptive loop reports. */
export interface PassResult {
  /** The pass found (or is still working on) something: no back-off. */
  busy: boolean;
  /** More is certainly waiting: pass again at once, without waiting. */
  again?: boolean;
  /** Milliseconds until the next job the loop already knows about is due; the wait never passes it. */
  dueInMs?: number | null;
}

export interface AdaptiveLoopOptions {
  topic: WakeTopic;
  pass: () => Promise<PassResult>;
  shouldStop: () => boolean;
  config: IdlePollConfig;
  bus: WakeBus;
  clock?: WaitClock;
  /** How often a long wait looks at `shouldStop`, so shutdown is quick. In-process only, no database work. Default 1000. */
  stopCheckMs?: number;
  /** Called with each wait, for measuring. */
  onWait?: (ms: number, why: "idle" | "busy" | "due") => void;
}

/**
 * Runs `pass` until `shouldStop()`, waiting between passes with the back-off above. A wake on `topic` ends the
 * wait early. Returns the number of passes made (each pass is one round of database work).
 */
export async function runAdaptiveLoop(o: AdaptiveLoopOptions): Promise<number> {
  const clock = o.clock ?? realClock;
  const backoff = new IdleBackoff(o.config, o.bus.isHealthy);
  const stopCheckMs = o.stopCheckMs ?? 1000;
  let woken = false;
  let cancelSleep: (() => void) | undefined;
  const off = o.bus.on(o.topic, () => { woken = true; cancelSleep?.(); });
  let passes = 0;
  try {
    while (!o.shouldStop()) {
      // A wake that arrives while the pass runs may be for work queued after the pass looked: it must not be slept through.
      woken = false;
      const r = await o.pass();
      passes++;
      if (o.shouldStop()) break;
      if (r.again || woken) { backoff.reset(); continue; }
      let wait: number;
      let why: "idle" | "busy" | "due";
      if (r.busy) { wait = backoff.reset(); why = "busy"; } else { wait = backoff.idle(); why = "idle"; }
      if (r.dueInMs !== undefined && r.dueInMs !== null && r.dueInMs < wait) {
        // Never a busy loop: a row that is due but held by another worker reports 0, so keep a small floor.
        wait = Math.max(Math.min(DUE_FLOOR_MS, wait), Math.ceil(r.dueInMs));
        why = "due";
      }
      o.onWait?.(wait, why);
      // The wait is cut into short slices so shutdown is noticed; a wake cancels the slice in progress.
      for (let left = wait; left > 0 && !woken && !o.shouldStop();) {
        const slice = Math.min(left, stopCheckMs);
        const s = clock.sleep(slice);
        cancelSleep = s.cancel;
        await s.done;
        cancelSleep = undefined;
        left -= slice;
      }
      if (woken) backoff.reset();
    }
  } finally {
    off();
  }
  return passes;
}
