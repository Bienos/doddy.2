import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createGatewayServer } from '../server.js';

/**
 * @param {Record<string, (request: Request, deps: any) => Promise<Response>>} routes
 * @param {(base: string) => Promise<void>} run
 */
async function withServer(routes, run) {
  const server = createGatewayServer({ routes, deps: () => ({ marker: 'deps' }) });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(undefined)));
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  try {
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(() => resolve(undefined)));
  }
}

test('routes each path to its handler with the body, headers and deps', async () => {
  /** @type {any[]} */
  const seen = [];
  const route = (/** @type {string} */ name) => async (/** @type {Request} */ request, /** @type {any} */ deps) => {
    seen.push({ name, method: request.method, auth: request.headers.get('authorization'), body: await request.text(), deps });
    return Response.json({ ok: name }, { status: 201 });
  };
  await withServer({ '/api/register': route('register'), '/api/assist': route('assist') }, async (base) => {
    const res = await fetch(`${base}/api/assist`, { method: 'POST', headers: { authorization: 'Bearer t', 'content-type': 'application/json' }, body: '{"q":1}' });
    assert.equal(res.status, 201);
    assert.deepEqual(await res.json(), { ok: 'assist' });
    await fetch(`${base}/api/register`, { method: 'POST', body: '{}' });
  });
  assert.deepEqual(seen.map((s) => s.name), ['assist', 'register']);
  assert.deepEqual(seen[0], { name: 'assist', method: 'POST', auth: 'Bearer t', body: '{"q":1}', deps: { marker: 'deps' } });
});

test('the client address comes from x-forwarded-for, never from client-set vercel or real-ip headers', async () => {
  /** @type {(string|null)[]} */
  const seen = [];
  const handle = async (/** @type {Request} */ request) => {
    seen.push(request.headers.get('x-vercel-forwarded-for'), request.headers.get('x-real-ip'));
    return new Response(null, { status: 204 });
  };
  await withServer({ '/api/register': handle }, async (base) => {
    await fetch(`${base}/api/register`, {
      method: 'POST',
      headers: { 'x-vercel-forwarded-for': '6.6.6.6', 'x-real-ip': '7.7.7.7', 'x-forwarded-for': '203.0.113.9, 10.0.0.1' },
    });
    await fetch(`${base}/api/register`, { method: 'POST' });
  });
  assert.equal(seen[0], null);
  assert.equal(seen[1], '203.0.113.9');
  assert.equal(seen[2], null);
  assert.ok(seen[3] && seen[3].includes('127.0.0.1'));
});

test('health check, unknown paths and endless bodies never reach a handler', async () => {
  let calls = 0;
  const handle = async () => { calls += 1; return new Response(null, { status: 204 }); };
  await withServer({ '/api/assist': handle }, async (base) => {
    const health = await fetch(`${base}/healthz`);
    assert.deepEqual([health.status, await health.json()], [200, { ok: true }]);
    assert.equal((await fetch(`${base}/api/other`, { method: 'POST' })).status, 404);
    const big = await fetch(`${base}/api/assist`, { method: 'POST', body: 'x'.repeat(300 * 1024) });
    assert.equal(big.status, 413);
  });
  assert.equal(calls, 0);
});

test('a handler that throws gives the generic providerUnavailable error', async () => {
  const handle = async () => { throw new Error('secret detail'); };
  await withServer({ '/api/assist': handle }, async (base) => {
    const res = await fetch(`${base}/api/assist`, { method: 'POST' });
    assert.equal(res.status, 503);
    const body = await res.json();
    assert.equal(body.error.code, 'providerUnavailable');
    assert.ok(!JSON.stringify(body).includes('secret detail'));
  });
});
