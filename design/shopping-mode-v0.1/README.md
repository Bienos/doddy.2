# Doddy na zakupach (shopping mode): design study v0.1

Date: 24 Oct 2026. Status: **proposal, not built.** Owner's brief (24 Oct, in Polish): a shopping mode where Doddy finds any item, looks for the cheapest option, reads grocery leaflets (Biedronka and others), makes a short report as a PDF in Doddy's style with a cheap model, lets the user say what matters most, and later lets people pay inside the app with Apple Pay or BLIK. Keep it simple. The written proposal, sources and decisions are in `docs/strategy/TRYB_ZAKUPOW_2026-10.md`.

Open `index.html` in a browser. It is one page; the only network request is Google Fonts (Bricolage Grotesque and Caveat, both already the site's faces). No font files are committed.

## What it shows

1. **Gazetki** (leaflets): asking on Home; the cheapest price this week with its conditions (store app, limit, end date); the basket as one shop or two, summed by code.
2. **Znajdź mi to** (find me this): one question about priorities and one hand-over card (the existing errand flow, ADR-570); the search in the background on the Lock Screen; three picks with the time each price was checked.
3. **Kup i pilnuj** (buy and watch): stage 1 hand-off to the shop's own checkout; stage 2 price-drop alert; stage 3 in-app Apple Pay or BLIK with a shop that supports agent checkout, with the confirmed and unknown outcomes.
4. **Raport PDF**: `report/raport-przyklad.pdf`, two A4 pages, rendered from `report/raport-przyklad.html` by `report/render.mjs` (Chromium). In the app the same layout would be drawn on the iPhone from the validated result, not by a model.

## What it does not prove

Everything is fictional. **Every price, shop result, order and notification is invented for the mockup** and marked as an example. Nothing searches, reads a leaflet, opens a shop, takes a payment or sends a notification. The Lock Screen and the Apple Pay button are illustrations; the real app must use Apple's own Apple Pay button and never draw a copy of a system sheet. Shop names appear as plain text only (no logos or brand colours).

## Character art

Poses are copies of the app's imported `WholeDoddy_*` image sets (`@3x`, 300 × 450), which come from the owner's `DODDY-Numbered-Video-Assets-v01` pack (provenance and hashes of the originals in `docs/design/UPLOADED_MEMORY_ASSETS.md`). Nothing was redrawn or recoloured. `img/wordmark.svg` is `web/public/brand/wordmark.svg` (ADR-562).

| File | Copied from | SHA-256 of the copy |
| --- | --- | --- |
| `img/kneeling_inspect.png` | `WholeDoddy_kneeling_inspect.imageset/art@3x.png` | `007d3db1de61efe88db9b3f401d5fd0251ac9c410ad502473b27f7a1f258dbae` |
| `img/listening.png` | `WholeDoddy_listening.imageset/art@3x.png` | `69ac3b1ab13beb758d9f196cfebc71cbdcfb640b3b3b69cff0e7fa6e1221a482` |
| `img/fistpump.png` | `WholeDoddy_fistpump.imageset/art@3x.png` | `5f72b3172143bad89b8f10f88784558e7a7ed1e9628284e62424bb624aea57b6` |
| `img/shrug.png` | `WholeDoddy_shrug.imageset/art@3x.png` | `bbc0211254e217f40b27c8545c3a4a699afb9b97a94da36f21164066e8c1763b` |
| `img/belly_reading.png` | `WholeDoddy_belly_reading.imageset/art@3x.png` | `27de5729455d657451304985802b66d9afb7b253ce3016bd346c902a8622cfa6` |
| `img/reaching_high.png` | `WholeDoddy_reaching_high.imageset/art@3x.png` | `a9471c78c18abd85852a5427330e8f8e2d1c00f77e9d3b07cdac824145fdd288` |

## Checked

Headless Chromium (Playwright 1.63), 24 Oct 2026: the page at 1280 px (light) and 390 px (dark): no horizontal scroll, no request or console errors, no phone screen whose content overflows. The report renders to two A4 pages with both web fonts loaded. This is a scripted browser check, not an accessibility audit or a device test.
