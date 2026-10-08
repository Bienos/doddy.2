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

## 2. Known conflicts — do not resolve silently

The two v1.3 archives disagree on almost every shared file (`diff -rq` shows PDF, PPTX, overview, status, character bible, motion bible, naming and implementation guide all differ).

| Topic | v1.3 (smaller zip) | v1.3_COMPLETE | v1.2 Pocket Notebook (working UI) |
|---|---|---|---|
| Type: UI | Inter | Inter (SIL OFL, no binary) | Inter + native Dynamic Type |
| Type: display | Lobster Two Bold Italic (exploration) | Custom hand-inked lettering (not yet drawn); wordmark SVG is a fallback | Caveat, 2–3 line accents only |
| Type: accent | Comic Neue | none ("avoid multiple handwritten fonts") | — |
| Orange | #FF6A00; accessible text #A44200 | not in a token file | #F58A24; accent text #A64B00 |
| Paper / ink | #F8F4EB / #111115 | not in a token file | #FFF7E9 / #171715 |
| Token file | `doddy_tokens.json` (colour, type, radius, motion) | `doddy.tokens.json` | `DESIGN-SYSTEM.md` tables |
| Scale | Display 64/68 … label 12/16 | Display 60/62 … label 13/18 | Inter 32 / 25 / 15–16 / 12–14 |

Consequence: the v1.3 colour and font values must not be copied into `CandidateTokens.swift`. The shell follows v1.2 until you decide.

## 3. Honest limits (from the packs' own status notes)

- Wordmark is font-based, not outlined or trademark-cleared.
- Motion GIFs are demos; there is no production Rive/Lottie rig.
- Character art is a new assembly from the approved direction, not a trace of the original drawings; a human illustrator should sign off.
- App mockups and widgets are speculative, not tested designs.
- **No font binaries are in the repo**, by design. Only the Inter and Caveat licence texts (`design/interface-v1.2/assets/`).

## 4. Decisions needed from the owner

1. Final UI master: Pocket Notebook, Quiet Companion or a hybrid.
2. Which v1.3 archive (or neither) is the brand master, and approval of final character drawings, logo and icon.
3. Typography: acquire/licence a display face, or stay on system type plus Inter/Caveat after licence verification.
4. Which orange and paper/ink values are canonical (v1.2 vs v1.3 above).
5. Localisation priorities and motion work.
6. Starting Xcode/iOS target, devices, and whether Dynamic Island / Back Tap are real requirements.
