# Product requirements — proposed MVP v0.1
**Product:** DODDY — *Your mate in your pocket.* **Platform:** iPhone. **Audience hypothesis:** 18+ users who already save/revisit small decisions, commitments and recommendations. **Core promise for test:** *Tell Doddy before you forget; find the original later.*

## Primary job and acceptance
User captures a useful thought with intent; after leaving and reopening the app, can retrieve the correct original record; can see source, correct, copy/export and delete it. No false assurance about persistence, no invented memory.

### In scope M1
1. First-launch value without mandatory account. Local profile and clear AI disclosure.
2. Explicit memory creation via text: save accepted text only after durable store success; max 5,000 Unicode characters; empty/oversized input rejected (no truncate-and-succeed).
3. Immutable `rawText`/accepted text and editable `currentText`; created timestamp, update timestamp, origin/source, optional tag/type. Original date never inferred from import.
4. Browsable list and deterministic lexical search: verified record IDs, matching terms, explanations, conflicts/no match handling, diacritic insensitive; source shown next to result.
5. Edit, copy, export JSON/text, delete one, delete all with irreversible-action confirmation, recovery/error handling.
6. Private/no-history temporary session mode when enabled; app never auto-persists free chat as memory.
7. VoiceOver, Dynamic Type, reduced-motion, 44pt touch targets, supported light and dark appearance; character animation must not block tasks.
8. Instrument only non-sensitive, content-free event enums and action outcome rates under the documented data and user settings policy.

### In scope later gated milestones
- **M2:** real text AI using provider gateway and minimal approved memory context; show difference between model inference and stored evidence. Fail gracefully without network.
- **M3:** real foreground speech capture, interruption and spoken output with text fallback; no ambient mic.
- **M4:** reminder proposal with explicit time/timezone and review/confirmation, EventKit write and verified result; permission denial retains intention locally.
- **M5:** user observational beta; no extra features without evidence.

## Sample end-to-end flows
**Capture:** user types "The parcel locker code is 1234" → taps Save → validation → database transaction → verified save → source-aware item appears; if disk/protection failure, display error and keep unsaved draft. (Use synthetic/non-sensitive test records in fixtures.)

**Recall:** "What was that book Marta recommended?" → local query → result matches one or more existing IDs → show original text, source and captured date; if no match, say "I couldn't find that in your saved memories" rather than generate an answer. A model may summarize *only selected verified candidate records*.

**Correction:** user edits a record; `rawText` remains unchanged, `currentText` changes with edit timestamp; original remains viewable and exportable as provenance, subject to user's deletion choices.

**Delete:** delete memory → UI refresh → no result in search/index → app restart verifies absence; export and backup behavior explained. Delete-all requires explicit confirmation.

## Non-goals / prohibited claims
No automatic phone-wide overlay, default Back Tap assignment, perpetual Dynamic Island, unrestricted screen reading, Gmail/Calendar on day one, autonomous browsing, passive lifelong memory, fabricated action receipts, unbounded cloud sync, health data, unapproved emotion/dependency features, Android, payments or graph DB. No promises that media/retention hypotheses are already validated.

## Quality targets (proposed test thresholds; not evidence)
- Zero false-positive "saved" outcomes under injected failure.
- 100% of returned recall hits map to real stored record IDs in deterministic synthetic corpus.
- Zero executed side-effecting actions without confirmation receipt.
- Offline M1 capture/recall/edit/delete works after restart; microphone denied → text route stays functional.
- Latency budgets to be measured on representative iPhones rather than assumed fixed.
