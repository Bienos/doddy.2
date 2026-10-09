/**
 * Fixed-window rate limit per session id. In-memory only: it resets on restart and does not
 * coordinate across instances. Adequate for one instance; a shared store is needed before scaling out.
 */
export function createSessionLimiter({ maxRequests = 20, windowMs = 60_000, now = () => Date.now() } = {}) {
  const windows = new Map();

  return {
    /** Returns true if the request is allowed and records it. */
    allow(sessionId) {
      const t = now();
      const entry = windows.get(sessionId);
      if (!entry || t - entry.start >= windowMs) {
        windows.set(sessionId, { start: t, count: 1 });
        return true;
      }
      if (entry.count >= maxRequests) return false;
      entry.count += 1;
      return true;
    },
  };
}
