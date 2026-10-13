// Plain Node entry point, for hosts that run a long-lived process (Render, Fly, a VM) instead of
// Vercel functions. Same handlers, same environment variables (README.md); no runtime dependencies.
//   PORT=8788 REQUIRE_SHARED_LIMITS=1 OPENAI_API_KEY=… … node server.js
// Routes: POST /api/register, POST /api/assist (the app's paths, unchanged) and GET /healthz.
//
// Client address: Vercel sets `x-vercel-forwarded-for`, which src/http.js reads. Here the wrapper
// drops whatever the client sent in `x-vercel-forwarded-for` and `x-real-ip` and sets `x-real-ip` from
// the first `x-forwarded-for` entry (Render's proxy). A client can put its own entry first, so the
// per-address limits are a brake, not a wall; the per-invite limits and the daily budget are the cap.
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { handleAssist } from './src/assist.js';
import { errorResponse } from './src/http.js';
import { handleRegister } from './src/register.js';
import { defaultDeps } from './src/runtime.js';

// Above the handlers' own caps (128 KB for assist), so they answer oversize bodies themselves; this
// only stops a client streaming without end.
const MAX_BODY_BYTES = 256 * 1024;

/** @typedef {(request: Request, deps: any) => Promise<Response>} Handler */

/**
 * @param {{ routes?: Record<string, Handler>, deps?: () => any }} [options]
 */
export function createGatewayServer({ routes = { '/api/register': handleRegister, '/api/assist': handleAssist }, deps = defaultDeps } = {}) {
  return createServer(async (req, res) => {
    try {
      const path = new URL(req.url ?? '/', 'http://localhost').pathname;
      if (path === '/healthz') return await send(res, Response.json({ ok: true }));
      const handler = routes[path];
      if (!handler) return await send(res, Response.json({ error: 'not_found' }, { status: 404 }));

      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_BODY_BYTES) return await send(res, errorResponse('payloadTooLarge'));
        chunks.push(chunk);
      }
      const headers = new Headers();
      for (const [name, value] of Object.entries(req.headers)) {
        if (name === 'x-vercel-forwarded-for' || name === 'x-real-ip') continue;
        if (typeof value === 'string') headers.set(name, value);
        else if (Array.isArray(value)) headers.set(name, value.join(', '));
      }
      const forwarded = headers.get('x-forwarded-for')?.split(',')[0]?.trim();
      const address = forwarded || req.socket.remoteAddress;
      if (address) headers.set('x-real-ip', address);
      const hasBody = req.method !== 'GET' && req.method !== 'HEAD' && chunks.length > 0;
      const request = new Request(`http://localhost${path}`, {
        method: req.method,
        headers,
        body: hasBody ? Buffer.concat(chunks) : undefined,
      });
      return await send(res, await handler(request, deps()));
    } catch {
      // Content-free, like the handlers' own logs.
      console.log(JSON.stringify({ evt: 'server', code: 'providerUnavailable', cause: 'unexpected' }));
      if (!res.headersSent) return await send(res, errorResponse('providerUnavailable'));
      res.end();
    }
  });
}

/** @param {import('node:http').ServerResponse} res @param {Response} response */
async function send(res, response) {
  /** @type {Record<string, string>} */
  const headers = {};
  response.headers.forEach((value, name) => { headers[name] = value; });
  res.writeHead(response.status, headers);
  res.end(Buffer.from(await response.arrayBuffer()));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const port = Number(process.env.PORT ?? '8788');
  createGatewayServer().listen(port, '0.0.0.0', () => {
    console.log(JSON.stringify({ evt: 'listening', port }));
  });
}
