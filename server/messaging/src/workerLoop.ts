import { purgeExpiredSessions } from "./calls.js";
import type { AbuseLimits } from "./config.js";
import type { TextCipher } from "./crypto.js";
import { pruneCounters } from "./dailyCounters.js";
import type { Db } from "./db.js";
import { runDueDigests, type NewsDeps } from "./news/digest.js";
import { pruneNewsCache } from "./news/sources.js";
import { dispatchDue, reconcileUnknownSms } from "./outbox.js";
import { DELETE_AFTER_HOURS_DEFAULT, deleteAfterMinutes, pruneDeletions, runDueDeletions } from "./providerRecords.js";
import type { PushSender, RecordDeleter, SmsSender } from "./providers/types.js";
import { placeDueCall, pruneCallReasons, type ScheduledCallDeps } from "./scheduledCalls.js";
import type { TaskVoice } from "./providers/taskCalls.js";
import type { TaskCallContext } from "./taskCalls/context.js";
import { runDeletions, runTaskCallPasses } from "./taskCalls/worker.js";
import type { ErrandContext } from "./errands/context.js";
import { newErrandLoopState, runErrandPasses, stopErrandRuns } from "./errands/worker.js";
import type { StudioContext } from "./studio/context.js";
import { newStudioLoopState, runStudioPasses, stopStudioRuns } from "./studio/worker.js";
import type { WatchContext } from "./watches/context.js";
import { BATCH, newWatchLoopState, runWatchPasses } from "./watches/worker.js";

import { idlePollFromEnv, runAdaptiveLoop, WakeBus, type IdlePollConfig, type PassResult } from "./idlePoll.js";
import { startWakeListener } from "./wake.js";
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
  taskCalls?: TaskCallContext;
  errands?: ErrandContext;
  studio?: StudioContext;
  watches?: WatchContext;
  /** Calling codes a text may go to, checked again when it is sent (ADR-704). */
  limits?: Pick<AbuseLimits, "allowedCountryCodes">;
  /** Deletes Doddy's records at Twilio, deleteAfterMinutes after they are final (ADR-753). */
  deleter?: RecordDeleter;
  deleteAfterMinutes?: number;
  /** Places scheduled calls (ADR-754); only when calls are fully set up, else due calls fail with a notice. */
  scheduledCalls?: Omit<ScheduledCallDeps, "db" | "cipher" | "now">;
  /** Deletes phone-agent conversations queued at account deletion when task calls (and their worker) are off. */
  phoneAgentVoice?: TaskVoice;
  /** Idle back-off of the queue loops (idlePoll.ts). Default: from IDLE_POLL_* in the environment, else 2 s up to 30 s. */
  idlePoll?: IdlePollConfig;
  /** Wake-ups for the queue loops; tests pass their own. Default: one bus fed by the database's LISTEN. */
  wake?: WakeBus;
  /** false: don't open the LISTEN connection (the loops then use the short fallback cap). Default true. */
  listen?: boolean;
  /** Called after every pass of an adaptive loop, for measuring. */
  onPass?: (loop: "dispatch" | "errand" | "studio") => void;
}

interface Poll { config: IdlePollConfig; bus: WakeBus; onPass?: WorkerDeps["onPass"] }

/**
 * Independent loops until `shouldStop()`: one sends queued updates every ~2 s (plus hourly tidying), one builds
 * due news digests, one deletes Doddy's records at Twilio, one places scheduled calls, and one each for call cases,
 * errands and price watches. They are separate so a slow feed or AI call can't hold back time-sensitive
 * pushes such as a PIN-lock alert. Logs counts and ids only, never message text or phone
 * numbers. Safe to run more than once at a time: every job is claimed with FOR UPDATE SKIP LOCKED.
 */
export async function runWorkerLoop(db: Db, deps: WorkerDeps, shouldStop: () => boolean): Promise<void> {
  const poll: Poll = { config: deps.idlePoll ?? idlePollFromEnv(), bus: deps.wake ?? new WakeBus(), onPass: deps.onPass };
  const listener = deps.listen === false ? undefined : startWakeListener(db, poll.bus, log, shouldStop);
  // The dispatch, errand and studio loops back off while idle and wake on a notification. The scheduled-call and
  // task-call loops stay on their fixed intervals: their timing is the product (dial times, the goodbye at a call's limit).
  const loops = [dispatchLoop(db, deps, shouldStop, poll), digestLoop(db, deps.news, shouldStop), deletionLoop(db, deps, shouldStop),
    callLoop(db, deps, shouldStop)];
  if (deps.taskCalls) loops.push(taskCallLoop(deps.taskCalls, shouldStop));
  else if (deps.phoneAgentVoice) loops.push(conversationDeletionLoop(db, deps.phoneAgentVoice, shouldStop));
  if (deps.errands) loops.push(errandLoop(deps.errands, shouldStop, poll));
  if (deps.studio) loops.push(studioLoop(deps.studio, shouldStop, poll));
  if (deps.watches) loops.push(watchLoop(deps.watches, shouldStop));
  try {
    await Promise.all(loops);
  } finally {
    await listener?.stop();
  }
}

/**
 * Studio (ADR-740): starts queued jobs (up to 2 at once in this process), reaps interrupted ones,
 * deletes expired drafts and keeps deleting copies left at Anthropic. On shutdown, running jobs stop
 * and are stored as `interrupted`.
 */
async function studioLoop(ctx: StudioContext, shouldStop: () => boolean, poll: Poll) {
  const state = newStudioLoopState();
  await runAdaptiveLoop({
    topic: "studio", shouldStop, config: poll.config, bus: poll.bus,
    pass: async (): Promise<PassResult> => {
      poll.onPass?.("studio");
      let counts: Record<string, number> = {};
      try {
        counts = await runStudioPasses(ctx, state);
        if (Object.keys(counts).length) log("studio passes", counts);
      } catch (err) {
        log("studio passes failed", { error: (err as Error).message });
      }
      // A job running here keeps the short interval (its cancel and slot handling); an idle loop backs off.
      return { busy: Object.keys(counts).length > 0 || state.runs.size > 0 };
    },
  });
  await stopStudioRuns(state);
}

/**
 * Price watches (shopping stage 2): checks the watches that are due, one at a time and politely, and tidies
 * drafts and finished watches. Its own loop, so a slow shop never holds back pushes. A watch is checked about
 * every 6 hours, so the loop looks every 10 seconds (one cheap index lookup) and goes straight on while a full
 * batch was due. On shutdown the check in flight is given back unrecorded.
 */
async function watchLoop(ctx: WatchContext, shouldStop: () => boolean) {
  const state = newWatchLoopState();
  const stopWatcher = setInterval(() => { if (shouldStop()) state.shutdown.abort(); }, 500);
  try {
    while (!shouldStop()) {
      let more = false;
      try {
        const counts = await runWatchPasses(ctx, state);
        if (Object.keys(counts).length) log("watch passes", counts);
        more = (counts.claimed ?? 0) >= BATCH;
      } catch (err) {
        log("watch passes failed", { error: (err as Error).message });
      }
      if (!more) await pause(10_000, shouldStop);
    }
  } finally {
    clearInterval(stopWatcher);
  }
}

/**
 * Errands (ADR-570): starts queued research runs (up to 3 at once in this process, each up to the
 * time limit) and tidies expired drafts and unacknowledged results. Its own loop, so a long run never
 * holds back pushes. On shutdown, running errands stop and are stored as `interrupted`.
 */
async function errandLoop(ctx: ErrandContext, shouldStop: () => boolean, poll: Poll) {
  const state = newErrandLoopState();
  await runAdaptiveLoop({
    topic: "errand", shouldStop, config: poll.config, bus: poll.bus,
    pass: async (): Promise<PassResult> => {
      poll.onPass?.("errand");
      let counts: Record<string, number> = {};
      try {
        counts = await runErrandPasses(ctx, state);
        if (Object.keys(counts).length) log("errand passes", counts);
      } catch (err) {
        log("errand passes failed", { error: (err as Error).message });
      }
      return { busy: Object.keys(counts).length > 0 || state.runs.size > 0 };
    },
  });
  await stopErrandRuns(state);
}

/**
 * Call cases (ADR-500): scheduled dials, the goodbye at the time limit, the kill switch, answer
 * cards, costs and deletions. Its own loop, so a slow provider call never holds back pushes.
 */
/** Without task calls, only the ElevenLabs deletions queued at account deletion still need a worker. */
async function conversationDeletionLoop(db: Db, voice: TaskVoice, shouldStop: () => boolean) {
  while (!shouldStop()) {
    try {
      const n = await runDeletions({ db, voice, now: () => new Date(), log });
      if (n) log("conversation deletions", { processed: n });
      if (n) continue;
    } catch (err) {
      log("conversation deletions failed", { error: (err as Error).message });
    }
    await pause(30_000, shouldStop);
  }
}

async function taskCallLoop(ctx: TaskCallContext, shouldStop: () => boolean) {
  const state = { lastSweep: 0 };
  while (!shouldStop()) {
    try {
      const counts = await runTaskCallPasses(ctx, state);
      if (Object.keys(counts).length) log("task-call passes", counts);
    } catch (err) {
      log("task-call passes failed", { error: (err as Error).message });
    }
    await pause(2000, shouldStop);
  }
}

async function dispatchLoop(
  db: Db, deps: { push?: PushSender; sms?: SmsSender; cipher?: TextCipher; limits?: Pick<AbuseLimits, "allowedCountryCodes"> },
  shouldStop: () => boolean, poll: Poll,
) {
  let lastTidy = 0;
  await runAdaptiveLoop({
    topic: "dispatch", shouldStop, config: poll.config, bus: poll.bus,
    pass: async (): Promise<PassResult> => {
      poll.onPass?.("dispatch");
      try {
        const r = await dispatchDue(db, { push: deps.push, sms: deps.sms, cipher: deps.cipher, allowedCountryCodes: deps.limits?.allowedCountryCodes });
        // Texts whose outcome is unknown are looked up at Twilio a little later (DOD-09).
        const looked = await reconcileUnknownSms(db, deps.sms);
        if (Date.now() - lastTidy > 3_600_000) {
          lastTidy = Date.now();
          // Expired sessions are already refused by findSession; this only reclaims space.
          const sessions = await purgeExpiredSessions(db);
          await pruneCounters(db); // daily counts older than two days (ADR-702)
          const pruned = await pruneNewsCache(db);
          const deletions = await pruneDeletions(db);
          const reasons = await pruneCallReasons(db);
          if (sessions || pruned || deletions || reasons) {
            log("tidied", { sessions, newsCacheRows: pruned, deletionRows: deletions, callReasons: reasons });
          }
        }
        if (r.processed || r.reaped) log("dispatch pass", r);
        if (r.processed) return { busy: true, again: true }; // more may be due
        return { busy: r.reaped > 0 || looked > 0, dueInMs: await nextQueuedInMs(db) };
      } catch (err) {
        log("dispatch pass failed", { error: (err as Error).message });
        return { busy: false };
      }
    },
  });
}

/** Milliseconds until the next message that was queued for later is due, or null when none is. */
async function nextQueuedInMs(db: Db): Promise<number | null> {
  const { rows } = await db.query<{ ms: string | null }>(
    "SELECT (EXTRACT(EPOCH FROM (min(send_at) - now())) * 1000)::text AS ms FROM outbound_messages WHERE state = 'queued'");
  const ms = rows[0]?.ms;
  return ms === null || ms === undefined ? null : Math.max(0, Number(ms));
}

/** Once a minute, the due deletions of Doddy's records at Twilio. */
async function deletionLoop(db: Db, deps: WorkerDeps, shouldStop: () => boolean) {
  const after = deps.deleteAfterMinutes ?? deleteAfterMinutes(DELETE_AFTER_HOURS_DEFAULT);
  while (!shouldStop()) {
    try {
      await runDueDeletions(db, deps.deleter, after);
    } catch (err) {
      log("twilio deletion pass failed", { error: (err as Error).message });
    }
    await pause(60_000, shouldStop);
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
