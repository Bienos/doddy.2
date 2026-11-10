import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Store } from "./store.js";

/**
 * Links to files Claude made (ADR-564). The phone opens them in Safari, which shows a deck, a Word
 * file, a spreadsheet or a PDF with Quick Look and a Share button, so the link can't carry the app's
 * session token. Instead it is a capability: the document's random ID (144 bits) plus an HMAC
 * signature over the ID and an expiry, made with the server's signing key. Anyone with the link can
 * open that one file until it expires (seven days, as long as the file is kept), so the link is shown
 * only in the app, never sent to the voice agent.
 */

export const DOCUMENT_LINK_TTL_SECONDS = 7 * 24 * 60 * 60;
/**
 * A file still "working" after this long has lost its job: a whole job ends within 8 minutes (DOCUMENT_TIMEOUT_MS), and it runs in
 * this server's memory, so a restart or a stop in the middle leaves the row "working" for good. Past this it is read as failed.
 */
export const DOCUMENT_STALE_AFTER_MS = 10 * 60_000;
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

/** What a row is, as far as anyone looking at it should be told: "working" for longer than a job can run is "failed". */
export function effectiveStatus(row: { status: "working" | "ready" | "failed"; created_at?: unknown }, now: Date): "working" | "ready" | "failed" {
  if (row.status !== "working") return row.status;
  const created = Number(row.created_at);
  return Number.isFinite(created) && created > 0 && now.getTime() - created > DOCUMENT_STALE_AFTER_MS ? "failed" : "working";
}

/** GET /v1/documents/:id?exp&sig. Returns the HTTP status it sent. */
export async function serveDocument(req: IncomingMessage, res: ServerResponse, url: URL, links: DocumentLinks, store: Store, now: Date): Promise<number> {
  const id = links.verify(url, now);
  const row = id ? await store.getDocument(id) : null;
  const status = row ? effectiveStatus(row, now) : null;
  // A lost job is made final, so the list in the app and Doddy Web agree with this page. Only a row still "working" changes.
  if (row && id && row.status === "working" && status === "failed") void store.failDocument(id).catch(() => {});
  // `?status=1` (file-ready push, 9 Nov 2026): only whether it is still being made, ready or failed, as JSON and with no
  // file bytes, so a poller doesn't download a deck to learn it is ready. The same signed link; no new permission.
  if (url.searchParams.get("status") === "1") return documentStatus(res, status);
  if (!row) return page(res, 404, "This link doesn't work any more", "Doddy keeps files for a week. Ask him to make it again.", false);
  if (status === "working") return page(res, 200, "Doddy is still making this", "Claude is working on it. This page opens the file by itself when it is ready.", true);
  if (status === "failed" || !row.body) return page(res, 200, "This one didn't work", "Claude couldn't finish the file. Ask Doddy to try again.", false);
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

/**
 * The page for a file still being made reloads itself when the file is ready. `<meta refresh>` alone isn't enough: Safari
 * stops it while the tab is in the background, which left people looking at "still making" long after the file was done. The
 * script asks the same signed link for `?status=1` (JSON, no file), every few seconds, and again the moment the tab is shown
 * or restored. The meta refresh stays as the fallback. The script is allowed by a per-response nonce, nothing else.
 */
function waitingScript(nonce: string): string {
  const code =
    'var u=new URL(location.href);u.searchParams.set("status","1");var busy=false;' +
    "function check(){if(busy)return;busy=true;" +
    'fetch(u.href,{cache:"no-store"}).then(function(r){return r.json()}).then(function(s){if(s&&s.status!=="working")location.reload()}).catch(function(){}).then(function(){busy=false})}' +
    "setInterval(check,4000);" +
    'document.addEventListener("visibilitychange",function(){if(!document.hidden)check()});' +
    'window.addEventListener("pageshow",check);';
  return `<script nonce="${nonce}">${code}</script>`;
}

function page(res: ServerResponse, status: number, title: string, line: string, refresh: boolean): number {
  const nonce = randomBytes(16).toString("base64url");
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${
    refresh ? '<meta http-equiv="refresh" content="10">' : ""
  }<title>${title}</title><style>body{font:17px -apple-system,system-ui,sans-serif;background:#FFF7E9;color:#171715;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center;padding:24px;box-sizing:border-box}main{max-width:28rem}h1{font-size:24px;margin:0 0 8px}p{margin:0;line-height:1.4}</style></head><body><main><h1>${title}</h1><p>${line}</p></main>${refresh ? waitingScript(nonce) : ""}</body></html>`;
  res.writeHead(status, {
    "content-type": "text/html; charset=utf-8",
    "content-length": Buffer.byteLength(html),
    "cache-control": "no-store",
    // The only script is the waiting page's own (by nonce); it may ask this same origin, and nothing else, for the status.
    "content-security-policy": refresh ? `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; connect-src 'self'` : "default-src 'none'; style-src 'unsafe-inline'",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
  });
  res.end(html);
  return status;
}

/** `{ status }` for a document link: working, ready, failed, or gone (a link that no longer works). */
function documentStatus(res: ServerResponse, status: "working" | "ready" | "failed" | null): number {
  const body = JSON.stringify({ status: status ?? "gone" });
  const code = status === null ? 404 : 200;
  res.writeHead(code, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "private, no-store",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
  });
  res.end(body);
  return code;
}
