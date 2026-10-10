# Onboarding status — Back Tap guide, introduction, personal Home
Date: 2026-10-09. Owner request: "implement onboarding etc screens". Source designs: `design/interface-v1.2/docs/GUIDED-BACK-TAP-AND-VOICE-SETUP.md`, `ONBOARDING-AND-PERSONAL-HOME.md`, `CLAUDE-GUIDED-SETUP-PROMPT.md` (phase 1, part of phase 2, phase 5). Replaces the old First Hello screen.

> **Changed at branch consolidation (2026-10-09, DECISIONS.md ADR-089):** the written Back Tap guide below (part 1, `SetupGuideView`, the `OpenDoddyIntent` receipt and Settings → Getting started) was **removed**, because V2 already ships a Back Tap guide that was tried on the owner's iPhone (`V2_SHORTCUT_SETUP_STATUS.md`). First use is now the optional introduction only; Back Tap is offered from the Home card and Settings → Back Tap and Siri. Parts 2 and 3 are unchanged. The UI test for the written guide was removed with it.

## Flow
First launch → **Two taps. A little help.** (optional Back Tap guide) → **Hey. Let's talk.** (optional introduction) → Home. Each part can be skipped; skipping never blocks the app, and neither is forced again. Both can be reopened from Settings.

### 1. Written Back Tap guide (`Features/Onboarding/SetupGuideView.swift`)
| Screen | What it does |
|---|---|
| Welcome | Explains Double Back Tap. **Show me how** / **Set this up later**. States that voice guidance isn't built and nothing listens. |
| Shortcut | Three steps to create a personal **Open Doddy** shortcut; **Open Shortcuts** button (`shortcuts://create-shortcut`); help for a missing action (use Open App → Doddy). |
| Walkthrough (6 cards) | Home Screen → Settings → Accessibility → Touch → Back Tap → Double Tap → Open Doddy. One card per page; the user taps "I'm in Touch" etc. and gets that page's instruction. Next / Previous / Set up later. |
| Test | Go to the Home Screen and double-tap. When Doddy comes back to the foreground it asks whether the double tap did it. **Yes** / **It didn't work** (troubleshooting, back to the steps) / **Finish without testing**. |

The place in the guide is saved, so leaving for the Settings app and coming back resumes on the same card.

### 2. Introduction (`Features/Onboarding/IntroductionView.swift`)
Six optional questions, one at a time, with preset choices and free text: what to call you (≤60), useful help (≤240), answer style (≤120), language (≤60), humor (≤120), current focus (≤400). Every question can be skipped; **Review and finish** is always available. The review screen lets you edit or remove each answer. **Save these preferences** is the only thing that stores anything; **Continue without saving** stores nothing. **Show me what you can do** lists what is actually built (capability catalog).

### 3. Personal Home and Settings
- Home greets with the approved name ("Hi, Ola.") or the neutral line, and shows approved focus / help / style under **What you told me**. With no profile, Home is unchanged.
- Settings → **Getting started**: Back Tap status as reported by the user ("Not set up", "In progress", "You said it's set up", "You said it works") and a button to go through the guide again.
- Settings → **About you**: approved fields, **Edit** (Cancel keeps everything as it was), **Answer the intro questions again**, **Forget all of this** (confirmation says memories stay).

## Honesty rules kept
- Doddy can't read the Back Tap setting and no public API reports it. No state says "verified"; statuses say "You said…". A test asserts this.
- The **Open Doddy** App Intent (`App/OpenDoddyIntent.swift`) only opens the app and records, in memory, when it ran. A run inside the 5-minute test window changes the wording to "Your Open Doddy shortcut ran just now"; it still asks whether a double tap started it. An Open App shortcut gives no receipt, and none is invented.
- Answers are a transient draft; nothing is written until Save, and the write is read back before Home changes. Setup stores task state only (step, decision, version), never answers or speech.
- Profile and memories share the SQLite file but not tables: forgetting the profile keeps memories, deleting all memories keeps the profile (tested).
- Voice conversations receive the profile **only when the user turns on** Settings → About you → "Use in voice conversations" (off by default, ADR-092). It is sent as `{{user_profile}}` at the start of each conversation; Home and Settings say whether it is on.
- The language answer is stored for later replies; the app's screens stay in English.

## Data
New GRDB migration `v2_profile_onboarding` (shipped `v1_memories` untouched):
- `profile_fields(key, value, source='explicit_user_review', approved_at_ms, revision)`. CHECKs on the key list, the length (1–400) and the source.
- `onboarding_progress` (single row): `walkthrough_version, setup_decision, setup_step, intro_decision, updated_at_ms`, with CHECKs on every enum.

Edits replace the profile in one transaction: unchanged fields keep their approval time and revision, changed ones get revision+1, removed ones are deleted. A save based on an outdated profile is rejected (`revisionConflict`) and the draft is kept. The store now refuses to open a database written by a newer app version (`newerSchema`) and leaves the file untouched.

This differs on purpose from the archived package's proposed `003_setup_and_profile.sql`: it uses a GRDB-named migration instead of `PRAGMA user_version`, plain text values instead of `value_json`, and decision names that never imply verification.

## Verified (Linux, Swift 6.1.2)
`scripts/ci.sh --core-only`: pack integrity PASS, forbidden-capability guard PASS, **51 package tests pass** (30 before this change, 21 new):
- Draft validation (trimming, skip, over-long rejected and not cut, Polish characters at the limit), preset choices fit their limits.
- Route and transitions: setup → intro → Home, defer never blocks, resume on the reported page, an outdated step map restarts, reopening setup keeps the intro decision, no "verified" state, step order/copy.
- Tap-test window: stale, in-window and late receipts.
- SQLite: commit + reopen, edit keeps/bumps/removes, stale draft rejected, invalid draft writes nothing, profile and memories independent, every enum value passes the CHECKs and survives reopen, **v1 → v2 upgrade keeps memories**, newer-schema file rejected byte-for-byte untouched.

All app Swift files pass `swiftc -parse` (syntax only). A separate code review of the app sources against the package APIs found no definite compile errors; its logic findings were fixed (reopening setup then "Set this up later" keeps an earlier report, each walkthrough card starts at the top, overlapping saves keep the newest state, container accessibility IDs removed, UI tests wait and scroll). Two items to watch in Xcode: method references passed as closures (now wrapped) and `Binding(get:set:)` in the profile fields.

## NOT verified (needs the Mac and a real iPhone)
- **App compile**: SwiftUI, AppIntents and the app/UI tests can't build on Linux. Run `scripts/ci.sh` on the Mac.
- New and updated tests (unit tests in `DoddyTests`; UI tests: skip-both, written guide by report, introduction keeps only reviewed answers, plus the existing smoke tests). The old smoke test expected Microphone "Not used", which no longer matched V1 voice; it now expects "Only while talking".
- On a phone: the Open Doddy action appears in Shortcuts; `shortcuts://create-shortcut` opens the editor; the personal shortcut is listed under Back Tap → Double Tap; a double tap returns to the test screen and shows "Welcome back"; Dynamic Type at accessibility sizes, VoiceOver order, dark mode, small screens.
- Existing installs: the old `hasSeenFirstHello` flag is no longer read, so an updated dev build shows the new first-use flow once. Memories are kept (migration test).

## Not built (by design or pending approval)
Voice setup guide, background audio, Dynamic Island/Live Activity controls (guided-setup phases 3–4); AI-driven introduction; profile sent to the voice agent; profile in the memory export (export format unchanged); translated UI.
