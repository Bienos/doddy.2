import { MESSAGE, STATUS } from './errors.js';

const BASE_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
};

/** @param {number} status @param {unknown} body */
export function json(status, body, extra = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...BASE_HEADERS, ...extra } });
}

/**
 * @param {import('./errors.js').ErrorCode} code
 * @param {{requestId?: string, retryAfterSeconds?: number}} [opts]
 */
export function errorResponse(code, opts = {}) {
  /** @type {Record<string, unknown>} */
  const error = { code, message: MESSAGE[code] };
  const headers = {};
  if (opts.retryAfterSeconds !== undefined) {
    error.retryAfterSeconds = opts.retryAfterSeconds;
    /** @type {Record<string,string>} */ (headers)['retry-after'] = String(opts.retryAfterSeconds);
  }
  /** @type {Record<string, unknown>} */
  const body = { schemaVersion: 1, error };
  if (opts.requestId) body.requestId = opts.requestId;
  return json(STATUS[code], body, headers);
}

/**
 * Reads a JSON body without ever buffering more than `maxBytes`.
 * @returns {Promise<{ok: true, value: unknown} | {ok: false, code: 'payloadTooLarge'|'invalidRequest'}>}
 */
export async function readJson(/** @type {Request} */ request, /** @type {number} */ maxBytes) {
  const type = request.headers.get('content-type') ?? '';
  if (!type.toLowerCase().startsWith('application/json')) return { ok: false, code: 'invalidRequest' };
  const declared = Number(request.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > maxBytes) return { ok: false, code: 'payloadTooLarge' };
  if (!request.body) return { ok: false, code: 'invalidRequest' };

  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return { ok: false, code: 'payloadTooLarge' };
    }
    chunks.push(value);
  }
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, code: 'invalidRequest' };
  }
}

/** @param {Request} request */
export function bearerToken(request) {
  const header = request.headers.get('authorization') ?? '';
  const match = /^Bearer ([A-Za-z0-9._-]{10,2048})$/.exec(header);
  return match ? match[1] : null;
}

/** One IPv6 /64 is one household/host; without this an attacker gets 2^64 free rate-limit buckets. */
function ipv6Prefix64(/** @type {string} */ address) {
  const [head, tail = ''] = address.toLowerCase().split('::');
  const first = head ? head.split(':') : [];
  const rest = tail ? tail.split(':') : [];
  const groups = address.includes('::') ? [...first, ...Array(Math.max(0, 8 - first.length - rest.length)).fill('0'), ...rest] : first;
  return groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, '') || '0').join(':') + '::/64';
}

/** Best-effort client address (Vercel sets these headers; do not rely on them behind another proxy) for rate limiting only; never logged in clear. */
/** @param {Request} request */
export function clientAddress(request) {
  const forwarded = request.headers.get('x-vercel-forwarded-for') ?? request.headers.get('x-real-ip') ?? '';
  const address = forwarded.split(',')[0].trim() || 'unknown';
  // An IPv4 client seen through IPv6 (::ffff:a.b.c.d) is that IPv4 address, not one shared /64.
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(address);
  if (mapped) return mapped[1];
  return address.includes(':') ? ipv6Prefix64(address) : address;
}
