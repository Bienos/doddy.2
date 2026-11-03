import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, type KeyObject, sign } from "node:crypto";
import { afterEach, test } from "node:test";
import type { FetchJson } from "../src/auth.js";
import { appScheme } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { ERASED_TABLES } from "../src/store.js";
import {
  type DeleteCall,
  LINK_REAUTH_MS,
  OAUTH_STATE_TTL_MS,
  OAUTH_TICKET_TTL_MS,
  PENDING_LINK_TTL_MS,
  PENDING_SIGNUP_TTL_MS,
  type PostJson,
  SIGNUP_LIMITS,
  SOCIAL_LIMITS,
} from "../src/web/social.js";
import { DEV_IDENTITIES } from "../src/auth.js";
import { USER_A, USER_B } from "./helpers.js";
import { CHROME_MAC, COOKIE, cookieValue, startWeb, WEB_ORIGIN, type WebRig } from "./webRig.js";

// ADR-700: Apple and Google sign-in on Doddy Web, linked to the iPhone's account, through Supabase Auth.

const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const STATE_COOKIE = "__Host-doddy_oauth";
const GOOGLE_PERSON = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const OTHER_PERSON = "7d1e9a0b-3c52-4d6e-8f70-123456789abc";

const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");

function accessToken(sub: string, provider: string, nowMs: number, key: KeyObject = ec.privateKey): string {
  const header = b64({ alg: "ES256", kid: "k1", typ: "JWT" });
  const now = Math.floor(nowMs / 1000);
  const body = b64({
    iss: ISSUER,
    aud: "authenticated",
    role: "authenticated",
    sub,
    iat: now - 5,
    exp: now + 3600,
    is_anonymous: false,
    app_metadata: { provider, providers: [provider] },
  });
  const signature = sign("sha256", Buffer.from(`${header}.${body}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${signature.toString("base64url")}`;
}

/**
 * A fake Supabase Auth: `/authorize` is the test itself (it reads the challenge from the redirect and
 * "signs the person in" by issuing a code for it), `/token?grant_type=pkce` checks the verifier
 * against that challenge and the publishable key, the way GoTrue does.
 */
function fakeSupabase(clock: () => number) {
  const codes = new Map<string, { challenge: string; sub: string; provider: string }>();
  const state = { exchanges: 0, requests: [] as { url: string; headers: Record<string, string>; body: Record<string, unknown> }[], down: false, wrongKey: false };
  const postJson: PostJson = async (url, init) => {
    state.exchanges += 1;
    const body = JSON.parse(init.body) as Record<string, unknown>;
    state.requests.push({ url, headers: init.headers, body });
    if (state.down) throw new Error("unreachable");
    if (url !== `${ISSUER}/token?grant_type=pkce` || init.headers.apikey !== "sb_publishable_test_key_123") return { status: 401, body: { error: "invalid apikey" } };
    const entry = codes.get(String(body.auth_code));
    if (!entry) return { status: 404, body: { error_code: "flow_state_not_found" } };
    codes.delete(String(body.auth_code));
    const challenge = createHash("sha256").update(String(body.code_verifier)).digest("base64url");
    if (challenge !== entry.challenge) return { status: 403, body: { error_code: "bad_code_verifier" } };
    return {
      status: 200,
      body: { access_token: state.wrongKey ? accessToken(entry.sub, entry.provider, clock(), generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey) : accessToken(entry.sub, entry.provider, clock()), refresh_token: "rt-never-kept", token_type: "bearer", user: { id: entry.sub } },
    };
  };
  const fetchJson: FetchJson = async () => ({ keys: [{ ...ec.publicKey.export({ format: "jwk" }), kid: "k1", alg: "ES256", use: "sig" }] });
  let n = 0;
  return {
    state,
    postJson,
    fetchJson,
    /** What Supabase does after the person signs in: a code bound to the challenge of `authorizeUrl`. */
    issueCode(authorizeUrl: string, sub: string, provider = "google"): string {
      const url = new URL(authorizeUrl);
      assert.equal(url.origin + url.pathname, `${ISSUER}/authorize`);
      assert.equal(url.searchParams.get("code_challenge_method"), "s256");
      assert.equal(url.searchParams.get("redirect_to"), `${WEB_ORIGIN}/v1/web/oauth/callback`);
      const code = `code-${(n += 1)}-${sub.slice(0, 8)}`;
      codes.set(code, { challenge: url.searchParams.get("code_challenge")!, sub, provider });
      return code;
    },
  };
}

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

async function socialRig(o: { providers?: ("google" | "apple")[]; signup?: boolean; deleteUser?: DeleteCall } = {}) {
  let r!: WebRig;
  const supabase = fakeSupabase(() => r.clock.ms);
  r = await startWeb({
    social: {
      projectUrl: PROJECT,
      postJson: supabase.postJson,
      fetchJson: supabase.fetchJson,
      ...(o.providers ? { providers: o.providers } : {}),
      ...(o.signup !== undefined ? { signup: o.signup } : {}),
      ...(o.deleteUser ? { deleteUser: o.deleteUser } : {}),
    },
  });
  rig = r;
  return { rig: r, supabase };
}

/** Starts a sign-in in "the browser" and returns where it was sent and its state cookie. */
async function start(r: WebRig, query: string, cookie?: string) {
  const res = await r.call("GET", `/v1/web/oauth/start?${query}`, cookie ? { cookie } : {});
  assert.equal(res.status, 303, res.text);
  const location = res.headers.get("location")!;
  const state = cookieValue(res.headers.get("set-cookie"), STATE_COOKIE);
  return { location, state, setCookie: res.headers.get("set-cookie") };
}

/** Supabase sends the browser back with a code; the browser carries its state cookie. */
async function callback(r: WebRig, query: string, state: string | null, userAgent = CHROME_MAC) {
  const headers: Record<string, string> = { "user-agent": userAgent };
  if (state) headers.cookie = `${STATE_COOKIE}=${state}`;
  const res = await r.call("GET", `/v1/web/oauth/callback?${query}`, { headers });
  assert.equal(res.status, 303, res.text);
  return { location: res.headers.get("location")!, setCookie: res.headers.get("set-cookie") ?? "", headers: res.headers };
}

/** The whole browser sign-in with Google as `sub`. */
async function googleSignIn(r: WebRig, supabase: ReturnType<typeof fakeSupabase>, sub: string) {
  const s = await start(r, "provider=google");
  const code = supabase.issueCode(s.location, sub);
  return callback(r, `code=${code}`, s.state);
}

/** Links Google as `sub` from a browser signed in with the iPhone's code for `token`. */
async function linkFromBrowser(r: WebRig, supabase: ReturnType<typeof fakeSupabase>, sub: string, token = USER_A) {
  const session = await r.signIn(await r.code(token));
  const s = await start(r, "provider=google&intent=link", session);
  const code = supabase.issueCode(s.location, sub);
  return callback(r, `code=${code}`, s.state);
}

// ------------------------------------------------------------------ what the sign-in page is offered

test("without Supabase settings the sign-in page offers the code only, and the sign-in routes don't exist", async () => {
  rig = await startWeb();
  const options = await rig.call("GET", "/v1/web/sign-in-options");
  assert.equal(options.status, 200);
  assert.deepEqual(options.body, { providers: [] });
  assert.equal((await rig.call("GET", "/v1/web/oauth/start?provider=google")).status, 404);
  assert.equal((await rig.call("GET", "/v1/web/oauth/callback?code=x")).status, 404);
  assert.equal((await rig.call("GET", "/v1/web/identities", { token: USER_A })).status, 404);
  assert.equal((await rig.call("POST", "/v1/web/oauth/tickets", { token: USER_A, body: { provider: "google" } })).status, 404);
});

test("with them it offers the configured buttons in order, and says whether new accounts can be made", async () => {
  const { rig: r } = await socialRig({ providers: ["apple", "google"] });
  assert.deepEqual((await r.call("GET", "/v1/web/sign-in-options")).body, { providers: ["apple", "google"], signup: false });
  await r.close();
  const { rig: open } = await socialRig({ signup: true });
  assert.deepEqual((await open.call("GET", "/v1/web/sign-in-options")).body, { providers: ["google", "apple"], signup: true });
});

// ------------------------------------------------------------------ the start: PKCE and the state cookie

test("start sends the browser to Supabase with a S256 challenge and sets a short Lax state cookie", async () => {
  const { rig: r } = await socialRig();
  const s = await start(r, "provider=google");
  const url = new URL(s.location);
  assert.equal(url.origin, PROJECT);
  assert.equal(url.pathname, "/auth/v1/authorize");
  assert.equal(url.searchParams.get("provider"), "google");
  assert.match(url.searchParams.get("code_challenge")!, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(url.searchParams.get("code_challenge_method"), "s256");
  assert.match(s.setCookie!, new RegExp(`^${STATE_COOKIE}=[A-Za-z0-9_-]{43}; Path=/; Max-Age=${OAUTH_STATE_TTL_MS / 1000}; HttpOnly; SameSite=Lax; Secure$`));
  // The verifier stays on the server: neither the address nor the cookie carries it.
  const again = await start(r, "provider=google");
  assert.notEqual(new URL(again.location).searchParams.get("code_challenge"), url.searchParams.get("code_challenge"));
});

test("an unknown or switched-off provider goes back to the sign-in page, without a state", async () => {
  const { rig: r } = await socialRig({ providers: ["google"] });
  for (const query of ["provider=apple", "provider=facebook", "provider=", ""]) {
    const s = await start(r, query);
    assert.equal(s.location, "/sign-in?signin=failed", query);
    assert.equal(s.state, null);
  }
});

// ------------------------------------------------------------------ signing in

test("a Google account linked to nobody opens nothing and creates no account", async () => {
  const { rig: r, supabase } = await socialRig();
  const done = await googleSignIn(r, supabase, GOOGLE_PERSON);
  assert.equal(done.location, "/sign-in?signin=not_linked&provider=google");
  assert.equal(cookieValue(done.setCookie, COOKIE), null, "no session cookie");
  assert.match(done.setCookie, new RegExp(`${STATE_COOKIE}=; Path=/; Max-Age=0`), "the state cookie is removed");
  assert.equal(done.headers.get("referrer-policy"), "no-referrer");
  assert.equal(done.headers.get("cache-control"), "no-store");
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);
  // The exchange carried the publishable key and the verifier that matched the challenge.
  assert.equal(supabase.state.requests[0]!.headers.apikey, "sb_publishable_test_key_123");
  assert.ok(!r.logs.some((line) => line.includes("rt-never-kept") || line.includes("code-1")), "no token or code in the logs");
});

test("linked from a browser signed in with the iPhone's code, Google then signs in to the same account", async () => {
  const { rig: r, supabase } = await socialRig();
  const linked = await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  assert.equal(linked.location, "/settings?link=linked&provider=google");
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), DEV_IDENTITIES[USER_A]);

  const done = await googleSignIn(r, supabase, GOOGLE_PERSON);
  assert.equal(done.location, "/");
  const session = cookieValue(done.setCookie, COOKIE);
  assert.ok(session, done.setCookie);
  assert.match(done.setCookie, /__Host-doddy_web=[A-Za-z0-9_-]{43}; Path=\/; Max-Age=2592000; HttpOnly; SameSite=Strict; Secure/);
  const current = await r.call("GET", "/v1/web/session", { cookie: session });
  assert.equal(current.status, 200, current.text);
  assert.equal(current.body.session.browser, "chrome");
  // The phone sees the new browser among its own.
  const listed = await r.call("GET", "/v1/web/sessions", { token: USER_A });
  assert.equal(listed.body.sessions.length, 2);
  // And the linked sign-in, from either side.
  const identities = await r.call("GET", "/v1/web/identities", { token: USER_A });
  assert.deepEqual(identities.body.identities.map((i: { id: string; provider: string }) => [i.id, i.provider]), [[GOOGLE_PERSON, "google"]]);
  assert.deepEqual((await r.call("GET", "/v1/web/identities", { cookie: session })).body, identities.body);
  // Another account sees none of it.
  assert.deepEqual((await r.call("GET", "/v1/web/identities", { token: USER_B })).body, { identities: [] });
});

test("linking needs the browser's own session: without one it goes back signed out", async () => {
  const { rig: r } = await socialRig();
  const s = await start(r, "provider=google&intent=link");
  assert.equal(s.location, "/settings?link=signed_out");
  assert.equal(s.state, null);
  const stale = await start(r, "provider=google&intent=link", "A".repeat(43));
  assert.equal(stale.location, "/settings?link=signed_out");
});

test("a Google account linked to one Doddy account can't be linked to another, and nothing is merged", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON, USER_A);
  const again = await linkFromBrowser(r, supabase, GOOGLE_PERSON, USER_A);
  assert.equal(again.location, "/settings?link=already&provider=google");
  const taken = await linkFromBrowser(r, supabase, GOOGLE_PERSON, USER_B);
  assert.equal(taken.location, "/settings?link=taken&provider=google");
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), DEV_IDENTITIES[USER_A]);
  assert.deepEqual((await r.call("GET", "/v1/web/identities", { token: USER_B })).body, { identities: [] });
});

// ------------------------------------------------------------------ what the callback refuses

test("a state works once, only with its own cookie, and only for ten minutes", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);

  // Used twice: the second time nothing is exchanged.
  const s = await start(r, "provider=google");
  const code = supabase.issueCode(s.location, GOOGLE_PERSON);
  assert.equal((await callback(r, `code=${code}`, s.state)).location, "/");
  const exchanges = supabase.state.exchanges;
  assert.equal((await callback(r, `code=${code}`, s.state)).location, "/sign-in?signin=failed");
  assert.equal(supabase.state.exchanges, exchanges);

  // No cookie, or a made-up one.
  const s2 = await start(r, "provider=google");
  const code2 = supabase.issueCode(s2.location, GOOGLE_PERSON);
  assert.equal((await callback(r, `code=${code2}`, null)).location, "/sign-in?signin=failed");
  assert.equal((await callback(r, `code=${code2}`, "B".repeat(43))).location, "/sign-in?signin=failed");

  // Expired.
  const s3 = await start(r, "provider=google");
  const code3 = supabase.issueCode(s3.location, GOOGLE_PERSON);
  r.clock.advance(OAUTH_STATE_TTL_MS + 1);
  assert.equal((await callback(r, `code=${code3}`, s3.state)).location, "/sign-in?signin=failed");
});

test("someone else's code is useless: the verifier of this browser's sign-in doesn't match its challenge", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  // The attacker starts a sign-in of their own and gets a code for it...
  const attacker = await start(r, "provider=google");
  const stolen = supabase.issueCode(attacker.location, GOOGLE_PERSON);
  // ...and sends the victim's browser (with its own state) to the callback with it.
  const victim = await start(r, "provider=google");
  const done = await callback(r, `code=${stolen}`, victim.state);
  assert.equal(done.location, "/sign-in?signin=failed&provider=google");
  assert.equal(cookieValue(done.setCookie, COOKIE), null);
});

test("cancelling, a provider error, Supabase down or a token it didn't sign: no session, plain words", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  const cancel = await start(r, "provider=google");
  assert.equal((await callback(r, "error=access_denied&error_description=The+user+said+%3Cscript%3E", cancel.state)).location, "/sign-in?signin=canceled&provider=google");
  const refused = await start(r, "provider=google");
  assert.equal((await callback(r, "error=server_error", refused.state)).location, "/sign-in?signin=failed&provider=google");
  const malformed = await start(r, "provider=google");
  assert.equal((await callback(r, "code=%22%3E%3Cscript%3E", malformed.state)).location, "/sign-in?signin=failed&provider=google");

  supabase.state.down = true;
  const down = await start(r, "provider=google");
  assert.equal((await callback(r, `code=${supabase.issueCode(down.location, GOOGLE_PERSON)}`, down.state)).location, "/sign-in?signin=failed&provider=google");
  supabase.state.down = false;

  supabase.state.wrongKey = true;
  const forged = await start(r, "provider=google");
  const done = await callback(r, `code=${supabase.issueCode(forged.location, GOOGLE_PERSON)}`, forged.state);
  assert.equal(done.location, "/sign-in?signin=failed&provider=google");
  assert.equal(cookieValue(done.setCookie, COOKIE), null);
  assert.ok(!r.logs.some((line) => line.includes("<script>")), "the provider's words aren't logged");
});

test("an email or phone sign-in at Supabase opens nothing, even for a linked person", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  const s = await start(r, "provider=google");
  const code = supabase.issueCode(s.location, GOOGLE_PERSON, "email");
  const done = await callback(r, `code=${code}`, s.state);
  assert.equal(done.location, "/sign-in?signin=failed&provider=google");
});

test("one client gets a limited number of starts a quarter hour, and callbacks are counted apart", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  const waiting = await start(r, "provider=google");
  // Linking took one start and `waiting` another.
  for (let i = 2; i < SOCIAL_LIMITS.startsPerClientPerQuarter; i++) assert.equal(new URL((await start(r, "provider=google")).location).origin, PROJECT);
  assert.equal((await start(r, "provider=google")).location, "/sign-in?signin=busy");
  // A sign-in already under way still finishes: a burst of starts can't block callbacks.
  assert.equal((await callback(r, `code=${supabase.issueCode(waiting.location, GOOGLE_PERSON)}`, waiting.state)).location, "/");
  r.clock.advance(15 * 60_000);
  assert.equal(new URL((await start(r, "provider=google")).location).origin, PROJECT);
});

// ------------------------------------------------------------------ from the iPhone

/** The iPhone's sheet: ticket, start, Google, callback. Returns the confirmation code it ended with. */
async function sheet(r: WebRig, supabase: ReturnType<typeof fakeSupabase>, token: string, sub: string) {
  const ticket = await r.call("POST", "/v1/web/oauth/tickets", { token, body: { provider: "google" } });
  assert.equal(ticket.status, 200, ticket.text);
  const s = await start(r, new URL(ticket.body.url).search.slice(1));
  const done = await callback(r, `code=${supabase.issueCode(s.location, sub)}`, s.state);
  const end = new URL(done.location);
  return { ticket, end, code: end.searchParams.get("code") };
}

test("the iPhone links Google with a one-time ticket, then confirms it with its own session", async () => {
  const { rig: r, supabase } = await socialRig();
  const ticket = await r.call("POST", "/v1/web/oauth/tickets", { token: USER_A, body: { provider: "google" } });
  assert.equal(ticket.status, 200, ticket.text);
  assert.equal(ticket.body.callbackScheme, "doddy-dev");
  assert.equal(Date.parse(ticket.body.expiresAt) - r.clock.ms, OAUTH_TICKET_TTL_MS);
  const url = new URL(ticket.body.url);
  assert.equal(url.origin + url.pathname, `${WEB_ORIGIN}/v1/web/oauth/start`);

  const s = await start(r, url.search.slice(1));
  assert.equal(new URL(s.location).origin, PROJECT);
  const done = await callback(r, `code=${supabase.issueCode(s.location, GOOGLE_PERSON)}`, s.state);
  const end = new URL(done.location);
  assert.equal(`${end.protocol}//${end.host}${end.pathname}`, "doddy-dev://web-sign-in/return");
  assert.equal(end.searchParams.get("result"), "confirm");
  assert.equal(end.searchParams.get("provider"), "google");
  const code = end.searchParams.get("code")!;
  assert.match(code, /^[A-Za-z0-9_-]{43}$/);
  // The sheet alone linked nothing.
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);

  const confirmed = await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code } });
  assert.equal(confirmed.status, 200, confirmed.text);
  assert.deepEqual(confirmed.body, { result: "linked", provider: "google" });
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), DEV_IDENTITIES[USER_A]);
  // Once.
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code } })).status, 404);

  // The ticket worked once.
  assert.equal((await start(r, url.search.slice(1))).location, "doddy-dev://web-sign-in/return?result=failed");
  // And now Google opens the web for this person without any code.
  assert.equal((await googleSignIn(r, supabase, GOOGLE_PERSON)).location, "/");
});

test("a ticket sent to someone else can't link their Google to the sender's account", async () => {
  const { rig: r, supabase } = await socialRig();
  // B (the sender) asks for a ticket and gets someone (A) to open it and sign in with A's Google.
  const { code } = await sheet(r, supabase, USER_B, GOOGLE_PERSON);
  // The confirmation code ended in A's browser. B, without it, can't confirm anything...
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { token: USER_B, body: { code: "C".repeat(43) } })).status, 404);
  // ...and A's own iPhone can't confirm it either: it was asked for by another account.
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code } })).status, 404);
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null, "nothing was linked to anyone");
  // A's Google is still free for A to link to A's own account.
  const own = await sheet(r, supabase, USER_A, GOOGLE_PERSON);
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code: own.code } })).body.result, "linked");
});

test("a confirmation needs the iPhone's session, a well-formed code, and comes in time", async () => {
  const { rig: r, supabase } = await socialRig();
  const { code } = await sheet(r, supabase, USER_A, GOOGLE_PERSON);
  const session = await r.signIn(await r.code());
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { cookie: session, browser: true, body: { code } })).status, 401);
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code: "short" } })).status, 400);
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code, userId: "x" } })).status, 400);
  r.clock.advance(PENDING_LINK_TTL_MS + 1);
  assert.equal((await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code } })).status, 404);
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);
});

test("an iPhone confirming a Google account already linked elsewhere is told so, and nothing merges", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON, USER_B);
  const { code } = await sheet(r, supabase, USER_A, GOOGLE_PERSON);
  assert.deepEqual((await r.call("POST", "/v1/web/oauth/complete", { token: USER_A, body: { code } })).body, { result: "taken", provider: "google" });
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), DEV_IDENTITIES[USER_B]);
});

test("a browser links or unlinks only soon after signing in; the iPhone always can", async () => {
  const { rig: r, supabase } = await socialRig();
  const session = await r.signIn(await r.code());
  r.clock.advance(LINK_REAUTH_MS + 1);
  const s = await start(r, "provider=google&intent=link", session);
  assert.equal(s.location, "/settings?link=reauth");
  assert.equal(s.state, null);

  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  r.clock.advance(LINK_REAUTH_MS + 1);
  const refused = await r.call("DELETE", `/v1/web/identities/${GOOGLE_PERSON}`, { cookie: session, browser: true });
  assert.equal(refused.status, 422, refused.text);
  assert.equal(refused.body.error.code, "refused");
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), DEV_IDENTITIES[USER_A]);
  assert.equal((await r.call("DELETE", `/v1/web/identities/${GOOGLE_PERSON}`, { token: USER_A })).status, 200);
});

test("a ticket comes only from the iPhone's own session, for a configured provider, and expires", async () => {
  const { rig: r } = await socialRig({ providers: ["google"] });
  assert.equal((await r.call("POST", "/v1/web/oauth/tickets", { body: { provider: "google" } })).status, 401);
  const session = await r.signIn(await r.code());
  assert.equal((await r.call("POST", "/v1/web/oauth/tickets", { cookie: session, browser: true, body: { provider: "google" } })).status, 401);
  assert.equal((await r.call("POST", "/v1/web/oauth/tickets", { token: USER_A, body: { provider: "apple" } })).status, 400);
  assert.equal((await r.call("POST", "/v1/web/oauth/tickets", { token: USER_A, body: { provider: "google", userId: "someone" } })).status, 400);
  const ticket = await r.call("POST", "/v1/web/oauth/tickets", { token: USER_A, body: { provider: "google" } });
  r.clock.advance(OAUTH_TICKET_TTL_MS + 1);
  assert.equal((await start(r, new URL(ticket.body.url).search.slice(1))).location, "doddy-dev://web-sign-in/return?result=failed");
  assert.equal((await start(r, "ticket=not-a-ticket")).location, "doddy-dev://web-sign-in/return?result=failed");
});

test("cancelling the iPhone's sheet tells the app, and links nothing", async () => {
  const { rig: r } = await socialRig();
  const ticket = await r.call("POST", "/v1/web/oauth/tickets", { token: USER_A, body: { provider: "apple" } });
  const s = await start(r, new URL(ticket.body.url).search.slice(1));
  assert.equal(new URL(s.location).searchParams.get("provider"), "apple");
  const done = await callback(r, "error=access_denied", s.state);
  assert.equal(done.location, "doddy-dev://web-sign-in/return?result=canceled&provider=apple");
  assert.deepEqual((await r.call("GET", "/v1/web/identities", { token: USER_A })).body, { identities: [] });
});

// ------------------------------------------------------------------ unlinking and erasure

test("unlinking needs the web app's origin from a browser, and Google then opens nothing", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  const session = await r.signIn(await r.code());
  assert.equal((await r.call("DELETE", `/v1/web/identities/${GOOGLE_PERSON}`, { cookie: session })).status, 401, "no same-origin header");
  assert.equal((await r.call("DELETE", `/v1/web/identities/${GOOGLE_PERSON}`, { token: USER_B })).status, 404, "another account's");
  assert.equal((await r.call("DELETE", `/v1/web/identities/${OTHER_PERSON}`, { token: USER_A })).status, 404);
  const gone = await r.call("DELETE", `/v1/web/identities/${GOOGLE_PERSON}`, { cookie: session, browser: true });
  assert.equal(gone.status, 200, gone.text);
  assert.equal((await googleSignIn(r, supabase, GOOGLE_PERSON)).location, "/sign-in?signin=not_linked&provider=google");
});

test("deleting the account removes its linked sign-ins and sign-ins in progress", async () => {
  const { rig: r, supabase } = await socialRig();
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  await r.call("POST", "/v1/web/oauth/tickets", { token: USER_A, body: { provider: "google" } });
  await sheet(r, supabase, USER_A, OTHER_PERSON);
  for (const table of ["web_identities", "web_oauth_states", "web_link_pending"]) assert.ok((ERASED_TABLES as readonly string[]).includes(table), table);
  const erasure = await r.store.eraseUser(DEV_IDENTITIES[USER_A]!, r.clock.ms);
  assert.equal(erasure.deleted.web_identities, 1);
  assert.ok(erasure.deleted.web_oauth_states >= 1);
  assert.equal(erasure.deleted.web_link_pending, 1);
  assert.equal(erasure.remaining, 0);
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);
});

// ------------------------------------------------------------------ config

test("config: Apple and Google on the web need SUPABASE_URL and the publishable key, never the secret one", () => {
  const web = { DODDY_WEB_ORIGIN: "https://app.doddy.lol" };
  assert.equal(loadConfig(web).web!.social, null);
  assert.deepEqual(loadConfig({ ...web, SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co/", SUPABASE_PUBLISHABLE_KEY: "sb_publishable_qvClrOM9aE-OZvFGZ54x" }).web!.social, {
    projectUrl: "https://abcdefghijklmnopqrst.supabase.co",
    publishableKey: "sb_publishable_qvClrOM9aE-OZvFGZ54x",
    providers: ["google", "apple"],
    signup: true,
    secretKey: null,
  });
  assert.deepEqual(
    loadConfig({ ...web, SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: "sb_publishable_qvClrOM9aE-OZvFGZ54x", DODDY_WEB_SIGNIN_PROVIDERS: "Apple" }).web!.social!.providers,
    ["apple"],
  );
  // The iPhone's own sign-in is unchanged: the auth mode stays as it was.
  assert.equal(loadConfig({ ...web, SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: "sb_publishable_qvClrOM9aE-OZvFGZ54x" }).supabaseUrl, null);
  assert.throws(() => loadConfig({ ...web, SUPABASE_PUBLISHABLE_KEY: "sb_publishable_qvClrOM9aE-OZvFGZ54x" }), /SUPABASE_URL/);
  assert.throws(() => loadConfig({ ...web, SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: "sb_secret_abcdefghijklmnop" }), /secret key/);
  assert.throws(() => loadConfig({ ...web, SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: "sb_publishable_ok_1234567", DODDY_WEB_SIGNIN_PROVIDERS: "google,facebook" }), /facebook/);
});

test("the iPhone's sheet ends at a doddy scheme, never at https", () => {
  assert.equal(appScheme("doddy-dev://connected-apps/return"), "doddy-dev");
  assert.equal(appScheme("doddy://connected-apps/return"), "doddy");
  assert.equal(appScheme("https://doddy.lol/return"), "doddy");
});

// ------------------------------------------------------------------ a new account on the web (owner, 3 Nov 2026)

const SIGNUP_COOKIE = "__Host-doddy_signup";

/** Google, then "Create my Doddy account". Returns the sign-in's end and the reply to the button. */
async function signupWithGoogle(r: WebRig, supabase: ReturnType<typeof fakeSupabase>, sub: string, o: { press?: boolean } = {}) {
  const done = await googleSignIn(r, supabase, sub);
  const pending = cookieValue(done.setCookie, SIGNUP_COOKIE);
  if (o.press === false) return { done, pending, created: null };
  const created = await r.call("POST", "/v1/web/signup", { body: {}, browser: true, headers: pending ? { cookie: `${SIGNUP_COOKIE}=${pending}`, "user-agent": CHROME_MAC } : { "user-agent": CHROME_MAC } });
  return { done, pending, created };
}

test("a Google account with no Doddy account is asked first, and makes nothing until the person says so", async () => {
  const { rig: r, supabase } = await socialRig({ signup: true });
  const { done, pending } = await signupWithGoogle(r, supabase, GOOGLE_PERSON, { press: false });
  assert.equal(done.location, "/sign-in?signin=new_account&provider=google");
  assert.equal(cookieValue(done.setCookie, COOKIE), null, "no session yet");
  assert.ok(pending);
  assert.match(done.setCookie, new RegExp(`${SIGNUP_COOKIE}=[A-Za-z0-9_-]{43}; Path=/; Max-Age=${PENDING_SIGNUP_TTL_MS / 1000}; HttpOnly; SameSite=Strict; Secure`));
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null, "no account was made by the redirect");
});

test("Create my Doddy account makes a new account, links Google to it and signs this browser in", async () => {
  const { rig: r, supabase } = await socialRig({ signup: true });
  const { created } = await signupWithGoogle(r, supabase, GOOGLE_PERSON);
  assert.equal(created!.status, 200, created!.text);
  assert.equal(created!.body.created, true);
  assert.equal(created!.body.provider, "google");
  const session = cookieValue(created!.headers.get("set-cookie"), COOKIE)!;
  assert.ok(session);
  assert.match(created!.headers.get("set-cookie")!, new RegExp(`${SIGNUP_COOKIE}=; Path=/; Max-Age=0`), "the one-time cookie is removed");
  const owner = await r.store.webIdentityOwner(GOOGLE_PERSON);
  assert.match(owner!, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.notEqual(owner, DEV_IDENTITIES[USER_A]);
  assert.notEqual(owner, DEV_IDENTITIES[USER_B]);
  // A real, empty workspace of its own.
  assert.equal((await r.call("GET", "/v1/web/session", { cookie: session })).status, 200);
  assert.deepEqual((await r.call("GET", "/v1/web/documents", { cookie: session })).body.documents, []);
  assert.deepEqual((await r.call("GET", "/v1/web/identities", { cookie: session })).body.identities.map((i: { provider: string }) => i.provider), ["google"]);
  // Next time, Continue with Google signs straight in to it.
  const again = await googleSignIn(r, supabase, GOOGLE_PERSON);
  assert.equal(again.location, "/");
  assert.ok(r.logs.some((line) => line.includes('"event":"web_signup"') && line.includes('"result":"created"')));
  assert.ok(!r.logs.some((line) => line.includes(GOOGLE_PERSON) || line.includes(owner!)), "no ids in the logs");
});

test("the button works once, only with its own cookie, from the web app, and for ten minutes", async () => {
  const { rig: r, supabase } = await socialRig({ signup: true });
  const { pending } = await signupWithGoogle(r, supabase, GOOGLE_PERSON, { press: false });
  // Not from the web app (no Origin and header): refused before anything happens.
  assert.equal((await r.call("POST", "/v1/web/signup", { body: {}, headers: { cookie: `${SIGNUP_COOKIE}=${pending}` } })).status, 401);
  // Without the cookie, or with a made-up one.
  assert.equal((await r.call("POST", "/v1/web/signup", { body: {}, browser: true })).status, 404);
  assert.equal((await r.call("POST", "/v1/web/signup", { body: {}, browser: true, headers: { cookie: `${SIGNUP_COOKIE}=${"D".repeat(43)}` } })).status, 404);
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);
  // Expired.
  r.clock.advance(PENDING_SIGNUP_TTL_MS + 1);
  assert.equal((await r.call("POST", "/v1/web/signup", { body: {}, browser: true, headers: { cookie: `${SIGNUP_COOKIE}=${pending}` } })).status, 404);
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);
  // A fresh one works, once.
  const { pending: second } = await signupWithGoogle(r, supabase, GOOGLE_PERSON, { press: false });
  assert.equal((await r.call("POST", "/v1/web/signup", { body: {}, browser: true, headers: { cookie: `${SIGNUP_COOKIE}=${second}` } })).status, 200);
  assert.equal((await r.call("POST", "/v1/web/signup", { body: {}, browser: true, headers: { cookie: `${SIGNUP_COOKIE}=${second}` } })).status, 404);
});

test("two tabs for the same Google account make one account, not two", async () => {
  const { rig: r, supabase } = await socialRig({ signup: true });
  const first = await signupWithGoogle(r, supabase, GOOGLE_PERSON, { press: false });
  const second = await signupWithGoogle(r, supabase, GOOGLE_PERSON, { press: false });
  const a = await r.call("POST", "/v1/web/signup", { body: {}, browser: true, headers: { cookie: `${SIGNUP_COOKIE}=${first.pending}` } });
  const b = await r.call("POST", "/v1/web/signup", { body: {}, browser: true, headers: { cookie: `${SIGNUP_COOKIE}=${second.pending}` } });
  assert.equal(a.body.created, true);
  assert.equal(b.status, 200);
  assert.equal(b.body.created, false, "the second signs in to the account the first made");
  const owner = await r.store.webIdentityOwner(GOOGLE_PERSON);
  const listed = await r.call("GET", "/v1/web/sessions", { cookie: cookieValue(b.headers.get("set-cookie"), COOKIE)! });
  assert.equal(listed.body.sessions.length, 2, "both browsers are in the one account");
  assert.ok(owner);
});

test("a Google account already linked to an iPhone's account signs in to it, never a new one", async () => {
  const { rig: r, supabase } = await socialRig({ signup: true });
  await linkFromBrowser(r, supabase, GOOGLE_PERSON);
  const done = await googleSignIn(r, supabase, GOOGLE_PERSON);
  assert.equal(done.location, "/");
  assert.equal(cookieValue(done.setCookie, SIGNUP_COOKIE), null);
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), DEV_IDENTITIES[USER_A]);
});

test("with DODDY_WEB_SIGNUP=off an unlinked Google account opens nothing, as before", async () => {
  const { rig: r, supabase } = await socialRig({ signup: false });
  const done = await googleSignIn(r, supabase, GOOGLE_PERSON);
  assert.equal(done.location, "/sign-in?signin=not_linked&provider=google");
  assert.equal(cookieValue(done.setCookie, SIGNUP_COOKIE), null);
  assert.equal((await r.call("POST", "/v1/web/signup", { body: {}, browser: true })).status, 404);
});

test("new accounts are limited per address an hour", async () => {
  const { rig: r, supabase } = await socialRig({ signup: true });
  for (let i = 0; i < SIGNUP_LIMITS.perClientPerHour; i++) {
    const sub = `5b0c8f7e-2a41-4c3d-9e6f-${String(i).padStart(12, "0")}`;
    assert.equal((await signupWithGoogle(r, supabase, sub)).created!.status, 200);
  }
  const over = await signupWithGoogle(r, supabase, "5b0c8f7e-2a41-4c3d-9e6f-999999999999");
  assert.equal(over.created!.status, 429);
  assert.equal(await r.store.webIdentityOwner("5b0c8f7e-2a41-4c3d-9e6f-999999999999"), null);
});

// ------------------------------------------------------------------ deleting the account from the web

test("an account made on the web is deleted from the web: everything, its Google sign-in at Supabase too", async () => {
  const deleted: string[] = [];
  const deleteUser: DeleteCall = async (url, init) => {
    assert.equal(init.headers.apikey, "sb_secret_test_key_456");
    deleted.push(url);
    return { status: 200 };
  };
  const { rig: r, supabase } = await socialRig({ signup: true, deleteUser });
  const { created } = await signupWithGoogle(r, supabase, GOOGLE_PERSON);
  const session = cookieValue(created!.headers.get("set-cookie"), COOKIE)!;
  const owner = (await r.store.webIdentityOwner(GOOGLE_PERSON))!;

  assert.deepEqual((await r.call("GET", "/v1/web/account", { cookie: session })).body, { madeOnWeb: true });
  // The word is sent back, from the web app.
  assert.equal((await r.call("POST", "/v1/web/account/delete", { cookie: session, browser: true, body: {} })).status, 400);
  assert.equal((await r.call("POST", "/v1/web/account/delete", { cookie: session, body: { confirm: "delete" } })).status, 401);
  const gone = await r.call("POST", "/v1/web/account/delete", { cookie: session, browser: true, body: { confirm: "delete" } });
  assert.equal(gone.status, 200, gone.text);
  assert.equal(gone.body.complete, true);
  assert.equal(gone.body.remaining, 0);
  assert.deepEqual(gone.body.onlineAccounts, { removed: ["supabase_auth"], pending: [] });
  assert.deepEqual(deleted, [`${PROJECT}/auth/v1/admin/users/${GOOGLE_PERSON}`]);
  assert.match(gone.headers.get("set-cookie")!, /__Host-doddy_web=; Path=\/; Max-Age=0/);
  assert.equal((await r.call("GET", "/v1/web/session", { cookie: session })).status, 401, "signed out");
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);
  assert.equal((await r.store.webSessions(owner, r.clock.ms, 1e12, 50)).length, 0);
});

test("deleting from a browser needs a recent sign-in, and without the secret key says the sign-in is still owed", async () => {
  const { rig: r, supabase } = await socialRig({ signup: true });
  const { created } = await signupWithGoogle(r, supabase, GOOGLE_PERSON);
  const session = cookieValue(created!.headers.get("set-cookie"), COOKIE)!;
  r.clock.advance(LINK_REAUTH_MS + 1);
  const old = await r.call("POST", "/v1/web/account/delete", { cookie: session, browser: true, body: { confirm: "delete" } });
  assert.equal(old.status, 422);
  assert.ok(await r.store.webIdentityOwner(GOOGLE_PERSON), "nothing was deleted");
  // Sign in again (Google), then delete: done here, but Supabase's copy is honestly still owed.
  const fresh = cookieValue((await googleSignIn(r, supabase, GOOGLE_PERSON)).setCookie, COOKIE)!;
  const gone = await r.call("POST", "/v1/web/account/delete", { cookie: fresh, browser: true, body: { confirm: "delete" } });
  assert.equal(gone.status, 200, gone.text);
  assert.equal(gone.body.complete, false);
  assert.deepEqual(gone.body.onlineAccounts, { removed: [], pending: ["supabase_auth"] });
  assert.equal(await r.store.webIdentityOwner(GOOGLE_PERSON), null);
});

test("an iPhone's account can't be deleted from a browser: that stays on the iPhone (ADR-674)", async () => {
  const { rig: r } = await socialRig({ signup: true });
  const session = await r.signIn(await r.code());
  assert.deepEqual((await r.call("GET", "/v1/web/account", { cookie: session })).body, { madeOnWeb: false });
  const refused = await r.call("POST", "/v1/web/account/delete", { cookie: session, browser: true, body: { confirm: "delete" } });
  assert.equal(refused.status, 422, refused.text);
  assert.match(refused.body.error.message, /iPhone/);
  assert.equal((await r.call("GET", "/v1/web/session", { cookie: session })).status, 200, "nothing happened");
  // Only browsers: the phone deletes with DELETE /v1/account, as before.
  assert.equal((await r.call("GET", "/v1/web/account", { token: USER_A })).status, 401);
});

test("SupabaseUserRemover: removed, already gone, refused, unreachable", async () => {
  const { SupabaseUserRemover } = await import("../src/web/social.js");
  const answer = (status: number | Error): DeleteCall => async () => {
    if (status instanceof Error) throw status;
    return { status };
  };
  const signal = new AbortController().signal;
  assert.equal(await new SupabaseUserRemover(PROJECT, "sb_secret_x", answer(200)).remove(GOOGLE_PERSON, signal), "removed");
  assert.equal(await new SupabaseUserRemover(PROJECT, "sb_secret_x", answer(404)).remove(GOOGLE_PERSON, signal), "removed");
  assert.equal(await new SupabaseUserRemover(PROJECT, "sb_secret_x", answer(401)).remove(GOOGLE_PERSON, signal), "failed");
  assert.equal(await new SupabaseUserRemover(PROJECT, "sb_secret_x", answer(new Error("down"))).remove(GOOGLE_PERSON, signal), "failed");
  assert.equal(await new SupabaseUserRemover(PROJECT, "sb_secret_x", answer(200)).remove("../../etc", signal), "failed");
});

test("config: sign-up is open by default with Supabase set, can be switched off, and the secret key is checked", () => {
  const base = { DODDY_WEB_ORIGIN: "https://app.doddy.lol", SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: "sb_publishable_qvClrOM9aE-OZvFGZ54x" };
  assert.equal(loadConfig(base).web!.social!.signup, true);
  assert.equal(loadConfig({ ...base, DODDY_WEB_SIGNUP: "off" }).web!.social!.signup, false);
  assert.equal(loadConfig(base).web!.social!.secretKey, null);
  assert.equal(loadConfig({ ...base, SUPABASE_SECRET_KEY: "sb_secret_abcdefghijklmnop" }).web!.social!.secretKey, "sb_secret_abcdefghijklmnop");
  assert.throws(() => loadConfig({ ...base, SUPABASE_SECRET_KEY: "not-a-key" }), /SUPABASE_SECRET_KEY/);
  assert.throws(() => loadConfig({ ...base, DODDY_WEB_SIGNUP: "maybe" }), /DODDY_WEB_SIGNUP/);
});

test("a Supabase removal that failed at the deletion is retried by the hourly sweep", async () => {
  const { Store } = await import("../src/store.js");
  const { AccountEraser } = await import("../src/account.js");
  const { SupabaseUserRemover } = await import("../src/web/social.js");
  const store = await Store.memory();
  try {
    let up = false;
    const calls: string[] = [];
    const remover = new SupabaseUserRemover(PROJECT, "sb_secret_x", async (url) => {
      calls.push(url);
      return { status: up ? 200 : 503 };
    });
    let now = 1_000_000;
    const eraser = new AccountEraser({ store, removers: [remover], timeoutMs: 1_000, now: () => now });
    await store.createWebAccount({ userId: OTHER_PERSON, identityId: GOOGLE_PERSON, provider: "google", now });
    const first = await eraser.erase(OTHER_PERSON);
    assert.deepEqual(first.onlineAccounts, { removed: [], pending: ["supabase_auth"] });
    up = true;
    now += 6 * 60_000;
    await eraser.sweep(["supabase_auth"]);
    assert.equal(calls.length, 2);
    assert.deepEqual(await store.cleanupsToRetry(["supabase_auth"], now, 99, 10), [], "done, dequeued");
  } finally {
    await store.close();
  }
});

