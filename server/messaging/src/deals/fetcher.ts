// The polite fetcher (SHOPPING.md §1.2), one for leaflets and for shop pages: User-Agent DoddyBot, robots.txt
// checked for that agent and `*` before every request (a disallowed fetch is not made), HTTPS only, no
// cookies, no login, 10 s for the whole fetch with redirects, 3 MB cap. A 401/403/429, a challenge page or a
// captcha comes back as `blocked` and is never retried or worked around.
//
// The default transport is node:https with every resolved address checked at connect time (no private or
// local networks, as in news/safeFetch.ts), so an address from a page can't reach this server's own network.
// Tests inject a fake `fetch`. The robots files are cached (in memory, per origin, DoddyBot's rules only, bounded by
// count and by size, oldest out). Pages are cached only by
// `CachingFetcher` below, briefly and in memory, so one leaflet read serves the searches of the next hours.
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
  /** What the robots.txt cache may hold in all, by `robotsStateBytes`. Default ROBOTS_CACHE_MAX_BYTES. */
  robotsCacheBytes?: number;
  now?: () => number;
}

export const DEFAULT_TIMEOUT_MS = 10_000;
export const DEFAULT_MAX_BYTES = 3 * 1024 * 1024;
/** Response headers accepted per request. Node's default is 16 KiB; lidl.pl's leaflet list answered with
 * about 20.5 KiB of headers on 2026-10-28, so every Lidl read failed as "network" until this was raised. */
export const MAX_HEADER_BYTES = 64 * 1024;
const ROBOTS_MAX_BYTES = 512 * 1024;
const ROBOTS_RETRY_MS = 5 * 60_000;
const ROBOTS_MAX_ORIGINS = 256;
/** Rules kept from one robots.txt, DoddyBot's own (else `*`'s). A file with more for DoddyBot is read as
 * disallowing every fetch: past the cap a Disallow could be missed, and a disallowed fetch is never made. */
export const ROBOTS_MAX_RULES = 2000;
/** What the robots.txt cache may hold in all, by `robotsStateBytes`; past it the oldest files go first. Real
 * files are a few KB, so 256 origins stay far below. */
export const ROBOTS_CACHE_MAX_BYTES = 8 * 1024 * 1024;
/** The Content-Signal keys kept (Cloudflare's three); the fetcher reads `ai-input`. */
const CONTENT_SIGNALS = new Set(["search", "ai-input", "ai-train"]);

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

/** Longer patterns, or ones with more `*`, are ignored: they match nothing. Real files stay far below. */
const ROBOTS_PATTERN_MAX_CHARS = 512;
const ROBOTS_PATTERN_MAX_STARS = 16;
const usablePattern = (body: string, pieces: string[]) => body.length <= ROBOTS_PATTERN_MAX_CHARS && pieces.length - 1 <= ROBOTS_PATTERN_MAX_STARS;

/** False for a pattern `robotsPatternMatches` ignores, so a rule with it can be left out. */
function canMatch(pattern: string): boolean {
  const p = normalisePattern(pattern);
  const body = p.endsWith("$") ? p.slice(0, -1) : p;
  return usablePattern(body, body.split("*"));
}

/**
 * True when `pattern` (with `*` and a trailing `$`) matches the start of `path`. Plain string search,
 * never a RegExp: a pattern like `/*a*a*a*a*a*a*X` used to backtrack for seconds and stall the server.
 * Taking the leftmost match of each piece between stars is enough, so this never backtracks.
 */
export function robotsPatternMatches(pattern: string, path: string): boolean {
  const p = normalisePattern(pattern);
  const anchored = p.endsWith("$");
  const body = anchored ? p.slice(0, -1) : p;
  const pieces = body.split("*");
  if (!usablePattern(body, pieces)) return false;
  const first = pieces[0]!;
  if (!path.startsWith(first)) return false;
  if (pieces.length === 1) return !anchored || path.length === first.length;
  let at = first.length;
  for (let i = 1; i < pieces.length - 1; i++) {
    const found = path.indexOf(pieces[i]!, at);
    if (found < 0) return false;
    at = found + pieces[i]!.length;
  }
  const last = pieces[pieces.length - 1]!;
  if (anchored) return path.length - last.length >= at && path.endsWith(last);
  return path.indexOf(last, at) >= 0;
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

/** A fresh copy of a string: a slice of the file's text would keep the whole file in memory. */
const own = (s: string) => Buffer.from(s, "utf8").toString("utf8");

/**
 * The part of a parsed robots.txt that applies to `token`, as small as it can be: other agents' groups, rules that can
 * never match and unknown Content-Signal keys are left out, and what is kept is copied out of the file's text.
 * `robotsAllows(kept, token, …)` answers as `robotsAllows(groups, token, …)` does, for the signals it keeps.
 * Undefined when more than ROBOTS_MAX_RULES rules apply.
 */
export function robotsRulesFor(groups: RobotsGroup[], token: string): RobotsGroup[] | undefined {
  const kept: RobotsGroup[] = [];
  let count = 0;
  for (const g of groupsFor(groups, token)) {
    const rules = g.rules.filter((r) => canMatch(r.pattern));
    count += rules.length;
    if (count > ROBOTS_MAX_RULES) return undefined;
    kept.push({
      agents: [...new Set(g.agents.filter((a) => a === "*" || a === token || a.split("/")[0] === token).map((a) => a.split("/")[0] === token ? token : "*"))],
      rules: rules.map((r) => ({ allow: r.allow, pattern: own(r.pattern) })),
      signals: Object.fromEntries(Object.entries(g.signals).filter(([k]) => CONTENT_SIGNALS.has(k)).map(([k, v]) => [own(k), own(v.slice(0, 32))])),
    });
  }
  return kept;
}

type RobotsState =
  | { kind: "rules"; groups: RobotsGroup[] }
  | { kind: "allow_all" } // 4xx: no robots file
  | { kind: "unreachable" } // 5xx, network, timeout: assume everything is disallowed (RFC 9309)
  | { kind: "blocked"; reason: string } // 401/403-with-challenge or 429 on robots.txt itself
  | { kind: "too_large" }; // more than ROBOTS_MAX_RULES rules for DoddyBot: everything is disallowed

/** About what a cached robots.txt keeps on the heap: two bytes a character, and a little for each object. */
export function robotsStateBytes(state: { kind: string; groups?: RobotsGroup[] }): number {
  let n = 64;
  for (const g of state.groups ?? []) {
    n += 96;
    for (const a of g.agents) n += 32 + 2 * a.length;
    for (const r of g.rules) n += 48 + 2 * r.pattern.length;
    for (const [k, v] of Object.entries(g.signals)) n += 64 + 2 * (k.length + v.length);
  }
  return n;
}

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
  const req = https.request(u, { method: "GET", headers, lookup: safeLookup, maxHeaderSize: MAX_HEADER_BYTES, signal: init.signal ?? undefined }, (res) => {
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

const BLOCKED_TITLE_WORDS = /captcha|access denied|dost[eę]p zablokowany/i;

/** A title naming a captcha or a block: what `/<title>[^<]*(captcha|access denied|dost[eę]p zablokowany)[^<]*<\/title>/i`
 * finds, in linear time (each title's text is read once, up to the next "<"). */
export function hasBlockedTitle(html: string): boolean {
  const open = /<title>/gi;
  for (let m = open.exec(html); m; m = open.exec(html)) {
    const textEnd = html.indexOf("<", open.lastIndex);
    if (textEnd < 0) return false;
    if (/^<\/title>/i.test(html.slice(textEnd, textEnd + 8)) && BLOCKED_TITLE_WORDS.test(html.slice(open.lastIndex, textEnd))) return true;
    open.lastIndex = textEnd;
  }
  return false;
}

const CHALLENGE_MARKERS: { test(html: string): boolean }[] = [
  /<title>\s*just a moment\.\.\.\s*<\/title>/i, // Cloudflare interstitial
  /_cf_chl_opt|cf-chl-bypass|cf_chl_prog/i,
  /<title>\s*attention required!?\s*\|\s*cloudflare/i,
  /px-captcha|captcha-delivery\.com|\/_incapsula_resource/i,
  { test: hasBlockedTitle },
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
  private readonly robotsCacheBytes: number;
  private readonly now: () => number;
  /** Oldest first (an origin read again goes to the end); `bytes` is counted once its file is read. */
  private readonly robots = new Map<string, { expires: number; state: Promise<RobotsState>; bytes: number }>();
  private robotsBytes = 0;

  constructor(opts: FetcherOptions = {}) {
    this.fetchFn = opts.fetch ?? safeHttpsFetch;
    this.userAgent = opts.userAgent ?? DODDY_BOT_UA;
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.maxBytes = opts.maxBytes ?? DEFAULT_MAX_BYTES;
    this.maxRedirects = opts.maxRedirects ?? 3;
    this.robotsTtlMs = opts.robotsTtlMs ?? 3600_000;
    this.robotsCacheBytes = opts.robotsCacheBytes ?? ROBOTS_CACHE_MAX_BYTES;
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
    if (state.kind === "too_large") return { kind: "disallowed", reason: "robots_too_large" };
    const v = robotsAllows(state.groups, ROBOTS_TOKEN, url.pathname + url.search);
    if (!v.allowed) return { kind: "disallowed", reason: "robots" };
    if (aiInput && v.signals["ai-input"] === "no") return { kind: "disallowed", reason: "content_signal" };
    return undefined;
  }

  /** How many robots.txt files are cached and their size by `robotsStateBytes` (for tests and logs). */
  robotsCacheStats(): { origins: number; bytes: number } {
    return { origins: this.robots.size, bytes: this.robotsBytes };
  }

  private robotsFor(origin: string): Promise<RobotsState> {
    const now = this.now();
    const hit = this.robots.get(origin);
    if (hit && hit.expires > now) return hit.state;
    if (hit) this.dropRobots(origin);
    if (this.robots.size >= ROBOTS_MAX_ORIGINS) {
      for (const [k, v] of this.robots) if (v.expires <= now) this.dropRobots(k);
      if (this.robots.size >= ROBOTS_MAX_ORIGINS) this.dropRobots(this.robots.keys().next().value!);
    }
    const state = this.loadRobots(origin);
    const entry = { expires: now + this.robotsTtlMs, state, bytes: 0 };
    this.robots.set(origin, entry);
    void state.then((s) => {
      // A file that couldn't be read is asked for again sooner than one that could.
      if (s.kind === "unreachable" || s.kind === "blocked") entry.expires = this.now() + ROBOTS_RETRY_MS;
      if (this.robots.get(origin) !== entry) return; // dropped while it was read
      entry.bytes = robotsStateBytes(s);
      this.robotsBytes += entry.bytes;
      // Past the budget the oldest files go first; the one just read stays, and so do files still being read (they
      // count nothing yet).
      for (const [k, v] of this.robots) {
        if (this.robotsBytes <= this.robotsCacheBytes) break;
        if (v !== entry && v.bytes > 0) this.dropRobots(k);
      }
    });
    return state;
  }

  private dropRobots(origin: string): void {
    const entry = this.robots.get(origin);
    if (!entry) return;
    this.robotsBytes -= entry.bytes;
    this.robots.delete(origin);
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
        // Only DoddyBot's part is kept, and only up to ROBOTS_MAX_RULES rules (see robotsRulesFor).
        const groups = robotsRulesFor(parseRobots(body.toString("utf8")), ROBOTS_TOKEN);
        return groups ? { kind: "rules", groups } : { kind: "too_large" };
      }
      return { kind: "allow_all" }; // more than five redirects: RFC 9309 treats it as unavailable (4xx)
    } catch {
      return { kind: "unreachable" };
    } finally {
      clearTimeout(timer);
    }
  }
}

/**
 * A short-lived page cache in front of a fetcher (11 Nov 2026). On the live server (free plan, one small instance)
 * each search read every chain's site again: 6 to 9 of 10 chains failed with `timeout` per search (log of 11 Nov,
 * 08:13 and 08:26 UTC), Biedronka alone fetching about 97 page images inside the 25 s budget. A leaflet changes once a
 * week, so a page read once now serves the next searches for `ttlMs`. Only successful answers are kept, in memory,
 * for everyone alike (nothing in it is linked to a person), within `maxBytes`, oldest first out. Two searches asking
 * for the same page at once share one fetch.
 */
export class CachingFetcher implements PageFetcher {
  private readonly entries = new Map<string, { expires: number; result: Extract<FetchResult, { kind: "ok" }> }>();
  private readonly inFlight = new Map<string, Promise<FetchResult>>();
  private bytes = 0;

  constructor(
    /** The fetcher underneath; the same polite fetcher (one robots.txt cache, one user agent) as everything else. */
    readonly inner: PageFetcher,
    private readonly ttlMs = 3 * 3600_000,
    private readonly maxBytes = 48 * 1024 * 1024,
    private readonly now: () => number = Date.now,
  ) {}

  async fetchPage(url: string, opts: FetchPageOptions = {}): Promise<FetchResult> {
    // The same address asked for with different rules (accept, AI input) is a different request.
    const key = `${opts.aiInput === true ? "ai" : "-"} ${opts.accept ?? "*/*"} ${url}`;
    const hit = this.entries.get(key);
    if (hit && hit.expires > this.now()) {
      // Most recently used last, so the oldest goes first when the cache is full.
      this.entries.delete(key);
      this.entries.set(key, hit);
      return hit.result;
    }
    if (hit) this.drop(key);
    const pending = this.inFlight.get(key);
    if (pending) return pending;
    // A shared fetch is not stopped by one caller's deadline; each caller still stops waiting at its own.
    const { signal, ...shared } = opts;
    const started = this.inner.fetchPage(url, shared).then((result) => {
      if (result.kind === "ok" && result.body.length <= this.maxBytes / 8) this.keep(key, result);
      return result;
    }).finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, started);
    if (!signal) return started;
    return new Promise<FetchResult>((resolve) => {
      const onAbort = () => resolve({ kind: "failed", reason: "timeout" });
      if (signal.aborted) return onAbort();
      signal.addEventListener("abort", onAbort, { once: true });
      started.then((r) => { signal.removeEventListener("abort", onAbort); resolve(r); });
    });
  }

  private keep(key: string, result: Extract<FetchResult, { kind: "ok" }>): void {
    this.drop(key);
    this.entries.set(key, { expires: this.now() + this.ttlMs, result });
    this.bytes += result.body.length;
    for (const [oldest] of this.entries) {
      if (this.bytes <= this.maxBytes) break;
      this.drop(oldest);
    }
  }

  private drop(key: string): void {
    const entry = this.entries.get(key);
    if (!entry) return;
    this.bytes -= entry.result.body.length;
    this.entries.delete(key);
  }
}
