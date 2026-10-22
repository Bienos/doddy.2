import { readFile, stat } from "node:fs/promises";
import type { IncomingMessage, ServerResponse } from "node:http";
import { extname, join, normalize, resolve, sep } from "node:path";

/**
 * Serves the built web app (`web/dist`, ADR-579) from this server, so the app, its API and its
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
    let body: Buffer;
    try {
      const info = await stat(file);
      if (!info.isFile()) return this.plain(res, 404, "Not found.");
      body = await readFile(file);
    } catch {
      return isPage
        ? this.plain(res, 503, "Doddy's web app isn't built on this server yet.")
        : this.plain(res, 404, "Not found.");
    }
    // Hashed build files never change; the page itself is always fetched fresh.
    const immutable = relative.startsWith(`assets${sep}`) || relative.startsWith("assets/");
    res.writeHead(200, {
      "content-type": type,
      "content-length": body.length,
      "cache-control": immutable ? "public, max-age=31536000, immutable" : "no-cache",
      ...this.securityHeaders(),
    });
    res.end(req.method === "HEAD" ? undefined : body);
    return 200;
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
