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
 *
 * ASK-01's two exceptions don't pass through this gate: they run on the messaging server, where
 * the approval is the digest of exactly the job on the card. Errands (ADR-570): one yes covers
 * that task's web searches and page reads. Studio (ADR-740): one yes covers that job's capped web
 * look-ups and the making of its files in Anthropic's container. Their tool lists are pinned by
 * scripts/check_forbidden_capabilities.sh; nothing in this backend can widen them.
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
   * True when `prepare` issued this approval to this user for this tool and account, and it is unused and
   * unexpired, whatever it is bound to. A write with a lookup is bound to what the lookup finds, so it can
   * only be checked in full after the lookup; this is the check that comes first, so a run that never had
   * a card can't be used to look things up (ADR-708).
   */
  issuedFor(binding: Pick<AskBinding, "userId" | "tool" | "accountId">, approvalId: string | undefined): Promise<boolean> {
    if (approvalId === undefined) return Promise.resolve(false);
    return this.store.approvalIssuedFor({ approvalId, userId: binding.userId, capability: binding.tool, accountId: binding.accountId, now: this.now() });
  }

  /**
   * A write's run takes its approval before anything else, its lookup included, so only one run can have
   * it: a repeat that arrives meanwhile finds it taken and is answered from the first try instead of
   * racing it. Taken only when `prepare` issued it to this user for this tool and account, unexpired,
   * unused and not taken, and (when `argsDigest` isn't null: a write without a lookup) for exactly these
   * arguments. `requestDigest` is what this run asks for, kept so a repeat is held to the same request.
   * Null when it wasn't taken; otherwise the time it was taken, which `giveBack` needs.
   */
  async take(
    binding: Pick<AskBinding, "userId" | "tool" | "accountId"> & { argsDigest: string | null },
    approvalId: string | undefined,
    requestDigest: string,
  ): Promise<{ startedAt: number } | null> {
    if (approvalId === undefined) return null;
    const startedAt = this.now();
    const took = await this.store.startApproval({
      approvalId, userId: binding.userId, capability: binding.tool, accountId: binding.accountId, argsDigest: binding.argsDigest, requestDigest, now: startedAt,
    });
    return took ? { startedAt } : null;
  }

  /** A taken approval whose write was never sent (a limit, busy, the lookup): the user's yes works again. */
  giveBack(approvalId: string, startedAt: number): Promise<void> {
    return this.store.releaseApproval(approvalId, startedAt);
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
