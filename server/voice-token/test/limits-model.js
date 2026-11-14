// The voice token limits, in memory: the same rules as `hitLimits` in src/voice-auth.js (one Redis script), written
// out in plain JavaScript so the tests can run on a machine without redis-server and so the Redis script is held to
// the rules by test/fair-share.test.js, which runs every scenario against both.
// Not a test itself: the test runner only takes *.test.js.
import { VoiceAuthStoreUnavailable } from "../src/voice-auth.js";

const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** The settings' defaults as `src/handler.js` passes them to the store. */
export const RULES = {
  globalPerDay: 600,
  newAccounts: { days: 7, perAccountPerDay: 10, poolPerDay: 100 },
  fairShare: { budgetPercent: 50, tokensPerHour: 10 },
};

/**
 * `hitLimits` on an in-memory store. `reset()` empties it the way a wiped Redis would be, and `firstSeenKeys()` lists
 * the accounts that have a first-seen day. Counters never expire here: the clock a test passes in moves the windows.
 */
export function modelLimitsStore() {
  let data = { counts: new Map(), firstSeen: new Map(), started: undefined };
  return {
    reset() { data = { counts: new Map(), firstSeen: new Map(), started: undefined }; },
    firstSeenKeys() { return [...data.firstSeen.keys()]; },
    firstSeenDay(userId) { return data.firstSeen.get(userId); },
    startedDay() { return data.started; },
    async hitLimits(userId, perUserLimit, globalLimit, nowMs, perUserDailyLimit = 150, rules = {}) {
      if (!Number.isSafeInteger(perUserDailyLimit) || perUserDailyLimit < 1) throw new VoiceAuthStoreUnavailable();
      const hourWindow = Math.floor(nowMs / HOUR_MS);
      const today = Math.floor(nowMs / DAY_MS);
      const count = (name) => data.counts.get(name) ?? 0;
      const kHour = `user:${userId}:${hourWindow}`;
      const kDay = `user-day:${userId}:${today}`;
      const kGlobal = `global:${hourWindow}`;
      const kGlobalDay = `global-day:${today}`;
      const kPool = `new-pool:${today}`;
      let hour = count(kHour);
      let day = count(kDay);
      let global = count(kGlobal);
      let globalDay = count(kGlobalDay);
      let pool = count(kPool);

      const { globalPerDay = 0, newAccounts, fairShare } = rules ?? {};
      const newDays = newAccounts?.days ?? 0;
      let firstDay = today;
      let isNew = false;
      if (newDays > 0) {
        if (data.started === undefined) data.started = today;
        firstDay = data.firstSeen.get(userId) ?? today;
        // Established: first seen in the first days after the rules started. New: first seen after that, and not yet `days` days ago.
        isNew = firstDay > data.started + newDays && today - firstDay < newDays;
      }

      let limit = null;
      if (hour >= perUserLimit) limit = "user_hour";
      else if (day >= perUserDailyLimit) limit = "user_day";
      else if (isNew && day >= newAccounts.perAccountPerDay) limit = "new_account_day";
      else if (isNew && pool >= newAccounts.poolPerDay) limit = "new_pool";
      else if (global >= globalLimit) limit = "global";
      else if (globalPerDay > 0 && globalDay >= globalPerDay) limit = "global_day";
      else if (fairShare && global * 100 >= globalLimit * fairShare.budgetPercent && hour >= fairShare.tokensPerHour) limit = "fair_share";

      if (limit === null) {
        hour += 1; day += 1; global += 1;
        data.counts.set(kHour, hour); data.counts.set(kDay, day); data.counts.set(kGlobal, global);
        if (globalPerDay > 0) { globalDay += 1; data.counts.set(kGlobalDay, globalDay); }
        if (newDays > 0) {
          data.firstSeen.set(userId, firstDay);
          if (isNew) { pool += 1; data.counts.set(kPool, pool); }
        }
      }
      const daily = ["user_day", "new_account_day", "new_pool", "global_day"].includes(limit);
      const windowMs = daily ? DAY_MS : HOUR_MS;
      return {
        allowed: limit === null, limit, perUserCount: hour, dailyCount: day, globalCount: global,
        globalDayCount: globalDay, newPoolCount: pool, newAccount: isNew,
        retryAfterSeconds: Math.max(1, Math.ceil((windowMs - (nowMs % windowMs)) / 1_000)),
      };
    },
  };
}
