# One design direction: remove what is left of the old designs, then redesign in order

- **Date:** 2026-11-09
- **Decided by:** owner, 9 Nov 2026: "ok recommended", to the design inventory and its recommendations (scope, colours, the opening, the site and the removal list R1 to R9)
- **Status:** accepted. The removals (R1 to R9) are applied in the pull request from `claude/gracious-turing-9v23dy` that adds this file; the rest follows in later pull requests, in the order below
- **Replaces:** nothing. Carries out ADR-548 ("use only the new design") and the leftovers ADR-549, ADR-550 and ADR-653 said to remove later

## Why
The owner asked to redesign the app and the site around one design direction and to remove everything left from older designs. An inventory of 9 Nov 2026 (every screen, asset, string, doc and site page, marked keep, redesign or remove) found:
- the breathing exercise (ADR-550) and the "Hey Doddy" wake word (ADR-549) still had their Dynamic Island states, art and strings, kept only because the widget couldn't be compiled then;
- art no screen shows (the storybook, the memory scenery, the sit strip, five widget copies), two views never created, an unused colour helper;
- old design studies ADR-548 left only because they weren't named, the historical brand candidate and the v1.3 brand extracts;
- unused site images, styles and a script for a section the homepage no longer has;
- the app's screens use `UploadedTokens` (ink `#080808`, paper `#F5EFE2`, orange `#EC803F`) while the site, Doddy Web, widgets, Lock Screen and exports use Brand Guidelines V2.2 (`#171715`, `#FFF7E9`, `#FF6A00`);
- the first-launch opening still plays four v1.3 SVG poses, the only old art on a live screen.

## Decision
The owner's answers, as recommended:
- **D1 Scope:** both the app and the site, in this order: Home, the memory journey, Settings, the site. One topic per pull request.
- **D2 Colours:** the app's light colours move to Brand Guidelines V2.2, so the app, widgets, site and web match. The dark background (`#171F29` vs the guide's `#16171C`, brand review item 3b) waits.
- **D3 Opening:** the basketball opening (ADR-225) is removed; the welcome (ADR-598) is the first launch.
- **D4 Homepage headline:** "Say it once. Tap once. Done." stays until the owner's later decision (brand review item 7). The homepage's untrue claims are fixed regardless: "no account" (accounts are required, `2026-11-08-required-account`), the voice providers' order (ElevenLabs is the default, ADR-546), the translator answering for you, the phone line as if live.
- **D5 Site film and Play:** dropped, to match the chosen homepage G.
- **D6:** "I'm here non-stop" goes. Applied as "I'm close at hand" (the English of the Polish "Jestem pod ręką"), not the recommended "Set up a quick way to call me": ADR-699 rules out any word about ease ("quick") on that row, its test enforces it, and the line under it already says "Set up a way to call me."
- **Removed now (R1 to R9):** the breathing and "Hey Doddy" island leftovers (content an older build left with a wake state reads as ended); `MemoryRow`, `MemoryTagRow`, `Color.candidate`; `Storybook_page_*`, `Scenery_memory`, `DoddyMotion_sit_*`, `WholeDoddy_oneleg_balance` and four widget copies; `design/settings-and-connections-v0.1/`, `docs/design/doddy-first-meet-quick-mockup.html` and three homepage CSS files only rejected options used; `assets/brand_candidate/` (and its entries in `PACKAGE_MANIFEST.json`) and `reference/brand_v1.3_unpacked/`; six unused site images, dead site styles and script; `DODDY_VIDEO_ASSET_PROMPTS.md` moved to `docs/archive/design/`.
- **Not removed:** the stale `VISUAL_REVIEW/*` path patterns in two CI scripts (R10, harmless, owner skipped); the Apple Watch section in iPhone Settings (S4, owner's call, left as is); the hash-pinned pack docs; the reference zips; the v1.3 SVGs the site and the opening still use (they go with D3 and the site pull request).

## Consequences
- Character art in the app now comes only from the owner's pack except the opening, until D3 lands.
- `scripts/check_island_art.sh` keeps requiring every Whole Doddy pose in both catalogs, so `WholeDoddy_sneaky_crouch` keeps its widget copy.
- `MANIFEST.json` still lists the brand candidate files: it is itself a hash-pinned pack file that no script reads.
- Removed files are in git history; the pack keeps every original picture.

## Evidence
Each pull request lists what it ran. For the removals: the strings, site, day-page, token and pack checks and the site tests ran on Linux; the Swift code (the island, the widget, the app) is compiled only by the hosted Mac job.
