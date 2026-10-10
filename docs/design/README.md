# Design documents: index and precedence

The files in this folder came in with the handoff pack and are hash-checked by `scripts/verify_imported_pack.py`, so they are not edited in place. New design documents written in this repository are listed here instead.

| Need | File | Status |
|---|---|---|
| Which visual direction to build, and what the owner still has to approve | `CANONICAL_DESIGN_DIRECTION.md` | pack, proposed |
| Writing as Doddy, product copy rules, typography, colour summary, marks | `BRAND_GUIDELINES.md` | **repo-authored, proposed** |
| Character identity, behavioural invariants, brand archive collision | `BRAND_AND_CHARACTER.md` | pack, proposed |
| Font and asset rights boundary | `ASSET_FONT_AND_RIGHTS_HANDOFF.md` | pack |
| What is missing before release | `GAPS_AND_DECISIONS.md` | pack |
| Browser screens to native views | `SCREEN_TO_IMPLEMENTATION_MAP.md` | pack |
| Colour tokens, type scale, component contracts (source of truth) | `../../design/interface-v1.2/docs/DESIGN-SYSTEM.md` | pack, visual reference |
| Native token values with contrast tests | `../../Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift` | code |

Precedence: owner-approved guidelines (none yet) → `CANONICAL_DESIGN_DIRECTION.md` → `BRAND_GUIDELINES.md` for copy and type → `DESIGN-SYSTEM.md` for tokens → Character Bible for behaviour → v1.3 brand archives as reference only.
