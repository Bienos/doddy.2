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
  /**
   * The provider's most recent messages to this number, newest first, to settle an unknown
   * outcome (DOD-09). Undefined when the provider couldn't be asked.
   */
  recentMessagesTo?(toE164: string): Promise<{ sid: string; body: string; createdAt: Date; status: string }[] | undefined>;
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

/**
 * Deleting one of Doddy's records at the phone provider (Twilio, ADR-494).
 * - deleted: gone (also when the provider had no such record).
 * - retry:   not yet (Twilio 20009: the record isn't final yet), rate limited, or no answer.
 * - failed:  refused for good; not tried again.
 */
export type DeleteOutcome = { kind: "deleted" } | { kind: "retry"; code: string } | { kind: "failed"; code: string };

export interface RecordDeleter {
  deleteRecord(kind: "message" | "call", sid: string): Promise<DeleteOutcome>;
}

/** What a reply to one text may use. search is absent unless the user allowed memories in replies. */
export interface TextReplyTools {
  searchMemories?: (query: string) => Promise<{ text: string; saved: string }[]>;
  /** "saved" only after the note is stored; it still waits for the user's confirmation in the app. */
  saveNote: (text: string) => Promise<"saved" | "inbox_full">;
}

export interface TextReplyRequest {
  /** The user's text, exactly as received. */
  text: string;
  /** The language of the user's settings; the reply follows the text's own language. */
  language: "en" | "pl";
  receivedAt: Date;
  maxSegments: number;
}

/**
 * - reply:    the answer, at most maxSegments SMS parts.
 * - too_long: the model's answer stayed too long after one request to shorten it.
 * - failed:   no usable answer (provider error, refusal, cut off, no text).
 * costMicroUsd is an estimate from the tokens used, at the model's list price.
 */
export type TextReplyOutcome =
  | { kind: "reply"; text: string; costMicroUsd: number }
  | { kind: "too_long"; costMicroUsd: number }
  | { kind: "failed"; code: string; costMicroUsd: number };

/** Writes Doddy's reply to the user's text (Claude, ADR-494). */
export interface TextReplyWriter {
  readonly provider: "anthropic";
  reply(request: TextReplyRequest, tools: TextReplyTools): Promise<TextReplyOutcome>;
}

export class ProviderError extends Error {
  constructor(readonly code: string, readonly status?: number) {
    super(`provider error ${code}${status ? ` (HTTP ${status})` : ""}`);
  }
}
