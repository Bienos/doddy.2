import { purgeExpiredSessions } from "./calls.js";
import type { Db } from "./db.js";
import { runDueDigests, type NewsDeps } from "./news/digest.js";
import { pruneNewsCache } from "./news/sources.js";
import { dispatchDue } from "./outbox.js";
import type { PushSender, SmsSender } from "./providers/types.js";

export const log = (msg: string, extra: object = {}) =>
  console.log(JSON.stringify({ time: new Date().toISOString(), msg, ...extra }));

/**
 * Sends queued updates, builds due news digests and tidies up, every ~2 s until `shouldStop()`.
 * Logs counts and ids only, never message text or phone numbers. Safe to run more than once at
 * a time: every job is claimed with FOR UPDATE SKIP LOCKED.
 */
export async function runWorkerLoop(
  db: Db, deps: { push?: PushSender; sms?: SmsSender; news: NewsDeps }, shouldStop: () => boolean,
): Promise<void> {
  let lastPrune = 0;
  while (!shouldStop()) {
    try {
      const r = await dispatchDue(db, { push: deps.push, sms: deps.sms });
      await purgeExpiredSessions(db);
      if (Date.now() - lastPrune > 3_600_000) {
        lastPrune = Date.now();
        const pruned = await pruneNewsCache(db);
        if (pruned) log("news cache pruned", { rows: pruned });
      }
      const digests = await runDueDigests(db, deps.news);
      if (digests) log("news digests built", { count: digests });
      if (r.processed || r.reaped) log("dispatch pass", r);
      if (r.processed) continue; // more may be due
    } catch (err) {
      log("dispatch pass failed", { error: (err as Error).message });
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
}
