import type { ConnectOffer, ErrorCode, Receipt } from "./contracts.js";
import type { ToolReceipt } from "./tools/contracts.js";

const HTTP_STATUS: Record<ErrorCode, number> = {
  unauthenticated: 401,
  invalid_request: 400,
  not_found: 404,
  payload_too_large: 413,
  not_connected: 409,
  permission_insufficient: 403,
  connection_expired: 409,
  capability_disabled: 403,
  attempt_invalid: 400,
  rate_limited: 429,
  quota_exceeded: 429,
  busy: 429,
  provider_unavailable: 502,
  provider_timeout: 504,
  malformed_provider_result: 502,
  live_not_configured: 503,
  internal: 500,
};

/** Plain, content-free messages. Provider error text is never forwarded to the client. */
const MESSAGES: Record<ErrorCode, string> = {
  unauthenticated: "Sign-in is required.",
  invalid_request: "The request was not valid.",
  not_found: "Not found.",
  payload_too_large: "The request was too large.",
  not_connected: "Google Calendar is not connected.",
  permission_insufficient: "This connection doesn't have the right access. Reconnect Google Calendar with read-only access.",
  connection_expired: "Google Calendar access expired or was removed. Reconnect to continue.",
  capability_disabled: "This action isn't available.",
  attempt_invalid: "That connection attempt is no longer valid. Start again.",
  rate_limited: "Google Calendar is busy right now. Try again shortly.",
  quota_exceeded: "Doddy's usage limit for calendar checks was reached. Try again later.",
  busy: "Another calendar check is still running.",
  provider_unavailable: "Google Calendar couldn't be reached. Nothing was changed.",
  provider_timeout: "Google Calendar took too long to answer. Nothing was changed.",
  malformed_provider_result: "Google Calendar sent a result Doddy couldn't read, so nothing is shown.",
  live_not_configured: "Live connections are not set up on this server.",
  internal: "Something went wrong on Doddy's server.",
};

export class AppError extends Error {
  readonly status: number;
  constructor(
    readonly code: ErrorCode,
    readonly options: { retryAfterSeconds?: number; receipt?: Receipt | ToolReceipt; message?: string; connect?: ConnectOffer } = {},
  ) {
    super(options.message ?? MESSAGES[code]);
    this.name = "AppError";
    this.status = HTTP_STATUS[code];
  }
}

/** A provider failure translated into a safe code. `detail` stays server-side and content-free. */
export class ProviderError extends Error {
  constructor(
    readonly code: Extract<
      ErrorCode,
      "rate_limited" | "provider_unavailable" | "provider_timeout" | "malformed_provider_result" | "connection_expired" | "permission_insufficient"
    >,
    readonly retryAfterSeconds?: number,
  ) {
    super(code);
    this.name = "ProviderError";
  }

  get transient(): boolean {
    return this.code === "provider_unavailable" || this.code === "provider_timeout" || this.code === "rate_limited";
  }
}
