// CEIDG, the register of sole traders (ADR-670): GET dane.biznes.gov.pl/api/ceidg/v3/firma?nip= with the
// owner's JWT, which only this server holds (the iPhone asks GET /v1/registry/ceidg). Free, but the token is
// Doddy's own (biznes.gov.pl, e-service 00_9999_00), so it never goes to an app. CEIDG's limits are 50
// requests per 3 minutes and 1000 per hour (integrator documentation, API v3, v1.0); this module keeps a
// server-wide pace under them. Only the NIP is sent; the answer is cut down to what an invoice needs and
// nothing is stored or logged but status codes and timings.

export const CEIDG_HOSTS = ["dane.biznes.gov.pl", "test-dane.biznes.gov.pl"] as const;
export const CEIDG_DEFAULT_BASE = "https://dane.biznes.gov.pl/api/ceidg/v3";

export interface CeidgDeps {
  token: string;
  /** https://dane.biznes.gov.pl/api/ceidg/v3 or the test host. */
  baseUrl: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
  /** Server-wide pace: at most this many requests in `windowMs` (default 40 in 3 minutes, under CEIDG's 50). */
  maxPerWindow?: number;
  windowMs?: number;
  now?: () => number;
}

/** What the app gets: CEIDG's entries for the NIP, with only the fields an invoice needs. */
export interface CeidgEntry {
  nazwa: string;
  status: string;
  wlasciciel: { nip: string };
  adresDzialalnosci: { ulica?: string; budynek?: string; lokal?: string; miasto?: string; kod?: string; kraj?: string };
}

export type CeidgAnswer =
  | { kind: "found"; firma: CeidgEntry[] }
  | { kind: "not_found" }
  | { kind: "busy" }
  | { kind: "unavailable"; status: number };

/** Ten digits whose last is the check digit (weights 6, 5, 7, 2, 3, 4, 5, 6, 7, mod 11). */
export function isValidNip(nip: string): boolean {
  if (!/^\d{10}$/u.test(nip)) return false;
  const weights = [6, 5, 7, 2, 3, 4, 5, 6, 7];
  const sum = weights.reduce((acc, w, i) => acc + w * Number(nip[i]), 0);
  return sum % 11 === Number(nip[9]);
}

const ADDRESS_KEYS = ["ulica", "budynek", "lokal", "miasto", "kod", "kraj"] as const;

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value.trim().slice(0, 200) : undefined;
}

/** CEIDG's `{"firma": [...]}` cut down to the owner's NIP, the name, the status and the business address. */
export function trimEntries(body: unknown, nip: string): CeidgEntry[] | undefined {
  const firms = (body as { firma?: unknown })?.firma;
  if (!Array.isArray(firms)) return undefined;
  const out: CeidgEntry[] = [];
  for (const firm of firms.slice(0, 20)) {
    const f = firm as Record<string, unknown>;
    const owner = f.wlasciciel as Record<string, unknown> | undefined;
    if (text(owner?.nip) !== nip) continue;
    const nazwa = text(f.nazwa);
    if (!nazwa) continue;
    const place = (f.adresDzialalnosci ?? {}) as Record<string, unknown>;
    const adresDzialalnosci: CeidgEntry["adresDzialalnosci"] = {};
    for (const key of ADDRESS_KEYS) { const v = text(place[key]); if (v) adresDzialalnosci[key] = v; }
    out.push({ nazwa, status: text(f.status) ?? "", wlasciciel: { nip }, adresDzialalnosci });
  }
  return out;
}

export class CeidgClient {
  private readonly times: number[] = [];
  constructor(private readonly deps: CeidgDeps) {
    const host = new URL(deps.baseUrl).host;
    if (new URL(deps.baseUrl).protocol !== "https:" || !(CEIDG_HOSTS as readonly string[]).includes(host)) {
      throw new Error(`CEIDG_API_BASE must be https on ${CEIDG_HOSTS.join(" or ")}`);
    }
  }

  async lookup(nip: string): Promise<CeidgAnswer> {
    const now = (this.deps.now ?? Date.now)();
    const windowMs = this.deps.windowMs ?? 180_000;
    while (this.times.length > 0 && now - this.times[0]! >= windowMs) this.times.shift();
    if (this.times.length >= (this.deps.maxPerWindow ?? 40)) return { kind: "busy" };
    this.times.push(now);

    const url = `${this.deps.baseUrl.replace(/\/+$/u, "")}/firma?nip=${nip}`;
    let res: Response;
    try {
      res = await (this.deps.fetch ?? fetch)(url, {
        headers: { authorization: `Bearer ${this.deps.token}`, accept: "application/json" },
        redirect: "error",
        signal: AbortSignal.timeout(this.deps.timeoutMs ?? 8000),
      });
    } catch {
      return { kind: "unavailable", status: 0 };
    }
    if (res.status === 204 || res.status === 404) return { kind: "not_found" };
    if (res.status === 429) return { kind: "busy" };
    if (res.status !== 200) return { kind: "unavailable", status: res.status };
    let body: unknown;
    try { body = await res.json(); } catch { return { kind: "unavailable", status: 200 }; }
    const firma = trimEntries(body, nip);
    if (!firma) return { kind: "unavailable", status: 200 };
    return firma.length === 0 ? { kind: "not_found" } : { kind: "found", firma };
  }
}
