// What the errand code needs, in one object. Built whenever MEMORY_ENCRYPTION_KEY is set, so stored
// errands can still be read, acknowledged and deleted; new errands also need the switch on and a
// researcher (an Anthropic key). Otherwise create and approve answer 503 errands_disabled.
import { DEFAULT_ERRAND_SETTINGS, type ErrandSettings } from "../config.js";
import type { TextCipher } from "../crypto.js";
import type { Db } from "../db.js";
import type { PushSender } from "../providers/types.js";
import type { ErrandResearcher } from "./researcher.js";

export interface ErrandDeps {
  settings: ErrandSettings;
  researcher?: ErrandResearcher;
  /** For tests: a fixed clock. Every errand time written to the database comes from here. */
  now?: () => Date;
  /** How often a running request checks for Cancel (default 15 s). */
  cancelPollMs?: number;
}

export interface ErrandContext {
  db: Db;
  cipher: TextCipher;
  settings: ErrandSettings;
  researcher?: ErrandResearcher;
  push?: PushSender;
  /** New errands can be created, approved and started. */
  enabled: boolean;
  now: () => Date;
  cancelPollMs: number;
  log: (msg: string, extra?: object) => void;
}

export function errandContext(db: Db, deps: ErrandDeps | undefined, cipher: TextCipher | undefined, push: PushSender | undefined,
  log: (msg: string, extra?: object) => void): ErrandContext | undefined {
  if (!cipher) return undefined;
  const settings = deps?.settings ?? DEFAULT_ERRAND_SETTINGS;
  return {
    db, cipher, settings, researcher: deps?.researcher, push,
    enabled: settings.enabled && !!deps?.researcher,
    now: deps?.now ?? (() => new Date()),
    cancelPollMs: deps?.cancelPollMs ?? 15_000,
    log,
  };
}

export const contentAad = (accountId: string, errandId: string) => `${accountId}:errand:${errandId}`;
export const resultAad = (accountId: string, errandId: string) => `${accountId}:errand-result:${errandId}`;
