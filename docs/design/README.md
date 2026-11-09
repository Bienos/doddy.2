# Design documents: index and precedence

Some files in this folder came in with the handoff pack and are hash-checked by `scripts/verify_imported_pack.py`, so they are not edited in place; where they name Pocket Notebook (`design/interface-v1.2`) as the direction, ADR-548 supersedes them. New design documents written in this repository are listed here instead.

**Current direction (9 Nov 2026):** Brand Guidelines V2.2 (`design/brand-v2.2/`, ADR-556) for colour, type, motion and how Doddy speaks; what the app shows now for the app (Home as the calm "I'm here" screen, ADR-545 with ADR-633's bar and ADR-552's persistent Doddy, and the memory-journey screens); `design/dynamic-island-v4` for the island; `design/website-what-can-doddy-do` and `design/website-homepage-vision/g-sort-thursday.html` for the site (ADR-548). Character art comes only from the owner's numbered pack (`UPLOADED_MEMORY_ASSETS.md`). The redesign onto this direction: decision `docs/decisions/2026-11-09-remove-old-design-leftovers.md`.

| Need | File | Status |
|---|---|---|
| What was adopted from Brand Guidelines V2.2 | `BRAND_V2_2_REVIEW.md` | **owner-approved** (ADR-556) |
| Where every brand and design source is | `BRAND_INDEX.md` | repo-authored, current |
| The pack's pictures in the app: provenance and hashes | `UPLOADED_MEMORY_ASSETS.md` | repo-authored, current |
| Motion v2 (the persistent Doddy) | `MOTION_V2_PLAN.md`, `MOTION_V2_DEVICE_CHECKLIST.md`, `MOTION_V2_ART_REQUESTS.md` | repo-authored, current |
| Writing as Doddy, product copy rules, state copy | `BRAND_GUIDELINES.md` | repo-authored; V2.2 supersedes it where they differ |
| Lists, note reminders, translator, Settings and Connections | `LISTS.md`, `NOTE_REMINDERS.md`, `TRANSLATOR_MODE.md`, `SETTINGS_AND_CONNECTIONS.md` | repo-authored, built |
| Which visual direction to build (October) | `CANONICAL_DESIGN_DIRECTION.md` | pack; superseded by ADR-548 and ADR-556 where they differ |
| Character identity, behavioural invariants, brand archive collision | `BRAND_AND_CHARACTER.md` | pack, proposed |
| Font and asset rights boundary | `ASSET_FONT_AND_RIGHTS_HANDOFF.md` | pack |
| What is missing before release | `GAPS_AND_DECISIONS.md` | pack |
| Browser screens to native views (Pocket Notebook) | `SCREEN_TO_IMPLEMENTATION_MAP.md` | pack, history |
| Native token values with contrast tests | `../../Packages/DoddyCore/Sources/DoddyDesignTokens/` (`UploadedTokens.swift`, what the app reads; `CandidateTokens.swift`, Brand V2.2, what the site and web read) | code |

Precedence: Brand Guidelines V2.2 as adopted in `BRAND_V2_2_REVIEW.md` → ADR-548's design sources → `BRAND_GUIDELINES.md` for product copy where V2.2 says nothing → Character Bible for behaviour → the October pack documents and the v1.3 brand archives as reference only. The constitution (`docs/trust/`) governs behaviour above all of these.
