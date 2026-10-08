# M0 implementation ticket — complete before further engineering
**Start state:** `Bienos/doddy.2` is empty as observed 2026-10-08. Reconfirm current remote state. Never modify `Bienos/AI-AGENT-DODDY`.

## Work requested
1. Initialize native iPhone app `Doddy`, SwiftUI, clearly labeled as development build; use current installed Xcode tools and verify deployment target before selecting.
2. Place `CLAUDE.md`, `AGENTS.md`, `docs/`, `schemas/`, `assets/` and prompts at repo root; keep original reference archives out of app target.
3. Add app shell with a Home surface, Memories placeholder, Settings/privacy summary, semantic colours, light/dark and accessibility toggle; character assets labelled "candidate"; no screens that imply real AI or listening.
4. Define core types and protocols: `MemoryRecord`, `MemoryRepository`, `RecallService`, `AssistantClient`, `ToolExecutor`; create **protocols only** or explicit `unavailable` adapters, not mock production behavior.
5. Implement a deterministic unit test for validation and provenance domain model; CI script that fails honestly if tests/build cannot run.
6. Documentation: `BUILD_AND_TEST.md`, dependencies/licenses, `DECISIONS.md` with status, environment, actual commands/results; keep build secrets out of repository.

## Definition of Done
- `xcodebuild -list` and selected target build succeed on the actual Mac environment, or explicitly state tools unavailable (do not claim PASS).
- Test target executes, report includes count and skipped/failed tests.
- UI never displays fake mic capture, real reminders, logged-in accounts or functioning AI.
- No provider key, production identifier, production user data or access token committed.
- App can open and shows clear AI identity/privacy summary; static visual direction explicitly candidate.
- `AGENTS.md` / `CLAUDE.md` and doc links consistent, no missing files in pack.

## Do NOT
Start M1 without a signed-off milestone exit; auto-create provider projects or paid resources; silently modify old repo; implement random features from original backlog; skip checks and say completed.
