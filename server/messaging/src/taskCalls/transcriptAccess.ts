// Who may read what the other side said on a call (ADR-730). The words are the owner's logs: an account on
// CALL_TRANSCRIPT_ACCOUNT_IDS gets the live words and the saved transcript; every other account gets the answer
// (summary, quote, next step, confidence) and never the words. Empty list: nobody.
import type { TaskCallContext } from "./context.js";

export function mayReadTranscripts(ctx: TaskCallContext, accountId: string): boolean {
  return (ctx.settings.transcriptAccountIds ?? []).includes(accountId.toLowerCase());
}

/**
 * The answer card for an account that may not read the transcript: the same card with `transcript` emptied.
 * The app already shows a card with no transcript, and a warning's line reference that points at nothing is not shown.
 */
export function withoutTranscript(ctx: TaskCallContext, accountId: string, card: unknown): unknown {
  if (mayReadTranscripts(ctx, accountId) || card === null || typeof card !== "object") return card;
  return { ...(card as Record<string, unknown>), transcript: [] };
}
