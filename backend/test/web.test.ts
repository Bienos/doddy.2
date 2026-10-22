import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { loadConfig } from "../src/config.js";
import { describeAgent, newLinkCode, normalizeCode, REDEEM_LIMITS } from "../src/web/sessions.js";
import { CurrentSessionSchema, DocumentListSchema, LinkCodeSchema, SessionListSchema } from "../src/web/contracts.js";
import { MockClaudeProvider } from "../src/tools/claude.js";
import { USER_A, USER_B } from "./helpers.js";
import { CHROME_MAC, COOKIE, cookieValue, startWeb, WEB_ORIGIN, type WebRig } from "./webRig.js";

/**
 * Doddy Web (ADR-579): the iPhone vouches for a browser with a one-time code; the browser gets a
 * cookie session for the same user that can read the workspace and nothing more.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const MINUTE = 60_000;
const DAY = 86_400_000;

/** The phone's flow for make_document: the card, the yes, the run (ASK-01). */
async function makeDocument(r: WebRig, title: string, token = USER_A) {
  const args = { kind: "pdf", title, request: "A one-page summary" };
  const asked = await r.call("POST", "/v1/tools/prepare", { token, body: { tool: "make_document", arguments: args } });
  assert.equal(asked.status, 200, asked.text);
  const ran = await r.call("POST", "/v1/tools/run", { token, body: { tool: "make_document", arguments: args, timeZone: "Europe/Warsaw", approvalId: asked.body.approvalId } });
  assert.equal(ran.status, 200, ran.text);
  return ran.body;
}

// ------------------------------------------------------------------ codes

test("the iPhone gets a code: eight letters and digits, five minutes, the web address to type it at", async () => {
  rig = await startWeb();
  const res = await rig.call("POST", "/v1/web/link-codes", { token: USER_A, body: {} });
  assert.equal(res.status, 200, res.text);
  const code = LinkCodeSchema.parse(res.body);
  assert.match(code.code, /^[A-HJKMNP-TV-Z2-9]{4}-[A-HJKMNP-TV-Z2-9]{4}$/);
  assert.equal(code.expiresAt, "2026-10-22T10:05:00.000Z");
  assert.equal(code.webOrigin, WEB_ORIGIN);
});

test("only the iPhone's own session makes codes: no session, or a browser's cookie, is refused", async () => {
  rig = await startWeb();
  assert.equal((await rig.call("POST", "/v1/web/link-codes", { body: {} })).status, 401);
  assert.equal((await rig.call("POST", "/v1/web/link-codes", { token: "not-a-user", body: {} })).status, 401);
  const cookie = await rig.signIn(await rig.code());
  const fromBrowser = await rig.call("POST", "/v1/web/link-codes", { cookie, browser: true, body: {} });
  assert.equal(fromBrowser.status, 401, "a browser session can't make more sessions");
});

test("codes are uniform over 30 characters without look-alikes, and typing is forgiving", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 2000; i++) for (const ch of newLinkCode()) seen.add(ch);
  assert.equal(seen.size, 30);
  for (const ch of "ILOU01") assert.ok(!seen.has(ch), ch);
  // Rejection sampling: bytes 240..255 are skipped, not folded onto the first letters.
  let calls = 0;
  const code = newLinkCode(() => (calls++ === 0 ? Buffer.alloc(16, 255) : Buffer.from([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])));
  assert.equal(code, "ABCDEFGH");
  assert.equal(normalizeCode(" abcd-efgh "), "ABCDEFGH");
  assert.equal(normalizeCode("ABCD EFGH"), "ABCDEFGH");
  assert.equal(normalizeCode("ABCDEFG"), null);
  assert.equal(normalizeCode("ABCDEFGO"), null, "O isn't in the alphabet");
});

// ------------------------------------------------------------------ signing in

test("a browser signs in with the code and gets an HttpOnly, SameSite=Strict, __Host- cookie", async () => {
  rig = await startWeb();
  const code = await rig.code();
  const res = await rig.call("POST", "/v1/web/session", { browser: true, body: { code }, headers: { "user-agent": CHROME_MAC } });
  assert.equal(res.status, 200, res.text);
  const setCookie = res.headers.get("set-cookie")!;
  assert.match(setCookie, /^__Host-doddy_web=[A-Za-z0-9_-]{43}; Path=\/; Max-Age=2592000; HttpOnly; SameSite=Strict; Secure$/);
  const session = CurrentSessionSchema.parse(res.body).session;
  assert.deepEqual({ browser: session.browser, os: session.os, current: session.current }, { browser: "chrome", os: "macos", current: true });
  assert.equal(session.expiresAt, "2026-11-05T10:00:00.000Z", "idle limit (14 days) comes before the 30-day cap");

  const cookie = cookieValue(setCookie)!;
  const me = await rig.call("GET", "/v1/web/session", { cookie });
  assert.equal(me.status, 200, me.text);
  assert.equal(me.body.session.id, session.id);
  // The token is only in the cookie: never in a body, and never stored as it is.
  assert.ok(!res.text.includes(cookie));
  const stored = await rig.store.db.query<{ token_hash: string }>("SELECT token_hash FROM web_sessions");
  assert.notEqual(stored.rows[0]!.token_hash, cookie);
  assert.match(stored.rows[0]!.token_hash, /^[0-9a-f]{64}$/);
});

test("typed in lower case with a space, the code still works", async () => {
  rig = await startWeb();
  const code = await rig.code();
  const typed = code.toLowerCase().replace("-", " ");
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code: typed } })).status, 200);
});

test("a code works once, for five minutes, and only the newest one", async () => {
  rig = await startWeb();
  const first = await rig.code();
  await rig.signIn(first);
  const again = await rig.call("POST", "/v1/web/session", { browser: true, body: { code: first } });
  assert.equal(again.status, 401);
  assert.match(again.body.error.message, /five minutes and work once/);

  const expiring = await rig.code();
  rig.clock.advance(5 * MINUTE);
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code: expiring } })).status, 401, "expired at exactly five minutes");

  const older = await rig.code();
  const newer = await rig.code();
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code: older } })).status, 401, "a newer code replaces it");
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code: newer } })).status, 200);
});

test("signing in must come from the web app itself (no Origin, another origin, or no header: refused)", async () => {
  rig = await startWeb();
  const code = await rig.code();
  const bare = await rig.call("POST", "/v1/web/session", { body: { code } });
  assert.equal(bare.status, 401);
  const elsewhere = await rig.call("POST", "/v1/web/session", { body: { code }, headers: { origin: "https://evil.example", "x-doddy-web": "1" } });
  assert.equal(elsewhere.status, 401);
  const noHeader = await rig.call("POST", "/v1/web/session", { body: { code }, headers: { origin: WEB_ORIGIN } });
  assert.equal(noHeader.status, 401);
  assert.equal(noHeader.headers.get("set-cookie"), null);
  // None of those used the code up.
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code } })).status, 200);
});

test("wrong codes are limited per client and for the whole server, before the code is checked", async () => {
  rig = await startWeb({ trustProxy: true });
  const wrong = (ip: string) => rig!.call("POST", "/v1/web/session", { browser: true, body: { code: "AAAA-AAAA" }, headers: { "x-forwarded-for": `9.9.9.9, ${ip}` } });
  for (let i = 0; i < REDEEM_LIMITS.perClientPerQuarter; i++) assert.equal((await wrong("1.1.1.1")).status, 401);
  const code = await rig.code();
  const blocked = await rig.call("POST", "/v1/web/session", { browser: true, body: { code }, headers: { "x-forwarded-for": "1.1.1.1" } });
  assert.equal(blocked.status, 429);
  assert.ok(Number(blocked.headers.get("retry-after")) > 0);
  // Another client is still let in, and the right code wasn't used up by the blocked try.
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code }, headers: { "x-forwarded-for": "2.2.2.2" } })).status, 200);
  // After the quarter hour the first client may try again.
  rig.clock.advance(15 * MINUTE);
  assert.equal((await wrong("1.1.1.1")).status, 401);

  // Server-wide: enough wrong codes from many clients close sign-in for the hour, for everyone.
  rig.clock.advance(60 * MINUTE);
  for (let i = 0; i < REDEEM_LIMITS.servicePerHour; i++) assert.equal((await wrong(`10.0.${Math.floor(i / 200)}.${i % 200}`)).status, 401);
  const late = await rig.code();
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code: late }, headers: { "x-forwarded-for": "3.3.3.3" } })).status, 429);
});

test("the iPhone may ask for at most 20 codes an hour", async () => {
  rig = await startWeb();
  for (let i = 0; i < 20; i++) await rig.code();
  const res = await rig.call("POST", "/v1/web/link-codes", { token: USER_A, body: {} });
  assert.equal(res.status, 429);
  rig.clock.advance(60 * MINUTE);
  await rig.code();
});

test("strict input: unknown fields, a missing code or a non-JSON body are refused", async () => {
  rig = await startWeb();
  const code = await rig.code();
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: { code, userId: USER_B } })).status, 400);
  assert.equal((await rig.call("POST", "/v1/web/session", { browser: true, body: {} })).status, 400);
  const text = await fetch(`${rig.base}/v1/web/session`, { method: "POST", headers: { origin: WEB_ORIGIN, "x-doddy-web": "1", "content-type": "text/plain" }, body: code });
  assert.equal(text.status, 400);
});

// ------------------------------------------------------------------ what a browser session may do

test("a browser session reads the workspace lists and nothing that runs tools or changes accounts", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  assert.equal((await rig.call("GET", "/v1/tools", { cookie })).status, 200);
  assert.equal((await rig.call("GET", "/v1/tools/receipts", { cookie })).status, 200);
  assert.equal((await rig.call("GET", "/v1/web/documents", { cookie })).status, 200);
  assert.equal((await rig.call("GET", "/v1/web/sessions", { cookie })).status, 200);
  // Same-origin headers don't widen it.
  for (const [method, path, body] of [
    ["POST", "/v1/tools/prepare", { tool: "web_search", arguments: { query: "x" } }],
    ["POST", "/v1/tools/run", { tool: "web_search", arguments: { query: "x" }, timeZone: "Europe/Warsaw" }],
    ["PUT", "/v1/tools/switch", { tool: "web_search", enabled: false }],
    ["POST", "/v1/tools/gmail/connect", {}],
    ["GET", "/v1/connected-apps", undefined],
  ] as const) {
    const res = await rig.call(method, path, { cookie, browser: true, ...(body ? { body } : {}) });
    assert.equal(res.status, 401, `${method} ${path}`);
  }
});

test("a forged, unknown or malformed cookie is signed out and the browser is told to drop it", async () => {
  rig = await startWeb();
  for (const cookie of ["x".repeat(43), "short", "a".repeat(43) + "; extra"]) {
    const res = await rig.call("GET", "/v1/web/session", { cookie });
    assert.equal(res.status, 401);
    assert.match(res.headers.get("set-cookie") ?? "", /^__Host-doddy_web=; Path=\/; Max-Age=0; HttpOnly; SameSite=Strict; Secure$/);
  }
  assert.equal((await rig.call("GET", "/v1/web/session")).status, 401);
  // A phone token can't stand in for a browser on browser-only routes.
  assert.equal((await rig.call("GET", "/v1/web/session", { token: USER_A })).status, 401);
});

// ------------------------------------------------------------------ isolation

test("one user's browser never sees or touches another user's documents or sessions", async () => {
  rig = await startWeb();
  const docA = await makeDocument(rig, "A's plan", USER_A);
  await rig.tools.settle();
  const cookieA = await rig.signIn(await rig.code(USER_A));
  const cookieB = await rig.signIn(await rig.code(USER_B));
  const idA = new URL(docA.document.url).pathname.split("/").pop()!;

  const listB = await rig.call("GET", "/v1/web/documents", { cookie: cookieB });
  assert.deepEqual(listB.body.documents, []);
  const fileB = await rig.call("GET", `/v1/web/documents/${idA}/file`, { cookie: cookieB });
  assert.equal(fileB.status, 404, "another user's document reads as missing, not forbidden");
  assert.equal((await rig.call("GET", `/v1/web/documents/${idA}/file`, { token: USER_B })).status, 404, "the same for B's phone");
  assert.equal((await rig.call("GET", `/v1/web/documents/${idA}/file`, { cookie: cookieA })).status, 200);

  const sessionsA = (await rig.call("GET", "/v1/web/sessions", { cookie: cookieA })).body.sessions;
  assert.equal(sessionsA.length, 1);
  const sessionsB = (await rig.call("GET", "/v1/web/sessions", { cookie: cookieB })).body.sessions;
  assert.equal(sessionsB.length, 1);
  assert.notEqual(sessionsA[0].id, sessionsB[0].id);
  const revokeOther = await rig.call("DELETE", `/v1/web/sessions/${sessionsA[0].id}`, { cookie: cookieB, browser: true });
  assert.equal(revokeOther.status, 404);
  assert.equal((await rig.call("DELETE", `/v1/web/sessions/${sessionsA[0].id}`, { token: USER_B })).status, 404);
  assert.equal((await rig.call("GET", "/v1/web/session", { cookie: cookieA })).status, 200, "A is still signed in");
});

test("receipts and accounts a browser reads are its own user's", async () => {
  rig = await startWeb();
  await makeDocument(rig, "Only A", USER_A);
  await rig.tools.settle();
  const cookieB = await rig.signIn(await rig.code(USER_B));
  const receiptsB = await rig.call("GET", "/v1/tools/receipts", { cookie: cookieB });
  assert.deepEqual(receiptsB.body.receipts, []);
  const cookieA = await rig.signIn(await rig.code(USER_A));
  const receiptsA = await rig.call("GET", "/v1/tools/receipts", { cookie: cookieA });
  assert.ok(receiptsA.body.receipts.length >= 1);
});

// ------------------------------------------------------------------ documents

test("documents Doddy made on the iPhone are listed and downloadable in the browser, as files only", async () => {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  const slow = new MockClaudeProvider();
  const original = slow.makeDocument.bind(slow);
  slow.makeDocument = async (args) => {
    await gate;
    return original(args);
  };
  rig = await startWeb({ claude: slow });
  const made = await makeDocument(rig, "Laptops for uni");
  const cookie = await rig.signIn(await rig.code());

  const working = DocumentListSchema.parse((await rig.call("GET", "/v1/web/documents", { cookie })).body);
  assert.equal(working.keptDays, 7);
  assert.equal(working.documents.length, 1);
  const doc = working.documents[0]!;
  assert.deepEqual(
    { name: doc.name, kind: doc.kind, status: doc.status, sizeBytes: doc.sizeBytes, deleteAfter: doc.deleteAfter },
    { name: "Laptops for uni.pdf", kind: "pdf", status: "working", sizeBytes: null, deleteAfter: "2026-10-29T10:00:00.000Z" },
  );
  assert.equal(new URL(made.document.url).pathname, `/v1/documents/${doc.id}`);
  assert.equal((await rig.call("GET", `/v1/web/documents/${doc.id}/file`, { cookie })).status, 404, "no file while it's being made");

  release();
  await rig.tools.settle();
  const ready = DocumentListSchema.parse((await rig.call("GET", "/v1/web/documents", { cookie })).body).documents[0]!;
  assert.equal(ready.status, "ready");
  assert.equal(ready.sizeBytes, Buffer.byteLength("DEMO PDF: Laptops for uni"));

  const file = await rig.call("GET", `/v1/web/documents/${doc.id}/file`, { cookie });
  assert.equal(file.status, 200);
  assert.equal(file.text, "DEMO PDF: Laptops for uni");
  assert.equal(file.headers.get("content-type"), "application/pdf");
  assert.match(file.headers.get("content-disposition")!, /^attachment; filename="Laptops for uni.pdf"/);
  assert.equal(file.headers.get("content-security-policy"), "sandbox; default-src 'none'");
  assert.equal(file.headers.get("x-content-type-options"), "nosniff");
  assert.match(file.headers.get("cache-control")!, /no-store/);
  // Malformed IDs are just not found.
  assert.equal((await rig.call("GET", "/v1/web/documents/..%2F..%2Fetc/file", { cookie })).status, 404);
  assert.equal((await rig.call("GET", "/v1/web/documents/short/file", { cookie })).status, 404);
});

test("a document still 'working' after ten minutes shows as interrupted, never as still being made", async () => {
  const never = new MockClaudeProvider();
  never.makeDocument = () => new Promise(() => {});
  rig = await startWeb({ claude: never });
  await makeDocument(rig, "Stuck");
  const cookie = await rig.signIn(await rig.code());
  assert.equal((await rig.call("GET", "/v1/web/documents", { cookie })).body.documents[0].status, "working");
  rig.clock.advance(10 * MINUTE + 1);
  assert.equal((await rig.call("GET", "/v1/web/documents", { cookie })).body.documents[0].status, "interrupted");
  // The never-ending job is dropped so the rig can close.
  (rig.tools as unknown as { background: Set<Promise<void>> }).background.clear();
});

// ------------------------------------------------------------------ signing out, expiry, revocation

test("signing out ends the session at once and clears the cookie; it needs the web app's origin", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  const forged = await rig.call("DELETE", "/v1/web/session", { cookie, headers: { origin: "https://evil.example", "x-doddy-web": "1" } });
  assert.equal(forged.status, 401, "a cross-site page can't sign you out (or in)");
  assert.equal((await rig.call("GET", "/v1/web/session", { cookie })).status, 200);

  const out = await rig.call("DELETE", "/v1/web/session", { cookie, browser: true });
  assert.equal(out.status, 200, out.text);
  assert.match(out.headers.get("set-cookie")!, /Max-Age=0/);
  assert.equal((await rig.call("GET", "/v1/web/session", { cookie })).status, 401);
  assert.equal((await rig.call("GET", "/v1/tools", { cookie })).status, 401);
});

test("the iPhone lists signed-in browsers and signs one out; that browser is out at once", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code(), CHROME_MAC);
  const listed = SessionListSchema.parse((await rig.call("GET", "/v1/web/sessions", { token: USER_A })).body).sessions;
  assert.equal(listed.length, 1);
  assert.equal(listed[0]!.current, false, "the phone isn't a browser session");
  assert.equal(listed[0]!.browser, "chrome");
  const revoked = await rig.call("DELETE", `/v1/web/sessions/${listed[0]!.id}`, { token: USER_A });
  assert.equal(revoked.status, 200);
  assert.equal((await rig.call("GET", "/v1/web/session", { cookie })).status, 401);
  assert.deepEqual((await rig.call("GET", "/v1/web/sessions", { token: USER_A })).body.sessions, []);
  assert.equal((await rig.call("DELETE", `/v1/web/sessions/${listed[0]!.id}`, { token: USER_A })).status, 404, "twice: already gone");
});

test("a browser signing itself out from the list also clears its cookie", async () => {
  rig = await startWeb();
  const cookie = await rig.signIn(await rig.code());
  const id = (await rig.call("GET", "/v1/web/session", { cookie })).body.session.id;
  const res = await rig.call("DELETE", `/v1/web/sessions/${id}`, { cookie, browser: true });
  assert.equal(res.status, 200);
  assert.match(res.headers.get("set-cookie")!, /Max-Age=0/);
  assert.equal((await rig.call("DELETE", `/v1/web/sessions/${id}`, { cookie })).status, 401, "a revoke without the origin check is refused");
});

test("sessions end after 14 idle days, and after 30 days however much they're used", async () => {
  rig = await startWeb();
  const idle = await rig.signIn(await rig.code());
  rig.clock.advance(14 * DAY);
  assert.equal((await rig.call("GET", "/v1/web/session", { cookie: idle })).status, 401);

  const busy = await rig.signIn(await rig.code());
  for (let day = 0; day < 29; day += 7) {
    rig.clock.advance(7 * DAY);
    const res = await rig.call("GET", "/v1/web/session", { cookie: busy });
    assert.equal(res.status, day + 7 < 30 ? 200 : 401, `day ${day + 7}`);
  }
  rig.clock.advance(3 * DAY);
  assert.equal((await rig.call("GET", "/v1/web/session", { cookie: busy })).status, 401, "day 31");
});

test("at most ten browsers per user: the eleventh signs the oldest out", async () => {
  rig = await startWeb();
  const cookies: string[] = [];
  for (let i = 0; i < 11; i++) {
    cookies.push(await rig.signIn(await rig.code()));
    rig.clock.advance(1000);
  }
  assert.equal((await rig.call("GET", "/v1/web/session", { cookie: cookies[0]! })).status, 401);
  for (const cookie of cookies.slice(1)) assert.equal((await rig.call("GET", "/v1/web/session", { cookie })).status, 200);
  assert.equal((await rig.call("GET", "/v1/web/sessions", { token: USER_A })).body.sessions.length, 10);
});

test("expired codes and sessions are pruned a day later", async () => {
  rig = await startWeb();
  await rig.signIn(await rig.code());
  await rig.code();
  rig.clock.advance(15 * DAY + DAY + 1);
  const removed = await rig.store.pruneWeb(rig.clock.ms, 14 * DAY);
  assert.equal(removed, 2, "the newest code and the idle session");
  assert.equal((await rig.store.db.query("SELECT 1 FROM web_sessions")).rows.length, 0);
});

// ------------------------------------------------------------------ privacy of logs

test("logs name routes and statuses only: no codes, tokens, cookies or document names", async () => {
  rig = await startWeb();
  await makeDocument(rig, "Secret salary plan");
  await rig.tools.settle();
  const code = await rig.code();
  const cookie = await rig.signIn(code, CHROME_MAC);
  await rig.call("GET", "/v1/web/documents", { cookie });
  await rig.call("POST", "/v1/web/session", { browser: true, body: { code: "WRNG-CODE" } });
  const logs = rig.logs.join("\n");
  for (const secret of [code, code.replace("-", ""), cookie, "Secret salary", "Macintosh", USER_A]) assert.ok(!logs.includes(secret), secret);
  assert.match(logs, /"route":"POST \/v1\/web\/session","status":200/);
  assert.match(logs, /"route":"GET \/v1\/web\/documents","status":200/);
});

// ------------------------------------------------------------------ the web app's pages

test("pages: the app for any page path, hashed files cached forever, strict headers, nothing else", async () => {
  rig = await startWeb();
  for (const path of ["/", "/documents", "/settings/sessions"]) {
    const res = await rig.call("GET", path);
    assert.equal(res.status, 200, path);
    assert.match(res.text, /<div id=root>/);
    assert.equal(res.headers.get("cache-control"), "no-cache");
    const csp = res.headers.get("content-security-policy")!;
    for (const rule of ["default-src 'self'", "script-src 'self'", "connect-src 'self'", "frame-ancestors 'none'", "object-src 'none'", "base-uri 'none'"]) assert.ok(csp.includes(rule), rule);
    assert.equal(res.headers.get("x-frame-options"), "DENY");
    assert.match(res.headers.get("permissions-policy")!, /microphone=\(\)/);
    assert.match(res.headers.get("strict-transport-security")!, /max-age=/);
  }
  const asset = await rig.call("GET", "/assets/app-abc123.js");
  assert.equal(asset.status, 200);
  assert.equal(asset.headers.get("cache-control"), "public, max-age=31536000, immutable");
  assert.match(asset.headers.get("content-type")!, /^text\/javascript/);
  for (const path of ["/.env", "/assets/missing.js", "/%2e%2e/%2e%2e/etc/passwd.txt", "/assets/..%2F..%2Fpackage.json", "/x.exe"]) {
    assert.equal((await rig.call("GET", path)).status, 404, path);
  }
  // The API never falls back to the page.
  const api = await rig.call("GET", "/v1/nothing-here");
  assert.equal(api.status, 404);
  assert.equal(api.body.error.code, "not_found");
  assert.equal((await rig.call("POST", "/documents", { body: {} })).status, 404);
  assert.equal((await rig.call("GET", "/v1/web/unknown")).status, 404);
});

test("without a built web app the pages say so, and the API still works", async () => {
  rig = await startWeb({ withDist: false });
  const res = await rig.call("GET", "/");
  assert.equal(res.status, 503);
  assert.match(res.text, /isn't built/);
  assert.equal((await rig.call("POST", "/v1/web/link-codes", { token: USER_A, body: {} })).status, 200);
});

test("on http loopback (local development) the cookie has no __Host- prefix and no Secure flag", async () => {
  rig = await startWeb({ origin: "http://127.0.0.1:5173" });
  const code = await rig.code();
  const res = await rig.call("POST", "/v1/web/session", { body: { code }, headers: { origin: "http://127.0.0.1:5173", "x-doddy-web": "1" } });
  assert.equal(res.status, 200, res.text);
  assert.match(res.headers.get("set-cookie")!, /^doddy_web=[A-Za-z0-9_-]{43}; Path=\/; Max-Age=2592000; HttpOnly; SameSite=Strict$/);
  assert.ok(!(await rig.call("GET", "/")).headers.get("strict-transport-security"));
});

// ------------------------------------------------------------------ config and helpers

test("config: the web app is off unless DODDY_WEB_ORIGIN is a valid origin", () => {
  assert.equal(loadConfig({}).web, null);
  assert.deepEqual(loadConfig({ DODDY_WEB_ORIGIN: "http://127.0.0.1:8787" }).web, { origin: "http://127.0.0.1:8787", distDir: "../web/dist", trustProxy: false });
  assert.deepEqual(loadConfig({ DODDY_WEB_ORIGIN: "https://app.doddy.lol/", DODDY_WEB_DIST: "/srv/web", DODDY_TRUST_PROXY: "1" }).web, {
    origin: "https://app.doddy.lol",
    distDir: "/srv/web",
    trustProxy: true,
  });
  for (const bad of ["http://app.doddy.lol", "https://app.doddy.lol/app", "https://app.doddy.lol?x=1", "not a url", "https://user:pw@app.doddy.lol"]) {
    assert.throws(() => loadConfig({ DODDY_WEB_ORIGIN: bad }), /DODDY_WEB_ORIGIN/, bad);
  }
});

test("browser and system are read coarsely from the User-Agent", () => {
  assert.deepEqual(describeAgent(CHROME_MAC), { browser: "chrome", os: "macos" });
  assert.deepEqual(describeAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1"), { browser: "safari", os: "ios" });
  assert.deepEqual(describeAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0"), { browser: "edge", os: "windows" });
  assert.deepEqual(describeAgent("Mozilla/5.0 (X11; Linux x86_64; rv:144.0) Gecko/20100101 Firefox/144.0"), { browser: "firefox", os: "linux" });
  assert.deepEqual(describeAgent("Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36"), { browser: "chrome", os: "android" });
  assert.deepEqual(describeAgent(undefined), { browser: "other", os: "other" });
});

test("the cookie name is fixed by the origin's scheme", async () => {
  rig = await startWeb();
  const res = await rig.call("POST", "/v1/web/session", { browser: true, body: { code: await rig.code() } });
  assert.ok(cookieValue(res.headers.get("set-cookie"), COOKIE));
});

test("contracts/web fixtures match the schemas the server answers with", async () => {
  const { readFileSync } = await import("node:fs");
  const { ErrorResponseSchema } = await import("../src/contracts.js");
  const read = (name: string) => JSON.parse(readFileSync(new URL(`../../../contracts/web/${name}.json`, import.meta.url), "utf8"));
  LinkCodeSchema.parse(read("link-code"));
  CurrentSessionSchema.parse(read("session-signed-in"));
  CurrentSessionSchema.parse(read("session-current"));
  SessionListSchema.parse(read("sessions-phone"));
  for (const name of ["documents-empty", "documents-working", "documents-ready", "documents-interrupted"]) DocumentListSchema.parse(read(name));
  for (const name of ["error-code-invalid", "error-signed-out"]) ErrorResponseSchema.parse(read(name));
  assert.deepEqual(
    read("documents-interrupted").documents.map((d: { status: string }) => d.status),
    ["ready", "interrupted", "ready"],
  );
});
