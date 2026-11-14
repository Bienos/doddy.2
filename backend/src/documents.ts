import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { MemoryCipher } from "./memory/crypto.js";
import type { Store } from "./store.js";

/**
 * Links to files Claude made (ADR-564). The phone opens them in Safari, which shows a deck, a Word
 * file, a spreadsheet or a PDF with Quick Look and a Share button, so the link can't carry the app's
 * session token. Instead it is a capability: the document's random ID (144 bits) plus an HMAC
 * signature over the ID, the account it was made for and an expiry, made with the server's signing
 * key. Every open looks the file up again: a deleted file, or one that isn't that account's, doesn't
 * open. The link is shown only in the app, never sent to the voice agent.
 *
 * A link works for a day (decision 2026-11-12-documents-at-rest), the file is kept a week: after a day
 * the app's own Share and Files download it with the app's sign-in (`GET /v1/web/documents/:id/file`).
 * The day covers the app's Messages card and the file-ready push (`server/messaging`, which asks the
 * link for 15 minutes at most).
 */
export const DOCUMENT_LINK_TTL_SECONDS = 24 * 60 * 60;
/**
 * A file still "working" after this long has lost its job: a whole job ends within 8 minutes (DOCUMENT_TIMEOUT_MS), and it runs in
 * this server's memory, so a restart or a stop in the middle leaves the row "working" for good. Past this it is read as failed.
 */
export const DOCUMENT_STALE_AFTER_MS = 10 * 60_000;
const ID = /^[A-Za-z0-9_-]{24}$/;

/** A link's parts, before anything in it is trusted. */
export interface LinkClaim {
  id: string;
  exp: number;
  sig: string;
}

/** `ok`: genuine for this account and unexpired. `expired`: genuine but past its time (or signed the older way, without the account). */
export type LinkCheck = "ok" | "expired" | "invalid";

export class DocumentLinks {
  constructor(
    private readonly key: Buffer,
    private readonly publicBaseUrl: string,
  ) {}

  link(id: string, userId: string, now: Date): string {
    const exp = Math.floor(now.getTime() / 1000) + DOCUMENT_LINK_TTL_SECONDS;
    return `${this.publicBaseUrl}/v1/documents/${id}?exp=${exp}&sig=${this.sign(id, userId, exp)}`;
  }

  /** The parts of anything shaped like a document link, else null. Nothing is checked yet. */
  claim(url: URL): LinkClaim | null {
    const match = /^\/v1\/documents\/([A-Za-z0-9_-]+)$/.exec(url.pathname);
    const id = match?.[1];
    const exp = Number(url.searchParams.get("exp"));
    const sig = url.searchParams.get("sig") ?? "";
    if (!id || !ID.test(id) || !Number.isSafeInteger(exp) || sig === "") return null;
    return { id, exp, sig };
  }

  /**
   * Whether the link was made by this server for `userId` (the owner of the row it names, read at the
   * time of the request). A link made before the account was part of the signature (the older `v1`
   * signature, 7 days) only ever reads as expired: it is never served again.
   */
  check(claim: LinkClaim, userId: string, now: Date): LinkCheck {
    if (equal(this.sign(claim.id, userId, claim.exp), claim.sig)) {
      return claim.exp < Math.floor(now.getTime() / 1000) ? "expired" : "ok";
    }
    return equal(this.signV1(claim.id, claim.exp), claim.sig) ? "expired" : "invalid";
  }

  private sign(id: string, userId: string, exp: number): string {
    return createHmac("sha256", this.key).update(`doddy-document:v2:${id}:${userId}:${exp}`).digest("base64url");
  }

  private signV1(id: string, exp: number): string {
    return createHmac("sha256", this.key).update(`doddy-document:v1:${id}:${exp}`).digest("base64url");
  }
}

function equal(expected: string, given: string): boolean {
  const a = Buffer.from(expected);
  const b = Buffer.from(given);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * A document's name and file, encrypted at rest (decision 2026-11-12-documents-at-rest) with the key and
 * cipher of kept memory (DODDY_MEMORY_KEY, ADR-603): encryption at rest, not end-to-end. The associated
 * data binds each blob to its account, its row and its part, so a blob copied to another account, row
 * or part doesn't decrypt. Without the key the server makes no files ("not set up"), as kept memory.
 */
export class DocumentSeal {
  constructor(private readonly cipher: MemoryCipher) {}

  get keyVersion(): number {
    return this.cipher.keyVersion;
  }

  sealName(userId: string, id: string, name: string): Buffer {
    return this.cipher.encrypt(name, nameAad(userId, id));
  }

  /** Throws when the blob was altered, belongs to another row or account, or was made with another key. */
  openName(userId: string, id: string, blob: Buffer): string {
    return this.cipher.decrypt(blob, nameAad(userId, id));
  }

  sealFile(userId: string, id: string, bytes: Buffer): Buffer {
    return this.cipher.encryptBytes(bytes, fileAad(userId, id));
  }

  openFile(userId: string, id: string, blob: Buffer): Buffer {
    return this.cipher.decryptBytes(blob, fileAad(userId, id));
  }
}

const nameAad = (userId: string, id: string) => `${userId}:document-name:${id}`;
const fileAad = (userId: string, id: string) => `${userId}:document-file:${id}`;

/**
 * The file kinds Doddy makes (`KIND_INFO`), which the app opens in Safari for Quick Look: these are sent
 * `inline`. Any other type is only ever a download. Both are sandboxed (`serveDocument`).
 */
export const INLINE_DOCUMENT_TYPES: ReadonlySet<string> = new Set([
  "application/pdf",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "text/markdown",
]);

/** `inline` for the kinds above, else `attachment`. Parameters (`; charset=…`) and case don't matter. */
export function documentDisposition(mime: string): "inline" | "attachment" {
  return INLINE_DOCUMENT_TYPES.has(mime.split(";")[0]!.trim().toLowerCase()) ? "inline" : "attachment";
}

/** What a row is, as far as anyone looking at it should be told: "working" for longer than a job can run is "failed". */
export function effectiveStatus(row: { status: "working" | "ready" | "failed"; created_at?: unknown }, now: Date): "working" | "ready" | "failed" {
  if (row.status !== "working") return row.status;
  const created = Number(row.created_at);
  return Number.isFinite(created) && created > 0 && now.getTime() - created > DOCUMENT_STALE_AFTER_MS ? "failed" : "working";
}

/** GET /v1/documents/:id?exp&sig. Returns the HTTP status it sent. */
export async function serveDocument(req: IncomingMessage, res: ServerResponse, url: URL, links: DocumentLinks, store: Store, now: Date): Promise<number> {
  // `?status=1` (file-ready push, 9 Nov 2026): only whether it is still being made, ready or failed, as JSON and with no
  // file bytes, so a poller doesn't download a deck to learn it is ready. The same signed link; no new permission.
  const statusOnly = url.searchParams.get("status") === "1";
  const claim = links.claim(url);
  // Looked up on every open, and the signature checked against the row's own account: a deleted file, or a
  // link made for another account, doesn't open.
  const row = claim ? await store.getDocument(claim.id, { file: !statusOnly }) : null;
  const check: LinkCheck = claim && row ? links.check(claim, row.user_id, now) : "invalid";
  const status = row && check === "ok" ? effectiveStatus(row, now) : null;
  // A lost job is made final, so the list in the app and Doddy Web agree with this page. Only a row still "working" changes.
  if (row && check === "ok" && row.status === "working" && status === "failed") void store.failDocument(row.id).catch(() => {});
  if (statusOnly) return documentStatus(res, status);
  if (check === "expired") {
    return page(res, 404, "This link has expired", "Links to Doddy's files work for a day. In the Doddy app, tap Share on the file: Doddy keeps it for a week.", false);
  }
  if (!row || status === null) return page(res, 404, "This link doesn't work any more", "Doddy keeps files for a week. Ask him to make it again.", false);
  if (status === "working") return page(res, 200, "Doddy is still making this", "Claude is working on it. This page opens the file by itself when it is ready.", true);
  if (status === "failed" || !row.body) return page(res, 200, "This one didn't work", "Claude couldn't finish the file. Ask Doddy to try again.", false);
  const ascii = row.name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  res.writeHead(200, {
    "content-type": row.mime,
    "content-length": row.body.length,
    // The kinds Doddy makes open inline, so Safari previews them with Quick Look and its Share button saves or
    // sends them; any other type is only a download.
    "content-disposition": `${documentDisposition(row.mime)}; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(row.name)}`,
    // Never a page of this origin, even if a browser rendered the file as one: no script, no requests, no origin.
    "content-security-policy": "sandbox; default-src 'none'",
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
