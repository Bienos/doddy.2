// Screenshots one element of a mockup page, with padding, for before/after pairs.
//   FONTS=<dir> node tools/crop.mjs <page under mockups/> <css selector> <out.png> [pad=24] [width=1440]
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { chromium } from 'playwright';

const [file, selector, out, padArg = '24', widthArg = '1440'] = process.argv.slice(2);
const pad = Number(padArg); const width = Number(widthArg);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
const fontsDir = process.env.FONTS;
const types = { '.html': 'text/html', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  const f = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!f.startsWith(root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch();
const context = await browser.newContext({ deviceScaleFactor: 1 });
if (fontsDir) {
  await context.route('https://fonts.googleapis.com/**', (route) => route.fulfill({ contentType: 'text/css', body: fs.readFileSync(path.join(fontsDir, 'local.css'), 'utf8') }));
  await context.route('https://fonts.gstatic.com/**', (route) => { const f = path.join(fontsDir, path.basename(new URL(route.request().url()).pathname)); return fs.existsSync(f) ? route.fulfill({ contentType: 'font/woff2', body: fs.readFileSync(f) }) : route.abort(); });
}
const page = await context.newPage();
await page.setViewportSize({ width, height: 900 });
await page.goto(`http://127.0.0.1:${server.address().port}/mockups/${file}`, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
const el = page.locator(selector).first();
await el.scrollIntoViewIfNeeded();
await page.waitForTimeout(300);
const box = await el.evaluate((e) => { const r = e.getBoundingClientRect(); return { x: r.x + scrollX, y: r.y + scrollY, w: r.width, h: r.height }; });
const clip = { x: Math.max(0, box.x - pad), y: Math.max(0, box.y - pad), width: Math.min(width, box.w + 2 * pad), height: box.h + 2 * pad };
fs.mkdirSync(path.dirname(out), { recursive: true });
await page.screenshot({ path: out, fullPage: true, clip });
console.log('cropped', out, Math.round(clip.width), 'x', Math.round(clip.height));
await browser.close(); server.close();
