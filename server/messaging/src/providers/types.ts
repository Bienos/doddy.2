/**
 * Outcome of handing one message to a provider.
 * - accepted:  the provider took it (we have its id).
 * - rejected:  the provider refused it for good (bad number, unsubscribed, bad token…).
 * - transient: the provider refused it *before* accepting (429/5xx); safe to try again later.
 * - unknown:   the request may or may not have been accepted (timeout, connection drop).
 *              Never retried automatically, so the user is not messaged twice.
 */
export type SendOutcome =
  | { kind: "accepted"; providerId: string }
  | { kind: "rejected"; code: string; deviceGone?: boolean; unsubscribed?: boolean }
  | { kind: "transient"; code: string }
  | { kind: "unknown"; code: string };

export interface PushTarget { deviceToken: string; environment: "sandbox" | "production" }

export interface PushSender {
  send(target: PushTarget, alert: { title: string; body: string }, messageId: string): Promise<SendOutcome>;
}

export interface SmsSender {
  send(toE164: string, body: string): Promise<SendOutcome>;
}

export type VerifyCheck = "approved" | "wrong_code" | "expired_or_missing";

export interface PhoneVerifier {
  start(toE164: string): Promise<void>;
  check(toE164: string, code: string): Promise<VerifyCheck>;
}

export type CallOutcome =
  | { kind: "accepted"; conversationId?: string; callSid?: string }
  | { kind: "rejected"; code: string }
  | { kind: "unknown"; code: string };

/** Asks the phone agent to ring a number, passing the call's dynamic variables. */
export interface OutboundCaller {
  placeCall(toE164: string, dynamicVariables: Record<string, string>): Promise<CallOutcome>;
}

export class ProviderError extends Error {
  constructor(readonly code: string, readonly status?: number) {
    super(`provider error ${code}${status ? ` (HTTP ${status})` : ""}`);
  }
}
