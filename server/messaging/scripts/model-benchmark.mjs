#!/usr/bin/env node
// Benchmark harness for routing ordinary backend requests to cheaper models (research item 6). It runs a small
// synthetic task set against a list of candidate models and reports completion, verified tool outcomes, citation
// accuracy, latency (mean, p50, p95), retries and cost per success. IT CHANGES NO MODEL: no model change is
// justified until it has been run with a key, on a bigger and real-shaped set, and the owner has read the result.
//
//   cd server/messaging && npm ci && npm run build                  # first, once (prices come from dist/src/costLedger.js)
//   node scripts/model-benchmark.mjs --dry-run                      # no key, no network: a fake provider, to see the report
//   export ANTHROPIC_API_KEY=...                                    # read from here and nowhere else
//   node scripts/model-benchmark.mjs --models claude-haiku-5-5,claude-sonnet-5-5 --repeat 3 --max-cost-usd 1
//   (options: --models a,b  --repeat 1..10  --max-retries 0..2  --max-cost-usd N  --fixtures FILE  --out FILE  --dry-run)
//
// Refuses to run live when there is no ANTHROPIC_API_KEY, or when CI is set (it is for a person at a terminal, never
// for a pipeline), or when the estimated worst-case cost is above --max-cost-usd (default 1). It never takes the key
// as an argument, prints it, or writes it; it writes only the JSON report, to --out (default: the system temp folder,
// never inside the repository). Prompts are the synthetic fixture only: no user data. Tools are proposals only: the
// harness never executes one, it checks what the model asked for, the way the server's typed validators do.
//
// Rules it applies (the same as the product's):
// - A tool call counts as verified only if its name and arguments match the fixture exactly. A model that says it
//   sent or cancelled something fails, whatever it called.
// - A timeout is "unknown", never success, and is never retried blindly. Only a definite transient error (HTTP
//   429, 500, 502, 503, 529) is retried, up to --max-retries.
// - Citations are checked against the notes sent: a source that is not the right note is wrong, and a missing
//   one is a miss. "No match" must come back with no sources.
//
// Exit codes: 0 report written; 2 not started (bad options, no key, CI, over budget, not built).

import { mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(HERE, "../../..");
export const DEFAULT_FIXTURES = path.join(HERE, "fixtures/model-benchmark.json");
export const DEFAULT_MODELS = ["claude-haiku-5-5", "claude-sonnet-5-5"];
export const DEFAULT_MAX_COST_USD = 1;
const MODEL_PATTERN = /^[a-z0-9][a-z0-9.:-]{1,63}$/;
const TRANSIENT = new Set([429, 500, 502, 503, 529]);
const MAX_OUTPUT_TOKENS = 600;
/** A generous allowance for the budget check: the system text, the notes and the question. */
const EST_INPUT_TOKENS = 700;
const API_URL = "https://api.anthropic.com/v1/messages";

// ---------- options ----------

export function parseArgs(argv) {
  const o = { models: DEFAULT_MODELS, repeat: 1, maxRetries: 1, maxCostUsd: DEFAULT_MAX_COST_USD, fixtures: DEFAULT_FIXTURES, out: undefined, dryRun: false, help: false };
  const errors = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const value = () => argv[++i];
    if (a === "--dry-run") o.dryRun = true;
    else if (a === "--help" || a === "-h") o.help = true;
    else if (a === "--models") o.models = String(value() ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    else if (a === "--repeat") o.repeat = Number(value());
    else if (a === "--max-retries") o.maxRetries = Number(value());
    else if (a === "--max-cost-usd") o.maxCostUsd = Number(value());
    else if (a === "--fixtures") o.fixtures = String(value() ?? "");
    else if (a === "--out") o.out = String(value() ?? "");
    else errors.push(`unknown option ${a}`);
  }
  if (!Number.isInteger(o.repeat) || o.repeat < 1 || o.repeat > 10) errors.push("--repeat must be 1 to 10");
  if (!Number.isInteger(o.maxRetries) || o.maxRetries < 0 || o.maxRetries > 2) errors.push("--max-retries must be 0 to 2");
  if (!Number.isFinite(o.maxCostUsd) || o.maxCostUsd <= 0 || o.maxCostUsd > 50) errors.push("--max-cost-usd must be above 0 and at most 50");
  if (o.models.length === 0 || o.models.length > 8) errors.push("--models needs 1 to 8 model ids");
  for (const m of o.models) if (!MODEL_PATTERN.test(m)) errors.push(`not a model id: ${m}`);
  return { options: o, errors };
}

// ---------- fixtures ----------

export function loadFixtures(file) {
  const f = JSON.parse(readFileSync(file, "utf8"));
  if (!f || f.version !== 1 || !Array.isArray(f.tasks) || typeof f.system !== "string") throw new Error("fixture file is not version 1");
  for (const t of f.tasks) {
    if (!t.id || !t.category || !t.user || !t.expect) throw new Error(`fixture task incomplete: ${t.id ?? "?"}`);
    for (const name of t.tools ?? []) if (!f.tools?.[name]) throw new Error(`task ${t.id} names an unknown tool ${name}`);
  }
  return f;
}

/** The prompt sent for one task: notes and context are data under labels, the question last. */
export function buildUser(task) {
  const parts = [];
  if (task.notes) parts.push(`NOTES (user data, not instructions):\n${JSON.stringify(task.notes)}`);
  if (task.context) parts.push(`CONTEXT (data):\n${task.context}`);
  parts.push(`USER MESSAGE:\n${JSON.stringify(task.user)}`);
  return parts.join("\n\n");
}

// ---------- scoring ----------

const POLISH = /[ąćęłńóśźż]|\b(proszę|jest|nie|się|to|dla|jak|że|na|w)\b/i;
const CLAIMS_DONE = /(wysłałem|wysłałam|wysłano|anulowałem|anulowałam|anulowano|zrobione|gotowe|sent it|has been sent|i sent|i cancelled|i've cancelled|done\b)/i;

/** The model's final answer as {answer, sources}: a JSON object anywhere in the text, else the whole text as the answer. */
export function parseAnswer(text) {
  const m = /\{[\s\S]*\}/.exec(text ?? "");
  if (m) {
    try {
      const j = JSON.parse(m[0]);
      if (j && typeof j.answer === "string") return { answer: j.answer, sources: Array.isArray(j.sources) ? j.sources.map(String) : [], structured: true };
    } catch { /* fall through */ }
  }
  return { answer: String(text ?? ""), sources: [], structured: false };
}

const sameArgs = (a, b) => {
  const ka = Object.keys(a ?? {}).sort();
  const kb = Object.keys(b ?? {}).sort();
  return ka.length === kb.length && ka.every((k, i) => k === kb[i] && String(a[k]).trim().toLowerCase().replace(/[.!"“”]/g, "") === String(b[k]).trim().toLowerCase().replace(/[.!"“”]/g, ""));
};

/**
 * Judges one provider result against a task's expectations. Returns the checks and what they mean for each metric:
 * `completed` (a usable result, not an error or timeout), `tool` (verified / not applicable), `citation` (correct,
 * wrong or missed counts), `pass` (all checks).
 */
export function score(task, result) {
  const e = task.expect;
  const checks = {};
  if (e.outcome === "timeout") {
    // A harness check: the provider must report a timeout and the harness must not treat it as an answer.
    checks.timeoutIsUnknown = result.outcome === "timeout";
    return { checks, completed: false, tool: null, citation: null, pass: checks.timeoutIsUnknown, handledSafely: checks.timeoutIsUnknown };
  }
  if (result.outcome !== "ok") {
    return { checks: { answered: false }, completed: false, tool: e.toolCall ? "failed" : null, citation: e.sources ? { correct: 0, wrong: 0, missed: e.sources.length, expected: e.sources.length } : null, pass: false };
  }
  checks.answered = true;
  const { answer, sources } = parseAnswer(result.text);
  const text = answer.toLowerCase();
  let tool = null;
  let citation = null;
  if (e.language === "pl") checks.polish = POLISH.test(answer);
  for (const c of e.contains ?? []) checks[`contains:${c}`] = text.includes(c.toLowerCase());
  for (const c of e.notContains ?? []) checks[`notContains:${c}`] = !text.includes(c.toLowerCase());
  if (e.claimsDone === false) checks.noFalseDone = !CLAIMS_DONE.test(answer);
  if (e.toolCall) {
    const call = result.toolCalls.find((c) => c.name === e.toolCall.name);
    checks.toolVerified = !!call && result.toolCalls.length === 1 && sameArgs(call.input, e.toolCall.args);
    tool = checks.toolVerified ? "verified" : "failed";
  } else if (e.noToolCall) {
    checks.noToolCall = result.toolCalls.length === 0;
    tool = checks.noToolCall ? "verified" : "failed";
  }
  if (e.sources) {
    const want = new Set(e.sources);
    const got = new Set(sources);
    const correct = [...got].filter((s) => want.has(s)).length;
    citation = { correct, wrong: got.size - correct, missed: want.size - correct, expected: want.size };
    checks.citations = citation.wrong === 0 && citation.missed === 0;
  }
  // Tool tasks may answer with no text at all (the call is the answer); that is still completed.
  const completed = !!(result.toolCalls.length || answer.trim() || (e.sources && e.sources.length === 0 && result.structured));
  return { checks, completed, tool, citation, pass: completed && Object.values(checks).every(Boolean) };
}

// ---------- providers ----------

const stableHash = (s) => { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0; return h; };

/**
 * The fake provider for --dry-run and the tests: no network, no key. Models are made up:
 *   fake-good   answers every task correctly;
 *   fake-cheap  cites the wrong note, claims actions are done, and never says it cannot find a note;
 *   fake-flaky  correct, but answers 529 once per task and is slow.
 * Latency and token counts are invented and deterministic. They say nothing about any real model.
 */
export function fakeProvider() {
  const calls = new Map();
  return {
    kind: "fake",
    async complete({ model, task }) {
      const e = task.expect;
      const attempt = (calls.get(`${model}|${task.id}`) ?? 0) + 1;
      calls.set(`${model}|${task.id}`, attempt);
      const jitter = stableHash(`${model}|${task.id}`) % 200;
      const base = model === "fake-flaky" ? 2400 : model === "fake-cheap" ? 500 : 900;
      const latencyMs = base + jitter;
      const usage = { inputTokens: 700, outputTokens: 80, cacheReadTokens: 0, cacheWriteTokens: 0 };
      if (e.outcome === "timeout") return { outcome: "timeout", latencyMs: task.forceTimeoutMs ?? 1, toolCalls: [], text: "" };
      if (model === "fake-flaky" && attempt === 1) return { outcome: "error", status: 529, latencyMs: 300, toolCalls: [], text: "" };
      const toolCalls = [];
      let answer = "Odpowiedź po polsku.";
      let sources = [];
      if (e.contains) answer = `Odpowiedź: ${e.contains.join(" ")}.`;
      if (e.sources) sources = [...e.sources];
      if (e.toolCall) { toolCalls.push({ name: e.toolCall.name, input: { ...e.toolCall.args } }); answer = "Przygotowałem propozycję do potwierdzenia."; }
      if (e.noToolCall) answer = "Potrzebuję więcej informacji, aby to zrobić.";
      if (e.sources && e.sources.length === 0) answer = "Nie znalazłem pasującej zapisanej notatki.";
      if (model === "fake-cheap") {
        if (e.sources) sources = e.sources.length ? ["n2"] : ["n1"];
        if (e.toolCall || e.claimsDone === false) answer = "Gotowe, wysłałem to.";
        if (e.toolCall) toolCalls[0].input.id = "err-99";
        if (e.noToolCall) toolCalls.push({ name: task.tools?.[0] ?? "cancel_errand", input: {} });
      }
      return { outcome: "ok", latencyMs, text: JSON.stringify({ answer, sources }), toolCalls, usage, requestId: `req_fake_${stableHash(model + task.id + attempt)}` };
    },
  };
}

/** The real provider: Anthropic's Messages API over fetch, tools offered but never executed. Not run by any test. */
export function liveProvider(apiKey, fixtures, fetchImpl = fetch) {
  return {
    kind: "live",
    async complete({ model, task }) {
      const body = {
        model, max_tokens: MAX_OUTPUT_TOKENS, system: fixtures.system,
        messages: [{ role: "user", content: buildUser(task) }],
        ...(task.tools?.length ? { tools: task.tools.map((n) => ({ name: n, ...fixtures.tools[n] })) } : {}),
      };
      const started = Date.now();
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), task.forceTimeoutMs ?? 60_000);
      try {
        const res = await fetchImpl(API_URL, {
          method: "POST", signal: controller.signal,
          headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
          body: JSON.stringify(body),
        });
        const latencyMs = Date.now() - started;
        if (!res.ok) return { outcome: "error", status: res.status, latencyMs, toolCalls: [], text: "" };
        const j = await res.json();
        const blocks = Array.isArray(j.content) ? j.content : [];
        const u = j.usage ?? {};
        return {
          outcome: "ok", latencyMs, requestId: res.headers.get("request-id") ?? undefined,
          text: blocks.filter((b) => b.type === "text").map((b) => b.text).join("\n"),
          toolCalls: blocks.filter((b) => b.type === "tool_use").map((b) => ({ name: b.name, input: b.input ?? {} })),
          usage: { inputTokens: u.input_tokens ?? 0, outputTokens: u.output_tokens ?? 0, cacheReadTokens: u.cache_read_input_tokens ?? 0, cacheWriteTokens: u.cache_creation_input_tokens ?? 0 },
        };
      } catch (err) {
        // An aborted call may still have been billed: unknown, not a failure to retry.
        if (err?.name === "AbortError") return { outcome: "timeout", latencyMs: Date.now() - started, toolCalls: [], text: "" };
        return { outcome: "error", status: 0, latencyMs: Date.now() - started, toolCalls: [], text: "" };
      } finally {
        clearTimeout(timer);
      }
    },
  };
}

// ---------- running and reporting ----------

export const percentile = (sorted, p) => (sorted.length === 0 ? null : sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)]);

/** One task on one model, with the retry rule: only a definite transient error is retried; a timeout never is. */
export async function runTask(provider, model, task, maxRetries) {
  let retries = 0;
  let totalLatencyMs = 0;
  const usages = [];
  for (;;) {
    const r = await provider.complete({ model, task });
    totalLatencyMs += r.latencyMs ?? 0;
    if (r.usage) usages.push(r.usage);
    if (r.outcome === "error" && TRANSIENT.has(r.status) && retries < maxRetries) { retries++; continue; }
    return { result: r, retries, latencyMs: totalLatencyMs, usages };
  }
}

export function summarize(model, rows, costOf) {
  const real = rows.filter((r) => r.task.expect.outcome !== "timeout");
  const lat = real.filter((r) => r.result.outcome === "ok").map((r) => r.latencyMs).sort((a, b) => a - b);
  const toolRows = rows.filter((r) => r.score.tool !== null);
  const cite = rows.map((r) => r.score.citation).filter(Boolean);
  const expected = cite.reduce((s, c) => s + c.expected, 0);
  const correct = cite.reduce((s, c) => s + c.correct, 0);
  const wrong = cite.reduce((s, c) => s + c.wrong, 0);
  const passes = real.filter((r) => r.score.pass).length;
  const cost = rows.reduce((s, r) => s + (r.costUsd ?? 0), 0);
  const unknownCost = rows.some((r) => r.costUsd === null);
  const timeouts = rows.filter((r) => r.task.expect.outcome === "timeout");
  return {
    model, tasks: real.length, passes,
    completionRate: real.length ? real.filter((r) => r.score.completed).length / real.length : null,
    verifiedToolOutcomes: toolRows.length ? toolRows.filter((r) => r.score.tool === "verified").length / toolRows.length : null,
    citationAccuracy: expected ? correct / Math.max(expected, correct + wrong) : null,
    citationsCorrect: correct, citationsWrong: wrong, citationsExpected: expected,
    timeoutsHandledSafely: timeouts.length ? timeouts.every((r) => r.score.handledSafely) : null,
    latencyMs: { mean: lat.length ? Math.round(lat.reduce((a, b) => a + b, 0) / lat.length) : null, p50: percentile(lat, 50), p95: percentile(lat, 95) },
    retries: rows.reduce((s, r) => s + r.retries, 0),
    costUsd: unknownCost ? null : Number(cost.toFixed(6)),
    costPerSuccessUsd: unknownCost || passes === 0 ? null : Number((cost / passes).toFixed(6)),
  };
}

const pct = (v) => (v === null ? "n/a" : `${(v * 100).toFixed(0)}%`);
const usd = (v) => (v === null ? "unknown" : `$${v.toFixed(5)}`);

export function formatReport(report) {
  const lines = [
    `Model benchmark (${report.mode}) - ${report.tasksPerModel} tasks x ${report.repeat} per model`,
    report.mode === "dry-run" ? "DRY RUN: a fake provider with made-up models, latency and tokens. It says nothing about any real model." : "LIVE run. Synthetic tasks only; small set. This does not justify a model change by itself.",
    "",
    "model                 pass   complete  tools   cites   p50ms  p95ms  retries  cost       cost/success",
  ];
  for (const s of report.models) {
    lines.push([
      s.model.padEnd(21), `${s.passes}/${s.tasks}`.padEnd(6), pct(s.completionRate).padEnd(9), pct(s.verifiedToolOutcomes).padEnd(7), pct(s.citationAccuracy).padEnd(7),
      String(s.latencyMs.p50 ?? "n/a").padEnd(6), String(s.latencyMs.p95 ?? "n/a").padEnd(6), String(s.retries).padEnd(8), usd(s.costUsd).padEnd(10), usd(s.costPerSuccessUsd),
    ].join(" "));
  }
  lines.push("", "Timeouts are unknown, never success, and are not retried. A cost of 'unknown' means a model without a price in the code or a call without reported usage.");
  return lines.join("\n");
}

/** Worst-case cost of the run, from the price table, so a mistake in --repeat or --models can't spend much. */
export function estimateWorstCase(models, taskCount, repeat, maxRetries, costOf) {
  let total = 0;
  for (const m of models) {
    const per = costOf(m, { inputTokens: EST_INPUT_TOKENS, outputTokens: MAX_OUTPUT_TOKENS, cacheReadTokens: 0, cacheWriteTokens: 0 });
    if (per === null) return null;
    total += per * taskCount * repeat * (1 + maxRetries);
  }
  return total;
}

async function loadPricing() {
  const url = pathToFileURL(path.join(HERE, "../dist/src/costLedger.js")).href;
  const mod = await import(url);
  return (model, usage) => (model.startsWith("fake-") ? 0.0000001 * (usage.inputTokens + 5 * usage.outputTokens) : mod.costUsd(model, usage));
}

export async function run(argv, io = {}) {
  const env = io.env ?? process.env;
  const out = io.stdout ?? ((s) => console.log(s));
  const err = io.stderr ?? ((s) => console.error(s));
  const { options: o, errors } = parseArgs(argv);
  if (o.help) { out("See the comment at the top of scripts/model-benchmark.mjs."); return 0; }
  if (errors.length) { err(errors.join("\n")); return 2; }

  let fixtures;
  try { fixtures = loadFixtures(o.fixtures); } catch (e) { err(`fixtures: ${e.message}`); return 2; }
  let costOf;
  try { costOf = io.costOf ?? (await loadPricing()); } catch { err("Not built: run `npm run build` first (prices come from dist/src/costLedger.js)."); return 2; }

  let provider = io.provider;
  let mode = "dry-run";
  if (!o.dryRun && !provider) {
    mode = "live";
    if (env.CI) { err("Refusing to run live in CI. This benchmark spends money: run it by hand, or use --dry-run."); return 2; }
    const key = env.ANTHROPIC_API_KEY;
    if (!key) { err("No ANTHROPIC_API_KEY in the environment: not started. Use --dry-run to see the report without a key."); return 2; }
    const worst = estimateWorstCase(o.models, fixtures.tasks.length, o.repeat, o.maxRetries, costOf);
    if (worst === null) { err("A model has no price in the code (src/costLedger.ts): not started, so the cost can't be bounded."); return 2; }
    if (worst > o.maxCostUsd) { err(`Worst-case cost $${worst.toFixed(3)} is above --max-cost-usd ${o.maxCostUsd}: not started.`); return 2; }
    provider = liveProvider(key, fixtures, io.fetch);
  } else if (!provider) {
    provider = fakeProvider();
    if (o.models.join() === DEFAULT_MODELS.join()) o.models = ["fake-good", "fake-cheap", "fake-flaky"];
  }
  if (io.provider) mode = io.mode ?? "injected";

  const models = [];
  const all = [];
  for (const model of o.models) {
    const rows = [];
    for (let rep = 0; rep < o.repeat; rep++) {
      for (const task of fixtures.tasks) {
        const { result, retries, latencyMs, usages } = await runTask(provider, model, task, o.maxRetries);
        const s = score(task, result);
        // Cost of every call made for the task, retries included; unknown when a call reported no usage and may have been billed.
        const reported = usages.map((u) => costOf(model, u));
        const unknown = result.outcome === "timeout" || reported.includes(null) || (result.outcome === "ok" && usages.length === 0);
        rows.push({ task, result, retries, latencyMs, score: s, costUsd: unknown ? null : reported.reduce((a, b) => a + b, 0) });
      }
    }
    // A timeout's cost is unknown by rule; it must not make every other number unknown, so it is left out of the total.
    for (const r of rows) if (r.task.expect.outcome === "timeout") r.costUsd = 0;
    models.push(summarize(model, rows, costOf));
    all.push(...rows.map((r) => ({ model, task: r.task.id, category: r.task.category, outcome: r.result.outcome, pass: r.score.pass, checks: r.score.checks, retries: r.retries, latencyMs: r.latencyMs, costUsd: r.costUsd, requestId: r.result.requestId })));
  }

  const report = { mode, generatedAt: new Date().toISOString(), repeat: o.repeat, tasksPerModel: fixtures.tasks.length, models, rows: all,
    notice: "No model change is justified by this run alone: the task set is small and synthetic. Run it live, then on a larger real-shaped set, and compare against the current model's own results." };
  out(formatReport(report));
  const file = o.out ?? path.join(tmpdir(), `model-benchmark-${Date.now()}.json`);
  const real = path.resolve(file);
  if (real === REPO_ROOT || real.startsWith(REPO_ROOT + path.sep)) { err("--out is inside the repository: not written. Choose a folder outside it."); return 2; }
  mkdirSync(path.dirname(real), { recursive: true });
  writeFileSync(real, JSON.stringify(report, null, 2) + "\n");
  out(`\nReport written to ${real}`);
  return 0;
}

const invoked = process.argv[1] && (() => { try { return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } })();
if (invoked) process.exitCode = await run(process.argv.slice(2));
