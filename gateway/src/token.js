import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

// Bearer token for an invited anonymous device: v1.<payload>.<hmac>. No account, no profile.
// payload = {did: deviceId, inv: inviteTag, iat, exp} (seconds).

/** @param {Uint8Array | string} buf */
const b64 = (buf) => Buffer.from(buf).toString('base64url');

/** Keyed with the server secret, so a token holder cannot test guessed invite codes offline. */
export function inviteTag(/** @type {string} */ code, /** @type {string} */ secret) {
  return createHmac('sha256', secret).update(`invite:${code}`).digest('hex').slice(0, 16);
}

/** Short non-reversible tag for logs. Never log the id itself. */
export function shortTag(/** @type {string} */ kind, /** @type {string} */ value) {
  return createHash('sha256').update(`${kind}:${value}`).digest('hex').slice(0, 8);
}

export const deviceTag = (/** @type {string} */ deviceId) => shortTag('device', deviceId);

/** @param {string} payloadB64 @param {string} secret */
function sign(payloadB64, secret) {
  return createHmac('sha256', secret).update(`v1.${payloadB64}`).digest();
}

/** @param {{deviceId: string, inviteTag: string}} claims @param {string} secret @param {number} nowSec @param {number} ttlSec */
export function issueToken(claims, secret, nowSec, ttlSec) {
  const payload = b64(JSON.stringify({ did: claims.deviceId, inv: claims.inviteTag, iat: nowSec, exp: nowSec + ttlSec }));
  return { token: `v1.${payload}.${b64(sign(payload, secret))}`, expiresAtMs: (nowSec + ttlSec) * 1000 };
}

/** @param {string} token @param {string} secret @param {number} nowSec @returns {{deviceId: string, inviteTag: string, exp: number} | null} */
export function verifyToken(token, secret, nowSec) {
  const parts = token.split('.');
  if (parts.length !== 3 || parts[0] !== 'v1') return null;
  const expected = sign(parts[1], secret);
  let given;
  try { given = Buffer.from(parts[2], 'base64url'); } catch { return null; }
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  try {
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (typeof claims.did !== 'string' || typeof claims.inv !== 'string') return null;
    if (!Number.isInteger(claims.exp) || claims.exp <= nowSec) return null;
    return { deviceId: claims.did, inviteTag: claims.inv, exp: claims.exp };
  } catch {
    return null;
  }
}
