// What the chain adapters share: fetching from the chain's official hosts only, turning a fetch result into a
// chain status, dates in Warsaw, and money from a chain's own numbers.
import type { FetchResult } from "../fetcher.js";
import type { ChainContext, ChainRead, Money } from "../types.js";

/** The address only if it is https on one of the chain's hosts (addresses in a chain's data are data). */
export function officialUrl(raw: unknown, hosts: readonly string[], base?: string): URL | undefined {
  if (typeof raw !== "string" || !raw.trim()) return undefined;
  let u: URL;
  try { u = new URL(raw.trim(), base); } catch { return undefined; }
  if (u.protocol !== "https:" || u.username || u.password || (u.port && u.port !== "443")) return undefined;
  return hosts.includes(u.hostname) ? u : undefined;
}

export type Fetched = { ok: true; body: Buffer; finalUrl: URL } | { ok: false; read: ChainRead };

/** A blocked or robots-disallowed fetch is `blocked`; anything else that failed is `failed`. */
export function notRead(r: Exclude<FetchResult, { kind: "ok" }>): ChainRead {
  return r.kind === "failed" ? { kind: "failed", reason: r.reason } : { kind: "blocked", reason: `${r.kind}:${r.reason}` };
}

/** Fetches from one of the chain's hosts; a redirect off them counts as failed. */
export async function fetchOfficial(ctx: ChainContext, url: string, hosts: readonly string[], accept: string): Promise<Fetched> {
  if (!officialUrl(url, hosts)) return { ok: false, read: { kind: "failed", reason: "not_official_host" } };
  const r = await ctx.fetcher.fetchPage(url, { accept, signal: ctx.signal });
  if (r.kind !== "ok") return { ok: false, read: notRead(r) };
  const finalUrl = officialUrl(r.finalUrl, hosts);
  if (!finalUrl) return { ok: false, read: { kind: "failed", reason: "redirected_off_host" } };
  return { ok: true, body: r.body, finalUrl };
}

export function parseJson(body: Buffer): unknown {
  try { return JSON.parse(body.toString("utf8")); } catch { return undefined; }
}

export const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
export const str = (v: unknown): string | undefined => (typeof v === "string" && v.trim() ? v.trim() : undefined);

/** A price the chain published as a number or a "79.99" string. */
export function moneyOf(v: unknown): Money | undefined {
  const n = typeof v === "number" ? v : typeof v === "string" && /^\d{1,6}(\.\d{1,2})?$/.test(v.trim()) ? Number(v) : NaN;
  if (!Number.isFinite(n)) return undefined;
  const minor = Math.round(n * 100);
  return minor > 0 && minor < 1_000_000 ? { minor, currency: "PLN" } : undefined;
}

export const validEan = (v: unknown): string | undefined => (typeof v === "string" && /^\d{8,14}$/.test(v) ? v : undefined);

/** Today's date in Warsaw, YYYY-MM-DD. */
export function warsawDay(now: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Warsaw", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

/** "2026-10-21", "2026-10-21 00:00:00", "2026-10-21T00:00:00+02:00" → "2026-10-21". */
export function isoDay(v: unknown): string | undefined {
  if (typeof v !== "string") return undefined;
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])/.exec(v.trim());
  if (!m) return undefined;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.getUTCMonth() === Number(m[2]) - 1 ? `${m[1]}-${m[2]}-${m[3]}` : undefined;
}

export function addDays(day: string, n: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** A day and month without a year (as leaflets print them): the year that puts it nearest to today. */
export function dayMonth(day: number, month: number, today: string, year?: number): string | undefined {
  if (day < 1 || day > 31 || month < 1 || month > 12) return undefined;
  const t = Number(today.slice(0, 4));
  const candidates = (year ? [year] : [t - 1, t, t + 1]).map((y) => isoDay(`${y}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`))
    .filter((d): d is string => !!d);
  const dist = (d: string) => Math.abs(Date.parse(`${d}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`));
  return candidates.sort((a, b) => dist(a) - dist(b))[0];
}

/** This week's leaflets: those whose dates touch today or the six days after it. Open ends count as open. */
export function currentWeek(validFrom: string | undefined, validTo: string | undefined, today: string): boolean {
  const end = addDays(today, 6);
  if (validTo && validTo < today) return false;
  if (validFrom && validFrom > end) return false;
  return true;
}

/** Runs `fn` over `items` with at most `limit` at once, keeping the order of the results. */
export async function mapLimit<T, R>(items: readonly T[], limit: number, fn: (item: T, index: number) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const worker = async () => {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      out[i] = await fn(items[i]!, i);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

/** Decodes the few HTML entities that appear in names and titles. */
export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (all, e: string) => {
    const k = e.toLowerCase();
    if (k === "amp") return "&";
    if (k === "lt") return "<";
    if (k === "gt") return ">";
    if (k === "quot") return '"';
    if (k === "apos") return "'";
    if (k === "nbsp") return " ";
    const code = k.startsWith("#x") ? parseInt(k.slice(2), 16) : parseInt(k.slice(1), 10);
    return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : all;
  });
}
