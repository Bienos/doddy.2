// The one model call behind Messages (ADR-586): Claude answers a typed question in the person's
// language, from the notes the app sent or from general knowledge, with no tools. Behind an interface so
// tests drive the route with a fake. Logs carry counts and codes only, never words.
import Anthropic from "@anthropic-ai/sdk";
import { answerJsonSchema, answerSchema, buildInput, buildInstructions } from "./prompt.js";
import type { AssistRequest } from "./request.js";

export interface AssistUsage { inputTokens: number; outputTokens: number }

export type AssistOutcome =
  | { kind: "ok"; answer: string; /** Real note ids, in the order cited, each once. */ sources: string[]; usage: AssistUsage }
  | { kind: "refused"; usage?: AssistUsage }
  | { kind: "unparsed"; usage?: AssistUsage };

export interface AssistantResponder {
  readonly provider: "anthropic";
  readonly model: string;
  /** Throws on API errors (network, HTTP, abort); a reply that doesn't fit the schema is "unparsed". */
  answer(req: AssistRequest, signal: AbortSignal): Promise<AssistOutcome>;
}

export const MAX_OUTPUT_TOKENS = 1500;

export class ClaudeAssistantResponder implements AssistantResponder {
  readonly provider = "anthropic" as const;
  readonly model: string;
  private readonly effort: "low" | "medium" | "high";
  private readonly client: Anthropic;

  constructor(apiKey: string, options: { model?: string; effort?: "low" | "medium" | "high"; baseURL?: string } = {}) {
    this.model = options.model ?? "claude-haiku-5-5";
    this.effort = options.effort ?? "medium";
    this.client = new Anthropic({ apiKey, baseURL: options.baseURL, maxRetries: 1, timeout: 40_000 });
  }

  async answer(req: AssistRequest, signal: AbortSignal): Promise<AssistOutcome> {
    const { input, aliasToId } = buildInput(req);
    const response = await this.client.messages.create({
      model: this.model,
      max_tokens: MAX_OUTPUT_TOKENS,
      output_config: { effort: this.effort, format: { type: "json_schema", schema: answerJsonSchema(aliasToId.size > 0) } },
      system: buildInstructions(req.locale),
      messages: [{ role: "user", content: input }],
    }, { signal });
    const usage: AssistUsage = {
      inputTokens: response.usage?.input_tokens ?? 0,
      outputTokens: response.usage?.output_tokens ?? 0,
    };
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
    return { kind: "ok", answer: parsed.data.answer, sources, usage };
  }
}
