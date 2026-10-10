# V2 status — "Talk to Doddy" shortcut and guided Back Tap setup
Date: 2026-10-09. Owner instruction: build the App Shortcut plus the guided Back Tap setup (research doc
`docs/research/VOICE_SHORTCUT_ISLAND_TOOLS_2026-10.md` §1 and §5, design `design/interface-v1.2/docs/GUIDED-BACK-TAP-AND-VOICE-SETUP.md`).
**Status: written on Linux, never compiled for iOS.** The core state machine is unit-tested on Linux (see "Verified");
everything under "Not verified" needs the Mac and a real iPhone.

## What was built
| Piece | Where | What it does |
|---|---|---|
| `TalkToDoddyIntent` + `DoddyShortcuts` | `Shared/Shortcuts/TalkToDoddyIntent.swift` (app + widget extension), `DoddyApp/Intents/DoddyShortcuts.swift` (app) | App Intent "Talk to Doddy" that opens the app in the foreground (`openAppWhenRun`). As an App Shortcut it appears in the Shortcuts app, Siri ("Talk to Doddy", "Hey Doddy", "Open Doddy") and the Action Button picker without setup. |
| `ShortcutRouter` | `DoddyApp/Infrastructure/ShortcutRouter.swift` | One owner of the voice and setup presentations. An invocation either opens/focuses the voice conversation (never a second one) or, during an active tap test, becomes the test's receipt. |
| `BackTapSetupCoordinator` | `Packages/DoddyCore/Sources/DoddyCore/BackTapSetup.swift` | Deterministic, versioned step map (6 steps: Settings → Accessibility → Touch → Back Tap → Double Tap → Open Doddy) and state machine: not started → shortcut preparation → guiding (by the page the user *reports*) → testing (120 s window) → receipt received → **user-reported tested**, or deferred. |
| `BackTapSetupModel` | same file as the router | Main-actor wrapper; persists only the outcome and an active test window as JSON in UserDefaults (`backTapSetup`). No transcript, no reported pages. An unexpired test window survives a relaunch, so a shortcut that opens the app after iOS killed it in the background still counts. |
| `BackTapSetupView` | `DoddyApp/Features/Setup/BackTapSetupView.swift` | The design's screens: intro ("Two taps. A little help."), shortcut preparation, step cards with "I'm in …" report chips, tap test with countdown, "That worked" with the self-report question, done. "Open iPhone Settings" opens Doddy's own Settings page and says so; it is not presented as a Back Tap deep link. |
| Entry points | `HomeView` card ("Set up" / "Later"), Settings → "Back Tap and Siri" (status row + button) | Optional and skippable, per `docs/design/CANONICAL_DESIGN_DIRECTION.md`. Not inserted before First Hello (deviation from the design's first-first order; see DECISIONS.md ADR-040). |
| Capability | `Capability.systemShortcut`, catalog `.v2Shortcut` | Settings → What's built shows "Shortcut and Back Tap". |
| Art | `Doddy_approaching` imageset copied from `design/ios-ready-asset-catalog` | Same candidate-art labelling as the other two poses. |

## Truth rules kept
- The finished state is `userReportedTested`: an intent receipt inside the test window **plus** the user saying they used Double Back Tap. There is no `verified` state; iOS has no API to read or set Back Tap, and the UI says so on the done screen and in Settings.
- Receipts outside a test, before its start, after its expiry, or a second receipt in the same test are refused (unit-tested). "I ran it another way" discards the receipt and returns to the "Choose your shortcut" step.
- "Confirm" without a receipt is refused, so the done state cannot be reached by tapping alone.
- A duplicate invocation while the conversation is open focuses it; no second microphone session.
- Unknown page reports change nothing; the app asks which page the user is on rather than guessing.

## Verified (Linux, 2026-10-09, Swift 6.4 x86_64, `scripts/ci.sh --core-only`, exit 0)
| Step | Result |
|---|---|
| Imported pack integrity | PASS (259 files match the manifest, no font binaries) |
| Forbidden-capability guard | PASS (no networking of our own, audio only in `Features/Voice`, microphone the only permission; App Intents adds none) |
| Swift package tests | PASS: 42 tests, 0 failures (DoddyCoreTests 33 incl. the 12 new `BackTapSetupTests`; DoddyDesignTokens 7; DoddyPersistence 2) |
| iOS app build + tests | NOT RUN here (no Xcode) |

**iPhone, 2026-10-09, owner report (not a recorded log):** the branch built in Xcode and ran on the owner's iPhone; the Home card and the guide showed; the tap test reached "That worked". Under Settings → Accessibility → Touch → Back Tap → Double Tap, the Shortcuts section listed **"Talk to Doddy" directly**, so no personal shortcut had to be created. iOS version, the two refusal paths (shortcut run another way; expired test), the relaunch-during-test case and the UI smoke tests were not reported. After this report the guide's "create a shortcut" screen was shortened to "Nothing to create first" with the personal-shortcut instructions kept as a fallback for iOS versions that do not list the App Shortcut (core tests re-run: 33 DoddyCore tests pass).

`BackTapSetupTests` cover: six non-empty unique steps and the manual path; happy path to `userReportedTested`; confirm without a receipt refused; receipt outside a test, before its start, after expiry and duplicate receipts refused; "I ran it another way" returns to the shortcut step without completion; reported pages jump to their step and unknown pages change nothing; next/previous bounds; defer and revisit; summary JSON round-trip that resumes an unexpired test window after a relaunch and drops an expired one; in-progress phases persist as not started.

## Not verified (needs the Mac and a real iPhone)
1. Compiler warnings, if any, on the Mac (`openAppWhenRun` may warn as deprecated on iOS 18+ SDKs; `supportedModes` is the iOS 18-only replacement, the deployment target is iOS 17). The build itself succeeded per the owner.
2. That "Talk to Doddy" appears in Siri and the Action Button picker (the Back Tap list is confirmed; the other two were not reported).
3. The personal-shortcut fallback on an iOS version that does not list the App Shortcut under Back Tap (none seen yet).
4. The two tap-test refusals: run the shortcut from the Shortcuts app instead (→ "I ran it another way" path) and let the 120 s window expire (→ "Start the test again").
5. Relaunch during a test: force-quit Doddy mid-test, double-tap → the receipt must still be accepted (persisted window).
6. UI smoke tests (`LaunchSmokeTests`), including the corrected microphone row assertion ("Only while talking") and the new Back Tap card test.
7. VoiceOver order on the step cards and chip selection announcement; Dynamic Type at accessibility sizes.

## Open decisions for the owner
- Keep the setup optional from Home/Settings (current) or move it before First Hello as the design proposes.
- Siri phrases: "Talk to Doddy", "Hey Doddy", "Open Doddy" are placeholders; English only for now.
- Whether the Home card should reappear after "Later" (currently it does not; Settings keeps the entry).
- Whether to drop the personal-shortcut fallback screen entirely once more iOS versions are seen to list the App Shortcut under Back Tap.

## Control Center / Lock Screen / Action Button control (added 2026-10-09, ADR-094)
- `DoddyWidgets/TalkToDoddyControl.swift`: an iOS 18+ `ControlWidget` button "Talk to Doddy" (kind `com.bienos.doddy2.talk`), in the existing widget extension; iOS 17 keeps everything else.
- A tap runs the same `TalkToDoddyIntent` as Siri and Back Tap (`openAppWhenRun`, so it runs in the app and goes through `ShortcutRouter`: opens or focuses the conversation, or counts as the receipt during a Back Tap test). The intent file is in `Shared/` because the control needs the type; in the extension it does nothing (`DODDY_WIDGET_EXTENSION`).
- The user adds it: Control Center → edit → Add a Control → Doddy; Lock Screen → customise → controls; Action Button → Controls → Doddy. Settings → Back Tap and Siri says so. Doddy can't add it or detect it.
- **Not verified:** compile (no Xcode here; `if #available` inside `WidgetBundle` and the shared intent in two targets are the risky parts), that the control shows in the gallery, and that a tap from the Lock Screen unlocks into the conversation.


## "Save to Doddy" shortcut (added 2026-10-10, ADR-136)
- **What it does:** `SaveToDoddyIntent` (app target, `DoddyApp/Intents/`) takes a text and opens Doddy's capture screen with it filled in, marked "Shared into Doddy from a shortcut". Nothing is saved until the user taps Save. The note is then saved with source `shared_content` ("Shared into Doddy").
- **Where it appears:** an App Shortcut with no setup, in Siri ("Save a note in Doddy", "Save to Doddy", "Keep this in Doddy"; Siri then asks "What should Doddy keep?"), the Shortcuts app and the Action Button picker. A user can build a personal shortcut that receives Share Sheet input and runs this action, which puts Doddy in the Share Sheet. No share extension, App Group or new permission was added.
- **When something is already open:** the draft waits while a voice conversation or another capture screen is open, and appears when it closes (`SharedDraftQueue`, tested). Only the newest waiting draft is kept. A draft already on screen is never swapped.
- **Text:** kept exactly, not trimmed or cut. An over-long text gets the usual "That's N characters; the limit is 5,000" message on Save. Whitespace-only text opens an empty editor.
- **Privacy:** the text goes from Shortcuts to the app on the phone. When it is dictated to Siri, Apple's speech recognition handles that part, as with any Siri request.
- **Not verified (needs the Mac and an iPhone):**
  - The app compiles with the new intent; check the `@Parameter` input options in particular.
  - The shortcut is listed in Shortcuts and Siri.
  - Siri asks for the text.
  - Share Sheet input reaches the action.
  - The sheet appears over Home, and after a conversation ends.
  - What happens if the Back Tap setup sheet was open.

## "New note" control and shortcut (added 2026-10-10, ADR-137)
- **What it does:** `NewNoteIntent` (`Shared/Shortcuts/`, in the app and the widget extension) opens Doddy's capture screen, empty, the same as tapping "Save a detail". The note is saved as a typed note (`explicit_text`), and only when the user taps Save.
- **Where it appears:**
  - `NewNoteControl` (kind `com.bienos.doddy2.newnote`, iOS 18+) for Control Center, the Lock Screen and the Action Button. The user adds it there themselves.
  - An App Shortcut: Siri "New note in Doddy" / "Write a note in Doddy", and the Shortcuts app.
- **When something is already open:**
  - A capture screen is open: nothing else opens.
  - A voice conversation is open: the empty screen appears when the conversation closes.
  - Shared text from "Save to Doddy" is waiting: "New note" never replaces it.
- **Not verified (needs the Mac and an iPhone):**
  - The widget extension and app compile with the new intent and control.
  - The control can be added and a tap opens the capture screen.
  - The Siri phrases work.

## "Find in Doddy" shortcut (added 2026-10-10, ADR-138)
- **What it does:** `FindInDoddyIntent` (app target) opens Memories → Find with the words filled in. The search runs straight away. It is the same local lookup as typing (FTS, Polish/English counterparts, spoken numbers, "may disagree" flags), and it only searches.
- **How to start it:** Siri ("Find in Doddy", "Search Doddy", "Look it up in Doddy"; Siri asks "What are you looking for?"), the Shortcuts app and the Action Button.
- **The query:** one line, trimmed, at most 200 characters, cut at a word break (`FindRequest`, tested).
- **When something is already open:** the Back Tap setup sheet closes. An open conversation or capture screen stays, and Find is ready underneath it.
- **Known gap:** running it again with exactly the same words while that Find screen is open doesn't replace text the user has since edited there.
- **Not verified (needs the Mac and an iPhone):** compile, the Siri phrases and dialog, the switch to Memories → Find, and the search running on arrival.
