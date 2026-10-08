# Consolidated DESIGN + ENGINEERING rules (read first)

This document accompanies `READ_ME_FIRST.md`. **The original agent rules follow below and remain applicable.**

- Use `prompts/00_CLAUDE_MASTER_START.md` for the FIRST action only. New repo `Bienos/doddy.2`; old repo is strictly read-only.
- Primary current visual reference is **Pocket Notebook in `design/interface-v1.2/`**, including the v1.2 First Hello and Personal Home. `docs/design/CANONICAL_DESIGN_DIRECTION.md` defines precedence and owner-approval limits. Do not implement all 42 mockup screens simultaneously.
- Character for interface = SVGs `design/interface-v1.2/assets`; native candidate PNGs in `design/ios-ready-asset-catalog`. Do not mix with historical `assets/brand_candidate` unless approved.
- Font files are intentionally omitted. Do not copy/share/download unreviewed font binaries into commits. Use native system Dynamic Type, with a licensed display solution only after approval.
- `docs/implementation/CLAUDE_BUILD_ORDER_WITH_DESIGN.md` reconciles design's first-first guided Back Tap story with engineering milestone gates. Optional guided Back Tap/Island work is NOT part of M0 and not proof of actual system integration.
- Never label mocked JavaScript voice/memory, unbuilt native app, or design screenshots as implemented functionality. Do not fake memory, saved preferences, real audio or system setup verification.

---

# AGENTS.md — Codex and autonomous coding-agent instructions
**Canonical navigation:** `README.md` → `docs/00_START_HERE/DECISIONS_AND_STATUS.md` → `docs/product/PRODUCT_REQUIREMENTS.md` → `docs/architecture/DECISIONS.md` → `docs/implementation/MILESTONES.md` → `docs/quality/ACCEPTANCE_TESTS.md`.

## Scope guard
New repository `Bienos/doddy.2` only; existing `Bienos/AI-AGENT-DODDY` and all research archives **read-only**. Do not follow older embedded `BUILD_PROMPTS` inside archived ZIPs. Do not create cloud services, API keys, financial obligations, public launches or user outreach.

## Project defaults
SwiftUI iPhone app, explicit source-grounded local memory, GRDB/SQLite proposed, no mandatory account; text M1; cloud text AI M2; real voice M3; EventKit M4. No automatic OS-wide Back Tap/overlay. Character personality cannot override accuracy, privacy, permission or action receipts.

## Work protocol
1. Confirm git status/branch and toolchain; read exact requested ticket + dependencies.
2. Write a short implementation plan, tests and security implications.
3. Implement smallest coherent vertical slice, preserving existing user modifications.
4. Execute tests and lint/build when environment supports it; capture exact commands/results, not estimates.
5. Update docs/ADR/status only as the code supports. Label limitations and any proposals.
6. Stop after requested milestone; await owner review before next high-impact scope.

## Quality bar
Zero fake persistence confirmations; citation-checked local recall; explicit no-match; no content telemetry, hidden microphone, embedded secrets or unauthorized tool actions. Every error has recovery copy. Support accessibility and reduced motion from the start. For side effects: typed proposals, user confirmation, native permission and independently verified receipt.

## Output format
`Implemented | Files changed | Tests executed (pass/fail/not-run) | Known risks | Owner decisions needed | Next task`.
