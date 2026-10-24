// Renders the example shopping report to PDF and PNG previews with the pre-installed Chromium.
// Usage: NODE_PATH=$(npm root -g) node design/shopping-mode-v0.1/report/render.mjs
// Needs network for Google Fonts (Bricolage Grotesque, Caveat); without it the page falls back to system faces.
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const html = path.join(here, "raport-przyklad.html");
const pdf = path.join(here, "raport-przyklad.pdf");

const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto(pathToFileURL(html).href, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
const missing = await page.evaluate(() =>
  ["Bricolage Grotesque", "Caveat"].filter((f) => !document.fonts.check(`16px "${f}"`)),
);
if (missing.length) console.warn("Fonts not loaded, fallback used:", missing.join(", "));
await page.pdf({ path: pdf, format: "A4", printBackground: true, preferCSSPageSize: true });
await browser.close();

// PNG previews, one per page (poppler).
execFileSync("pdftoppm", ["-png", "-r", "110", pdf, path.join(here, "raport-strona")]);
console.log("Wrote", pdf, "and raport-strona-*.png");
