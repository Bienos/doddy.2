// Shared by the waitlist admin functions. Files starting with "_" in api/ are not deployed as routes.
import { createHash, timingSafeEqual } from "node:crypto";
import { get, list } from "@vercel/blob";
import { clientAddress, GuardUnavailable, takeAttempt } from "./_admin-guard.js";

const digest = (value) => createHash("sha256").update(value).digest();

// HTTP Basic auth: any username, password = WAITLIST_ADMIN_PASSWORD. Constant time: both sides are
// hashed to the same length before timingSafeEqual.
function passwordMatches(header, password) {
  if (!header.startsWith("Basic ")) return false;
  const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  const given = decoded.slice(decoded.indexOf(":") + 1);
  return timingSafeEqual(digest(given), digest(password));
}

const json = { "Content-Type": "application/json", "Cache-Control": "no-store" };

export const unauthorized = (prompt = true) =>
  new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
    status: 401,
    headers: {
      ...json,
      // The admin page sends its own credentials; only plain browser visits get the login prompt.
      ...(prompt ? { "WWW-Authenticate": 'Basic realm="Doddy waitlist", charset="UTF-8"' } : {}),
    },
  });

const tooManyAttempts = (retryAfter) =>
  new Response(JSON.stringify({ ok: false, error: "too_many_attempts", retryAfter }), {
    status: 429,
    headers: { ...json, "Retry-After": String(retryAfter) },
  });

const unavailable = () => new Response(JSON.stringify({ ok: false, error: "unavailable" }), { status: 503, headers: json });

// How long a request that brought a wrong password waits before it is answered (ADR-714). It only slows
// each connection; the limit on attempts per address is in _admin-guard.js.
export const FAILED_LOGIN_DELAY_MS = 750;

// Log lines hold the route and method only: nothing from the request's headers, body or address.
const log = (event, route, request) => console.warn(JSON.stringify({ event, route, method: request.method }));

// Null when the request is the admin's; otherwise the answer to send.
// - No credentials (the browser's first visit, before it asks for the password): answered at once, not counted.
// - Credentials: first an attempt is taken for the caller's address (_admin-guard.js). A locked-out address
//   gets 429 and its password is not compared; if the attempt can't be counted, 503 and nothing is compared.
// - A wrong password (or no WAITLIST_ADMIN_PASSWORD, which locks the routes) is logged, then answered after
//   the delay: 401, or 429 when it was the last attempt the address had.
export async function admit(request, route, prompt = true) {
  const header = request.headers.get("authorization");
  if (!header) return unauthorized(prompt);
  const password = process.env.WAITLIST_ADMIN_PASSWORD;
  let slot = null;
  if (password) {
    try {
      slot = await takeAttempt(password, clientAddress(request));
    } catch (err) {
      if (!(err instanceof GuardUnavailable)) throw err;
      log("waitlist_admin_guard_unavailable", route, request);
      return unavailable();
    }
    if (slot.locked) {
      log("waitlist_admin_locked_out", route, request);
      return tooManyAttempts(slot.retryAfter);
    }
    if (passwordMatches(header, password)) {
      await slot.release();
      return null;
    }
  }
  log("waitlist_admin_login_failed", route, request);
  await new Promise((resolve) => setTimeout(resolve, FAILED_LOGIN_DELAY_MS));
  return slot?.lockedNow ? tooManyAttempts(slot.retryAfter) : unauthorized(prompt);
}

async function readRecord(pathname) {
  const result = await get(pathname, { access: "private" });
  if (result?.statusCode !== 200) return null;
  try {
    const { answerKeyHash, ...record } = JSON.parse(await new Response(result.stream).text());
    // id = the hash in the file name; used to delete one signup without sending its email around.
    return { id: pathname.slice("waitlist/".length, -".json".length), ...record };
  } catch {
    return null;
  }
}

// Every signup, oldest first.
export async function readAll() {
  const pathnames = [];
  let cursor;
  do {
    const page = await list({ prefix: "waitlist/", cursor, limit: 1000 });
    pathnames.push(...page.blobs.map((b) => b.pathname));
    cursor = page.cursor;
  } while (cursor);

  const records = [];
  for (let i = 0; i < pathnames.length; i += 20) {
    const batch = await Promise.all(pathnames.slice(i, i + 20).map(readRecord));
    records.push(...batch.filter(Boolean));
  }
  return records.sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
}

export const ID = /^[0-9a-f]{64}$/;
