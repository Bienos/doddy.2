// First real run of Doddy Studio S0 against the live Anthropic API (STUDIO.md "First real run").
//   ANTHROPIC_API_KEY=… STUDIO_SKILLS=skill_…@skver_…,… node scripts/studio-live-run.mjs <pl|en|short> [outDir]
// Reads the key only from the environment and never prints or writes it. Needs the compiled server
// (npm run build). No database. Records every model call (step, usage, stop reason, error text),
// writes the made files, the plan/pack/content and a summary.json into outDir, and prints a summary.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AnthropicStudioApi, parseSkills } from "../dist/src/studio/model.js";
import { runStudio, costOf } from "../dist/src/studio/pipeline.js";

const TOPICS = {
  pl: { kind: "brief", topic: "Pompy ciepła w Polsce: ile kosztują i czy się opłacają?", length: "short", style: "plain", language: "pl" },
  en: { kind: "brief", topic: "How do heat pumps compare with gas boilers in cold climates?", length: "standard", style: "plain", language: "en" },
  short: { kind: "brief", topic: "Is intermittent fasting better than normal dieting for weight loss?", length: "short", style: "plain", language: "en" },
};

const name = process.argv[2];
const job = TOPICS[name];
const key = process.env.ANTHROPIC_API_KEY;
if (!job) { console.error("usage: studio-live-run.mjs <pl|en|short> [outDir]"); process.exit(64); }
if (!key) { console.error("ANTHROPIC_API_KEY is not set"); process.exit(2); }
const skills = parseSkills(process.env.STUDIO_SKILLS);
if (skills.length === 0) { console.error("STUDIO_SKILLS is not set"); process.exit(2); }
const outDir = process.argv[3] ?? join(process.env.TMPDIR ?? "/tmp", `studio-live-${name}-${Date.now()}`);
mkdirSync(outDir, { recursive: true });

const api = new AnthropicStudioApi(key, {
  skills, maxSearches: 8, maxFetches: 8, blockedDomains: [], taskBudgetTokens: 150000, baseURL: "https://api.anthropic.com",
});

const calls = [];
const fileIds = [];
const saved = {};
const errText = (e) => `${e?.name ?? "Error"} ${e?.status ?? ""} ${e?.error?.error?.message ?? e?.message ?? ""}`.replace(/sk-ant-[A-Za-z0-9_-]+/g, "[redacted]").slice(0, 1500);
const usageOf = (u) => u && ({ in: u.input_tokens ?? 0, out: u.output_tokens ?? 0, cacheRead: u.cache_read_input_tokens ?? 0, cacheWrite: u.cache_creation_input_tokens ?? 0, search: u.server_tool_use?.web_search_requests ?? 0, fetch: u.server_tool_use?.web_fetch_requests ?? 0 });
async function rec(step, fn, summarise) {
  const t0 = Date.now();
  try {
    const r = await fn();
    calls.push({ step, ms: Date.now() - t0, ...summarise(r) });
    return r;
  } catch (e) {
    calls.push({ step, ms: Date.now() - t0, error: errText(e) });
    throw e;
  }
}
const structuredSummary = (r) => ({ kind: r.kind, usage: usageOf(r.usage) });
const wrapped = {
  model: api.model, skills: api.skills,
  plan: async (i, s) => { const r = await rec("plan", () => api.plan(i, s), structuredSummary); saved.plan = r.value; return r; },
  pack: async (i, s) => { const r = await rec("pack", () => api.pack(i, s), structuredSummary); saved.pack = r.value; return r; },
  write: async (i, s) => { const r = await rec(`write${saved.writes ? "-retry" : ""}`, () => api.write(i, s), structuredSummary); (saved.writes ??= []).push(r.value ?? null); return r; },
  research: async (m, s) => rec("research", () => api.research(m, s), (r) => {
    (saved.research ??= []).push(r.content.filter((b) => b.type === "text").map((b) => b.text));
    return { stop: r.stop_reason, usage: usageOf(r.usage), blocks: r.content.map((b) => b.type).join(",") };
  }),
  make: async (m, c, s) => rec("make", () => api.make(m, c, s), (r) => {
    const results = r.content.filter((b) => b.type.endsWith("tool_result")).map((b) => JSON.stringify(b.content).slice(0, 600));
    return { stop: r.stop_reason, usage: usageOf(r.usage), container: r.containerId, blocks: r.content.map((b) => b.type).join(","), results };
  }),
  fileName: (id, s) => rec("file.metadata", () => api.fileName(id, s), (n) => { fileIds.push(id); return { id, name: n }; }),
  download: (id, s) => rec("file.download", () => api.download(id, s), (b) => ({ id, bytes: b.length })),
  deleteFile: (id, s) => rec("file.delete", () => api.deleteFile(id, s), () => ({ id })),
  fileGone: (id, s) => rec("file.gone?", () => api.fileGone(id, s), (g) => ({ id, gone: g })),
};

const started = Date.now();
const outcome = await runStudio(wrapped, job, {
  deadline: new Date(Date.now() + 20 * 60_000),
  isCancelled: async () => false,
  setStage: async (stage) => { console.log(`[${((Date.now() - started) / 1000).toFixed(0)}s] stage ${stage}`); },
  jobLimitUsd: 2,
  log: (msg, extra) => console.log("log:", msg, JSON.stringify(extra ?? {})),
});
const wallSeconds = Math.round((Date.now() - started) / 1000);

const written = [];
if (outcome.kind === "made") {
  for (const f of outcome.files) { writeFileSync(join(outDir, f.name), f.bytes); written.push(`${f.name} (${f.bytes.length} bytes)`); }
}
for (const [k, v] of Object.entries(saved)) writeFileSync(join(outDir, `${k}.json`), JSON.stringify(v, null, 2));
// Cost implied by the recorded per-call usage (independent of the pipeline's own sums).
const sum = { in: 0, out: 0, cacheRead: 0, cacheWrite: 0, search: 0, fetch: 0 };
for (const c of calls) if (c.usage) for (const k of Object.keys(sum)) sum[k] += c.usage[k];
const impliedUsd = costOf({ inputTokens: sum.in, outputTokens: sum.out, cacheReadTokens: sum.cacheRead, cacheWriteTokens: sum.cacheWrite }, sum.search);
const summary = {
  name, job, wallSeconds, outcome: outcome.kind, state: outcome.state, failure: outcome.code,
  checks: outcome.result?.checks, pipelineCostUsd: outcome.costUsd, impliedCostFromCallsUsd: impliedUsd,
  usage: outcome.usage, searches: outcome.searches, fetches: outcome.fetches, containerSeconds: outcome.containerSeconds,
  pendingAtAnthropic: outcome.pending, madeFileIds: fileIds, written, calls,
};
writeFileSync(join(outDir, "summary.json"), JSON.stringify(summary, null, 2));
console.log(JSON.stringify({ ...summary, calls: undefined }, null, 2));
console.log("calls:");
for (const c of calls) console.log(" ", JSON.stringify(c).slice(0, 700));
console.log("outDir:", outDir);
