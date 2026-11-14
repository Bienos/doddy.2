// One Studio job from plan to checked files (ADR-740, STUDIO.md "The pipeline"). Never throws for
// model, network or file problems: each ends as a failure code. Files made at Anthropic are written
// down (`noteFiles`) the moment their ids come back and always deleted there before this returns; any
// delete not read back as gone is returned as `pending`.
import Anthropic from "@anthropic-ai/sdk";
import { collectSources, countToolUses, echoable, languageName, SeenSources, type ResearchTurn } from "../errands/researcher.js";
import { checkFiles, failed, isKeptFile, type MadeFile } from "./checks.js";
import { JobReservations, planCall, TOOL_INPUT_FACTOR } from "./budget.js";
import { fileIdsOf, MAKE_SYSTEM, PACK_SYSTEM, PLAN_SYSTEM, RESEARCH_SYSTEM, WRITE_SYSTEM, type MakeTurn, type StudioModelApi, type Structured, type UsageLike } from "./model.js";
import { PER_SEARCH_USD, tokenCostUsd, type StudioStep } from "./models.js";
import {
  contentProblems, LIMITS, type Check, type ContentOutput, type FailureCode, type PackSource, type PlanOutput,
  type RenderContent, type ResearchPack, type Stage, type StudioJob, type StudioResult,
} from "./schema.js";

export const MAX_PAUSE_TURNS = 12;
export const MAX_NOTES_CHARS = 200_000;
/** The first real run (22 Oct 2026) went over a length limit in each of two attempts, a different one each time. */
export const MAX_WRITE_ATTEMPTS = 3;

export interface Usage { inputTokens: number; cacheWriteTokens: number; cacheReadTokens: number; outputTokens: number }
export interface RunStats {
  usage: Usage; searches: number; fetches: number; containerSeconds: number; costUsd: number; model: string;
  /**
   * True when a model request may have spent more than `costUsd` counts: one was cut off once it had started (Cancel,
   * the time limit, shutdown, a failure at the provider) or came back without its usage. The worker then keeps the
   * job's whole reservation on the server's day and month (ADR-742).
   */
  costUnknown: boolean;
}

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
  /**
   * Called with the ids of files made at Anthropic as soon as a make request returns them, before anything is
   * downloaded, so a delete, a reap or a crash before the end still finds them. A failure here is logged; the
   * job's own clean-up still deletes them.
   */
  noteFiles?: (ids: string[]) => Promise<void>;
}

/** USD with four decimals. Tokens are priced per call with that step's model (models.ts); web search at $10 per 1,000; container time inside the free hours counts $0. */
export const roundUsd = (usd: number) => Math.round(usd * 10_000) / 10_000;

/** Cost of one step's tokens and the web searches it made. */
export function stepCostUsd(model: string, usage: Usage, searches = 0): number {
  return roundUsd(tokenCostUsd(model, usage) + searches * PER_SEARCH_USD);
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
  /** Token cost so far, each call priced with its own step's model. */
  let tokenUsd = 0;
  let searches = 0, fetches = 0, reportedSearches = 0, reportedFetches = 0, containerMs = 0;
  /** A request may have spent more than was counted (see RunStats.costUnknown). */
  let costUnknown = false;
  /** Calls in flight and the allowance kept for calls whose outcome is unknown (budget.ts). */
  const reservations = new JobReservations();
  let callSeq = 0;
  const caps = api.caps ?? { maxSearches: 15, maxFetches: 15, taskBudgetTokens: 150_000 };
  /** Files made at Anthropic in this job, until each delete is read back. */
  const atAnthropic = new Set<string>();

  const stats = (): RunStats => {
    const s = Math.max(searches, reportedSearches);
    return {
      usage: { ...usage }, searches: s, fetches: Math.max(fetches, reportedFetches),
      // `unknownUsd` is an allowance for calls that were sent and never came back with their usage, so they aren't counted as free;
      // `costUnknown` tells the worker to keep the job's whole reservation on the server's day and month as well (ADR-742).
      containerSeconds: Math.round(containerMs / 1000), costUsd: roundUsd(tokenUsd + s * PER_SEARCH_USD + reservations.unknownUsd), model: api.model, costUnknown,
    };
  };
  const add = (step: StudioStep, u: UsageLike | undefined) => {
    if (!u) return;
    const call: Usage = {
      inputTokens: u.input_tokens ?? 0, cacheWriteTokens: u.cache_creation_input_tokens ?? 0,
      cacheReadTokens: u.cache_read_input_tokens ?? 0, outputTokens: u.output_tokens ?? 0,
    };
    usage.inputTokens += call.inputTokens;
    usage.cacheWriteTokens += call.cacheWriteTokens;
    usage.cacheReadTokens += call.cacheReadTokens;
    usage.outputTokens += call.outputTokens;
    tokenUsd += tokenCostUsd(api.models[step], call);
    reportedSearches += u.server_tool_use?.web_search_requests ?? 0;
    reportedFetches += u.server_tool_use?.web_fetch_requests ?? 0;
  };
  const withinLimit = () => {
    if (stats().costUsd > control.jobLimitUsd) throw fail("cost_limit");
  };

  /**
   * One call with the time limit, Cancel and shutdown wired to an abort. `billed`: a model request, whose cost is
   * unknown when it ends without its answer (Files API calls are free). `prepare` runs after the stop checks and
   * before anything is sent (the pre-call budget check and reservation).
   */
  async function guarded<T>(call: (signal: AbortSignal) => Promise<T>, billed = true, prepare?: () => void): Promise<T> {
    if (control.signal?.aborted) throw stopFor("interrupted");
    if (now() >= control.deadline) throw stopFor("time_limit");
    if (await control.isCancelled()) throw stopFor("cancelled");
    prepare?.(); // the pre-call budget check and reservation: throws cost_limit before anything is sent
    const controller = new AbortController();
    const abort = (why: StopReason) => { if (!controller.signal.aborted) controller.abort(why); };
    const timer = setTimeout(() => abort("time_limit"), Math.max(0, control.deadline.getTime() - now().getTime()));
    const poll = setInterval(() => { control.isCancelled().then((c) => { if (c) abort("cancelled"); }, () => {}); }, control.cancelPollMs ?? 15_000);
    const onShutdown = () => abort("interrupted");
    control.signal?.addEventListener("abort", onShutdown);
    try {
      return await call(controller.signal);
    } catch (err) {
      // The request went out and ended without its answer: it may have billed tokens and searches nobody counted.
      if (billed) costUnknown = true;
      if (controller.signal.aborted) throw stopFor(controller.signal.reason as StopReason);
      log("studio request failed", { error: err instanceof Anthropic.APIError ? `api_${err.status ?? "connection"}` : (err as Error)?.name });
      throw fail("provider_error");
    } finally {
      clearTimeout(timer);
      clearInterval(poll);
      control.signal?.removeEventListener("abort", onShutdown);
    }
  }

  /**
   * One PAID model call: ceiling, clamp, reserve, send, settle (budget.ts). `spec` is the request's size; `call` gets the
   * max_tokens the job's remaining budget allows. The reservation is settled from the usage the reply reports; a call that
   * was sent but didn't come back cleanly keeps an allowance counted, and one that never left costs nothing.
   */
  async function paid<T extends { usage?: UsageLike }>(
    step: StudioStep, spec: { inputChars: number; cacheWrite?: boolean; tools?: boolean },
    call: (signal: AbortSignal, maxTokens: number) => Promise<T>,
  ): Promise<T> {
    const id = `${step}#${++callSeq}`;
    let maxTokens = 0;
    let sent = false;
    const prepare = () => {
      const searchesLeft = spec.tools ? Math.max(0, caps.maxSearches - Math.max(searches, reportedSearches)) : 0;
      const fetchesLeft = spec.tools ? Math.max(0, caps.maxFetches - Math.max(fetches, reportedFetches)) : 0;
      const wholeCaps = caps.maxSearches + caps.maxFetches;
      const toolInputTokens = spec.tools && wholeCaps > 0 ? caps.taskBudgetTokens * TOOL_INPUT_FACTOR * (searchesLeft + fetchesLeft) / wholeCaps : 0;
      const remaining = control.jobLimitUsd - stats().costUsd - reservations.openUsd;
      const plan = planCall({ step, model: api.models[step], inputChars: spec.inputChars, cacheWrite: spec.cacheWrite, searchesLeft, toolInputTokens }, remaining);
      if (!plan) {
        log("studio call not sent: its worst-case cost doesn't fit the job's limit", { step, remainingUsd: roundUsd(Math.max(0, remaining)) });
        throw fail("cost_limit");
      }
      maxTokens = plan.maxTokens;
      reservations.reserve(id, plan.ceilingUsd);
    };
    let r: T;
    try {
      r = await guarded((signal) => { sent = true; return call(signal, maxTokens); }, true, prepare);
    } catch (err) {
      if (sent) reservations.unknown(id); // guarded has already marked the job's cost unknown
      else reservations.release(id);
      throw err;
    }
    if (r.usage) {
      add(step, r.usage);
      reservations.settle(id);
    } else {
      reservations.unknown(id); // a reply with no usage may still have been billed
      costUnknown = true;
    }
    return r;
  }

  const structured = async <T>(step: StudioStep, input: string, system: string, call: (signal: AbortSignal, maxTokens: number) => Promise<Structured<T>>): Promise<Structured<T>> => {
    const r = await paid(step, { inputChars: system.length + input.length }, call);
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
    const planInput = JSON.stringify({ today, language, job });
    const planned = await structured("plan", planInput, PLAN_SYSTEM, (s, n) => api.plan(planInput, s, n));
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
      const m = await paid("research", { inputChars: RESEARCH_SYSTEM.length + JSON.stringify(messages).length, cacheWrite: true, tools: true }, (s, n) => api.research(messages, s, n));
      const counted = countToolUses(m.content);
      searches += counted.searches;
      fetches += counted.fetches;
      collectSources(m.content, seen);
      for (const url of seen.urls) if (!seenAt.has(url)) seenAt.set(url, now().toISOString());
      for (const b of m.content) if (b.type === "text" && typeof b.text === "string" && b.text.trim()) notes.push(b.text.trim());
      withinLimit();
      if (resumable(m.stop_reason, m.content) && turn < MAX_PAUSE_TURNS) {
        messages.push({ role: "assistant", content: echoable(m.content) });
        continue;
      }
      if (m.stop_reason === "refusal") throw fail("refused");
      break;
    }
    const allNotes = notes.join("\n\n").slice(0, MAX_NOTES_CHARS);
    if (!allNotes) throw fail("unreadable_result");

    const packInput = JSON.stringify({ today, language, job, notes: allNotes, sources: seen.list(200) });
    const packed = await structured("pack", packInput, PACK_SYSTEM, (s, n) => api.pack(packInput, s, n));
    if (packed.kind !== "ok") throw fail("unreadable_result");
    const pack = buildPack(packed.value.claims, seen, seenAt);
    log("studio pack", { claims: pack.claims.length, sources: pack.sources.length, seen: seen.size, offered: packed.value.claims.length });
    if (pack.claims.length < LIMITS.claimsMin) throw fail("too_little_found");
    withinLimit();

    // ---------- 3. write, checked by code (two retries; each gets the last attempt and its problems) ----------
    await control.setStage("write");
    const writeInput = { today, language, job, plan, pack };
    let content: ContentOutput | undefined;
    let problems: string[] = [];
    let previous: ContentOutput | undefined;
    for (let attempt = 0; attempt < MAX_WRITE_ATTEMPTS && !content; attempt++) {
      const input = attempt === 0 ? writeInput : { ...writeInput, previousAttempt: previous, fixThese: problems };
      const writeJson = JSON.stringify(input);
      const written = await structured("write", writeJson, WRITE_SYSTEM, (s, n) => api.write(writeJson, s, n));
      withinLimit();
      if (written.kind !== "ok") { problems = ["the reply didn't match the schema"]; continue; }
      previous = written.value;
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
      const m = await paid("make", { inputChars: MAKE_SYSTEM.length + JSON.stringify(turns).length, cacheWrite: true }, (s, n) => api.make(turns, containerId, s, n));
      containerMs += Date.now() - started;
      containerId = m.containerId ?? containerId;
      const made = fileIdsOf(m.content);
      for (const id of made) { ids.push(id); atAnthropic.add(id); }
      if (made.length) await control.noteFiles?.(made).catch((err) => log("studio files not noted", { error: (err as Error)?.name }));
      turns.push({ role: "assistant", content: m.content });
      withinLimit();
      if (resumable(m.stop_reason, m.content) && turn < MAX_PAUSE_TURNS) continue;
      if (m.stop_reason === "refusal") throw fail("refused");
      break;
    }
    const files: MadeFile[] = [];
    for (const id of ids) {
      const name = await guarded((s) => api.fileName(id, s), false);
      if (!isKeptFile(name)) continue;
      const bytes = await guarded((s) => api.download(id, s), false);
      files.push({ name, bytes });
    }
    return { containerId, files };
  }
}

/**
 * `pause_turn`, or (seen in the first real runs, Sonnet 5.5 with the 20260209 web tools) `tool_use` with no
 * tool call of ours in it: the server-side loop stopped early, and the turn is resumed as it stands.
 */
export function resumable(stop: string | null | undefined, content: readonly { type: string }[]): boolean {
  return stop === "pause_turn" || (stop === "tool_use" && !content.some((b) => b.type === "tool_use"));
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
