# Everyday page: mockup board (13 October 2026)

Three design concepts for a new page on the Doddy site that shows, for someone with no technical background, what Doddy does in a normal day. Nothing here is built into `site/`; this folder is the proposal the owner picks from before any page is coded.

## View it

Open `index.html` in a browser (it loads two fonts from Google Fonts, as the live site does; everything else is in this folder). For the interactive bits (cards, chips, filters, phone demo) it must be served, not opened as a file:

```sh
cd design/everyday-mockup && python3 -m http.server 8766
# open http://localhost:8766
```

## What's on the board

| Section | What it shows |
|---|---|
| 0 Navbar | The live navbar today, the proposed navbar with **Everyday** as the second link, the same navbar on the new page (link underlined in orange), and a 390 px navbar with a **Menu** button, because below 820 px the live site shows no links at all. |
| A One ordinary Tuesday (recommended) | A full page: one day told as eight moments (7:10 to 21:30). Each moment is what you say, what Doddy says, and the card Doddy puts in front of you. Tap the card to see "yes" (receipt, Doddy fist-pumps) or "no" (nothing changed). A sticky strip of times follows the scroll. Then "Three things Doddy always does", a "Try saying…" chip row with example answers, and the join panel. |
| B The fridge door | A door of handwritten scraps (things people say), filterable by At home / Out and about / At work / Family / Travelling. Tap a scrap and the exchange opens underneath. |
| C Say it, see it | One CSS phone in the middle; phrases on the left grouped by Remember / Plan / Do / Find out / Talk; "What just happened" and "What didn't" on the right. Tapping a phrase changes the phone. |
| On a phone | `previews/concept-a-390.png`, a headless-Chromium capture of concept A at 390 px, shown inside a phone frame. |
| Decisions | Six questions for the owner, with a pick marked on each, plus "what's real behind each scene" and the build plan if A is chosen. |

## Rules the mockups keep

- Every scene ends on a card the person taps. Nothing on the page shows Doddy changing something without a yes (quick list edits are the exception, shown with Undo, as in the app).
- Everything is labelled early testing: the same "iPhone app, in early testing" pill as the front page, plus fine print. No ratings, counts, logos, quotes or dates.
- The cards are drawings of the app's confirmation cards, not screenshots. Names (Ola, Marta, Olena, Kuba, Tomek) and notes are examples.
- Every scene maps to something the app's voice agent can actually propose (`voice-agent/tools.json`): calendar and birthdays, leave-by nudge, Gmail read and draft, sums and currency, parking spot, lists, translator, saved memory, weather, timers, free time, "I couldn't find that". All of it is built but not yet verified on a real iPhone, which is why the page says in testing.
- Character art: `media/doddy-*.png` are byte copies of the `WholeDoddy_*` `art@3x.png` files in `DoddyApp/Resources/Assets.xcassets`, which come from the owner's `DODDY-Numbered-Video-Assets-v01` pack (provenance in `docs/design/UPLOADED_MEMORY_ASSETS.md`). No v1.3 SVGs, no generated or redrawn art. The front page still uses the v1.3 SVGs; see decision 5 on the board.
- Colours are the site's `tokens.css` values (light only, as the site is); type is Bricolage Grotesque, Caveat for Doddy's own voice, system text for reading. No new colours or fonts.

## Checked (13 October 2026, headless Chromium 1194 via Playwright, local server)

- 1440, 390, 360 and 320 px: no horizontal scroll, no console errors, no page errors.
- Interactions by script: tapping "Remind me" on moment 1 switches the card to its receipt and the pose to the fist pump; the "Try saying…" chip for the Wi-Fi password shows "I couldn't find that in your saved memories."; the Travelling filter leaves three scraps; tapping "Translate for me" fills the door detail; tapping the Wi-Fi phrase in concept C shows the "No match" card.
- `previews/concept-a-390.png` is the first 2600 px of concept A at 390 px from that run.

Not checked: a real iPhone (fonts, Dynamic Type, touch), VoiceOver, keyboard-only walk-through, reduced motion (the page only turns off transitions), JavaScript off (cards would show their question with the buttons doing nothing, chips and filters would show but not respond; the real page should hide what needs JavaScript, as `memory.js` does on the front page).

## If concept A is chosen

New files `site/everyday/index.html`, `site/everyday.css` and `site/everyday.js`, sharing `tokens.css`, `styles.css` and `analytics.js`; the Everyday link in `site/index.html`, in the blog template in `tools/build_blog.py` and in both footers; a Menu button for phones (and a "See a day with Doddy" link in the front-page hero); the twelve pack poses copied to `site/assets/poses-pack/` with a provenance line in `site/README.md`; no inline scripts (the CSP in `vercel.json` hashes them); checks at 1440, 390 and 320 px, keyboard only, JavaScript off, under the production headers, with screenshots in `VISUAL_REVIEW/landing/`.
