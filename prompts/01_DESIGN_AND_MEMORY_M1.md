# M1 Claude implementation prompt — use ONLY after an actually built/reviewed M0

You are implementing DODDY's first tested local utility in the NEW V2 repository. Read `CLAUDE.md`, `docs/implementation/CLAUDE_BUILD_ORDER_WITH_DESIGN.md`, `docs/architecture/MEMORY_AND_DATA.md`, `docs/design/SCREEN_TO_IMPLEMENTATION_MAP.md`, `docs/quality/ACCEPTANCE_TESTS.md` and the v1.2 design `previews` + `docs`.

Build a real, explicit text-only memory loop: capture → commit receipt → search candidate → view exact saved source → correct preserving original capture → delete and export. Use transactional protected SQLite/GRDB as approved, clear migrations, deterministic recall and recoverable failure states. No cloud AI or inferred memory. Implement Pocket Notebook native screens with character scaled appropriately, semantic color tokens, Dynamic Type, VoiceOver and dark mode. Use `design/ios-ready-asset-catalog/` but do not assume its art has final signoff.

Demonstrate actual on-disk persistence across app restarts and correct failure behaviour; test boundary inputs, conflicts, duplicates and cancellation. Run tests where possible and report all skipped device gates. End after M1; do not invent or ship voice, model API, personal profile inference, Reminders or iOS system overlays.
