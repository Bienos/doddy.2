// Render entry point (ADR-461): a plain Node server around the same handler the Vercel function ran.
// POST /api/voice-token for the app, GET /healthz for Render's health check. Render sets PORT.
import { createServer } from "node:http";
import { Readable } from "node:stream";
import { pathToFileURL } from "node:url";
import voiceToken from "./api/voice-token.js";

/** @typedef {(request: Request) => Response | Promise<Response>} Route */

/** @type {Record<string, Route>} */
const ROUTES = { "/api/voice-token": (request) => voiceToken.fetch(request) };

/** @param {import("node:http").IncomingMessage} req */
export function toRequest(req) {
  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers)) {
    for (const v of Array.isArray(value) ? value : value === undefined ? [] : [value]) headers.append(name, v);
  }
  const method = req.method ?? "GET";
  const body = method === "GET" || method === "HEAD" ? undefined : /** @type {ReadableStream} */ (Readable.toWeb(req));
  // duplex is required with a streamed body; @types/node 22 doesn't list it in RequestInit yet.
  const init = /** @type {RequestInit} */ ({ method, headers, body, duplex: "half" });
  return new Request(new URL(req.url ?? "/", "http://localhost"), init);
}

/** @param {Record<string, Route>} routes */
export function createApp(routes = ROUTES) {
  return createServer(async (req, res) => {
    /** @type {Response} */
    let response;
    try {
      const path = new URL(req.url ?? "/", "http://localhost").pathname;
      const route = routes[path];
      if (path === "/healthz") response = Response.json({ ok: true });
      else if (!route) response = Response.json({ error: "not_found" }, { status: 404 });
      else response = await route(toRequest(req));
    } catch {
      console.log(JSON.stringify({ evt: "host", outcome: "unhandled_error" }));
      response = Response.json({ error: "internal" }, { status: 500 });
    }
    const body = Buffer.from(await response.arrayBuffer());
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(body);
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT ?? 8787);
  createApp().listen(port, () => console.log(JSON.stringify({ evt: "listening", port })));
}
