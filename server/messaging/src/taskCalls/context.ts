// What the call-case code needs, in one object. Built only when everything is configured
// (Twilio, ElevenLabs task agent, webhook secret, encryption key, public URL); otherwise the
// feature answers 503 not_configured and nothing is faked.
import type { TaskCallConfig, TaskCallSettings } from "../config.js";
import type { TextCipher } from "../crypto.js";
import type { Db } from "../db.js";
import type { TaskTelephony, TaskVoice } from "../providers/taskCalls.js";
import type { PushSender } from "../providers/types.js";
import { checkAgentSafety, type AgentProblem } from "./agentSafety.js";
import { TASK_AGENT_SPEC, TASK_BOOK_AGENT_SPEC, TASK_ORDER_AGENT_SPEC, type TaskAgentSpec } from "./agentSpec.js";
import type { BriefDrafter } from "./draft.js";
import { caseKeys, type CaseKeys } from "./payload.js";
import type { SayVoice } from "./twiml.js";

export interface LiveActivityPusher {
  /** ActivityKit push: phase and times only, never words. */
  update(token: string, env: "sandbox" | "production", state: Record<string, unknown>, end: boolean): Promise<void>;
}

/** Optional model step: picks the answer span, writes the summary and next step. */
export interface ResultWriter {
  readonly provider: "anthropic";
  readonly model: string;
  write(input: import("./result.js").WriterInput): Promise<import("./result.js").WriterOutput>;
}

export interface TaskCallDeps {
  telephony: TaskTelephony;
  voice: TaskVoice;
  config: TaskCallConfig;
  settings: TaskCallSettings;
  writer?: ResultWriter;
  /** Optional: proposes a brief from the user's one sentence (decision 2026-11-13-calls-one-field-brief). Anthropic only. */
  drafter?: BriefDrafter;
  liveActivity?: LiveActivityPusher;
  /** The daily caps on texts (SMS_DAILY_PER_ACCOUNT / SMS_DAILY_PER_SERVER) for a task's result text. Absent: the defaults. */
  smsCaps?: { perAccount: number; perServer: number };
  /** For tests: a fixed clock. Every task-call time written to the database comes from here. */
  now?: () => Date;
}

export interface TaskCallContext {
  db: Db;
  cipher: TextCipher;
  keys: CaseKeys;
  telephony: TaskTelephony;
  voice: TaskVoice;
  config: TaskCallConfig;
  settings: TaskCallSettings;
  publicBaseUrl: string;
  push?: PushSender;
  writer?: ResultWriter;
  drafter?: BriefDrafter;
  liveActivity?: LiveActivityPusher;
  smsCaps?: { perAccount: number; perServer: number };
  now: () => Date;
  say: SayVoice;
  /** The ask agent's safety check. */
  drift: DriftCache;
  /** The safety check of the agent for a call's kind; the booking agent's fails closed while it isn't configured. */
  driftFor(kind: "ask" | "book" | "order"): DriftCache;
  /** The ElevenLabs agent that talks on a call of this kind; undefined for "book" and "order" while they aren't configured. */
  agentIdFor(kind: "ask" | "book" | "order"): string | undefined;
  log: (msg: string, extra?: object) => void;
}

export function taskCallContext(
  db: Db, deps: TaskCallDeps | undefined, cipher: TextCipher | undefined, publicBaseUrl: string | undefined,
  push: PushSender | undefined, log: (msg: string, extra?: object) => void,
): TaskCallContext | undefined {
  if (!deps || !cipher || !publicBaseUrl) return undefined;
  const now = deps.now ?? (() => new Date());
  const drift = new DriftCache(deps.voice, deps.config.agentId, now, log);
  const bookAgentId = deps.config.bookAgentId;
  const bookDrift = bookAgentId ? new DriftCache(deps.voice, bookAgentId, now, log, TASK_BOOK_AGENT_SPEC) : DriftCache.notConfigured(deps.voice, now, log);
  const orderAgentId = deps.config.orderAgentId;
  const orderDrift = orderAgentId ? new DriftCache(deps.voice, orderAgentId, now, log, TASK_ORDER_AGENT_SPEC) : DriftCache.notConfigured(deps.voice, now, log);
  return {
    db, cipher, keys: caseKeys(cipher), telephony: deps.telephony, voice: deps.voice, config: deps.config,
    settings: deps.settings, publicBaseUrl, push, writer: deps.writer, drafter: deps.drafter, liveActivity: deps.liveActivity, smsCaps: deps.smsCaps, now,
    say: { voice: deps.settings.sayVoice, language: "pl-PL" },
    drift,
    driftFor: (kind) => (kind === "order" ? orderDrift : kind === "book" ? bookDrift : drift),
    agentIdFor: (kind) => (kind === "order" ? orderAgentId : kind === "book" ? bookAgentId : deps.config.agentId),
    log,
  };
}

export const DRIFT_TTL_MS = 10 * 60_000;

/**
 * The live agent's safety check, refreshed at most every 10 minutes. Fails closed: an agent that
 * couldn't be read counts as a problem, so no call starts.
 */
export class DriftCache {
  private last?: { problems: AgentProblem[]; at: number };
  private inFlight?: Promise<AgentProblem[]>;

  constructor(private readonly voice: TaskVoice, private readonly agentId: string | undefined, private readonly now: () => Date,
    private readonly log: (msg: string, extra?: object) => void, private readonly spec: TaskAgentSpec = TASK_AGENT_SPEC) {}

  /** Which agent this cache reads, for the log: the ask, booking or order agent. */
  private get agent(): "ask" | "book" | "order" {
    return this.spec === TASK_AGENT_SPEC ? "ask" : this.spec === TASK_ORDER_AGENT_SPEC ? "order" : "book";
  }

  /** For an agent that isn't set up: always a problem, never a network call. */
  static notConfigured(voice: TaskVoice, now: () => Date, log: (msg: string, extra?: object) => void): DriftCache {
    return new DriftCache(voice, undefined, now, log);
  }

  /** Problems right now, reading the agent if the last check is older than the TTL. */
  async problems(): Promise<AgentProblem[]> {
    if (this.last && this.now().getTime() - this.last.at < DRIFT_TTL_MS) return this.last.problems;
    this.inFlight ??= this.refresh().finally(() => { this.inFlight = undefined; });
    return this.inFlight;
  }

  /** The last result without any network (for the answer webhook); unknown counts as a problem. */
  cached(): AgentProblem[] {
    return this.last?.problems ?? ["unreadable"];
  }

  async refresh(): Promise<AgentProblem[]> {
    if (!this.agentId) {
      this.last = { problems: ["unreadable"], at: this.now().getTime() };
      return this.last.problems;
    }
    const agent = await this.voice.getAgent(this.agentId);
    const problems = agent === "error" ? ["unreadable" as const] : checkAgentSafety(agent, this.spec);
    // Logged when the first check is made and whenever the answer changes: names only, never values. The
    // first line after a deploy is how the live agent is confirmed (or refused) without reading its settings.
    if (!this.last || this.last.problems.join() !== problems.join()) {
      if (problems.length) this.log("task-call agent differs from its spec; calls refused", { agent: this.agent, problems });
      else this.log("task-call agent matches its spec", { agent: this.agent });
    }
    this.last = { problems, at: this.now().getTime() };
    return problems;
  }
}
