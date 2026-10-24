import type { IncomingMessage, ServerResponse } from "node:http";
import { type AuthenticatedUser, requireFullAccess, type SessionVerifier } from "../auth.js";
import { AppError } from "../errors.js";
import type { DocumentRow, DocumentSummaryRow, Store } from "../store.js";
import type { DocumentView } from "./contracts.js";
import { isoDay, LOGBOOK_MAX_BODY_BYTES, type LogbookView, LogbookStateSchema, parseDaySummary, readLogbookView } from "./logbook.js";
import type { MemoryChat } from "../memory/chat.js";
import { memoryRoutes } from "../memory/routes.js";
import type { MemoryService } from "../memory/service.js";
import type { WebAuth, WebSessionContext } from "./sessions.js";

/**
 * The `/v1/web/…` routes (ADR-600). Each route says who may call it:
 *  - `public`: no session (signing in).
 *  - `phone`: the iPhone's own session (Authorization header) only.
 *  - `either`: the iPhone's session, or a browser session cookie.
 *  - `browser`: a browser session cookie only.
 * A cookie request that changes something must pass the same-origin check (`assertSameOrigin`).
 */

export type Access = "public" | "phone" | "either" | "browser";

export interface WebCaller {
  userId: string;
  /** Set when the caller is a browser session. */
  session: WebSessionContext | null;
}

export interface Reply {
  status: number;
  body?: unknown;
  setCookie?: string;
  /** A file instead of JSON. */
  file?: { name: string; mime: string; bytes: Buffer };
}

export interface Route {
  method: string;
  pattern: RegExp;
  template: string;
  access: Access;
  /** A larger body than the default, for the one route that takes a summary. */
  maxBodyBytes?: number;
  run(input: { caller: WebCaller | null; params: string[]; body: unknown; req: IncomingMessage; now: Date }): Promise<Reply>;
}

/** Documents are kept a week (ADR-564); the list says so instead of implying they stay. */
export const DOCUMENT_KEPT_DAYS = 7;
/**
 * A document still `working` after this long is not being made any more: the job runs in the
 * server's memory with an 8-minute limit, so a restart in between leaves the row behind.
 */
export const DOCUMENT_STALE_MS = 10 * 60_000;
const DOCUMENT_ID = /^[A-Za-z0-9_-]{24}$/;

export class WebRoutes {
  private readonly routes: Route[];

  constructor(
    private readonly auth: WebAuth,
    private readonly store: Store,
    private readonly verifier: SessionVerifier,
    private readonly maxBodyBytes: number,
    /** Notes and conversations kept on request, and chat over them (ADR-603). Without it those routes don't exist. */
    memory?: { service: MemoryService; chat: MemoryChat },
  ) {
    this.routes = [
      {
        method: "POST",
        pattern: /^\/v1\/web\/link-codes$/,
        template: "POST /v1/web/link-codes",
        access: "phone",
        run: async ({ caller, now }) => ({ status: 200, body: await this.auth.createLinkCode(caller!.userId, now) }),
      },
      {
        method: "POST",
        pattern: /^\/v1\/web\/session$/,
        template: "POST /v1/web/session",
        access: "public",
        run: async ({ req, body, now }) => {
          const { view, setCookie } = await this.auth.redeem(req, body, now);
          return { status: 200, body: { session: view }, setCookie };
        },
      },
      {
        method: "GET",
        pattern: /^\/v1\/web\/session$/,
        template: "GET /v1/web/session",
        access: "browser",
        run: async ({ caller, now }) => ({ status: 200, body: { session: await this.auth.current(caller!.session!, now) } }),
      },
      {
        method: "DELETE",
        pattern: /^\/v1\/web\/session$/,
        template: "DELETE /v1/web/session",
        access: "browser",
        run: async ({ caller, now }) => {
          await this.auth.revoke(caller!.userId, caller!.session!.sessionId, now);
          return { status: 200, body: { signedOut: true }, setCookie: this.auth.clearCookie() };
        },
      },
      {
        method: "GET",
        pattern: /^\/v1\/web\/sessions$/,
        template: "GET /v1/web/sessions",
        access: "either",
        run: async ({ caller, now }) => ({ status: 200, body: { sessions: await this.auth.list(caller!.userId, caller!.session?.sessionId ?? null, now) } }),
      },
      {
        method: "DELETE",
        pattern: /^\/v1\/web\/sessions\/([0-9a-f-]{36})$/,
        template: "DELETE /v1/web/sessions/:id",
        access: "either",
        run: async ({ caller, params, now }) => {
          await this.auth.revoke(caller!.userId, params[0]!, now);
          const self = caller!.session?.sessionId === params[0];
          return { status: 200, body: { signedOut: true }, ...(self ? { setCookie: this.auth.clearCookie() } : {}) };
        },
      },
      {
        method: "GET",
        pattern: /^\/v1\/web\/documents$/,
        template: "GET /v1/web/documents",
        access: "either",
        run: async ({ caller, now }) => {
          const rows = await this.store.listDocuments(caller!.userId, 100);
          return { status: 200, body: { documents: rows.map((row) => documentView(row, now)), keptDays: DOCUMENT_KEPT_DAYS } };
        },
      },
      {
        method: "GET",
        pattern: /^\/v1\/web\/documents\/([A-Za-z0-9_-]+)\/file$/,
        template: "GET /v1/web/documents/:id/file",
        access: "either",
        run: async ({ caller, params }) => {
          const id = params[0]!;
          const row = DOCUMENT_ID.test(id) ? await this.store.getOwnDocument(caller!.userId, id) : null;
          if (!row) throw new AppError("not_found", { message: "Doddy has no such document for you. Documents are kept for a week." });
          if (row.status !== "ready" || !row.body) throw new AppError("not_found", { message: "This document has no file yet." });
          return { status: 200, file: { name: row.name, mime: row.mime, bytes: row.body } };
        },
      },
      // ---------------------------------------------------------------- Logbook (ADR-602)
      {
        method: "GET",
        pattern: /^\/v1\/web\/logbook$/,
        template: "GET /v1/web/logbook",
        access: "either",
        run: async ({ caller, now }) => ({ status: 200, body: await this.logbookView(caller!.userId, now) }),
      },
      {
        method: "DELETE",
        pattern: /^\/v1\/web\/logbook$/,
        template: "DELETE /v1/web/logbook",
        access: "either",
        // Deletes every stored day and says how many went. Logbook stays on or off as it was.
        run: async ({ caller }) => ({ status: 200, body: { deletedDays: await this.store.deleteLogbookDays(caller!.userId) } }),
      },
      {
        method: "GET",
        pattern: /^\/v1\/web\/logbook\/export$/,
        template: "GET /v1/web/logbook/export",
        access: "either",
        run: async ({ caller, now }) => {
          const view = await this.logbookView(caller!.userId, now);
          const bytes = Buffer.from(`${JSON.stringify({ exportedAt: now.toISOString(), ...view }, null, 2)}\n`, "utf8");
          return { status: 200, file: { name: `doddy-logbook-${isoDay(now.getTime())}.json`, mime: "application/json", bytes } };
        },
      },
      {
        method: "PUT",
        pattern: /^\/v1\/web\/logbook\/state$/,
        template: "PUT /v1/web/logbook/state",
        access: "phone",
        run: async ({ caller, body, now }) => {
          const parsed = LogbookStateSchema.safeParse(body);
          if (!parsed.success) throw new AppError("invalid_request");
          const { deletedDays } = await this.store.setLogbookEnabled(caller!.userId, parsed.data.enabled, now.getTime());
          return { status: 200, body: { enabled: parsed.data.enabled, deletedDays } };
        },
      },
      {
        method: "PUT",
        pattern: /^\/v1\/web\/logbook\/days\/(\d{4}-\d{2}-\d{2})$/,
        template: "PUT /v1/web/logbook/days/:day",
        access: "phone",
        maxBodyBytes: LOGBOOK_MAX_BODY_BYTES,
        run: async ({ caller, params, body, now }) => {
          // Validated whole, then stored in its canonical form (defaults filled, nothing extra).
          const day = parseDaySummary(body, params[0]!, now.getTime());
          const stored = await this.store.putLogbookDay(caller!.userId, day.day, JSON.stringify(day), now.getTime());
          if (!stored) throw new AppError("capability_disabled", { message: "Logbook is off for this iPhone. Turn it on in Doddy first. Nothing was stored." });
          return { status: 200, body: { stored: true, day: day.day } };
        },
      },
      ...(memory ? memoryRoutes(memory) : []),
    ];
  }

  /** What the page reads (shared with the chat, ADR-604). */
  private logbookView(userId: string, now: Date): Promise<LogbookView> {
    return readLogbookView(this.store, userId, now);
  }

  /** The route for this request, or null when the path isn't a web route. */
  match(method: string, pathname: string): { route: Route; params: string[] } | null {
    if (!pathname.startsWith("/v1/web/")) return null;
    for (const route of this.routes) {
      const m = route.pattern.exec(pathname);
      if (m && route.method === method) return { route, params: m.slice(1) };
    }
    // A known path with another method, or an unknown web path: both are not found.
    return { route: notFoundRoute, params: [] };
  }

  /** Authenticates, checks the origin, runs the route and writes the reply. Throws AppError before writing. */
  async serve(match: { route: Route; params: string[] }, req: IncomingMessage, res: ServerResponse, now: Date): Promise<number> {
    const { route } = match;
    if (route === notFoundRoute) throw new AppError("not_found");
    const caller = await this.caller(route.access, req, res, now);
    const unsafe = route.method !== "GET" && route.method !== "HEAD";
    // A browser request that changes something (signing in included) must come from the web app.
    if (unsafe && (route.access === "public" || caller?.session)) this.auth.assertSameOrigin(req);
    const body = route.method === "POST" || route.method === "PUT" ? await readJson(req, route.maxBodyBytes ?? this.maxBodyBytes) : undefined;
    const reply = await route.run({ caller, params: match.params, body, req, now });
    if (reply.setCookie) res.setHeader("set-cookie", reply.setCookie);
    if (reply.file) {
      writeFile(res, reply.file);
      return 200;
    }
    const json = JSON.stringify(reply.body);
    // What a signed-in person reads is never cached by the browser or anything between.
    res.writeHead(reply.status, { "content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(json), "cache-control": "private, no-store" });
    res.end(json);
    return reply.status;
  }

  private async caller(access: Access, req: IncomingMessage, res: ServerResponse, now: Date): Promise<WebCaller | null> {
    if (access === "public") return null;
    const authorization = header(req, "authorization");
    if (authorization !== undefined) {
      if (access === "browser") throw new AppError("unauthenticated");
      const user: AuthenticatedUser | null = await this.verifier.verify(authorization, now);
      if (!user) throw new AppError("unauthenticated");
      // A guest iPhone (ADR-587) can't open the web workspace: it has Ask Doddy only.
      requireFullAccess(user);
      return { userId: user.userId, session: null };
    }
    if (access === "phone") throw new AppError("unauthenticated");
    const session = await this.auth.fromCookie(req, now);
    if (!session) {
      // A stale cookie is removed, so the browser stops sending it.
      if (this.auth.hasCookie(req)) res.setHeader("set-cookie", this.auth.clearCookie());
      throw new AppError("unauthenticated", { message: "You're signed out. Get a sign-in code on your iPhone." });
    }
    return { userId: session.userId, session };
  }
}

const notFoundRoute: Route = {
  method: "NONE",
  pattern: /^$/,
  template: "/v1/web/:unmatched",
  access: "public",
  run: async () => {
    throw new AppError("not_found");
  },
};

const KINDS: Record<string, DocumentView["kind"]> = {
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": "deck",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "doc",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "spreadsheet",
  "application/pdf": "pdf",
  "text/markdown; charset=utf-8": "text",
};

export function documentView(row: DocumentSummaryRow | DocumentRow, now: Date): DocumentView {
  const stale = row.status === "working" && now.getTime() - row.created_at > DOCUMENT_STALE_MS;
  const size = "size" in row ? row.size : row.body ? row.body.length : null;
  return {
    id: row.id,
    name: row.name,
    kind: KINDS[row.mime] ?? "file",
    status: stale ? "interrupted" : row.status,
    createdAt: new Date(row.created_at).toISOString(),
    deleteAfter: new Date(row.created_at + DOCUMENT_KEPT_DAYS * 86_400_000).toISOString(),
    sizeBytes: row.status === "ready" ? (size ?? null) : null,
  };
}

/**
 * A download, never shown inline: the file is served on the web app's own origin, so the browser
 * must not run it. `sandbox` stops scripts even if a browser ignored the attachment.
 */
function writeFile(res: ServerResponse, file: { name: string; mime: string; bytes: Buffer }): void {
  const ascii = file.name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  res.writeHead(200, {
    "content-type": file.mime,
    "content-length": file.bytes.length,
    "content-disposition": `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(file.name)}`,
    "content-security-policy": "sandbox; default-src 'none'",
    "cache-control": "private, no-store",
  });
  res.end(file.bytes);
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

function header(req: IncomingMessage, name: string): string | undefined {
  const value = req.headers[name];
  return Array.isArray(value) ? undefined : value;
}
