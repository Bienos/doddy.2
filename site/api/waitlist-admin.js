// /api/waitlist-admin — data for the admin page (/admin/). Basic auth, see _waitlist-store.js.
//   GET                  -> {ok, records: [{id, email, page, consent, createdAt}]} oldest first
//   DELETE ?id=<sha256>  -> removes one signup (for "please delete my email" requests)
import { BlobNotFoundError, del, head } from "@vercel/blob";
import { ID, isAdmin, readAll, unauthorized } from "./_waitlist-store.js";

const reply = (body, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store", "X-Robots-Tag": "noindex" } });

export async function GET(request) {
  if (!isAdmin(request)) return unauthorized(false);
  return reply({ ok: true, records: await readAll() });
}

export async function DELETE(request) {
  if (!isAdmin(request)) return unauthorized(false);
  const id = new URL(request.url).searchParams.get("id") ?? "";
  if (!ID.test(id)) return reply({ ok: false, error: "bad_request" }, 400);
  const pathname = `waitlist/${id}.json`;
  try {
    await head(pathname);
  } catch (err) {
    if (err instanceof BlobNotFoundError) return reply({ ok: false, error: "not_found" }, 404);
    throw err;
  }
  await del(pathname);
  return reply({ ok: true, deleted: id });
}
