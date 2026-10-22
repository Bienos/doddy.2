// Studio (ADR-584, docs/implementation/STUDIO.md): the job the app sends and the user approves, the
// shapes the model returns at each step, and the content the renderers read. Model-facing schemas
// have no length limits (structured output refuses them); code checks the limits afterwards.
import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJson } from "../taskCalls/payload.js";

export const STUDIO_KINDS = ["brief"] as const;
export const LENGTHS = ["short", "standard", "long"] as const;
export const STYLES = ["plain", "lively"] as const;
export const ITEM_STATES = ["draft", "queued", "running", "ready", "needs_look", "failed", "cancelled"] as const;
export type ItemState = (typeof ITEM_STATES)[number];
export const STAGES = ["plan", "research", "write", "make", "check", "store"] as const;
export type Stage = (typeof STAGES)[number];
export const FAILURE_CODES = [
  "interrupted", "time_limit", "refused", "provider_error", "unreadable_result", "too_little_found", "cost_limit",
] as const;
export type FailureCode = (typeof FAILURE_CODES)[number];
export const CONFIDENCE = ["high", "medium", "low"] as const;
export const CHART_KINDS = ["bar", "column", "line", "donut"] as const;

/** What the app shows: a running item's stage folded into three words. */
export type AppState = "queued" | "researching" | "making" | "checking" | "ready" | "needs_look" | "failed" | "cancelled";
export function appState(state: ItemState, stage: Stage | null): AppState | undefined {
  if (state === "draft") return undefined;
  if (state !== "running") return state;
  if (stage === "make") return "making";
  if (stage === "check" || stage === "store") return "checking";
  return "researching";
}

export const LIMITS = {
  topic: 300, audience: 120, details: 1000, sources: 5, sourceTitle: 200, url: 2048,
  title: 90, answer: 500, heading: 90, point: 400, sectionsMin: 2, sectionsMax: 5, pointsMax: 6,
  disagreements: 4, gaps: 5, gap: 200, headline: 90, fact: 110, factsMin: 3, factsMax: 7,
  chartTitle: 70, unit: 20, chartRowsMin: 2, chartRowsMax: 8, chartLabel: 24, sourceLine: 160, altText: 400,
  claimText: 400, quote: 300, claimsMin: 3, claimsMax: 40, subQuestionsMin: 3, subQuestionsMax: 5,
} as const;

const text = (max: number) => z.string().max(max).refine((s) => s.trim().length > 0, "empty");
export const httpUrl = z.string().max(LIMITS.url).regex(/^https?:\/\/\S+$/);

/** POST /v1/studio. Kept exactly as sent; optional fields are left out, never null or empty. */
export const jobBody = z.strictObject({
  kind: z.enum(STUDIO_KINDS),
  topic: text(LIMITS.topic),
  audience: text(LIMITS.audience).optional(),
  length: z.enum(LENGTHS),
  style: z.enum(STYLES),
  language: z.string().regex(/^[a-z]{2}$/),
  details: text(LIMITS.details).optional(),
  sources: z.array(z.strictObject({ url: httpUrl, title: text(LIMITS.sourceTitle) })).min(1).max(LIMITS.sources).optional(),
});
export type StudioJob = z.infer<typeof jobBody>;

/** What the user approves: SHA-256 over the canonical JSON of the job (keys sorted, no spaces). */
export const jobJson = (job: StudioJob): string => canonicalJson(job);
export const jobDigest = (job: StudioJob): Buffer => createHash("sha256").update(jobJson(job), "utf8").digest();

// ---------- what the model returns (no limits; code checks them) ----------

export const PlanOutput = z.object({
  title: z.string().describe(`A short, honest title for the brief, at most ${LIMITS.title} characters.`),
  subQuestions: z.array(z.string()).describe(`${LIMITS.subQuestionsMin} to ${LIMITS.subQuestionsMax} sub-questions that together answer the topic.`),
  outline: z.array(z.string()).describe("The brief's sections in order, one line each."),
  audience: z.string().describe("Who it is for, in a few words."),
});
export type PlanOutput = z.infer<typeof PlanOutput>;

export const PackOutput = z.object({
  claims: z.array(z.object({
    text: z.string().describe("One claim in plain words."),
    quote: z.string().describe(`The words on the page that support it, copied exactly, at most ${LIMITS.quote} characters.`),
    url: z.string().describe("Copied exactly from the sources list."),
    sourceTitle: z.string(),
  })).describe(`The useful claims, at most ${LIMITS.claimsMax}.`),
});
export type PackOutput = z.infer<typeof PackOutput>;

const claimRefs = z.array(z.string()).describe("IDs of the claims this rests on, e.g. [\"c1\"].");
export const ContentOutput = z.object({
  title: z.string(),
  answer: z.string().describe(`The answer first, in plain words, at most ${LIMITS.answer} characters.`),
  sections: z.array(z.object({
    heading: z.string(),
    points: z.array(z.object({ text: z.string(), claims: claimRefs })),
  })).describe(`${LIMITS.sectionsMin} to ${LIMITS.sectionsMax} sections, one per sub-question, up to ${LIMITS.pointsMax} points each.`),
  disagreements: z.array(z.object({ text: z.string(), claims: claimRefs })).describe("Where sources disagree; may be empty."),
  confidence: z.enum(CONFIDENCE),
  gaps: z.array(z.string()).describe("What couldn't be found or confirmed; may be empty."),
  infographic: z.object({
    headline: z.object({ text: z.string(), claims: claimRefs }),
    facts: z.array(z.object({ text: z.string(), claims: claimRefs })).describe(`${LIMITS.factsMin} to ${LIMITS.factsMax} facts.`),
    numbered: z.boolean().describe("True only when the facts are a sequence."),
    chart: z.object({
      kind: z.enum(CHART_KINDS),
      title: z.string(),
      unit: z.string(),
      data: z.array(z.object({ label: z.string(), value: z.number() })),
      claims: claimRefs,
    }),
    sourceLine: z.string(),
    altText: z.string().describe("What the infographic shows, for someone who can't see it."),
  }),
});
export type ContentOutput = z.infer<typeof ContentOutput>;

// ---------- the research pack and the content, as checked and stored ----------

export interface PackSource { id: string; url: string; title: string; fetchedAt: string }
export interface PackClaim { id: string; text: string; quote: string; source: string }
export interface ResearchPack { sources: PackSource[]; claims: PackClaim[] }

/** content.json as the renderers read it: the written content plus the pack it rests on. */
export type RenderContent = ContentOutput & { language: string; sources: PackSource[]; claims: PackClaim[] };

const tooLong = (problems: string[], where: string, value: string, max: number) => {
  if (!value.trim()) problems.push(`${where} is empty`);
  else if (value.length > max) problems.push(`${where} is ${value.length} characters; at most ${max}`);
};
const countIn = (problems: string[], where: string, n: number, min: number, max: number) => {
  if (n < min || n > max) problems.push(`${where}: ${n}; needs ${min} to ${max}`);
};

/**
 * Every rule the written content must meet before anything is rendered. Returns the problems in
 * plain words (they go back to the model for one retry); empty means it passes.
 */
export function contentProblems(c: ContentOutput, pack: ResearchPack): string[] {
  const p: string[] = [];
  const known = new Set(pack.claims.map((x) => x.id));
  const refs = (where: string, ids: string[], required = true) => {
    if (required && ids.length === 0) p.push(`${where} names no claim`);
    for (const id of ids) if (!known.has(id)) p.push(`${where} names claim "${id}", which isn't in the pack`);
  };
  tooLong(p, "title", c.title, LIMITS.title);
  tooLong(p, "answer", c.answer, LIMITS.answer);
  countIn(p, "sections", c.sections.length, LIMITS.sectionsMin, LIMITS.sectionsMax);
  c.sections.forEach((s, i) => {
    tooLong(p, `section ${i + 1} heading`, s.heading, LIMITS.heading);
    countIn(p, `section ${i + 1} points`, s.points.length, 1, LIMITS.pointsMax);
    s.points.forEach((pt, j) => {
      tooLong(p, `section ${i + 1} point ${j + 1}`, pt.text, LIMITS.point);
      refs(`section ${i + 1} point ${j + 1}`, pt.claims);
    });
  });
  countIn(p, "disagreements", c.disagreements.length, 0, LIMITS.disagreements);
  c.disagreements.forEach((d, i) => {
    tooLong(p, `disagreement ${i + 1}`, d.text, LIMITS.point);
    refs(`disagreement ${i + 1}`, d.claims);
  });
  countIn(p, "gaps", c.gaps.length, 0, LIMITS.gaps);
  c.gaps.forEach((g, i) => tooLong(p, `gap ${i + 1}`, g, LIMITS.gap));
  const g = c.infographic;
  tooLong(p, "headline", g.headline.text, LIMITS.headline);
  refs("headline", g.headline.claims);
  countIn(p, "facts", g.facts.length, LIMITS.factsMin, LIMITS.factsMax);
  g.facts.forEach((f, i) => {
    tooLong(p, `fact ${i + 1}`, f.text, LIMITS.fact);
    refs(`fact ${i + 1}`, f.claims);
  });
  tooLong(p, "chart title", g.chart.title, LIMITS.chartTitle);
  if (g.chart.unit.length > LIMITS.unit) p.push(`chart unit is ${g.chart.unit.length} characters; at most ${LIMITS.unit}`);
  countIn(p, "chart rows", g.chart.data.length, LIMITS.chartRowsMin, LIMITS.chartRowsMax);
  g.chart.data.forEach((row, i) => {
    tooLong(p, `chart row ${i + 1} label`, row.label, LIMITS.chartLabel);
    if (!Number.isFinite(row.value)) p.push(`chart row ${i + 1} value isn't a number`);
    else if (g.chart.kind === "donut" && row.value < 0) p.push(`chart row ${i + 1} is negative in a donut`);
  });
  refs("chart", g.chart.claims);
  tooLong(p, "source line", g.sourceLine, LIMITS.sourceLine);
  tooLong(p, "alt text", g.altText, LIMITS.altText);
  return p;
}

/** The result the app reads (encrypted at rest): what the run made and how it checked. */
export interface StudioResult {
  title: string;
  /** `altText` is the infographic's, for VoiceOver on the item screen. */
  summary: { answer: string; confidence: (typeof CONFIDENCE)[number]; altText: string };
  sources: PackSource[];
  checks: Check[];
  skills: { id: string; version: string }[];
}

export interface Check { name: string; passed: boolean; detail: string }

/** The files S0 keeps, by name. Anything else Claude saves is dropped. */
export const FILE_SPECS = {
  "brief.pdf": { role: "brief", mime: "application/pdf" },
  "infographic.svg": { role: "infographic", mime: "image/svg+xml" },
  "infographic.png": { role: "infographic_png", mime: "image/png" },
  "infographic-a4.png": { role: "infographic_print", mime: "image/png" },
} as const;
export type FileName = keyof typeof FILE_SPECS;
export const FILE_NAMES = Object.keys(FILE_SPECS) as FileName[];
export const MAX_FILE_BYTES = 15 * 1024 * 1024;
