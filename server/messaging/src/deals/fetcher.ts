// The polite fetcher (SHOPPING.md §1.2), one for leaflets and for shop pages: User-Agent DoddyBot, robots.txt
// checked for that agent and `*` before every request (a disallowed fetch is not made), HTTPS only, no
// cookies, no login, 10 s for the whole fetch with redirects, 3 MB cap. A 401/403/429, a challenge page or a
// captcha comes back as `blocked` and is never retried or worked around.
//
// The default transport is node:https with every resolved address checked at connect time (no private or
// local networks, as in news/safeFetch.ts), so an address from a page can't reach this server's own network.
// Tests inject a fake `fetch`. Only the robots files are cached (in memory, per origin); pages never are.
import { lookup as dnsLookup } from "node:dns";
import https from "node:https";
import { pipeline, Readable } from "node:stream";
import zlib from "node:zlib";
import type { LookupFunction } from "node:net";
import { checkUrl, isPublicAddress, UnsafeUrlError } from "../news/safeFetch.js";

export const DODDY_BOT_UA = "DoddyBot/1.0 (+https://doddy.lol/bot)";
/** The product token robots.txt groups are matched against (case-insensitive). */
export const ROBOTS_TOKEN = "doddybot";

export type FetchResult =
  | { kind: "ok"; status: number; contentType: string; body: Buffer; finalUrl: string }
  | { kind: "blocked" | "disallowed" | "failed"; reason: string };

export interface FetchPageOptions {
  accept?: string;
  /** The content will go to an AI model: robots.txt `Content-Signal: ai-input=no` refuses the fetch. */
  aiInput?: boolean;
  /** Stops the fetch early (the caller's own deadline). */
  signal?: AbortSignal;
}

export interface PageFetcher {
  fetchPage(url: string, opts?: FetchPageOptions): Promise<FetchResult>;
}

/** A `fetch`-shaped transport. It must not follow redirects (the fetcher checks each hop). */
export type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

export interface FetcherOptions {
  fetch?: FetchFn;
  userAgent?: string;
  timeoutMs?: number;
  maxBytes?: number;
  maxRedirects?: number;
  /** How long a robots.txt that was read stays cached. Default 1 hour. */
  robotsTtlMs?: number;
  now?: () => number;
}

export const DEFAULT_TIMEOUT_MS = 10_000;
export const DEFAULT_MAX_BYTES = 3 * 1024 * 1024;
const ROBOTS_MAX_BYTES = 512 * 1024;
const ROBOTS_RETRY_MS = 5 * 60_000;
const ROBOTS_MAX_ORIGINS = 256;

// ---------- robots.txt ----------

export interface RobotsRule { allow: boolean; pattern: string }
export interface RobotsGroup { agents: string[]; rules: RobotsRule[]; signals: Record<string, string> }

/** Parses robots.txt into groups (RFC 9309), plus Cloudflare-style `Content-Signal` lines per group. */
export function parseRobots(text: string): RobotsGroup[] {
  const groups: RobotsGroup[] = [];
  let current: RobotsGroup | undefined;
  let lastWasAgent = false;
  for (const rawLine of text.split(/\r\n|\r|\n/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
    const m = /^([A-Za-z-]+)\s*:\s*(.*)$/.exec(line);
    if (!m) continue;
    const key = m[1]!.toLowerCase();
    const value = m[2]!.trim();
    if (key === "user-agent") {
      if (!current || !lastWasAgent) {
        current = { agents: [], rules: [], signals: {} };
        groups.push(current);
      }
      current.agents.push(value.toLowerCase());
      lastWasAgent = true;
      continue;
    }
    lastWasAgent = false;
    if (!current) continue; // rules before any user-agent line belong to no group
    if (key === "allow" || key === "disallow") {
      if (value) current.rules.push({ allow: key === "allow", pattern: value });
    } else if (key === "content-signal") {
      for (const part of value.split(",")) {
        const [k, v] = part.split("=").map((s) => s.trim().toLowerCase());
        if (k && v) current.signals[k] = v;
      }
    }
  }
  return groups;
}

function normalisePattern(p: string): string {
  try { return encodeURI(decodeURI(p)); } catch { return p; }
}

/** True when `pattern` (with `*` and a trailing `$`) matches the start of `path`. */
export function robotsPatternMatches(pattern: string, path: string): boolean {
  const p = normalisePattern(pattern);
  const anchored = p.endsWith("$");
  const body = anchored ? p.slice(0, -1) : p;
  const re = body.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*");
  return new RegExp(`^${re}${anchored ? "$" : ""}`).test(path);
}

/** The groups that apply to `token`: every group naming it, else every `*` group (merged, RFC 9309). */
export function groupsFor(groups: RobotsGroup[], token: string): RobotsGroup[] {
  const named = groups.filter((g) => g.agents.some((a) => a === token || a.split("/")[0] === token));
  return named.length ? named : groups.filter((g) => g.agents.includes("*"));
}

/** Longest matching rule wins; Allow wins a tie; no matching rule allows. `/robots.txt` is always allowed. */
export function robotsAllows(groups: RobotsGroup[], token: string, pathAndQuery: string): { allowed: boolean; signals: Record<string, string> } {
  const applying = groupsFor(groups, token);
  const signals: Record<string, string> = {};
  for (const g of applying) Object.assign(signals, g.signals);
  if (pathAndQuery === "/robots.txt") return { allowed: true, signals };
  let best: RobotsRule | undefined;
  for (const g of applying) {
    for (const r of g.rules) {
      if (!robotsPatternMatches(r.pattern, pathAndQuery)) continue;
      if (!best || r.pattern.length > best.pattern.length || (r.pattern.length === best.pattern.length && r.allow && !best.allow)) best = r;
    }
  }
  return { allowed: best ? best.allow : true, signals };
}

type RobotsState =
  | { kind: "rules"; groups: RobotsGroup[] }
  | { kind: "allow_all" } // 4xx: no robots file
  | { kind: "unreachable" } // 5xx, network, timeout: assume everything is disallowed (RFC 9309)
  | { kind: "blocked"; reason: string }; // 401/403-with-challenge or 429 on robots.txt itself

// ---------- the default transport ----------

const safeLookup: LookupFunction = (hostname, options, callback) => {
  dnsLookup(hostname, { ...options, all: true }, (err, addresses) => {
    if (err) return callback(err, "", 0);
    const list = addresses as unknown as { address: string; family: number }[];
    if (list.length === 0 || list.some((a) => !isPublicAddress(a.address))) {
      return callback(new UnsafeUrlError("resolves to a private address"), "", 0);
    }
    if ((options as { all?: boolean }).all) return (callback as unknown as (e: null, a: typeof list) => void)(null, list);
    callback(null, list[0]!.address, list[0]!.family);
  });
};

/** GET over node:https with connect-time address checks and gzip/deflate/br decoding. No redirects, no cookies. */
export const safeHttpsFetch: FetchFn = (url, init) => new Promise<Response>((resolve, reject) => {
  const u = new URL(url);
  if (u.protocol !== "https:") return reject(new UnsafeUrlError("scheme"));
  const headers: Record<string, string> = { "accept-encoding": "gzip, deflate, br" };
  new Headers(init.headers).forEach((v, k) => { headers[k] = v; });
  const req = https.request(u, { method: "GET", headers, lookup: safeLookup, signal: init.signal ?? undefined }, (res) => {
    const status = res.statusCode ?? 0;
    const h = new Headers();
    for (const [k, v] of Object.entries(res.headers)) {
      if (v === undefined) continue;
      if (Array.isArray(v)) v.forEach((x) => h.append(k, x)); else h.set(k, String(v));
    }
    if (status < 200 || status > 599) { res.resume(); return reject(new Error(`status ${status}`)); }
    if (status >= 300 && status < 400 || status === 204 || status === 205) {
      res.resume();
      return resolve(new Response(null, { status, headers: h }));
    }
    const enc = (res.headers["content-encoding"] ?? "").toString().toLowerCase().trim();
    const decoder = enc === "gzip" || enc === "x-gzip" ? zlib.createGunzip()
      : enc === "deflate" ? zlib.createInflate()
      : enc === "br" ? zlib.createBrotliDecompress() : undefined;
    let body: Readable = res;
    if (decoder) {
      body = pipeline(res, decoder, () => {});
      h.delete("content-encoding");
      h.delete("content-length");
    }
    resolve(new Response(Readable.toWeb(body) as unknown as ReadableStream<Uint8Array>, { status, headers: h }));
  });
  req.on("error", reject);
  req.end();
});

// ---------- the fetcher ----------

const CHALLENGE_MARKERS = [
  /<title>\s*just a moment\.\.\.\s*<\/title>/i, // Cloudflare interstitial
  /_cf_chl_opt|cf-chl-bypass|cf_chl_prog/i,
  /<title>\s*attention required!?\s*\|\s*cloudflare/i,
  /px-captcha|captcha-delivery\.com|\/_incapsula_resource/i,
  /<title>[^<]*(captcha|access denied|dost[eę]p zablokowany)[^<]*<\/title>/i,
];

/** True for a challenge, captcha or bot-wall page. Only strong markers: the ordinary Cloudflare beacon is not one. */
export function looksLikeChallenge(headers: Headers, body: Buffer): boolean {
  if ((headers.get("cf-mitigated") ?? "").toLowerCase() === "challenge") return true;
  const type = (headers.get("content-type") ?? "").toLowerCase();
  if (!type.includes("html")) return false;
  const head = body.subarray(0, 64 * 1024).toString("utf8");
  return CHALLENGE_MARKERS.some((re) => re.test(head));
}

/** Reads the body up to `max` bytes: past it, "too_large" (or, with `truncate`, the first `max` bytes). */
async function readCapped(res: Response, max: number, truncate = false): Promise<Buffer | "too_large"> {
  if (!res.body) return Buffer.alloc(0);
  const reader = res.body.getReader();
  const chunks: Buffer[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      await reader.cancel().catch(() => {});
      if (!truncate) return "too_large";
      chunks.push(Buffer.from(value.subarray(0, value.byteLength - (size - max))));
      break;
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

const discard = (res: Response) => { void res.body?.cancel().catch(() => {}); };

/** HTTPS, default port, no credentials, not a local or private address. */
function httpsUrl(raw: string | URL): URL | { reason: string } {
  let u: URL;
  try { u = typeof raw === "string" ? new URL(raw) : new URL(raw.toString()); } catch { return { reason: "not_a_url" }; }
  if (u.protocol !== "https:") return { reason: "not_https" };
  try { checkUrl(u.toString()); } catch { return { reason: "unsafe_url" }; }
  u.hash = "";
  return u;
}

export class PoliteFetcher implements PageFetcher {
  private readonly fetchFn: FetchFn;
  private readonly userAgent: string;
  private readonly timeoutMs: number;
  private readonly maxBytes: number;
  private readonly maxRedirects: number;
  private readonly robotsTtlMs: number;
  private readonly now: () => number;
  private readonly robots = new Map<string, { expires: number; state: Promise<RobotsState> }>();

  constructor(opts: FetcherOptions = {}) {
    this.fetchFn = opts.fetch ?? safeHttpsFetch;
    this.userAgent = opts.userAgent ?? DODDY_BOT_UA;
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.maxBytes = opts.maxBytes ?? DEFAULT_MAX_BYTES;
    this.maxRedirects = opts.maxRedirects ?? 3;
    this.robotsTtlMs = opts.robotsTtlMs ?? 3600_000;
    this.now = opts.now ?? Date.now;
  }

  async fetchPage(raw: string, opts: FetchPageOptions = {}): Promise<FetchResult> {
    const first = httpsUrl(raw);
    if (!(first instanceof URL)) return { kind: "failed", reason: first.reason };
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error("timeout")), this.timeoutMs);
    const onAbort = () => controller.abort(new Error("aborted"));
    if (opts.signal?.aborted) onAbort();
    opts.signal?.addEventListener("abort", onAbort);
    try {
      let url = first;
      for (let hop = 0; ; hop++) {
        const verdict = await this.robotsVerdict(url, opts.aiInput === true);
        if (verdict) return verdict;
        if (controller.signal.aborted) throw controller.signal.reason;
        const res = await this.fetchFn(url.toString(), {
          method: "GET", redirect: "manual", credentials: "omit", signal: controller.signal,
          headers: { "user-agent": this.userAgent, accept: opts.accept ?? "*/*", "accept-language": "pl-PL,pl;q=0.9,en;q=0.5" },
        });
        const status = res.status;
        if (status >= 300 && status < 400) {
          discard(res);
          const location = res.headers.get("location");
          if (!location) return { kind: "failed", reason: "redirect_without_location" };
          if (hop >= this.maxRedirects) return { kind: "failed", reason: "too_many_redirects" };
          const next = httpsUrl(new URL(location, url));
          if (!(next instanceof URL)) return { kind: "failed", reason: `redirect_${next.reason}` };
          url = next;
          continue;
        }
        if ((res.headers.get("cf-mitigated") ?? "").toLowerCase() === "challenge") {
          discard(res);
          return { kind: "blocked", reason: "challenge" };
        }
        if ([401, 403, 407, 429, 451].includes(status)) {
          discard(res);
          return { kind: "blocked", reason: `http_${status}` };
        }
        if (status >= 400) {
          // A 503 challenge page is a block, not an outage.
          const body = status === 503 ? await readCapped(res, 256 * 1024).catch(() => Buffer.alloc(0)) : (discard(res), Buffer.alloc(0));
          if (body !== "too_large" && body.length && looksLikeChallenge(res.headers, body)) return { kind: "blocked", reason: "challenge" };
          return { kind: "failed", reason: `http_${status}` };
        }
        const declared = Number(res.headers.get("content-length") ?? "");
        if (Number.isFinite(declared) && declared > this.maxBytes) {
          discard(res);
          return { kind: "failed", reason: "too_large" };
        }
        const body = await readCapped(res, this.maxBytes);
        if (body === "too_large") return { kind: "failed", reason: "too_large" };
        if (looksLikeChallenge(res.headers, body)) return { kind: "blocked", reason: "challenge" };
        return { kind: "ok", status, contentType: res.headers.get("content-type") ?? "", body, finalUrl: url.toString() };
      }
    } catch (err) {
      if (controller.signal.aborted) {
        const why = (controller.signal.reason as Error | undefined)?.message;
        return { kind: "failed", reason: why === "timeout" ? "timeout" : "aborted" };
      }
      if (err instanceof UnsafeUrlError) return { kind: "failed", reason: "unsafe_url" };
      return { kind: "failed", reason: "network" };
    } finally {
      clearTimeout(timer);
      opts.signal?.removeEventListener("abort", onAbort);
    }
  }

  /** undefined when the fetch may go ahead; otherwise the result to return instead. */
  private async robotsVerdict(url: URL, aiInput: boolean): Promise<FetchResult | undefined> {
    if (url.pathname === "/robots.txt") return undefined;
    const state = await this.robotsFor(url.origin);
    if (state.kind === "allow_all") return undefined;
    if (state.kind === "unreachable") return { kind: "disallowed", reason: "robots_unreachable" };
    if (state.kind === "blocked") return { kind: "blocked", reason: `robots_${state.reason}` };
    const v = robotsAllows(state.groups, ROBOTS_TOKEN, url.pathname + url.search);
    if (!v.allowed) return { kind: "disallowed", reason: "robots" };
    if (aiInput && v.signals["ai-input"] === "no") return { kind: "disallowed", reason: "content_signal" };
    return undefined;
  }

  private robotsFor(origin: string): Promise<RobotsState> {
    const now = this.now();
    const hit = this.robots.get(origin);
    if (hit && hit.expires > now) return hit.state;
    if (this.robots.size >= ROBOTS_MAX_ORIGINS) {
      for (const [k, v] of this.robots) if (v.expires <= now) this.robots.delete(k);
      if (this.robots.size >= ROBOTS_MAX_ORIGINS) this.robots.delete(this.robots.keys().next().value!);
    }
    const state = this.loadRobots(origin);
    const entry = { expires: now + this.robotsTtlMs, state };
    this.robots.set(origin, entry);
    // A file that couldn't be read is asked for again sooner than one that could.
    void state.then((s) => { if (s.kind === "unreachable" || s.kind === "blocked") entry.expires = this.now() + ROBOTS_RETRY_MS; });
    return state;
  }

  private async loadRobots(origin: string): Promise<RobotsState> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error("timeout")), this.timeoutMs);
    try {
      let url = new URL("/robots.txt", origin);
      for (let hop = 0; hop <= 5; hop++) {
        const res = await this.fetchFn(url.toString(), {
          method: "GET", redirect: "manual", credentials: "omit", signal: controller.signal,
          headers: { "user-agent": this.userAgent, accept: "text/plain, */*;q=0.5" },
        });
        if (res.status >= 300 && res.status < 400) {
          discard(res);
          const next = res.headers.get("location") ? httpsUrl(new URL(res.headers.get("location")!, url)) : { reason: "no_location" };
          if (!(next instanceof URL)) return { kind: "allow_all" }; // a redirect to nowhere usable: treated as no file
          url = next;
          continue;
        }
        if (res.status === 429) { discard(res); return { kind: "blocked", reason: "http_429" }; }
        if (res.status >= 500) { discard(res); return { kind: "unreachable" }; }
        if (res.status >= 400) { discard(res); return { kind: "allow_all" }; }
        // Past the first 512 KiB nothing is read (RFC 9309 asks crawlers to parse at least 500 KiB).
        const body = await readCapped(res, ROBOTS_MAX_BYTES, true);
        if (body === "too_large") return { kind: "unreachable" }; // not reached with truncate
        if (looksLikeChallenge(res.headers, body)) return { kind: "blocked", reason: "challenge" };
        return { kind: "rules", groups: parseRobots(body.toString("utf8")) };
      }
      return { kind: "allow_all" }; // more than five redirects: RFC 9309 treats it as unavailable (4xx)
    } catch {
      return { kind: "unreachable" };
    } finally {
      clearTimeout(timer);
    }
  }
}
