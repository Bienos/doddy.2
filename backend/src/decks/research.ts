import { z } from "zod";
import { ProviderError } from "../errors.js";
import { decodeEntities, type WebSearchProvider } from "../tools/websearch.js";
import { DECK_LANGUAGES, type DeckLanguage } from "./spec.js";

/**
 * Research for a deck (decision 2026-11-10-better-presentations), before Claude writes a word:
 *  - Wikipedia: the article text for one or two phrases, in the deck's language (free, no key; the
 *    voice agent already reads Wikipedia the same way). The host is built here from a fixed list of
 *    languages, never taken from the model.
 *  - Wikimedia Commons: the article's lead picture, only when Commons states a free licence Doddy can
 *    honour (CC0, public domain, CC BY, CC BY-SA), with an author, and no restriction. The picture's
 *    author and licence go on the slide and on the sources slide.
 *  - Web search through Monid, the server's existing search (Doddy pays per search): short snippets for
 *    what Wikipedia lacks, only when the user's web search switch is on and the daily cap allows.
 *  - The material the voice agent passed (often its own web search results).
 * All of it is untrusted data: Claude is told so, and nothing in it becomes a link, a tool or an
 * instruction. Links on the sources slide are the addresses found here, never ones Claude wrote.
 */

export interface ResearchSource {
  /** m1 for the user's material, s1… for research. */
  id: string;
  kind: "material" | "wikipedia" | "web";
  title: string;
  url: string | null;
  site: string | null;
  text: string;
}

export interface DeckImage {
  /** i1… */
  id: string;
  mime: "image/jpeg" | "image/png";
  bytes: Buffer;
  width: number;
  height: number;
  /** What it shows, from its file name ("Ratusz w Iławie"). */
  title: string;
  author: string;
  license: string;
  licenseUrl: string | null;
  /** The file's page on Commons. */
  pageUrl: string;
}

export interface ResearchPack {
  language: DeckLanguage;
  sources: ResearchSource[];
  images: DeckImage[];
}

export const ResearchPlan = z.object({
  language: z.enum(DECK_LANGUAGES),
  wikipedia: z.array(z.string().trim().min(1).max(100)).max(4).transform((a) => a.slice(0, 2)),
  web: z.array(z.string().trim().min(1).max(150)).max(4).transform((a) => a.slice(0, 2)),
});
export type ResearchPlan = z.infer<typeof ResearchPlan>;

export const RESEARCH_PLAN_SCHEMA: Record<string, unknown> = {
  type: "object",
  properties: {
    language: { type: "string", enum: [...DECK_LANGUAGES] },
    wikipedia: { type: "array", items: { type: "string" } },
    web: { type: "array", items: { type: "string" } },
  },
  required: ["language", "wikipedia", "web"],
  additionalProperties: false,
};

export const ARTICLE_CHARS = 9_000;
export const MATERIAL_CHARS = 6_000;
const SNIPPET_CHARS = 400;
const MAX_WEB_SOURCES_PER_QUERY = 4;
const MAX_IMAGE_BYTES = 6 * 1024 * 1024;
const MIN_IMAGE_WIDTH = 480;
/** One Wikimedia request. Research as a whole is bounded by the job's own deadline. */
export const WIKIMEDIA_TIMEOUT_MS = 12_000;
/** Wikimedia asks for a User-Agent that names the client (meta.wikimedia.org/wiki/User-Agent_policy). Nothing about the user. */
export const WIKIMEDIA_USER_AGENT = "DoddyDeckResearch/1.0 (https://doddy.lol)";

export interface WikiArticle {
  title: string;
  url: string;
  site: string;
  text: string;
  /** The lead picture's file name, if the article has one. */
  imageFile: string | null;
}

/** Wikipedia and Commons. Live: `WikimediaClient`; mock mode and tests: their own. */
export interface Wikimedia {
  readonly mode: "mock" | "live";
  article(language: DeckLanguage, phrase: string, signal: AbortSignal): Promise<WikiArticle | null>;
  image(fileName: string, signal: AbortSignal): Promise<Omit<DeckImage, "id"> | null>;
}

// ------------------------------------------------------------------ gathering

export interface ResearchDeps {
  wikimedia: Wikimedia;
  webSearch: WebSearchProvider | null;
  /** Reserves one paid web search for this user (switch on, cap not reached), or says no. */
  allowWebSearch: () => Promise<boolean>;
  log?: (line: Record<string, unknown>) => void;
}

export async function gatherResearch(plan: ResearchPlan, material: string | undefined, deps: ResearchDeps, signal: AbortSignal): Promise<ResearchPack> {
  const log = deps.log ?? (() => {});
  const [articles, web] = await Promise.all([wikipedia(plan, deps, signal), webResults(plan, deps, signal)]);

  const sources: ResearchSource[] = [];
  if (material?.trim()) {
    sources.push({ id: "m1", kind: "material", title: "material", url: null, site: null, text: dataText(material, MATERIAL_CHARS) });
  }
  let n = 0;
  const urls = new Set<string>();
  for (const a of articles) {
    if (urls.has(a.url)) continue;
    urls.add(a.url);
    sources.push({ id: `s${++n}`, kind: "wikipedia", title: `${a.title} — Wikipedia`, url: a.url, site: a.site, text: a.text });
  }
  for (const r of web) {
    if (urls.has(r.url) || n >= 14) continue;
    urls.add(r.url);
    sources.push({ id: `s${++n}`, kind: "web", title: r.title, url: r.url, site: r.site, text: r.text });
  }

  const images: DeckImage[] = [];
  const files = [...new Set(articles.map((a) => a.imageFile).filter((f): f is string => !!f))].slice(0, 3);
  const found = await Promise.all(files.map((f) => deps.wikimedia.image(f, signal).catch(() => null)));
  for (const image of found) if (image) images.push({ ...image, id: `i${images.length + 1}` });

  log({ level: "info", event: "deck_research", wikipedia: articles.length, web: web.length, images: images.length, material: !!material });
  return { language: plan.language, sources, images };
}

async function wikipedia(plan: ResearchPlan, deps: ResearchDeps, signal: AbortSignal): Promise<WikiArticle[]> {
  const look = (language: DeckLanguage, phrase: string) => deps.wikimedia.article(language, phrase, signal).catch(() => null);
  const found = (await Promise.all(plan.wikipedia.map((p) => look(plan.language, p)))).filter((a): a is WikiArticle => a !== null);
  // Nothing in the deck's language: English has more articles. Claude writes the deck in the deck's language either way.
  if (found.length === 0 && plan.language !== "en" && plan.wikipedia.length > 0) {
    const english = await look("en", plan.wikipedia[0]!);
    if (english) found.push(english);
  }
  return found;
}

async function webResults(plan: ResearchPlan, deps: ResearchDeps, signal: AbortSignal): Promise<{ title: string; url: string; site: string; text: string }[]> {
  const provider = deps.webSearch;
  if (!provider || !provider.isConfigured() || plan.web.length === 0) return [];
  const out: { title: string; url: string; site: string; text: string }[] = [];
  for (const query of plan.web) {
    if (!(await deps.allowWebSearch().catch(() => false))) break;
    let output: unknown;
    try {
      output = (await provider.search({ query, signal: AbortSignal.any([signal, AbortSignal.timeout(15_000)]) })).output;
    } catch {
      continue;
    }
    out.push(...webSources(output).slice(0, MAX_WEB_SOURCES_PER_QUERY));
  }
  return out;
}

/** Monid's `{ results: [{ title, link, snippet }] }`, kept only with an https or http link. Wikipedia results are left out (read in full above). */
export function webSources(output: unknown): { title: string; url: string; site: string; text: string }[] {
  const results = (output as { results?: unknown } | null)?.results;
  if (!Array.isArray(results)) return [];
  return results.flatMap((item: unknown) => {
    if (typeof item !== "object" || item === null) return [];
    const r = item as Record<string, unknown>;
    const url = httpUrl(r.link);
    const title = typeof r.title === "string" ? dataText(String(decodeEntities(r.title)), 140) : "";
    const snippet = typeof r.snippet === "string" ? dataText(String(decodeEntities(r.snippet)), SNIPPET_CHARS) : "";
    if (!url || !title || !snippet) return [];
    const site = new URL(url).hostname.replace(/^www\./, "");
    if (/(^|\.)wikipedia\.org$/.test(site)) return [];
    return [{ title, url, site, text: snippet }];
  });
}

// ------------------------------------------------------------------ Wikimedia (live)

const WIKI_HOST = (language: DeckLanguage) => `${language}.wikipedia.org`;
const COMMONS = "https://commons.wikimedia.org/w/api.php";
/** Where Commons serves its thumbnails (thumb.wikimedia.org seen in a live answer on 10 Nov 2026). A picture from anywhere else isn't downloaded. */
export const PICTURE_HOSTS: ReadonlySet<string> = new Set(["upload.wikimedia.org", "thumb.wikimedia.org"]);

/** Licences whose terms a slide can meet with an attribution line. Anything else (GFDL only, fair use, unknown) is left out. */
export function freeLicence(shortName: string): boolean {
  const s = shortName.trim().toLowerCase().replace(/\s+/g, " ");
  return /^(cc0( 1\.0)?|public domain|pd|cc[ -]by(-sa)?[ -]\d(\.\d)?( [a-z-]{2,10})?)$/.test(s);
}

export class WikimediaClient implements Wikimedia {
  readonly mode = "live" as const;

  /**
   * @param retryDelayMs Wikimedia limits requests per address (seen as 429 from shared addresses, 10 Nov 2026): one
   *   429 waits this long (or the Retry-After it gives, up to 3 s) and tries once more; a second 429 is "rate_limited",
   *   and research goes on without that source.
   */
  constructor(
    private readonly fetchImpl: typeof fetch = (input, init) => fetch(input, init),
    private readonly retryDelayMs = 1_500,
  ) {}

  async article(language: DeckLanguage, phrase: string, signal: AbortSignal): Promise<WikiArticle | null> {
    if (!(DECK_LANGUAGES as readonly string[]).includes(language)) return null;
    const host = WIKI_HOST(language);
    const params = new URLSearchParams({
      action: "query", format: "json", formatversion: "2", utf8: "1", redirects: "1",
      generator: "search", gsrsearch: phrase, gsrlimit: "1", gsrnamespace: "0",
      prop: "extracts|pageimages|info", explaintext: "1", exsectionformat: "wiki", piprop: "name", inprop: "url",
    });
    const body = await this.json(`https://${host}/w/api.php?${params}`, signal);
    const page = (body as { query?: { pages?: unknown[] } } | null)?.query?.pages?.[0] as Record<string, unknown> | undefined;
    if (!page || typeof page.title !== "string" || typeof page.extract !== "string") return null;
    const text = articleText(page.extract);
    if (text.length < 200) return null;
    const url = httpUrl(page.fullurl);
    const sameSite = url && new URL(url).hostname === host ? url : `https://${host}/wiki/${encodeURIComponent(page.title.replace(/ /g, "_"))}`;
    const imageFile = typeof page.pageimage === "string" && page.pageimage.length < 240 ? page.pageimage : null;
    return { title: dataText(page.title, 120), url: sameSite, site: host, text, imageFile };
  }

  async image(fileName: string, signal: AbortSignal): Promise<Omit<DeckImage, "id"> | null> {
    const params = new URLSearchParams({
      action: "query", format: "json", formatversion: "2", titles: `File:${fileName}`,
      prop: "imageinfo", iiprop: "url|mime|size|extmetadata", iiurlwidth: "1600",
      iiextmetadatafilter: "LicenseShortName|LicenseUrl|Artist|AttributionRequired|NonFree|Restrictions|ObjectName",
    });
    const body = await this.json(`${COMMONS}?${params}`, signal);
    const page = (body as { query?: { pages?: unknown[] } } | null)?.query?.pages?.[0] as Record<string, unknown> | undefined;
    // Not on Commons (a local, often non-free, file): no picture.
    if (!page || page.missing === true) return null;
    const info = (page.imageinfo as Record<string, unknown>[] | undefined)?.[0];
    if (!info) return null;
    const meta = (info.extmetadata ?? {}) as Record<string, { value?: unknown } | undefined>;
    const value = (key: string) => (typeof meta[key]?.value === "string" ? (meta[key]!.value as string) : "");
    const license = plainText(value("LicenseShortName"), 40);
    if (!license || !freeLicence(license) || value("NonFree") || plainText(value("Restrictions"), 200)) return null;
    const attribution = !/^(cc0|public domain|pd)/i.test(license);
    const author = plainText(value("Artist"), 80) || (attribution ? "" : "Wikimedia Commons");
    if (!author) return null;
    const thumb = httpUrl(info.thumburl);
    const pageUrl = httpUrl(info.descriptionurl);
    if (!thumb || !PICTURE_HOSTS.has(new URL(thumb).hostname) || !pageUrl || new URL(pageUrl).hostname !== "commons.wikimedia.org") return null;
    const bytes = await this.bytes(thumb, signal);
    const kind = imageKind(bytes);
    if (!kind || kind.width < MIN_IMAGE_WIDTH) return null;
    const title = plainText(value("ObjectName"), 100) || fileTitle(fileName);
    return { mime: kind.mime, bytes, width: kind.width, height: kind.height, title, author, license, licenseUrl: httpUrl(value("LicenseUrl")), pageUrl };
  }

  private async get(url: string, signal: AbortSignal, retried = false): Promise<Response> {
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        headers: { "user-agent": WIKIMEDIA_USER_AGENT, accept: "application/json, image/*" },
        signal: AbortSignal.any([signal, AbortSignal.timeout(WIKIMEDIA_TIMEOUT_MS)]),
        redirect: "error",
      });
    } catch (error) {
      throw new ProviderError(error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError") ? "provider_timeout" : "provider_unavailable");
    }
    if (response.status === 429) {
      if (retried) throw new ProviderError("rate_limited");
      const after = Number(response.headers.get("retry-after"));
      const wait = Number.isFinite(after) && after > 0 ? Math.min(after * 1000, 3_000) : this.retryDelayMs;
      await new Promise((resolve) => setTimeout(resolve, wait));
      return this.get(url, signal, true);
    }
    if (!response.ok) throw new ProviderError("provider_unavailable");
    return response;
  }

  private async json(url: string, signal: AbortSignal): Promise<unknown> {
    const response = await this.get(url, signal);
    return response.json().catch(() => null);
  }

  private async bytes(url: string, signal: AbortSignal): Promise<Buffer> {
    const response = await this.get(url, signal);
    const length = Number(response.headers.get("content-length"));
    if (Number.isFinite(length) && length > MAX_IMAGE_BYTES) throw new ProviderError("malformed_provider_result");
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) throw new ProviderError("malformed_provider_result");
    return bytes;
  }
}

// ------------------------------------------------------------------ text helpers

/** Untrusted text made safe to place between tags: no angle brackets, one-space runs, clipped at a word. */
export function dataText(text: string, max: number): string {
  const flat = text.replace(/[<>]/g, " ").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, " ").replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim();
  if (flat.length <= max) return flat;
  const cut = flat.slice(0, max);
  const at = Math.max(cut.lastIndexOf("\n"), cut.lastIndexOf(". "));
  return (at > max * 0.6 ? cut.slice(0, at + 1) : cut).trimEnd();
}

/** Reference sections say nothing a slide can use; they are dropped. */
const DROP_SECTIONS = new RegExp(
  "^(przypisy|bibliografia|linki zewnętrzne|zobacz też|uwagi|references|notes|external links|see also|further reading|bibliography|" +
    "einzelnachweise|weblinks|literatur|siehe auch|anmerkungen|références|notes et références|liens externes|voir aussi|bibliographie|" +
    "referencias|enlaces externos|véase también|bibliografía|note|collegamenti esterni|voci correlate|referências|ligações externas|" +
    "bronnen|externe links|zie ook|källor|externa länkar|se även|reference|externí odkazy|odkazy|související články)$",
  "i",
);

/** Wikipedia's plain extract with `== Heading ==` lines: headings become "## Heading", reference sections go, then it's clipped. */
export function articleText(extract: string): string {
  const out: string[] = [];
  let skipping = false;
  for (const raw of extract.split("\n")) {
    const heading = /^(=+)\s*(.*?)\s*\1\s*$/.exec(raw.trim());
    if (heading) {
      const level = heading[1]!.length;
      if (level <= 2) skipping = DROP_SECTIONS.test(heading[2]!);
      if (!skipping) out.push(`\n## ${heading[2]}`);
      continue;
    }
    if (!skipping && raw.trim()) out.push(raw.trim());
  }
  // Headings with nothing under them go too.
  const lines = out.filter((l, i) => !(l.startsWith("\n## ") && (i + 1 >= out.length || out[i + 1]!.startsWith("\n## "))));
  return dataText(lines.join("\n"), ARTICLE_CHARS);
}

/** Commons' HTML fields ("<a href=…>Foo</a>") as plain words. */
export function plainText(html: string, max: number): string {
  const text = String(decodeEntities(html.replace(/<[^>]*>/g, " "))).replace(/\s+/g, " ").trim();
  return text.length <= max ? text : `${text.slice(0, max - 1).trimEnd()}…`;
}

function fileTitle(fileName: string): string {
  return plainText(fileName.replace(/\.[a-z0-9]+$/i, "").replace(/_/g, " "), 100);
}

function httpUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2048) return null;
  try {
    const url = new URL(value.startsWith("//") ? `https:${value}` : value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
  } catch {
    return null;
  }
}

/** JPEG or PNG, by its bytes, and its pixel size from the header. Anything else: null. */
export function imageKind(bytes: Buffer): { mime: "image/jpeg" | "image/png"; width: number; height: number } | null {
  if (bytes.length > 24 && bytes.readUInt32BE(0) === 0x89504e47 && bytes.readUInt32BE(4) === 0x0d0a1a0a) {
    return { mime: "image/png", width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    let at = 2;
    while (at + 9 < bytes.length) {
      if (bytes[at] !== 0xff) return null;
      const marker = bytes[at + 1]!;
      if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) {
        at += 2;
        continue;
      }
      const length = bytes.readUInt16BE(at + 2);
      // SOF0–SOF15, except DHT (C4), JPG (C8) and DAC (CC).
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        return { mime: "image/jpeg", height: bytes.readUInt16BE(at + 5), width: bytes.readUInt16BE(at + 7) };
      }
      at += 2 + length;
    }
  }
  return null;
}
