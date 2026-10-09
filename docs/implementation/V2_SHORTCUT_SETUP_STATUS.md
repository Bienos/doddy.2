# V2 status — "Talk to Doddy" shortcut and guided Back Tap setup
Date: 2026-10-09. Owner instruction: build the App Shortcut plus the guided Back Tap setup (research doc
`docs/research/VOICE_SHORTCUT_ISLAND_TOOLS_2026-10.md` §1 and §5, design `design/interface-v1.2/docs/GUIDED-BACK-TAP-AND-VOICE-SETUP.md`).
**Status: written on Linux, never compiled for iOS.** The core state machine is unit-tested where a Swift toolchain
was available (see "Verified"); everything under "Not verified" needs the Mac and a real iPhone.

## What was built
| Piece | Where | What it does |
|---|---|---|
| `TalkToDoddyIntent` + `DoddyShortcuts` | `DoddyApp/Intents/TalkToDoddyIntent.swift` | App Intent "Talk to Doddy" that opens the app in the foreground (`openAppWhenRun`). As an App Shortcut it appears in the Shortcuts app, Siri ("Talk to Doddy", "Hey Doddy", "Open Doddy") and the Action Button picker without setup. |
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

## Verified
- `scripts/check_forbidden_capabilities.sh`: PASS after the change (no networking of our own, audio only in `Features/Voice`, microphone still the only permission; App Intents adds none).
- Core package tests (`BackTapSetupTests`, 12 cases): see the test log recorded in the commit message / CI output. If no toolchain was available when this file was written, the section below says so.

## Not verified (needs the Mac and a real iPhone)
1. App compile with App Intents on the current SDK. `openAppWhenRun` may warn as deprecated on iOS 18+ SDKs (`supportedModes` is the replacement, iOS 18 only; the deployment target is iOS 17).
2. That "Talk to Doddy" appears in the Shortcuts app, Siri and the Action Button picker after one launch.
3. Whether Back Tap's Shortcuts list offers the App Shortcut directly or only a personal shortcut created in the Shortcuts app (the guide covers both; the copy says "if Back Tap already lists Talk to Doddy, choose it there").
4. The tap test on a real iPhone: start the test, go Home, double-tap → Doddy opens → "That worked" → confirm → Settings shows "Tested by you · date". Also the two refusals: run the shortcut from the Shortcuts app instead (→ "I ran it another way" path) and let the 120 s window expire (→ "Start the test again").
5. Relaunch during a test: force-quit Doddy mid-test, double-tap → the receipt must still be accepted (persisted window).
6. UI smoke tests (`LaunchSmokeTests`), including the corrected microphone row assertion ("Only while talking") and the new Back Tap card test.
7. VoiceOver order on the step cards and chip selection announcement; Dynamic Type at accessibility sizes.

## Open decisions for the owner
- Keep the setup optional from Home/Settings (current) or move it before First Hello as the design proposes.
- Siri phrases: "Talk to Doddy", "Hey Doddy", "Open Doddy" are placeholders; English only for now.
- Whether the Home card should reappear after "Later" (currently it does not; Settings keeps the entry).
