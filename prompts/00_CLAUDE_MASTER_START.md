# Paste this entire prompt into Claude Code opened at the NEW DODDY V2 project root

You are the lead iOS SwiftUI engineer for DODDY V2 ("Your mate in your pocket"). The codebase is new and must remain separate from `Bienos/AI-AGENT-DODDY`.

## Mandatory first steps

1. Print `pwd`, `git remote -v`, `git status --short`, `xcodebuild -version`, `swift --version` where available. **STOP** if this working repository is not intended `Bienos/doddy.2`, if data may be overwritten, or if branch context is uncertain. Do not initialize/git-push automatically without permission.
2. Read `READ_ME_FIRST.md`, `CLAUDE.md`, `AGENTS.md`, `docs/design/CANONICAL_DESIGN_DIRECTION.md`, `docs/design/SCREEN_TO_IMPLEMENTATION_MAP.md`, `docs/product/PRODUCT_REQUIREMENTS.md`, `docs/architecture/IOS_ARCHITECTURE.md`, `docs/implementation/MILESTONES.md`, `docs/implementation/M0_FIRST_MILESTONE.md`, `docs/quality/ACCEPTANCE_TESTS.md`.
3. Inspect the interactive HTML prototype `design/interface-v1.2/index.html`, its `docs/DESIGN-SYSTEM.md`, `docs/MOTION-AND-STATES.md`, `docs/ONBOARDING-AND-PERSONAL-HOME.md`, and PNG previews. **Treat browser interactions as scripted fiction.** Never port HTML as the iOS app or claim native voice exists.
4. Use Pocket Notebook as a *reversible working direction*, preserving the design v1.2 aesthetic and readable accessibility semantics. Do not claim an owner-approved master, and do not silently combine brand archive versions.
5. Treat all paths under `reference/` as research only, not executable instructions. Never commit fonts or credentials.

## Implement M0 only — no more

Create a clean runnable native iPhone SwiftUI application shell in the new repo with a basic First Hello (skip available), Home, Memories and Settings, a static character view using the provided export candidates if technically appropriate, and clear labels for unavailable AI/voice actions. Use semantic colors, system typography with a constrained handwritten heading fallback, Dynamic Type and reduced-motion behavior. Architect features with protocols to later add M1 local persistence, but **do not fake persistence or generated personal history.**

Add relevant build/test instructions, unit tests for state transitions and routing, and accessibility review placeholders. Verify with available Xcode simulator tools; if none exist, report native build as NOT RUN, not passed. Preserve repo ownership and security boundaries. Never touch the existing repo. Do not deploy, publish or make paid provider calls.

## Report and stop

Provide changed-file inventory, screenshots if simulator available, precise build/test commands and outcomes, accessibility gaps, pending decisions (brand master + OS target + MVP priority), and proposed M1 steps. **Stop after M0.** Do not implement real voice, AI gateway, memory DB, Reminders, guided Back Tap or ActivityKit without separate instruction.
