import type { IncomingMessage, ServerResponse } from "node:http";
import { type AuthenticatedUser, requireFullAccess, type SessionVerifier } from "../auth.js";
import { AppError } from "../errors.js";
import type { DocumentRow, DocumentSummaryRow, Store } from "../store.js";
import type { DocumentView } from "./contracts.js";
import { isoDay, LOGBOOK_MAX_BODY_BYTES, type LogbookView, LogbookStateSchema, parseDaySummary, readLogbookView } from "./logbook.js";
import type { MemoryChat } from "../memory/chat.js";
import { memoryRoutes } from "../memory/routes.js";
import type { MemoryService } from "../memory/service.js";
import { threadRoutes } from "../messages/routes.js";
import type { ThreadService } from "../messages/service.js";
import type { WebAuth, WebSessionContext } from "./sessions.js";
import { LINK_REAUTH_MS, type SocialSignIn } from "./social.js";
import type { AccountEraser } from "../account.js";
import { OwnerPanel } from "./owner.js";

/**
 * The `/v1/web/…` routes (ADR-600). Each route says who may call it:
 *  - `public`: no session (signing in).
 *  - `phone`: the iPhone's own session (Authorization header) only.
 *  - `either`: the iPhone's session, or a browser session cookie.
 *  - `browser`: a browser session cookie only.
 *  - `device`: the iPhone's own session, a guest's too (ADR-819: a guest iPhone may sign in to an account).
 * A cookie request that changes something must pass the same-origin check (`assertSameOrigin`).
 */

export type Access = "public" | "phone" | "either" | "browser" | "device";

export interface WebCaller {
  userId: string;
  /** Set when the caller is a browser session. */
  session: WebSessionContext | null;
}

export interface Reply {
  status: number;
  body?: unknown;
  setCookie?: string | string[];
  /** A redirect (303) instead of JSON: the browser steps of Apple and Google sign-in (ADR-818). */
  redirect?: string;
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
  run(input: { caller: WebCaller | null; params: string[]; query: URLSearchParams; body: unknown; req: IncomingMessage; now: Date }): Promise<Reply>;
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
    /** The Messages copy for the web. Without it those routes don't exist. */
    thread?: ThreadService,
    /** Apple and Google sign-in (ADR-818). Without it the sign-in page offers the code only. */
    private readonly social?: SocialSignIn | null,
    /** Deleting the account from a browser (ADR-818: an account made on the web has no iPhone to do it). */
    account?: AccountEraser | null,
    /** This server's device sign-in (ADR-563), so an iPhone can use another account (ADR-819). */
    devices?: { userIdFor(deviceId: unknown): string | null } | null,
    /** The owner panel (decision 2026-11-09-usage-counts-on-by-default). Without it those routes don't exist. */
    owner?: OwnerPanel | null,
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
      // ---------------------------------------------------------------- Apple and Google (ADR-818)
      {
        method: "GET",
        pattern: /^\/v1\/web\/sign-in-options$/,
        template: "GET /v1/web/sign-in-options",
        access: "public",
        run: async () => ({ status: 200, body: this.social ? this.social.options() : { providers: [] } }),
      },
      ...(social
        ? ([
            {
              method: "GET",
              pattern: /^\/v1\/web\/oauth\/start$/,
              template: "GET /v1/web/oauth/start",
              access: "public",
              run: async ({ req, query, now }) => redirect(await social.start(req, query, now)),
            },
            {
              method: "GET",
              pattern: /^\/v1\/web\/oauth\/callback$/,
              template: "GET /v1/web/oauth/callback",
              access: "public",
              run: async ({ req, query, now }) => redirect(await social.callback(req, query, now)),
            },
            {
              method: "POST",
              pattern: /^\/v1\/web\/oauth\/tickets$/,
              template: "POST /v1/web/oauth/tickets",
              access: "phone",
              run: async ({ caller, body, now }) => ({ status: 200, body: await social.ticket(caller!.userId, body, now) }),
            },
            {
              // "Create my Doddy account", after Google or Apple. Public (its own one-time cookie), same origin.
              method: "POST",
              pattern: /^\/v1\/web\/signup$/,
              template: "POST /v1/web/signup",
              access: "public",
              run: async ({ req, now }) => {
                const done = await social.signup(req, now);
                return { status: 200, body: { session: done.view, created: done.created, provider: done.provider }, setCookie: done.setCookies };
              },
            },
            {
              method: "POST",
              pattern: /^\/v1\/web\/oauth\/complete$/,
              template: "POST /v1/web/oauth/complete",
              access: "phone",
              run: async ({ caller, body, now }) => ({ status: 200, body: await social.complete(caller!.userId, body, now) }),
            },
            ...(devices
              ? ([
                  {
                    method: "POST",
                    pattern: /^\/v1\/web\/oauth\/join-tickets$/,
                    template: "POST /v1/web/oauth/join-tickets",
                    access: "device",
                    run: async ({ caller, body, now }) => ({ status: 200, body: await social.joinTicket(caller!.userId, body, now) }),
                  },
                  {
                    method: "POST",
                    pattern: /^\/v1\/web\/oauth\/join$/,
                    template: "POST /v1/web/oauth/join",
                    access: "device",
                    run: async ({ caller, body, now }) => ({ status: 200, body: await social.join(caller!.userId, body, now, (id) => devices.userIdFor(id)) }),
                  },
                  {
                    method: "POST",
                    pattern: /^\/v1\/web\/device-account$/,
                    template: "POST /v1/web/device-account",
                    access: "device",
                    run: async ({ caller, body }) => ({ status: 200, body: await social.deviceAccount(caller!.userId, body, (id) => devices.userIdFor(id)) }),
                  },
                  {
                    method: "POST",
                    pattern: /^\/v1\/web\/device-account\/leave$/,
                    template: "POST /v1/web/device-account/leave",
                    access: "device",
                    run: async ({ caller, body }) => ({ status: 200, body: await social.leave(caller!.userId, body, (id) => devices.userIdFor(id)) }),
                  },
                ] satisfies Route[])
              : []),
            {
              method: "GET",
              pattern: /^\/v1\/web\/identities$/,
              template: "GET /v1/web/identities",
              access: "either",
              run: async ({ caller }) => ({ status: 200, body: { identities: await social.list(caller!.userId) } }),
            },
            {
              method: "DELETE",
              pattern: /^\/v1\/web\/identities\/([0-9a-f-]{36})$/,
              template: "DELETE /v1/web/identities/:id",
              access: "either",
              run: async ({ caller, params, now }) => {
                social.assertMayChange(caller!.session, now);
                await social.unlink(caller!.userId, params[0]!);
                return { status: 200, body: { unlinked: true } };
              },
            },
          ] satisfies Route[])
        : []),
      ...(account
        ? ([
            {
              // Whether this browser may delete the account: only one made on the web. An iPhone's
              // account is deleted on the iPhone, as before (ADR-674).
              method: "GET",
              pattern: /^\/v1\/web\/account$/,
              template: "GET /v1/web/account",
              access: "browser",
              run: async ({ caller }) => ({ status: 200, body: { madeOnWeb: await this.store.isWebAccount(caller!.userId) } }),
            },
            {
              // Deletes the whole account, as the iPhone's Delete account does (ADR-674): only an account
              // made on the web, from a browser signed in within the last 15 minutes, with the word sent
              // back. The answer is the receipt.
              method: "POST",
              pattern: /^\/v1\/web\/account\/delete$/,
              template: "POST /v1/web/account/delete",
              access: "browser",
              run: async ({ caller, body, now }) => {
                const confirm = typeof body === "object" && body !== null ? (body as Record<string, unknown>).confirm : undefined;
                if (confirm !== "delete" || Object.keys(body as object).length !== 1) throw new AppError("invalid_request");
                if (!(await this.store.isWebAccount(caller!.userId))) {
                  throw new AppError("refused", { message: "This account belongs to your iPhone: delete it in Doddy on the iPhone." });
                }
                if (now.getTime() - caller!.session!.createdAt > LINK_REAUTH_MS) {
                  throw new AppError("refused", { message: "For safety, sign in again, then delete within 15 minutes." });
                }
                const erasure = await account.erase(caller!.userId);
                return { status: 200, body: erasure, setCookie: this.auth.clearCookie() };
              },
            },
          ] satisfies Route[])
        : []),
      ...(memory ? memoryRoutes(memory) : []),
      ...(thread ? threadRoutes(thread) : []),
      // ---------------------------------------------------------------- Owner panel (decision 2026-11-09-usage-counts-on-by-default)
      // Only the accounts in DODDY_OWNER_ACCOUNTS; anyone else is told there is nothing here. A browser
      // only (never the iPhone's session), within OWNER_FRESH_MS of signing in, and each use recorded
      // before it is shown (`OwnerPanel.open`, decision 2026-11-14-owner-panel-fresh-sign-in).
      ...(owner
        ? ([
            {
              // Whether to show the menu's "Admin" link. It holds no data, so it needs no fresh sign-in.
              method: "GET",
              pattern: /^\/v1\/web\/owner$/,
              template: "GET /v1/web/owner",
              access: "browser",
              run: async ({ caller }) => {
                await owner.requireOwner(caller!.userId);
                return { status: 200, body: { owner: true } };
              },
            },
            {
              method: "GET",
              pattern: /^\/v1\/web\/owner\/overview$/,
              template: "GET /v1/web/owner/overview",
              access: "browser",
              run: async ({ caller, query, now }) => {
                await owner.open(caller!, "overview", null, now);
                return { status: 200, body: await owner.overview(now, OwnerPanel.period(query.get("days") ?? undefined)) };
              },
            },
            {
              method: "GET",
              pattern: /^\/v1\/web\/owner\/accounts$/,
              template: "GET /v1/web/owner/accounts",
              access: "browser",
              run: async ({ caller, query, now }) => {
                await owner.open(caller!, "accounts", null, now);
                return { status: 200, body: await owner.accounts(now, OwnerPanel.period(query.get("days") ?? undefined)) };
              },
            },
            {
              method: "GET",
              pattern: /^\/v1\/web\/owner\/accounts\/([A-Za-z0-9-]{1,64})\/logbook$/,
              template: "GET /v1/web/owner/accounts/:id/logbook",
              access: "browser",
              run: async ({ caller, params, now }) => {
                await owner.open(caller!, "account_logbook", params[0]!, now);
                return { status: 200, body: await owner.accountLogbook(params[0]!, now) };
              },
            },
          ] satisfies Route[])
        : []),
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
  async serve(match: { route: Route; params: string[] }, req: IncomingMessage, res: ServerResponse, now: Date, query: URLSearchParams = new URLSearchParams()): Promise<number> {
    const { route } = match;
    if (route === notFoundRoute) throw new AppError("not_found");
    const caller = await this.caller(route.access, req, res, now);
    const unsafe = route.method !== "GET" && route.method !== "HEAD";
    // A browser request that changes something (signing in included) must come from the web app.
    if (unsafe && (route.access === "public" || caller?.session)) this.auth.assertSameOrigin(req);
    const body = route.method === "POST" || route.method === "PUT" ? await readJson(req, route.maxBodyBytes ?? this.maxBodyBytes) : undefined;
    const reply = await route.run({ caller, params: match.params, query, body, req, now });
    if (reply.setCookie && reply.setCookie.length > 0) res.setHeader("set-cookie", reply.setCookie);
    if (reply.redirect !== undefined) {
      // The callback's address carries Supabase's code: no Referer to the next page, nothing cached.
      res.writeHead(303, { location: reply.redirect, "cache-control": "no-store", "referrer-policy": "no-referrer", "content-length": 0 });
      res.end();
      return 303;
    }
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
      // A guest iPhone (ADR-587) can't open the web workspace: it has Ask Doddy only. It may still
      // sign in to an account it proves with Google or Apple (`device`, ADR-819).
      if (access !== "device") requireFullAccess(user);
      return { userId: user.userId, session: null };
    }
    if (access === "phone" || access === "device") throw new AppError("unauthenticated");
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

function redirect(outcome: { location: string; setCookies: string[] }): Reply {
  return { status: 303, redirect: outcome.location, setCookie: outcome.setCookies };
}
