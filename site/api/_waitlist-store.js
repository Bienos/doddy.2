// Shared by the waitlist admin functions. Files starting with "_" in api/ are not deployed as routes.
import { createHash, timingSafeEqual } from "node:crypto";
import { get, list } from "@vercel/blob";

const digest = (value) => createHash("sha256").update(value).digest();

// HTTP Basic auth: any username, password = WAITLIST_ADMIN_PASSWORD. Locked if the variable is missing.
export function isAdmin(request) {
  const password = process.env.WAITLIST_ADMIN_PASSWORD;
  const header = request.headers.get("authorization");
  if (!password || !header?.startsWith("Basic ")) return false;
  const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  const given = decoded.slice(decoded.indexOf(":") + 1);
  return timingSafeEqual(digest(given), digest(password));
}

export const unauthorized = (prompt = true) =>
  new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
    status: 401,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      // The admin page sends its own credentials; only plain browser visits get the login prompt.
      ...(prompt ? { "WWW-Authenticate": 'Basic realm="Doddy waitlist", charset="UTF-8"' } : {}),
    },
  });

// How long a request that brought a wrong password waits before it is answered (ADR-714). It slows a
// script guessing the password to a few guesses a second per connection and no more: serverless runs as
// many instances as there are requests, so the real brake is a rate limit in the Vercel Firewall.
export const FAILED_LOGIN_DELAY_MS = 750;

// The answer for a request that is not the admin's. A request with no credentials (the browser's first
// visit, before it asks for the password) is answered at once; one that carried credentials is a failed
// login: it is counted in a log line that holds nothing from the request, then answered after the delay.
export async function refuse(request, route, prompt = true) {
  if (request.headers.has("authorization")) {
    console.warn(JSON.stringify({ event: "waitlist_admin_login_failed", route, method: request.method }));
    await new Promise((resolve) => setTimeout(resolve, FAILED_LOGIN_DELAY_MS));
  }
  return unauthorized(prompt);
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
