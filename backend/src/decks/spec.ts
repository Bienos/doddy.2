import { z } from "zod";
import type { ResearchPack } from "./research.js";

/**
 * What Claude writes for a deck (decision 2026-11-10-better-presentations): a typed outline, never
 * a file. Code checks it here, then `render.ts` lays it out. Claude writes the content slides, the
 * takeaways and the speaker notes; code adds the title, agenda, summary and sources slides, so
 * every deck has the same frame.
 *
 * Facts on the data slides (numbers, a timeline's dates, a quote) must be found in the text of the
 * sources the slide cites: a model proposes, typed code checks. A chart never shows a number that
 * isn't in its sources.
 */

export const DECK_LANGUAGES = [
  "en", "pl", "de", "fr", "es", "it", "pt", "nl", "sv", "da", "no", "fi", "cs", "sk", "hu", "ro", "bg", "el", "hr", "sl",
  "lv", "lt", "uk", "et", "ca", "sr", "is", "ga", "mt", "mk", "bs", "cy", "gl", "lb", "tr", "ru", "be",
] as const;
export type DeckLanguage = (typeof DECK_LANGUAGES)[number];

export const LAYOUTS = ["bullets", "two_column", "stats", "quote", "timeline", "comparison", "chart", "image"] as const;
export type Layout = (typeof LAYOUTS)[number];

/** Source IDs the model may cite: m1 is the user's own material, s1… the research. Fixed, so the schema is the same every time. */
export const SOURCE_IDS = ["m1", ...Array.from({ length: 14 }, (_, i) => `s${i + 1}`)] as const;
export const IMAGE_IDS = ["i1", "i2", "i3"] as const;

export const DECK_LIMITS = {
  contentMin: 5, contentMax: 10, afterDropMin: 3,
  title: 80, subtitle: 140, label: 24, materialLabel: 60, slideTitle: 70, notes: 700,
  pointsMin: 2, pointsMax: 5, point: 130,
  heading: 40, columnPointsMax: 4, columnPoint: 110,
  statsMax: 3, statValue: 16, statLabel: 60, context: 200,
  quote: 280, attribution: 80,
  eventsMin: 3, eventsMax: 6, when: 16, what: 90,
  columnsMin: 2, columnsMax: 3, rowsMin: 2, rowsMax: 6, rowLabel: 30, cell: 50,
  chartMin: 2, chartMax: 8, chartLabel: 24, unit: 24, note: 140,
  caption: 120, imagePointsMax: 3,
  takeawaysMin: 3, takeawaysMax: 5, takeaway: 120,
} as const;
const L = DECK_LIMITS;

// ------------------------------------------------------------------ the typed outline

const line = (max: number) => z.string().transform(oneLine).pipe(z.string().min(1, "empty").max(max));
const optionalLine = (max: number) => z.string().transform(oneLine).pipe(z.string().max(max));
const notes = z.string().transform((s) => s.replace(/\s+/g, " ").trim()).pipe(z.string().max(L.notes));
const sources = z.array(z.string()).max(6);

const common = { title: line(L.slideTitle), notes, sources };

export const SlideSpec = z.discriminatedUnion("layout", [
  z.object({ layout: z.literal("bullets"), ...common, points: z.array(line(L.point)).min(L.pointsMin).max(L.pointsMax) }).strict(),
  z.object({
    layout: z.literal("two_column"), ...common,
    left: z.object({ heading: line(L.heading), points: z.array(line(L.columnPoint)).min(1).max(L.columnPointsMax) }).strict(),
    right: z.object({ heading: line(L.heading), points: z.array(line(L.columnPoint)).min(1).max(L.columnPointsMax) }).strict(),
  }).strict(),
  z.object({
    layout: z.literal("stats"), ...common,
    items: z.array(z.object({ value: line(L.statValue), label: line(L.statLabel) }).strict()).min(1).max(L.statsMax),
    context: optionalLine(L.context),
  }).strict(),
  z.object({ layout: z.literal("quote"), ...common, quote: line(L.quote), attribution: line(L.attribution) }).strict(),
  z.object({
    layout: z.literal("timeline"), ...common,
    events: z.array(z.object({ when: line(L.when), what: line(L.what) }).strict()).min(L.eventsMin).max(L.eventsMax),
  }).strict(),
  z.object({
    layout: z.literal("comparison"), ...common,
    row_header: optionalLine(L.rowLabel),
    columns: z.array(line(L.rowLabel)).min(L.columnsMin).max(L.columnsMax),
    rows: z.array(z.object({ label: line(L.rowLabel), cells: z.array(optionalLine(L.cell)) }).strict()).min(L.rowsMin).max(L.rowsMax),
  }).strict(),
  z.object({
    layout: z.literal("chart"), ...common,
    unit: optionalLine(L.unit),
    points: z.array(z.object({ label: line(L.chartLabel), value: z.number().finite().nonnegative() }).strict()).min(L.chartMin).max(L.chartMax),
    note: optionalLine(L.note),
  }).strict(),
  z.object({
    layout: z.literal("image"), ...common,
    image: z.string(),
    caption: optionalLine(L.caption),
    points: z.array(line(L.point)).max(L.imagePointsMax),
  }).strict(),
]);
export type Slide = z.infer<typeof SlideSpec>;

export const DeckSpec = z
  .object({
    language: z.enum(DECK_LANGUAGES),
    title: line(L.title),
    subtitle: optionalLine(L.subtitle),
    labels: z.object({ agenda: line(L.label), summary: line(L.label), sources: line(L.label), source: line(L.label), material: line(L.materialLabel) }).strict(),
    cover_notes: notes,
    slides: z.array(SlideSpec).min(1).max(L.contentMax + 2),
    takeaways: z.array(line(L.takeaway)).min(L.takeawaysMin).max(L.takeawaysMax),
    summary_notes: notes,
  })
  .strict();
export type Deck = z.infer<typeof DeckSpec>;

function oneLine(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

// ------------------------------------------------------------------ the schema Claude answers in

const str = { type: "string" } as const;
const strs = { type: "array", items: str } as const;
const obj = (properties: Record<string, unknown>) => ({ type: "object", properties, required: Object.keys(properties), additionalProperties: false });
const sourceList = { type: "array", items: { type: "string", enum: [...SOURCE_IDS] } };
const slide = (layout: Layout, extra: Record<string, unknown>) =>
  obj({ layout: { type: "string", const: layout }, title: str, ...extra, sources: sourceList, notes: str });

/**
 * JSON Schema for structured output. No length or count limits (structured output refuses them):
 * the prompt states them and `DeckSpec` enforces them. Fixed, so Anthropic's compiled grammar is
 * reused between decks.
 */
export const DECK_JSON_SCHEMA: Record<string, unknown> = {
  ...obj({
    language: { type: "string", enum: [...DECK_LANGUAGES] },
    title: str,
    subtitle: str,
    labels: obj({ agenda: str, summary: str, sources: str, source: str, material: str }),
    cover_notes: str,
    slides: {
      type: "array",
      items: {
        anyOf: [
          slide("bullets", { points: strs }),
          slide("two_column", { left: obj({ heading: str, points: strs }), right: obj({ heading: str, points: strs }) }),
          slide("stats", { items: { type: "array", items: obj({ value: str, label: str }) }, context: str }),
          slide("quote", { quote: str, attribution: str }),
          slide("timeline", { events: { type: "array", items: obj({ when: str, what: str }) } }),
          slide("comparison", { row_header: str, columns: strs, rows: { type: "array", items: obj({ label: str, cells: strs }) } }),
          slide("chart", { unit: str, points: { type: "array", items: obj({ label: str, value: { type: "number" } }) }, note: str }),
          slide("image", { image: { type: "string", enum: [...IMAGE_IDS] }, caption: str, points: strs }),
        ],
      },
    },
    takeaways: strs,
    summary_notes: str,
  }),
};

// ------------------------------------------------------------------ checks

export interface DeckProblem {
  /** 1-based content slide number, or null for the deck as a whole. */
  slide: number | null;
  message: string;
}

export type CheckResult = { deck: Deck; problems: DeckProblem[] } | { deck: null; problems: DeckProblem[] };

/** Layouts that show facts as data: what they show must be in the sources they cite. */
const DATA_LAYOUTS: ReadonlySet<Layout> = new Set(["stats", "chart", "timeline", "quote", "comparison"]);

/**
 * Shape first (zod), then the rules a schema can't hold: counts, citations that exist, data
 * found in its sources, images that exist and are used once, more than one kind of slide.
 */
export function checkDeck(raw: unknown, pack: ResearchPack): CheckResult {
  const parsed = DeckSpec.safeParse(raw);
  if (!parsed.success) {
    const problems = parsed.error.issues.slice(0, 12).map((issue) => {
      const at = issue.path;
      const slide = at[0] === "slides" && typeof at[1] === "number" ? at[1] + 1 : null;
      const where = at.length ? at.join(".") : "deck";
      return { slide, message: `${where}: ${issue.message}` };
    });
    return { deck: null, problems };
  }
  const deck = parsed.data;
  const problems: DeckProblem[] = [];
  const count = deck.slides.length;
  if (count < L.contentMin || count > L.contentMax) {
    problems.push({ slide: null, message: `the deck has ${count} content slides; write ${L.contentMin} to ${L.contentMax}` });
  }
  const layouts = new Set(deck.slides.map((s) => s.layout));
  // Without sources the data layouts can't be used (they must cite), so only a deck with sources is asked for variety.
  if (pack.sources.length > 0 && count >= 4 && [...layouts].filter((l) => l !== "bullets").length < 2) {
    problems.push({ slide: null, message: "almost every slide is a bullet list; use at least two other layouts (timeline, stats, chart, comparison, two_column, quote, image) where the content fits" });
  }
  const known = new Map(pack.sources.map((s) => [s.id, s]));
  const imagesUsed = new Set<string>();
  deck.slides.forEach((s, index) => {
    const n = index + 1;
    const add = (message: string) => problems.push({ slide: n, message });
    for (const id of s.sources) if (!known.has(id)) add(`cites ${id}, which isn't one of the sources`);
    const cited = s.sources.map((id) => known.get(id)?.text ?? "").join("\n");
    if (DATA_LAYOUTS.has(s.layout) && s.sources.filter((id) => known.has(id)).length === 0) {
      add(`a ${s.layout} slide shows facts, so it must cite the source they come from`);
      return;
    }
    const numbersFound = numbersIn(cited);
    const inSources = (shown: FoundNumber) => numbersFound.some((found) => sameNumber(shown, found));
    const checkNumbers = (what: string, text: string) => {
      for (const token of numberTokens(text)) {
        if (!token.readings.some(inSources)) add(`${what} "${text}" has a number (${token.text}) that isn't in the sources it cites`);
      }
    };
    switch (s.layout) {
      case "stats":
        s.items.forEach((item) => {
          if (!/\d/.test(item.value)) add(`stat "${item.value}" has no number; a stat is a number from the sources`);
          checkNumbers("stat", item.value);
        });
        break;
      case "chart":
        s.points.forEach((p) => {
          if (!inSources({ value: p.value, decimals: decimalsOf(p.value) })) {
            add(`chart value ${p.value} (${p.label}) isn't in the sources it cites; use the numbers exactly as the source writes them`);
          }
        });
        break;
      case "timeline":
        s.events.forEach((e) => checkNumbers("date", e.when));
        break;
      case "comparison":
        s.rows.forEach((r) => {
          if (r.cells.length !== s.columns.length) add(`row "${r.label}" has ${r.cells.length} cells for ${s.columns.length} columns`);
          r.cells.forEach((c) => checkNumbers("cell", c));
        });
        break;
      case "quote":
        if (!normalized(cited).includes(normalized(s.quote))) add("the quote isn't word for word in the source it cites; quote only words a source has");
        break;
      case "image":
        if (!pack.images.some((i) => i.id === s.image)) add(`image ${s.image} doesn't exist; use only the images listed`);
        else if (imagesUsed.has(s.image)) add(`image ${s.image} is used twice`);
        imagesUsed.add(s.image);
        break;
      case "bullets":
      case "two_column":
        break;
    }
  });
  return { deck, problems };
}

/** The deck without the slides that still have a problem, or null when too little is left to show. */
export function dropBroken(deck: Deck, problems: DeckProblem[]): Deck | null {
  const broken = new Set(problems.map((p) => p.slide).filter((n): n is number => n !== null));
  const slides = deck.slides.filter((_, i) => !broken.has(i + 1)).slice(0, L.contentMax);
  return slides.length >= L.afterDropMin ? { ...deck, slides } : null;
}

// ------------------------------------------------------------------ numbers and quotes in source text

export interface FoundNumber {
  value: number;
  /** Decimal places as written, so a rounded figure can be matched honestly. */
  decimals: number;
}

/** One number as a text writes it ("31 808", "27,45"), with every way it could be meant. */
export interface NumberToken {
  text: string;
  readings: FoundNumber[];
}

const DIGITS = /\d+(?:[   .,']\d+)*/g;
const SEPARATORS = /[   .,']/;

/**
 * The numbers a text writes, each read every way it could be meant: "31 808" and "31,808" as
 * 31808, "27,45" as 27.45, "1.305" as 1305 or 1.305. With `groups`, each digit group also counts
 * on its own, for source text where "1305 1945" or a list may run together; never for what a
 * slide shows, so "27,5" can't pass because "27" is somewhere in the source.
 */
export function numberTokens(text: string, groups = false): NumberToken[] {
  const tokens: NumberToken[] = [];
  for (const match of text.matchAll(DIGITS)) {
    const raw = match[0];
    const readings: FoundNumber[] = [];
    const push = (value: number, decimals: number) => {
      if (Number.isFinite(value)) readings.push({ value, decimals });
    };
    if (groups) for (const g of raw.split(SEPARATORS)) push(Number(g), 0);
    const compact = raw.replace(/[   ']/g, "");
    const lastComma = compact.lastIndexOf(",");
    const lastDot = compact.lastIndexOf(".");
    if (lastComma < 0 && lastDot < 0) {
      push(Number(compact), 0);
    } else if (lastComma >= 0 && lastDot >= 0) {
      const decimalMark = lastComma > lastDot ? "," : ".";
      const other = decimalMark === "," ? "." : ",";
      const plain = compact.split(other).join("").replace(decimalMark, ".");
      push(Number(plain), plain.split(".")[1]?.length ?? 0);
    } else {
      const mark = lastComma >= 0 ? "," : ".";
      const parts = compact.split(mark);
      // As thousands separators: 31,808 or 1.305.000.
      if (parts.slice(1).every((p) => p.length === 3)) push(Number(parts.join("")), 0);
      // As a decimal mark, when it appears once: 27,45 or 3.5.
      if (parts.length === 2) push(Number(`${parts[0]}.${parts[1]}`), parts[1]!.length);
    }
    tokens.push({ text: raw, readings });
  }
  return tokens;
}

/** Every reading of every number in source text. */
export function numbersIn(text: string): FoundNumber[] {
  return numberTokens(text, true).flatMap((t) => t.readings);
}

function decimalsOf(value: number): number {
  const s = String(value);
  return s.includes(".") ? s.split(".")[1]!.length : 0;
}

/**
 * The same figure: equal, or the slide's value is the source's figure rounded to the places the
 * slide writes (27.45 in the source may show as 27.5, never 28 shown as 27.45).
 */
export function sameNumber(shown: FoundNumber, found: FoundNumber): boolean {
  if (shown.value === found.value) return true;
  if (shown.decimals >= found.decimals) return false;
  return Math.abs(shown.value - found.value) <= 0.5 * 10 ** -shown.decimals + 1e-9;
}

/** For quotes: case, spacing, quotation marks and dashes don't matter. */
export function normalized(text: string): string {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[‘’‚‛'`]/g, "'")
    .replace(/[“”„‟«»"]/g, '"')
    .replace(/[‐-―-]/g, "-")
    .replace(/\s+/g, " ")
    .trim();
}
