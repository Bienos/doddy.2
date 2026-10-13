// Screenshots every mockup with headless Chromium (Playwright).
//   NODE_PATH=$(npm root -g) node render.mjs [--fonts <dir with local.css + woff2>] [--only 02]
// The pages link Google Fonts exactly like the live site. When --fonts points at a local
// cache (css + woff2 files, kept out of the repository), those requests are answered from it,
// so rendering works offline and no font binary is committed.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { chromium } from 'playwright';

const here = path.dirname(new URL(import.meta.url).pathname);
const root = path.resolve(here, '..'); // design/website-what-can-doddy-do
const outDir = path.join(root, 'png');
const args = process.argv.slice(2);
const fontsDir = args.includes('--fonts') ? args[args.indexOf('--fonts') + 1] : null;
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;

// Shots: file, output name, viewport, full page or not. Mobile is 390 wide, desktop 1440.
const shots = [
  ['01-homepage-nav.html', '01-homepage-nav-1440', 1440, 1180, false],
  ['01-homepage-nav.html', '01-homepage-nav-390', 390, 844, false],
  ['01-homepage-nav-mobile.html', '01-homepage-nav-390-menu', 390, 844, false],
  ['02-hero-a.html', '02-hero-a-1440', 1440, 1180, false],
  ['03-hero-b.html', '03-hero-b-1440', 1440, 1500, false],
  ['04-hero-c.html', '04-hero-c-1440', 1440, 1100, false],
  ['05-full-page.html', '05-full-page-1440', 1440, 900, true],
  ['06-scenario-selection.html', '06-scenario-selection-1440', 1440, 900, true],
  ['07-expanded-scenario.html', '07-expanded-scenario-1440', 1440, 900, true],
  ['08-character-states.html', '08-character-states-1440', 1440, 900, true],
  ['09-iphone-conversation.html', '09-iphone-conversation-1440', 1440, 900, true],
  ['05-full-page.html', '10-mobile-full-page-390', 390, 844, true],
  ['11-navigation-transitions.html', '11-navigation-transitions-1440', 1440, 900, true],
  ['12-cta-footer.html', '12-cta-footer-1440', 1440, 900, true],
  ['13-headline-options.html', '13-headline-options-1440', 1440, 900, true],
  ['14-copy-deck.html', '14-copy-deck-1440', 1440, 900, true],
  ['15-showcase-alternatives.html', '15-showcase-alternatives-1440', 1440, 900, true],
  ['02-hero-a.html', '02-hero-a-390', 390, 844, false],
  ['03-hero-b.html', '03-hero-b-390', 390, 844, false],
  ['04-hero-c.html', '04-hero-c-390', 390, 844, false],
];

const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };

const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); res.end('not found'); return;
  }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const browser = await chromium.launch();
const context = await browser.newContext({ deviceScaleFactor: 1 });
if (fontsDir) {
  await context.route('https://fonts.googleapis.com/**', (route) => route.fulfill({
    contentType: 'text/css', body: fs.readFileSync(path.join(fontsDir, 'local.css'), 'utf8'),
  }));
  await context.route('https://fonts.gstatic.com/**', (route) => {
    const name = path.basename(new URL(route.request().url()).pathname);
    const file = path.join(fontsDir, name);
    return fs.existsSync(file) ? route.fulfill({ contentType: 'font/woff2', body: fs.readFileSync(file) }) : route.abort();
  });
}
fs.mkdirSync(outDir, { recursive: true });
const errors = [];
for (const [file, out, width, height, fullPage] of shots) {
  if (only && !out.startsWith(only)) continue;
  const page = await context.newPage();
  await page.setViewportSize({ width, height });
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`${file}: ${m.text()}`); });
  page.on('pageerror', (e) => errors.push(`${file}: ${e.message}`));
  await page.goto(`http://127.0.0.1:${port}/mockups/${file}`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(400);
  const families = await page.evaluate(() => [...new Set([...document.fonts].filter((f) => f.status === 'loaded').map((f) => f.family.replace(/"/g, '')))]);
  for (const need of ['Bricolage Grotesque', 'Caveat']) if (!families.includes(need)) errors.push(`${file}: font not loaded: ${need}`);
  const scroll = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
  if (scroll) errors.push(`${file} @${width}: horizontal scroll`);
  await page.screenshot({ path: path.join(outDir, `${out}.png`), fullPage });
  console.log('rendered', out);
  await page.close();
}
await browser.close();
server.close();
if (errors.length) { console.log('\nISSUES:'); errors.forEach((e) => console.log(' -', e)); }
