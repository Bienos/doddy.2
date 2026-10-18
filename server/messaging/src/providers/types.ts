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

/**
 * Outcome of asking the phone provider to ring someone.
 * - accepted: the provider took the call (we have its CallSid).
 * - rejected: the provider refused it, so nothing rang.
 * - unknown:  the call may or may not have been placed. Never redialled automatically.
 */
export type CallOutcome =
  | { kind: "accepted"; callSid: string }
  | { kind: "rejected"; code: string }
  | { kind: "unknown"; code: string };

export interface OutboundCall {
  to: string;
  from: string;
  /** Asked for TwiML once the call is answered. */
  answerUrl: string;
  /** Receives how the call went: ringing, answered, completed, busy, no answer… */
  statusCallbackUrl: string;
}

/** Rings someone from Doddy's own number (Twilio, ADR-490). */
export interface OutboundCaller {
  placeCall(call: OutboundCall): Promise<CallOutcome>;
}

export type RegisterOutcome = { kind: "twiml"; twiml: string } | { kind: "failed"; code: string };

/** Hands an answered call to the phone agent and returns the TwiML that connects it (ElevenLabs register-call). */
export interface CallRegistrar {
  register(call: {
    from: string; to: string; direction: "inbound" | "outbound"; variables: Record<string, string>;
  }): Promise<RegisterOutcome>;
}

export class ProviderError extends Error {
  constructor(readonly code: string, readonly status?: number) {
    super(`provider error ${code}${status ? ` (HTTP ${status})` : ""}`);
  }
}
