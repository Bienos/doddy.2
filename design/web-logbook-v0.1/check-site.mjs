// Checks the live-site version of Logbook (site/logbook/) and the nav it added to every page, in headless
// Chromium under the production headers from site/vercel.json (CSP included).
//   NODE_PATH=$(npm root -g) node design/web-logbook-v0.1/check-site.mjs [--out <dir>]
// With --out, it also saves screenshots there. Exits 1 if any check fails.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(new URL(import.meta.url).pathname);
// --site <dir> checks another copy of site/ (for example main's, to compare).
const siteArg = process.argv.indexOf("--site");
const site = siteArg > -1 ? path.resolve(process.argv[siteArg + 1]) : path.resolve(here, "..", "..", "site");
const outArg = process.argv.indexOf("--out");
const outDir = outArg > -1 ? path.resolve(process.argv[outArg + 1]) : null;
if (outDir) fs.mkdirSync(outDir, { recursive: true });

// Serve site/ with the headers vercel.json gives each path.
const vercel = JSON.parse(fs.readFileSync(path.join(site, "vercel.json"), "utf8"));
const rules = vercel.headers.map((r) => ({ re: new RegExp("^" + r.source.replace(/\(\.\*\)/g, "(.*)") + "$"), headers: r.headers }));
const types = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".webp": "image/webp", ".png": "image/png", ".svg": "image/svg+xml", ".json": "application/json", ".xml": "application/xml", ".mp4": "video/mp4", ".jpg": "image/jpeg" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file = path.join(site, url);
  if (!file.startsWith(site)) { res.writeHead(403).end(); return; }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
  const headers = { "content-type": types[path.extname(file)] || "application/octet-stream" };
  for (const r of rules) if (r.re.test(url)) for (const h of r.headers) headers[h.key] = h.value;
  if (!fs.existsSync(file)) { res.writeHead(404, headers).end(); return; }
  res.writeHead(200, headers);
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const fontCache = new Map();
async function fonts(route) {
  const req = route.request(), url = req.url();
  try {
    if (!fontCache.has(url)) fontCache.set(url, execFileSync("curl", ["-sSfL", "--max-time", "20", "-A", req.headers()["user-agent"] || "Mozilla/5.0", url], { maxBuffer: 8 << 20 }));
    await route.fulfill({ status: 200, body: fontCache.get(url), headers: { "content-type": url.includes("googleapis") ? "text/css; charset=utf-8" : "font/woff2", "access-control-allow-origin": "*" } });
  } catch { await route.abort(); }
}

let failures = 0;
function report(ok, name, detail) {
  if (!ok) failures += 1;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? "  " + detail : ""}`);
}

async function open(url, width, height) {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: width < 600 ? 2 : 1 });
  await page.route(/fonts\.(googleapis|gstatic)\.com/, fonts);
  // Vercel's insights script only exists on Vercel; answer it with an empty script like the deploy would.
  await page.route(/\/_vercel\/insights\/script\.js/, (r) => r.fulfill({ status: 200, body: "", headers: { "content-type": "text/javascript" } }));
  await page.route(/googletagmanager\.com|google-analytics\.com/, (r) => r.fulfill({ status: 200, body: "", headers: { "content-type": "text/javascript" } }));
  const problems = [];
  page.on("console", (m) => { if (m.type() === "error") problems.push(m.text()); });
  page.on("pageerror", (e) => problems.push(String(e)));
  page.on("response", (r) => { if (r.status() >= 400) problems.push(r.status() + " " + r.url()); });
  await page.addInitScript(() => {
    window.__csp = [];
    document.addEventListener("securitypolicyviolation", (e) => window.__csp.push(e.violatedDirective + " " + (e.blockedURI || "inline")));
  });
  await page.goto(base + url, { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(250);
  return { page, problems };
}

async function pageChecks(page, problems, label) {
  const info = await page.evaluate(() => ({
    overflow: document.documentElement.scrollWidth - window.innerWidth,
    csp: window.__csp,
    noStyleAttr: document.querySelectorAll("[style]").length,
    brokenImages: [...document.images].filter((i) => i.complete && i.naturalWidth === 0 && i.loading !== "lazy").map((i) => i.src)
  }));
  report(info.overflow <= 0, `${label}: no sideways scroll`, info.overflow > 0 ? `${info.overflow}px` : "");
  report(info.csp.length === 0, `${label}: no CSP violations`, info.csp.join("; "));
  report(problems.length === 0, `${label}: no console errors or failed requests`, problems.join("; "));
  report(info.brokenImages.length === 0, `${label}: no broken images`, info.brokenImages.join(" "));
}

// 1. The Logbook page.
for (const [w, h] of [[1440, 900], [1024, 800], [390, 844], [320, 640]]) {
  const { page, problems } = await open("/logbook/", w, h);
  await pageChecks(page, problems, `/logbook/ ${w}px`);
  const state = await page.evaluate(() => ({
    current: document.querySelector('.nav a[aria-current="page"]')?.getAttribute("href"),
    receiptLines: document.querySelectorAll("#lb-rc-lines .lb-rc-line").length,
    bars: document.querySelectorAll("#lb-uses .lb-hrow").length,
    dots: document.querySelectorAll("#lb-when circle").length,
    banner: document.querySelector(".lb-banner")?.textContent.trim(),
    robots: document.querySelector('meta[name="robots"]')?.content,
    analytics: [...document.scripts].some((s) => /analytics|insights|googletagmanager/.test(s.src))
  }));
  report(state.current === "/logbook/", `/logbook/ ${w}px: nav marks Logbook as the current page`);
  report(state.receiptLines === 13 && state.bars === 7 && state.dots > 0, `/logbook/ ${w}px: receipt, bars and dots drawn`, JSON.stringify({ r: state.receiptLines, b: state.bars, d: state.dots }));
  report(/^Example\./.test(state.banner || ""), `/logbook/ ${w}px: example banner shown`);
  report(state.robots === "noindex, nofollow" && !state.analytics, `/logbook/ ${w}px: noindex and no analytics scripts`);
  if (outDir) await page.screenshot({ path: path.join(outDir, `site-logbook-${w}.png`), fullPage: true });

  if (w === 1440 || w === 390) {
    // Closer look, its controls, the table view, the week arrows, the two-tap delete and a demo button.
    await page.click("#lb-tab-closer");
    await page.waitForTimeout(150);
    const closer = await page.evaluate(() => ({ kpis: document.querySelectorAll("#lb-kpis .lb-kpi").length, rows: document.querySelectorAll("#lb-tools tbody tr").length, cells: document.querySelectorAll("#lb-heat rect.lb-cell").length }));
    report(closer.kpis === 5 && closer.rows > 10 && closer.cells === 168, `/logbook/ ${w}px: Closer look drawn`, JSON.stringify(closer));
    for (const r of ["7", "90", "30"]) await page.click(`[data-lb-range="${r}"]`);
    await page.click("#lb-tools th:nth-child(1) button");
    await page.check("#lb-as-tables");
    const tables = await page.evaluate(() => ({ shown: [...document.querySelectorAll(".lb-tview")].filter((t) => t.offsetParent !== null).length }));
    report(tables.shown >= 6, `/logbook/ ${w}px: table view shows tables`, JSON.stringify(tables));
    if (outDir) await page.screenshot({ path: path.join(outDir, `site-logbook-closer-${w}.png`), fullPage: true });
    await page.uncheck("#lb-as-tables");
    await page.click("#lb-tab-glance");
    await page.click("#lb-wk-prev");
    await page.click("#lb-wk-next");
    await page.click("#lb-delete");
    const armed = await page.textContent("#lb-delete");
    await page.click("#lb-delete");
    const toast = await page.textContent("#lb-toast");
    report(/Tap again/.test(armed) && /Deleting is always free/.test(toast), `/logbook/ ${w}px: two-tap delete explains itself`);
    await pageChecks(page, problems, `/logbook/ ${w}px after clicking around`);
  }
  await page.close();
}

// 2. The nav on the other pages: Logbook is there and the desktop nav still fits on one line.
for (const url of ["/", "/de/", "/fr/", "/pl/", "/what-can-doddy-do/", "/de/what-can-doddy-do/", "/blog/"]) {
  for (const w of [820, 900, 1024, 1280, 390]) {
    const { page, problems } = await open(url, w, 800);
    const nav = await page.evaluate(() => {
      const inner = document.querySelector(".nav-inner");
      const links = [...document.querySelectorAll(".nav-links li")].filter((li) => li.offsetParent !== null);
      const tops = new Set(links.map((li) => Math.round(li.getBoundingClientRect().top)));
      const logbook = [...document.querySelectorAll(".nav a, .menu-sheet a")].filter((a) => a.getAttribute("href") === "/logbook/");
      return { height: Math.round(document.querySelector(".nav").getBoundingClientRect().height), oneLine: tops.size <= 1, fits: inner.scrollWidth <= inner.clientWidth + 1, logbookLinks: logbook.length, label: logbook[0]?.textContent.trim() };
    });
    // On phones the translated "Join early access" button can wrap the header to a second row (it did before Logbook too).
    report(nav.logbookLinks >= 2 && nav.oneLine && nav.fits && (w < 820 || nav.height <= 80), `${url} ${w}px: nav has "${nav.label}" and fits`, JSON.stringify(nav));
    if (w === 1024) await pageChecks(page, problems, `${url} ${w}px`);
    if (outDir && (w === 820 || w === 1024) && ["/", "/de/", "/pl/"].includes(url)) {
      await page.screenshot({ path: path.join(outDir, `nav${url.replace(/\//g, "_")}${w}.png`), clip: { x: 0, y: 0, width: w, height: 90 } });
    }
    await page.close();
  }
}

await browser.close();
server.close();
console.log(failures ? `${failures} check(s) failed` : "all checks passed");
process.exit(failures ? 1 : 0);
