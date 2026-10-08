# Implementation roadmap — build in sequence, not simultaneously
Status labels on all milestones: **PLANNED** until executed evidence is recorded.

## M0 — Repo and technical foundation (first Claude/Codex task)
Goal: runnable, testable SwiftUI app skeleton with no mock claims. Import docs; create Xcode project and targets; set up basic dependency rules, CI lint/test placeholder clearly labelled, design tokens sample, privacy-safe defaults, README for building. No cloud calls, voice, account or external side effects. **Exit:** app launches on selected target simulator, unit tests execute, results/logs captured, privacy screen visible, no real-user data retained.

## M1 — Local trust loop
Goal: explicit text memory save, correction, searchable recall and deletion. GRDB+SQLite with migrations and transactional operations; accessible native screens; export; deterministic recall and failure recovery. **Exit:** all M1 acceptance matrix scenarios pass on simulator, physical-device file-lock/relaunch test scheduled and executed where required. No false save success.

## M2 — Real text AI (separate gated scope)
Goal: provider-neutral assistant with cloud key gateway, limits and memory-grounded citations. Egress minimized, privacy notices and provider review. **Exit:** real provider response confirmed, not mocked; offline/cancellation/rate-limit paths; citation verifier blocks unknown memory IDs; measured request cost and logs scrubbed of personal text.

## M3 — Foreground voice
Goal: real Polish/English speech intake and spoken response with explicit mic permissions, interruption handling, text fallback. Compare Apple speech+TTS to realtime model route before implementation choice. **Exit:** physical iPhone capture, denied permission, background/route/cancel tests, latency and billing observations; no fake audio or overlay claims.

## M4 — One reliable action: Apple Reminders
Goal: user-reviewed proposal, timezone clarification, EventKit permission and verified write with idempotent recovery. **Exit:** actual reminder exists and receipt is visible after user confirmation; denied/timeouts and duplicates tested on device.

## M5 — 2-week private beta and product decision
Goal: 20–24 adult non-friend participants as *proposed recruitment*, compare real substitute (Notes/Reminders/Siri) and character-light control, measure spontaneous later retrieval vs taught demo and retention. **Exit:** documented denominators, paid intent vs actual payment distinction, privacy/security/Store gates; decide continue, narrow, pivot, stop. Not a guarantee of retention.

## Additional tasks (only after observed demand)
Optional Control Center / Live Activities, personalized cloud sync & identity, Calendar, translation as primary mode, richer memory ranking, proactive nudges, Android, subscriptions and media-scale marketing. Each requires a new explicit decision.

## Stop/approval rules
Agent implements **one milestone at a time**. After coding: summarize files changed, tests actually executed, unverified manual tests, risks, next proposed tasks. Do not change scope based on ancient prompts in `reference/`. Stop and ask for owner decision on third-party provider, billable account, external service, legal gate or ambiguous brand master.
