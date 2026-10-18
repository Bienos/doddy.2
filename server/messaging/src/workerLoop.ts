import { purgeExpiredSessions } from "./calls.js";
import type { TextCipher } from "./crypto.js";
import type { Db } from "./db.js";
import { runDueDigests, type NewsDeps } from "./news/digest.js";
import { pruneNewsCache } from "./news/sources.js";
import { dispatchDue, reconcileUnknownSms } from "./outbox.js";
import { DELETE_AFTER_HOURS_DEFAULT, deleteAfterMinutes, pruneDeletions, runDueDeletions } from "./providerRecords.js";
import type { PushSender, RecordDeleter, SmsSender, TextReplyWriter } from "./providers/types.js";
import { processTextReply } from "./textReplies.js";
import { placeDueCall, pruneCallReasons, type ScheduledCallDeps } from "./scheduledCalls.js";

import { log } from "./log.js";

export { log };

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Waits up to `ms`, checking `shouldStop` every second so shutdown isn't held up. */
async function pause(ms: number, shouldStop: () => boolean) {
  for (let waited = 0; waited < ms && !shouldStop(); waited += 1000) await sleep(Math.min(1000, ms - waited));
}

export interface WorkerDeps {
  push?: PushSender;
  sms?: SmsSender;
  cipher?: TextCipher;
  news: NewsDeps;
  /** Replies to the user's texts (ADR-494). */
  replyWriter?: TextReplyWriter;
  /** Deletes Doddy's records at Twilio, deleteAfterMinutes after they are final (ADR-494). */
  deleter?: RecordDeleter;
  deleteAfterMinutes?: number;
  /** Places scheduled calls (ADR-495); only when calls are fully set up, else due calls fail with a notice. */
  scheduledCalls?: Omit<ScheduledCallDeps, "db" | "cipher" | "now">;
}

/**
 * Four independent loops until `shouldStop()`: one sends queued updates every ~2 s (plus hourly
 * tidying), one builds due news digests, one writes replies to the user's texts and deletes
 * records at Twilio, and one places scheduled calls. They are separate so a slow feed or AI call can't hold back time-sensitive
 * pushes such as a PIN-lock alert. Logs counts and ids only, never message text or phone
 * numbers. Safe to run more than once at a time: every job is claimed with FOR UPDATE SKIP LOCKED.
 */
export async function runWorkerLoop(db: Db, deps: WorkerDeps, shouldStop: () => boolean): Promise<void> {
  await Promise.all([dispatchLoop(db, deps, shouldStop), digestLoop(db, deps.news, shouldStop), textLoop(db, deps, shouldStop),
    callLoop(db, deps, shouldStop)]);
}

async function dispatchLoop(db: Db, deps: { push?: PushSender; sms?: SmsSender; cipher?: TextCipher }, shouldStop: () => boolean) {
  let lastTidy = 0;
  while (!shouldStop()) {
    try {
      const r = await dispatchDue(db, { push: deps.push, sms: deps.sms, cipher: deps.cipher });
      // Texts whose outcome is unknown are looked up at Twilio a little later (DOD-09).
      await reconcileUnknownSms(db, deps.sms);
      if (Date.now() - lastTidy > 3_600_000) {
        lastTidy = Date.now();
        // Expired sessions are already refused by findSession; this only reclaims space.
        const sessions = await purgeExpiredSessions(db);
        const pruned = await pruneNewsCache(db);
        const deletions = await pruneDeletions(db);
        const reasons = await pruneCallReasons(db);
        if (sessions || pruned || deletions || reasons) {
          log("tidied", { sessions, newsCacheRows: pruned, deletionRows: deletions, callReasons: reasons });
        }
      }
      if (r.processed || r.reaped) log("dispatch pass", r);
      if (r.processed) continue; // more may be due
    } catch (err) {
      log("dispatch pass failed", { error: (err as Error).message });
    }
    await sleep(2000);
  }
}

/** Replies to the user's texts, one at a time, and once a minute the due deletions at Twilio. */
async function textLoop(db: Db, deps: WorkerDeps, shouldStop: () => boolean) {
  let lastDeletions = 0;
  const after = deps.deleteAfterMinutes ?? deleteAfterMinutes(DELETE_AFTER_HOURS_DEFAULT);
  while (!shouldStop()) {
    let handled = false;
    try {
      handled = await processTextReply({ db, cipher: deps.cipher, replyWriter: deps.replyWriter });
    } catch (err) {
      log("text reply pass failed", { error: (err as Error).message });
    }
    if (Date.now() - lastDeletions > 60_000) {
      lastDeletions = Date.now();
      try {
        await runDueDeletions(db, deps.deleter, after);
      } catch (err) {
        log("twilio deletion pass failed", { error: (err as Error).message });
      }
    }
    if (!handled) await pause(2000, shouldStop);
  }
}

/** Scheduled calls, one at a time, checked every few seconds so a call rings close to its time. */
async function callLoop(db: Db, deps: WorkerDeps, shouldStop: () => boolean) {
  while (!shouldStop()) {
    let handled = false;
    try {
      handled = await placeDueCall({ db, cipher: deps.cipher, ...deps.scheduledCalls });
    } catch (err) {
      log("scheduled call pass failed", { error: (err as Error).message });
    }
    if (!handled) await pause(5000, shouldStop);
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
