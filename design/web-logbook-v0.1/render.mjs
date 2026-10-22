// Screenshots the Logbook mockup with headless Chromium (Playwright) and checks each state.
//   NODE_PATH=$(npm root -g) node design/web-logbook-v0.1/render.mjs
// Serves the repository root on a local port so ../../site/ paths resolve as they would on
// the site. Prints, for every shot: horizontal overflow, console errors and failed requests.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(new URL(import.meta.url).pathname);
const repo = path.resolve(here, "..", "..");
// --out <dir> writes the shots somewhere else (for a quick look without touching png/).
const outArg = process.argv.indexOf("--out");
const outDir = outArg > -1 ? path.resolve(process.argv[outArg + 1]) : path.join(here, "png");
fs.mkdirSync(outDir, { recursive: true });

const types = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".webp": "image/webp", ".png": "image/png", ".svg": "image/svg+xml" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file = path.join(repo, url);
  if (!file.startsWith(repo)) { res.writeHead(403).end(); return; }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
  if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}/design/web-logbook-v0.1/index.html`;

// [hash, output name, width, height, full page]
const shots = [
  ["glance", "01-at-a-glance-1440", 1440, 900, true],
  ["glance", "01-at-a-glance-390", 390, 844, true],
  ["closer", "02-closer-look-1440", 1440, 900, true],
  ["closer", "02-closer-look-390", 390, 844, true],
  ["signin", "03-sign-in-1440", 1440, 900, false],
  ["signin", "03-sign-in-390", 390, 844, true],
  ["closer-paid", "04-closer-look-paid-later-1440", 1440, 900, false],
  ["glance-sources", "05-where-numbers-come-from-1440", 1440, 900, true],
  ["closer-tables-d7", "06-closer-look-tables-1440", 1440, 900, true]
];

// The page itself comes from the local server. Google Fonts are fetched with curl, which uses
// the environment's proxy and CA settings, and cached for the run.
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const fontCache = new Map();
async function fonts(route) {
  const req = route.request();
  const url = req.url();
  try {
    if (!fontCache.has(url)) {
      const body = execFileSync("curl", ["-sSfL", "--max-time", "20", "-A", req.headers()["user-agent"] || "Mozilla/5.0", url], { maxBuffer: 8 << 20 });
      fontCache.set(url, body);
    }
    const type = url.includes("fonts.googleapis.com") ? "text/css; charset=utf-8" : "font/woff2";
    await route.fulfill({ status: 200, body: fontCache.get(url), headers: { "content-type": type, "access-control-allow-origin": "*" } });
  } catch {
    await route.abort();
  }
}
let problems = 0;
for (const [hash, name, width, height, full] of shots) {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: width < 600 ? 2 : 1 });
  await page.route(/fonts\.(googleapis|gstatic)\.com/, fonts);
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("requestfailed", (r) => errors.push("failed " + r.url()));
  page.on("response", (r) => { if (r.status() >= 400) errors.push(r.status() + " " + r.url()); });
  await page.goto(`${base}#${hash}`, { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  const info = await page.evaluate(() => ({
    overflow: document.documentElement.scrollWidth - window.innerWidth,
    fonts: [...document.fonts].filter((f) => f.status === "loaded").map((f) => f.family).filter((v, i, a) => a.indexOf(v) === i)
  }));
  await page.screenshot({ path: path.join(outDir, name + ".png"), fullPage: full });
  const bad = info.overflow > 0 || errors.length;
  if (bad) problems += 1;
  console.log(`${bad ? "CHECK" : "ok   "} ${name}  overflow=${info.overflow}px  fonts=${info.fonts.join("/") || "none"}${errors.length ? "\n      " + errors.join("\n      ") : ""}`);
  await page.close();
}
await browser.close();
server.close();
console.log(problems ? `${problems} shot(s) need a look` : "all shots clean");
