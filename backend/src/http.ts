import { randomUUID } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { AccountEraser } from "./account.js";
import { type AccountLinker, accountSubjectOf } from "./accountLinks.js";
import { ASSIST_MAX_BODY_BYTES, type AssistService } from "./assist.js";
import { type AuthenticatedUser, requireFullAccess, type SessionVerifier } from "./auth.js";
import { clientAddress } from "./clientAddress.js";
import { type ErrorResponse, MockScenario } from "./contracts.js";
import type { DeviceSessionIssuer } from "./deviceSession.js";
import { type DocumentLinks, serveDocument } from "./documents.js";
import { issuedAtOf, requestCredential } from "./requestCredential.js";
import type { Store } from "./store.js";
import { AppError } from "./errors.js";
import { PAYMENT_SCENARIOS, type PaymentScenario, type PaymentsService } from "./payments/service.js";
import type { ConnectedAppsService } from "./service.js";
import type { ShopifyUcpService } from "./shopify/ucp.js";
import type { UsageLimiter } from "./policy.js";
import type { ToolsMockScenario } from "./tools/mock.js";
import type { CloudToolsService } from "./tools/service.js";
import type { WebRoutes } from "./web/routes.js";
import { COOKIE_READABLE, type WebAuth } from "./web/sessions.js";
import type { WebStatic } from "./web/static.js";

/**
 * HTTP routing for the Doddy-owned v1 API. Every route under /v1/connected-apps is
 * authenticated; the user is derived from the session token only. There is deliberately no
 * route that accepts a tool slug, a provider method, a URL to proxy, or a connection ID.
 */

export interface HttpDeps {
  service: ConnectedAppsService;
  /** Online-account tools (Gmail, Drive, Notion, Todoist). Routes exist only when provided. */
  tools?: CloudToolsService;
  /** Paying for things (x402). Routes exist only when provided; each says "not set up" until a wallet is. */
  payments?: PaymentsService;
  /** Live Shopify Shop MCP search and merchant-owned checkout. No payment or order submission. */
  shopify?: ShopifyUcpService | null;
  /** Durable, per-user Shopify provider call limits plus provider concurrency slots. */
  shopifyLimiter?: UsageLimiter;
  verifier: SessionVerifier;
  /** Beta device sign-in (ADR-563). Absent: `POST /v1/session/device` is not found. */
  deviceSessions?: DeviceSessionIssuer | null;
  /** Files Claude made (ADR-564), opened by signed link. Absent: `GET /v1/documents/…` is not found. */
  documents?: { links: DocumentLinks; store: Store } | null;
  /** Doddy Web (ADR-600): its routes, its cookie sessions and its pages. Absent: none of them exist. */
  web?: { auth: WebAuth; routes: WebRoutes; pages: WebStatic } | null;
  /** Ask Doddy (ADR-587): typed questions answered by Claude. Absent: `POST /v1/assist` is not found. */
  assist?: AssistService | null;
  /** Deleting the account on this server (ADR-674). Absent: `DELETE /v1/account` is not found. */
  account?: AccountEraser | null;
  /** An account taking over an iPhone's earlier data (decision 2026-11-08-required-account). Absent: not found. */
  accountLinker?: AccountLinker | null;
  /**
   * What `GET /v1/health` checks (engineering audit, 7 Nov 2026): a database round trip, so a server whose
   * database is gone answers 503 instead of a static "ok". It answers with its status only (12 Nov 2026);
   * the running commit is in the start log (startLine.ts). Absent: health is static.
   */
  health?: { ping(): Promise<void> } | null;
  appReturnUrl: string;
  maxBodyBytes: number;
  /** Behind one proxy that appends the client to X-Forwarded-For (Render). For per-client limits. */
  trustProxy?: boolean;
  now?: () => Date;
  log?: (line: Record<string, unknown>) => void;
}

/** A database that takes longer than this to answer counts as down for health (the request limit is 20 s). */
const HEALTH_DATABASE_TIMEOUT_MS = 3_000;

async function databaseAnswers(ping: () => Promise<void>): Promise<"ok" | "unavailable"> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      ping(),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("timeout")), HEALTH_DATABASE_TIMEOUT_MS);
      }),
    ]);
    return "ok";
  } catch {
    return "unavailable";
  } finally {
    if (timer) clearTimeout(timer);
  }
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
    // Whether this server runs on demo data (mock) or for real (live); Doddy Web's "Demo server" banner
    // reads it with the browser's session (COOKIE_READABLE). Signed in only: GET /v1/health tells nobody.
    "GET /v1/server": async () => ({ mode: service.mode }),
    "GET /v1/connected-apps": async ({ userId }) => ({
      mode: service.mode,
      apps: [await service.view(userId)],
      planned: PLANNED.map((id) => ({ id, status: "planned" })),
    }),
    "GET /v1/connected-apps/google-calendar": async ({ userId }) => service.refreshStatus(userId),
    "GET /v1/connected-apps/google-calendar/receipts": async ({ userId }) => ({ receipts: await service.receipts(userId) }),
    "POST /v1/connected-apps/google-calendar/connect": async ({ userId, body, scenario }) => service.connect(userId, body, scenario),
    "POST /v1/connected-apps/google-calendar/complete": async ({ userId, body }) => service.complete(userId, body),
    // The one read with no approval, on purpose (ADR-708): the Connected Apps screen's own button, with the
    // owner's session. Not reachable by a model (its calendar tool is `read_google_calendar`, which asks
    // first), by a guest iPhone or by a browser cookie. See `CALENDAR_LIST_EVENTS`.
    "POST /v1/connected-apps/google-calendar/events": async ({ userId, body, scenario }) => service.listEvents(userId, body, scenario),
    "POST /v1/connected-apps/google-calendar/disconnect": async ({ userId, body }) => service.disconnect(userId, body),
  };

  const tools = deps.tools;
  const toolsRoutes: Record<string, (userId: string, body: unknown) => unknown | Promise<unknown>> = tools
    ? {
        "GET /v1/tools": (userId) => tools.catalog(userId),
        "GET /v1/tools/receipts": async (userId) => ({ receipts: await tools.receipts(userId) }),
        "PUT /v1/tools/switch": (userId, body) => tools.setSwitch(userId, body),
        "PUT /v1/tools/access": (userId, body) => tools.setAppAccess(userId, body),
        "POST /v1/tools/prepare": (userId, body) => tools.prepare(userId, body),
        "POST /v1/tools/run": (userId, body) => tools.run(userId, body),
        // Travel, stage 1: the trip screen's own Gmail search, with its own ask-first card (TRAVEL_EMAILS.md).
        "POST /v1/travel/prepare": (userId, body) => tools.prepareTravelScan(userId, body),
        "POST /v1/travel/scan": (userId, body) => tools.runTravelScan(userId, body),
        // The trip planner (TRAVEL_PLANNER.md): words to a brief, then Kiwi.com's flights for it.
        "POST /v1/travel/plan/understand": (userId, body) => tools.understandTrip(userId, body),
        "POST /v1/travel/plan/search": (userId, body) => tools.searchTrip(userId, body),
      }
    : {};

  const shopify = deps.shopify;
  const shopifyRoutes: Record<string, (body: unknown) => Promise<unknown>> = shopify
    ? {
        "POST /v1/shopify/search": (body) => shopify.search(body),
        "POST /v1/shopify/checkout": (body) => shopify.prepareCheckout(body),
      }
    : {};

  const payments = deps.payments;
  const paymentsRoutes: Record<string, (userId: string, body: unknown) => unknown | Promise<unknown>> = payments
    ? {
        "GET /v1/payments": (userId) => payments.status(userId),
        "GET /v1/payments/receipts": async (userId) => ({ receipts: await payments.receipts(userId) }),
        "PUT /v1/payments/switch": (userId, body) => payments.setSwitch(userId, body),
        "POST /v1/payments/page": (userId, body) => payments.page(userId, body),
        "POST /v1/payments/prepare": (userId, body) => payments.prepare(userId, body),
        "POST /v1/payments/pay": (userId, body) => payments.pay(userId, body),
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

      // Open to anyone (Render's health check, the iPhone's wake-up ping), so it says nothing but its status:
      // no mode, version, commit or configuration. A signed-in caller reads the mode at GET /v1/server.
      if (key === "GET /v1/health") {
        route = key;
        const database = deps.health ? await databaseAnswers(deps.health.ping) : undefined;
        status = database === "unavailable" ? 503 : 200;
        return send(res, status, { status: database === "unavailable" ? "unavailable" : "ok" });
      }
      if (key === "GET /v1/oauth/return" || key === "GET /v1/oauth/verify") {
        route = key;
        status = 302;
        log({ level: "info", correlationId, event: "oauth_return", ...describeReturn(url, key.endsWith("verify")) });
        return redirectToApp(res, url, deps.appReturnUrl, key.endsWith("verify"));
      }
      // The one route that needs no session: it is how the app gets one (ADR-563).
      if (key === "POST /v1/session/device" && deps.deviceSessions) {
        route = key;
        const body = await readJson(req, deps.maxBodyBytes);
        const issued = await deps.deviceSessions.issue(body, now(), clientAddress(req, deps.trustProxy ?? false));
        status = 200;
        return send(res, 200, issued);
      }
      // A signed link is its own permission (documents.ts); Safari opens it without the app's token.
      if (req.method === "GET" && url.pathname.startsWith("/v1/documents/") && deps.documents) {
        route = "GET /v1/documents/:id";
        status = await serveDocument(req, res, url, deps.documents.links, deps.documents.store, now());
        return;
      }

      // Ask Doddy (ADR-587): the iPhone's own session only (never a browser cookie), a guest's
      // included, and its own body limit, sized for a question plus up to eight matching notes.
      if (key === "POST /v1/assist" && deps.assist) {
        route = key;
        const user = await deps.verifier.verify(header(req, "authorization"), now());
        if (!user) throw new AppError("unauthenticated");
        const body = await readJson(req, ASSIST_MAX_BODY_BYTES);
        const reply = await deps.assist.answer(user.userId, body, user.scope);
        status = 200;
        return send(res, 200, reply);
      }

      // Deleting the account (ADR-674): the iPhone's own session in the Authorization header, never a
      // browser cookie (Doddy Web deletes its parts on its own pages), a guest's included: it is their
      // data. No body. The answer is the receipt; `complete: false` says what is still owed.
      if (key === "DELETE /v1/account" && deps.account) {
        route = key;
        const authorization = header(req, "authorization");
        const user = await deps.verifier.verify(authorization, now());
        if (!user) throw new AppError("unauthenticated");
        const subject = accountSubjectOf(authorization);
        const erasure = await deps.account.erase(user.userId, subject ? [subject] : []);
        status = 200;
        return send(res, 200, erasure);
      }

      // Decision 2026-11-08-required-account: a Doddy account takes over this iPhone's earlier data,
      // once. The iPhone's own device session starts it (a one-time code), the account's sign-in
      // finishes it with that code, and for a day the device session can take it back (accountLinks.ts).
      if (key === "POST /v1/account/link-device/start" && deps.accountLinker) {
        route = key;
        const code = await deps.accountLinker.start(header(req, "authorization"), now());
        status = 200;
        return send(res, 200, code);
      }
      if (key === "POST /v1/account/link-device" && deps.accountLinker) {
        route = key;
        const body = await readJson(req, deps.maxBodyBytes);
        const linked = await deps.accountLinker.link(header(req, "authorization"), body, now());
        status = 200;
        return send(res, 200, linked);
      }
      if (key === "POST /v1/account/link-device/undo" && deps.accountLinker) {
        route = key;
        const undone = await deps.accountLinker.undo(header(req, "authorization"), now());
        status = 200;
        return send(res, 200, undone);
      }

      // Doddy Web (ADR-600): its own routes, then its pages for anything that isn't the API.
      const web = deps.web;
      if (web) {
        const match = web.routes.match(req.method ?? "GET", url.pathname);
        if (match) {
          route = match.route.template;
          status = await web.routes.serve(match, req, res, now(), url.searchParams);
          return;
        }
        if ((req.method === "GET" || req.method === "HEAD") && !url.pathname.startsWith("/v1/")) {
          route = "GET /*page";
          status = await web.pages.serve(req, res, url.pathname);
          return;
        }
      }

      const toolkitRoute = tools ? TOOLKIT_ROUTE.exec(key) : null;
      const toolsHandler = toolsRoutes[key];
      const handler = routes[key];
      const paymentsHandler = paymentsRoutes[key];
      const shopifyHandler = shopifyRoutes[key];
      if (!handler && !toolsHandler && !toolkitRoute && !paymentsHandler && !shopifyHandler) throw new AppError("not_found");
      // Route templates only in logs, so the set of values stays small.
      route = toolkitRoute ? `POST /v1/tools/:toolkit/${toolkitRoute[2]}` : key;

      const authorization = header(req, "authorization");
      let user = await deps.verifier.verify(authorization, now());
      // When this sign-in dates from (requestCredential.ts): the token's own date, or when the browser signed in.
      let issuedAt = user ? issuedAtOf(authorization) : undefined;
      // A browser session may read a few lists (COOKIE_READABLE); every other route needs the
      // iPhone's own session in the Authorization header.
      if (!user && authorization === undefined && web && COOKIE_READABLE.has(key)) {
        const session = await web.auth.fromCookie(req, now());
        if (session) {
          user = { userId: session.userId };
          issuedAt = Math.floor(session.createdAt / 1000);
        }
      }
      if (!user) throw new AppError("unauthenticated");
      // A guest iPhone (ADR-587) has Ask Doddy only.
      requireFullAccess(user);

      const serve = async (signedIn: AuthenticatedUser): Promise<void> => {
        const rawScenario = header(req, "x-doddy-demo-scenario");
        const scenario = rawScenario === undefined ? undefined : MockScenario.safeParse(rawScenario);
        if (scenario && !scenario.success) throw new AppError("invalid_request");

        const body = req.method === "POST" || req.method === "PUT" ? await readJson(req, deps.maxBodyBytes) : undefined;
        if (shopifyHandler) {
          // Only the iPhone’s full authenticated session reaches the live storefront.
          // A merchant cart or checkout is never a payment or a placed order.
          const result = deps.shopifyLimiter
            ? await (async () => {
                await deps.shopifyLimiter!.reserveToolRun(signedIn.userId, now().getTime());
                return deps.shopifyLimiter!.withSlot(signedIn.userId, () => shopifyHandler(body));
              })()
            : await shopifyHandler(body); // Legacy harness injects a one-call fake; production always supplies limiter.
          status = 200;
          return send(res, 200, result);
        }
        if (payments && paymentsHandler) {
          const rawPayments = header(req, "x-doddy-payments-scenario");
          if (rawPayments !== undefined) {
            if (!PAYMENT_SCENARIOS.has(rawPayments)) throw new AppError("invalid_request");
            payments.applyMockScenario(rawPayments as PaymentScenario);
          }
          const paymentsResult = await paymentsHandler(signedIn.userId, body);
          status = 200;
          return send(res, 200, paymentsResult);
        }
        if (tools && (toolsHandler || toolkitRoute)) {
          const rawTools = header(req, "x-doddy-tools-scenario");
          if (rawTools !== undefined) {
            if (!TOOLS_SCENARIOS.has(rawTools as ToolsMockScenario)) throw new AppError("invalid_request");
            await tools.applyMockScenario(signedIn.userId, rawTools as ToolsMockScenario);
          }
          let toolsResult: unknown;
          if (toolsHandler) toolsResult = await toolsHandler(signedIn.userId, body);
          else if (toolkitRoute) {
            const [, toolkitId, action] = toolkitRoute;
            toolsResult =
              action === "connect"
                ? await tools.connect(signedIn.userId, toolkitId!, body)
                : action === "complete"
                  ? await tools.complete(signedIn.userId, toolkitId!, body)
                  : await tools.disconnect(signedIn.userId, toolkitId!, body);
          }
          status = 200;
          return send(res, 200, toolsResult);
        }
        if (!handler) throw new AppError("not_found");
        const result = await handler({ userId: signedIn.userId, body, scenario: scenario?.data });
        status = 200;
        send(res, 200, result);
      };
      // Everything this request writes for the person is refused if their account is deleted while it
      // runs (Store.refuseIfCutOff). A sign-in with no date (mock mode's test identities) isn't checked.
      const signedIn = user;
      if (issuedAt === undefined) return await serve(signedIn);
      return await requestCredential.run({ userId: signedIn.userId, issuedAt }, () => serve(signedIn));
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
 * What came back from the sign-in page, for the log: parameter NAMES (shortened, at most 12) and whether
 * the values we forward were well-formed. Never a value, so no id, token or session address is logged.
 * It exists so a failed connect can be told apart: nothing came back, only some fields did, or the
 * fields came back malformed (for example an attempt id with other parameters glued onto it).
 */
function describeReturn(url: URL, verifier: boolean): Record<string, unknown> {
  const names = [...new Set(url.searchParams.keys())].slice(0, 12).map((name) => (/^[A-Za-z0-9_.-]{1,32}$/.test(name) ? name : "other"));
  const q = url.searchParams;
  const status = q.get("status");
  return verifier
    ? { kind: "verify", names, sessionUriOk: (q.get("session_uri") ?? "") !== "" }
    : {
        kind: "return",
        names,
        attemptOk: UUID.test(q.get("attempt") ?? ""),
        statusOk: status === "success" || status === "failed",
        accountOk: OPAQUE.test(q.get("connected_account_id") ?? ""),
      };
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
