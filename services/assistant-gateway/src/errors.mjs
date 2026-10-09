// Error taxonomy from docs/architecture/AI_RUNTIME.md, plus two codes the spec implies but does not list:
// `badRequest` (contract violation) and `invalidResponse` (model reply not in the expected shape).

export const STATUS_FOR_CODE = Object.freeze({
  badRequest: 400,
  notAuthorized: 401,
  rateLimited: 429,
  providerUnavailable: 503,
  timeout: 504,
  invalidCitations: 502,
  invalidResponse: 502,
});

export class GatewayError extends Error {
  constructor(code) {
    if (!(code in STATUS_FOR_CODE)) throw new Error(`unknown error code ${code}`);
    super(code);
    this.name = "GatewayError";
    this.code = code;
  }
}
