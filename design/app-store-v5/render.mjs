// Renders the six App Store frames and review pictures with headless Chromium (Playwright).
//   node design/app-store-v5/render.mjs                 → shots/s1..s6.png (1290 × 2796), shots/web/*.jpg, DODDY_Prezentacja_v5.pdf
//   node design/app-store-v5/render.mjs --review <dir>  → also whole-page and per-step pictures in <dir>
// Serves this folder on a local port. Google Fonts load through the session's proxy when HTTPS_PROXY is set.
// Prints, for every page: horizontal overflow, console errors, failed requests and whether the fonts loaded.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(new URL(import.meta.url).pathname);
const reviewArg = process.argv.indexOf("--review");
const reviewDir = reviewArg > -1 ? path.resolve(process.argv[reviewArg + 1]) : null;
const shotsDir = path.join(here, "shots");
fs.mkdirSync(path.join(shotsDir, "web"), { recursive: true });
if (reviewDir) fs.mkdirSync(reviewDir, { recursive: true });

const types = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file = path.join(here, url);
  if (!file.startsWith(here)) { res.writeHead(403).end(); return; }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
  if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}/index.html`;

const launch = { };
if (process.env.HTTPS_PROXY) launch.proxy = { server: process.env.HTTPS_PROXY, bypass: "127.0.0.1,localhost" };
const browser = await chromium.launch(launch);

async function open(url, opts) {
  const ctx = await browser.newContext(opts);
  const page = await ctx.newPage();
  const problems = [];
  page.on("console", (m) => { if (m.type() === "error") problems.push("console: " + m.text()); });
  page.on("pageerror", (e) => problems.push("error: " + e.message));
  page.on("requestfailed", (r) => problems.push("failed: " + r.url() + " " + (r.failure() && r.failure().errorText)));
  await page.goto(url, { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);
  const fonts = await page.evaluate(() => ({
    display: document.fonts.check('800 40px "Bricolage Grotesque"'),
    body: document.fonts.check('500 16px "Inter"'),
    hand: document.fonts.check('500 24px "Caveat"'),
  }));
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  return { ctx, page, problems, fonts, overflow };
}
function report(name, r) {
  console.log(`${name}: overflow ${r.overflow}px, fonts ${JSON.stringify(r.fonts)}${r.problems.length ? "\n  " + r.problems.join("\n  ") : ""}`);
}

// 1. The App Store frames, one per scene.
for (const id of ["s1", "s2", "s3", "s4", "s5", "s6"]) {
  for (const [scale, out, type] of [[3, path.join(shotsDir, id + ".png"), "png"], [1.5, path.join(shotsDir, "web", id + ".jpg"), "jpeg"]]) {
    const r = await open(`${base}?shot=${id}`, { viewport: { width: 430, height: 932 }, deviceScaleFactor: scale });
    await r.page.waitForTimeout(300);
    await r.page.screenshot({ path: out, type, quality: type === "jpeg" ? 86 : undefined });
    if (scale === 3) report("shot " + id, r);
    await r.ctx.close();
  }
}

// 2. The PDF version (deck.html, A4 landscape), built from the frames above.
{
  const r = await open(base.replace("index.html", "deck.html"), { viewport: { width: 1123, height: 794 } });
  await r.page.waitForTimeout(300);
  await r.page.pdf({ path: path.join(here, "DODDY_Prezentacja_v5.pdf"), width: "297mm", height: "210mm", printBackground: true, preferCSSPageSize: true });
  report("deck", r);
  if (reviewDir) {
    const n = await r.page.locator(".pg").count();
    for (let i = 0; i < n; i++) await r.page.locator(".pg").nth(i).screenshot({ path: path.join(reviewDir, `deck-${i + 1}.png`) });
  }
  await r.ctx.close();
}

// 3. Review pictures: the whole page at rest (reduced motion shows every scene's last step), and every step.
if (reviewDir) {
  for (const [w, h, dsf] of [[1440, 900, 1], [390, 844, 2]]) {
    const r = await open(base, { viewport: { width: w, height: h }, deviceScaleFactor: dsf, reducedMotion: "reduce" });
    await r.page.waitForTimeout(400);
    await r.page.screenshot({ path: path.join(reviewDir, `page-${w}.png`), fullPage: true });
    report("page " + w, r);
    await r.ctx.close();
  }
  const r = await open(base, { viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1, reducedMotion: "reduce" });
  const counts = await r.page.evaluate(() => window.DoddyStory.SCENES.map((s) => s.steps.length));
  for (let si = 0; si < counts.length; si++) {
    for (let st = 0; st < counts[si]; st++) {
      await r.page.evaluate(([a, b]) => { const p = window.DoddyStory.players[a]; p.show(b, false); }, [si, st]);
      await r.page.waitForTimeout(120);
      const stage = r.page.locator(".stage").nth(si);
      await stage.screenshot({ path: path.join(reviewDir, `step-s${si + 1}-${String(st).padStart(2, "0")}.png`) });
    }
  }
  report("steps", r);
  await r.ctx.close();
}

await browser.close();
server.close();
