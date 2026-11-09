import assert from "node:assert/strict";
import { createServer, request, type Server } from "node:http";
import { mkdirSync, mkdtempSync, writeFileSync, utimesSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { brotliDecompressSync, gunzipSync } from "node:zlib";
import { WebStatic } from "../src/web/static.js";

// Static delivery (research item 13): conditional responses and compression for the built web app,
// on top of the existing hashed-file caching and strict headers.

const BIG_JS = `console.log(${JSON.stringify("doddy ".repeat(2000))});`;

async function start(): Promise<{ get: (path: string, headers?: Record<string, string>, method?: string) => Promise<{ status: number; headers: Record<string, string | string[] | undefined>; body: Buffer }>; dist: string; close: () => Promise<void> }> {
  const dist = mkdtempSync(join(tmpdir(), "doddy-static-"));
  mkdirSync(join(dist, "assets"));
  writeFileSync(join(dist, "index.html"), "<!doctype html><title>Doddy</title><div id=root></div>");
  writeFileSync(join(dist, "assets", "app-abc123.js"), BIG_JS);
  writeFileSync(join(dist, "assets", "logo.png"), Buffer.alloc(4000, 7));
  const pages = new WebStatic(dist, "https://app.doddy.lol");
  const server: Server = createServer((req, res) => void pages.serve(req, res, new URL(req.url ?? "/", "http://x").pathname));
  await new Promise<void>((ok) => server.listen(0, "127.0.0.1", ok));
  const port = (server.address() as AddressInfo).port;
  return {
    dist,
    get: (path, headers = {}, method = "GET") =>
      new Promise((ok, fail) => {
        const r = request({ host: "127.0.0.1", port, path, method, headers }, (res) => {
          const chunks: Buffer[] = [];
          res.on("data", (c: Buffer) => chunks.push(c));
          res.on("end", () => ok({ status: res.statusCode ?? 0, headers: res.headers, body: Buffer.concat(chunks) }));
        });
        r.on("error", fail);
        r.end();
      }),
    close: () => new Promise<void>((ok) => server.close(() => ok())),
  };
}

test("static: brotli and gzip for text files only when the client accepts them, with Vary", async () => {
  const s = await start();
  try {
    const plain = await s.get("/assets/app-abc123.js", { "accept-encoding": "identity" });
    assert.equal(plain.status, 200);
    assert.equal(plain.headers["content-encoding"], undefined);
    assert.equal(plain.body.toString(), BIG_JS);

    const br = await s.get("/assets/app-abc123.js", { "accept-encoding": "gzip, br" });
    assert.equal(br.headers["content-encoding"], "br");
    assert.equal(brotliDecompressSync(br.body).toString(), BIG_JS);
    assert.ok(br.body.length < plain.body.length / 5, `brotli ${br.body.length} vs ${plain.body.length}`);
    assert.equal(br.headers["content-length"], String(br.body.length));
    assert.match(String(br.headers.vary), /Accept-Encoding/i);

    const gz = await s.get("/assets/app-abc123.js", { "accept-encoding": "gzip" });
    assert.equal(gz.headers["content-encoding"], "gzip");
    assert.equal(gunzipSync(gz.body).toString(), BIG_JS);

    // Images are not recompressed; tiny files are not worth it.
    const png = await s.get("/assets/logo.png", { "accept-encoding": "gzip, br" });
    assert.equal(png.headers["content-encoding"], undefined);
    const page = await s.get("/", { "accept-encoding": "gzip, br" });
    assert.equal(page.headers["content-encoding"], undefined);
    assert.match(page.body.toString(), /<div id=root>/);
  } finally {
    await s.close();
  }
});

test("static: a matching If-None-Match gets 304 with the same cache and security headers, and no body", async () => {
  const s = await start();
  try {
    const first = await s.get("/");
    const etag = String(first.headers.etag);
    assert.match(etag, /^"[A-Za-z0-9_-]+"$/);
    assert.equal(first.headers["cache-control"], "no-cache");
    const again = await s.get("/", { "if-none-match": etag });
    assert.equal(again.status, 304);
    assert.equal(again.body.length, 0);
    assert.equal(again.headers["cache-control"], "no-cache");
    assert.ok(String(again.headers["content-security-policy"]).includes("default-src 'self'"));
    assert.equal((await s.get("/", { "if-none-match": `W/${etag}` })).status, 304);
    assert.equal((await s.get("/", { "if-none-match": '"other"' })).status, 200);

    const asset = await s.get("/assets/app-abc123.js");
    assert.equal(asset.headers["cache-control"], "public, max-age=31536000, immutable");
    assert.equal((await s.get("/assets/app-abc123.js", { "if-none-match": String(asset.headers.etag) })).status, 304);
  } finally {
    await s.close();
  }
});

test("static: a rebuilt file is served fresh with a new tag, not from the memory copy", async () => {
  const s = await start();
  try {
    const before = await s.get("/");
    writeFileSync(join(s.dist, "index.html"), "<!doctype html><title>Doddy 2</title><div id=root></div>");
    const future = new Date(Date.now() + 5000);
    utimesSync(join(s.dist, "index.html"), future, future);
    const after = await s.get("/");
    assert.match(after.body.toString(), /Doddy 2/);
    assert.notEqual(after.headers.etag, before.headers.etag);
    // The old tag no longer matches.
    assert.equal((await s.get("/", { "if-none-match": String(before.headers.etag) })).status, 200);
  } finally {
    await s.close();
  }
});

test("static: HEAD sends headers and length but no body; dotfiles and unknown types stay 404", async () => {
  const s = await start();
  try {
    const head = await s.get("/assets/app-abc123.js", { "accept-encoding": "identity" }, "HEAD");
    assert.equal(head.status, 200);
    assert.equal(head.body.length, 0);
    assert.equal(head.headers["content-length"], String(Buffer.byteLength(BIG_JS)));
    assert.equal((await s.get("/.env")).status, 404);
    assert.equal((await s.get("/x.exe")).status, 404);
  } finally {
    await s.close();
  }
});
