// What the Studio code needs, in one object (ADR-584). Built whenever MEMORY_ENCRYPTION_KEY is set, so
// stored items can still be read and deleted; new jobs also need the switch on and the model API
// (an Anthropic key and Doddy's skills). Otherwise create and approve answer 503 studio_disabled.
import type { TextCipher } from "../crypto.js";
import type { Db } from "../db.js";
import type { PushSender } from "../providers/types.js";
import type { StudioModelApi } from "./model.js";

export interface StudioSettings {
  enabled: boolean;
  model: string;
  skills: string;
  maxSearches: number;
  maxFetches: number;
  blockedDomains: string[];
  taskBudgetTokens: number;
  jobLimitUsd: number;
  dailyCapUsd: number;
  timeLimitMinutes: number;
  maxOpen: number;
}

/** For tests and a server without the variables: the code's defaults, switch on (the env's default is off). */
export const DEFAULT_STUDIO_SETTINGS: StudioSettings = {
  enabled: true, model: "claude-opus-5-5", skills: "", maxSearches: 15, maxFetches: 15, blockedDomains: [],
  taskBudgetTokens: 150_000, jobLimitUsd: 4, dailyCapUsd: 5, timeLimitMinutes: 20, maxOpen: 3,
};

/** Set aside per open job when checking the daily cap, before its real cost is known. */
export const RESERVE_PER_OPEN_JOB_USD = 2;

export interface StudioDeps {
  settings: StudioSettings;
  api?: StudioModelApi;
  now?: () => Date;
  cancelPollMs?: number;
}

export interface StudioContext {
  db: Db;
  cipher: TextCipher;
  settings: StudioSettings;
  api?: StudioModelApi;
  push?: PushSender;
  /** New jobs can be created, approved and started. */
  enabled: boolean;
  now: () => Date;
  cancelPollMs: number;
  log: (msg: string, extra?: object) => void;
}

export function studioContext(db: Db, deps: StudioDeps | undefined, cipher: TextCipher | undefined, push: PushSender | undefined,
  log: (msg: string, extra?: object) => void): StudioContext | undefined {
  if (!cipher) return undefined;
  const settings = deps?.settings ?? DEFAULT_STUDIO_SETTINGS;
  return {
    db, cipher, settings, api: deps?.api, push,
    enabled: settings.enabled && !!deps?.api && deps.api.skills.length > 0,
    now: deps?.now ?? (() => new Date()),
    cancelPollMs: deps?.cancelPollMs ?? 15_000,
    log,
  };
}

export const jobAad = (accountId: string, id: string) => `${accountId}:studio-job:${id}`;
export const resultAad = (accountId: string, id: string) => `${accountId}:studio-result:${id}`;
export const fileAad = (accountId: string, id: string, name: string) => `${accountId}:studio-file:${id}:${name}`;
