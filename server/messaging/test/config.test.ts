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

test("Messages: off by default, Haiku 5.5 at medium effort, 100 per account and 1000 per server; caps only go down", () => {
  const base = { DATABASE_URL: "postgres://x/y" };
  const c = loadConfig({ ...base, ASSISTANT_ENABLED: "", ASSISTANT_MODEL: "", ASSISTANT_EFFORT: "" });
  assert.deepEqual(c.assistantSettings, { enabled: false, model: "claude-haiku-5-5", effort: "medium", dailyPerAccount: 100, dailyPerServer: 1000 });
  const on = loadConfig({ ...base, ASSISTANT_ENABLED: "1", ASSISTANT_MODEL: "claude-sonnet-5-5", ASSISTANT_EFFORT: "low", ASSISTANT_DAILY_PER_ACCOUNT: "20", ASSISTANT_DAILY_PER_SERVER: "200" });
  assert.deepEqual(on.assistantSettings, { enabled: true, model: "claude-sonnet-5-5", effort: "low", dailyPerAccount: 20, dailyPerServer: 200 });
  for (const bad of [{ ASSISTANT_ENABLED: "yes" }, { ASSISTANT_EFFORT: "max" }, { ASSISTANT_DAILY_PER_ACCOUNT: "0" },
    { ASSISTANT_DAILY_PER_ACCOUNT: "1001" }, { ASSISTANT_DAILY_PER_SERVER: "100001" }, { ASSISTANT_MODEL: "Claude Haiku" }]) {
    assert.throws(() => loadConfig({ ...base, ...bad }), JSON.stringify(bad));
  }
});

test("Messages gets a responder only with an Anthropic key and the switch on", async () => {
  const { providersFrom } = await import("../src/providers/index.js");
  const base = { DATABASE_URL: "postgres://x/y" };
  assert.equal(providersFrom(loadConfig(base)).assistant.responder, undefined);
  assert.equal(providersFrom(loadConfig({ ...base, ANTHROPIC_API_KEY: "test-key" })).assistant.responder, undefined, "keyed but not switched on");
  assert.equal(providersFrom(loadConfig({ ...base, ASSISTANT_ENABLED: "1" })).assistant.responder, undefined, "switched on but no key");
  const on = providersFrom(loadConfig({ ...base, ANTHROPIC_API_KEY: "test-key", ASSISTANT_ENABLED: "1", ASSISTANT_MODEL: "claude-sonnet-5-5" })).assistant;
  assert.equal(on.responder?.model, "claude-sonnet-5-5");
});

test("shopping errands (ADR-607, ADR-611): Haiku 5.5 for everyone, Sonnet 5.5 for listed premium accounts, 8 offer searches and 15 page reads, no Serper key unless set", () => {
  const c = loadConfig({ DATABASE_URL: "postgres://x/y", SHOPPING_MODEL: "", SERPER_API_KEY: "" });
  assert.deepEqual(c.shoppingSettings, {
    model: "claude-haiku-5-5", premiumModel: "claude-sonnet-5-5", premiumAccountIds: [],
    effort: "medium", maxOfferSearches: 8, maxPageChecks: 15, serperApiKey: undefined, affiliateRules: [],
  });
  const ids = ["0c5d3f2e-8d3a-4b3e-9a57-0f2f0f5a1111", "7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"];
  const set = loadConfig({
    DATABASE_URL: "postgres://x/y", SHOPPING_MODEL: "claude-sonnet-5-5", SHOPPING_PREMIUM_MODEL: "claude-opus-5-5", SHOPPING_EFFORT: "low",
    SHOPPING_PREMIUM_ACCOUNTS: ` ${ids[0]} , ${ids[1]},`,
    SHOPPING_MAX_OFFER_SEARCHES: "3", SHOPPING_MAX_PAGE_CHECKS: "5", SERPER_API_KEY: "serper-test-key",
  });
  assert.deepEqual(set.shoppingSettings, {
    model: "claude-sonnet-5-5", premiumModel: "claude-opus-5-5", premiumAccountIds: ids,
    effort: "low", maxOfferSearches: 3, maxPageChecks: 5, serperApiKey: "serper-test-key", affiliateRules: [],
  });
  for (const bad of [
    { SHOPPING_MAX_OFFER_SEARCHES: "0" }, { SHOPPING_MAX_OFFER_SEARCHES: "21" }, { SHOPPING_MAX_PAGE_CHECKS: "41" }, { SHOPPING_EFFORT: "extreme" },
    { SHOPPING_PREMIUM_ACCOUNTS: "not-an-account-id" }, { SHOPPING_PREMIUM_ACCOUNTS: `${ids[0]};${ids[1]}` },
  ]) {
    assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", ...bad }), JSON.stringify(bad));
  }
});

test("affiliate links (ADR-612): none by default; a rule is a shop host and an https template with one {url}", () => {
  assert.deepEqual(loadConfig({ DATABASE_URL: "postgres://x/y" }).shoppingSettings.affiliateRules, []);
  const tpl = "https://network.example/click?id=7&to={url}";
  const set = loadConfig({ DATABASE_URL: "postgres://x/y", AFFILIATE_LINKS: JSON.stringify({ "mediaexpert.pl": tpl }) });
  assert.deepEqual(set.shoppingSettings.affiliateRules, [{ host: "mediaexpert.pl", template: tpl }]);
  for (const bad of ["not json", "[]", '{"Media Expert": "https://n.example/?u={url}"}', '{"mediaexpert.pl": "https://n.example/"}',
    '{"mediaexpert.pl": "https://n.example/?a={url}&b={url}"}', '{"mediaexpert.pl": "http://n.example/?u={url}"}', '{"mediaexpert.pl": 5}']) {
    assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", AFFILIATE_LINKS: bad }), bad);
  }
});

test("leaflets (ADR-609): off by default, Haiku 5.5 reads pages, 40 pages per chain, 30 a day per account, 1000 per server", () => {
  const c = loadConfig({ DATABASE_URL: "postgres://x/y", DEALS_ENABLED: "" });
  assert.deepEqual(c.dealsSettings, { enabled: false, visionModel: "claude-haiku-5-5", maxPages: 40, dailyPerAccount: 30, dailyPerServer: 1000 });
  assert.equal(loadConfig({ DATABASE_URL: "postgres://x/y", DEALS_ENABLED: "1" }).dealsSettings.enabled, true);
  for (const bad of [{ DEALS_ENABLED: "yes" }, { DEALS_MAX_PAGES: "101" }, { DEALS_DAILY_PER_ACCOUNT: "0" }, { DEALS_VISION_MODEL: "Claude Haiku" }]) {
    assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", ...bad }), JSON.stringify(bad));
  }
});

test("price watches (shopping stage 2): off by default, 5 open, a check every 6 hours; empty values count as unset; limits are validated", () => {
  const c = loadConfig({ DATABASE_URL: "postgres://x/y", WATCHES_ENABLED: "", WATCHES_MAX_OPEN: "", WATCHES_CHECK_HOURS: "" });
  assert.deepEqual(c.watchSettings, { enabled: false, maxOpen: 5, checkHours: 6 });
  assert.deepEqual(loadConfig({ DATABASE_URL: "postgres://x/y" }).watchSettings, { enabled: false, maxOpen: 5, checkHours: 6 });
  assert.equal(loadConfig({ DATABASE_URL: "postgres://x/y", WATCHES_ENABLED: "1" }).watchSettings.enabled, true);
  const set = loadConfig({ DATABASE_URL: "postgres://x/y", WATCHES_ENABLED: "1", WATCHES_MAX_OPEN: "20", WATCHES_CHECK_HOURS: "24" });
  assert.deepEqual(set.watchSettings, { enabled: true, maxOpen: 20, checkHours: 24 });
  const low = loadConfig({ DATABASE_URL: "postgres://x/y", WATCHES_MAX_OPEN: "1", WATCHES_CHECK_HOURS: "1" });
  assert.deepEqual(low.watchSettings, { enabled: false, maxOpen: 1, checkHours: 1 });
  const bad: Record<string, string>[] = [
    { WATCHES_ENABLED: "yes" }, { WATCHES_ENABLED: "true" }, { WATCHES_MAX_OPEN: "0" }, { WATCHES_MAX_OPEN: "21" }, { WATCHES_MAX_OPEN: "2.5" },
    { WATCHES_CHECK_HOURS: "0" }, { WATCHES_CHECK_HOURS: "25" }, { WATCHES_CHECK_HOURS: "1.5" }, { WATCHES_CHECK_HOURS: "six" },
  ];
  for (const env of bad) assert.throws(() => loadConfig({ DATABASE_URL: "postgres://x/y", ...env }), JSON.stringify(env));
});

test("price watches read pages through the one shared polite fetcher, with the configured settings", async () => {
  const { providersFrom } = await import("../src/providers/index.js");
  const { PoliteFetcher } = await import("../src/deals/fetcher.js");
  const p = providersFrom(loadConfig({ DATABASE_URL: "postgres://x/y", WATCHES_ENABLED: "1", WATCHES_CHECK_HOURS: "12", WATCHES_MAX_OPEN: "3" }));
  assert.ok(p.watches.fetcher instanceof PoliteFetcher);
  assert.equal(p.watches.fetcher, p.deals.fetcher, "the same instance as the leaflets (one robots.txt cache, one user agent)");
  assert.deepEqual(p.watches.settings, { enabled: true, maxOpen: 3, checkHours: 12 });
});
