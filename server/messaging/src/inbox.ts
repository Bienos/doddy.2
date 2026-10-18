import { randomUUID } from "node:crypto";
import type pg from "pg";
import { MAX_PENDING_NOTES } from "./calls.js";
import type { TextCipher } from "./crypto.js";
import { inTransaction, type Db } from "./db.js";
import { searchMemories, type MemoryHit } from "./memorySearch.js";

// The notes inbox and the memory copy, shared by phone calls (routes/elevenlabs.ts) and texts to
// Doddy (textReplies.ts). A note is not a memory: it waits until the user confirms or discards it
// in the app (DOD-06).

/** call: Doddy took it on a call. text: the user's text, word for word. doddy: Claude wrote it while answering a text. */
export type NoteSource = "call" | "text" | "doddy";

/** Leaves a note in the inbox, encrypted. Undefined when the inbox is full (MAX_PENDING_NOTES). */
export async function saveNote(
  db: Db, cipher: TextCipher, accountId: string, text: string, source: NoteSource, conversationId: string | null = null,
): Promise<string | undefined> {
  return inTransaction(db, (c) => saveNoteIn(c, cipher, accountId, text, source, conversationId));
}

/** The same inside the caller's transaction, so the note and the caller's own row commit together. */
export async function saveNoteIn(
  c: pg.PoolClient, cipher: TextCipher, accountId: string, text: string, source: NoteSource, conversationId: string | null = null,
): Promise<string | undefined> {
  const id = randomUUID();
  // Serialises notes per account so parallel tool calls can't overfill the inbox.
  await c.query("SELECT pg_advisory_xact_lock(hashtext('call_notes:' || $1))", [accountId]);
  const { rows } = await c.query<{ n: number }>(
    "SELECT count(*)::int AS n FROM call_notes WHERE account_id = $1", [accountId]);
  if ((rows[0]?.n ?? 0) >= MAX_PENDING_NOTES) return undefined;
  await c.query(
    `INSERT INTO call_notes (id, account_id, key_version, ciphertext, conversation_id, source) VALUES ($1, $2, $3, $4, $5, $6)`,
    [id, accountId, cipher.keyVersion, cipher.encrypt(text, `${accountId}:note:${id}`), conversationId, source]);
  return id;
}

/** True when the user has turned on the memory copy (Settings → Phone calls → Memory on calls). */
export async function memoryCopyOn(db: Db, accountId: string): Promise<boolean> {
  const { rows } = await db.query<{ on: boolean }>(
    "SELECT memory_copy_enabled_at IS NOT NULL AS on FROM call_settings WHERE account_id = $1", [accountId]);
  return rows[0]?.on ?? false;
}

/** Searches the user's memory copy. A row that won't decrypt (after a key change) is skipped. */
export async function searchMemoryCopy(db: Db, cipher: TextCipher, accountId: string, query: string): Promise<MemoryHit[]> {
  const { rows } = await db.query<{ memory_id: string; ciphertext: Buffer; captured_at: Date | null }>(
    "SELECT memory_id, ciphertext, captured_at FROM memory_copies WHERE account_id = $1", [accountId]);
  const memories = rows.flatMap((r) => {
    try {
      return [{ id: r.memory_id, text: cipher.decrypt(r.ciphertext, `${accountId}:memory:${r.memory_id}`), capturedAt: r.captured_at }];
    } catch {
      return [];
    }
  });
  return searchMemories(memories, query);
}

/** A memory as a tool may quote it: the text and the day it was saved. */
export const quotedMemory = (h: MemoryHit) => ({
  text: h.text, saved: h.capturedAt ? h.capturedAt.toISOString().slice(0, 10) : "date unknown",
});
