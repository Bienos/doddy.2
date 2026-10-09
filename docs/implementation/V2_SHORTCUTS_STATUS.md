# V2 status: Shortcuts, Control Center control and guided Back Tap setup
Date: 2026-10-09. Owner instruction: build V2 (step 2 of `docs/research/VOICE_SHORTCUT_ISLAND_TOOLS_2026-10.md` §5).
No new provider, account, permission or cost.

## Built
| Piece | What exists |
|---|---|
| **App Shortcuts** (`DoddyApp/Shortcuts/DoddyShortcuts.swift`) | Siri, Spotlight and Shortcuts get them on install, with no setup. **Talk to Doddy** opens the app and the voice screen. **Save to Doddy** (asks "What should Doddy keep?") saves the exact text without opening the app, and says "Saved" only after the committed read-back; otherwise Shortcuts shows the store's error. **Ask Doddy** (asks "What should I look for?") runs the local lexical recall and reads back up to 3 stored notes, or "I couldn't find that in your saved memories." No AI, nothing sent. |
| **Control Center control** (`DoddyControls/`, iOS 18+) | New widget extension target `DoddyControls` with one control button, "Talk to Doddy". It runs `TalkToDoddyIntent` (`Shared/`, compiled into both targets), which opens the app. The app stays iOS 17+. |
| **Routing** (`AppRouter`, `AppServices`) | One shared `MemoryStore` and router for the scene and the intents. A talk request switches to Home and presents the voice screen. After a cold launch it opens on first appearance. Before First Hello it waits until First Hello is dismissed (AI disclosure first). Home's button uses the same path. |
| **Guided Back Tap setup** (`QuickAccessSetupView`) | Step cards following the v1.2 design ("Two taps. A little help."): intro with other quick ways (Siri, Action Button, Control Center); "make the shortcut" (Back Tap lists only the user's own shortcuts); 5 Settings steps with "Tell Doddy where you are"; the **tap test**; done. Opened from Settings → Quick access, or from Home's "Make Doddy easier to reach" link until tested. |
| **Tap test** (`ShortcutTest` in DoddyCore) | While armed, an arriving Talk to Doddy completes the test instead of starting a conversation. Doddy then asks "Did you use Double Back Tap?". **Tested by you · date** is stored only after a real arrival plus the user's yes. "I ran it another way" stores nothing. Leaving the screen disarms the test. |
| Honesty copy | Settings → Quick access shows "Double Back Tap: Not tested / Tested by you · date". It also says Doddy can't see or change Back Tap, Action Button or Control Center settings, and that Siri requests are handled by Apple. "What's built" lists **Siri & Shortcuts**. |

## Verified (Linux, 2026-10-09, Swift 6.1.2)
- `scripts/ci.sh --core-only`: pack integrity PASS, guard PASS (now also scans `DoddyControls/` and `Shared/`), **33 core tests, 0 failures**. The 3 new tests cover: Ask reply = stored text only; the tap test can't be confirmed without an arrival; status never claims system verification.
- Every app/extension/test Swift file passes `swiftc -parse`. Not type-checked: no iOS SDK on Linux.
- XcodeGen 2.44.1 (built on Linux) generated the project. `DoddyControls.appex` lands in "Embed Foundation Extensions", `TalkToDoddyIntent.swift` is in both targets' Sources, and the extension has iOS 18.0 and `DODDY_CONTROLS_EXTENSION`.
- Fixed a stale UI test from V1: `LaunchSmokeTests` expected Microphone "Not used", but V1 changed it to "Only while talking".

## Not verified (needs the Mac and a real iPhone)
- **App and extension compile** with the iOS SDK. Most likely spots for compile errors: the `AppIntent` static properties under Swift 6, `IntentDialog(stringLiteral:)`, and the control's `StaticControlConfiguration`.
- Siri phrases, Spotlight, and the Shortcuts app listing the three actions. Siri asking for the note/question. Save without opening the app, then the note appearing in the open app.
- The Control Center control opening the app and starting a conversation. Apple says an intent that opens the app runs in the app process when it is in both targets; check this on a device.
- Back Tap → personal shortcut → app; the tap test on a device; the Action Button path; the exact Settings wording on the current iOS.
- A talk request while the note editor sheet is open. The voice screen may not present until the sheet is closed (SwiftUI single-presentation rule); the draft is never discarded.
- `openAppWhenRun` may show a deprecation warning on the newest SDK (`supportedModes` replaces it). Behaviour should be unchanged.

## Not built (later, each needs a decision)
- Voice-guided setup and the Dynamic Island guide from the design: V3 (Live Activity, needs a developer account and a device).
- Polish Siri phrases (needs an `AppShortcuts.xcstrings` catalog, Polish phrase review).
- A `shortcut` memory source. Saves from Shortcuts are recorded as `explicit_text`, because the app receives text and can't tell whether Siri dictated it. A new source needs a schema change in the imported pack.

## Owner report — 2026-10-09
Owner: "i use doddy on my phone it wokred". Recorded as reported. Not yet known: which commit was installed, and
which of voice (EN/PL), the save confirmation card, Siri / Save / Ask, Control Center, Back Tap tap test were tried.
At report time the token server had no API key or access codes set (Vercel env), so any voice conversation used the
public development agent.
