import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";
import { AppError } from "../errors.js";
import type { Store, WebSessionRow } from "../store.js";
import { type Browser, type LinkCode, type Os, RedeemRequestSchema, type WebSessionView } from "./contracts.js";
import type { z } from "zod";

/**
 * Doddy Web sign-in (ADR-579).
 *
 * The browser has no Apple or Google sign-in of its own yet, and the iPhone's account is a device
 * session (ADR-563). So the iPhone vouches for the browser:
 *  1. In Settings the iPhone asks for a code (`POST /v1/web/link-codes`, with its own session).
 *  2. The person types the code at the web address the phone shows. It lasts five minutes, works
 *     once, and only the newest code of a user works.
 *  3. The browser gets a session for the same user: a random token in an HttpOnly, SameSite=Strict
 *     cookie that the page's scripts can't read. The server keeps only its SHA-256.
 * A browser session can read the workspace and sign browsers out; it can't run tools, change
 * accounts or make more codes (`COOKIE_READABLE` and the web routes decide). The iPhone lists and
 * signs out browsers too.
 */

export const LINK_CODE_TTL_MS = 5 * 60_000;
export const SESSION_TTL_MS = 30 * 24 * 60 * 60_000;
/** A browser unused for this long is signed out. */
export const SESSION_IDLE_MS = 14 * 24 * 60 * 60_000;
/** `last_seen_at` is written at most this often. */
const TOUCH_EVERY_MS = 60 * 60_000;
export const MAX_SESSIONS_PER_USER = 10;

/** Wrong codes: per client address per quarter hour, and for the whole server per hour. */
export const REDEEM_LIMITS = { perClientPerQuarter: 10, servicePerHour: 120 } as const;
/** Codes the iPhone may ask for per user per hour. */
export const CODES_PER_USER_PER_HOUR = 20;

/** 30 letters and digits, without I, L, O, U, 0 and 1 (they read alike). */
export const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789";
const CODE_LENGTH = 8;
const TOKEN = /^[A-Za-z0-9_-]{43}$/;

/** Read-only routes elsewhere in the API that a browser session may also use. Everything else needs the iPhone's session. */
export const COOKIE_READABLE: ReadonlySet<string> = new Set(["GET /v1/tools", "GET /v1/tools/receipts"]);

export interface WebSessionContext {
  sessionId: string;
  userId: string;
}

const sha256 = (value: string) => createHash("sha256").update(value).digest("hex");
const codeHash = (code: string) => sha256(`doddy-web-link:v1:${code}`);
const tokenHash = (token: string) => sha256(`doddy-web-session:v1:${token}`);

/** A uniformly random code (rejection sampling keeps every letter equally likely). */
export function newLinkCode(random: (size: number) => Buffer = randomBytes): string {
  let code = "";
  const limit = 256 - (256 % CODE_ALPHABET.length);
  while (code.length < CODE_LENGTH) {
    for (const byte of random(16)) {
      if (byte >= limit) continue;
      code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
      if (code.length === CODE_LENGTH) break;
    }
  }
  return code;
}

/** What a person typed, as the canonical eight characters, or null when it can't be a code. */
export function normalizeCode(typed: string): string | null {
  const plain = typed.toUpperCase().replace(/[\s-]/g, "");
  if (plain.length !== CODE_LENGTH) return null;
  for (const ch of plain) if (!CODE_ALPHABET.includes(ch)) return null;
  return plain;
}

/** Browser and system from the User-Agent, coarse on purpose. The header itself is never stored. */
export function describeAgent(userAgent: string | undefined): { browser: z.infer<typeof Browser>; os: z.infer<typeof Os> } {
  const ua = userAgent ?? "";
  const browser = /Edg(e|A|iOS)?\//.test(ua)
    ? "edge"
    : /OPR\/|Opera/.test(ua)
      ? "opera"
      : /Firefox\/|FxiOS\//.test(ua)
        ? "firefox"
        : /Chrome\/|CriOS\//.test(ua)
          ? "chrome"
          : /Safari\//.test(ua) && /Version\//.test(ua)
            ? "safari"
            : "other";
  const os = /iPad/.test(ua)
    ? "ipados"
    : /iPhone|iPod/.test(ua)
      ? "ios"
      : /Android/.test(ua)
        ? "android"
        : /CrOS/.test(ua)
          ? "chromeos"
          : /Windows/.test(ua)
            ? "windows"
            : /Mac OS X|Macintosh/.test(ua)
              ? "macos"
              : /Linux/.test(ua)
                ? "linux"
                : "other";
  return { browser, os };
}

export class WebAuth {
  readonly cookieName: string;
  private readonly secure: boolean;

  constructor(
    private readonly store: Store,
    readonly origin: string,
    private readonly trustProxy: boolean,
  ) {
    this.secure = origin.startsWith("https:");
    // `__Host-` makes the browser refuse the cookie unless it is Secure, host-only and Path=/.
    this.cookieName = this.secure ? "__Host-doddy_web" : "doddy_web";
  }

  // ---------------------------------------------------------------- iPhone side

  /** A fresh code for `userId` (the iPhone's session). Earlier codes of theirs stop working. */
  async createLinkCode(userId: string, now: Date): Promise<LinkCode> {
    const hour = `day:${now.toISOString().slice(0, 13)}`;
    const allowed = await this.store.reserveUsage([{ counter: `web_codes:${sha256(userId)}`, period: hour, limit: CODES_PER_USER_PER_HOUR }], 1);
    if (!allowed) throw new AppError("rate_limited", { message: "Too many sign-in codes this hour. Try again later.", retryAfterSeconds: secondsToNextHour(now) });
    const code = newLinkCode();
    await this.store.createWebLinkCode(userId, codeHash(code), now.getTime(), LINK_CODE_TTL_MS);
    return { code: `${code.slice(0, 4)}-${code.slice(4)}`, expiresAt: new Date(now.getTime() + LINK_CODE_TTL_MS).toISOString(), webOrigin: this.origin };
  }

  // ---------------------------------------------------------------- browser side

  /**
   * Signs a browser in with a code. Returns the session and the Set-Cookie value. Wrong codes count
   * against the client's address and the whole server, checked before the code is looked at.
   */
  async redeem(req: IncomingMessage, body: unknown, now: Date): Promise<{ view: WebSessionView; setCookie: string }> {
    const parsed = RedeemRequestSchema.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");
    const quarter = `day:${now.toISOString().slice(0, 14)}${String(Math.floor(now.getUTCMinutes() / 15) * 15).padStart(2, "0")}`;
    const hour = `day:${now.toISOString().slice(0, 13)}`;
    const client = `web_redeem_fail:${sha256(`client:${this.clientAddress(req)}`)}`;
    const service = "web_redeem_fail:service";
    if ((await this.store.usage(client, quarter)) >= REDEEM_LIMITS.perClientPerQuarter || (await this.store.usage(service, hour)) >= REDEEM_LIMITS.servicePerHour) {
      throw new AppError("rate_limited", { message: "Too many tries. Wait a few minutes, then get a new code on your iPhone.", retryAfterSeconds: 15 * 60 });
    }
    const code = normalizeCode(parsed.data.code);
    const token = randomBytes(32).toString("base64url");
    const agent = describeAgent(header(req, "user-agent"));
    const sessionId = randomUUID();
    const expiresAt = now.getTime() + SESSION_TTL_MS;
    const userId = code
      ? await this.store.redeemWebLinkCode({
          codeHash: codeHash(code),
          session: { sessionId, tokenHash: tokenHash(token), browser: agent.browser, os: agent.os, expiresAt },
          now: now.getTime(),
          idleMs: SESSION_IDLE_MS,
          maxSessions: MAX_SESSIONS_PER_USER,
        })
      : null;
    if (!userId) {
      await this.store.reserveUsage([{ counter: client, period: quarter, limit: Number.MAX_SAFE_INTEGER }, { counter: service, period: hour, limit: Number.MAX_SAFE_INTEGER }], 1);
      throw new AppError("unauthenticated", { message: "That code didn't work. Codes last five minutes and work once: get a new one on your iPhone." });
    }
    const row: WebSessionRow = { session_id: sessionId, user_id: userId, browser: agent.browser, os: agent.os, created_at: now.getTime(), last_seen_at: now.getTime(), expires_at: expiresAt };
    return { view: view(row, sessionId), setCookie: this.cookie(token, SESSION_TTL_MS / 1000) };
  }

  /** The browser session behind the request's cookie, or null. */
  async fromCookie(req: IncomingMessage, now: Date): Promise<WebSessionContext | null> {
    const token = readCookie(header(req, "cookie"), this.cookieName);
    if (!token || !TOKEN.test(token)) return null;
    const row = await this.store.webSessionByToken(tokenHash(token), now.getTime(), SESSION_IDLE_MS);
    if (!row) return null;
    if (now.getTime() - row.last_seen_at >= TOUCH_EVERY_MS) await this.store.touchWebSession(row.session_id, now.getTime());
    return { sessionId: row.session_id, userId: row.user_id };
  }

  /** True when the request carries this server's session cookie at all (valid or not). */
  hasCookie(req: IncomingMessage): boolean {
    return readCookie(header(req, "cookie"), this.cookieName) !== null;
  }

  /**
   * Cross-site request forgery: a request that changes something with the cookie alone must come
   * from the web app's own origin and carry its header. Pages elsewhere can't set that header
   * without a CORS preflight, which this server never answers.
   */
  assertSameOrigin(req: IncomingMessage): void {
    if (header(req, "origin") !== this.origin || header(req, "x-doddy-web") !== "1") {
      throw new AppError("unauthenticated", { message: "This request didn't come from Doddy's web app." });
    }
  }

  async current(session: WebSessionContext, now: Date): Promise<WebSessionView> {
    const rows = await this.store.webSessions(session.userId, now.getTime(), SESSION_IDLE_MS, MAX_SESSIONS_PER_USER * 2);
    const row = rows.find((r) => r.session_id === session.sessionId);
    if (!row) throw new AppError("unauthenticated");
    return view(row, session.sessionId);
  }

  async list(userId: string, currentSessionId: string | null, now: Date): Promise<WebSessionView[]> {
    const rows = await this.store.webSessions(userId, now.getTime(), SESSION_IDLE_MS, MAX_SESSIONS_PER_USER * 2);
    return rows.map((row) => view(row, currentSessionId));
  }

  /** Signs one of the user's browsers out. Another user's session ID reads as not found. */
  async revoke(userId: string, sessionId: string, now: Date): Promise<void> {
    if (!/^[0-9a-f-]{36}$/.test(sessionId) || !(await this.store.revokeWebSession(userId, sessionId, now.getTime()))) throw new AppError("not_found");
  }

  /** Set-Cookie that removes the session cookie. */
  clearCookie(): string {
    return this.cookie("", 0);
  }

  private cookie(value: string, maxAgeSeconds: number): string {
    return `${this.cookieName}=${value}; Path=/; Max-Age=${maxAgeSeconds}; HttpOnly; SameSite=Strict${this.secure ? "; Secure" : ""}`;
  }

  /** The client's address: the last X-Forwarded-For entry behind one trusted proxy, else the socket's. */
  private clientAddress(req: IncomingMessage): string {
    if (this.trustProxy) {
      const forwarded = header(req, "x-forwarded-for");
      const last = forwarded?.split(",").map((part) => part.trim()).filter(Boolean).at(-1);
      if (last) return last;
    }
    return req.socket.remoteAddress ?? "unknown";
  }
}

function view(row: WebSessionRow, currentSessionId: string | null): WebSessionView {
  return {
    id: row.session_id,
    browser: row.browser as WebSessionView["browser"],
    os: row.os as WebSessionView["os"],
    createdAt: new Date(row.created_at).toISOString(),
    lastSeenAt: new Date(row.last_seen_at).toISOString(),
    expiresAt: new Date(Math.min(row.expires_at, row.last_seen_at + SESSION_IDLE_MS)).toISOString(),
    current: row.session_id === currentSessionId,
  };
}

export function readCookie(cookieHeader: string | undefined, name: string): string | null {
  if (!cookieHeader) return null;
  for (const part of cookieHeader.split(";")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    if (part.slice(0, eq).trim() === name) return part.slice(eq + 1).trim();
  }
  return null;
}

function header(req: IncomingMessage, name: string): string | undefined {
  const value = req.headers[name];
  return Array.isArray(value) ? undefined : value;
}

function secondsToNextHour(now: Date): number {
  return 3600 - (now.getUTCMinutes() * 60 + now.getUTCSeconds());
}
