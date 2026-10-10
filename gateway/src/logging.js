// Content-free logging (acceptance A-16). Only whitelisted, primitive, non-text fields can be logged,
// so a future edit cannot accidentally write a question, note, token, or provider body to the logs.

const ALLOWED = new Set([
  'evt', 'requestId', 'deviceTag', 'status', 'code', 'ms', 'inputTokens', 'outputTokens',
  'memoryCount', 'turnCount', 'providerStatus', 'configMissing', 'cause', 'costMicros',
]);

// Values are constrained by shape too, so free text cannot ride in under an allowed key.
const SHAPES = /** @type {Record<string, RegExp>} */ ({
  evt: /^(assist|register|startup)$/,
  requestId: /^[0-9a-f]{8}$/,
  deviceTag: /^[0-9a-f]{8}$/,
  code: /^[A-Za-z]{3,24}$/,
  cause: /^[A-Za-z]{3,24}$/,
});
const NUMBERS = new Set(['status', 'ms', 'inputTokens', 'outputTokens', 'memoryCount', 'turnCount', 'providerStatus', 'costMicros']);

/** @param {Record<string, unknown>} fields */
export function sanitize(fields) {
  /** @type {Record<string, string|number|string[]>} */
  const out = {};
  for (const [key, value] of Object.entries(fields)) {
    if (!ALLOWED.has(key)) continue;
    if (NUMBERS.has(key)) {
      if (typeof value === 'number' && Number.isInteger(value) && value >= 0) out[key] = value;
    } else if (key === 'configMissing') {
      if (Array.isArray(value)) out[key] = value.filter((v) => typeof v === 'string' && /^[A-Z_]{1,40}$/.test(v));
    } else if (typeof value === 'string' && SHAPES[key]?.test(value)) {
      out[key] = value;
    }
  }
  return out;
}

/** @param {Record<string, unknown>} fields @param {(line: string) => void} [sink] */
export function logEvent(fields, sink = (line) => console.log(line)) {
  sink(JSON.stringify(sanitize(fields)));
}
