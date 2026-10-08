# Interface → native SwiftUI task mapping

The browser study has multiple screen/state variants. This is a mapping, **not a claim of complete native routes**.

| Browser design / source | Proposed native responsibility | Minimum milestone | Test gate |
|---|---|---|---|
| `previews/welcome.png`, `10-first-hello-personal-home.png` | FirstHello with skip, explain AI, optional consent | M0 static shell; M1 state | Skip never blocks local value; VoiceOver |
| `previews/intro-chat.png`, `profile-review.png`, `personal-home.png` | Optional intro; draft preferences; approve/edit/remove; truthful personalized Home | M1 after explicit approval | No profile saved until confirm; no fake status |
| `previews/home.png`, `09-recommended-overview.png` | Pocket Notebook Home with clear Save/Find, character, tabs | M0 static native; M1 interactive | Safe areas, Dynamic Type, dark mode |
| `previews/capture.png`, `save-failed.png` | Editor, explicit capture, transactional commit and errors | M1 | No receipt on failure; preserve draft |
| `previews/recall.png`, `unknown.png` | Deterministic local match search and empty/uncertain results | M1 | Unknown result never invented; source identities |
| `previews/detail.png` | Exact saved source, provenance, correction, delete/export | M1 | Original retained, correction conflict controls |
| `previews/dark-home.png`, `large-home.png`, `polish-home.png` | Appearance, text scaling and localized layouts | M0/M1 | Real native accessibility and Polish flow |
| `previews/06-planned-voice.png` | Explicit foreground audio, AI provider speech adapter and speaking/listening states | M3 | Physical phone; mic denial, cancel, interruption |
| `previews/11-guided-back-tap-setup.png`, `previews/setup-*.png` | Skippable shortcut/back-tap setup guide and user-confirmed test | Separate approved post-M3 slice | Cannot assign Back Tap automatically; device test |
| `previews/08-motion-storyboard.png` | State-driven character/motion with reduced-motion fallback | M1 subtle static; later native motion | Actual state events, not fake listening |
| `previews/05-failure-recovery.png` | Recoverable error flows with next steps and preserved user data | All milestones | Unit + UI failure paths |
| Other examples in 42-screen gallery | Design alternatives / native state studies | Depends on feature | Maintain checklist, no copied impossible system UI |

## Native component boundaries

- `DoddyHomeView`, `DoddyCharacterPresence`, `CaptureEditor`, `SaveReceipt`, `MemoriesList`, `MemoryCandidateRow`, `MemoryDetail`, `MemoryCorrection`, `PreferencesReview`, `SettingsHome`.
- Inject an observable presenter/model: screens never directly call storage, AI vendors or EventKit.
- Shared semantics: busy, pending, failed, confirmed. No UI element claims capability that has no functioning adapter.
- `DoddyCharacterPresence` takes actual state enum; asset names follow `Doddy_<pose-with-underscores>` from the provided Xcode imagesets.
- Browser CSS/JavaScript is visual/behavioural reference, **not ported as a WKWebView substitute**.

## Traceability

- UX source: `design/interface-v1.2/docs/`, `previews/`, `verification/`.
- Domain and data rules: `docs/product/PRODUCT_REQUIREMENTS.md`, `docs/architecture/MEMORY_AND_DATA.md`, `docs/quality/ACCEPTANCE_TESTS.md`.
- Milestones/tickets: `docs/implementation/MILESTONES.md`, `docs/implementation/TICKETS.csv`.
- Always report what was NOT built and which on-device tests are blocked.
