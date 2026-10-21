import { randomUUID } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { SessionVerifier } from "./auth.js";
import { type ErrorResponse, MockScenario } from "./contracts.js";
import type { DeviceSessionIssuer } from "./deviceSession.js";
import { type DocumentLinks, serveDocument } from "./documents.js";
import type { Store } from "./store.js";
import { AppError } from "./errors.js";
import type { ConnectedAppsService } from "./service.js";
import type { ToolsMockScenario } from "./tools/mock.js";
import type { CloudToolsService } from "./tools/service.js";

/**
 * HTTP routing for the Doddy-owned v1 API. Every route under /v1/connected-apps is
 * authenticated; the user is derived from the session token only. There is deliberately no
 * route that accepts a tool slug, a provider method, a URL to proxy, or a connection ID.
 */

export interface HttpDeps {
  service: ConnectedAppsService;
  /** Online-account tools (Gmail, Drive, Notion, Todoist). Routes exist only when provided. */
  tools?: CloudToolsService;
  verifier: SessionVerifier;
  /** Beta device sign-in (ADR-562). Absent: `POST /v1/session/device` is not found. */
  deviceSessions?: DeviceSessionIssuer | null;
  /** Files Claude made (ADR-563), opened by signed link. Absent: `GET /v1/documents/…` is not found. */
  documents?: { links: DocumentLinks; store: Store } | null;
  appReturnUrl: string;
  maxBodyBytes: number;
  now?: () => Date;
  log?: (line: Record<string, unknown>) => void;
}

const PLANNED = ["apple_calendar", "apple_reminders", "todoist", "notion"] as const;
const OPAQUE = /^[A-Za-z0-9_\-.:]{1,256}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

type Handler = (ctx: { userId: string; body: unknown; scenario: MockScenario | undefined }) => Promise<unknown>;

const TOOLS_SCENARIOS = new Set<ToolsMockScenario>(["normal", "empty", "malformed", "malformed_write", "provider_error", "rate_limited", "expired", "broad_scope", "missing_scope", "read_compose_only"]);
const TOOLKIT_ROUTE = /^POST \/v1\/tools\/([a-z]{1,20})\/(connect|complete|disconnect)$/;

export function createHandler(deps: HttpDeps) {
  const now = deps.now ?? (() => new Date());
  const log = deps.log ?? ((line) => process.stdout.write(`${JSON.stringify(line)}\n`));
  const { service } = deps;

  const routes: Record<string, Handler> = {
    "GET /v1/connected-apps": async ({ userId }) => ({
      mode: service.mode,
      apps: [await service.view(userId)],
      planned: PLANNED.map((id) => ({ id, status: "planned" })),
    }),
    "GET /v1/connected-apps/google-calendar": async ({ userId }) => service.refreshStatus(userId),
    "GET /v1/connected-apps/google-calendar/receipts": async ({ userId }) => ({ receipts: await service.receipts(userId) }),
    "POST /v1/connected-apps/google-calendar/connect": async ({ userId, body, scenario }) => service.connect(userId, body, scenario),
    "POST /v1/connected-apps/google-calendar/complete": async ({ userId, body }) => service.complete(userId, body),
    "POST /v1/connected-apps/google-calendar/events": async ({ userId, body, scenario }) => service.listEvents(userId, body, scenario),
    "POST /v1/connected-apps/google-calendar/disconnect": async ({ userId, body }) => service.disconnect(userId, body),
  };

  const tools = deps.tools;
  const toolsRoutes: Record<string, (userId: string, body: unknown) => unknown | Promise<unknown>> = tools
    ? {
        "GET /v1/tools": (userId) => tools.catalog(userId),
        "GET /v1/tools/receipts": async (userId) => ({ receipts: await tools.receipts(userId) }),
        "PUT /v1/tools/switch": (userId, body) => tools.setSwitch(userId, body),
        "POST /v1/tools/prepare": (userId, body) => tools.prepare(userId, body),
        "POST /v1/tools/run": (userId, body) => tools.run(userId, body),
      }
    : {};

  return async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const started = Date.now();
    const correlationId = randomUUID();
    let route = "unmatched";
    let status = 500;
    let code: string | undefined;

    try {
      res.setHeader("x-correlation-id", correlationId);
      res.setHeader("cache-control", "no-store");
      res.setHeader("x-content-type-options", "nosniff");
      res.setHeader("referrer-policy", "no-referrer");

      // Parsed inside the try: Node accepts request targets that URL rejects (e.g. "//[").
      let url: URL;
      try {
        url = new URL(req.url ?? "/", "http://localhost");
      } catch {
        throw new AppError("invalid_request");
      }
      const key = `${req.method ?? "GET"} ${url.pathname}`;

      if (key === "GET /v1/health") {
        route = key;
        status = 200;
        return send(res, 200, { status: "ok", mode: service.mode, api: "v1", capabilities: ["calendar.listEvents"] });
      }
      if (key === "GET /v1/oauth/return" || key === "GET /v1/oauth/verify") {
        route = key;
        status = 302;
        return redirectToApp(res, url, deps.appReturnUrl, key.endsWith("verify"));
      }
      // The one route that needs no session: it is how the app gets one (ADR-562).
      if (key === "POST /v1/session/device" && deps.deviceSessions) {
        route = key;
        const body = await readJson(req, deps.maxBodyBytes);
        const issued = await deps.deviceSessions.issue(body, now());
        status = 200;
        return send(res, 200, issued);
      }
      // A signed link is its own permission (documents.ts); Safari opens it without the app's token.
      if (req.method === "GET" && url.pathname.startsWith("/v1/documents/") && deps.documents) {
        route = "GET /v1/documents/:id";
        status = await serveDocument(req, res, url, deps.documents.links, deps.documents.store, now());
        return;
      }

      const toolkitRoute = tools ? TOOLKIT_ROUTE.exec(key) : null;
      const toolsHandler = toolsRoutes[key];
      const handler = routes[key];
      if (!handler && !toolsHandler && !toolkitRoute) throw new AppError("not_found");
      // Route templates only in logs, so the set of values stays small.
      route = toolkitRoute ? `POST /v1/tools/:toolkit/${toolkitRoute[2]}` : key;

      const user = await deps.verifier.verify(header(req, "authorization"), now());
      if (!user) throw new AppError("unauthenticated");

      const rawScenario = header(req, "x-doddy-demo-scenario");
      const scenario = rawScenario === undefined ? undefined : MockScenario.safeParse(rawScenario);
      if (scenario && !scenario.success) throw new AppError("invalid_request");

      const body = req.method === "POST" || req.method === "PUT" ? await readJson(req, deps.maxBodyBytes) : undefined;
      if (tools && (toolsHandler || toolkitRoute)) {
        const rawTools = header(req, "x-doddy-tools-scenario");
        if (rawTools !== undefined) {
          if (!TOOLS_SCENARIOS.has(rawTools as ToolsMockScenario)) throw new AppError("invalid_request");
          await tools.applyMockScenario(user.userId, rawTools as ToolsMockScenario);
        }
        let toolsResult: unknown;
        if (toolsHandler) toolsResult = await toolsHandler(user.userId, body);
        else if (toolkitRoute) {
          const [, toolkitId, action] = toolkitRoute;
          toolsResult =
            action === "connect"
              ? await tools.connect(user.userId, toolkitId!, body)
              : action === "complete"
                ? await tools.complete(user.userId, toolkitId!, body)
                : await tools.disconnect(user.userId, toolkitId!, body);
        }
        status = 200;
        return send(res, 200, toolsResult);
      }
      if (!handler) throw new AppError("not_found");
      const result = await handler({ userId: user.userId, body, scenario: scenario?.data });
      status = 200;
      send(res, 200, result);
    } catch (error) {
      const appError = error instanceof AppError ? error : new AppError("internal");
      status = appError.status;
      code = appError.code;
      const payload: ErrorResponse = {
        error: {
          code: appError.code,
          message: appError.message,
          correlationId,
          ...(appError.options.retryAfterSeconds !== undefined ? { retryAfterSeconds: appError.options.retryAfterSeconds } : {}),
          ...(appError.options.receipt ? { receipt: appError.options.receipt as ErrorResponse["error"]["receipt"] } : {}),
        },
      };
      if (appError.options.retryAfterSeconds !== undefined) res.setHeader("retry-after", String(appError.options.retryAfterSeconds));
      if (!res.headersSent) send(res, appError.status, payload);
      if (!(error instanceof AppError)) {
        // Content-free: the error class only. Never the message (it may echo provider data).
        log({ level: "error", correlationId, kind: error instanceof Error ? error.name : typeof error });
      }
    } finally {
      // Content-free access log: route template, status, timing, error code. No bodies, query strings,
      // tokens, user IDs, provider payloads or calendar data.
      log({ level: "info", correlationId, route, status, ms: Date.now() - started, ...(code ? { code } : {}) });
    }
  };
}

function header(req: IncomingMessage, name: string): string | undefined {
  const value = req.headers[name];
  return Array.isArray(value) ? undefined : value;
}

function send(res: ServerResponse, status: number, body: unknown): void {
  const json = JSON.stringify(body);
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(json) });
  res.end(json);
}

async function readJson(req: IncomingMessage, maxBytes: number): Promise<unknown> {
  const type = header(req, "content-type") ?? "";
  if (!/^application\/json(;|$)/i.test(type)) throw new AppError("invalid_request");
  const declared = Number(header(req, "content-length") ?? "0");
  if (declared > maxBytes) throw new AppError("payload_too_large");
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > maxBytes) throw new AppError("payload_too_large");
    chunks.push(chunk as Buffer);
  }
  if (size === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new AppError("invalid_request");
  }
}

/**
 * Browser landing for Composio's completion redirect. It changes no state: it forwards only
 * well-formed, allowlisted parameters to the single configured app return URL, where the
 * authenticated app finishes the attempt. Anything else is dropped.
 */
function redirectToApp(res: ServerResponse, url: URL, appReturnUrl: string, verifier: boolean): void {
  const target = new URL(appReturnUrl);
  const q = url.searchParams;
  if (verifier) {
    const sessionUri = q.get("session_uri");
    if (sessionUri && sessionUri.length <= 2048 && !/[\s<>"]/.test(sessionUri)) target.searchParams.set("session_uri", sessionUri);
  } else {
    const attempt = q.get("attempt");
    const status = q.get("status");
    const account = q.get("connected_account_id");
    if (attempt && UUID.test(attempt)) target.searchParams.set("attempt", attempt);
    if (status === "success" || status === "failed") target.searchParams.set("status", status);
    if (account && OPAQUE.test(account)) target.searchParams.set("connected_account_id", account);
  }
  res.writeHead(302, { location: target.toString(), "content-length": 0 });
  res.end();
}
