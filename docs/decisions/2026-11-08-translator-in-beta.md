# The translator is shown in the beta

- **Date:** 2026-11-08
- **Decided by:** owner, 8 Nov 2026: "tlumac ma nie byc ukryty" (the translator must not be hidden), after the App Store presentation v5 (`design/app-store-v5/`) found frame 4 held back by the release scope.
- **Status:** applied on `claude/pensive-pascal-d8z2vm`, once merged
- **Replaces:** the translator line of `2026-11-07-release-scope` (only that line; the rest of that decision stands)

## Why
Decision `2026-11-07-release-scope` hid the translator in the beta together with 43 other features. The owner wants it in: it is one of the six scenes the App Store presentation shows ("Mówisz po polsku. Kelner słyszy hiszpański."), and it needs nothing the beta doesn't already have. It runs on the same voice conversation (ElevenLabs), keeps no notes, conversations or profile in its prompt when started from Home, and refuses every other tool while it is on (`TranslatorPolicy`, ADR-215).

## Decision
- `ReleaseScope.shipping` no longer hides `.translator` (`Packages/DoddyCore/Sources/DoddyCore/ReleaseScope.swift`). Everything that reads the scope follows: Home's ••• menu shows Translate, `start_translator` and `stop_translator` run, "What I can do" lists it.
- The beta now hides 43 of 46 features and 65 of 108 voice tools; the agent keeps 43. `start_translator` and `stop_translator` are no longer on the list of tools to take off the live agent (owner queue 22).
- Nothing else in the release scope changes.

## Consequences
- Privacy: in translator mode the other person's voice goes to the voice provider. Settings › Privacy and "What leaves this iPhone" already say so (ADR-215), and the Privacy paragraph is now in Polish too (same change; owner read pending, see the change note).
- Constitution: the translator tells the other person first, in their language, that it is an AI translator; their half of the screen carries an AI label; health, law and money words turn on the careful-mode banners; nothing is kept unless the person taps Copy or Save within five minutes (ADR-215, `TRANSLATOR_STATUS.md`). This decision changes none of it.
- Its status bar is now translated (it showed "Listening" in English in a Polish build), in the same change.
- The translator has not been recorded as run on a device. It needs the same device check as the rest of the beta before TestFlight users rely on it.

## Evidence
See the change note `changes/polish-strings-and-translator-in-beta.md` for what was run (DoddyCore tests on Linux with Swift 6.1.3) and what wasn't (the app's SwiftUI and `DoddyTests` compile only in the hosted Mac job; nothing on a device).
