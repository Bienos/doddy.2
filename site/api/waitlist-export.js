// GET /api/waitlist-export — download every waitlist signup as a CSV that opens in Excel or Google Sheets.
// Protected by HTTP Basic auth: any username, password = WAITLIST_ADMIN_PASSWORD (a Vercel environment variable).
import { createHash, timingSafeEqual } from "node:crypto";
import { get, list } from "@vercel/blob";

const digest = (value) => createHash("sha256").update(value).digest();

function authorized(header, password) {
  if (!header?.startsWith("Basic ")) return false;
  const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  const given = decoded.slice(decoded.indexOf(":") + 1);
  return timingSafeEqual(digest(given), digest(password));
}

// CSV cell: quote it, and neutralise anything a spreadsheet would run as a formula.
function cell(value) {
  let text = String(value ?? "");
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  return `"${text.replace(/"/g, '""')}"`;
}

async function readRecord(pathname) {
  const result = await get(pathname, { access: "private" });
  if (result?.statusCode !== 200) return null;
  try {
    return JSON.parse(await new Response(result.stream).text());
  } catch {
    return null;
  }
}

export async function GET(request) {
  const password = process.env.WAITLIST_ADMIN_PASSWORD;
  if (!password || !authorized(request.headers.get("authorization"), password)) {
    return new Response("Sign in to download the Doddy waitlist.", {
      status: 401,
      headers: { "WWW-Authenticate": 'Basic realm="Doddy waitlist", charset="UTF-8"', "Cache-Control": "no-store" },
    });
  }

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
  records.sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));

  const lines = [["Signed up (UTC)", "Email", "Page", "Consent version"].map(cell).join(",")];
  for (const r of records) lines.push([r.createdAt, r.email, r.page, r.consent].map(cell).join(","));
  // The BOM makes Excel read the file as UTF-8.
  const csv = "﻿" + lines.join("\r\n") + "\r\n";
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
