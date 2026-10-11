// Strict request validation. Unknown fields are rejected so nothing the app was not meant to send
// can ride along (egress minimisation, acceptance A-16).

export const LIMITS = Object.freeze({
  // Above the worst case the scalar limits allow (26,000 four-byte scalars ≈ 104 KB plus JSON), so a
  // request within every field limit is never refused as too large.
  bodyBytes: 128 * 1024,
  userText: 2_000,
  turns: 6,
  turnText: 2_000,
  memories: 8,
  memoryText: 5_000,
  memoryTotal: 12_000,
});

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const LOCALE = /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$/;
const SOURCES = new Set(['explicit_text', 'explicit_voice', 'shared_content', 'imported_legacy_unknown']);
const ISO_DATE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

/** @param {string} s */
const scalars = (s) => [...s].length;
/** @param {unknown} v @returns {v is Record<string, any>} */
const isObject = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
/** @param {object} obj @param {string[]} keys */
const onlyKeys = (obj, keys) => Object.keys(obj).every((k) => keys.includes(k));
/** @param {unknown} v @param {number} max */
const text = (v, max) => typeof v === 'string' && !/^\s*$/.test(v) && scalars(v) <= max;

/**
 * @typedef {{id: string, text: string, source: string, capturedAt?: string}} MemoryInput
 * @typedef {{schemaVersion: 1, requestId: string, sessionId: string, locale: string, userText: string,
 *   turns: {role: 'user'|'assistant', text: string}[], memories: MemoryInput[]}} AssistRequest
 * @param {unknown} body
 * @returns {{ok: true, value: AssistRequest} | {ok: false, reason: string}}
 */
export function validateAssistRequest(body) {
  if (!isObject(body)) return { ok: false, reason: 'body' };
  if (!onlyKeys(body, ['schemaVersion', 'requestId', 'sessionId', 'locale', 'userText', 'turns', 'memories'])) {
    return { ok: false, reason: 'unknown-field' };
  }
  if (body.schemaVersion !== 1) return { ok: false, reason: 'schemaVersion' };
  if (typeof body.requestId !== 'string' || !UUID.test(body.requestId)) return { ok: false, reason: 'requestId' };
  if (typeof body.sessionId !== 'string' || !UUID.test(body.sessionId)) return { ok: false, reason: 'sessionId' };
  if (typeof body.locale !== 'string' || !LOCALE.test(body.locale)) return { ok: false, reason: 'locale' };
  if (!text(body.userText, LIMITS.userText)) return { ok: false, reason: 'userText' };

  const turnsIn = body.turns ?? [];
  if (!Array.isArray(turnsIn) || turnsIn.length > LIMITS.turns) return { ok: false, reason: 'turns' };
  for (const t of turnsIn) {
    if (!isObject(t) || !onlyKeys(t, ['role', 'text'])) return { ok: false, reason: 'turn' };
    if (t.role !== 'user' && t.role !== 'assistant') return { ok: false, reason: 'turn-role' };
    if (!text(t.text, LIMITS.turnText)) return { ok: false, reason: 'turn-text' };
  }

  const memIn = body.memories ?? [];
  if (!Array.isArray(memIn) || memIn.length > LIMITS.memories) return { ok: false, reason: 'memories' };
  let total = 0;
  const seen = new Set();
  for (const m of memIn) {
    if (!isObject(m) || !onlyKeys(m, ['id', 'text', 'source', 'capturedAt'])) return { ok: false, reason: 'memory' };
    if (typeof m.id !== 'string' || !UUID.test(m.id)) return { ok: false, reason: 'memory-id' };
    const key = m.id.toLowerCase();
    if (seen.has(key)) return { ok: false, reason: 'memory-duplicate' };
    seen.add(key);
    if (!text(m.text, LIMITS.memoryText)) return { ok: false, reason: 'memory-text' };
    if (typeof m.source !== 'string' || !SOURCES.has(m.source)) return { ok: false, reason: 'memory-source' };
    if (m.capturedAt !== undefined && (typeof m.capturedAt !== 'string' || !ISO_DATE.test(m.capturedAt))) {
      return { ok: false, reason: 'memory-date' };
    }
    total += scalars(m.text);
  }
  if (total > LIMITS.memoryTotal) return { ok: false, reason: 'memory-total' };

  return {
    ok: true,
    value: /** @type {AssistRequest} */ ({ ...body, turns: turnsIn, memories: memIn }),
  };
}

/** @param {unknown} body @returns {{ok: true, value: {inviteCode: string, deviceId: string}} | {ok: false}} */
export function validateRegisterRequest(body) {
  if (!isObject(body) || !onlyKeys(body, ['inviteCode', 'deviceId'])) return { ok: false };
  if (typeof body.inviteCode !== 'string' || body.inviteCode.length < 4 || body.inviteCode.length > 64) return { ok: false };
  if (typeof body.deviceId !== 'string' || !UUID.test(body.deviceId)) return { ok: false };
  return { ok: true, value: { inviteCode: body.inviteCode, deviceId: body.deviceId } };
}
