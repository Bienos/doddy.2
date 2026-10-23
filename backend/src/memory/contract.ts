import { z } from "zod";
import { AppError } from "../errors.js";

/**
 * Kept memory, the server's contract (ADR-603, docs/product/CLOUD_MEMORY.md): the notes and
 * conversations a person has chosen to keep on Doddy's server, in text only (never audio).
 * Unlike Logbook (counts), this is content. It is accepted only from the iPhone's own session,
 * only while the person's switch for that kind is on, and only in these shapes: every object is
 * strict, every text has a length range, every id is a UUID.
 */

/** Conversations are kept this long, counted from when they started; the hourly sweep deletes older ones. */
export const MEMORY_KEPT_DAYS = 365;
export const MEMORY_MAX_NOTES = 5_000;
export const MEMORY_NOTE_TEXT_MAX = 5_000;
export const MEMORY_NOTES_MAX_BODY_BYTES = 8 * 1024 * 1024;
export const MEMORY_MAX_TURNS = 400;
export const MEMORY_TURN_TEXT_MAX = 4_000;
export const MEMORY_CONVERSATION_MAX_BODY_BYTES = 768 * 1024;
/**
 * What one person can keep: a year of conversations at a few a day, and a size that bounds what one
 * download, search or chat question has to decrypt in the server's memory. A new conversation past
 * either is refused (it replaces an older one with the same id).
 */
export const MEMORY_MAX_CONVERSATIONS = 1_500;
export const MEMORY_MAX_CONVERSATION_BYTES = 24 * 1024 * 1024;

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const ISO_INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;
const SOURCES = ["explicit_text", "explicit_voice", "shared_content", "imported_legacy_unknown", "imported_file"] as const;
const KINDS = ["fact", "preference", "commitment", "recommendation", "decision", "item", "place", "intention", "other"] as const;
const ENDINGS = ["you", "doddy", "quiet", "dropped"] as const;

const id = z.string().regex(UUID).transform((value) => value.toLowerCase());
const instant = z.string().regex(ISO_INSTANT).refine((value) => !Number.isNaN(Date.parse(value)), "not a time");
/** A text that isn't blank, counted in characters the way the app counts them. */
const words = (max: number) => z.string().refine((value) => !/^\s*$/.test(value) && [...value].length <= max, `1 to ${max} characters`);
const locale = z.string().regex(/^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$/);

export const NoteItem = z
  .object({
    id,
    text: words(MEMORY_NOTE_TEXT_MAX),
    source: z.enum(SOURCES),
    kind: z.enum(KINDS).optional(),
    capturedAt: instant.optional(),
  })
  .strict();
export type NoteItem = z.output<typeof NoteItem>;

/** The whole list of notes the iPhone holds now. Notes it no longer holds are deleted here too. */
export const NotesSnapshot = z
  .object({ items: z.array(NoteItem).max(MEMORY_MAX_NOTES) })
  .strict()
  .refine((snapshot) => new Set(snapshot.items.map((item) => item.id)).size === snapshot.items.length, "a note appears twice");

export const Turn = z.object({ role: z.enum(["user", "doddy"]), text: words(MEMORY_TURN_TEXT_MAX) }).strict();
export type Turn = z.output<typeof Turn>;

export const ConversationUpload = z
  .object({
    startedAt: instant,
    endedAt: instant,
    language: locale.optional(),
    endedBy: z.enum(ENDINGS).optional(),
    turns: z.array(Turn).min(1).max(MEMORY_MAX_TURNS),
  })
  .strict()
  .refine((conversation) => Date.parse(conversation.endedAt) >= Date.parse(conversation.startedAt), "it ended before it started");
export type ConversationUpload = z.output<typeof ConversationUpload>;

/** The two switches, set by the iPhone. Off deletes that kind of data. */
export const MemoryStateBody = z.object({ notes: z.boolean(), conversations: z.boolean() }).strict();

/** Searching notes: the words travel in the body, never in an address that a proxy or the browser's history could keep. */
export const NotesSearchBody = z
  .object({
    q: words(200),
    limit: z.number().int().min(1).max(100).optional(),
    offset: z.number().int().min(0).max(100_000).optional(),
  })
  .strict();

/** What the browser's chat asks. The page sends the earlier turns it shows; nothing is stored. */
export const ChatBody = z
  .object({
    message: words(2_000),
    history: z.array(z.object({ role: z.enum(["user", "assistant"]), text: words(2_000) }).strict()).max(6).optional(),
    locale: locale.optional(),
  })
  .strict();
export type ChatBody = z.output<typeof ChatBody>;

// ---- what the page reads

export interface NoteView {
  id: string;
  text: string;
  source: (typeof SOURCES)[number];
  kind: (typeof KINDS)[number] | null;
  capturedAt: string | null;
}

export interface ConversationSummary {
  id: string;
  startedAt: string;
  endedAt: string;
  turnCount: number;
  language: string | null;
  endedBy: (typeof ENDINGS)[number] | null;
  /** The first thing the person said, cut to 140 characters. */
  preview: string;
}

export interface ConversationView extends Omit<ConversationSummary, "preview" | "turnCount"> {
  turns: Turn[];
}

export interface MemoryOverview {
  notes: boolean;
  conversations: boolean;
  noteCount: number;
  conversationCount: number;
  keptDays: number;
  /** When the iPhone last sent a note list or a conversation; null before the first. */
  lastSyncedAt: string | null;
}

/** A refusal names the section that failed, never what was sent. */
export function refuse(error: z.ZodError): never {
  const sections = [...new Set(error.issues.map((issue) => (typeof issue.path[0] === "string" ? issue.path[0] : "the request")))].slice(0, 3);
  throw new AppError("invalid_request", { message: `That wasn't valid (${sections.join(", ")}). Nothing was stored.` });
}

export const ONE_DAY_MS = 86_400_000;
export const keptSince = (now: number) => now - MEMORY_KEPT_DAYS * ONE_DAY_MS;
