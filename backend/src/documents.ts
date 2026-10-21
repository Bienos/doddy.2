import { createHmac, timingSafeEqual } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Store } from "./store.js";

/**
 * Links to files Claude made (ADR-563). The phone opens them in Safari, which shows a deck, a Word
 * file, a spreadsheet or a PDF with Quick Look and a Share button, so the link can't carry the app's
 * session token. Instead it is a capability: the document's random ID (144 bits) plus an HMAC
 * signature over the ID and an expiry, made with the server's signing key. Anyone with the link can
 * open that one file until it expires (seven days, as long as the file is kept), so the link is shown
 * only in the app, never sent to the voice agent.
 */

export const DOCUMENT_LINK_TTL_SECONDS = 7 * 24 * 60 * 60;
const ID = /^[A-Za-z0-9_-]{24}$/;

export class DocumentLinks {
  constructor(
    private readonly key: Buffer,
    private readonly publicBaseUrl: string,
  ) {}

  link(id: string, now: Date): string {
    const exp = Math.floor(now.getTime() / 1000) + DOCUMENT_LINK_TTL_SECONDS;
    return `${this.publicBaseUrl}/v1/documents/${id}?exp=${exp}&sig=${this.sign(id, exp)}`;
  }

  /** The document ID when the link is genuine and unexpired, else null. */
  verify(url: URL, now: Date): string | null {
    const match = /^\/v1\/documents\/([A-Za-z0-9_-]+)$/.exec(url.pathname);
    const id = match?.[1];
    const exp = Number(url.searchParams.get("exp"));
    const sig = url.searchParams.get("sig") ?? "";
    if (!id || !ID.test(id) || !Number.isSafeInteger(exp) || exp < Math.floor(now.getTime() / 1000)) return null;
    const expected = Buffer.from(this.sign(id, exp));
    const given = Buffer.from(sig);
    return expected.length === given.length && timingSafeEqual(expected, given) ? id : null;
  }

  private sign(id: string, exp: number): string {
    return createHmac("sha256", this.key).update(`doddy-document:v1:${id}:${exp}`).digest("base64url");
  }
}

/** GET /v1/documents/:id?exp&sig. Returns the HTTP status it sent. */
export async function serveDocument(req: IncomingMessage, res: ServerResponse, url: URL, links: DocumentLinks, store: Store, now: Date): Promise<number> {
  const id = links.verify(url, now);
  const row = id ? await store.getDocument(id) : null;
  if (!row) return page(res, 404, "This link doesn't work any more", "Doddy keeps files for a week. Ask him to make it again.", false);
  if (row.status === "working") return page(res, 200, "Doddy is still making this", "Claude is working on it. This page checks again every ten seconds.", true);
  if (row.status === "failed" || !row.body) return page(res, 200, "This one didn't work", "Claude couldn't finish the file. Ask Doddy to try again.", false);
  const ascii = row.name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  res.writeHead(200, {
    "content-type": row.mime,
    "content-length": row.body.length,
    // inline: Safari previews it with Quick Look; the share button saves or sends it.
    "content-disposition": `inline; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(row.name)}`,
    "cache-control": "private, no-store",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
  });
  res.end(row.body);
  void req;
  return 200;
}

function page(res: ServerResponse, status: number, title: string, line: string, refresh: boolean): number {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${
    refresh ? '<meta http-equiv="refresh" content="10">' : ""
  }<title>${title}</title><style>body{font:17px -apple-system,system-ui,sans-serif;background:#FFF7E9;color:#171715;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center;padding:24px;box-sizing:border-box}main{max-width:28rem}h1{font-size:24px;margin:0 0 8px}p{margin:0;line-height:1.4}</style></head><body><main><h1>${title}</h1><p>${line}</p></main></body></html>`;
  res.writeHead(status, {
    "content-type": "text/html; charset=utf-8",
    "content-length": Buffer.byteLength(html),
    "cache-control": "no-store",
    "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
  });
  res.end(html);
  return status;
}
