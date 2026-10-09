# Brand and design index

One map of every brand/design source in this repo. **Status: reference only.** Nothing here is an owner-approved production identity yet; precedence is defined in `CANONICAL_DESIGN_DIRECTION.md`.

## 1. Where things are

| Area | Location | Role |
|---|---|---|
| Working UI reference ("Pocket Notebook", v1.2) | `design/interface-v1.2/` (`docs/`, `assets/` SVGs, `previews/`, 42-screen `index.html`) | **Primary visual reference** for the native shell |
| iOS asset candidates | `design/ios-ready-asset-catalog/DoddyCharacter.xcassets` | Generated PNG exports of the v1.2 character; rights/fidelity unconfirmed |
| Design decision records | `docs/design/` (`CANONICAL_DESIGN_DIRECTION`, `BRAND_AND_CHARACTER`, `ASSET_FONT_AND_RIGHTS_HANDOFF`, `GAPS_AND_DECISIONS`, `SCREEN_TO_IMPLEMENTATION_MAP`) | Precedence, rights, open gaps |
| Visual comparison | `VISUAL_REVIEW/` | Pocket Notebook vs Quiet Companion vs Tiny Investigation |
| Brand guidelines v1.3 — original archives | `reference/original_archives/DODDY_BRAND_SYSTEM_v1.3.zip`, `…_v1.3_COMPLETE.zip` | **Source of truth** for the v1.3 pack (hashes in `reference/ARCHIVE_CHECKSUMS.md`) |
| Brand guidelines v1.3 — readable extracts | `reference/brand_v1.3_unpacked/{v1.3,v1.3_COMPLETE}/` | PDF (57 pp), PPTX (57 slides), markdown specs and token JSON only. Images, SVGs, GIFs and mockups stay inside the zips |
| Character, voice, personality | `reference/original_archives/DODDY_Character_Bible_v1_Complete.zip`; `reference/character_evals/` | Behaviour/voice reference |
| Research | `reference/original_archives/DODDY_Deep_Research_2026-10-08.zip`, `…First_Useful_Product_Research_2026.zip`; `reference/compiled_research/` | Evidence, not binding |
| Historical candidate brand assets | `assets/brand_candidate/` | **Do not mix** with v1.2 tokens without approval |
| Code tokens | `Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift` (+ tests), `DoddyApp/DesignSystem/` | Candidate values used by the M0 shell |

The extracts under `reference/brand_v1.3_unpacked/` are copies from the zips; if they ever differ, the zips win.

## 2. Decision: brand master = `v1.3_COMPLETE` (owner, 2026-10-08, in chat) — **superseded**

> **Superseded on 2026-10-09 by DECISIONS.md ADR-056:** the owner compared A (v1.3_COMPLETE), B (v1.3) and C (the v1.3-r1 redraw in `design/interface-v1.2/assets`, `#F58A24` on warm paper) and chose **C**. Both v1.3 packs are history only, so the app keeps the Pocket Notebook colour tokens (`#F58A24`, accent text `#A64B00`) and the `#FF7A00` token switch described below was not kept when the branches were merged. The readable extracts stay for reference.


The owner chose `DODDY_BRAND_SYSTEM_v1.3_COMPLETE.zip` and asked for the app tokens to follow it. Applied in `CandidateTokens.swift`; see `DECISIONS.md` ADR-010 and ADR-018. **Still open:** approval of the final character art, logo and app icon.

The two v1.3 archives disagree on almost every shared file (`diff -rq` shows PDF, PPTX, overview, status, character bible, motion bible, naming and implementation guide all differ). Where they differ:

| Topic | v1.3_COMPLETE (**chosen**) | v1.3 (smaller zip, not used) | v1.2 Pocket Notebook (previous app values) |
|---|---|---|---|
| Orange | #FF7A00 | #FF6A00 (accessible text #A44200) | #F58A24 (accent text #A64B00) |
| Paper / canvas | #F7F2E9 | #F8F4EB | #FFF7E9 |
| Ink | #0B0B0B | #111115 | #171715 |
| Dark | #151515 (slate #1E1E1E) | #16171C | #171F29 |
| Greys | #4B4B4B / #BABABA / #E6E6E6 | #67676B | #655F56 / #C5BCAD |
| Status colours | success #22C55E, error #EF4444, info #3B82F6, warning #F59E0B | none | #326746 / #A3342E |
| Type: UI | Inter | Inter | Inter + native Dynamic Type |
| Type: display | Custom hand-inked lettering (not yet drawn; wordmark SVG is a fallback) | Lobster Two Bold Italic (+ Comic Neue accent) | Caveat, 2–3 line accents |
| Radii / motion | card 24, button 16; 140/260/450/720 ms | card 24; 120/240/420/680 ms | — |
| Token file | `doddy.tokens.json` | `doddy_tokens.json` | `DESIGN-SYSTEM.md` tables |

**Precedence note:** `CANONICAL_DESIGN_DIRECTION.md`, `BRAND_AND_CHARACTER.md` and `GAPS_AND_DECISIONS.md` are imported pack files and are deliberately left unmodified (DECISIONS.md ADR-024). Where they still say the v1.2 colours (#FFF7E9 / #171715 / #F58A24), the non-COMPLETE v1.3 tokens, or "brand master unselected", this section and `DECISIONS.md` ADR-010/018 supersede them.

(An earlier version of this index wrongly said the COMPLETE pack had no token file. It does; the table above is read from it.)

What is **derived, not from the pack** (needs owner/designer sign-off):
- Light `accentText` #B05400: #FF7A00 darkened to reach 4.5:1 on paper (4.58:1). The pack gives no accessible orange; #FF7A00 itself is 2.34:1 on paper.
- `confirmed` / `error` text colours: kept from v1.2, because the pack's success/error fills are only 2.04:1 / 3.37:1 as text on its paper.
- Display typography: the pack's lettering does not exist yet, so the app uses system fonts. No font binaries are bundled.

## 3. Honest limits (from the packs' own status notes)

- Wordmark is font-based, not outlined or trademark-cleared.
- Motion GIFs are demos; there is no production Rive/Lottie rig.
- Character art is a new assembly from the approved direction, not a trace of the original drawings; a human illustrator should sign off.
- App mockups and widgets are speculative, not tested designs.
- **No font binaries are in the repo**, by design. Only the Inter and Caveat licence texts (`design/interface-v1.2/assets/`).

## 4. Decisions needed from the owner

1. Final UI master: Pocket Notebook, Quiet Companion or a hybrid.
2. ~~Which v1.3 archive~~ — decided: `v1.3_COMPLETE`. Still needed: approval of final character drawings, logo and icon. The app still ships v1.2 character art; the COMPLETE pack has its own SVG/PNG art in the zip.
3. Typography: commission the hand-inked display lettering, licence a display face, or stay on system type (current).
4. Sign-off on the three derived colour roles above.
5. Localisation priorities and motion work.
6. Starting Xcode/iOS target, devices, and whether Dynamic Island / Back Tap are real requirements.
