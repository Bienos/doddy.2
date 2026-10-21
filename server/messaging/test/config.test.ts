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
