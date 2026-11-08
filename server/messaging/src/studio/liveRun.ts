// The first real runs of Studio S0 against the live API (STUDIO.md "First real run"), as a function so
// the recording, cost and file-writing code is tested against a fake Claude before any paid call.
// `scripts/studio-live-run.mjs` builds the real client from the environment and calls this. Nothing
// here reads or writes the API key; errors are redacted of anything key-shaped before they are kept.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type StudioModelApi, type UsageLike } from "./model.js";
import { PER_SEARCH_USD, tokenCostUsd, type StudioStep } from "./models.js";
import { runStudio, type StudioOutcome } from "./pipeline.js";
import type { StudioJob } from "./schema.js";

export interface LiveCall {
  step: string; model?: string; ms: number; kind?: string; stop?: string | null; error?: string;
  usage?: { in: number; out: number; cacheRead: number; cacheWrite: number; search: number; fetch: number };
  [extra: string]: unknown;
}

export interface LiveRunOptions {
  name: string; mix: string; outDir: string; jobLimitUsd: number; timeLimitMinutes?: number;
  print?: (line: string) => void;
}

const redact = (s: string) => s.replace(/sk-ant-[A-Za-z0-9_-]+/g, "[redacted]");
const errText = (e: unknown) => {
  const x = e as { name?: string; status?: number; error?: { error?: { message?: string } }; message?: string };
  return redact(`${x?.name ?? "Error"} ${x?.status ?? ""} ${x?.error?.error?.message ?? x?.message ?? ""}`).slice(0, 1500);
};
const usageOf = (u: UsageLike | undefined) => u && ({
  in: u.input_tokens ?? 0, out: u.output_tokens ?? 0, cacheRead: u.cache_read_input_tokens ?? 0, cacheWrite: u.cache_creation_input_tokens ?? 0,
  search: u.server_tool_use?.web_search_requests ?? 0, fetch: u.server_tool_use?.web_fetch_requests ?? 0,
});
const round4 = (n: number) => Math.round(n * 1e4) / 1e4;

export async function liveRun(api: StudioModelApi, job: StudioJob, o: LiveRunOptions) {
  const print = o.print ?? (() => {});
  mkdirSync(o.outDir, { recursive: true });
  const calls: LiveCall[] = [];
  const fileIds: string[] = [];
  const saved: Record<string, unknown> = {};
  const stepOf = (step: string): StudioStep => (step.startsWith("file.") ? "make" : (step.replace(/-retry$/, "") as StudioStep));

  async function rec<T>(step: string, fn: () => Promise<T>, summarise: (r: T) => Record<string, unknown>): Promise<T> {
    const t0 = Date.now();
    try {
      const r = await fn();
      calls.push({ step, model: api.models[stepOf(step)], ms: Date.now() - t0, ...summarise(r) });
      return r;
    } catch (e) {
      calls.push({ step, model: api.models[stepOf(step)], ms: Date.now() - t0, error: errText(e) });
      throw e;
    }
  }
  const structuredSummary = (r: { kind: string; usage?: UsageLike }) => ({ kind: r.kind, usage: usageOf(r.usage) });
  let writes = 0;
  const wrapped: StudioModelApi = {
    model: api.model, models: api.models, skills: api.skills,
    plan: async (i, s) => { const r = await rec("plan", () => api.plan(i, s), structuredSummary); if (r.kind === "ok") saved.plan = r.value; return r; },
    pack: async (i, s) => { const r = await rec("pack", () => api.pack(i, s), structuredSummary); if (r.kind === "ok") saved.pack = r.value; return r; },
    write: async (i, s) => {
      const r = await rec(writes++ ? "write-retry" : "write", () => api.write(i, s), structuredSummary);
      ((saved.writes ??= []) as unknown[]).push(r.kind === "ok" ? r.value : null);
      return r;
    },
    research: async (m, s) => rec("research", () => api.research(m, s), (r) => {
      ((saved.research ??= []) as unknown[]).push(r.content.filter((b) => b.type === "text").map((b) => b.text));
      return { stop: r.stop_reason, usage: usageOf(r.usage), blocks: r.content.map((b) => b.type).join(",") };
    }),
    make: async (m, c, s) => rec("make", () => api.make(m, c, s), (r) => ({
      stop: r.stop_reason, usage: usageOf(r.usage), container: r.containerId, blocks: r.content.map((b) => b.type).join(","),
      results: r.content.filter((b) => b.type.endsWith("tool_result")).map((b) => JSON.stringify(b.content).slice(0, 600)),
    })),
    fileName: (id, s) => rec("file.metadata", () => api.fileName(id, s), (n) => { fileIds.push(id); return { id, name: n }; }),
    download: (id, s) => rec("file.download", () => api.download(id, s), (b) => ({ id, bytes: b.length })),
    deleteFile: (id, s) => rec("file.delete", () => api.deleteFile(id, s), () => ({ id })),
    fileGone: (id, s) => rec("file.gone?", () => api.fileGone(id, s), (g) => ({ id, gone: g })),
  };

  const started = Date.now();
  const outcome: StudioOutcome = await runStudio(wrapped, job, {
    deadline: new Date(Date.now() + (o.timeLimitMinutes ?? 20) * 60_000),
    isCancelled: async () => false,
    setStage: async (stage) => { print(`[${((Date.now() - started) / 1000).toFixed(0)}s] stage ${stage}`); },
    jobLimitUsd: o.jobLimitUsd,
    log: (msg, extra) => print(`log: ${msg} ${JSON.stringify(extra ?? {})}`),
  });
  const wallSeconds = Math.round((Date.now() - started) / 1000);

  const written: string[] = [];
  if (outcome.kind === "made") {
    for (const f of outcome.files) { writeFileSync(join(o.outDir, f.name), f.bytes); written.push(`${f.name} (${f.bytes.length} bytes)`); }
  }
  for (const [k, v] of Object.entries(saved)) writeFileSync(join(o.outDir, `${k}.json`), JSON.stringify(v, null, 2));

  // The cost the recorded per-call usage implies, each call at its own model's prices: independent of the pipeline's own sums.
  let tokenUsd = 0, searchesSeen = 0;
  const byStep: Record<string, { model: string; usd: number; calls: number }> = {};
  for (const c of calls) {
    if (!c.usage || !c.model) continue;
    const usd = tokenCostUsd(c.model, { inputTokens: c.usage.in, outputTokens: c.usage.out, cacheReadTokens: c.usage.cacheRead, cacheWriteTokens: c.usage.cacheWrite });
    tokenUsd += usd;
    searchesSeen += c.usage.search;
    const k = c.step.replace(/-retry$/, "");
    byStep[k] = { model: c.model, usd: round4((byStep[k]?.usd ?? 0) + usd), calls: (byStep[k]?.calls ?? 0) + 1 };
  }
  const summary = {
    name: o.name, mix: o.mix, models: api.models, job, wallSeconds, outcome: outcome.kind,
    state: outcome.kind === "made" ? outcome.state : undefined, failure: outcome.kind === "failed" ? outcome.code : undefined,
    checks: outcome.kind === "made" ? outcome.result.checks : undefined,
    pipelineCostUsd: outcome.costUsd, impliedCostFromCallsUsd: round4(tokenUsd + searchesSeen * PER_SEARCH_USD),
    tokenUsdByStep: byStep, searchUsd: round4(searchesSeen * PER_SEARCH_USD),
    usage: outcome.usage, searches: outcome.searches, fetches: outcome.fetches, containerSeconds: outcome.containerSeconds,
    pendingAtAnthropic: outcome.pending, madeFileIds: fileIds, written, calls,
  };
  writeFileSync(join(o.outDir, "summary.json"), JSON.stringify(summary, null, 2));
  return { summary, outcome };
}
