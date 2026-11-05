import { AppError } from "../errors.js";
import { refuse } from "../memory/contract.js";
import type { MemoryCipher } from "../memory/crypto.js";
import type { Store } from "../store.js";
import { type ThreadMessageItem, ThreadSnapshot, type ThreadView } from "./contract.js";

/**
 * The Messages copy for Doddy Web: encrypted on the way in with the same key and cipher as kept memory (ADR-603,
 * encryption at rest, not end-to-end), decrypted on the way out, always for the caller's own user id. Logs carry
 * counts only.
 */
const aad = (userId: string) => `${userId}:thread`;
const UNSET = "Showing Messages on the web isn't set up on this server.";

export class ThreadService {
  constructor(
    private readonly deps: {
      store: Store;
      cipher: MemoryCipher | null;
      now?: () => number;
      log?: (line: Record<string, unknown>) => void;
    },
  ) {}

  private now = () => this.deps.now?.() ?? Date.now();
  private cipher(): MemoryCipher {
    if (!this.deps.cipher) throw new AppError("live_not_configured", { message: UNSET });
    return this.deps.cipher;
  }

  /** Replaces the kept copy with this snapshot, oldest first. An empty snapshot deletes it. */
  async replace(userId: string, body: unknown): Promise<{ stored: true; count: number }> {
    const parsed = ThreadSnapshot.safeParse(body);
    if (!parsed.success) refuse(parsed.error);
    const cipher = this.cipher();
    const messages = [...parsed.data.messages].sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
    if (messages.length === 0) {
      await this.deps.store.deleteMessageThread(userId);
    } else {
      await this.deps.store.putMessageThread(userId, {
        key_version: cipher.keyVersion,
        ciphertext: cipher.encrypt(JSON.stringify(messages), aad(userId)),
        message_count: messages.length,
        received_at: this.now(),
      });
    }
    this.deps.log?.({ level: "info", event: "thread_synced", count: messages.length });
    return { stored: true, count: messages.length };
  }

  async read(userId: string): Promise<ThreadView> {
    const row = await this.deps.store.messageThread(userId);
    if (!row) return { messages: [], syncedAt: null };
    try {
      const messages = JSON.parse(this.cipher().decrypt(row.ciphertext, aad(userId))) as ThreadMessageItem[];
      return { messages, syncedAt: new Date(Number(row.received_at)).toISOString() };
    } catch (error) {
      if (error instanceof AppError) throw error;
      // Another key or altered bytes: nothing is shown half-read.
      this.deps.log?.({ level: "warn", event: "thread_unreadable" });
      return { messages: [], syncedAt: new Date(Number(row.received_at)).toISOString() };
    }
  }

  /** Deletes the copy and reads back that it is gone. */
  async deleteAll(userId: string): Promise<{ deleted: true }> {
    await this.deps.store.deleteMessageThread(userId);
    if (await this.deps.store.messageThread(userId)) throw new AppError("internal", { message: "The copy on Doddy's server couldn't be confirmed deleted. Try again." });
    return { deleted: true };
  }
}
