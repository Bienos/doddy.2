// Plain Node entry point, for hosts that run a long-lived process (Render, Fly, a VM) instead of
// Vercel functions. Same handler, same environment variables (README.md); no dependencies.
//   PORT=8787 ELEVENLABS_API_KEY=… ELEVENLABS_AGENT_ID=… DODDY_ACCESS_CODES=… node server.js
// Routes: POST /api/voice-token (the app's path, unchanged) and GET /healthz.
import { createServer } from "node:http";
import { pathToFileURL } from "node:url";
import { handleTokenRequest } from "./src/handler.js";

// The app sends no body for ElevenLabs and a tiny JSON one for the OpenAI test voice.
const MAX_BODY_BYTES = 4096;

/**
 * @param {{ env?: Record<string, string | undefined>, handle?: typeof handleTokenRequest }} [options]
 */
export function createTokenServer({ env = process.env, handle = handleTokenRequest } = {}) {
  return createServer(async (req, res) => {
    try {
      const path = new URL(req.url ?? "/", "http://localhost").pathname;
      if (path === "/healthz") return send(res, new Response('{"ok":true}', { headers: { "content-type": "application/json" } }));
      if (path !== "/api/voice-token") return send(res, Response.json({ error: "not_found" }, { status: 404 }));

      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_BODY_BYTES) return send(res, Response.json({ error: "payload_too_large" }, { status: 413 }));
        chunks.push(chunk);
      }
      const headers = new Headers();
      for (const [name, value] of Object.entries(req.headers)) {
        if (typeof value === "string") headers.set(name, value);
        else if (Array.isArray(value)) headers.set(name, value.join(", "));
      }
      const hasBody = req.method !== "GET" && req.method !== "HEAD" && chunks.length > 0;
      const request = new Request(`http://localhost${path}`, {
        method: req.method,
        headers,
        body: hasBody ? Buffer.concat(chunks) : undefined,
      });
      return send(res, await handle(request, env));
    } catch {
      // Content-free, like the handler's own logs.
      console.log(JSON.stringify({ event: "voice_token", status: 500, error: "unexpected" }));
      if (!res.headersSent) return send(res, Response.json({ error: "unexpected" }, { status: 500 }));
      res.end();
    }
  });
}

/** @param {import("node:http").ServerResponse} res @param {Response} response */
async function send(res, response) {
  const headers = {};
  response.headers.forEach((value, name) => { headers[name] = value; });
  res.writeHead(response.status, headers);
  res.end(Buffer.from(await response.arrayBuffer()));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const port = Number(process.env.PORT ?? "8787");
  createTokenServer().listen(port, "0.0.0.0", () => {
    console.log(JSON.stringify({ event: "listening", port }));
  });
}
