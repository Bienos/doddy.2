# Decisions, evidence and unresolved constraints
**Snapshot date:** 2026-10-08. **Approval:** proposed working choices; founder approval not yet recorded.

## Observed facts
- The linked **private** `Bienos/AI-AGENT-DODDY` repo is an iOS/SwiftUI prototype and documentation archive. Its `README` explicitly says question/transcript/answer and speech/AI services are mocked. `SpeechService.swift` and `AIService.swift` contain mock implementations; `RecallService.swift` uses local candidate lexical matching. Old data uses `UserDefaults`, not protected GRDB SQLite.
- The old repo has an App Shortcut and manual Back Tap setup guidance, tests, UI demonstrations, 168 tracked files at inventory time and a research archive with 78 entries (76 unique by its own source review). Do not conflate file count with completeness.
- `Bienos/doddy.2` exists as an empty private repo (GitHub API 409 for an empty git tree on 2026-10-08). This pack has not been committed.
- ChatGPT Library contains research, character bible, business evidence, brand guidelines and two different v1.3 brand ZIPs. An initial Google Drive title search for Doddy returned no matches. Direct inspection of private local Codex workspace and chat sessions was unavailable.

## Product hypotheses, not conclusions
1. **H1:** adults who already self-message or use Notes/Reminders will explicitly save small useful facts, retrieve them again on later days and prefer the Doddy interaction to their existing method.
2. **H2:** a recognisable character improves qualified acquisition or user comfort without harming task completion.
3. **H3:** simple foreground voice reduces friction after text reliability is proven, but does not guarantee retention.
4. **H4:** one verified action (Apple Reminders) improves follow-through enough to justify the permission and engineering cost.

## Proposed architecture decisions (ADRs in `docs/architecture/DECISIONS.md`)
- New greenfield iPhone app, iOS 17+ baseline for core UI and Shortcuts (verify current SDK/build). Later iOS 18+ Control Center extension guarded by availability.
- SwiftUI + Swift Concurrency, local-first, app-defined interfaces; GRDB+SQLite candidate for typed persistence, FTS5 lexical retrieval; Apple Data Protection and Keychain where applicable.
- Explicit, editable personal memories only. No autonomous inference from ambient conversation.
- No account, cloud sync, persistent backend database or arbitrary automation for M0/M1. Backend key proxy only when real cloud AI is enabled; a PostgreSQL identity/control plane is **future architecture**, not a requirement for first value.
- Character is an expressive *presentation layer* and content IP, not a source of truth, fake action outcomes or emotional coercion.

## Decisions waiting on owner
- Confirm narrow MVP job (recommended: capture → later retrieval), whether first private beta must include real text AI, and minimum OS/device matrix.
- Approve one visual master among two different v1.3 brand ZIPs. Asset authoring and app mockups need human QA.
- Select early voice route after proof-of-concept on actual Polish/English devices, and target usage/cost cap.
- Decide whether local-first product should export user data in structured JSON and/or plain text (proposal: both).
- Approve actual provider, data retention terms, telemetry and lawful basis notices with appropriate expertise before beta.

## Hard prohibitions for coding agents
Do not edit existing prototype repo; do not declare fake AI, microphone capture or completed reminder writes. Do not embed provider API secrets in the client. Do not merge historical prompts wholesale or implement every feature found in the archive. Do not invent legally binding compliance conclusions or production-tested animation rigs.
