# V2 status — guided Back Tap setup with direct links
Date: 2026-10-09. Owner request: show how to set up Back Tap properly, with shortcuts that open
exactly the place that needs changing.

## What the user sees
Home → **Open Doddy with two taps** (shown until Back Tap is tested) or Settings → **Back Tap**.

| Step | Button | Opens | Then the user |
|---|---|---|---|
| 1 Make the shortcut | **New shortcut in Shortcuts** | `shortcuts://create-shortcut` — the Shortcuts editor with an empty shortcut | Search Actions → *Open Doddy* → rename to **Open Doddy** → Done |
| | **Try the shortcut** | `shortcuts://run-shortcut?name=Open%20Doddy` | Doddy reopens; the step shows "last opened Doddy …" |
| 2 Open Back Tap | **Open Back Tap settings** | `App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/Back%20Tap` → fallbacks below | If another page opens: Accessibility → Touch → Back Tap (always shown) |
| 3 Choose the shortcut | — | (already on Back Tap) | Double Tap → Shortcuts → Open Doddy (tick) → back to Doddy |
| 4 Test it | **Start the tap test** | — | Home Screen → double-tap → Doddy opens → "Was that your double tap?" → Yes |

Settings URL fallbacks, used only if iOS refuses the previous one: `prefs:` form of the same path →
`App-prefs:root=ACCESSIBILITY` → `App-prefs:` (Settings). iOS can accept a URL and still land on
another page, so the written path is always on screen.

## How it works
- `OpenDoddyIntent` (App Intents, opens the app) records the time it ran. `DoddyAppShortcuts` makes it
  appear under Doddy in Shortcuts with no setup. Back Tap only lists the user's own shortcuts, hence step 1.
- `TapTestState` (DoddyCore, unit-tested) counts a shortcut open only if it happened after the test
  started and within 10 minutes. The user then confirms it was the double tap; only then Settings shows
  **Tested by you, <date>**. Running the shortcut from Shortcuts or Siri looks the same to Doddy, which
  is why the user is asked.
- A shortcut built with the general **Open App** action opens Doddy but leaves no record; the screen says so.

## Limits (be honest about these)
- `App-prefs:` / `prefs:` Settings URLs are **not public API**. Community lists show the Back Tap path on
  iOS 26.1; Apple DTS says such URLs may change between releases, and App Review can reject them
  (Guideline 2.5.1). Fine for the owner's dev build; decide before any App Store submission (ADR-038).
  The guard script keeps them in `BackTapSetup.swift` only.
- iOS has no API to assign Back Tap or read it. Doddy never claims it is set up by itself.

## Verified
Linux: DoddyCore 32 tests pass (2 new: exact link URLs, tap-test window rules); guard passes and fails on a
stray `App-prefs:` URL outside `BackTapSetup.swift`; all app and UI-test Swift files syntax-parse.

## Not verified (needs the Mac and a real iPhone)
App compile (App Intents metadata, Swift 6 checks); the new UI test; that the Back Tap URL lands on Back
Tap on the owner's iOS version; that Open Doddy appears in the Shortcuts action search and in Back Tap's
list once saved; the tap test end to end.

Sources: Apple Back Tap guide https://support.apple.com/guide/iphone/back-tap-iphaa57e7885/ios ·
Shortcuts URL scheme https://support.apple.com/guide/shortcuts/apda283236d7/ios ·
Settings URL lists https://wesleydegroot.nl/blog/iOS-settings-URLs , https://github.com/FifiTheBulldog/ios-settings-urls ·
DTS on undocumented Settings URLs https://developer.apple.com/forums/thread/805248
