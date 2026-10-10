// Minimal client for a Redis-compatible REST API (Upstash Redis REST; Vercel KV / Marketplace Redis
// expose the same API). Plain `fetch`, zero dependencies. Only the transaction endpoint is used:
//   POST <url>/multi-exec   body: [["INCR","k"],["EXPIRE","k","60"]]   reply: [{"result":1},{"result":1}]
// Every failure (network, timeout, non-2xx, an {error} entry, an unexpected shape) throws
// StoreUnavailableError, so callers can fail closed. The token is only ever sent in the header.

export class StoreUnavailableError extends Error {
  constructor() {
    super('shared store unavailable');
    this.name = 'StoreUnavailableError';
  }
}

/**
 * @typedef {(string|number)[]} Command
 * @typedef {{exec(commands: Command[]): Promise<unknown[]>}} SharedStore
 */

/**
 * @param {{url: string, token: string, fetch: typeof fetch, timeoutMs?: number}} cfg
 * @returns {SharedStore}
 */
export function createRestStore(cfg) {
  const endpoint = `${cfg.url.replace(/\/+$/, '')}/multi-exec`;
  const timeoutMs = cfg.timeoutMs ?? 2_000;
  return {
    async exec(commands) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const res = await cfg.fetch(endpoint, {
          method: 'POST',
          headers: { 'content-type': 'application/json', authorization: `Bearer ${cfg.token}` },
          body: JSON.stringify(commands.map((c) => c.map(String))),
          signal: controller.signal,
        });
        if (!res.ok) throw new StoreUnavailableError();
        const data = await res.json();
        if (!Array.isArray(data) || data.length !== commands.length) throw new StoreUnavailableError();
        return data.map((entry) => {
          if (!entry || typeof entry !== 'object' || 'error' in entry || !('result' in entry)) throw new StoreUnavailableError();
          return entry.result;
        });
      } catch {
        // Never rethrow the original: it could carry the URL or a provider body into a log.
        throw new StoreUnavailableError();
      } finally {
        clearTimeout(timer);
      }
    },
  };
}

/** Redis returns integers as numbers over REST; accept numeric strings too, reject anything else. */
export function asInt(/** @type {unknown} */ value) {
  const n = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : NaN;
  if (!Number.isSafeInteger(n)) throw new StoreUnavailableError();
  return n;
}
