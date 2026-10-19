import type { Store } from "../store.js";

/**
 * ASK-01 (ADR-483), the owner's rule: Doddy never acts without asking first. Every tool, reads
 * included, runs only with a single-use approval that `prepare` made for exactly these arguments
 * after showing what it will do. This is the one place that says yes or no; `run` and the web
 * search both call it, and a mutation check (docs/trust/ASK_FIRST.md) shows the tests fail
 * without it.
 *
 * What the server can and can't know: it can't hear the user. It can make sure nothing runs
 * without an approval it issued for this user, this tool, this account and these exact
 * arguments, used once, within two minutes. That the app only sends the approval after the
 * user's yes (a tap on the card for anything that changes something) is the app's half.
 */

export const ASK_TTL_SECONDS = 120;

/** The account an approval is bound to for web search, which has none. */
export const WEB_ACCOUNT = "websearch";

export interface AskBinding {
  userId: string;
  /** Doddy's tool name, e.g. "check_email". */
  tool: string;
  /** The connection id (or WEB_ACCOUNT). */
  accountId: string;
  /** argumentDigest of the validated arguments (plus the looked-up target for a write with one). */
  argsDigest: string;
}

export class AskGate {
  constructor(
    private readonly store: Store,
    private readonly now: () => number,
  ) {}

  /** After the card is made: the approval the app sends back once the user said yes. */
  issue(binding: AskBinding): Promise<{ approvalId: string; expiresAt: number }> {
    return this.store.createApproval({
      userId: binding.userId,
      capability: binding.tool,
      accountId: binding.accountId,
      argsDigest: binding.argsDigest,
      now: this.now(),
      ttlSeconds: ASK_TTL_SECONDS,
    });
  }

  /**
   * True only for an approval issued for exactly this binding, unexpired and unused. "check"
   * leaves it unused (a refusal before the provider call shouldn't cost the user their yes);
   * "use" uses it up atomically, so two runs with one approval can't both pass.
   */
  async allows(binding: AskBinding, approvalId: string | undefined, mode: "check" | "use"): Promise<boolean> {
    if (approvalId === undefined) return false;
    return this.store.consumeApproval(
      {
        approvalId,
        userId: binding.userId,
        capability: binding.tool,
        accountId: binding.accountId,
        argsDigest: binding.argsDigest,
        now: this.now(),
      },
      { checkOnly: mode === "check" },
    );
  }
}
