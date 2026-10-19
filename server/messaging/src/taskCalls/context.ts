// What the call-case code needs, in one object. Built only when everything is configured
// (Twilio, ElevenLabs task agent, webhook secret, encryption key, public URL); otherwise the
// feature answers 503 not_configured and nothing is faked.
import type { TaskCallConfig, TaskCallSettings } from "../config.js";
import type { TextCipher } from "../crypto.js";
import type { Db } from "../db.js";
import type { TaskTelephony, TaskVoice } from "../providers/taskCalls.js";
import type { PushSender } from "../providers/types.js";
import { checkAgentSafety, type AgentProblem } from "./agentSafety.js";
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
  liveActivity?: LiveActivityPusher;
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
  liveActivity?: LiveActivityPusher;
  now: () => Date;
  say: SayVoice;
  drift: DriftCache;
  log: (msg: string, extra?: object) => void;
}

export function taskCallContext(
  db: Db, deps: TaskCallDeps | undefined, cipher: TextCipher | undefined, publicBaseUrl: string | undefined,
  push: PushSender | undefined, log: (msg: string, extra?: object) => void,
): TaskCallContext | undefined {
  if (!deps || !cipher || !publicBaseUrl) return undefined;
  const now = deps.now ?? (() => new Date());
  return {
    db, cipher, keys: caseKeys(cipher), telephony: deps.telephony, voice: deps.voice, config: deps.config,
    settings: deps.settings, publicBaseUrl, push, writer: deps.writer, liveActivity: deps.liveActivity, now,
    say: { voice: deps.settings.sayVoice, language: "pl-PL" },
    drift: new DriftCache(deps.voice, deps.config.agentId, now, log),
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

  constructor(private readonly voice: TaskVoice, private readonly agentId: string, private readonly now: () => Date,
    private readonly log: (msg: string, extra?: object) => void) {}

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
    const agent = await this.voice.getAgent(this.agentId);
    const problems = agent === "error" ? ["unreadable" as const] : checkAgentSafety(agent);
    if (problems.length && (!this.last || this.last.problems.join() !== problems.join())) {
      this.log("task-call agent differs from its spec; calls refused", { problems });
    }
    this.last = { problems, at: this.now().getTime() };
    return problems;
  }
}
