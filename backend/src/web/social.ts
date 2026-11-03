import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";
import { SupabaseSessionVerifier, type FetchJson } from "../auth.js";
import { clientAddress, clientKey } from "../clientAddress.js";
import type { WebSocialSettings } from "../config.js";
import { AppError } from "../errors.js";
import type { Store, WebIdentityRow } from "../store.js";
import { describeAgent, MAX_SESSIONS_PER_USER, readCookie, SESSION_IDLE_MS, SESSION_TTL_MS, type WebAuth, type WebSessionContext } from "./sessions.js";

/**
 * Apple and Google sign-in for Doddy Web (ADR-700), through Supabase Auth.
 *
 * A Doddy account is still the iPhone's (ADR-563); Apple or Google is a second way into the same
 * account, and only after the person links it from a place they are already signed in:
 *  - from the iPhone: Settings › Doddy on the web › Link Google (or Apple). The phone gets a
 *    one-time ticket (`POST /v1/web/oauth/tickets`) and opens it in the system sign-in sheet;
 *  - from a browser already signed in with a code: Settings › Sign-in methods › Link.
 * After that, "Continue with Google" on the sign-in page opens a browser session for that account.
 * A Google or Apple account linked to nobody opens nothing and creates nothing: accounts are never
 * made or merged behind the person's back (ADR-600).
 *
 * The flow is OAuth 2.0 with PKCE, run by this server, so the browser never holds a Supabase token:
 *  1. `GET /v1/web/oauth/start` keeps a random verifier and the intent in `web_oauth_states`, sets
 *     a ten-minute HttpOnly, SameSite=Lax state cookie (Lax: the callback is a navigation from
 *     Supabase's site) and sends the browser to Supabase's `/authorize` with the code challenge.
 *  2. Supabase (after Apple or Google) sends the browser to `GET /v1/web/oauth/callback?code=…`.
 *  3. The state row is used once; the code is exchanged with the verifier; the access token is
 *     checked like any Supabase session (`SupabaseSessionVerifier`: signature, issuer, expiry, and
 *     Apple or Google only). Its `sub` is the identity that is linked or signed in with.
 * A code stolen from the address bar is useless without the verifier, which never leaves this server,
 * and a state row only works with the cookie of the browser that started it.
 * Supabase's refresh token is not kept.
 */

export type SocialProvider = "google" | "apple";
export type SocialIntent = "signin" | "link";
/** Where the person goes back to: the web app, or the iPhone's sign-in sheet. */
export type SocialReturn = "web" | "app";

/** A sign-in in progress lasts this long (the person may type a password or approve on a phone). */
export const OAUTH_STATE_TTL_MS = 10 * 60_000;
/** An iPhone's ticket must be opened this soon; the sign-in then has OAUTH_STATE_TTL_MS. */
export const OAUTH_TICKET_TTL_MS = 5 * 60_000;
/** Starts and callbacks per client per quarter hour, and tickets per user per hour. */
export const SOCIAL_LIMITS = { perClientPerQuarter: 30, ticketsPerUserPerHour: 20 } as const;

const STATE = /^[A-Za-z0-9_-]{43}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const sha256 = (value: string) => createHash("sha256").update(value).digest("hex");
const stateHash = (token: string) => sha256(`doddy-web-oauth:v1:${token}`);

/** Posts JSON and reads JSON back; injectable for tests. `status` is the HTTP status. */
export type PostJson = (url: string, init: { headers: Record<string, string>; body: string; signal: AbortSignal }) => Promise<{ status: number; body: unknown }>;

const defaultPostJson: PostJson = async (url, init) => {
  const response = await fetch(url, { method: "POST", headers: init.headers, body: init.body, signal: init.signal, redirect: "error" });
  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  return { status: response.status, body };
};

export interface SignInOptions {
  providers: SocialProvider[];
}

export interface IdentityView {
  id: string;
  provider: SocialProvider;
  linkedAt: string;
}

/** What a finished (or failed) sign-in does next: a redirect, and cookies to set. */
export interface SocialOutcome {
  location: string;
  setCookies: string[];
}

/** Why a sign-in didn't finish, as the page shows it (`?signin=` or `?link=`). Never a provider's own text. */
export type SocialResult = "linked" | "already" | "taken" | "not_linked" | "canceled" | "failed" | "busy" | "signed_out";

export class SocialSignIn {
  readonly providers: readonly SocialProvider[];
  private readonly projectUrl: string;
  private readonly publishableKey: string;
  private readonly verifier: SupabaseSessionVerifier;
  private readonly postJson: PostJson;
  private readonly stateCookie: string;
  private readonly secure: boolean;
  private readonly callbackUrl: string;
  private readonly appReturn: string;

  constructor(
    private readonly store: Store,
    private readonly web: WebAuth,
    settings: WebSocialSettings,
    private readonly o: {
      /** Where the iPhone's sign-in sheet ends: the app's own scheme (DODDY_APP_RETURN_URL's). */
      appScheme: string;
      trustProxy: boolean;
      postJson?: PostJson;
      fetchJson?: FetchJson;
      timeoutMs?: number;
      log?: (line: Record<string, unknown>) => void;
    },
  ) {
    this.providers = settings.providers;
    this.projectUrl = settings.projectUrl;
    this.publishableKey = settings.publishableKey;
    this.verifier = new SupabaseSessionVerifier({ projectUrl: settings.projectUrl, providers: ["apple", "google"], ...(o.fetchJson ? { fetchJson: o.fetchJson } : {}) });
    this.postJson = o.postJson ?? defaultPostJson;
    this.secure = web.origin.startsWith("https:");
    this.stateCookie = this.secure ? "__Host-doddy_oauth" : "doddy_oauth";
    this.callbackUrl = `${web.origin}/v1/web/oauth/callback`;
    this.appReturn = `${o.appScheme}://web-sign-in/return`;
  }

  options(): SignInOptions {
    return { providers: [...this.providers] };
  }

  /** The app's callback scheme, so the iPhone's sheet knows when the sign-in has finished. */
  get callbackScheme(): string {
    return this.o.appScheme;
  }

  // ---------------------------------------------------------------- iPhone side

  /** A one-time address the iPhone opens to link Apple or Google to its own account. */
  async ticket(userId: string, body: unknown, now: Date): Promise<{ url: string; expiresAt: string; callbackScheme: string }> {
    const provider = this.provider(typeof body === "object" && body !== null ? (body as Record<string, unknown>).provider : undefined);
    if (!provider || Object.keys(body as object).length !== 1) throw new AppError("invalid_request");
    const hour = `day:${now.toISOString().slice(0, 13)}`;
    const allowed = await this.store.reserveUsage([{ counter: `web_oauth_tickets:${sha256(userId)}`, period: hour, limit: SOCIAL_LIMITS.ticketsPerUserPerHour }], 1);
    if (!allowed) throw new AppError("rate_limited", { message: "Too many tries this hour. Try again later." });
    const token = randomBytes(32).toString("base64url");
    await this.store.createWebOAuthState({
      stateHash: stateHash(token),
      userId,
      provider,
      intent: "link",
      returnTo: "app",
      verifier: randomBytes(48).toString("base64url"),
      now: now.getTime(),
      ttlMs: OAUTH_TICKET_TTL_MS,
    });
    return { url: `${this.web.origin}/v1/web/oauth/start?ticket=${token}`, expiresAt: new Date(now.getTime() + OAUTH_TICKET_TTL_MS).toISOString(), callbackScheme: this.o.appScheme };
  }

  // ---------------------------------------------------------------- browser side

  /**
   * `GET /v1/web/oauth/start`. With `ticket` (the iPhone): that ticket's sign-in. Otherwise
   * `provider` and `intent`; `link` needs the browser's own session (its cookie is SameSite=Strict,
   * so another site can't start a link for someone).
   */
  async start(req: IncomingMessage, query: URLSearchParams, now: Date): Promise<SocialOutcome> {
    const ticket = query.get("ticket");
    if (ticket !== null) return this.startFromTicket(req, ticket, now);
    const intent: SocialIntent = query.get("intent") === "link" ? "link" : "signin";
    const back = (result: SocialResult) => this.done({ intent, returnTo: "web", result });
    if (!(await this.withinLimit(req, now))) return back("busy");
    const provider = this.provider(query.get("provider"));
    if (!provider) return back("failed");
    let session: WebSessionContext | null = null;
    if (intent === "link") {
      session = await this.web.fromCookie(req, now);
      if (!session) return back("signed_out");
    }
    const token = randomBytes(32).toString("base64url");
    const verifier = randomBytes(48).toString("base64url");
    await this.store.createWebOAuthState({
      stateHash: stateHash(token),
      userId: session?.userId ?? null,
      provider,
      intent,
      returnTo: "web",
      verifier,
      now: now.getTime(),
      ttlMs: OAUTH_STATE_TTL_MS,
    });
    return { location: this.authorizeUrl(provider, verifier), setCookies: [this.stateCookieValue(token, OAUTH_STATE_TTL_MS / 1000)] };
  }

  /** The iPhone's ticket: its row was made with the phone's session; this browser takes it over once. */
  private async startFromTicket(req: IncomingMessage, ticket: string, now: Date): Promise<SocialOutcome> {
    const back = (result: SocialResult) => this.done({ intent: "link", returnTo: "app", result });
    if (!(await this.withinLimit(req, now))) return back("busy");
    if (!STATE.test(ticket)) return back("failed");
    // The ticket is used once here; a fresh state (new token, same verifier) carries the sign-in on.
    const row = await this.store.consumeWebOAuthState(stateHash(ticket), now.getTime());
    if (!row || row.intent !== "link" || row.return_to !== "app" || !row.user_id) return back("failed");
    const provider = this.provider(row.provider);
    if (!provider) return back("failed");
    const token = randomBytes(32).toString("base64url");
    await this.store.createWebOAuthState({
      stateHash: stateHash(token),
      userId: row.user_id,
      provider,
      intent: "link",
      returnTo: "app",
      verifier: row.verifier,
      now: now.getTime(),
      ttlMs: OAUTH_STATE_TTL_MS,
    });
    return { location: this.authorizeUrl(provider, row.verifier), setCookies: [this.stateCookieValue(token, OAUTH_STATE_TTL_MS / 1000)] };
  }

  /** `GET /v1/web/oauth/callback`: Supabase sends the browser back here with `code` (or `error`). */
  async callback(req: IncomingMessage, query: URLSearchParams, now: Date): Promise<SocialOutcome> {
    const clear = this.stateCookieValue("", 0);
    const token = readCookie(header(req, "cookie"), this.stateCookie);
    // Without our cookie we can't tell which sign-in this was, or where to send the person back.
    if (!token || !STATE.test(token)) return withCookie(this.done({ intent: "signin", returnTo: "web", result: "failed" }), clear);
    if (!(await this.withinLimit(req, now))) return withCookie(this.done({ intent: "signin", returnTo: "web", result: "busy" }), clear);
    const row = await this.store.consumeWebOAuthState(stateHash(token), now.getTime());
    if (!row) return withCookie(this.done({ intent: "signin", returnTo: "web", result: "failed" }), clear);
    const intent: SocialIntent = row.intent === "link" ? "link" : "signin";
    const returnTo: SocialReturn = row.return_to === "app" ? "app" : "web";
    const provider = this.provider(row.provider);
    const back = (result: SocialResult, extra: string[] = []) => withCookie(this.done({ intent, returnTo, result, ...(provider ? { provider } : {}) }), clear, ...extra);

    const code = query.get("code");
    if (!code) {
      // Supabase's own error words are not shown; the person cancelled, or the provider refused.
      const error = query.get("error") ?? "";
      this.log({ event: "web_oauth_returned_error", provider: row.provider, error: /^[a-z_]{1,40}$/.test(error) ? error : "other" });
      return back(error === "access_denied" ? "canceled" : "failed");
    }
    if (!provider || code.length > 512 || !/^[A-Za-z0-9_.~-]+$/.test(code)) return back("failed");

    let identityId: string;
    try {
      identityId = await this.exchange(code, row.verifier, now);
    } catch (error) {
      this.log({ event: "web_oauth_exchange_failed", provider, reason: error instanceof AppError ? error.code : "unexpected" });
      return back("failed");
    }

    if (intent === "link") {
      if (!row.user_id) return back("failed");
      const linked = await this.store.linkWebIdentity(identityId, row.user_id, provider, now.getTime());
      this.log({ event: "web_identity_link", provider, result: linked });
      return back(linked);
    }
    const userId = await this.store.webIdentityOwner(identityId);
    if (!userId) {
      this.log({ event: "web_social_signin", provider, result: "not_linked" });
      return back("not_linked");
    }
    const sessionToken = randomBytes(32).toString("base64url");
    const agent = describeAgent(header(req, "user-agent"));
    await this.store.openWebSession(userId, {
      session: { sessionId: randomUUID(), tokenHash: this.web.tokenHashOf(sessionToken), browser: agent.browser, os: agent.os, expiresAt: now.getTime() + SESSION_TTL_MS },
      now: now.getTime(),
      idleMs: SESSION_IDLE_MS,
      maxSessions: MAX_SESSIONS_PER_USER,
    });
    this.log({ event: "web_social_signin", provider, result: "signed_in" });
    return { location: "/", setCookies: [clear, this.web.sessionCookie(sessionToken)] };
  }

  // ---------------------------------------------------------------- linked sign-ins

  async list(userId: string): Promise<IdentityView[]> {
    return (await this.store.webIdentities(userId)).map(identityView).filter((v): v is IdentityView => v !== null);
  }

  async unlink(userId: string, identityId: string): Promise<void> {
    if (!UUID.test(identityId) || !(await this.store.unlinkWebIdentity(userId, identityId))) throw new AppError("not_found");
  }

  // ---------------------------------------------------------------- helpers

  private authorizeUrl(provider: SocialProvider, verifier: string): string {
    const challenge = createHash("sha256").update(verifier).digest("base64url");
    const url = new URL(`${this.projectUrl}/auth/v1/authorize`);
    url.searchParams.set("provider", provider);
    url.searchParams.set("redirect_to", this.callbackUrl);
    url.searchParams.set("code_challenge", challenge);
    url.searchParams.set("code_challenge_method", "s256");
    return url.toString();
  }

  /** Exchanges the code for a Supabase session and returns the checked user ID. Throws AppError. */
  private async exchange(code: string, verifier: string, now: Date): Promise<string> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.o.timeoutMs ?? 8_000);
    let reply: { status: number; body: unknown };
    try {
      reply = await this.postJson(`${this.projectUrl}/auth/v1/token?grant_type=pkce`, {
        headers: { apikey: this.publishableKey, "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({ auth_code: code, code_verifier: verifier }),
        signal: controller.signal,
      });
    } catch {
      throw new AppError("provider_unavailable");
    } finally {
      clearTimeout(timer);
    }
    if (reply.status !== 200) throw new AppError(reply.status >= 500 ? "provider_unavailable" : "unauthenticated");
    const accessToken = typeof reply.body === "object" && reply.body !== null ? (reply.body as Record<string, unknown>).access_token : undefined;
    if (typeof accessToken !== "string") throw new AppError("provider_unavailable");
    const user = await this.verifier.verify(`Bearer ${accessToken}`, now);
    if (!user) throw new AppError("unauthenticated");
    return user.userId;
  }

  private done(o: { intent: SocialIntent; returnTo: SocialReturn; result: SocialResult; provider?: SocialProvider }): SocialOutcome {
    const params = new URLSearchParams({ result: o.result, ...(o.provider ? { provider: o.provider } : {}) });
    if (o.returnTo === "app") return { location: `${this.appReturn}?${params}`, setCookies: [] };
    if (o.intent === "link") return { location: `/settings?link=${o.result}${o.provider ? `&provider=${o.provider}` : ""}`, setCookies: [] };
    return { location: `/sign-in?signin=${o.result}${o.provider ? `&provider=${o.provider}` : ""}`, setCookies: [] };
  }

  private provider(value: unknown): SocialProvider | null {
    return typeof value === "string" && (this.providers as readonly string[]).includes(value) ? (value as SocialProvider) : null;
  }

  private async withinLimit(req: IncomingMessage, now: Date): Promise<boolean> {
    const quarter = `day:${now.toISOString().slice(0, 14)}${String(Math.floor(now.getUTCMinutes() / 15) * 15).padStart(2, "0")}`;
    const client = `web_oauth:${sha256(`client:${clientKey(clientAddress(req, this.o.trustProxy))}`)}`;
    return this.store.reserveUsage([{ counter: client, period: quarter, limit: SOCIAL_LIMITS.perClientPerQuarter }], 1);
  }

  private stateCookieValue(value: string, maxAgeSeconds: number): string {
    return `${this.stateCookie}=${value}; Path=/; Max-Age=${maxAgeSeconds}; HttpOnly; SameSite=Lax${this.secure ? "; Secure" : ""}`;
  }

  private log(line: Record<string, unknown>): void {
    this.o.log?.({ level: "info", ...line });
  }
}

function identityView(row: WebIdentityRow): IdentityView | null {
  if (row.provider !== "google" && row.provider !== "apple") return null;
  return { id: row.identity_id, provider: row.provider, linkedAt: new Date(row.created_at).toISOString() };
}

function withCookie(outcome: SocialOutcome, ...cookies: string[]): SocialOutcome {
  return { location: outcome.location, setCookies: [...cookies, ...outcome.setCookies] };
}

function header(req: IncomingMessage, name: string): string | undefined {
  const value = req.headers[name];
  return Array.isArray(value) ? undefined : value;
}
