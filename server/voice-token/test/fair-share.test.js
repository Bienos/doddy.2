// A small daily pool for new accounts, a fair share per account inside the hourly budget, and a daily ceiling for the
// whole service (decision 2026-11-12-voice-token-fair-share, items 1 and 2). The rules live in the one Redis script
// behind `hitLimits`; every scenario below runs against an in-memory model of the rules (test/limits-model.js) and
// against the real script on a local redis-server, so the two are held to each other. The same rules are then run
// through the token handler: the answer is the same `rate_limited` with Retry-After, and no log line carries a token,
// an account or a key.
import assert from "node:assert/strict";
import { test } from "node:test";
import { handleTokenRequest } from "../src/handler.js";
import { createVoiceAuthStore } from "../src/voice-auth.js";
import { fakeConversationStore } from "./conversation-fakes.js";
import { RULES, modelLimitsStore } from "./limits-model.js";
import { hasRedis, withLocalRedis } from "./local-redis.js";

const HOUR = 3_600_000;
const DAY = 86_400_000;
/** The rules start counting here (the first call). Mid-morning UTC, so an hour never sits at the edge of a day. */
const START = Date.parse("2026-11-16T10:00:00Z");
const PREFIX = "doddy:voice:v1:";
const FIRST_SEEN_SECONDS = 180 * 86_400;

const hit = (store, user, now, { perHour = 30, global = 100, perDay = 150, rules = RULES } = {}) =>
  store.hitLimits(user, perHour, global, now, perDay, rules);
async function take(store, user, now, count, options) {
  const decisions = [];
  for (let i = 0; i < count; i += 1) decisions.push(await hit(store, user, now, options));
  return decisions;
}
const pick = (decision) => [decision.allowed, decision.limit];
const counts = (d) => [d.perUserCount, d.dailyCount, d.globalCount, d.globalDayCount, d.newPoolCount];
/** Tokens for accounts on the day the rules start: they are the established ones. */
async function establish(store, ...users) {
  for (const user of users) assert.equal((await hit(store, user, START)).allowed, true);
}
function assertAllowed(decisions, message, { newAccount } = {}) {
  decisions.forEach((decision, index) => {
    assert.equal(decision.allowed, true, `${message}: token ${index + 1} was refused (${decision.limit})`);
    if (newAccount !== undefined) assert.equal(decision.newAccount, newAccount, `${message}: token ${index + 1}`);
  });
}
/** Seconds from `now` to the next UTC midnight. */
const toMidnight = (now) => Math.ceil((DAY - (now % DAY)) / 1_000);
const toHourEnd = (now) => Math.ceil((HOUR - (now % HOUR)) / 1_000);

// ---- the scenarios ---------------------------------------------------------------------------------------------
// Each gets `store`, `reset` (empties the store, as a wiped Redis would be), `keys` (the store's keys on a real Redis, else
// null) and `command` (a raw Redis command on a real Redis, else null).

const scenarios = {
  "whoever is first seen in the first 7 days after the rules start counts as established, so today's testers stay where they are": async ({ store }) => {
    // The first call after the deploy: this account, and the clock, start here.
    assertAllowed(await take(store, "early", START, 12), "the first account", { newAccount: false });
    assertAllowed(await take(store, "mid", START + 3 * DAY, 12), "day 3", { newAccount: false });
    // The day the rules start and the 7 days after it: always at least a full 7 x 24 hours.
    assertAllowed(await take(store, "edge", START + 7 * DAY, 12), "day 7", { newAccount: false });
    const late = await take(store, "late", START + 8 * DAY, 11);
    assertAllowed(late.slice(0, 10), "day 8 is the first day a first-time account is new", { newAccount: true });
    assert.deepEqual(pick(late[10]), [false, "new_account_day"]);
  },

  "a new account has 10 tokens of its own a day, the 11th is refused until tomorrow, and a refusal uses no budget": async ({ store }) => {
    await establish(store, "early");
    const T = START + 10 * DAY;
    const tokens = await take(store, "newcomer", T, 10);
    assertAllowed(tokens, "ten tokens", { newAccount: true });
    // A new account's tokens still count against the service's budgets.
    assert.deepEqual(counts(tokens[9]), [10, 10, 10, 10, 10]);
    for (let i = 0; i < 20; i += 1) {
      const refused = await hit(store, "newcomer", T);
      assert.deepEqual(pick(refused), [false, "new_account_day"]);
      assert.deepEqual(counts(refused), [10, 10, 10, 10, 10], "a refused request moves no counter");
      assert.equal(refused.retryAfterSeconds, toMidnight(T), "until the next UTC midnight");
    }
    // Hours later the hour has room, but the day does not.
    assert.deepEqual(pick(await hit(store, "newcomer", T + 5 * HOUR)), [false, "new_account_day"]);
    // Tomorrow it has 10 again; it is still new, so the 11th is refused again.
    const tomorrow = await take(store, "newcomer", T + DAY, 11);
    assertAllowed(tomorrow.slice(0, 10), "tomorrow", { newAccount: true });
    assert.deepEqual(pick(tomorrow[10]), [false, "new_account_day"]);
  },

  "the pool shared by all new accounts is 100 tokens a day: the 101st is refused, an established account is not affected": async ({ store }) => {
    await establish(store, "early");
    const T = START + 10 * DAY;
    // Ten new accounts with ten tokens each, in ten different hours so the hourly budget is not what stops them.
    for (let k = 0; k < 10; k += 1) assertAllowed(await take(store, `new-${k}`, T + k * HOUR, 10), `account ${k}`, { newAccount: true });
    const evening = T + 9 * HOUR;
    for (let i = 0; i < 20; i += 1) {
      const refused = await hit(store, "new-10", evening);
      assert.deepEqual(pick(refused), [false, "new_pool"]);
      assert.equal(refused.newPoolCount, 100, "a refused request does not use the pool");
      assert.equal(refused.retryAfterSeconds, toMidnight(evening));
    }
    // The established account has all of its own allowance, whatever the pool says.
    assertAllowed(await take(store, "early", evening, 15), "an established account", { newAccount: false });
    // A new account that already used its own 10 is told so, not about the pool.
    assert.deepEqual(pick(await hit(store, "new-3", evening)), [false, "new_account_day"]);
    // The pool starts again with the next day.
    const tomorrow = await hit(store, "new-10", T + DAY);
    assert.deepEqual([tomorrow.allowed, tomorrow.newPoolCount], [true, 1]);
  },

  "a heavy account is refused at its fair share only once the hour is half used, and a light account is still served": async ({ store }) => {
    await establish(store, "nine", "heavy", "filler", "light");
    const T = START + 10 * DAY;
    // Under half of the hour's 100, nobody is held back: 'heavy' has 21 tokens, well over its 10.
    assertAllowed(await take(store, "nine", T, 9), "nine tokens");
    assertAllowed(await take(store, "heavy", T, 21), "a heavy account while the hour is under half used");
    const filler = await take(store, "filler", T, 20);
    assertAllowed(filler, "filler");
    assert.equal(filler[19].globalCount, 50, "the hour is now half used");
    for (let i = 0; i < 20; i += 1) {
      for (const heavy of ["heavy", "filler"]) {
        const refused = await hit(store, heavy, T);
        assert.deepEqual(pick(refused), [false, "fair_share"], heavy);
        assert.equal(refused.retryAfterSeconds, toHourEnd(T), "until the hour ends");
        assert.equal(refused.globalCount, 50, "a refused request uses none of the hour's budget");
      }
    }
    assert.equal((await hit(store, "heavy", T)).perUserCount, 21, "nor the account's own count");
    // The same moment: an account that had 9 gets its 10th, one that had none is served. The 11th of the first is refused.
    assert.deepEqual(pick(await hit(store, "nine", T)), [true, null]);
    assert.deepEqual(pick(await hit(store, "nine", T)), [false, "fair_share"]);
    const light = await hit(store, "light", T);
    assert.deepEqual([light.allowed, light.globalCount], [true, 52]);
    // The hour ends, the budget starts again, and the heavy account is served.
    assert.deepEqual(pick(await hit(store, "heavy", T + HOUR)), [true, null]);
  },

  "the fair-share line is exactly half of the hour's budget, and with the line at 100 percent the hour's budget alone decides": async ({ store }) => {
    const rules = { fairShare: { budgetPercent: 50, tokensPerHour: 3 } };
    const options = { global: 10, rules };
    const T = START + 10 * DAY;
    assertAllowed(await take(store, "a", T, 3, options), "a");
    assertAllowed(await take(store, "b", T, 1, options), "b");
    // 4 of 10 used: under half, so 'a' (3 tokens) gets its 4th. That makes 5 of 10: half.
    assert.deepEqual(pick(await hit(store, "a", T, options)), [true, null]);
    assert.deepEqual(pick(await hit(store, "a", T, options)), [false, "fair_share"]);
    assert.deepEqual(pick(await hit(store, "b", T, options)), [true, null], "'b' has 1 of its 3");

    const hundred = { global: 10, rules: { fairShare: { budgetPercent: 100, tokensPerHour: 3 } } };
    const U = T + 3 * HOUR;
    assertAllowed(await take(store, "c", U, 10, hundred), "the whole budget, one account");
    assert.deepEqual(pick(await hit(store, "c", U, hundred)), [false, "global"], "the hour's budget refuses first");
  },

  "the whole service has a daily ceiling, and a refusal for it uses no hourly budget": async ({ store }) => {
    const rules = { ...RULES, globalPerDay: 6 };
    await establish(store, "a", "b", "c", "d");
    const T = START + 10 * DAY;
    assertAllowed(await take(store, "a", T, 2, { rules }), "a");
    assertAllowed(await take(store, "b", T + HOUR, 2, { rules }), "b");
    assertAllowed(await take(store, "c", T + 2 * HOUR, 2, { rules }), "c");
    const evening = T + 3 * HOUR;
    for (let i = 0; i < 20; i += 1) {
      const refused = await hit(store, "d", evening, { rules });
      assert.deepEqual(pick(refused), [false, "global_day"]);
      assert.deepEqual(counts(refused), [0, 0, 0, 6, 0], "nothing was counted for the refused request, in the hour or the day");
      assert.equal(refused.retryAfterSeconds, toMidnight(evening));
    }
    const tomorrow = await hit(store, "d", T + DAY, { rules });
    assert.deepEqual([tomorrow.allowed, tomorrow.globalDayCount, tomorrow.dailyCount], [true, 1, 1], "the ceiling starts again with the day");
  },

  "the window of a new account ends after 7 days, and then the normal limits apply": async ({ store }) => {
    await establish(store, "early");
    const first = START + 10 * DAY;
    assertAllowed(await take(store, "newcomer", first, 3), "the first day", { newAccount: true });
    // The 7th day is the last new one: its 10 tokens are allowed, the 11th is not.
    const seventh = await take(store, "newcomer", first + 6 * DAY, 11);
    assertAllowed(seventh.slice(0, 10), "the 7th day", { newAccount: true });
    assert.deepEqual(pick(seventh[10]), [false, "new_account_day"]);
    // The 8th day: no longer new, the account's own limit of 30 an hour applies.
    const eighth = await take(store, "newcomer", first + 7 * DAY, 12);
    assertAllowed(eighth, "the 8th day", { newAccount: false });
  },

  "an emptied store counts everyone as established for the first 7 days, never as new": async ({ store, reset }) => {
    await establish(store, "early");
    const T = START + 10 * DAY;
    assertAllowed(await take(store, "newcomer", T, 3), "before the reset", { newAccount: true });
    await reset();
    // Redis was wiped: no first-seen day, no start day. The next request starts the clock again.
    const after = START + 12 * DAY;
    assertAllowed(await take(store, "newcomer", after, 12), "the same account after the reset", { newAccount: false });
    assertAllowed(await take(store, "stranger", after + 3 * DAY, 12), "an account nobody has seen, 3 days after", { newAccount: false });
    // Once those days have passed, an account seen for the first time is new, as before.
    const late = await take(store, "latecomer", after + 8 * DAY, 11);
    assertAllowed(late.slice(0, 10), "a new account after the reset window", { newAccount: true });
    assert.deepEqual(pick(late[10]), [false, "new_account_day"]);
  },

  "called without the new rules, the limits are the three they always were": async ({ store, keys }) => {
    const T = START + 10 * DAY;
    const tokens = [];
    for (let i = 0; i < 12; i += 1) tokens.push(await store.hitLimits("someone", 30, 100, T, 150));
    assertAllowed(tokens, "twelve tokens", { newAccount: false });
    assert.deepEqual(counts(tokens[11]), [12, 12, 12, 0, 0]);
    // The hour's and the account's own limits still say no, with the words they always had.
    assert.deepEqual(pick(await store.hitLimits("someone", 12, 100, T, 150)), [false, "user_hour"]);
    assert.deepEqual(pick(await store.hitLimits("someone", 30, 100, T, 12)), [false, "user_day"]);
    assert.deepEqual(pick(await store.hitLimits("someone", 30, 12, T, 150)), [false, "global"]);
    if (keys) assert.equal((await keys()).length, 3, "no first-seen day, start day, pool or daily ceiling is written");
  },
};

test("the model of the rules: every scenario", async (t) => {
  for (const [name, scenario] of Object.entries(scenarios)) {
    await t.test(name, async () => {
      const store = modelLimitsStore();
      await scenario({ store, reset: async () => store.reset(), keys: null, command: null });
    });
  }
});

test("the Redis script: every scenario, on a real redis-server", { skip: !hasRedis && "redis-server not installed" }, async (t) => {
  for (const [name, scenario] of Object.entries(scenarios)) {
    await t.test(name, async () => {
      await withLocalRedis(async ({ store, command }) => {
        await scenario({
          store, command,
          reset: async () => { await command("FLUSHALL"); },
          keys: async () => (await command("KEYS", `${PREFIX}*`)).sort(),
        });
      });
    });
  }
});

// ---- what is stored, on a real Redis ----------------------------------------------------------------------------

test("Redis: the start day is one key without an expiry, written by the first call and never moved", { skip: !hasRedis && "redis-server not installed" }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    const started = `${PREFIX}fair-share-started`;
    assert.equal(await command("GET", started), null, "nothing before the first call");
    // Even a refused first call starts the clock: it is the day the code first ran, not a budget. It writes nothing about the account.
    assert.deepEqual(pick(await hit(store, "x", START, { perHour: 0 })), [false, "user_hour"]);
    assert.equal(await command("GET", started), String(Math.floor(START / DAY)));
    assert.equal(await command("TTL", started), -1);
    assert.deepEqual((await command("KEYS", `${PREFIX}*`)).sort(), [started]);
    await hit(store, "y", START + 30 * DAY);
    assert.equal(await command("GET", started), String(Math.floor(START / DAY)), "SET NX: a later call leaves it alone");
  });
});

test("Redis: the first-seen day is one key per account holding only that day, written only when a token is issued, expiring when the account is long gone", { skip: !hasRedis && "redis-server not installed" }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    await establish(store, "early");
    const T = START + 10 * DAY;
    const day = Math.floor(T / DAY);
    // Refused for a full hourly budget: nothing about the account is written.
    const full = { global: 1 };
    await take(store, "first", T, 1, full);
    const keysBefore = (await command("KEYS", `${PREFIX}*`)).sort();
    const refused = await hit(store, "second", T, full);
    assert.deepEqual(pick(refused), [false, "global"]);
    assert.deepEqual((await command("KEYS", `${PREFIX}*`)).sort(), keysBefore, "a refused request writes no key at all");
    assert.equal(await command("EXISTS", `${PREFIX}first-seen:second`), 0);
    // Issued: the key holds the day and nothing else, and it lives for 180 days.
    assert.equal((await hit(store, "second", T + HOUR)).allowed, true);
    const key = `${PREFIX}first-seen:second`;
    assert.equal(await command("GET", key), String(Math.floor((T + HOUR) / DAY)));
    const ttl = await command("TTL", key);
    assert.ok(ttl > FIRST_SEEN_SECONDS - 60 && ttl <= FIRST_SEEN_SECONDS, `the first-seen day expires after 180 days (${ttl})`);
    // Another token a day later keeps the day, and starts the 180 days again (the account is still in use).
    await command("EXPIRE", key, 100);
    assert.equal((await hit(store, "second", T + DAY)).allowed, true);
    assert.equal(await command("GET", key), String(day), "the first day is kept");
    assert.ok((await command("TTL", key)) > FIRST_SEEN_SECONDS - 60);
    // The shared counters expire after a day and an hour, not never.
    for (const name of [`limit-global-day:${day}`, `limit-new-pool:${day}`]) {
      const t = await command("TTL", `${PREFIX}${name}`);
      assert.ok(t > 3_600 && t <= 90_000, `${name} lives about a day (${t})`);
    }
  });
});

// ---- the same rules, through the token handler -------------------------------------------------------------------

const ENV = {
  DODDY_SESSION_SIGNING_KEY: "server-only-session-key-for-tests-000000000000000",
  ELEVENLABS_API_KEY: "elevenlabs-server-secret",
  ELEVENLABS_AGENT_ID: "agent_test",
};

/** One token request for `userId` at time `now`, against `limits` (anything with `hitLimits`). */
async function ask(limits, userId, now, environment = ENV) {
  const logs = [];
  const upstream = [];
  const authStore = { ...fakeConversationStore(), hitLimits: (...args) => limits.hitLimits(...args) };
  const response = await handleTokenRequest(new Request("https://example.test/api/voice-token", {
    method: "POST", headers: { authorization: "Bearer doddysession" },
  }), environment, {
    fetch: async (url) => { upstream.push(String(url)); return Response.json({ token: "provider-credential" }); },
    log: (entry) => logs.push(entry), now: () => now, authStore,
    authenticateSession: async () => ({ userId, sessionId: "session-1" }),
  });
  return { status: response.status, body: await response.json(), retryAfter: response.headers.get("retry-after"), logs, upstream };
}

async function throughTheHandler(limits) {
  const everything = [];
  const send = async (...args) => { const result = await ask(limits, ...args); everything.push(...result.logs); return result; };
  // The first account starts the clock; the others are first seen on that day too, so they are established.
  for (const account of ["early-account", "busy-account", "busier-account", "light-account"]) assert.equal((await send(account, START)).status, 200);
  const T = START + 10 * DAY;

  // A new account: ten tokens, then the same `rate_limited` and Retry-After as for the other limits, and nothing asked of ElevenLabs.
  for (let i = 0; i < 10; i += 1) assert.equal((await send("new-account", T)).status, 200);
  const eleventh = await send("new-account", T);
  assert.equal(eleventh.status, 429);
  assert.deepEqual(eleventh.body, { error: "rate_limited" });
  assert.equal(eleventh.retryAfter, String(toMidnight(T)));
  assert.equal(eleventh.logs.at(-1).limit, "new_account_day");
  assert.equal(eleventh.upstream.length, 0, "a refused request never reaches the provider");
  // An established account is not held to the new-account allowance.
  for (let i = 0; i < 12; i += 1) assert.equal((await send("early-account", T)).status, 200);

  // The hour is half used (10 + 12 + the rest here); a heavy account is refused at its fair share, a light one is served.
  for (let i = 0; i < 28; i += 1) assert.equal((await send("busy-account", T + HOUR)).status, 200);
  for (let i = 0; i < 22; i += 1) assert.equal((await send("busier-account", T + HOUR)).status, 200);
  const heavy = await send("busy-account", T + HOUR);
  assert.equal(heavy.status, 429);
  assert.deepEqual(heavy.body, { error: "rate_limited" });
  assert.equal(heavy.retryAfter, String(toHourEnd(T + HOUR)));
  assert.equal(heavy.logs.at(-1).limit, "fair_share");
  assert.equal(heavy.upstream.length, 0);
  assert.equal((await send("light-account", T + HOUR)).status, 200, "a light account is served in the same moment");

  // Nothing in any log line carries a token, an account, a key or a Redis key.
  const logged = JSON.stringify(everything);
  for (const secret of ["provider-credential", "doddysession", "elevenlabs-server-secret", ENV.DODDY_SESSION_SIGNING_KEY,
    "early-account", "new-account", "busy-account", "busier-account", "light-account", "first-seen", "fair-share-started", PREFIX]) {
    assert.ok(!logged.includes(secret), `a log line carried ${secret}`);
  }
  const words = new Set(everything.map((entry) => entry.limit).filter(Boolean));
  assert.deepEqual([...words].sort(), ["fair_share", "new_account_day"], "the log says which limit, in a fixed word");
}

test("through the handler (model): the same rate_limited answer with Retry-After, and clean logs", async () => {
  await throughTheHandler(modelLimitsStore());
});

test("through the handler on a real Redis: the same rate_limited answer with Retry-After, and clean logs", { skip: !hasRedis && "redis-server not installed" }, async () => {
  await withLocalRedis(async ({ store }) => {
    await throughTheHandler(store);
  });
});

test("the store refuses rules that are not whole numbers, as an unreachable store, before counting anything", { skip: !hasRedis && "redis-server not installed" }, async () => {
  await withLocalRedis(async ({ store, command }) => {
    const bad = [
      { globalPerDay: 0.5 }, { globalPerDay: -1 }, { globalPerDay: "6" },
      { newAccounts: { days: 0, perAccountPerDay: 10, poolPerDay: 100 } },
      { newAccounts: { days: 7, perAccountPerDay: 1.5, poolPerDay: 100 } },
      { newAccounts: { days: 7, perAccountPerDay: 10 } },
      { fairShare: { budgetPercent: 101, tokensPerHour: 10 } },
      { fairShare: { budgetPercent: 0, tokensPerHour: 10 } },
      { fairShare: { budgetPercent: 50, tokensPerHour: 0 } },
    ];
    for (const rules of bad) {
      await assert.rejects(() => store.hitLimits("u", 30, 100, START, 150, rules), { name: "VoiceAuthStoreUnavailable" }, JSON.stringify(rules));
    }
    assert.deepEqual(await command("KEYS", `${PREFIX}*`), []);
  });
});

test("the Redis store sends the new rules as one script call with its own keys only, and no account in a key beyond the existing ones", async () => {
  const sent = [];
  const store = createVoiceAuthStore({
    url: "https://redis.example.test", token: "store-secret",
    fetch: async (_url, init) => { sent.push(JSON.parse(init.body)); return Response.json([{ result: [0, 1, 1, 1, 1, 0, 0] }]); },
  });
  await hit(store, "account:abc", START);
  assert.equal(sent.length, 1, "one request to the store, one script");
  assert.equal(sent[0].length, 1);
  const [command, , keyCount, ...rest] = sent[0][0];
  assert.equal(command, "EVAL");
  const keys = rest.slice(0, Number(keyCount));
  const day = Math.floor(START / DAY);
  const hour = Math.floor(START / HOUR);
  assert.deepEqual(keys, [
    `${PREFIX}limit-user:account:abc:${hour}`, `${PREFIX}limit-user-day:account:abc:${day}`, `${PREFIX}limit-global:${hour}`,
    `${PREFIX}limit-global-day:${day}`, `${PREFIX}limit-new-pool:${day}`, `${PREFIX}first-seen:account:abc`, `${PREFIX}fair-share-started`,
  ]);
  assert.ok(!JSON.stringify(sent).includes("store-secret"));
});
