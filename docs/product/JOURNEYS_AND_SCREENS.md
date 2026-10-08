# Core journeys and screen/state requirements
## First launch
Offer transparent "Doddy is an AI assistant" framing and instant local demo capture. Show privacy summary and where memories live. No fabricated account sign-in. Provide opt-in/opt-out telemetry controls. If cloud AI is enabled later, explain provider processing prior to first call.

## Navigation (proposal)
- **Home / Talk:** friendly recognisable Doddy greeting, single useful entry area, typed capture with clear Save state, optional Ask. Don't animate before accepting input.
- **Memories:** search, list, source/capture metadata, edit, copy, export, delete, conflicting results/no results.
- **Assistant:** current turn, response grounded/source linked where personal context used; review tool proposals. No hidden auto-save.
- **Settings:** memory export and delete, local data storage explanation, humour/length/language/motion preferences, microphone and analytics, legal/data links.

## States
App: `onboarding | idle | capturing | persisting | saved | search | results | noResults | error | privacySession`.
Assistant: `idle | listening | transcribing | thinking | proposingAction | awaitingConfirmation | executing | succeeded | unverified | failed`.
Every asynchronous operation uses a distinct operation/session token; stale responses may not alter newer state. Closing, backgrounding and mic interruptions release resources deterministically.

## Character expression map
`idle -> relaxed`, `capture persisted -> reassuring nod`, `search -> focused`, `no result -> curious/uncertain`, `tool proposal -> explaining`, `verified action -> happy`, `error -> concerned/calm`, `serious situation -> neutral/grounded`. Animations must reflect *actual* state, not simulate listening/completion when services are not running.

## Accessibility
Support accessibilityReduceMotion / Reduce Transparency and Dynamic Type, contrast validation (decorative #FF6A00 not small text color), VoiceOver announcements for status, screen-reader navigation, haptics optional, screen-size adaptation, native permission denial paths. Text-only UX remains first-class.
