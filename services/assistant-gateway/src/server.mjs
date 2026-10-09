import http from "node:http";
import { timingSafeEqual } from "node:crypto";
import { parseAssistRequest, ContractError } from "./contract.mjs";
import { GatewayError, STATUS_FOR_CODE } from "./errors.mjs";
import { buildMessages, callOpenAI } from "./model.mjs";
import { verifyModelReply } from "./verify.mjs";
import { createSessionLimiter } from "./limiter.mjs";

const MAX_BODY_BYTES = 64 * 1024;

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
  });
  res.end(body);
}

function bearerMatches(header, token) {
  if (typeof header !== "string" || !header.startsWith("Bearer ")) return false;
  const given = Buffer.from(header.slice("Bearer ".length));
  const expected = Buffer.from(token);
  return given.length === expected.length && timingSafeEqual(given, expected);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new GatewayError("badRequest"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", () => reject(new GatewayError("badRequest")));
  });
}

/**
 * Creates the gateway. Fails closed: every /v1 request needs the gateway token, and the provider
 * key stays on the server. Logs are content-free: request id, route, status, code and latency only.
 */
export function createGateway({
  token,
  apiKey,
  model,
  fetchImpl,
  timeoutMs,
  limiter = createSessionLimiter(),
  log = (line) => console.log(line),
}) {
  if (typeof token !== "string" || token.length < 32) {
    throw new Error("GATEWAY_TOKEN must be set (32+ characters)");
  }

  return http.createServer(async (req, res) => {
    const started = Date.now();
    let requestId = null;
    let code = null;
    let status = 500;

    try {
      if (req.method === "GET" && req.url === "/health") {
        status = 200;
        return send(res, status, { ok: true });
      }

      if (!(req.method === "POST" && req.url === "/v1/assist")) {
        status = 404;
        return send(res, status, { error: "notFound" });
      }

      if (!bearerMatches(req.headers.authorization, token)) throw new GatewayError("notAuthorized");

      let body;
      try {
        body = JSON.parse(await readBody(req));
      } catch {
        throw new GatewayError("badRequest");
      }

      let request;
      try {
        request = parseAssistRequest(body);
      } catch (err) {
        if (err instanceof ContractError) throw new GatewayError("badRequest");
        throw err;
      }
      requestId = request.requestId;

      if (!limiter.allow(request.sessionId)) throw new GatewayError("rateLimited");

      // Memory question with nothing matched: answer without calling the model, so nothing can be invented.
      if (request.taskType === "memory_answer" && request.memories.length === 0) {
        status = 200;
        return send(res, status, { requestId, answer: null, citedIds: [], noMatch: true });
      }

      if (!apiKey) throw new GatewayError("providerUnavailable");

      const raw = await callOpenAI({
        apiKey,
        model,
        messages: buildMessages(request),
        fetchImpl,
        timeoutMs,
      });
      const verified = verifyModelReply(raw, request.memories.map((m) => m.id));

      status = 200;
      return send(res, status, { requestId, answer: verified.answer, citedIds: verified.citedIds, noMatch: false });
    } catch (err) {
      if (err instanceof GatewayError) {
        code = err.code;
        status = STATUS_FOR_CODE[code];
      } else {
        code = "internal";
        status = 500;
      }
      if (!res.headersSent) send(res, status, { requestId, error: code === "internal" ? "internal" : code });
      else res.end();
    } finally {
      log(JSON.stringify({ requestId, status, code, ms: Date.now() - started }));
    }
  });
}
