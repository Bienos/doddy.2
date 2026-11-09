// The one model call behind Messages (ADR-586): Claude answers a typed question in the person's
// language, from the notes the app sent or from general knowledge, with no tools. Behind an interface so
// tests drive the route with a fake. Logs carry counts and codes only, never words.
import { AsyncLocalStorage } from "node:async_hooks";
import Anthropic from "@anthropic-ai/sdk";
import { baseModel, usageFromAnthropic, type TokenUsage } from "../costLedger.js";
import { answerJsonSchema, answerSchema, buildInput, buildInstructions, readPlanOffer, readProposal, type PlanOffer, type Proposal } from "./prompt.js";
import { fileText, type AssistRequest } from "./request.js";

export interface AssistUsage { inputTokens: number; outputTokens: number }

/** The cost detail rides on the usage object under this symbol, so `addTokens` (called by the route and by the
 * text-message chat alike) can write the ledger row. A symbol key is never serialised: the app's wire shape is unchanged. */
export const CALL_DETAIL = Symbol("doddy.callDetail");

/** What the cost ledger needs from one call (counts and ids only). `usage` is absent when the provider reported none. */
export interface CallDetail { model: string; providerRequestId?: string; attempts: number; usage?: TokenUsage }

export type AssistOutcome =
  | { kind: "ok"; answer: string; /** Real note ids, in the order cited, each once. */ sources: string[]; usage: AssistUsage;
      /** A file the user asked for, offered as a card (ADR-606). Absent when none was asked for. */ proposal?: Proposal;
      /** A training plan the user asked for, offered as a card (ADR-626). Absent when none was asked for. */ plan?: PlanOffer }
  | { kind: "refused"; usage?: AssistUsage }
  | { kind: "unparsed"; usage?: AssistUsage };

export interface AssistantResponder {
  readonly provider: "anthropic";
  readonly model: string;
  /** Throws on API errors (network, HTTP, abort); a reply that doesn't fit the schema is "unparsed". */
  answer(req: AssistRequest, signal: AbortSignal): Promise<AssistOutcome>;
}

export const MAX_OUTPUT_TOKENS = 1500;

/**
 * Shortest prompt each model caches, from https://platform.claude.com/docs/en/build-with-claude/prompt-caching
 * (read 9 Nov 2026). A shorter prefix is processed uncached without error, so this only avoids asking for nothing.
 * A model not listed is never given a cache marker.
 */
const CACHE_MIN_TOKENS: Record<string, number> = {
  "claude-fable-5-1": 512, "claude-fable-5": 512, "claude-opus-5-5": 512, "claude-opus-5": 512,
  "claude-sonnet-5-5": 512, "claude-haiku-5-5": 512, "claude-sonnet-5": 1024,
};

/** True when `text` is surely long enough to cache on `model`. English text is about four characters a token; five
 * is used so the estimate errs low: a miss here only skips a saving, never costs money (a too-short prefix is
 * simply not cached by the API). */
export function cacheEligible(model: string, text: string): boolean {
  const min = CACHE_MIN_TOKENS[baseModel(model)];
  return min !== undefined && Math.floor(text.length / 5) >= min;
}

/** Per-call counting of HTTP attempts (the SDK retries inside `create`), so retries can reach the ledger. */
const attemptCounter = new AsyncLocalStorage<{ attempts: number }>();
const countingFetch: typeof fetch = (input, init) => {
  const c = attemptCounter.getStore();
  if (c) c.attempts++;
  return fetch(input, init);
};

/** Marks an error with how many attempts were made; read by `attemptsOf`. */
export const attemptsOf = (err: unknown): number => {
  const a = (err as { doddyAttempts?: unknown } | null)?.doddyAttempts;
  return typeof a === "number" && a >= 1 ? a : 1;
};
export const requestIdOf = (err: unknown): string | undefined => {
  const r = (err as { requestID?: unknown } | null)?.requestID;
  return typeof r === "string" ? r : undefined;
};

type AttachmentBlock = Anthropic.ImageBlockParam | Anthropic.DocumentBlockParam;

/** The photo or file sent with this question, as the API's own blocks. The request schema has already checked it. */
export function attachmentBlocks(req: AssistRequest): AttachmentBlock[] {
  if (req.image) return [{ type: "image", source: { type: "base64", media_type: req.image.mediaType, data: req.image.data } }];
  if (req.file?.mediaType === "application/pdf") {
    return [{ type: "document", title: req.file.name, source: { type: "base64", media_type: "application/pdf", data: req.file.data } }];
  }
  if (req.file?.mediaType === "text/plain") {
    return [{ type: "document", title: req.file.name, source: { type: "text", media_type: "text/plain", data: fileText(req.file.data) ?? "" } }];
  }
  return [];
}

export class ClaudeAssistantResponder implements AssistantResponder {
  readonly provider = "anthropic" as const;
  readonly model: string;
  private readonly effort: "low" | "medium" | "high";
  private readonly client: Anthropic;

  constructor(apiKey: string, options: { model?: string; effort?: "low" | "medium" | "high"; baseURL?: string } = {}) {
    this.model = options.model ?? "claude-haiku-5-5";
    this.effort = options.effort ?? "medium";
    this.client = new Anthropic({ apiKey, baseURL: options.baseURL, maxRetries: 1, timeout: 40_000, fetch: countingFetch });
  }

  async answer(req: AssistRequest, signal: AbortSignal): Promise<AssistOutcome> {
    const counter = { attempts: 0 };
    try {
      return await attemptCounter.run(counter, () => this.ask(req, signal, counter));
    } catch (err) {
      if (err && typeof err === "object") (err as { doddyAttempts?: number }).doddyAttempts = Math.max(1, counter.attempts);
      throw err;
    }
  }

  private async ask(req: AssistRequest, signal: AbortSignal, counter: { attempts: number }): Promise<AssistOutcome> {
    const { input, aliasToId } = buildInput(req);
    const instructions = buildInstructions(req.locale);
    const response = await this.client.messages.create({
      model: this.model,
      max_tokens: MAX_OUTPUT_TOKENS,
      output_config: { effort: this.effort, format: { type: "json_schema", schema: answerJsonSchema(aliasToId.size > 0) } },
      // The instructions are the same on every question (per locale), so they are the cached prefix; the notes,
      // earlier turns, photo and question change every time and come after it, in the user message.
      system: cacheEligible(this.model, instructions)
        ? [{ type: "text", text: instructions, cache_control: { type: "ephemeral" } }]
        : instructions,
      messages: [{ role: "user", content: attachmentBlocks(req).length > 0
        // The photo or file first, then the text that says what it is for; it goes to this call only.
        ? [...attachmentBlocks(req), { type: "text", text: input }]
        : input }],
    }, { signal });
    const usage: AssistUsage = {
      inputTokens: response.usage?.input_tokens ?? 0,
      outputTokens: response.usage?.output_tokens ?? 0,
    };
    const requestId = (response as { _request_id?: string | null })._request_id ?? undefined;
    const detail: CallDetail = {
      model: this.model, attempts: Math.max(1, counter.attempts),
      ...(requestId ? { providerRequestId: requestId } : {}), ...(usageFromAnthropic(response.usage) ? { usage: usageFromAnthropic(response.usage)! } : {}),
    };
    // Not enumerable, so it is invisible to JSON and to deep equality: the wire shape and the usage's own fields are unchanged.
    Object.defineProperty(usage, CALL_DETAIL, { value: detail, enumerable: false });
    // Read the stop reason before the text: a refusal arrives with no text at all.
    if (response.stop_reason === "refusal") return { kind: "refused", usage };
    if (response.stop_reason === "max_tokens") return { kind: "unparsed", usage };
    const block = response.content.find((b) => b.type === "text");
    let json: unknown;
    try { json = JSON.parse(block && "text" in block ? block.text : ""); } catch { return { kind: "unparsed", usage }; }
    const parsed = answerSchema(aliasToId.size > 0).safeParse(json);
    if (!parsed.success || parsed.data.answer.trim() === "") return { kind: "unparsed", usage };
    const seen = new Set<string>();
    const sources: string[] = [];
    for (const alias of parsed.data.sources ?? []) {
      const id = aliasToId.get(alias);
      if (id && !seen.has(id.toLowerCase())) {
        seen.add(id.toLowerCase());
        sources.push(id);
      }
    }
    const proposal = readProposal(parsed.data.proposal);
    const plan = readPlanOffer(parsed.data.plan);
    return { kind: "ok", answer: parsed.data.answer, sources, usage, ...(proposal ? { proposal } : {}), ...(plan ? { plan } : {}) };
  }
}
