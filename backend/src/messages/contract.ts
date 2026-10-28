import { z } from "zod";

/**
 * Messages on the web (owner, 28 Oct 2026: "sync always on"): a copy of the iPhone's Messages thread, so Doddy Web
 * can show it. The iPhone sends its newest messages as one snapshot each time the thread changes; the snapshot
 * replaces what was kept, so a message deleted on the iPhone is gone here at its next send, and "Delete
 * conversation" on the iPhone deletes this copy and reads that back. Text only: a photo is never sent here (only
 * that a message had one), and a file is its name and kind, never its link.
 */
export const THREAD_MAX_MESSAGES = 200;
export const THREAD_TEXT_MAX = 10_000;
export const THREAD_MAX_BODY_BYTES = 3 * 1024 * 1024;

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const ISO_INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;
const FILE_KINDS = ["deck", "doc", "spreadsheet", "pdf", "text"] as const;

const words = (max: number) => z.string().refine((value) => !/^\s*$/.test(value) && [...value].length <= max, `1 to ${max} characters`);

export const ThreadMessageItem = z
  .object({
    id: z.string().regex(UUID).transform((value) => value.toLowerCase()),
    sender: z.enum(["user", "doddy"]),
    text: words(THREAD_TEXT_MAX),
    createdAt: z.string().regex(ISO_INSTANT).refine((value) => !Number.isNaN(Date.parse(value)), "not a time"),
    /** Only a user message that was answered or is still on its way is worth showing; the phone sends those it has. */
    delivery: z.enum(["sending", "sent", "failed"]).optional(),
    hasPhoto: z.boolean().optional(),
    file: z.object({ name: words(200), kind: z.enum(FILE_KINDS) }).strict().optional(),
  })
  .strict();
export type ThreadMessageItem = z.output<typeof ThreadMessageItem>;

export const ThreadSnapshot = z
  .object({ messages: z.array(ThreadMessageItem).max(THREAD_MAX_MESSAGES) })
  .strict()
  .refine((snapshot) => new Set(snapshot.messages.map((m) => m.id)).size === snapshot.messages.length, "a message appears twice");

export interface ThreadView {
  messages: ThreadMessageItem[];
  /** When the iPhone last sent the thread; null before the first time. */
  syncedAt: string | null;
}
