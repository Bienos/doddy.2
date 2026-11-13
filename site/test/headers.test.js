import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// The response headers vercel.json gives each path (ADR-714). Vercel turns every rule into its own route
// and applies all that match, so the rules must not overlap on the Content-Security-Policy: the admin page
// would otherwise be served under the public site's policy, which allows Google Tag Manager.
const config = JSON.parse(readFileSync(new URL("../vercel.json", import.meta.url), "utf8"));
const rules = config.headers;

// Vercel reads a `source` as a path pattern. The ones in this file are written so that a plain regular
// expression reads them the same way (checked against Vercel's own converter, @vercel/routing-utils,
// when they were written); that is the only syntax to use here.
const rulesFor = (path) => rules.filter((rule) => new RegExp(`^${rule.source}$`).test(path));
const withCsp = (path) => rulesFor(path).filter((rule) => rule.headers.some((h) => h.key === "Content-Security-Policy"));
const headersFor = (path) => Object.fromEntries(rulesFor(path).flatMap((rule) => rule.headers.map((h) => [h.key, h.value])));

// The public site's headers exactly as they were before the admin page got its own (copied, not read
// from vercel.json, so that changing them has to change this test too).
const SITE_HEADERS = {
  "Content-Security-Policy": "default-src 'self'; script-src 'self' https://www.googletagmanager.com 'sha256-Du+OJKJSbdUgz5nrHeWWINvez6XKDDU/tyj/5c2uvwo=' 'sha256-c8jFACcp7aC/kl5F73u8SoW30LTdH+lrpBp0IpSz97I='; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data: https://*.google-analytics.com https://*.googletagmanager.com; connect-src 'self' https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
};
const PUBLIC_PATHS = [
  "/", "/index.html", "/fr/", "/de/index.html", "/zh-hans/", "/pt-br/", "/privacy/", "/terms/", "/blog/", "/blog/hello-doddy/",
  "/what-can-doddy-do/", "/sitemap.xml", "/styles.css", "/api/waitlist", "/api/waitlist-answers", "/api/waitlist-admin", "/api/waitlist-export",
  "/assets/day/poses/wave.webp",
];
const ADMIN_PATHS = ["/admin", "/admin/", "/admin/index.html", "/admin/admin.js", "/admin/admin.css", "/admin/anything/else"];

test("every public path keeps exactly the headers it had, with one Content-Security-Policy", () => {
  for (const path of PUBLIC_PATHS) {
    assert.equal(withCsp(path).length, 1, `${path}: exactly one rule sets the policy`);
    const headers = headersFor(path);
    for (const [key, value] of Object.entries(SITE_HEADERS)) assert.equal(headers[key], value, `${path}: ${key}`);
    const extra = [...(path.startsWith("/api/") ? [] : ["Access-Control-Allow-Origin"]), ...(path.startsWith("/assets/") ? ["Cache-Control"] : [])];
    assert.deepEqual(Object.keys(headers).filter((key) => !(key in SITE_HEADERS)).sort(), extra.sort(), `${path}: nothing else`);
  }
  assert.equal(headersFor("/assets/day/poses/x.webp")["Cache-Control"], "public, max-age=86400");
});

// Vercel serves static files with "Access-Control-Allow-Origin: *" unless a rule names the header (a rule's
// value replaces Vercel's own, as the /assets/ Cache-Control rule does). Pages, scripts, styles and images are
// for this site only; the API routes add no CORS header and are called from this site's own pages.
test("the site's files name the site itself as the only origin that may read them; the API routes allow none", () => {
  for (const path of [...PUBLIC_PATHS, ...ADMIN_PATHS, "/_vercel/insights/script.js", "/blog/feed.xml", "/i18n/de.js"]) {
    const values = rulesFor(path).flatMap((rule) => rule.headers).filter((h) => h.key.toLowerCase() === "access-control-allow-origin");
    if (path.startsWith("/api/")) {
      assert.deepEqual(values, [], `${path}: no CORS header`);
    } else {
      assert.deepEqual(values.map((h) => h.value), ["https://www.doddy.lol"], `${path}: exactly one, never *`);
    }
  }
  for (const rule of rules) {
    for (const h of rule.headers) assert.ok(!(h.key.toLowerCase().startsWith("access-control-") && h.value.includes("*")), `${rule.source}: no wildcard`);
  }
});

test("the admin page has its own policy: no Google Tag Manager, no inline script, nothing it does not need", () => {
  for (const path of ADMIN_PATHS) {
    const matching = withCsp(path);
    assert.equal(matching.length, 1, `${path}: exactly one rule sets the policy, so the public one can't also apply`);
    const headers = headersFor(path);
    const csp = headers["Content-Security-Policy"];
    assert.notEqual(csp, SITE_HEADERS["Content-Security-Policy"], path);
    for (const forbidden of ["googletagmanager", "google-analytics", "analytics.google", "unsafe-inline", "unsafe-eval", "sha256-", "nonce-", "data:", "blob:", "*"]) {
      assert.ok(!csp.includes(forbidden), `${path}: the policy has no ${forbidden}`);
    }
    const directives = Object.fromEntries(csp.split(";").map((part) => part.trim().split(/\s+/)).map(([name, ...sources]) => [name, sources.join(" ")]));
    assert.deepEqual(directives, {
      "default-src": "'none'",
      "script-src": "'self'",
      "style-src": "'self' https://fonts.googleapis.com",
      "font-src": "https://fonts.gstatic.com",
      "img-src": "'self'",
      "connect-src": "'self'",
      "frame-ancestors": "'none'",
      "base-uri": "'none'",
      "form-action": "'none'",
    }, path);
    // What the public rule used to add around it is still there, plus what only this page had.
    for (const key of ["X-Content-Type-Options", "Referrer-Policy", "Permissions-Policy"]) assert.equal(headers[key], SITE_HEADERS[key], `${path}: ${key}`);
    assert.equal(headers["X-Robots-Tag"], "noindex, nofollow", path);
    assert.equal(headers["Cache-Control"], "no-store", path);
  }
});

test("the admin page needs nothing its policy does not give it", () => {
  const html = readFileSync(new URL("../admin/index.html", import.meta.url), "utf8");
  // No inline script, style or event handler: the policy would block them, and so it should.
  const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  assert.ok(scripts.length > 0);
  for (const [, attributes, body] of scripts) {
    assert.match(attributes, /\bsrc="[^"]+"/, "every script is a file");
    assert.equal(body.trim(), "", "no inline script text");
  }
  assert.ok(!/<style\b/i.test(html), "no <style> element");
  assert.ok(!/\sstyle\s*=/i.test(html), "no style attribute");
  assert.ok(!/\son[a-z]+\s*=/i.test(html), "no inline event handler");
  assert.ok(!/javascript:/i.test(html));
  // The only other sites the page talks to are the two the policy names.
  const hosts = new Set([...html.matchAll(/(?:href|src)="(https?:)?\/\/([^/"]+)/g)].map((match) => match[2]));
  assert.deepEqual([...hosts].sort(), ["fonts.googleapis.com", "fonts.gstatic.com"]);
  // Scripts load from this site; the page's script reaches only this site's own API.
  assert.ok(![...scripts].some(([, attributes]) => /\bsrc="(https?:)?\/\//.test(attributes)));
  const script = readFileSync(new URL("../admin/admin.js", import.meta.url), "utf8");
  assert.ok(!/\b(eval|new Function)\s*\(/.test(script));
  assert.ok(!/fetch\(\s*["'`]https?:/.test(script));
});
