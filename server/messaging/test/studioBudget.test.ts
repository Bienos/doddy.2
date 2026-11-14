// Studio's per-job dollar limit is enforced BEFORE each paid call (pre-call ceiling, clamp, reserve, settle).
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  CEILING_MARGIN, ceilingUsd, CHARS_PER_TOKEN, JobReservations, MIN_USEFUL_OUTPUT_TOKENS, planCall, REQUEST_OVERHEAD_TOKENS, UNKNOWN_OUTCOME_SHARE,
} from "../src/studio/budget.js";
import { HAIKU, OPUS, PER_SEARCH_USD, SONNET, STEP_MAX_OUTPUT, tokenCostUsd } from "../src/studio/models.js";
import { roundUsd, runStudio, type StudioControl } from "../src/studio/pipeline.js";
import type { Stage } from "../src/studio/schema.js";
import { content, FakeStudioApi, job, usage } from "./studioFakes.js";

const control = (over: Partial<StudioControl> = {}) => {
  const logs: { msg: string; extra?: object }[] = [];
  const c: StudioControl = {
    deadline: new Date(Date.now() + 60_000), isCancelled: async () => false, setStage: async (_s: Stage) => {},
    jobLimitUsd: 50, cancelPollMs: 5, log: (msg, extra) => logs.push({ msg, extra }), ...over,
  };
  return { c, logs };
};
const codeOf = (o: { kind: string; code?: string }) => (o.kind === "failed" ? o.code : o.kind);
const opus = (input: number, output: number) => tokenCostUsd(OPUS, { inputTokens: input, cacheWriteTokens: 0, cacheReadTokens: 0, outputTokens: output });

describe("the ceiling maths", () => {
  test("prompt estimate at the model's prices, cache-write price, searches and max_tokens at the output price", () => {
    const tokens = 10_000 / CHARS_PER_TOKEN + REQUEST_OVERHEAD_TOKENS; // 9,000
    const plain = ceilingUsd({ step: "write", model: SONNET, inputChars: 10_000 }, 10_000);
    assert.ok(Math.abs(plain.inputUsd - (tokens * 2 * CEILING_MARGIN) / 1e6) < 1e-12);
    assert.equal(plain.searchUsd, 0);
    assert.ok(Math.abs(plain.ceilingUsd - (plain.inputUsd + (10_000 * 10) / 1e6)) < 1e-12);
    const cached = ceilingUsd({ step: "research", model: SONNET, inputChars: 10_000, cacheWrite: true, searchesLeft: 4 }, 0);
    assert.ok(Math.abs(cached.inputUsd - plain.inputUsd * 1.25) < 1e-12, "a request that caches is priced as a cache write");
    assert.ok(Math.abs(cached.searchUsd - 4 * PER_SEARCH_USD) < 1e-12);
  });

  test("Haiku's long-prompt tier applies when the estimated prompt passes 100,000 tokens; an unknown model is priced as the dearest", () => {
    const short = ceilingUsd({ step: "write", model: HAIKU, inputChars: 100_000 }, 1_000);
    const long = ceilingUsd({ step: "write", model: HAIKU, inputChars: 200_000 }, 1_000);
    assert.ok(Math.abs(short.ceilingUsd - ((54_000 * 0.1 * CEILING_MARGIN + 1_000 * 0.5) / 1e6)) < 1e-9);
    assert.ok(Math.abs(long.ceilingUsd - ((104_000 * 0.5 * CEILING_MARGIN + 1_000 * 2.5) / 1e6)) < 1e-9);
    const unknown = ceilingUsd({ step: "write", model: "claude-new-9", inputChars: 0 }, 1_000);
    assert.ok(unknown.ceilingUsd > ceilingUsd({ step: "write", model: OPUS, inputChars: 0 }, 1_000).ceilingUsd);
  });

  test("planCall clamps max_tokens down to what fits, never above the step's usual, and refuses when the minimum useful reply doesn't fit", () => {
    const spec = { step: "write" as const, model: SONNET, inputChars: 20_000 };
    const roomy = planCall(spec, 50)!;
    assert.equal(roomy.maxTokens, STEP_MAX_OUTPUT.write);
    const tight = planCall(spec, 0.1)!;
    assert.ok(tight.maxTokens < STEP_MAX_OUTPUT.write && tight.maxTokens >= MIN_USEFUL_OUTPUT_TOKENS.write);
    assert.ok(tight.ceilingUsd <= 0.1 + 1e-12, "the clamped ceiling fits the remaining budget");
    assert.ok(planCall(spec, 0.1 + 0.0005)!.maxTokens >= tight.maxTokens);
    const inputOnly = ceilingUsd(spec, 0).ceilingUsd;
    assert.equal(planCall(spec, inputOnly), undefined, "no room for any output");
    assert.equal(planCall(spec, inputOnly + (MIN_USEFUL_OUTPUT_TOKENS.write - 1) * 10 / 1e6), undefined, "room for less than a minimal reply");
    assert.ok(planCall(spec, inputOnly + (MIN_USEFUL_OUTPUT_TOKENS.write + 1) * 10 / 1e6));
    assert.equal(planCall(spec, -1), undefined);
  });

  test("the reservation ledger is idempotent per call id: reserving or settling twice never double counts", () => {
    const r = new JobReservations();
    assert.equal(r.reserve("write#1", 1), true);
    assert.equal(r.reserve("write#1", 1), false, "a retry or resume of the same call doesn't reserve again");
    assert.equal(r.openUsd, 1);
    assert.equal(r.settle("write#1"), true);
    assert.equal(r.settle("write#1"), false);
    assert.equal(r.reserve("write#1", 1), false, "a finished call can't be reserved again");
    assert.deepEqual([r.openUsd, r.unknownUsd], [0, 0]);
    r.reserve("make#2", 2);
    assert.equal(r.unknown("make#2"), true);
    assert.equal(r.unknown("make#2"), false);
    assert.equal(r.settle("make#2"), false, "a call whose outcome is unknown isn't later counted as free");
    assert.equal(r.unknownUsd, 2 * UNKNOWN_OUTCOME_SHARE);
    r.reserve("pack#3", 3);
    assert.equal(r.release("pack#3"), true);
    assert.deepEqual([r.openUsd, r.unknownUsd], [0, 1]);
  });
});

describe("the job's dollar limit is checked before a call, not after", () => {
  test("regression: a $0.05 limit used to stop only after ~$0.204 of simulated usage; now no call that could cross it is sent", async () => {
    const api = new FakeStudioApi();
    const { c, logs } = control({ jobLimitUsd: 0.05 });
    const out = await runStudio(api, job, c);
    assert.equal(codeOf(out), "cost_limit");
    assert.ok(out.costUsd <= 0.05, `spent ${out.costUsd}, over the $0.05 limit`);
    assert.deepEqual(api.calls, [], "not even the plan's worst case fits $0.05 on Opus, so nothing was sent");
    assert.ok(logs.some((l) => l.msg.startsWith("studio call not sent")));
    assert.ok(!JSON.stringify(logs).includes(job.topic), "no job text in the logs");
  });

  test("with room for the plan but not for research, the plan runs, research is never sent, and the job ends cost_limit within its limit", async () => {
    const api = new FakeStudioApi();
    const out = await runStudio(api, job, control({ jobLimitUsd: 0.3 }).c);
    assert.equal(codeOf(out), "cost_limit");
    assert.deepEqual(api.calls, ["plan"]);
    assert.equal(out.costUsd, roundUsd(opus(1000, 500)), "the plan settled from its reported usage, nothing else counted");
  });

  test("max_tokens is clamped to the remaining budget so that each call's ceiling fits it", async () => {
    const api = new FakeStudioApi();
    const out = await runStudio(api, job, control({ jobLimitUsd: 2 }).c);
    assert.equal(out.kind, "made");
    const research = api.maxTokens.research![0]!;
    assert.ok(research < STEP_MAX_OUTPUT.research && research >= MIN_USEFUL_OUTPUT_TOKENS.research, `research got ${research}`);
    assert.ok(api.maxTokens.plan![0]! <= STEP_MAX_OUTPUT.plan);
    assert.ok(out.costUsd <= 2, `spent ${out.costUsd}`);
    // With a roomy limit nothing is clamped.
    const roomy = new FakeStudioApi();
    await runStudio(roomy, job, control({ jobLimitUsd: 50 }).c);
    assert.deepEqual([roomy.maxTokens.plan![0], roomy.maxTokens.research![0], roomy.maxTokens.write![0], roomy.maxTokens.make![0]],
      [STEP_MAX_OUTPUT.plan, STEP_MAX_OUTPUT.research, STEP_MAX_OUTPUT.write, STEP_MAX_OUTPUT.make]);
  });

  test("across limits: no call is ever sent whose ceiling exceeds what was left, and a failed job never reports more than its limit", async () => {
    for (const limit of [0.05, 0.2, 0.5, 1, 1.6, 2, 3, 6]) {
      const api = new FakeStudioApi();
      const out = await runStudio(api, job, control({ jobLimitUsd: limit }).c);
      if (out.kind !== "made") assert.equal(codeOf(out), "cost_limit", `limit ${limit}`);
      // The fake's usage is small, so a made job can't have passed its limit either.
      assert.ok(out.costUsd <= limit + 1e-9, `limit ${limit}: reported ${out.costUsd}`);
    }
  });

  test("settle after the response: the reservation is replaced by the reported usage, so the cost is exactly the priced usage", async () => {
    const api = new FakeStudioApi();
    const out = await runStudio(api, job, control({ jobLimitUsd: 2 }).c);
    assert.equal(out.kind, "made");
    const expected = opus(1000, 500) + opus(20_000, 4_000) + 3 * PER_SEARCH_USD + opus(1000, 500) + opus(1000, 500) + opus(5000, 2000);
    assert.equal(out.costUsd, roundUsd(expected), "no reservation or ceiling is left in the reported cost");
  });

  test("a write retry gets its own reservation and settlement; retries don't double count", async () => {
    const api = new FakeStudioApi();
    const broken = content();
    broken.infographic.facts = [];
    api.writes.push({ kind: "ok", value: broken, usage: usage() }, { kind: "ok", value: broken, usage: usage() });
    const out = await runStudio(api, job, control({ jobLimitUsd: 2 }).c);
    assert.equal(out.kind, "made");
    assert.equal(api.calls.filter((s) => s === "write").length, 3);
    const expected = opus(1000, 500) + opus(20_000, 4_000) + 3 * PER_SEARCH_USD + opus(1000, 500) + 3 * opus(1000, 500) + opus(5000, 2000);
    assert.equal(out.costUsd, roundUsd(expected));
  });

  test("a call that fails after it was sent has an unknown outcome: part of its ceiling stays counted, not free", async () => {
    const api = new FakeStudioApi();
    api.onCall = (s) => { if (s === "write") throw new Error("socket hang up"); };
    const out = await runStudio(api, job, control({ jobLimitUsd: 2 }).c);
    assert.equal(codeOf(out), "provider_error");
    const settled = opus(1000, 500) + opus(20_000, 4_000) + 3 * PER_SEARCH_USD + opus(1000, 500);
    assert.ok(out.costUsd > roundUsd(settled) + 0.05, `the unknown write counted ${roundUsd(out.costUsd - settled)}`);
    assert.ok(out.costUsd <= 2);
    // A timeout (the abort the deadline fires) is the same.
    const slow = new FakeStudioApi();
    slow.onCall = async (s) => { if (s === "write") await new Promise((r) => setTimeout(r, 200)); };
    const out2 = await runStudio(slow, job, control({ jobLimitUsd: 2, deadline: new Date(Date.now() + 80) }).c);
    assert.equal(codeOf(out2), "time_limit");
    assert.ok(out2.costUsd > roundUsd(settled));
  });

  test("a call stopped before it was sent (Cancel) costs nothing", async () => {
    const api = new FakeStudioApi();
    let cancelled = false;
    api.onCall = (s) => { if (s === "plan") cancelled = true; };
    const out = await runStudio(api, job, control({ jobLimitUsd: 2, isCancelled: async () => cancelled }).c);
    assert.equal(out.kind, "cancelled");
    assert.deepEqual(api.calls, ["plan"]);
    assert.equal(out.costUsd, roundUsd(opus(1000, 500)));
  });

  test("a reply with no usage may still have been billed: it keeps the allowance counted", async () => {
    const api = new FakeStudioApi();
    api.plans.push({ kind: "unparsed" });
    const out = await runStudio(api, job, control({ jobLimitUsd: 2 }).c);
    assert.equal(codeOf(out), "unreadable_result");
    assert.ok(out.costUsd > 0, "an unreadable reply without usage isn't free");
  });

  test("an interrupted run (worker shutdown) before a call is sent costs nothing and sends nothing", async () => {
    const api = new FakeStudioApi();
    const ac = new AbortController();
    ac.abort();
    const out = await runStudio(api, job, control({ signal: ac.signal }).c);
    assert.equal(codeOf(out), "interrupted");
    assert.deepEqual([api.calls, out.costUsd], [[], 0]);
  });
});
