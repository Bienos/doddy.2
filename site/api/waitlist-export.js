// GET /api/waitlist-export — download every waitlist signup as a CSV that opens in Excel or Google Sheets.
// Protected by HTTP Basic auth: any username, password = WAITLIST_ADMIN_PASSWORD (a Vercel environment variable).
import { isAdmin, readAll, unauthorized } from "./_waitlist-store.js";

// CSV cell: quote it, and neutralise anything a spreadsheet would run as a formula.
function cell(value) {
  let text = String(value ?? "");
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  return `"${text.replace(/"/g, '""')}"`;
}

export async function GET(request) {
  if (!isAdmin(request)) return unauthorized(true);

  const records = await readAll();
  const PHONE = { iphone: "iPhone", android: "Android", other: "Something else" };
  const HEARD = { tiktok: "TikTok", instagram: "Instagram", linkedin: "LinkedIn", friend: "A friend", search: "Search", other: "Somewhere else" };
  const header = ["Signed up (UTC)", "Email", "Phone", "Heard about Doddy", "Wants Doddy to", "Answered (UTC)", "Page", "Consent version"];
  const lines = [header.map(cell).join(",")];
  for (const r of records) {
    const a = r.answers ?? {};
    lines.push([r.createdAt, r.email, PHONE[a.phone] ?? "", HEARD[a.heard] ?? "", a.wish ?? "", a.answeredAt ?? "", r.page, r.consent].map(cell).join(","));
  }
  // The BOM makes Excel read the file as UTF-8.
  const csv = "\uFEFF" + lines.join("\r\n") + "\r\n";
  const date = new Date().toISOString().slice(0, 10);

  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="doddy-waitlist-${date}.csv"`,
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex",
    },
  });
}
