import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createApp } from '../server.js';

/** Starts the Render host on a free port, runs `fn` with its base URL, then closes it. */
async function withServer(routes, fn) {
  const server = createApp(routes);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = /** @type {import('node:net').AddressInfo} */ (server.address());
  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

const echo = {
  '/api/assist': async (/** @type {Request} */ request) =>
    Response.json({
      vercel: request.headers.get('x-vercel-forwarded-for'),
      realIp: request.headers.get('x-real-ip'),
      body: request.method === 'POST' ? await request.json() : null,
    }),
};

test('health check answers 200 and unknown paths 404', async () => {
  await withServer(undefined, async (base) => {
    assert.equal((await fetch(`${base}/healthz`)).status, 200);
    assert.equal((await fetch(`${base}/api/other`)).status, 404);
  });
});

test('the real register route reaches its handler, which refuses GET', async () => {
  await withServer(undefined, async (base) => {
    assert.equal((await fetch(`${base}/api/register`)).status, 405);
  });
});

test('caller-supplied address headers are dropped and CF-Connecting-IP becomes x-real-ip', async () => {
  await withServer(echo, async (base) => {
    const res = await fetch(`${base}/api/assist`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-vercel-forwarded-for': '1.1.1.1',
        'x-real-ip': '2.2.2.2',
        'cf-connecting-ip': '203.0.113.7',
      },
      body: JSON.stringify({ q: 'hi' }),
    });
    assert.deepEqual(await res.json(), { vercel: null, realIp: '203.0.113.7', body: { q: 'hi' } });
  });
});

test('without CF-Connecting-IP no client address is passed on', async () => {
  await withServer(echo, async (base) => {
    const res = await fetch(`${base}/api/assist`, { headers: { 'x-real-ip': '2.2.2.2' } });
    assert.deepEqual(await res.json(), { vercel: null, realIp: null, body: null });
  });
});
