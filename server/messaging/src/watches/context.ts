// What the price-watch code needs, in one object. Built whenever MEMORY_ENCRYPTION_KEY is set, so
// finished and expired watches are still tidied away; creating, approving, reading and checking also
// need the switch on and a page fetcher. Otherwise every route answers 503 watches_disabled and
// nothing is stored or checked.
import { DEFAULT_WATCH_SETTINGS, type WatchSettings } from "../config.js";
import type { TextCipher } from "../crypto.js";
import type { Db } from "../db.js";
import type { PushSender } from "../providers/types.js";
import type { PageFetcher } from "../shopping/pagecheck.js";

export interface WatchDeps {
  settings: WatchSettings;
  /** The shared polite fetcher (providers/index.ts). Without one nothing can be read, so the feature is off. */
  fetcher?: PageFetcher;
  /** For tests: a fixed clock. Every watch time written to the database comes from here. */
  now?: () => Date;
  /** For tests: waiting between two requests to one host. Default: a real timer. */
  sleep?: (ms: number) => Promise<void>;
  /** The random shift of a check time, in ms, for a given time between checks. Tests give 0 or a fixed value. */
  jitterMs?: (intervalMs: number) => number;
}

export interface WatchContext {
  db: Db;
  cipher: TextCipher;
  settings: WatchSettings;
  fetcher?: PageFetcher;
  push?: PushSender;
  /** Routes answer and the worker checks. */
  enabled: boolean;
  now: () => Date;
  sleep: (ms: number) => Promise<void>;
  jitterMs: (intervalMs: number) => number;
  log: (msg: string, extra?: object) => void;
}

/** A shift of up to a quarter of an hour either way (at most 5% of the interval), so checks don't line up. */
export const defaultJitterMs = (intervalMs: number): number =>
  Math.round((Math.random() * 2 - 1) * Math.min(15 * 60_000, intervalMs * 0.05));

export function watchContext(db: Db, deps: WatchDeps | undefined, cipher: TextCipher | undefined, push: PushSender | undefined,
  log: (msg: string, extra?: object) => void): WatchContext | undefined {
  if (!cipher) return undefined;
  const settings = deps?.settings ?? DEFAULT_WATCH_SETTINGS;
  return {
    db, cipher, settings, fetcher: deps?.fetcher, push,
    enabled: settings.enabled && !!deps?.fetcher,
    now: deps?.now ?? (() => new Date()),
    sleep: deps?.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms))),
    jitterMs: deps?.jitterMs ?? defaultJitterMs,
    log,
  };
}

export const contentAad = (accountId: string, watchId: string) => `${accountId}:watch:${watchId}`;
