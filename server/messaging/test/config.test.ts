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
