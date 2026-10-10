# Siri reads a note back — status

Date: 2026-10-10. Owner request: "build the Siri note readback next". Decision: `DECISIONS.md` ADR-232.

## What the user gets
| Where | Behaviour |
|---|---|
| Siri, iPhone unlocked | "Hey Siri, ask Doddy what I saved" → Siri: "What are you looking for?" → "gate code" → "You saved this on 3 October: Gate code 4821." Doddy doesn't open. Other phrases: "What did I save in Doddy", "Read my note from Doddy", "Check my notes in Doddy" |
| Siri, iPhone locked | Siri asks to unlock first; nothing about the notes is said before that |
| Shortcuts app / Action Button | "Ask what I saved" appears under Doddy with no setup |
| Settings → Back Tap and Siri | "Siri can read my notes aloud" (on unless turned off) with what it does |
| Settings → What leaves this iPhone | New "Apple (Siri)" row, active while the switch is on |

## What Siri says (`Packages/DoddyCore/Sources/DoddyCore/SiriReadback.swift`)
The search is the same on-device recall as Memories → Find (word search, then Find by meaning if on). Fixed rules
turn its result into words:
- **One note:** its words in quotes and when it was saved ("today", "yesterday", "on 3 October", "on 31 December 2025").
- **Several:** the two closest matches and "There are N more. Open Doddy to see them."
- **Different numbers for the same thing:** both read, then "Check which one is current". Never picks one.
- **Only a meaning match:** "No note uses those words. This one might be what you mean, …" (one at most).
- **Nothing:** "I couldn't find that in your saved memories." Never a guess.
- **Long notes:** line breaks become pauses; cut at a word after 280 characters with "open Doddy for the rest".
- Switched off, storage problem, search error and an empty request each have one plain sentence.

## Privacy
- The search runs in Doddy on the iPhone. Nothing goes to a Doddy server, ElevenLabs or any AI model.
- Siri is Apple's: it hears the request and speaks the answer under the user's Siri settings (which can use Apple's
  servers). That is now stated in Settings and in What leaves this iPhone.
- The iPhone must be unlocked (`authenticationPolicy = .requiresAuthentication`), because notes can hold codes and
  addresses. The intent only reads; it can't save, change or delete.

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/SiriReadback.swift` | Reply rules |
| `DoddyApp/Infrastructure/SiriNoteLookup.swift` | Switch, storage and search → reply (type-checked on Linux) |
| `DoddyApp/Intents/AskDoddyNoteIntent.swift`, `DoddyShortcuts.swift` | The App Intent and its Siri phrases |
| `DoddyApp/Infrastructure/AppEnvironment.swift`, `App/DoddyApp.swift` | `AppEnvironment.shared`: one database connection per process |
| `DoddyApp/Features/Settings/SettingsView.swift`, `Features/Privacy/DataFlowView.swift`, `DoddyCore/DataFlow.swift` | Switch, privacy text, Siri row |

## Verified (Linux, Swift 6.1.2)
- `SiriReadbackTests` (8) and the new Siri lines in `DataFlowTests`. `scripts/ci.sh --core-only`: PASS for core-only
  scope, 447 DoddyCore package tests, 0 failures (439 before).
- `scripts/typecheck_app_logic.sh` now includes `SiriNoteLookup.swift`: PASS.

## Not verified (needs the Mac and an iPhone)
- App compile of the intent (`authenticationPolicy`, `ProvidesDialog`, the dialog from a runtime string) and the
  shortcut phrases being recognised.
- Siri's timeout on the first question after a restart with Find by meaning on (the model may load in the background).
  If it times out, use word search only for Siri.
- Siri doesn't offer Polish as a Siri language; Polish notes are read by the Siri voice of the user's Siri language.
- Checklist S7–S11 in `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`.
