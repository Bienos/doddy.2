import { z } from "zod";
import { ENDINGS, KINDS } from "../logbook/catalog.js";

/**
 * What Doddy's server answers for kept notes and conversations (ADR-595), mirroring
 * backend/src/memory/. test/contracts.test.ts reads contracts/web/memory-*.json, which the server
 * writes from its own replies, through these. Unknown fields are dropped, so a newer server doesn't
 * break an older page; a reply that doesn't fit is an error, never half-shown text.
 */

export const MemoryOverview = z.object({
  notes: z.boolean(),
  conversations: z.boolean(),
  noteCount: z.number().int().nonnegative(),
  conversationCount: z.number().int().nonnegative(),
  keptDays: z.number().int().positive(),
  lastSyncedAt: z.string().nullable(),
});
export type MemoryOverview = z.infer<typeof MemoryOverview>;

export const NoteSource = z.enum(["explicit_text", "explicit_voice", "shared_content", "imported_legacy_unknown", "imported_file"]);

export const NoteView = z.object({
  id: z.string(),
  text: z.string(),
  source: NoteSource,
  kind: z.enum(KINDS).nullable(),
  capturedAt: z.string().nullable(),
});
export type NoteView = z.infer<typeof NoteView>;

/** `unreadable` is how many rows the server left out because they no longer decrypt (another key, altered bytes). */
export const NotesList = z.object({
  notes: z.array(NoteView),
  total: z.number().int().nonnegative(),
  nextOffset: z.number().int().nullable(),
  unreadable: z.number().int().nonnegative().default(0),
});

export const Turn = z.object({ role: z.enum(["user", "doddy"]), text: z.string() });
export type Turn = z.infer<typeof Turn>;

export const ConversationSummary = z.object({
  id: z.string(),
  startedAt: z.string(),
  endedAt: z.string(),
  turnCount: z.number().int().nonnegative(),
  language: z.string().nullable(),
  endedBy: z.enum(ENDINGS).nullable(),
  preview: z.string(),
});
export type ConversationSummary = z.infer<typeof ConversationSummary>;

export const ConversationList = z.object({
  conversations: z.array(ConversationSummary),
  total: z.number().int().nonnegative(),
  nextOffset: z.number().int().nullable(),
  unreadable: z.number().int().nonnegative().default(0),
});

export const ConversationDetail = z.object({
  id: z.string(),
  startedAt: z.string(),
  endedAt: z.string(),
  language: z.string().nullable(),
  endedBy: z.enum(ENDINGS).nullable(),
  turns: z.array(Turn),
});
export type ConversationDetail = z.infer<typeof ConversationDetail>;

export const ConversationDeleted = z.object({ deleted: z.number().int().nonnegative() });

/** What DELETE /v1/web/memory answers: both kinds are now off, and how many of each went. */
export const MemoryDeleted = z.object({
  notes: z.boolean(),
  conversations: z.boolean(),
  deletedNotes: z.number().int().nonnegative(),
  deletedConversations: z.number().int().nonnegative(),
});

export const ChatSource = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("note"), id: z.string(), text: z.string(), capturedAt: z.string().nullable() }),
  z.object({ kind: z.literal("conversation"), id: z.string(), startedAt: z.string(), turns: z.array(Turn) }),
]);
export type ChatSource = z.infer<typeof ChatSource>;

export const ChatReply = z.object({ text: z.string(), sources: z.array(ChatSource) });
export type ChatReply = z.infer<typeof ChatReply>;
