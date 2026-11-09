# Voice starts with a bounded storage snapshot

Connecting voice no longer calls MemoryStore.reload: one SQLite read selects at most 24 eligible, non-private notes plus one overflow row, and up to 30 list names with counts, without correction history, list item text, attachments or reminder refresh. Privacy is checked before the limit and again after the await. The translator skips this read. A failed read explicitly says memory is unavailable, rather than empty. Existing token/context overlap and startup cancellation guards remain.

Learning and errands use their already-loaded bounded prompt renderers at startup; a cold/unavailable cache is named as such. Tagged note lookup loads fresh data on demand, as ordinary retrieval already does. No live voice-agent configuration or audio/provider choice changes.

Rules: DOD-06, DOD-08, DOD-11, ASK-01. Exact write approvals/read-back are unchanged. Validation: the three new VoiceStartupSnapshotTests pass against real SQLite; all Swift package tests pass (2598 core tests plus persistence/design suites); the Debug iPhone simulator app builds with Xcode 27.2/iOS 27.2. scripts/ci.sh --only checks,swift passes every step except the existing Studio broken-SVG self-test (its GNU sed range does not mutate the fixture on macOS BSD sed). No Studio files changed. Real-device latency and a live provider session are not measured.
