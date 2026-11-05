// Who may read what the other side said on a call (ADR-730). The words are the owner's logs: the account that
// verified one of the numbers in CALL_TRANSCRIPT_PHONE_NUMBERS gets the live words and the saved transcript; every
// other account gets the answer (summary, quote, next step, confidence) and never the words. Empty list: nobody.
import type { TaskCallContext } from "./context.js";

export async function mayReadTranscripts(ctx: TaskCallContext, accountId: string): Promise<boolean> {
  const numbers = ctx.settings.transcriptPhoneNumbers ?? [];
  if (numbers.length === 0) return false;
  // A number is on `phone_numbers` only once its owner has verified it with a code, so this is the person who holds it.
  const { rowCount } = await ctx.db.query("SELECT 1 FROM phone_numbers WHERE account_id = $1 AND e164 = ANY($2::text[])", [accountId, numbers]);
  return (rowCount ?? 0) > 0;
}

/**
 * The answer card for an account that may not read the transcript: the same card with `transcript` emptied.
 * The app already shows a card with no transcript, and a warning's line reference that points at nothing is not shown.
 */
export function withoutTranscript(mayRead: boolean, card: unknown): unknown {
  if (mayRead || card === null || typeof card !== "object") return card;
  return { ...(card as Record<string, unknown>), transcript: [] };
}
