import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import type { IncomingMessage, ServerResponse } from "node:http";
import { extname, join, normalize, resolve, sep } from "node:path";
import { promisify } from "node:util";
import { brotliCompress, constants as zlibConstants, gzip } from "node:zlib";

const brotliAsync = promisify(brotliCompress);
const gzipAsync = promisify(gzip);

/** Types worth compressing; images, fonts (woff2) and icons already are, or gain nothing. */
const COMPRESSIBLE = new Set([".html", ".js", ".css", ".json", ".webmanifest", ".svg", ".txt"]);
const MIN_COMPRESS_BYTES = 1024;
/** The built app is a few dozen files; this bounds the memory held if the folder ever grows. */
const MAX_CACHED_FILES = 256;

interface CachedFile {
  mtimeMs: number;
  size: number;
  body: Buffer;
  etag: string;
  br?: Buffer;
  gz?: Buffer;
}

/**
 * Serves the built web app (`web/dist`, ADR-600) from this server, so the app, its API and its
 * session cookie share one origin. Only files inside the folder with a known type are served; a
 * path without a file extension is a page of the app and gets `index.html`. API paths (`/v1/…`)
 * never reach here.
 */

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".txt": "text/plain; charset=utf-8",
  ".woff2": "font/woff2",
};

export class WebStatic {
  private readonly root: string;
  private readonly secure: boolean;
  /** Built files by path. An entry is reused only while the file's size and modified time still match. */
  private readonly cache = new Map<string, CachedFile>();

  constructor(distDir: string, origin: string) {
    this.root = resolve(distDir);
    this.secure = origin.startsWith("https:");
  }

  /** Handles GET or HEAD for a non-API path. Returns the status it sent. */
  async serve(req: IncomingMessage, res: ServerResponse, pathname: string): Promise<number> {
    let decoded: string;
    try {
      decoded = decodeURIComponent(pathname);
    } catch {
      return this.plain(res, 400, "Bad path.");
    }
    if (decoded.includes("\0")) return this.plain(res, 400, "Bad path.");
    // No dotfiles or dot-folders, not even as page paths.
    if (decoded.split(/[/\\]/).some((part) => part.startsWith("."))) return this.plain(res, 404, "Not found.");
    const isPage = extname(decoded) === "";
    const relative = isPage ? "index.html" : normalize(decoded).replace(/^([/\\])+/, "");
    const file = join(this.root, relative);
    // No way out of the folder, and no dotfiles.
    if (!file.startsWith(this.root + sep) || relative.split(/[/\\]/).some((part) => part.startsWith("."))) return this.plain(res, 404, "Not found.");
    const type = TYPES[extname(file)];
    if (!type) return this.plain(res, 404, "Not found.");
    let entry: CachedFile;
    try {
      const info = await stat(file);
      if (!info.isFile()) return this.plain(res, 404, "Not found.");
      entry = await this.load(file, info.mtimeMs, info.size);
    } catch {
      return isPage
        ? this.plain(res, 503, "Doddy's web app isn't built on this server yet.")
        : this.plain(res, 404, "Not found.");
    }
    // Hashed build files never change; the page itself is always fetched fresh (but may be answered 304).
    const immutable = relative.startsWith(`assets${sep}`) || relative.startsWith("assets/");
    const headers: Record<string, string | number> = {
      "content-type": type,
      "cache-control": immutable ? "public, max-age=31536000, immutable" : "no-cache",
      etag: entry.etag,
      vary: "Accept-Encoding",
      ...this.securityHeaders(),
    };
    if (matchesEtag(req.headers["if-none-match"], entry.etag)) {
      res.writeHead(304, headers);
      res.end();
      return 304;
    }
    let body = entry.body;
    const accepted = String(req.headers["accept-encoding"] ?? "");
    if (COMPRESSIBLE.has(extname(file)) && entry.body.length >= MIN_COMPRESS_BYTES) {
      if (/\bbr\b/.test(accepted)) {
        entry.br ??= await brotliAsync(entry.body, { params: { [zlibConstants.BROTLI_PARAM_QUALITY]: 9 } });
        body = entry.br;
        headers["content-encoding"] = "br";
      } else if (/\bgzip\b/.test(accepted)) {
        entry.gz ??= await gzipAsync(entry.body, { level: 9 });
        body = entry.gz;
        headers["content-encoding"] = "gzip";
      }
    }
    headers["content-length"] = body.length;
    res.writeHead(200, headers);
    res.end(req.method === "HEAD" ? undefined : body);
    return 200;
  }

  private async load(file: string, mtimeMs: number, size: number): Promise<CachedFile> {
    const hit = this.cache.get(file);
    if (hit && hit.mtimeMs === mtimeMs && hit.size === size) return hit;
    const body = await readFile(file);
    const etag = `"${createHash("sha256").update(body).digest("base64url").slice(0, 22)}"`;
    const entry: CachedFile = { mtimeMs, size, body, etag };
    if (this.cache.size >= MAX_CACHED_FILES) this.cache.delete(this.cache.keys().next().value as string);
    this.cache.set(file, entry);
    return entry;
  }

  /**
   * The page's rules: scripts, styles, images and API calls only from this origin; no frames, no
   * plugins, no other sites. The microphone stays off until voice on the web is a decided milestone.
   */
  securityHeaders(): Record<string, string> {
    const csp = [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self'",
      "img-src 'self' data:",
      "font-src 'self'",
      "connect-src 'self'",
      "object-src 'none'",
      "base-uri 'none'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      ...(this.secure ? ["upgrade-insecure-requests"] : []),
    ].join("; ");
    return {
      "content-security-policy": csp,
      "x-frame-options": "DENY",
      "cross-origin-opener-policy": "same-origin",
      "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=()",
      ...(this.secure ? { "strict-transport-security": "max-age=31536000" } : {}),
    };
  }

  private plain(res: ServerResponse, status: number, text: string): number {
    res.writeHead(status, { "content-type": "text/plain; charset=utf-8", "content-length": Buffer.byteLength(text), "cache-control": "no-store", ...this.securityHeaders() });
    res.end(text);
    return status;
  }
}

/** True when an If-None-Match header names this entity tag (or `*`). Weak tags compare equal here. */
function matchesEtag(header: string | string[] | undefined, etag: string): boolean {
  if (!header) return false;
  const value = Array.isArray(header) ? header.join(",") : header;
  return value.split(",").some((part) => {
    const tag = part.trim().replace(/^W\//, "");
    return tag === "*" || tag === etag;
  });
}
