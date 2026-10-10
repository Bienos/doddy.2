import { readFileSync } from 'node:fs';
import { MemoryRateLimiter } from '../src/ratelimit.js';
import { inviteTag, issueToken } from '../src/token.js';

export const SECRET = 'test-secret-test-secret-test-secret-123456';
export const INVITE = 'BETA-INVITE-0001';
export const DEVICE = '3f2b8a10-6c4d-4e7f-b1a2-c3d4e5f60718';
export const NOW_MS = 1_790_000_000_000;

export const ENV = {
  OPENAI_API_KEY: 'sk-test-not-a-real-key-000000000000',
  OPENAI_MODEL: 'test-model',
  GATEWAY_TOKEN_SECRET: SECRET,
  GATEWAY_INVITE_CODES: `${INVITE},OTHER-INVITE-0002`,
};

export function fixture(name) {
  return JSON.parse(readFileSync(new URL(`../../schemas/fixtures/${name}`, import.meta.url), 'utf8'));
}

export function token(overrides = {}) {
  return issueToken(
    { deviceId: overrides.deviceId ?? DEVICE, inviteTag: overrides.inviteTag ?? inviteTag(INVITE, SECRET) },
    overrides.secret ?? SECRET,
    Math.floor(NOW_MS / 1000) - (overrides.ageSeconds ?? 0),
    overrides.ttl ?? 3600,
  ).token;
}

export function assistRequest(body, { auth = token(), headers = {} } = {}) {
  return new Request('https://gateway.test/api/assist', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(auth ? { authorization: `Bearer ${auth}` } : {}), ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

/** OpenAI Responses API shaped reply. */
export function providerOk(payload, usage = { input_tokens: 120, output_tokens: 20 }) {
  return Response.json({
    status: 'completed',
    output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(payload) }] }],
    usage,
  });
}

/** Records every provider call; `replies` is consumed in order (last one repeats). */
export function fakeProvider(...replies) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    const next = replies.length > 1 ? replies.shift() : replies[0];
    const value = typeof next === 'function' ? await next(init) : next;
    return value.clone ? value.clone() : value;
  };
  fn.calls = calls;
  return fn;
}

export function makeDeps(overrides = {}) {
  const logs = [];
  return {
    deps: {
      env: ENV,
      fetch: fakeProvider(providerOk({ answer: 'ok', sources: [] })),
      now: () => NOW_MS,
      limiter: new MemoryRateLimiter(),
      logSink: (line) => logs.push(line),
      ...overrides,
    },
    logs,
  };
}
