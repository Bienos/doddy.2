// Errands (ADR-570, docs/implementation/ERRANDS.md): the request the app sends, the result card the
// app receives, and the digest the user approves. The card schema here is the contract; what the
// model writes is checked against it after the code rules in card.ts have run.
import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJson } from "../taskCalls/payload.js";

export const ERRAND_STATES = ["draft", "queued", "running", "done", "failed", "cancelled"] as const;
export type ErrandState = (typeof ERRAND_STATES)[number];

export const FAILURE_CODES = ["interrupted", "time_limit", "refused", "provider_error", "unreadable_result"] as const;
export type FailureCode = (typeof FAILURE_CODES)[number];

export const SECTION_KINDS = ["options", "brief", "checklist", "places"] as const;
export const BUDGET_WITHIN = ["yes", "no", "unknown"] as const;

export const LIMITS = {
  words: 1000, brief: 1000, title: 80,
  answer: 600, sections: 6, items: 8, next: 3, sources: 20,
  heading: 80, itemTitle: 120, detail: 300, when: 80, price: 60, site: 80,
  recommendation: 600, budgetAsked: 200, nextLine: 160, sourceTitle: 200, url: 2048,
} as const;

const text = (max: number) => z.string().max(max).refine((s) => s.trim().length > 0, "empty");

export const ERRAND_KINDS = ["shopping"] as const;
export const PRIORITY_LIMITS = { count: 5, length: 40 } as const;

const priority = z.string().min(1).max(PRIORITY_LIMITS.length)
  .refine((s) => s === s.trim() && s.trim().length > 0, "untrimmed or empty");

/**
 * POST /v1/errands. The words are stored exactly as sent (never trimmed or rewritten). A shopping
 * errand (docs/implementation/SHOPPING.md) adds `kind: "shopping"` and the user's priorities in their
 * order; priorities are allowed only on a shopping errand and are required there (may be empty).
 */
export const createBody = z.strictObject({
  words: text(LIMITS.words),
  brief: text(LIMITS.brief),
  title: text(LIMITS.title),
  language: z.string().regex(/^[a-z]{2}$/),
  kind: z.enum(ERRAND_KINDS).optional(),
  priorities: z.array(priority).max(PRIORITY_LIMITS.count).optional(),
}).superRefine((b, ctx) => {
  if (b.kind === "shopping" && !b.priorities) ctx.addIssue({ code: "custom", path: ["priorities"], message: "required for shopping" });
  if (b.kind !== "shopping" && b.priorities) ctx.addIssue({ code: "custom", path: ["priorities"], message: "only for shopping" });
  const seen = new Set<string>();
  for (const p of b.priorities ?? []) {
    const k = p.toLocaleLowerCase("pl");
    if (seen.has(k)) ctx.addIssue({ code: "custom", path: ["priorities"], message: "duplicate" });
    seen.add(k);
  }
});
export type ErrandContent = z.infer<typeof createBody>;

/**
 * What the user approves: SHA-256 over the canonical JSON of {brief, language, title, words} (keys
 * sorted, no spaces, strings as JSON.stringify writes them), UTF-8. Plain SHA-256 as the contract
 * says, so the app can recompute it from the words it showed; the call-case digest is an HMAC instead.
 * A shopping errand also binds `kind` and `priorities` (fixture errand_create_shopping_v1.json); a
 * research errand's digest is unchanged.
 */
export function contentJson(c: ErrandContent): string {
  if (c.kind === "shopping") {
    return canonicalJson({ brief: c.brief, kind: c.kind, language: c.language, priorities: c.priorities ?? [], title: c.title, words: c.words });
  }
  return canonicalJson({ brief: c.brief, language: c.language, title: c.title, words: c.words });
}
export const contentDigest = (c: ErrandContent): Buffer => createHash("sha256").update(contentJson(c), "utf8").digest();

const httpUrl = z.string().max(LIMITS.url).regex(/^https?:\/\/\S+$/);

const ResultItem = z.strictObject({
  title: text(LIMITS.itemTitle),
  detail: text(LIMITS.detail).optional(),
  when: text(LIMITS.when).optional(),
  price: text(LIMITS.price).optional(),
  url: httpUrl.optional(),
  site: text(LIMITS.site).optional(),
});

export const SHOPPING_LIMITS = {
  offers: 12, picks: 4, offerTitle: 160, shop: 80, delivery: 120, notes: 160, line: 200,
  howChosen: 3, watchOuts: 4, unknowns: 4, rejected: 4,
} as const;
export const PICK_ROLES = ["best", "cheapest", "premium", "alternative"] as const;
export const EVIDENCE = ["shop_page", "listing"] as const;

const money = z.strictObject({ minor: z.number().int().positive().max(1e11), currency: z.string().regex(/^[A-Z]{3}$/) });

/** `result.shopping` (SHOPPING.md): every offer was registered by the code, never written by the model. */
export const ShoppingResultSchema = z.strictObject({
  priorities: z.array(z.string().max(PRIORITY_LIMITS.length)).max(PRIORITY_LIMITS.count),
  budget: money.optional(),
  offers: z.array(z.strictObject({
    id: z.string().regex(/^o\d{1,3}$/),
    title: text(SHOPPING_LIMITS.offerTitle),
    shop: text(SHOPPING_LIMITS.shop),
    price: money,
    delivery: text(SHOPPING_LIMITS.delivery).optional(),
    url: httpUrl,
    /** A tracked link to the same page, only when the owner has an affiliate programme with this shop (ADR-612). */
    buyUrl: httpUrl.optional(),
    site: text(LIMITS.site).optional(),
    evidence: z.enum(EVIDENCE),
    seenAt: z.iso.datetime(),
    gtin: z.string().regex(/^\d{8,14}$/).optional(),
    notes: text(SHOPPING_LIMITS.notes).optional(),
  })).min(1).max(SHOPPING_LIMITS.offers),
  picks: z.array(z.strictObject({
    role: z.enum(PICK_ROLES),
    offerId: z.string().regex(/^o\d{1,3}$/),
    why: text(SHOPPING_LIMITS.line),
    tradeoff: text(SHOPPING_LIMITS.line).optional(),
    overBudget: money.optional(),
  })).min(1).max(SHOPPING_LIMITS.picks),
  howChosen: z.array(text(SHOPPING_LIMITS.line)).max(SHOPPING_LIMITS.howChosen),
  watchOuts: z.array(text(SHOPPING_LIMITS.line)).max(SHOPPING_LIMITS.watchOuts),
  unknowns: z.array(text(SHOPPING_LIMITS.line)).max(SHOPPING_LIMITS.unknowns),
  rejected: z.array(text(SHOPPING_LIMITS.line)).max(SHOPPING_LIMITS.rejected),
  stats: z.strictObject({ offersSeen: z.number().int().min(0), shops: z.number().int().min(0) }),
});
export type ShoppingResult = z.infer<typeof ShoppingResultSchema>;

/** The result card as stored and served. Optional fields are left out, never null. */
export const ErrandResultSchema = z.strictObject({
  answer: text(LIMITS.answer),
  sections: z.array(z.strictObject({
    heading: text(LIMITS.heading),
    kind: z.enum(SECTION_KINDS),
    items: z.array(ResultItem).min(1).max(LIMITS.items),
  })).max(LIMITS.sections),
  recommendation: text(LIMITS.recommendation).optional(),
  budget: z.strictObject({ asked: text(LIMITS.budgetAsked), within: z.enum(BUDGET_WITHIN) }).optional(),
  next: z.array(text(LIMITS.nextLine)).max(LIMITS.next),
  sources: z.array(z.strictObject({ title: text(LIMITS.sourceTitle), url: httpUrl, site: text(LIMITS.site).optional() })).max(LIMITS.sources),
  checkedAt: z.iso.datetime(),
  shopping: ShoppingResultSchema.optional(),
});
export type ErrandResult = z.infer<typeof ErrandResultSchema>;

export const resultJson = (r: ErrandResult): string => canonicalJson(r);
export const resultDigest = (r: ErrandResult): Buffer => createHash("sha256").update(resultJson(r), "utf8").digest();

/**
 * What the card writer (phase 2) returns: every field present (null when empty), no length limits,
 * so a long line is shortened by code instead of failing the whole card. card.ts turns it into an
 * ErrandResult.
 */
export const CardOutput = z.object({
  answer: z.string().describe(`The gist in one to three sentences, at most ${LIMITS.answer} characters.`),
  sections: z.array(z.object({
    heading: z.string().describe("A short heading, e.g. the kind of thing compared."),
    kind: z.enum(SECTION_KINDS).describe("options: things to compare; places: places; checklist: steps; brief: short findings."),
    items: z.array(z.object({
      title: z.string(),
      detail: z.string().nullable(),
      when: z.string().nullable().describe("Dates or times, if any."),
      price: z.string().nullable().describe("Only as found on the page at `url`, with its currency and unit."),
      url: z.string().nullable().describe("Copied exactly from the sources list, or null."),
      site: z.string().nullable(),
    })).describe(`At most ${LIMITS.items}.`),
  })).describe(`At most ${LIMITS.sections}.`),
  recommendation: z.string().nullable().describe("What you would pick and why, in a sentence or two, or null."),
  budget: z.object({
    asked: z.string().describe("The budget in the person's words."),
    within: z.enum(BUDGET_WITHIN),
  }).nullable().describe("Only when the person gave a budget; otherwise null."),
  next: z.array(z.string()).describe(`At most ${LIMITS.next} short follow-ups the person might ask next.`),
  sources: z.array(z.object({
    title: z.string(),
    url: z.string().describe("Copied exactly from the sources list."),
    site: z.string().nullable(),
  })).describe(`The pages the card relies on, at most ${LIMITS.sources}.`),
});
export type CardOutput = z.infer<typeof CardOutput>;
