// In-memory stand-in for the parts of @vercel/blob the waitlist functions use. Mirrors 2.8.0's documented
// behaviour: get() returns null for a missing blob, head() throws BlobNotFoundError, put() refuses to
// overwrite unless allowOverwrite, and ifMatch throws BlobPreconditionFailedError on a different etag
// or a missing blob (the real service is not called; that last case is assumed, not checked against it).
import { mock } from "node:test";

export class BlobError extends Error {}
export class BlobNotFoundError extends BlobError {}
export class BlobPreconditionFailedError extends BlobError {}

export const store = new Map();  // pathname -> { body, etag, uploadedAt? }
// Set by a test: beforePut to change the store between a read and put(), beforeGet to make reads fail.
export const hooks = { beforePut: null, beforeGet: null };
let version = 0;

export const blob = {
  BlobError,
  BlobNotFoundError,
  BlobPreconditionFailedError,
  async get(pathname) {
    await hooks.beforeGet?.(pathname);
    const entry = store.get(pathname);
    if (!entry) return null;
    return { statusCode: 200, stream: new Response(entry.body).body, blob: { pathname, etag: entry.etag } };
  },
  async head(pathname) {
    const entry = store.get(pathname);
    if (!entry) throw new BlobNotFoundError();
    return { pathname, etag: entry.etag };
  },
  async put(pathname, body, options = {}) {
    await hooks.beforePut?.(pathname);
    const entry = store.get(pathname);
    if (options.ifMatch !== undefined) {
      if (!entry || entry.etag !== options.ifMatch) throw new BlobPreconditionFailedError();
    } else if (entry && !options.allowOverwrite) {
      throw new BlobError("This blob already exists");
    }
    const etag = `"v${++version}"`;
    // Every put is a new upload, as on the real service (list() reports when each blob was last written).
    store.set(pathname, { body, etag, uploadedAt: new Date() });
    return { pathname, etag };
  },
  async del(pathnames) {
    for (const pathname of [pathnames].flat()) store.delete(pathname);
  },
  async list({ prefix = "" } = {}) {
    const blobs = [...store.entries()]
      .filter(([p]) => p.startsWith(prefix))
      .map(([pathname, entry]) => ({ pathname, uploadedAt: entry.uploadedAt ?? new Date() }));
    return { blobs, cursor: undefined, hasMore: false };
  },
};

mock.module("@vercel/blob", { namedExports: blob });

export function reset() {
  store.clear();
  hooks.beforePut = null;
  hooks.beforeGet = null;
}

// A request as the browser would send it from this site.
export function post(url, body, headers = {}) {
  return new Request(`https://doddy.test${url}`, {
    method: "POST",
    headers: { host: "doddy.test", origin: "https://doddy.test", "content-type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

export const basic = (password) => `Basic ${Buffer.from(`admin:${password}`).toString("base64")}`;
