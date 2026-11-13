// The page addresses one shopping run has been shown (find_offers listings, web_search results, pages web_fetch
// read and the links in them). check_offer_page reads only one of these: the model chooses the address, and the
// code fetches it (robots.txt included), so an address the model made up could carry the person's words out in
// its path or query. Addresses are compared by origin and path; a query is kept only when that same query was seen
// with that page, and is otherwise dropped before anything is fetched.

type Block = { type: string; [key: string]: unknown };

/** The most addresses one run keeps; links on fetched pages can be many. */
const MAX_PAGES = 5_000;
/** An http(s) address inside fetched text, up to the first space, quote or bracket. */
const LINK = /https?:\/\/[^\s"'<>()[\]{}\\^`|]+/giu;

function parse(raw: string): URL | undefined {
  let u: URL;
  try {
    u = new URL(raw.trim());
  } catch {
    return undefined;
  }
  if (u.protocol !== "https:" && u.protocol !== "http:") return undefined;
  if (u.username || u.password) return undefined;
  return u;
}

/** "https://shop.example/p/1" for https://Shop.Example/p/1/?x=1#y: origin and path, without a trailing slash. */
function keyOf(u: URL): string {
  return `${u.protocol}//${u.host}${u.pathname.replace(/\/+$/u, "") || "/"}`;
}

export class SeenPages {
  /** Origin and path -> the queries seen with it ("" for none). */
  private readonly pages = new Map<string, Set<string>>();

  get size() { return this.pages.size; }

  add(raw: unknown) {
    if (typeof raw !== "string" || this.pages.size >= MAX_PAGES) return;
    const u = parse(raw);
    if (!u) return;
    const key = keyOf(u);
    const queries = this.pages.get(key) ?? new Set<string>();
    queries.add(u.search);
    this.pages.set(key, queries);
  }

  /** Every address in one model message's server-tool results: search results, fetched pages and their links. */
  addFromResults(content: readonly Block[]) {
    for (const b of content) {
      if (b.type === "web_search_tool_result" && Array.isArray(b.content)) {
        for (const r of b.content as Block[]) if (r?.type === "web_search_result") this.add(r.url);
      } else if (b.type === "web_fetch_tool_result") {
        const r = b.content as Block | undefined;
        if (!r || Array.isArray(r) || r.type !== "web_fetch_result") continue;
        this.add(r.url);
        const source = (r.content as { source?: { type?: unknown; data?: unknown } } | undefined)?.source;
        if (source?.type === "text" && typeof source.data === "string") {
          for (const link of source.data.match(LINK) ?? []) this.add(link.replace(/[.,;:!?]+$/u, ""));
        }
      }
    }
  }

  /**
   * The address to fetch for one the model asked for, or undefined when its origin and path never appeared in this
   * run. A query that wasn't seen with that page is dropped; a fragment always is.
   */
  resolve(raw: string): string | undefined {
    const u = parse(raw);
    if (!u) return undefined;
    const queries = this.pages.get(keyOf(u));
    if (!queries) return undefined;
    u.hash = "";
    if (!queries.has(u.search)) u.search = "";
    return u.href;
  }
}
