import { purgeExpiredSessions } from "./calls.js";
import type { TextCipher } from "./crypto.js";
import type { Db } from "./db.js";
import { runDueDigests, type NewsDeps } from "./news/digest.js";
import { pruneNewsCache } from "./news/sources.js";
import { dispatchDue } from "./outbox.js";
import type { PushSender, SmsSender } from "./providers/types.js";

export const log = (msg: string, extra: object = {}) =>
  console.log(JSON.stringify({ time: new Date().toISOString(), msg, ...extra }));

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Waits up to `ms`, checking `shouldStop` every second so shutdown isn't held up. */
async function pause(ms: number, shouldStop: () => boolean) {
  for (let waited = 0; waited < ms && !shouldStop(); waited += 1000) await sleep(Math.min(1000, ms - waited));
}

/**
 * Two independent loops until `shouldStop()`: one sends queued updates every ~2 s (plus hourly
 * tidying), the other builds due news digests. They are separate so a slow feed or AI call can't
 * hold back time-sensitive pushes such as a PIN-lock alert. Logs counts and ids only, never
 * message text or phone numbers. Safe to run more than once at a time: every job is claimed with
 * FOR UPDATE SKIP LOCKED.
 */
export async function runWorkerLoop(
  db: Db, deps: { push?: PushSender; sms?: SmsSender; cipher?: TextCipher; news: NewsDeps }, shouldStop: () => boolean,
): Promise<void> {
  await Promise.all([dispatchLoop(db, deps, shouldStop), digestLoop(db, deps.news, shouldStop)]);
}

async function dispatchLoop(db: Db, deps: { push?: PushSender; sms?: SmsSender; cipher?: TextCipher }, shouldStop: () => boolean) {
  let lastTidy = 0;
  while (!shouldStop()) {
    try {
      const r = await dispatchDue(db, { push: deps.push, sms: deps.sms, cipher: deps.cipher });
      if (Date.now() - lastTidy > 3_600_000) {
        lastTidy = Date.now();
        // Expired sessions are already refused by findSession; this only reclaims space.
        const sessions = await purgeExpiredSessions(db);
        const pruned = await pruneNewsCache(db);
        if (sessions || pruned) log("tidied", { sessions, newsCacheRows: pruned });
      }
      if (r.processed || r.reaped) log("dispatch pass", r);
      if (r.processed) continue; // more may be due
    } catch (err) {
      log("dispatch pass failed", { error: (err as Error).message });
    }
    await sleep(2000);
  }
}

async function digestLoop(db: Db, news: NewsDeps, shouldStop: () => boolean) {
  while (!shouldStop()) {
    try {
      const digests = await runDueDigests(db, news);
      if (digests) log("news digests built", { count: digests });
    } catch (err) {
      log("news digest pass failed", { error: (err as Error).message });
    }
    await pause(10_000, shouldStop);
  }
}
