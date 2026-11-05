import { AppError } from "../errors.js";
import type { MemoryConversationRow, MemoryNoteRow, Store } from "../store.js";
import {
  type ConversationSummary,
  ConversationUpload,
  type ConversationView,
  keptSince,
  MEMORY_KEPT_DAYS,
  MEMORY_MAX_CONVERSATION_BYTES,
  MEMORY_MAX_CONVERSATIONS,
  type MemoryOverview,
  MemoryStateBody,
  type NoteView,
  NotesSnapshot,
  ONE_DAY_MS,
  refuse,
  type Turn,
} from "./contract.js";
import type { MemoryCipher } from "./crypto.js";
import { rankConversations, rankNotes, type ConversationExcerpt } from "./search.js";

/**
 * Notes and conversations kept on request (ADR-603): the one place that encrypts them on the way
 * in and decrypts them on the way out. Everything is keyed by the caller's user id. A row that no
 * longer decrypts or reads is left out and counted in the log, never shown half-read. Logs carry
 * counts only, never a word of what is kept.
 */

const UNSET = "Keeping notes and conversations on Doddy's server isn't set up on this server.";
/**
 * A small per-user limit on the reads that decrypt a lot (searching notes, downloading everything),
 * so one account can't keep the server busy. Kept in this process's memory: the service runs as one
 * instance, and a restart only forgets who was close to the limit.
 */
class ReadLimiter {
  private readonly hits = new Map<string, number[]>();
  constructor(
    private readonly max: number,
    private readonly windowMs: number,
  ) {}
  take(userId: string, now: number): boolean {
    const recent = (this.hits.get(userId) ?? []).filter((at) => now - at < this.windowMs);
    if (recent.length >= this.max) {
      this.hits.set(userId, recent);
      return false;
    }
    recent.push(now);
    this.hits.set(userId, recent);
    if (this.hits.size > 10_000) for (const [id, times] of this.hits) if (times.every((at) => now - at >= this.windowMs)) this.hits.delete(id);
    return true;
  }
}

const tick = () => new Promise<void>((resolve) => setImmediate(resolve));
const noteAad = (userId: string, id: string) => `${userId}:note:${id}`;
const conversationAad = (userId: string, id: string) => `${userId}:conversation:${id}`;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export interface NoteBlob {
  text: string;
  source: NoteView["source"];
  kind?: NoteView["kind"];
  capturedAt?: string;
}
interface ConversationBlob {
  language?: string;
  endedBy?: ConversationView["endedBy"];
  turns: Turn[];
}

export class MemoryService {
  private readonly reads = new ReadLimiter(20, 60_000);

  constructor(
    private readonly deps: {
      store: Store;
      cipher: MemoryCipher | null;
      /** What one person can keep. Default: `MEMORY_MAX_CONVERSATIONS` and `MEMORY_MAX_CONVERSATION_BYTES`. */
      limits?: { conversations: number; bytes: number };
      now?: () => number;
      log?: (line: Record<string, unknown>) => void;
    },
  ) {}

  /** Whether a key is set, so callers can refuse before spending anything. */
  isConfigured(): boolean {
    return this.deps.cipher !== null;
  }

  private spendRead(userId: string): void {
    if (!this.reads.take(userId, this.now())) {
      throw new AppError("rate_limited", { retryAfterSeconds: 30, message: "Too many searches or downloads in a short time. Try again in a minute." });
    }
  }

  /** A row that no longer reads (another key, altered bytes) is left out; how many is logged, never what. */
  private noteUnreadable(what: "notes" | "conversations", count: number): void {
    if (count > 0) this.deps.log?.({ level: "warn", event: "memory_unreadable", kind: what, count });
  }

  /** Every note of one user, decrypted, giving the event loop a turn now and then. */
  private async readAllNotes(userId: string): Promise<{ notes: (NoteView & { capturedMs: number | null })[]; unreadable: number }> {
    const rows = await this.deps.store.memoryNoteRows(userId);
    const notes: (NoteView & { capturedMs: number | null })[] = [];
    let unreadable = 0;
    for (let i = 0; i < rows.length; i += 1) {
      const note = this.readNote(userId, rows[i]!);
      if (note) notes.push(note);
      else unreadable += 1;
      if (i % 200 === 199) await tick();
    }
    this.noteUnreadable("notes", unreadable);
    return { notes, unreadable };
  }

  private now = () => this.deps.now?.() ?? Date.now();
  private cipher(): MemoryCipher {
    if (!this.deps.cipher) throw new AppError("live_not_configured", { message: UNSET });
    return this.deps.cipher;
  }
  private off(what: string): never {
    throw new AppError("capability_disabled", { message: `Keeping ${what} on Doddy's server is off for this iPhone. Turn it on in Doddy first. Nothing was stored.` });
  }

  /** The switches, what is kept, and when the iPhone last sent. Works without a key (it only counts). */
  async overview(userId: string): Promise<MemoryOverview> {
    const [state, counts] = await Promise.all([this.deps.store.memoryState(userId), this.deps.store.memoryCounts(userId, keptSince(this.now()))]);
    return {
      notes: state.notes,
      conversations: state.conversations,
      noteCount: counts.notes,
      conversationCount: counts.conversations,
      keptDays: MEMORY_KEPT_DAYS,
      lastSyncedAt: counts.lastReceivedAt === null ? null : new Date(counts.lastReceivedAt).toISOString(),
    };
  }

  async setState(userId: string, body: unknown) {
    const parsed = MemoryStateBody.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");
    const deleted = await this.deps.store.setMemoryState(userId, parsed.data, this.now());
    return { ...parsed.data, ...deleted };
  }

  async replaceNotes(userId: string, body: unknown): Promise<{ count: number }> {
    const cipher = this.cipher();
    const parsed = NotesSnapshot.safeParse(body);
    if (!parsed.success) return refuse(parsed.error);
    const rows: MemoryNoteRow[] = parsed.data.items.map((item) => {
      const blob: NoteBlob = { text: item.text, source: item.source, ...(item.kind ? { kind: item.kind } : {}), ...(item.capturedAt ? { capturedAt: item.capturedAt } : {}) };
      return {
        note_id: item.id,
        key_version: cipher.keyVersion,
        ciphertext: cipher.encrypt(JSON.stringify(blob), noteAad(userId, item.id)),
        captured_at: item.capturedAt ? Date.parse(item.capturedAt) : null,
        received_at: this.now(),
      };
    });
    if (!(await this.deps.store.replaceMemoryNotes(userId, rows, this.now()))) return this.off("notes");
    this.deps.log?.({ level: "info", event: "memory_notes_replaced", count: rows.length });
    return { count: rows.length };
  }

  async putConversation(userId: string, rawId: string, body: unknown): Promise<{ stored: true; id: string }> {
    const cipher = this.cipher();
    const id = rawId.toLowerCase();
    if (!UUID.test(id)) throw new AppError("not_found");
    const parsed = ConversationUpload.safeParse(body);
    if (!parsed.success) return refuse(parsed.error);
    const conversation = parsed.data;
    const now = this.now();
    const started = Date.parse(conversation.startedAt);
    if (started < keptSince(now) || Date.parse(conversation.endedAt) > now + ONE_DAY_MS) {
      throw new AppError("invalid_request", { message: `Conversations are kept ${MEMORY_KEPT_DAYS} days, up to tomorrow. Nothing was stored.` });
    }
    const blob: ConversationBlob = { ...(conversation.language ? { language: conversation.language } : {}), ...(conversation.endedBy ? { endedBy: conversation.endedBy } : {}), turns: conversation.turns };
    const stored = await this.deps.store.putMemoryConversation(
      userId,
      {
        conversation_id: id,
        started_at: started,
        ended_at: Date.parse(conversation.endedAt),
        turn_count: conversation.turns.length,
        key_version: cipher.keyVersion,
        ciphertext: cipher.encrypt(JSON.stringify(blob), conversationAad(userId, id)),
        received_at: now,
      },
      this.deps.limits ?? { conversations: MEMORY_MAX_CONVERSATIONS, bytes: MEMORY_MAX_CONVERSATION_BYTES },
    );
    if (stored === "off") return this.off("conversations");
    if (stored === "full") {
      throw new AppError("payload_too_large", { message: "Doddy's server is already keeping as many conversations as it can for this iPhone. Nothing was stored." });
    }
    this.deps.log?.({ level: "info", event: "memory_conversation_put", turns: conversation.turns.length });
    return { stored: true, id };
  }

  // ---------------------------------------------------------------- reading

  private readNote(userId: string, row: MemoryNoteRow): (NoteView & { capturedMs: number | null }) | null {
    try {
      const blob = JSON.parse(this.cipher().decrypt(row.ciphertext, noteAad(userId, row.note_id))) as NoteBlob;
      if (typeof blob.text !== "string") return null;
      return { id: row.note_id, text: blob.text, source: blob.source, kind: blob.kind ?? null, capturedAt: blob.capturedAt ?? null, capturedMs: row.captured_at };
    } catch {
      return null;
    }
  }

  private readConversation(userId: string, row: MemoryConversationRow): (ConversationView & { startedMs: number }) | null {
    try {
      const blob = JSON.parse(this.cipher().decrypt(row.ciphertext, conversationAad(userId, row.conversation_id))) as ConversationBlob;
      if (!Array.isArray(blob.turns)) return null;
      return {
        id: row.conversation_id,
        startedAt: new Date(row.started_at).toISOString(),
        endedAt: new Date(row.ended_at).toISOString(),
        language: blob.language ?? null,
        endedBy: blob.endedBy ?? null,
        turns: blob.turns,
        startedMs: row.started_at,
      };
    } catch {
      return null;
    }
  }

  /** Notes, newest first. `unreadable` counts rows left out because they no longer decrypt. */
  async listNotes(userId: string, o: { limit: number; offset: number }): Promise<{ notes: NoteView[]; total: number; nextOffset: number | null; unreadable: number }> {
    this.cipher();
    const rows = await this.deps.store.memoryNoteRows(userId);
    let unreadable = 0;
    const notes: (NoteView & { capturedMs: number | null })[] = [];
    // Only the page is decrypted.
    for (const row of rows.slice(o.offset, o.offset + o.limit)) {
      const note = this.readNote(userId, row);
      if (note) notes.push(note);
      else unreadable += 1;
    }
    this.noteUnreadable("notes", unreadable);
    return { notes: notes.map(stripMs), total: rows.length, nextOffset: o.offset + o.limit < rows.length ? o.offset + o.limit : null, unreadable };
  }

  /** Notes that match `q`, best first. Decrypts every note, so it is rate limited per person. */
  async searchNotes(userId: string, o: { q: string; limit: number; offset: number }): Promise<{ notes: NoteView[]; total: number; nextOffset: number | null; unreadable: number }> {
    this.cipher();
    this.spendRead(userId);
    const { notes: all, unreadable } = await this.readAllNotes(userId);
    const hits = rankNotes(all, o.q, all.length, pickNote);
    const page = hits.slice(o.offset, o.offset + o.limit);
    return { notes: page.map(stripMs), total: hits.length, nextOffset: o.offset + o.limit < hits.length ? o.offset + o.limit : null, unreadable };
  }

  async listConversations(userId: string, o: { limit: number; offset: number }): Promise<{ conversations: ConversationSummary[]; total: number; nextOffset: number | null; unreadable: number }> {
    this.cipher();
    const since = keptSince(this.now());
    const [rows, counts] = await Promise.all([this.deps.store.memoryConversationRows(userId, since, o.limit, o.offset), this.deps.store.memoryCounts(userId, since)]);
    const conversations: ConversationSummary[] = [];
    let unreadable = 0;
    for (const row of rows) {
      const view = this.readConversation(userId, row);
      if (!view) {
        unreadable += 1;
        continue;
      }
      const first = view.turns.find((turn) => turn.role === "user") ?? view.turns[0];
      conversations.push({
        id: view.id,
        startedAt: view.startedAt,
        endedAt: view.endedAt,
        turnCount: row.turn_count,
        language: view.language,
        endedBy: view.endedBy,
        preview: first ? [...first.text].slice(0, 140).join("") : "",
      });
    }
    this.noteUnreadable("conversations", unreadable);
    return { conversations, total: counts.conversations, nextOffset: o.offset + o.limit < counts.conversations ? o.offset + o.limit : null, unreadable };
  }

  async getConversation(userId: string, rawId: string): Promise<ConversationView> {
    this.cipher();
    const id = rawId.toLowerCase();
    const row = UUID.test(id) ? await this.deps.store.memoryConversationRow(userId, id) : null;
    const view = row && row.started_at >= keptSince(this.now()) ? this.readConversation(userId, row) : null;
    if (!view) throw new AppError("not_found");
    const { startedMs: _ignored, ...rest } = view;
    return rest;
  }

  async deleteConversation(userId: string, rawId: string): Promise<{ deleted: number }> {
    const id = rawId.toLowerCase();
    return { deleted: UUID.test(id) ? await this.deps.store.deleteMemoryConversation(userId, id) : 0 };
  }

  /** Deletes everything kept and switches both off. The iPhone's next send is refused, so it stops. */
  async deleteAll(userId: string) {
    return { notes: false, conversations: false, ...(await this.deps.store.deleteAllMemory(userId, this.now())) };
  }

  /** Everything kept, decrypted, for the person's own download. Bounded by what one person can keep; rate limited. */
  async exportAll(userId: string) {
    this.cipher();
    this.spendRead(userId);
    const since = keptSince(this.now());
    const [overview, noteResult, conversationRows] = await Promise.all([
      this.overview(userId),
      this.readAllNotes(userId),
      this.deps.store.memoryConversationRows(userId, since, MEMORY_MAX_CONVERSATIONS),
    ]);
    const conversations = [];
    let unreadable = noteResult.unreadable;
    for (let i = 0; i < conversationRows.length; i += 1) {
      const view = this.readConversation(userId, conversationRows[i]!);
      if (view) {
        const { startedMs: _ignored, ...rest } = view;
        conversations.push(rest);
      } else unreadable += 1;
      if (i % 50 === 49) await tick();
    }
    this.noteUnreadable("conversations", conversationRows.length - conversations.length);
    // The switches are named apart from the two lists, so neither hides the other.
    return {
      keptDays: overview.keptDays,
      lastSyncedAt: overview.lastSyncedAt,
      switches: { notes: overview.notes, conversations: overview.conversations },
      unreadable,
      notes: noteResult.notes.map(stripMs),
      conversations,
    };
  }

  /** What chat may read: the best-matching notes and conversation excerpts for one question. */
  async searchForChat(userId: string, query: string, o: { notes: number; conversations: number }): Promise<{ notes: NoteView[]; conversations: ConversationExcerpt[] }> {
    this.cipher();
    const state = await this.deps.store.memoryState(userId);
    const notes: NoteView[] = [];
    if (state.notes) {
      const { notes: all } = await this.readAllNotes(userId);
      notes.push(...rankNotes(all, query, o.notes, pickNote).map(stripMs));
    }
    let conversations: ConversationExcerpt[] = [];
    if (state.conversations) {
      // The newest 150 inside the window: enough to answer from, and a bound on how much is decrypted per question.
      const rows = await this.deps.store.memoryConversationRows(userId, keptSince(this.now()), 150);
      const all: { id: string; startedAt: number; turns: Turn[] }[] = [];
      for (let i = 0; i < rows.length; i += 1) {
        const view = this.readConversation(userId, rows[i]!);
        if (view) all.push({ id: view.id, startedAt: view.startedMs, turns: view.turns });
        if (i % 25 === 24) await tick();
      }
      this.noteUnreadable("conversations", rows.length - all.length);
      conversations = rankConversations(all, query, o.conversations);
    }
    return { notes, conversations };
  }

  async state(userId: string) {
    return this.deps.store.memoryState(userId);
  }
}

const pickNote = (note: { text: string; capturedMs: number | null }) => ({ text: note.text, capturedAt: note.capturedMs });

function stripMs<T extends { capturedMs?: number | null }>(note: T): Omit<T, "capturedMs"> {
  const { capturedMs: _ignored, ...rest } = note;
  return rest;
}
