// POST /api/waitlist — store one waitlist signup privately in Vercel Blob (store "doddy-waitlist", fra1).
// Body: {"email", "page", "consent", "website"} as JSON. Replies {ok, status: "added"} or {ok:false, error}.
// A new signup also gets {id, key}: the key lets that browser add the optional answers (api/waitlist-answers.js).
// An email already stored gets the same reply without id/key, so nobody can use this to check who signed up
// (a script can still notice the missing key; acceptable for a waitlist).
// Only a hash of the key is stored, so nobody who merely knows the email can change the answers.
// Stores only email, page, consent version, time and the answer-key hash. No IP, no user agent, and emails never go to logs.
import { createHash, randomBytes } from "node:crypto";
import { BlobNotFoundError, head, put } from "@vercel/blob";

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_BODY = 2000;

const reply = (body, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

// Plain text only: drop leading characters spreadsheets treat as formulas, and cap the length.
const clean = (value, max) => String(value ?? "").replace(/^[=+\-@\s]+/, "").slice(0, max);

async function exists(pathname) {
  try {
    await head(pathname);
    return true;
  } catch (err) {
    if (err instanceof BlobNotFoundError) return false;
    throw err;
  }
}

export async function POST(request) {
  // Only this site's own form: a browser always sends Origin on a cross-site POST.
  const origin = request.headers.get("origin");
  if (origin && new URL(origin).host !== request.headers.get("host")) {
    return reply({ ok: false, error: "forbidden" }, 403);
  }

  const raw = await request.text();
  if (raw.length > MAX_BODY) return reply({ ok: false, error: "bad_request" }, 413);
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return reply({ ok: false, error: "bad_request" }, 400);
  }

  // Honeypot: people never see or fill "website"; bots usually do. Pretend it worked.
  if (body.website) return reply({ ok: true, status: "added" });

  const email = String(body.email ?? "").trim().toLowerCase();
  if (!email || email.length > 254 || !EMAIL.test(email) || /^[=+\-@]/.test(email)) {
    return reply({ ok: false, error: "invalid_email" }, 400);
  }

  // One blob per email; the name is a hash so the same email can only be stored once.
  const id = createHash("sha256").update(email).digest("hex");
  const pathname = `waitlist/${id}.json`;
  const key = randomBytes(18).toString("base64url");
  const record = {
    email,
    page: clean(body.page, 200),
    consent: clean(body.consent, 40),
    createdAt: new Date().toISOString(),
    answerKeyHash: createHash("sha256").update(key).digest("hex"),
  };

  try {
    if (await exists(pathname)) return reply({ ok: true, status: "added" });
    await put(pathname, JSON.stringify(record), {
      access: "private",
      addRandomSuffix: false,
      allowOverwrite: false,
      contentType: "application/json",
    });
    return reply({ ok: true, status: "added", id, key });
  } catch (err) {
    // A duplicate signup can win the race between head() and put(); same reply as above.
    if (await exists(pathname).catch(() => false)) return reply({ ok: true, status: "added" });
    console.error("waitlist: write failed", err?.name ?? "unknown");
    return reply({ ok: false, error: "unavailable" }, 503);
  }
}
