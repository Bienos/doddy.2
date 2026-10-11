// POST /api/waitlist-answers — the three optional questions shown right after someone joins.
// Body: {"id", "key", "phone", "heard", "wish"}. Every answer is optional; unknown choices are dropped.
// Only the browser that created the signup holds the key (see api/waitlist.js).
// The write only goes through if the stored file is still the one read here (etag), so answers sent
// after the admin deleted the signup can't bring it back.
import { createHash, timingSafeEqual } from "node:crypto";
import { BlobNotFoundError, BlobPreconditionFailedError, get, put } from "@vercel/blob";

const PHONES = ["iphone", "android", "other"];
const HEARD = ["tiktok", "instagram", "linkedin", "friend", "search", "other"];
const MAX_BODY = 2000;
const ID = /^[0-9a-f]{64}$/;

const reply = (body, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const sha = (value) => createHash("sha256").update(value).digest();
// Free text: plain text only, one line, no leading formula characters, capped.
const cleanText = (value, max) =>
  String(value ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim().replace(/^[=+\-@\s]+/, "").slice(0, max);
const pick = (value, allowed) => (allowed.includes(value) ? value : "");

export async function POST(request) {
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

  const id = String(body.id ?? "");
  const key = String(body.key ?? "");
  if (!ID.test(id) || key.length < 16 || key.length > 64) return reply({ ok: false, error: "forbidden" }, 403);

  const pathname = `waitlist/${id}.json`;
  // No CDN cache: a cached copy could outlive a delete or carry an old etag.
  const result = await get(pathname, { access: "private", useCache: false }).catch(() => null);
  if (result?.statusCode !== 200) return reply({ ok: false, error: "forbidden" }, 403);
  // Without an etag the write below would be unconditional.
  if (!result.blob?.etag) return reply({ ok: false, error: "unavailable" }, 503);
  let record;
  try {
    record = JSON.parse(await new Response(result.stream).text());
  } catch {
    return reply({ ok: false, error: "unavailable" }, 503);
  }
  if (!record.answerKeyHash || !timingSafeEqual(sha(key), Buffer.from(record.answerKeyHash, "hex"))) {
    return reply({ ok: false, error: "forbidden" }, 403);
  }

  record.answers = {
    phone: pick(body.phone, PHONES),
    heard: pick(body.heard, HEARD),
    wish: cleanText(body.wish, 300),
    note: "answers-note-v1",
    answeredAt: new Date().toISOString(),
  };
  try {
    await put(pathname, JSON.stringify(record), {
      access: "private",
      addRandomSuffix: false,
      allowOverwrite: true,
      ifMatch: result.blob.etag,
      contentType: "application/json",
    });
  } catch (err) {
    // Deleted or changed since the read: nothing was written.
    if (err instanceof BlobPreconditionFailedError || err instanceof BlobNotFoundError) {
      return reply({ ok: false, error: "forbidden" }, 403);
    }
    console.error("waitlist: answers write failed", err?.name ?? "unknown");
    return reply({ ok: false, error: "unavailable" }, 503);
  }
  return reply({ ok: true });
}
