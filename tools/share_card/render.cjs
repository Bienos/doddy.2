// Renders big_brain.html to a 1200 x 630 PNG (ADR-444). Needs Playwright with Chromium and network
// access to Google Fonts (the card uses the site's fonts; none are stored in the repository).
//
//     node tools/share_card/render.cjs <output.png>
const path = require("path");
const { chromium } = require("playwright");

async function main(out) {
  if (!out) throw new Error("usage: node tools/share_card/render.cjs <output.png>");
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
    await page.goto("file://" + path.join(__dirname, "big_brain.html"));
    await page.evaluate(() => document.fonts.ready);
    const missing = await page.evaluate(() =>
      ["700 40px Caveat", "600 40px Caveat", "800 40px 'Bricolage Grotesque'"].filter((f) => !document.fonts.check(f)));
    if (missing.length) throw new Error("fonts did not load: " + missing.join(", "));
    const art = await page.$eval("img.art", (img) => img.complete && img.naturalWidth > 0);
    if (!art) throw new Error("the ShareDoddy_big_brain art did not load");
    await page.screenshot({ path: out });
  } finally {
    await browser.close();
  }
}

main(process.argv[2]).catch((error) => {
  console.error(error.message);
  process.exit(1);
});
