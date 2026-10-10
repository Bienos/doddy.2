// Error taxonomy shared with the app (docs/architecture/AI_RUNTIME.md). Codes are the wire values.

/** @typedef {'notAuthorized'|'rateLimited'|'providerUnavailable'|'timeout'|'invalidRequest'|'payloadTooLarge'|'invalidCitations'|'refused'|'notConfigured'|'dailyLimitReached'} ErrorCode */

/** @type {Record<ErrorCode, number>} */
export const STATUS = {
  invalidRequest: 400,
  notAuthorized: 401,
  payloadTooLarge: 413,
  rateLimited: 429,
  dailyLimitReached: 429,
  invalidCitations: 502,
  refused: 422,
  providerUnavailable: 503,
  notConfigured: 503,
  timeout: 504,
};

/** Fixed, content-free messages. Never echo request text or provider error bodies. */
/** @type {Record<ErrorCode, string>} */
export const MESSAGE = {
  invalidRequest: 'The request was not valid.',
  notAuthorized: 'This device is not authorized.',
  payloadTooLarge: 'The request was too large.',
  rateLimited: 'Too many requests. Try again shortly.',
  dailyLimitReached: "Doddy's daily limit is reached; try again tomorrow.",
  invalidCitations: 'The answer could not be checked against your notes.',
  refused: 'The assistant declined to answer that.',
  providerUnavailable: 'The assistant is unavailable right now.',
  notConfigured: 'The assistant is not set up yet.',
  timeout: 'The assistant took too long to answer.',
};
