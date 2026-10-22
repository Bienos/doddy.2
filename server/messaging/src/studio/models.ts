// Which Claude model does each Studio step (ADR-584), and what each costs. The owner, 22 Oct: the
// first plan (Opus 5.5 for every step) cost too much, so cheaper models do the steps they suit and a
// real run compares mixes. Prices are Anthropic's list prices read on 22 Oct 2026 (models overview,
// pricing, web search); the code computes each call's cost with its own model's prices.
export const STEPS = ["plan", "research", "pack", "write", "make"] as const;
export type StudioStep = (typeof STEPS)[number];
export type StepModels = Record<StudioStep, string>;

export const OPUS = "claude-opus-5-5";
export const SONNET = "claude-sonnet-5-5";
export const HAIKU = "claude-haiku-5-5";
export const FABLE = "claude-fable-5-1";

/**
 * Default mix: Haiku 5.5 (built for "classification, extraction and routing") plans, extracts claims
 * and runs the fixed render recipe; Sonnet 5.5 researches on the web and writes. Research stays off
 * Haiku because dynamic-filtering web search isn't confirmed for it (the docs say "Claude 4.6 and
 * later"; the skill's own list leaves Haiku 5.5 out) until a real run shows it.
 */
export const DEFAULT_STEP_MODELS: StepModels = { plan: HAIKU, research: SONNET, pack: HAIKU, write: SONNET, make: HAIKU };

/** Named mixes for comparison runs (scripts/studio-live-run.mjs --mix). */
export const MODEL_MIXES: Record<string, StepModels> = {
  cheap: DEFAULT_STEP_MODELS,
  haiku: { plan: HAIKU, research: HAIKU, pack: HAIKU, write: HAIKU, make: HAIKU },
  sonnet: { plan: SONNET, research: SONNET, pack: SONNET, write: SONNET, make: SONNET },
  fable: { plan: FABLE, research: FABLE, pack: FABLE, write: FABLE, make: FABLE },
  opus: { plan: OPUS, research: OPUS, pack: OPUS, write: OPUS, make: OPUS },
};

export interface ModelPrice {
  /** USD per million input and output tokens (prompts up to `longFrom` tokens). */
  input: number; output: number;
  /** Cache reads cost this fraction of `input`; a 5-minute cache write costs 1.25 times it. */
  readFactor: number;
  /** Haiku 5.5 charges more for prompts beyond 100K tokens. */
  long?: { from: number; input: number; output: number };
}

export const PRICES: Record<string, ModelPrice> = {
  [OPUS]: { input: 4, output: 20, readFactor: 0.05 },
  [SONNET]: { input: 2, output: 10, readFactor: 0.05 },
  [HAIKU]: { input: 0.1, output: 0.5, readFactor: 0.1, long: { from: 100_000, input: 0.5, output: 2.5 } },
  "claude-fable-5-1": { input: 10, output: 50, readFactor: 0.025 },
};
/** A model without a price here is counted at the most expensive price, so a cap never under-counts. */
const UNKNOWN_MODEL_PRICE = PRICES["claude-fable-5-1"]!;
export const PER_SEARCH_USD = 0.01;

export interface CallUsage { inputTokens: number; cacheWriteTokens: number; cacheReadTokens: number; outputTokens: number }

/** One call's token cost in USD (searches are priced separately, per search). */
export function tokenCostUsd(model: string, u: CallUsage): number {
  const p = PRICES[model] ?? UNKNOWN_MODEL_PRICE;
  const promptTokens = u.inputTokens + u.cacheReadTokens + u.cacheWriteTokens;
  const tier = p.long && promptTokens > p.long.from ? p.long : p;
  const usd = (u.inputTokens * tier.input + u.outputTokens * tier.output
    + u.cacheReadTokens * tier.input * p.readFactor + u.cacheWriteTokens * tier.input * 1.25) / 1_000_000;
  return usd;
}

/** Fallback on a safety refusal is offered by Anthropic for these models only; Haiku 5.5 has none. */
export const supportsServerFallback = (model: string) => model === OPUS || model === SONNET || model === "claude-fable-5-1";

/** What `studio_items.model` and the logs show: the model when every step uses one, else the short names. */
export function modelLabel(models: StepModels): string {
  const unique = [...new Set(STEPS.map((s) => models[s]))];
  if (unique.length === 1) return unique[0]!;
  return unique.map((m) => m.replace(/^claude-/, "")).join("+").slice(0, 64);
}

/** Parses STUDIO_MODEL_<STEP> overrides over the defaults; STUDIO_MODEL (the old single setting) sets all steps first. */
export function stepModelsFrom(overrides: Partial<Record<StudioStep, string>>, all?: string): StepModels {
  const base: StepModels = all ? { plan: all, research: all, pack: all, write: all, make: all } : { ...DEFAULT_STEP_MODELS };
  for (const s of STEPS) if (overrides[s]) base[s] = overrides[s]!;
  return base;
}
