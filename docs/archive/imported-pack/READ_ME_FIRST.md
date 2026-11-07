# DODDY V2 — One package for Claude Code / Codex

**Product:** DODDY — Your mate in your pocket.  
**Snapshot:** 8 October 2026. **Status:** consolidated DESIGN + ENGINEERING handoff; **not built**, **not founder-approved**.  
**Target repository:** `Bienos/doddy.2` (a new, separate repo). **Never modify** `Bienos/AI-AGENT-DODDY`.

## Open these now, in order

1. Open `VISUAL_REVIEW/00_COMPARE_3_DESIGNS.jpg`, then `01_POCKET_NOTEBOOK.png` and `02_ONBOARDING_AND_HOME.png`.
2. Open `design/interface-v1.2/index.html` in a desktop browser. It is a 42-screen **interactive browser design prototype**. Text/voice, save, memory and Back Tap are simulated.
3. Read `docs/design/CANONICAL_DESIGN_DIRECTION.md` for what to implement first, and the remaining owner decisions.
4. In Claude Code, read this root README and `CLAUDE.md` automatically; give Claude `prompts/00_CLAUDE_MASTER_START.md`.
5. Implement only M0. After the actual build and test report, approve M1 (local memory). Progress one milestone at a time.

## What is included

- `design/interface-v1.2/`: full browser design source (HTML/CSS/JS), 42 screen variants, SVG poses, motion and onboarding specification, test artifacts, preview PNGs and original handoff documents. **Font binaries excluded**; font OFL notices retained. The browser therefore uses fallback fonts; PNGs preserve original appearance.
- `design/ios-ready-asset-catalog/`: **generated PNG exports of supplied character SVGs**, with light/dark imagesets for Xcode. This is not a production-approved master, animation rig or completed asset integration.
- `VISUAL_REVIEW/`: instant images of the working direction, alternatives, UX and planned voice.
- `docs/`: canonical *proposed* product scope, implementation sequence, privacy/security, technical architecture, UX crosswalk and visual decisions.
- `prompts/`: gated instructions for Claude/Codex, including this merged design handoff.
- `reference/`: original research, brand version candidates, source archives, character behaviour/evals, unapproved or historical evidence. Read-only context.
- `schemas/`: proposed JSON Schema definitions, **not a backend implementation**.

## Critical working decision

Use **Pocket Notebook** as the **provisional UI foundation** with the **warm, capable character** from Quiet Companion. The v1.2 First Hello / Personal Home revision takes precedence over older static Home ideas where they conflict. **Neither the visual direction nor the narrow first job has been formally user-approved.** Keep all alternatives as research, and do not quietly implement the entire broad DODDY vision or guided voice/Live Activity setup in M0.

## Known limitations

- New V2 native SwiftUI app has not been built or tested by this document package.
- Voice, cloud AI, Dynamic Island, backed memory and remiders are not delivered by the browser prototype; some are planned later milestones.
- Brand v1.3 archive variants are inconsistent; the owner should select a final commercial master. The original PNG previews are source-faithful, but browser re-rendering without bundled font files differs in typography.
- Physical iPhone gesture and audio tests, API/provider pricing/privacy/legal review, production animation, final localization, app-store assets and real user validation remain open.

## Verify this package locally

Run `python3 tools/verify_pack.py` at the package root to check all file hashes, forbidden font binaries and nested archive safety. Run `python3 design/interface-v1.2/verification/verify-bundle.py` to check interface subpack integrity. These checks are not native app tests.

**Do not treat research claims or automated generated illustrations as approvals or shipped functionality.**
