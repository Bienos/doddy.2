// One Studio job from plan to checked files (ADR-584, STUDIO.md "The pipeline"). Never throws for
// model, network or file problems: each ends as a failure code. Files made at Anthropic are always
// deleted there before this returns; any delete not read back as gone is returned as `pending`.
import Anthropic from "@anthropic-ai/sdk";
import { collectSources, countToolUses, echoable, languageName, SeenSources, type ResearchTurn } from "../errands/researcher.js";
import { checkFiles, failed, isKeptFile, type MadeFile } from "./checks.js";
import { fileIdsOf, type MakeTurn, type StudioModelApi, type Structured, type UsageLike } from "./model.js";
import {
  contentProblems, LIMITS, type Check, type ContentOutput, type FailureCode, type PackSource, type PlanOutput,
  type RenderContent, type ResearchPack, type Stage, type StudioJob, type StudioResult,
} from "./schema.js";

export const MAX_PAUSE_TURNS = 12;
export const MAX_NOTES_CHARS = 200_000;

/** Opus 5.5 list prices (USD per million tokens) and web search ($10 per 1,000). Container time inside the free hours counts $0. */
export const PRICES = { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5, perSearch: 0.01 } as const;

export interface Usage { inputTokens: number; cacheWriteTokens: number; cacheReadTokens: number; outputTokens: number }
export interface RunStats { usage: Usage; searches: number; fetches: number; containerSeconds: number; costUsd: number; model: string }

export type StudioOutcome =
  | ({ kind: "made"; state: "ready" | "needs_look"; result: StudioResult; files: MadeFile[]; pending: string[] } & RunStats)
  | ({ kind: "failed"; code: FailureCode; pending: string[] } & RunStats)
  | ({ kind: "cancelled"; pending: string[] } & RunStats);

export interface StudioControl {
  /** No model request runs past it. */
  deadline: Date;
  /** True once the user cancelled or deleted the item. Checked between requests and polled during one. */
  isCancelled(): Promise<boolean>;
  /** Records where the job is, for the app. */
  setStage(stage: Stage): Promise<void>;
  /** Aborted when the worker shuts down: the job ends as `interrupted`. */
  signal?: AbortSignal;
  jobLimitUsd: number;
  now?: () => Date;
  cancelPollMs?: number;
  log?: (msg: string, extra?: object) => void;
}

export function costOf(usage: Usage, searches: number): number {
  const usd = (usage.inputTokens * PRICES.input + usage.outputTokens * PRICES.output
    + usage.cacheReadTokens * PRICES.cacheRead + usage.cacheWriteTokens * PRICES.cacheWrite) / 1_000_000
    + searches * PRICES.perSearch;
  return Math.round(usd * 10_000) / 10_000;
}

type StopReason = "time_limit" | "cancelled" | "interrupted";
class Stop extends Error {
  constructor(readonly outcome: { kind: "cancelled" } | { kind: "failed"; code: FailureCode }) { super("stop"); }
}
const stopFor = (why: StopReason) => new Stop(why === "cancelled" ? { kind: "cancelled" } : { kind: "failed", code: why });
const fail = (code: FailureCode) => new Stop({ kind: "failed", code });

const clip = (s: string, max: number) => (s.length <= max ? s : s.slice(0, max).trimEnd());

export async function runStudio(api: StudioModelApi, job: StudioJob, control: StudioControl): Promise<StudioOutcome> {
  const now = control.now ?? (() => new Date());
  const log = control.log ?? (() => {});
  const usage: Usage = { inputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0, outputTokens: 0 };
  let searches = 0, fetches = 0, reportedSearches = 0, reportedFetches = 0, containerMs = 0;
  /** Files made at Anthropic in this job, until each delete is read back. */
  const atAnthropic = new Set<string>();

  const stats = (): RunStats => {
    const s = Math.max(searches, reportedSearches);
    return {
      usage: { ...usage }, searches: s, fetches: Math.max(fetches, reportedFetches),
      containerSeconds: Math.round(containerMs / 1000), costUsd: costOf(usage, s), model: api.model,
    };
  };
  const add = (u: UsageLike | undefined) => {
    if (!u) return;
    usage.inputTokens += u.input_tokens ?? 0;
    usage.cacheWriteTokens += u.cache_creation_input_tokens ?? 0;
    usage.cacheReadTokens += u.cache_read_input_tokens ?? 0;
    usage.outputTokens += u.output_tokens ?? 0;
    reportedSearches += u.server_tool_use?.web_search_requests ?? 0;
    reportedFetches += u.server_tool_use?.web_fetch_requests ?? 0;
  };
  const withinLimit = () => {
    if (stats().costUsd > control.jobLimitUsd) throw fail("cost_limit");
  };

  /** One model call with the time limit, Cancel and shutdown wired to an abort. */
  async function guarded<T>(call: (signal: AbortSignal) => Promise<T>): Promise<T> {
    if (control.signal?.aborted) throw stopFor("interrupted");
    if (now() >= control.deadline) throw stopFor("time_limit");
    if (await control.isCancelled()) throw stopFor("cancelled");
    const controller = new AbortController();
    const abort = (why: StopReason) => { if (!controller.signal.aborted) controller.abort(why); };
    const timer = setTimeout(() => abort("time_limit"), Math.max(0, control.deadline.getTime() - now().getTime()));
    const poll = setInterval(() => { control.isCancelled().then((c) => { if (c) abort("cancelled"); }, () => {}); }, control.cancelPollMs ?? 15_000);
    const onShutdown = () => abort("interrupted");
    control.signal?.addEventListener("abort", onShutdown);
    try {
      return await call(controller.signal);
    } catch (err) {
      if (controller.signal.aborted) throw stopFor(controller.signal.reason as StopReason);
      log("studio request failed", { error: err instanceof Anthropic.APIError ? `api_${err.status ?? "connection"}` : (err as Error)?.name });
      throw fail("provider_error");
    } finally {
      clearTimeout(timer);
      clearInterval(poll);
      control.signal?.removeEventListener("abort", onShutdown);
    }
  }

  const structured = async <T>(call: (signal: AbortSignal) => Promise<Structured<T>>): Promise<Structured<T>> => {
    const r = await guarded(call);
    add(r.usage);
    if (r.kind === "refused") throw fail("refused");
    return r;
  };

  /** Deletes every file this job left at Anthropic and reads each delete back. Returns the ones not confirmed. */
  const tidyAnthropic = async (): Promise<string[]> => {
    const pending: string[] = [];
    for (const id of atAnthropic) {
      try {
        const signal = AbortSignal.timeout(20_000);
        await api.deleteFile(id, signal).catch(() => {});
        if (await api.fileGone(id, AbortSignal.timeout(20_000))) atAnthropic.delete(id);
        else pending.push(id);
      } catch {
        pending.push(id);
      }
    }
    return pending;
  };

  try {
    const today = now().toISOString().slice(0, 10);
    const language = languageName(job.language);

    // ---------- 1. plan ----------
    await control.setStage("plan");
    const planned = await structured((s) => api.plan(JSON.stringify({ today, language, job }), s));
    if (planned.kind !== "ok") throw fail("unreadable_result");
    const plan: PlanOutput = {
      title: clip(planned.value.title.trim(), LIMITS.title),
      subQuestions: planned.value.subQuestions.map((q) => q.trim()).filter(Boolean).slice(0, LIMITS.subQuestionsMax),
      outline: planned.value.outline.map((o) => o.trim()).filter(Boolean).slice(0, 12),
      audience: clip(planned.value.audience.trim(), LIMITS.audience),
    };
    if (!plan.title || plan.subQuestions.length === 0) throw fail("unreadable_result");
    withinLimit();

    // ---------- 2. research, then the pack ----------
    await control.setStage("research");
    const seen = new SeenSources();
    const seenAt = new Map<string, string>();
    const messages: ResearchTurn[] = [{ role: "user", content: JSON.stringify({ today, language, job, subQuestions: plan.subQuestions }) }];
    const notes: string[] = [];
    for (let turn = 0; ; turn++) {
      const m = await guarded((s) => api.research(messages, s));
      add(m.usage);
      const counted = countToolUses(m.content);
      searches += counted.searches;
      fetches += counted.fetches;
      collectSources(m.content, seen);
      for (const url of seen.urls) if (!seenAt.has(url)) seenAt.set(url, now().toISOString());
      for (const b of m.content) if (b.type === "text" && typeof b.text === "string" && b.text.trim()) notes.push(b.text.trim());
      withinLimit();
      if (m.stop_reason === "pause_turn" && turn < MAX_PAUSE_TURNS) {
        messages.push({ role: "assistant", content: echoable(m.content) });
        continue;
      }
      if (m.stop_reason === "refusal") throw fail("refused");
      break;
    }
    const allNotes = notes.join("\n\n").slice(0, MAX_NOTES_CHARS);
    if (!allNotes) throw fail("unreadable_result");

    const packed = await structured((s) => api.pack(JSON.stringify({ today, language, job, notes: allNotes, sources: seen.list(200) }), s));
    if (packed.kind !== "ok") throw fail("unreadable_result");
    const pack = buildPack(packed.value.claims, seen, seenAt);
    log("studio pack", { claims: pack.claims.length, sources: pack.sources.length, seen: seen.size, offered: packed.value.claims.length });
    if (pack.claims.length < LIMITS.claimsMin) throw fail("too_little_found");
    withinLimit();

    // ---------- 3. write, checked by code (one retry with the problems listed) ----------
    await control.setStage("write");
    const writeInput = { today, language, job, plan, pack };
    let content: ContentOutput | undefined;
    let problems: string[] = [];
    for (let attempt = 0; attempt < 2 && !content; attempt++) {
      const input = attempt === 0 ? writeInput : { ...writeInput, fixThese: problems };
      const written = await structured((s) => api.write(JSON.stringify(input), s));
      withinLimit();
      if (written.kind !== "ok") { problems = ["the reply didn't match the schema"]; continue; }
      problems = contentProblems(written.value, pack);
      if (problems.length === 0) content = written.value;
    }
    if (!content) {
      log("studio content failed its rules", { problems: problems.length });
      throw fail("unreadable_result");
    }
    const render: RenderContent = { ...content, language: job.language, sources: pack.sources, claims: pack.claims };

    // ---------- 4 and 5. make, check in code (one retry with the failed checks listed) ----------
    await control.setStage("make");
    const makeTurns: MakeTurn[] = [{ role: "user", content: `content.json:\n${JSON.stringify(render, null, 2)}` }];
    let containerId: string | undefined;
    let files: MadeFile[] = [];
    let checks: Check[] = [];
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await control.setStage("make");
        makeTurns.push({ role: "user", content: `These checks failed. Render again with the same content.json and fix only the rendering:\n${failed(checks).map((c) => `- ${c.name}: ${c.detail}`).join("\n")}` });
      }
      const made = await makeOnce(makeTurns, containerId);
      containerId = made.containerId;
      files = mergeFiles(files, made.files);
      await control.setStage("check");
      checks = checkFiles(files, render);
      if (failed(checks).length === 0) break;
      log("studio checks failed", { attempt, failed: failed(checks).map((c) => c.name) });
    }

    const result: StudioResult = {
      title: content.title.trim() || plan.title,
      summary: { answer: content.answer, confidence: content.confidence, altText: content.infographic.altText },
      sources: pack.sources,
      checks,
      skills: api.skills.map((s) => ({ id: s.id, version: s.version })),
    };
    const pending = await tidyAnthropic();
    return {
      kind: "made", state: failed(checks).length === 0 ? "ready" : "needs_look", result,
      files: files.filter((f) => isKeptFile(f.name)), pending, ...stats(),
    };
  } catch (err) {
    const pending = await tidyAnthropic();
    if (err instanceof Stop) {
      return err.outcome.kind === "cancelled" ? { kind: "cancelled", pending, ...stats() } : { kind: "failed", code: err.outcome.code, pending, ...stats() };
    }
    log("studio job threw", { error: (err as Error)?.name });
    return { kind: "failed", code: "interrupted", pending, ...stats() };
  }

  /** One make request and its pause_turn resumes, then the kept files downloaded. */
  async function makeOnce(turns: MakeTurn[], container: string | undefined): Promise<{ containerId?: string; files: MadeFile[] }> {
    const ids: string[] = [];
    let containerId = container;
    for (let turn = 0; ; turn++) {
      const started = Date.now();
      const m = await guarded((s) => api.make(turns, containerId, s));
      containerMs += Date.now() - started;
      add(m.usage);
      containerId = m.containerId ?? containerId;
      for (const id of fileIdsOf(m.content)) { ids.push(id); atAnthropic.add(id); }
      turns.push({ role: "assistant", content: m.content });
      withinLimit();
      if (m.stop_reason === "pause_turn" && turn < MAX_PAUSE_TURNS) continue;
      if (m.stop_reason === "refusal") throw fail("refused");
      break;
    }
    const files: MadeFile[] = [];
    for (const id of ids) {
      const name = await guarded((s) => api.fileName(id, s));
      if (!isKeptFile(name)) continue;
      const bytes = await guarded((s) => api.download(id, s));
      files.push({ name, bytes });
    }
    return { containerId, files };
  }
}

/** The later copy of a file wins (a second make attempt replaces the first's). */
function mergeFiles(before: MadeFile[], after: MadeFile[]): MadeFile[] {
  const by = new Map(before.map((f) => [f.name, f]));
  for (const f of after) by.set(f.name, f);
  return [...by.values()];
}

/**
 * Claims whose page this run actually saw, each tied to a numbered source with the time the run
 * first saw it. A claim with a URL the run never saw is dropped (DOD-02), as Errands drops links.
 */
export function buildPack(
  offered: { text: string; quote: string; url: string; sourceTitle: string }[], seen: SeenSources, seenAt: Map<string, string>,
): ResearchPack {
  const sources: PackSource[] = [];
  const sourceFor = new Map<string, string>();
  const titles = new Map(seen.list(Number.MAX_SAFE_INTEGER).map((s) => [s.url, s.title]));
  const claims: ResearchPack["claims"] = [];
  for (const c of offered) {
    const url = c.url.trim();
    const text = clip(c.text.trim(), LIMITS.claimText);
    const quote = clip(c.quote.trim(), LIMITS.quote);
    if (!seen.urls.has(url) || !text || !quote || claims.length >= LIMITS.claimsMax) continue;
    let sid = sourceFor.get(url);
    if (!sid) {
      sid = `s${sources.length + 1}`;
      sourceFor.set(url, sid);
      sources.push({ id: sid, url, title: clip(titles.get(url) || c.sourceTitle.trim() || url, LIMITS.sourceTitle), fetchedAt: seenAt.get(url) ?? new Date().toISOString() });
    }
    claims.push({ id: `c${claims.length + 1}`, text, quote, source: sid });
  }
  return { sources, claims };
}
