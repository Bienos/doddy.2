import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";
import { SupabaseSessionVerifier, type FetchJson } from "../auth.js";
import { clientAddress, clientKey } from "../clientAddress.js";
import type { WebSocialSettings } from "../config.js";
import { AppError } from "../errors.js";
import { type Store, SUPABASE_AUTH_CLEANUP as SUPABASE_AUTH, type WebIdentityRow } from "../store.js";
import type { WebSessionView } from "./contracts.js";
import { readCookie, type WebAuth, type WebSessionContext } from "./sessions.js";

/**
 * Apple and Google sign-in for Doddy Web (ADR-700), through Supabase Auth.
 *
 * A Doddy account is still the iPhone's (ADR-563); Apple or Google is a second way into the same
 * account, and only after the person links it from a place they are already signed in:
 *  - from the iPhone: Settings › Doddy on the web › Link Google (or Apple). The phone gets a
 *    one-time ticket (`POST /v1/web/oauth/tickets`) and opens it in the system sign-in sheet;
 *  - from a browser already signed in with a code: Settings › Sign-in methods › Link.
 * After that, "Continue with Google" on the sign-in page opens a browser session for that account.
 *
 * Two rules keep a link from being planted (security review of 3 Nov):
 *  - The iPhone's sheet links nothing by itself. It ends with a one-time confirmation code at the
 *    app's scheme, and only the iPhone that asked can redeem it, with its own session
 *    (`POST /v1/web/oauth/complete`). A ticket sent to someone else ends in their browser, where it
 *    can't be confirmed for the sender's account.
 *  - A browser links or unlinks only within LINK_REAUTH_MS of signing in, so a stolen or forgotten
 *    browser session can't add a way back in that outlives signing it out.
 * A Google or Apple account linked to nobody can make a new Doddy account on the web (owner, 3 Nov
 * 2026: "it must be able to create account in web as well"), but only after the person says so on
 * the sign-in page ("Create my Doddy account", `POST /v1/web/signup`); nothing is made by the
 * redirect alone, and with DODDY_WEB_SIGNUP=off it opens nothing. Accounts are never merged behind
 * the person's back (ADR-600): an account made on the web is its own account.
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
/** The iPhone's confirmation code, from the end of its sheet, must be redeemed this soon. */
export const PENDING_LINK_TTL_MS = 5 * 60_000;
/** "Create my Doddy account" must be pressed this soon after Google or Apple sent the person back. */
export const PENDING_SIGNUP_TTL_MS = 10 * 60_000;
/** New accounts per client address per hour, and for the whole server per day. */
export const SIGNUP_LIMITS = { perClientPerHour: 5, servicePerDay: 500 } as const;
/** A browser may link or unlink Apple or Google only this soon after it signed in. */
export const LINK_REAUTH_MS = 15 * 60_000;
/** Starts and callbacks (counted apart) per client per quarter hour, and tickets per user per hour. */
export const SOCIAL_LIMITS = { startsPerClientPerQuarter: 30, callbacksPerClientPerQuarter: 60, ticketsPerUserPerHour: 20 } as const;

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
  /** Whether a Google or Apple account with no Doddy account can make one here. */
  signup: boolean;
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
export type SocialResult = "linked" | "already" | "taken" | "not_linked" | "new_account" | "canceled" | "failed" | "busy" | "signed_out" | "reauth" | "confirm";

export class SocialSignIn {
  readonly providers: readonly SocialProvider[];
  private readonly projectUrl: string;
  private readonly publishableKey: string;
  private readonly verifier: SupabaseSessionVerifier;
  private readonly postJson: PostJson;
  private readonly stateCookie: string;
  private readonly signupCookie: string;
  private readonly signupOpen: boolean;
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
    this.signupCookie = this.secure ? "__Host-doddy_signup" : "doddy_signup";
    this.signupOpen = settings.signup;
    this.callbackUrl = `${web.origin}/v1/web/oauth/callback`;
    this.appReturn = `${o.appScheme}://web-sign-in/return`;
  }

  options(): SignInOptions {
    return { providers: [...this.providers], signup: this.signupOpen };
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
    if (!(await this.withinLimit(req, now, "start"))) return back("busy");
    const provider = this.provider(query.get("provider"));
    if (!provider) return back("failed");
    let session: WebSessionContext | null = null;
    if (intent === "link") {
      session = await this.web.fromCookie(req, now);
      if (!session) return back("signed_out");
      if (!isRecent(session, now)) return back("reauth");
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
    if (!(await this.withinLimit(req, now, "start"))) return back("busy");
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
    if (!(await this.withinLimit(req, now, "callback"))) return withCookie(this.done({ intent: "signin", returnTo: "web", result: "busy" }), clear);
    const row = await this.store.consumeWebOAuthState(stateHash(token), now.getTime());
    if (!row) return withCookie(this.done({ intent: "signin", returnTo: "web", result: "failed" }), clear);
    const intent: SocialIntent = row.intent === "link" ? "link" : "signin";
    const returnTo: SocialReturn = row.return_to === "app" ? "app" : "web";
    const provider = this.provider(row.provider);
    const back = (result: SocialResult, confirmCode?: string) =>
      withCookie(this.done({ intent, returnTo, result, ...(provider ? { provider } : {}), ...(confirmCode ? { confirmCode } : {}) }), clear);

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
      if (returnTo === "app") {
        // Nothing is linked yet: the iPhone that asked confirms with its own session.
        const confirmCode = randomBytes(32).toString("base64url");
        await this.store.createPendingLink({ codeHash: stateHash(`confirm:${confirmCode}`), userId: row.user_id, identityId, provider, now: now.getTime(), ttlMs: PENDING_LINK_TTL_MS });
        this.log({ event: "web_identity_link", provider, result: "confirm" });
        return back("confirm", confirmCode);
      }
      const linked = await this.store.linkWebIdentity(identityId, row.user_id, provider, now.getTime());
      this.log({ event: "web_identity_link", provider, result: linked });
      return back(linked);
    }
    const userId = await this.store.webIdentityOwner(identityId);
    if (!userId) {
      if (!this.signupOpen) {
        this.log({ event: "web_social_signin", provider, result: "not_linked" });
        return back("not_linked");
      }
      // No account yet: nothing is made until the person presses "Create my Doddy account". This
      // browser holds the one-time code for that (Strict: only Doddy's own page can use it).
      const signupCode = randomBytes(32).toString("base64url");
      await this.store.createPendingSignup({ codeHash: stateHash(`signup:${signupCode}`), identityId, provider, now: now.getTime(), ttlMs: PENDING_SIGNUP_TTL_MS });
      this.log({ event: "web_social_signin", provider, result: "new_account" });
      return { location: `/sign-in?signin=new_account&provider=${provider}`, setCookies: [clear, this.signupCookieValue(signupCode, PENDING_SIGNUP_TTL_MS / 1000)] };
    }
    const opened = await this.web.openFor(userId, req, now);
    this.log({ event: "web_social_signin", provider, result: "signed_in" });
    return { location: "/", setCookies: [clear, opened.setCookie] };
  }

  /**
   * `POST /v1/web/signup`: the person pressed "Create my Doddy account" after Google or Apple. A new
   * account, with that sign-in linked, and this browser signed in to it. If the same Google account
   * got an account a moment ago (a second tab), this signs in to that one instead of making two.
   */
  async signup(req: IncomingMessage, now: Date): Promise<{ view: WebSessionView; setCookies: string[]; created: boolean; provider: SocialProvider }> {
    const clear = this.signupCookieValue("", 0);
    const code = readCookie(header(req, "cookie"), this.signupCookie);
    if (!this.signupOpen || !code || !STATE.test(code)) {
      throw new AppError("not_found", { message: "That sign-in has expired. Choose Continue with Google or Apple again." });
    }
    const hour = `day:${now.toISOString().slice(0, 13)}`;
    const day = `day:${now.toISOString().slice(0, 10)}`;
    const client = `web_signup:${sha256(`client:${clientKey(clientAddress(req, this.o.trustProxy))}`)}`;
    const allowed = await this.store.reserveUsage(
      [
        { counter: client, period: hour, limit: SIGNUP_LIMITS.perClientPerHour },
        { counter: "web_signup:service", period: day, limit: SIGNUP_LIMITS.servicePerDay },
      ],
      1,
    );
    if (!allowed) throw new AppError("rate_limited", { message: "Too many new accounts right now. Try again later.", retryAfterSeconds: 3600 });
    const pending = await this.store.consumePendingSignup(stateHash(`signup:${code}`), now.getTime());
    const provider = pending ? this.provider(pending.provider) : null;
    if (!pending || !provider) throw new AppError("not_found", { message: "That sign-in has expired. Choose Continue with Google or Apple again." });
    const account = await this.store.createWebAccount({ userId: randomUUID(), identityId: pending.identity_id, provider, now: now.getTime() });
    if (!account) throw new AppError("not_found");
    const opened = await this.web.openFor(account.userId, req, now);
    this.log({ event: "web_signup", provider, result: account.created ? "created" : "existing" });
    return { view: opened.view, setCookies: [clear, opened.setCookie], created: account.created, provider };
  }

  /**
   * `POST /v1/web/oauth/complete` (the iPhone's session): links what its sheet signed in with. Only
   * the account that asked for the ticket can, and only once, within PENDING_LINK_TTL_MS.
   */
  async complete(userId: string, body: unknown, now: Date): Promise<{ result: "linked" | "already" | "taken"; provider: SocialProvider }> {
    const code = typeof body === "object" && body !== null ? (body as Record<string, unknown>).code : undefined;
    if (typeof code !== "string" || !STATE.test(code) || Object.keys(body as object).length !== 1) throw new AppError("invalid_request");
    const pending = await this.store.consumePendingLink(stateHash(`confirm:${code}`), userId, now.getTime());
    const provider = pending ? this.provider(pending.provider) : null;
    if (!pending || !provider) throw new AppError("not_found", { message: "That sign-in has expired or was already used. Link it again." });
    const result = await this.store.linkWebIdentity(pending.identity_id, userId, provider, now.getTime());
    this.log({ event: "web_identity_link", provider, result });
    return { result, provider };
  }

  // ---------------------------------------------------------------- linked sign-ins

  /** A browser changes its linked sign-ins only soon after signing in; the iPhone always can. */
  assertMayChange(session: WebSessionContext | null, now: Date): void {
    if (session && !isRecent(session, now)) {
      throw new AppError("refused", { message: "For safety, sign in again with a code from your iPhone, then change this within 15 minutes." });
    }
  }

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

  private done(o: { intent: SocialIntent; returnTo: SocialReturn; result: SocialResult; provider?: SocialProvider; confirmCode?: string }): SocialOutcome {
    const params = new URLSearchParams({ result: o.result, ...(o.provider ? { provider: o.provider } : {}), ...(o.confirmCode ? { code: o.confirmCode } : {}) });
    if (o.returnTo === "app") return { location: `${this.appReturn}?${params}`, setCookies: [] };
    if (o.intent === "link") return { location: `/settings?link=${o.result}${o.provider ? `&provider=${o.provider}` : ""}`, setCookies: [] };
    return { location: `/sign-in?signin=${o.result}${o.provider ? `&provider=${o.provider}` : ""}`, setCookies: [] };
  }

  private provider(value: unknown): SocialProvider | null {
    return typeof value === "string" && (this.providers as readonly string[]).includes(value) ? (value as SocialProvider) : null;
  }

  /** Starts and callbacks are counted apart: a burst of starts can't make others' callbacks fail. */
  private async withinLimit(req: IncomingMessage, now: Date, step: "start" | "callback"): Promise<boolean> {
    const quarter = `day:${now.toISOString().slice(0, 14)}${String(Math.floor(now.getUTCMinutes() / 15) * 15).padStart(2, "0")}`;
    const client = `web_oauth_${step}:${sha256(`client:${clientKey(clientAddress(req, this.o.trustProxy))}`)}`;
    const limit = step === "start" ? SOCIAL_LIMITS.startsPerClientPerQuarter : SOCIAL_LIMITS.callbacksPerClientPerQuarter;
    return this.store.reserveUsage([{ counter: client, period: quarter, limit }], 1);
  }

  private signupCookieValue(value: string, maxAgeSeconds: number): string {
    return `${this.signupCookie}=${value}; Path=/; Max-Age=${maxAgeSeconds}; HttpOnly; SameSite=Strict${this.secure ? "; Secure" : ""}`;
  }

  private stateCookieValue(value: string, maxAgeSeconds: number): string {
    return `${this.stateCookie}=${value}; Path=/; Max-Age=${maxAgeSeconds}; HttpOnly; SameSite=Lax${this.secure ? "; Secure" : ""}`;
  }

  private log(line: Record<string, unknown>): void {
    this.o.log?.({ level: "info", ...line });
  }
}

function isRecent(session: WebSessionContext, now: Date): boolean {
  return now.getTime() - session.createdAt <= LINK_REAUTH_MS;
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

/** Sends DELETE and reads only the status; injectable for tests. */
export type DeleteCall = (url: string, init: { headers: Record<string, string>; signal: AbortSignal }) => Promise<{ status: number }>;

const defaultDelete: DeleteCall = async (url, init) => {
  const response = await fetch(url, { method: "DELETE", headers: init.headers, signal: init.signal, redirect: "error" });
  await response.body?.cancel();
  return { status: response.status };
};

/**
 * Deletes a person's Supabase Auth user (their Google or Apple sign-in, with name and email) when
 * their Doddy account is deleted (ADR-700), through Supabase's admin API with the project's secret
 * key, on the server only. A user already gone counts as removed; anything else stays owed.
 */
export class SupabaseUserRemover {
  readonly providers = [SUPABASE_AUTH] as const;
  private readonly call: DeleteCall;

  constructor(
    private readonly projectUrl: string,
    private readonly secretKey: string,
    call?: DeleteCall,
  ) {
    this.call = call ?? defaultDelete;
  }

  async remove(identityId: string, signal: AbortSignal): Promise<"removed" | "failed"> {
    if (!UUID.test(identityId)) return "failed";
    try {
      const { status } = await this.call(`${this.projectUrl}/auth/v1/admin/users/${identityId}`, {
        headers: { apikey: this.secretKey, authorization: `Bearer ${this.secretKey}` },
        signal,
      });
      return status === 200 || status === 204 || status === 404 ? "removed" : "failed";
    } catch {
      return "failed";
    }
  }
}
