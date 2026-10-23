// The request the app sends to Messages (ADR-586), validated strictly. The same wire as the Ask
// gateway's (gateway/src/validate.js, AssistantWire.swift) so the app's reply handling is shared:
// unknown fields are refused, text is bounded in Unicode scalars, notes carry only what an answer
// needs. Failure names a field, never a value.
import { z } from "zod";

export const LIMITS = Object.freeze({
  /** Above the worst case the scalar limits allow, so a request within every field limit is never refused as too large. */
  bodyBytes: 128 * 1024,
  userText: 2_000,
  turns: 6,
  turnText: 2_000,
  memories: 8,
  memoryText: 5_000,
  memoryTotal: 12_000,
});

const scalars = (s: string) => [...s].length;
const text = (max: number) => z.string().refine((v) => !/^\s*$/.test(v) && scalars(v) <= max);
const uuid = z.string().regex(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/);

const memory = z.strictObject({
  id: uuid,
  text: text(LIMITS.memoryText),
  source: z.enum(["explicit_text", "explicit_voice", "shared_content", "imported_legacy_unknown"]),
  capturedAt: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/).optional(),
});

export const AssistRequest = z.strictObject({
  schemaVersion: z.literal(1),
  requestId: uuid,
  sessionId: uuid,
  locale: z.string().regex(/^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$/),
  userText: text(LIMITS.userText),
  turns: z.array(z.strictObject({ role: z.enum(["user", "assistant"]), text: text(LIMITS.turnText) })).max(LIMITS.turns).default([]),
  memories: z.array(memory).max(LIMITS.memories).default([]),
}).superRefine((req, ctx) => {
  // A note may be sent once, and all notes together stay under the total.
  const ids = new Set<string>();
  let total = 0;
  for (const [i, m] of req.memories.entries()) {
    const id = m.id.toLowerCase();
    if (ids.has(id)) ctx.addIssue({ code: "custom", path: ["memories", i, "id"], message: "duplicate" });
    ids.add(id);
    total += scalars(m.text);
  }
  if (total > LIMITS.memoryTotal) ctx.addIssue({ code: "custom", path: ["memories"], message: "total" });
});
export type AssistRequest = z.infer<typeof AssistRequest>;

/** The error body, in the app's taxonomy (AssistantError.init(wireCode:)). Content-free messages. */
export const WIRE_STATUS = {
  invalidRequest: 400, notAuthorized: 401, payloadTooLarge: 413, rateLimited: 429, dailyLimitReached: 429,
  invalidCitations: 502, refused: 422, providerUnavailable: 503, notConfigured: 503, timeout: 504,
} as const;
export type WireCode = keyof typeof WIRE_STATUS;

export const WIRE_MESSAGE: Record<WireCode, string> = {
  invalidRequest: "The request was not valid.",
  notAuthorized: "This device is not authorized.",
  payloadTooLarge: "The request was too large.",
  rateLimited: "Too many requests. Try again shortly.",
  dailyLimitReached: "Doddy's daily limit is reached; try again tomorrow.",
  invalidCitations: "The answer could not be checked against your notes.",
  refused: "The assistant declined to answer that.",
  providerUnavailable: "The assistant is unavailable right now.",
  notConfigured: "The assistant is not set up yet.",
  timeout: "The assistant took too long to answer.",
};
