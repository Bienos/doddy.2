// Host clients for the sync tool. Each one lists what a host has and writes one variable at a time.
// They never return or log a value they read: Render's API sends values back on every read and
// write, so the Render client reduces each one to a fingerprint at once (ADR-493).
//
// Outcomes follow the constitution's action rule: a write is "set" only when the host's answer
// confirms it; a timeout, a dropped connection or a 5xx is "unknown" (never success, never retried
// here); a 4xx is "failed".
import { fingerprint } from "./redact.mjs";

export class HostError extends Error {
  /** @param {"failed"|"unknown"} outcome */
  constructor(outcome, message) {
    super(message);
    this.outcome = outcome;
  }
}

async function call(fetchImpl, url, init, timeoutMs, { write }) {
  let response;
  try {
    response = await fetchImpl(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
  } catch (error) {
    const timedOut = error?.name === "TimeoutError" || error?.name === "AbortError";
    // Never include error.message: some fetch errors echo the request.
    throw new HostError("unknown", timedOut ? "timed out" : "connection failed");
  }
  if (!response.ok) {
    const outcome = write && response.status >= 500 ? "unknown" : "failed";
    throw new HostError(outcome, `HTTP ${response.status}`);
  }
  if (response.status === 204) return null;
  try {
    return await response.json();
  } catch {
    if (write) throw new HostError("unknown", "unreadable answer");
    throw new HostError("failed", "unreadable answer");
  }
}

/**
 * Vercel project environment variables. Lists names without decrypting anything (no `decrypt`),
 * and stores every value it writes as the Secret ("sensitive") type, which can't be read back.
 */
export function vercelClient({ token, teamId, fetch: fetchImpl = fetch, timeoutMs = 15_000, base = "https://api.vercel.com" }) {
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  const url = (path) => `${base}${path}${path.includes("?") ? "&" : "?"}teamId=${encodeURIComponent(teamId)}`;
  const project = (name) => encodeURIComponent(name);
  return {
    /** @returns {Promise<Map<string, Array<{id: string, type: string, targets: string[], updatedAt: number|null}>>>} */
    async list(name) {
      const body = await call(fetchImpl, url(`/v10/projects/${project(name)}/env`), { method: "GET", headers }, timeoutMs, { write: false });
      const byKey = new Map();
      for (const env of body?.envs ?? []) {
        // Only metadata is kept; `value` (encrypted, or plain for Config types) is dropped here.
        const entry = {
          id: String(env.id),
          type: String(env.type ?? ""),
          targets: Array.isArray(env.target) ? env.target.map(String) : env.target ? [String(env.target)] : [],
          updatedAt: typeof env.updatedAt === "number" ? env.updatedAt : null,
        };
        byKey.set(env.key, [...(byKey.get(env.key) ?? []), entry]);
      }
      return byKey;
    },
    async create(name, key, value, target) {
      await call(fetchImpl, url(`/v10/projects/${project(name)}/env`), {
        method: "POST", headers, body: JSON.stringify({ key, value, type: "sensitive", target: [target] }),
      }, timeoutMs, { write: true });
    },
    async update(name, id, value) {
      await call(fetchImpl, url(`/v9/projects/${project(name)}/env/${encodeURIComponent(id)}`), {
        method: "PATCH", headers, body: JSON.stringify({ value }),
      }, timeoutMs, { write: true });
    },
    async remove(name, id) {
      await call(fetchImpl, url(`/v9/projects/${project(name)}/env/${encodeURIComponent(id)}`), { method: "DELETE", headers }, timeoutMs, { write: true });
    },
  };
}

/**
 * Render service or env-group variables, one key at a time (never the bulk replace, which would
 * drop or regenerate keys such as the backend's generated signing key).
 */
export function renderClient({ apiKey, fetch: fetchImpl = fetch, timeoutMs = 15_000, base = "https://api.render.com" }) {
  const headers = { authorization: `Bearer ${apiKey}`, "content-type": "application/json", accept: "application/json" };
  const path = (kind, id) => (kind === "render-group" ? `/v1/env-groups/${encodeURIComponent(id)}` : `/v1/services/${encodeURIComponent(id)}`);
  return {
    /** @returns {Promise<Map<string, string>>} name -> fingerprint of the stored value */
    async list(kind, id) {
      const result = new Map();
      if (kind === "render-group") {
        const body = await call(fetchImpl, `${base}${path(kind, id)}`, { method: "GET", headers }, timeoutMs, { write: false });
        for (const item of body?.envVars ?? []) result.set(item.key, fingerprint(String(item.value ?? "")));
        return result;
      }
      let cursor = null;
      for (let page = 0; page < 20; page++) {
        const query = `?limit=100${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`;
        const body = await call(fetchImpl, `${base}${path(kind, id)}/env-vars${query}`, { method: "GET", headers }, timeoutMs, { write: false });
        const items = Array.isArray(body) ? body : [];
        for (const item of items) {
          const envVar = item?.envVar ?? item;
          result.set(envVar.key, fingerprint(String(envVar.value ?? "")));
        }
        if (items.length < 100) break;
        cursor = items[items.length - 1]?.cursor ?? null;
        if (!cursor) break;
      }
      return result;
    },
    /** @returns {Promise<string|null>} fingerprint of the value Render says it stored, if it said */
    async put(kind, id, key, value) {
      const body = await call(fetchImpl, `${base}${path(kind, id)}/env-vars/${encodeURIComponent(key)}`, {
        method: "PUT", headers, body: JSON.stringify({ value }),
      }, timeoutMs, { write: true });
      // A service answers with the variable; a group answers with the whole group.
      const stored = body?.envVars ? body.envVars.find((item) => item.key === key) : body;
      return stored && stored.key === key && typeof stored.value === "string" ? fingerprint(stored.value) : null;
    },
    async remove(kind, id, key) {
      await call(fetchImpl, `${base}${path(kind, id)}/env-vars/${encodeURIComponent(key)}`, { method: "DELETE", headers }, timeoutMs, { write: true });
    },
  };
}
