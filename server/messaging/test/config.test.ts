import assert from "node:assert/strict";
import { test } from "node:test";
import { loadConfig } from "../src/config.js";

test("empty variables count as unset, and task calls stay off until fully configured", () => {
  const c = loadConfig({
    DATABASE_URL: "postgres://x/y", TWILIO_TASK_ACCOUNT_SID: "", TASK_CALL_FROM_NUMBER: "", ELEVENLABS_WEBHOOK_SECRET: "",
    PRICE_ELEVENLABS_USD_PER_CREDIT: "", TASK_CALLS_KILL_SWITCH: "", CALL_RECORDING_NOTICE: "",
  });
  assert.equal(c.taskCalls, undefined);
  assert.equal(c.taskCallSettings.killSwitch, false);
  assert.equal(c.taskCallSettings.notice, "off");
  assert.equal(c.taskCallSettings.prices.elevenLabsUsdPerCredit, undefined);
});

test("limits can only be lowered below the code's ceilings", () => {
  assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", TASK_CALL_LIMIT_USER_HOUR: "4" }));
  assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", TASK_CALL_MAX_SECS: "301" }));
  assert.equal(loadConfig({ DATABASE_URL: "postgres://x/y", TASK_CALL_LIMIT_USER_HOUR: "1" }).taskCallSettings.limits.userPerHour, 1);
});

test("errands: off by default (switched on with ERRANDS_ENABLED=1), Opus 5.5 at high effort, 30 minutes, 5 open; empty values count as unset", () => {
  const c = loadConfig({ DATABASE_URL: "postgres://x/y", ERRANDS_ENABLED: "", ERRANDS_MODEL: "", ERRANDS_EFFORT: "" });
  assert.deepEqual(c.errandSettings, { enabled: false, model: "claude-opus-5-5", effort: "high", timeLimitMinutes: 30, maxOpen: 5 });
  assert.equal(loadConfig({ DATABASE_URL: "postgres://x/y", ERRANDS_ENABLED: "1" }).errandSettings.enabled, true);
  const set = loadConfig({
    DATABASE_URL: "postgres://x/y", ERRANDS_ENABLED: "0", ERRANDS_MODEL: "claude-sonnet-5-5", ERRANDS_EFFORT: "xhigh",
    ERRAND_TIME_LIMIT_MINUTES: "45", ERRANDS_MAX_OPEN: "2",
  });
  assert.deepEqual(set.errandSettings, { enabled: false, model: "claude-sonnet-5-5", effort: "xhigh", timeLimitMinutes: 45, maxOpen: 2 });
});

test("errands: effort, time limit, open limit and the switch are validated", () => {
  for (const effort of ["low", "medium", "high", "xhigh", "max"]) {
    assert.equal(loadConfig({ DATABASE_URL: "postgres://x/y", ERRANDS_EFFORT: effort }).errandSettings.effort, effort);
  }
  const bad: Record<string, string>[] = [
    { ERRANDS_EFFORT: "extreme" }, { ERRANDS_EFFORT: "HIGH" }, { ERRANDS_ENABLED: "yes" },
    { ERRAND_TIME_LIMIT_MINUTES: "0" }, { ERRAND_TIME_LIMIT_MINUTES: "121" }, { ERRAND_TIME_LIMIT_MINUTES: "2.5" },
    { ERRANDS_MAX_OPEN: "0" }, { ERRANDS_MAX_OPEN: "21" }, { ERRANDS_MODEL: "Claude Opus" },
  ];
  for (const env of bad) assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", ...env }), JSON.stringify(env));
});

test("errands get a researcher only with an Anthropic key and the switch on", async () => {
  const { providersFrom } = await import("../src/providers/index.js");
  const base = { DATABASE_URL: "postgres://x/y", MEMORY_ENCRYPTION_KEY: Buffer.alloc(32, 3).toString("base64") };
  assert.equal(providersFrom(loadConfig(base)).errands.researcher, undefined);
  // Keyed but not switched on: still none, because ERRANDS_ENABLED defaults to "0".
  assert.equal(providersFrom(loadConfig({ ...base, ANTHROPIC_API_KEY: "test-key" })).errands.researcher, undefined);
  const keyed = providersFrom(loadConfig({ ...base, ANTHROPIC_API_KEY: "test-key", ERRANDS_ENABLED: "1", ERRANDS_EFFORT: "max" })).errands;
  assert.equal(keyed.researcher?.model, "claude-opus-5-5");
  assert.equal(providersFrom(loadConfig({ ...base, ANTHROPIC_API_KEY: "test-key", ERRANDS_ENABLED: "0" })).errands.researcher, undefined);
});

test("studio: off by default; the cheap model mix, $2 a job and $3 a day, 15 searches; empty values count as unset", () => {
  const c = loadConfig({ DATABASE_URL: "postgres://x/y", STUDIO_ENABLED: "", STUDIO_MODEL: "", STUDIO_SKILLS: "" });
  assert.deepEqual(c.studioSettings, {
    enabled: false, models: { plan: "claude-haiku-5-5", research: "claude-sonnet-5-5", pack: "claude-haiku-5-5", write: "claude-sonnet-5-5", make: "claude-haiku-5-5" },
    skills: "", maxSearches: 15, maxFetches: 15, blockedDomains: [], taskBudgetTokens: 150_000, jobLimitUsd: 2, dailyCapUsd: 3, timeLimitMinutes: 20, maxOpen: 3,
  });
  assert.equal(loadConfig({ DATABASE_URL: "postgres://x/y", STUDIO_ENABLED: "1" }).studioSettings.enabled, true);
});

test("studio: STUDIO_MODEL sets every step first, a step variable overrides it, bad ids and values are refused", () => {
  const all = loadConfig({ DATABASE_URL: "postgres://x/y", STUDIO_MODEL: "claude-opus-5-5" }).studioSettings.models;
  assert.deepEqual(Object.values(all), Array(5).fill("claude-opus-5-5"));
  const mixed = loadConfig({ DATABASE_URL: "postgres://x/y", STUDIO_MODEL: "claude-sonnet-5-5", STUDIO_MODEL_RESEARCH: "claude-opus-5-5", STUDIO_MODEL_MAKE: "claude-haiku-5-5" }).studioSettings.models;
  assert.deepEqual(mixed, { plan: "claude-sonnet-5-5", research: "claude-opus-5-5", pack: "claude-sonnet-5-5", write: "claude-sonnet-5-5", make: "claude-haiku-5-5" });
  const set = loadConfig({
    DATABASE_URL: "postgres://x/y", STUDIO_SKILLS: "skill_a@skver_1,skill_b", STUDIO_MAX_SEARCHES: "8", STUDIO_BLOCKED_DOMAINS: "spam.example,farm.example",
    STUDIO_JOB_LIMIT_USD: "1.5", STUDIO_DAILY_CAP_USD: "2", STUDIO_TASK_BUDGET_TOKENS: "20000",
  }).studioSettings;
  assert.deepEqual([set.skills, set.maxSearches, set.blockedDomains, set.jobLimitUsd, set.dailyCapUsd, set.taskBudgetTokens],
    ["skill_a@skver_1,skill_b", 8, ["spam.example", "farm.example"], 1.5, 2, 20_000]);
  for (const bad of [{ STUDIO_MODEL_PLAN: "Not A Model!" }, { STUDIO_TASK_BUDGET_TOKENS: "1000" }, { STUDIO_JOB_LIMIT_USD: "0" }, { STUDIO_BLOCKED_DOMAINS: "http://x.example" }, { STUDIO_SKILLS: "bad skill" }]) {
    assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", ...bad }), JSON.stringify(bad));
  }
});
