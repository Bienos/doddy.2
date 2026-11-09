// LISTEN side of the worker's wake-ups (migration 027 NOTIFYs on a queued message, errand or studio job).
// Best effort by design: the loops still poll, only less often while idle. If this connection can't be made
// or drops, `bus.setHealthy(false)` makes them fall back to the short idle cap (idlePoll.ts), and it retries.
// Payloads are only the topic names; no row, id or text travels in a notification.
import type pg from "pg";
import type { Db } from "./db.js";
import type { WakeBus, WakeTopic } from "./idlePoll.js";

export const WAKE_CHANNEL = "doddy_work";
const TOPICS = new Set<string>(["dispatch", "errand", "studio"]);
const RETRY_MS = 15_000;

export interface WakeListener { stop(): Promise<void> }

export function startWakeListener(db: Db, bus: WakeBus, log: (msg: string, extra?: object) => void, shouldStop: () => boolean): WakeListener {
  let client: pg.PoolClient | undefined;
  let stopped = false;
  let retry: ReturnType<typeof setTimeout> | undefined;
  let lostLogged = false;

  const lost = (code: string) => {
    bus.setHealthy(false);
    if (client) { const c = client; client = undefined; c.removeAllListeners("notification"); c.release(true); } // true: drop the connection, never return it to the pool
    if (!lostLogged) { lostLogged = true; log("wake listener down, polling at the short interval", { code }); }
    if (!stopped && !shouldStop()) retry = setTimeout(connect, RETRY_MS);
  };

  async function connect() {
    if (stopped || shouldStop()) return;
    try {
      const c = await db.connect();
      client = c;
      c.on("notification", (m) => { if (m.channel === WAKE_CHANNEL && m.payload && TOPICS.has(m.payload)) bus.wake(m.payload as WakeTopic); });
      c.on("error", (err) => lost((err as { code?: string }).code ?? "error"));
      c.on("end", () => lost("end"));
      await c.query(`LISTEN ${WAKE_CHANNEL}`);
      bus.setHealthy(true);
      if (lostLogged) log("wake listener back");
      lostLogged = false;
      // Everything queued while the listener was down is picked up by one pass of every loop now.
      for (const t of TOPICS) bus.wake(t as WakeTopic);
    } catch (err) {
      lost((err as { code?: string }).code ?? (err as Error).name);
    }
  }

  void connect();
  return {
    async stop() {
      stopped = true;
      if (retry) clearTimeout(retry);
      bus.setHealthy(false);
      if (client) { const c = client; client = undefined; c.removeAllListeners(); c.release(true); }
    },
  };
}
