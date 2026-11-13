// /api/waitlist-admin — data for the admin page (/admin/). Basic auth with limited attempts, see _waitlist-store.js.
//   GET                  -> {ok, records: [{id, email, page, consent, createdAt}]} oldest first
//   DELETE ?id=<sha256>  -> removes one signup (for "please delete my email" requests)
import { BlobNotFoundError, del, head } from "@vercel/blob";
import { sweepGuardRecords } from "./_admin-guard.js";
import { ID, admit, readAll } from "./_waitlist-store.js";

const reply = (body, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store", "X-Robots-Tag": "noindex" } });

export async function GET(request) {
  const refused = await admit(request, "admin", false);
  if (refused) return refused;
  // A signed-in list also deletes expired sign-in attempt records (_admin-guard.js); that never fails the list.
  const [records] = await Promise.all([readAll(), sweepGuardRecords()]);
  return reply({ ok: true, records });
}

export async function DELETE(request) {
  const refused = await admit(request, "admin", false);
  if (refused) return refused;
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
