// The model benchmark harness (scripts/model-benchmark.mjs): its refusals (no key, CI, budget), the retry and timeout
// rules, the scoring, and a whole --dry-run against its fake provider. The live provider is only exercised against a
// fake `fetch`: nothing here reaches Anthropic and no test has run a real model.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, describe, test } from "node:test";

interface Task { id: string; category: string; user: string; notes?: unknown[]; tools?: string[]; forceTimeoutMs?: number; expect: Record<string, any> }
interface Result { outcome: string; status?: number; latencyMs?: number; text?: string; toolCalls: { name: string; input: Record<string, unknown> }[]; usage?: object; requestId?: string }
interface Provider { kind: string; complete(a: { model: string; task: Task }): Promise<Result> }
interface Summary { model: string; tasks: number; passes: number; completionRate: number | null; verifiedToolOutcomes: number | null; citationAccuracy: number | null;
  citationsWrong: number; timeoutsHandledSafely: boolean | null; latencyMs: { mean: number | null; p50: number | null; p95: number | null }; retries: number; costUsd: number | null; costPerSuccessUsd: number | null }
interface Script {
  parseArgs(argv: string[]): { options: Record<string, any>; errors: string[] };
  loadFixtures(file: string): { tasks: Task[]; system: string; tools: Record<string, any> };
  score(task: Task, result: Result): { pass: boolean; completed: boolean; tool: string | null; citation: any; checks: Record<string, boolean>; handledSafely?: boolean };
  parseAnswer(text: string): { answer: string; sources: string[]; structured: boolean };
  runTask(p: Provider, model: string, task: Task, maxRetries: number): Promise<{ result: Result; retries: number }>;
  fakeProvider(): Provider;
  liveProvider(key: string, fixtures: unknown, fetchImpl: typeof fetch): Provider;
  percentile(sorted: number[], p: number): number | null;
  run(argv: string[], io?: Record<string, any>): Promise<number>;
  DEFAULT_FIXTURES: string;
}
const script = (await import(new URL("../../scripts/model-benchmark.mjs", import.meta.url).href)) as Script;
const fixtures = script.loadFixtures(script.DEFAULT_FIXTURES);
const byId = (id: string) => fixtures.tasks.find((t) => t.id === id)!;

const tmp = mkdtempSync(path.join(tmpdir(), "bench-test-"));
after(() => rmSync(tmp, { recursive: true, force: true }));

async function runCli(argv: string[], io: Record<string, any> = {}) {
  const out: string[] = [];
  const err: string[] = [];
  const code = await script.run(argv, { stdout: (s: string) => out.push(s), stderr: (s: string) => err.push(s), env: {}, ...io });
  return { code, out: out.join("\n"), err: err.join("\n") };
}

describe("fixtures and options", () => {
  test("the fixture set covers Polish requests, note recall, cancellation, timeouts and tool confirmation, with synthetic data only", () => {
    const cats = new Set(fixtures.tasks.map((t) => t.category));
    for (const c of ["polish_request", "note_recall", "cancellation", "provider_timeout", "tool_confirmation"]) assert.ok(cats.has(c), c);
    assert.ok(fixtures.tasks.some((t) => t.category === "note_recall" && t.expect.sources?.length === 0), "a no-match recall case");
    assert.ok(fixtures.tasks.some((t) => t.expect.noToolCall), "a case where the right move is no tool call");
    assert.ok(!/@|https?:\/\/|\+48/.test(JSON.stringify(fixtures.tasks)), "no addresses, links or phone numbers");
  });

  test("options are validated", () => {
    assert.deepEqual(script.parseArgs([]).errors, []);
    assert.ok(script.parseArgs(["--repeat", "99"]).errors.length);
    assert.ok(script.parseArgs(["--max-retries", "5"]).errors.length);
    assert.ok(script.parseArgs(["--models", "bad model!"]).errors.length);
    assert.ok(script.parseArgs(["--api-key", "x"]).errors.length, "the key is never taken as an argument");
    assert.deepEqual(script.parseArgs(["--models", "a1,b2"]).options.models, ["a1", "b2"]);
  });
});

describe("scoring", () => {
  const ok = (text: object, toolCalls: Result["toolCalls"] = []): Result => ({ outcome: "ok", text: JSON.stringify(text), toolCalls, latencyMs: 1 });
  test("a right cited answer passes; a wrong or missing citation fails; no-match must have no sources", () => {
    const t = byId("note-dentist");
    assert.ok(script.score(t, ok({ answer: "W piątek o 9:00.", sources: ["n1"] })).pass);
    const wrong = script.score(t, ok({ answer: "W piątek o 9:00.", sources: ["n2"] }));
    assert.deepEqual([wrong.pass, wrong.citation.correct, wrong.citation.wrong, wrong.citation.missed], [false, 0, 1, 1]);
    assert.equal(script.score(t, ok({ answer: "W piątek o 9:00.", sources: [] })).pass, false);
    const none = byId("note-no-match");
    assert.ok(script.score(none, ok({ answer: "Nie znalazłem takiej notatki.", sources: [] })).pass);
    assert.equal(script.score(none, ok({ answer: "Nie wiem, kod to 4821.", sources: ["n2"] })).pass, false);
  });

  test("a tool call is verified only when the name and the arguments match; saying it was done fails whatever was called", () => {
    const t = byId("confirm-sms");
    const right = [{ name: "propose_send_text", input: { to: "Anna", body: "Będę o 18" } }];
    assert.ok(script.score(t, ok({ answer: "Przygotowałem SMS do potwierdzenia.", sources: [] }, right)).pass);
    assert.equal(script.score(t, ok({ answer: "Wysłałem SMS.", sources: [] }, right)).pass, false, "claims it was sent");
    const wrongBody = [{ name: "propose_send_text", input: { to: "Anna", body: "Będę o 19" } }];
    assert.equal(script.score(t, ok({ answer: "Do potwierdzenia.", sources: [] }, wrongBody)).tool, "failed");
    const extra = [...right, { name: "propose_send_text", input: { to: "Ola", body: "x" } }];
    assert.equal(script.score(t, ok({ answer: "Do potwierdzenia.", sources: [] }, extra)).tool, "failed", "a second, unrequested call fails");
    const miss = byId("confirm-missing-recipient");
    assert.ok(script.score(miss, ok({ answer: "Do kogo wysłać?", sources: [] })).pass);
    assert.equal(script.score(miss, ok({ answer: "Do kogo?", sources: [] }, right)).pass, false);
  });

  test("a timeout is never an answer: the timeout task passes only when it is reported as a timeout", () => {
    const t = byId("timeout-handled");
    assert.ok(script.score(t, { outcome: "timeout", toolCalls: [] }).handledSafely);
    assert.equal(script.score(t, ok({ answer: "cześć", sources: [] })).pass, false);
    const normal = script.score(byId("pl-percent"), { outcome: "timeout", toolCalls: [] });
    assert.deepEqual([normal.pass, normal.completed], [false, false]);
  });

  test("answers that are not JSON are still read as text", () => {
    assert.deepEqual(script.parseAnswer("zwykły tekst"), { answer: "zwykły tekst", sources: [], structured: false });
    assert.equal(script.parseAnswer('Oto: {"answer":"a","sources":["n1"]}').sources[0], "n1");
  });
  test("percentiles", () => {
    assert.equal(script.percentile([], 95), null);
    assert.equal(script.percentile([10, 20, 30, 40, 50, 60, 70, 80, 90, 100], 95), 100);
    assert.equal(script.percentile([10, 20, 30, 40, 50, 60, 70, 80, 90, 100], 50), 50);
  });
});

describe("retries and timeouts", () => {
  const scripted = (...results: Result[]): Provider & { calls: number } => {
    const p = { kind: "scripted", calls: 0, async complete() { return results[Math.min(p.calls++, results.length - 1)]!; } };
    return p;
  };
  const task = byId("pl-percent");
  test("a definite transient error is retried up to the limit; a timeout is not retried; a 400 is not retried", async () => {
    const flaky = scripted({ outcome: "error", status: 529, toolCalls: [] }, { outcome: "error", status: 529, toolCalls: [] }, { outcome: "ok", text: "{}", toolCalls: [] });
    assert.equal((await script.runTask(flaky, "m", task, 1)).retries, 1);
    assert.equal(flaky.calls, 2, "one retry, then it stops");
    assert.equal((await script.runTask(scripted({ outcome: "timeout", toolCalls: [] }), "m", task, 2)).retries, 0);
    const bad = scripted({ outcome: "error", status: 400, toolCalls: [] });
    assert.equal((await script.runTask(bad, "m", task, 2)).retries, 0);
    assert.equal(bad.calls, 1);
    const timeout = scripted({ outcome: "timeout", toolCalls: [] });
    await script.runTask(timeout, "m", task, 2);
    assert.equal(timeout.calls, 1, "an unknown outcome is never sent again");
  });
});

describe("--dry-run with the fake provider", () => {
  test("needs no key and no network; shows the report and writes the JSON outside the repository", async () => {
    const out = path.join(tmp, "dry.json");
    const r = await runCli(["--dry-run", "--out", out]);
    assert.equal(r.code, 0, r.err);
    assert.match(r.out, /DRY RUN: a fake provider/);
    assert.match(r.out, /fake-good/);
    assert.ok(existsSync(out));
    const report = JSON.parse(readFileSync(out, "utf8"));
    assert.equal(report.mode, "dry-run");
    const [good, cheap, flaky] = report.models as Summary[];
    assert.deepEqual([good!.model, cheap!.model, flaky!.model], ["fake-good", "fake-cheap", "fake-flaky"]);

    // The good fake passes every task, including the timeout check.
    assert.equal(good!.passes, good!.tasks);
    assert.deepEqual([good!.completionRate, good!.verifiedToolOutcomes, good!.citationAccuracy, good!.timeoutsHandledSafely], [1, 1, 1, true]);
    assert.ok(good!.costPerSuccessUsd !== null && good!.costPerSuccessUsd > 0);
    assert.equal(good!.retries, 0);
    // The cheap fake is cheaper per call but wrong where it matters: tools, citations.
    assert.ok(cheap!.passes < cheap!.tasks);
    assert.ok(cheap!.verifiedToolOutcomes! < 1);
    assert.ok(cheap!.citationAccuracy! < 1 && cheap!.citationsWrong > 0);
    // The flaky fake is right but retried once per task and slow.
    assert.equal(flaky!.passes, flaky!.tasks);
    assert.equal(flaky!.retries, flaky!.tasks);
    assert.ok(flaky!.latencyMs.p95! > good!.latencyMs.p95!);
    assert.ok(good!.latencyMs.p50! > 0 && good!.latencyMs.p95! >= good!.latencyMs.p50!);
    assert.match(report.notice, /No model change is justified/);
  });

  test("--repeat multiplies the runs", async () => {
    const out = path.join(tmp, "rep.json");
    const r = await runCli(["--dry-run", "--repeat", "3", "--models", "fake-good", "--out", out]);
    assert.equal(r.code, 0, r.err);
    assert.equal(JSON.parse(readFileSync(out, "utf8")).rows.length, fixtures.tasks.length * 3);
  });
});

describe("live mode refuses to start", () => {
  test("without a key", async () => {
    const r = await runCli([]);
    assert.equal(r.code, 2);
    assert.match(r.err, /No ANTHROPIC_API_KEY/);
  });
  test("in CI, even with a key", async () => {
    const r = await runCli([], { env: { CI: "true", ANTHROPIC_API_KEY: "sk-ant-test-secret" } });
    assert.equal(r.code, 2);
    assert.match(r.err, /Refusing to run live in CI/);
    assert.ok(!r.out.includes("sk-ant-test-secret") && !r.err.includes("sk-ant-test-secret"), "the key is never printed");
  });
  test("when the worst case is above the cost limit, or a model has no price", async () => {
    const big = await runCli(["--models", "claude-fable-5-1", "--repeat", "10", "--max-cost-usd", "0.01"], { env: { ANTHROPIC_API_KEY: "k" } });
    assert.equal(big.code, 2);
    assert.match(big.err, /above --max-cost-usd/);
    const unknown = await runCli(["--models", "claude-unpriced-9"], { env: { ANTHROPIC_API_KEY: "k" } });
    assert.equal(unknown.code, 2);
    assert.match(unknown.err, /no price/);
  });
  test("when --out is inside the repository", async () => {
    const r = await runCli(["--dry-run", "--out", path.join(path.dirname(script.DEFAULT_FIXTURES), "x.json")]);
    assert.equal(r.code, 2);
    assert.match(r.err, /inside the repository/);
  });
  test("bad options are refused before anything runs", async () => {
    assert.equal((await runCli(["--repeat", "0", "--dry-run"])).code, 2);
  });
});

describe("the live provider against a fake fetch", () => {
  const reply = (body: object, status = 200, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });
  test("sends the key in a header, offers the task's tools, reads a tool call and the usage", async () => {
    const seen: { url: string; init: RequestInit }[] = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      seen.push({ url, init });
      return reply({ content: [{ type: "text", text: '{"answer":"ok","sources":[]}' }, { type: "tool_use", name: "cancel_errand", input: { id: "err-17" } }],
        usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 3 } }, 200, { "request-id": "req_x" });
    }) as unknown as typeof fetch;
    const p = script.liveProvider("test-key", fixtures, fetchImpl);
    const r = await p.complete({ model: "claude-haiku-5-5", task: byId("cancel-yes") });
    assert.equal(seen[0]!.url, "https://api.anthropic.com/v1/messages");
    assert.equal((seen[0]!.init.headers as Record<string, string>)["x-api-key"], "test-key");
    const body = JSON.parse(String(seen[0]!.init.body));
    assert.deepEqual(body.tools.map((t: { name: string }) => t.name), ["cancel_errand"]);
    assert.ok(!JSON.stringify(body).includes("test-key"));
    assert.deepEqual(r.toolCalls, [{ name: "cancel_errand", input: { id: "err-17" } }]);
    assert.deepEqual(r.usage, { inputTokens: 10, outputTokens: 5, cacheReadTokens: 3, cacheWriteTokens: 0 });
    assert.equal(r.requestId, "req_x");
  });
  test("an HTTP error carries its status; an aborted call is a timeout", async () => {
    const down = script.liveProvider("k", fixtures, (async () => reply({}, 529)) as unknown as typeof fetch);
    assert.deepEqual(await down.complete({ model: "m1", task: byId("pl-percent") }).then((r) => [r.outcome, r.status]), ["error", 529]);
    const slow = script.liveProvider("k", fixtures, ((_u: string, init: RequestInit) => new Promise((_res, rej) => {
      init.signal!.addEventListener("abort", () => rej(Object.assign(new Error("aborted"), { name: "AbortError" })));
    })) as unknown as typeof fetch);
    assert.equal((await slow.complete({ model: "m1", task: byId("timeout-handled") })).outcome, "timeout");
  });
});
