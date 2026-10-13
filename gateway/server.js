// Render entry point (ADR-461): a plain Node server around the same handlers the Vercel functions ran.
// POST /api/register and /api/assist for the app, GET /healthz for Render's health check. Render sets PORT.
import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { pathToFileURL } from 'node:url';
import assist from './api/assist.js';
import register from './api/register.js';

/** @typedef {(request: Request) => Response | Promise<Response>} Route */

/** @type {Record<string, Route>} */
const ROUTES = {
  '/api/register': (request) => register.fetch(request),
  '/api/assist': (request) => assist.fetch(request),
};

/**
 * `clientAddress` (src/http.js) reads x-vercel-forwarded-for, then x-real-ip, for rate limiting. On Render
 * both would come from the caller, so they are dropped, and x-real-ip is set from CF-Connecting-IP, which
 * Cloudflare (in front of every public Render service) overwrites on each request.
 * @param {import('node:http').IncomingMessage} req
 */
export function toRequest(req) {
  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers)) {
    if (name === 'x-vercel-forwarded-for' || name === 'x-real-ip') continue;
    for (const v of Array.isArray(value) ? value : value === undefined ? [] : [value]) headers.append(name, v);
  }
  const client = headers.get('cf-connecting-ip');
  if (client) headers.set('x-real-ip', client);
  const method = req.method ?? 'GET';
  const body = method === 'GET' || method === 'HEAD' ? undefined : /** @type {ReadableStream} */ (Readable.toWeb(req));
  // duplex is required with a streamed body; @types/node 22 doesn't list it in RequestInit yet.
  const init = /** @type {RequestInit} */ ({ method, headers, body, duplex: 'half' });
  return new Request(new URL(req.url ?? '/', 'http://localhost'), init);
}

/** @param {Record<string, Route>} routes */
export function createApp(routes = ROUTES) {
  const server = createServer(async (req, res) => {
    /** @type {Response} */
    let response;
    try {
      const path = new URL(req.url ?? '/', 'http://localhost').pathname;
      const route = routes[path];
      if (path === '/healthz') response = Response.json({ ok: true });
      else if (!route) response = Response.json({ error: 'not_found' }, { status: 404 });
      else response = await route(toRequest(req));
    } catch {
      console.log(JSON.stringify({ evt: 'host', outcome: 'unhandledError' }));
      response = Response.json({ error: 'internal' }, { status: 500 });
    }
    const body = Buffer.from(await response.arrayBuffer());
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(body);
  });
  // Vercel stopped /api/assist at 30 s (vercel.json); the handlers keep their own deadlines inside that.
  server.requestTimeout = 35_000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT ?? 8788);
  createApp().listen(port, () => console.log(JSON.stringify({ evt: 'listening', port })));
}
