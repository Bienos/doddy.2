/**
 * Wykop API v3: read-only source adapter for Polish social discovery.
 *
 * Server-side only. A registered application's bearer token is injected by a future
 * credential provider; NO user's Wykop account, secrets, or login cookies are read.
 * This is intentionally not connected to an HTTP or voice route until Wykop grants
 * application credentials and the live response shapes/rate limits are verified.
 *
 * Reference: https://dev.wykop.pl/ and https://doc.wykop.pl/.
 */
export const WYKOP_ORIGIN = "https://wykop.pl";
const API = `${WYKOP_ORIGIN}/api/v3`;
const REQUEST_TIMEOUT_MS = 8_000;
const MAX_RESPONSE_BYTES = 256 * 1024;
const MAX_RESULTS = 10;

export type WykopKind = "hot" | "tags" | "search";
export interface WykopItem {
  id: string;
  kind: "entry" | "tag";
  text: string;
  url: string;
  /** Wykop's published timestamp if provided; no date is fabricated. */
  publishedAt: string | null;
  /** One user's comment is not an independently verified fact. */
  attribution: "Wykop community post" | "Wykop hashtag";
}
export interface WykopReadResult {
  source: "Wykop";
  kind: WykopKind;
  fetchedAt: string;
  items: WykopItem[];
}
export type WykopFetch = (url: URL, init: RequestInit) => Promise<Response>;
export type WykopToken = () => Promise<string | null>;

export class WykopUnavailable extends Error {
  constructor(readonly reason: "not_configured" | "unauthorized" | "rate_limited" | "upstream_failure" | "invalid_response") {
    super(reason);
    this.name = "WykopUnavailable";
  }
}

const record = (data: unknown): Record<string, unknown> | null =>
  data !== null && typeof data === "object" && !Array.isArray(data) ? data as Record<string, unknown> : null;

const string = (data: unknown, max = 500): string | null =>
  typeof data === "string" && data.length > 0 ? data.slice(0, max) : null;

function textOnly(input: unknown): string {
  const source = string(input, 2_000) ?? "";
  // Treat Wykop HTML and user-generated instructions as untrusted data; never render
  // active markup into the app or feed it into an instruction channel.
  return source.replace(/<[^>]*>/g, " ").replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<").replace(/&gt;/gi, ">")
    .replace(/\s+/g, " ").trim().slice(0, 550);
}
function rows(payload: unknown): unknown[] {
  const root = record(payload);
  if (!root) throw new WykopUnavailable("invalid_response");
  const data = root.data;
  if (Array.isArray(data)) return data;
  const inside = record(data);
  if (inside && Array.isArray(inside.items)) return inside.items;
  throw new WykopUnavailable("invalid_response");
}
function normalizePost(item: unknown): WykopItem | null {
  const row = record(item);
  if (!row || typeof row.id !== "number" || !Number.isSafeInteger(row.id) || row.id <= 0) return null;
  const content = textOnly(row.content);
  if (!content || row.adult === true) return null;
  return {
    id: String(row.id),
    kind: "entry",
    text: content,
    url: `${WYKOP_ORIGIN}/wpis/${row.id}`,
    publishedAt: string(row.created_at, 80) ?? null,
    attribution: "Wykop community post",
  };
}
function normalizeTag(item: unknown): WykopItem | null {
  const tag = record(item);
  const name = string(tag?.name, 90);
  if (!name || !/^[\p{L}\p{N}_-]{1,80}$/u.test(name)) return null;
  return {
    id: name,
    kind: "tag",
    text: `#${name}`,
    url: `${WYKOP_ORIGIN}/tag/${encodeURIComponent(name)}`,
    publishedAt: null,
    attribution: "Wykop hashtag",
  };
}
export function normalizeWykop(kind: WykopKind, payload: unknown, at: Date): WykopReadResult {
  const decode = kind === "tags" ? normalizeTag : normalizePost;
  const unique = new Map<string, WykopItem>();
  for (const raw of rows(payload)) {
    const item = decode(raw);
    if (item && !unique.has(item.id)) unique.set(item.id, item);
    if (unique.size === MAX_RESULTS) break;
  }
  return { source: "Wykop", kind, fetchedAt: at.toISOString(), items: [...unique.values()] };
}
export function wykopReadURL(kind: WykopKind, search?: string): URL {
  const urls = {
    hot: `${API}/entries`,
    tags: `${API}/tags/popular`,
    search: `${API}/search/entries`,
  } as const;
  const url = new URL(urls[kind]);
  if (kind === "hot") {
    url.searchParams.set("sort", "hot");
    url.searchParams.set("last_update", "12");
    url.searchParams.set("limit", String(MAX_RESULTS));
  } else if (kind === "search") {
    const q = search?.trim() ?? "";
    if (q.length < 2 || q.length > 120 || /[\x00-\x1f\x7f]/.test(q)) {
      throw new WykopUnavailable("invalid_response");
    }
    url.searchParams.set("query", q);
    url.searchParams.set("limit", String(MAX_RESULTS));
  }
  return url;
}

export class WykopReadOnly {
  constructor(
    private readonly getToken: WykopToken,
    private readonly fetcher: WykopFetch = (url, init) => fetch(url, init),
    private readonly clock: () => Date = () => new Date(),
  ) {}

  async read(kind: WykopKind, query?: string): Promise<WykopReadResult> {
    // Validate and pin the exact API URL BEFORE consulting credentials.
    const url = wykopReadURL(kind, query);
    const bearer = await this.getToken();
    if (!bearer || !/^[A-Za-z0-9_.-]{16,4096}$/.test(bearer)) {
      throw new WykopUnavailable("not_configured");
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await this.fetcher(url, {
        method: "GET",
        headers: { authorization: `Bearer ${bearer}`, accept: "application/json" },
        signal: controller.signal,
        redirect: "error",
      });
      if (response.status === 401 || response.status === 403) throw new WykopUnavailable("unauthorized");
      if (response.status === 429) throw new WykopUnavailable("rate_limited");
      if (!response.ok) throw new WykopUnavailable("upstream_failure");
      const declared = response.headers.get("content-length");
      if (declared !== null && Number(declared) > MAX_RESPONSE_BYTES) {
        throw new WykopUnavailable("invalid_response");
      }
      // Bounded stream read, not unbounded response.json().
      if (!response.body) throw new WykopUnavailable("invalid_response");
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        while (true) {
          const part = await reader.read();
          if (part.done) break;
          size += part.value.byteLength;
          if (size > MAX_RESPONSE_BYTES) throw new WykopUnavailable("invalid_response");
          chunks.push(part.value);
        }
      } finally {
        reader.releaseLock();
      }
      const bytes = new Uint8Array(size);
      let at = 0;
      for (const part of chunks) { bytes.set(part, at); at += part.length; }
      let json: unknown;
      try { json = JSON.parse(new TextDecoder().decode(bytes)); }
      catch { throw new WykopUnavailable("invalid_response"); }
      return normalizeWykop(kind, json, this.clock());
    } catch (error) {
      if (error instanceof WykopUnavailable) throw error;
      throw new WykopUnavailable("upstream_failure");
    } finally {
      clearTimeout(timeout);
    }
  }
}
