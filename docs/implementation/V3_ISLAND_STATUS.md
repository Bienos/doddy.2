# V3 status — Doddy in the Dynamic Island
Date: 2026-10-09. Owner request: "it opens app [with] double back tap, now live island". ADRs 053–054 in `DECISIONS.md`.

## What it does
- Start a conversation as before (Talk to Doddy, Double Back Tap, Action Button). You can now go Home or open another app: the conversation keeps running and Doddy appears in the **Dynamic Island** (and as a banner on the **Lock Screen**).
- Island design (ADR-238, ADR-239): the owner's V4 boards (`design/dynamic-island-v4/`), drawn from the pack's own SVGs. Default **Lean In**; Settings → Voice → Dynamic Island style also offers Orbit, Ink Ripple, Negative Space, Editorial, Abstract Horizon and Here With You. While a note, plan or reminder is in play the island switches to Thought Pocket, Step Stones or Reminder Knot (ADR-240); while Doddy translates, to Language Bridge with the language pair only (ADR-244). Doddy's face with the pack's own expressions (listening smile, open mouth when speaking, brow up when thinking or waiting, calm when connecting/muted/lost), his cupped hand and an orange arc while he can hear you.
- Compact island: face + hand on the left; on the right five voice bars (listening/speaking), three dots (thinking/connecting) or a symbol (mic-slash = muted, hand = confirm a note in the app, warning = lost).
- Minimal (another activity is running): face + three bars or dots.
- Long-press the island (expanded, the "big" one): "VOICE ● LIVE" and the time beside the camera; big Doddy with hand and arc, the status in 21 pt with a second line, **Mute/Unmute** and **Stop** pills, and the voice bars.
- Lock Screen: the same, as a card that follows the phone's light/dark setting (paper in light, Night in dark). Muted: mic-slash, "Doddy can't hear you", Unmute is the main button, no orange. After End: a "Conversation ended" card with the notes you saved and the total time, removed after 2 minutes (ADR-106).
- Tap the island to jump back into the app (e.g. to Save or Don't save a note Doddy proposed).
- The island disappears the moment the conversation ends (End, Close, connection lost, failure). A stale one from a killed app is removed at the next launch.
- **If iOS stops Doddy in the background** (reports exist of background recording being ended after ~50 s), the island does not keep saying "Listening": every update carries a 90 s stale date, a heartbeat refreshes it every 40 s while the app is alive, and once stale the island shows "Lost Doddy — open the app" with a **Dismiss** button only (ADR-055). Dismiss works even when the app process is gone.

## How
| Piece | Where |
|---|---|
| Activity type + labels/symbols | `Shared/VoiceActivity/DoddyVoiceAttributes.swift` (app + extension) |
| Mute / End buttons | `Shared/VoiceActivity/VoiceActivityIntents.swift`: `LiveActivityIntent`s; the app registers handlers in `VoiceSessionController.start`. On iOS 27+ they are pinned to the app process (`allowedExecutionTargets = .main`, ADR-128); the widget extension's copy has no handlers |
| Island + Lock Screen UI | `DoddyWidgets/` widget extension (target `com.bienos.doddy2.dev.widgets`); art = owner-approved `UploadedDoddy_Listening` / `_Kept` / `_Sitting` (numbered ZIP poses, downscaled for the widget); light/dark colour sets in `DoddyWidgets/Assets.xcassets` (ADR-106) |
| Start / update / end | `DoddyApp/Features/Voice/VoiceLiveActivity.swift`, driven by `didSet` on phase, mute and pending save in `VoiceSessionController` |
| Background audio + Live Activities | `Config/Doddy-Info.plist` (`UIBackgroundModes: audio`, `NSSupportsLiveActivities`) |
| Keep running in background | `VoiceView` no longer ends the conversation on `scenePhase == .background` |
| Stale date + heartbeat; stale rendering; End fallback | `VoiceLiveActivity` (`staleAfter`, `heartbeatEvery`), `DoddyWidgets/DoddyVoiceLiveActivity.swift` (`context.isStale`), `EndDoddyConversationIntent` ends leftover activities |

## Verified
Linux only: capability guard passes (now also scans `DoddyWidgets/`, `Shared/`, `Config/`); plists and asset JSON parse. **The app, the widget extension and the Shared files have not been compiled** (ActivityKit/WidgetKit are Apple-only). See the bottom of this file for the Swift package test run of 2026-10-09 (second session).

## To check on the iPhone
1. Build: `git pull && make project`, then set **Team** for **both** targets, `Doddy` and `DoddyWidgets` (Signing & Capabilities).
2. Start a conversation, press Home: island shows Doddy; talk — status changes listening → thinking → speaking.
3. Keep talking from another app for 2+ minutes (reports exist of iOS killing background recording after ~50 s).
4. Long-press island → Mute (status "Muted", Doddy can't hear you) → Unmute → End (island disappears, app shows "Conversation ended").
5. From another app ask "remember that my locker code is 1234": island shows the hand / "Confirm in Doddy"; tap it, Save.
6. Lock the phone mid-conversation: Lock Screen banner with Mute/End.
7. Settings → Doddy → Live Activities off: conversation still continues in the background, no island.
8. **Stale island.** Start a conversation, go Home, then force-quit Doddy from the app switcher. Within about 90 s the island must change to "Lost Doddy — open the app" (yellow warning symbol, no Mute). Tap **Dismiss**: the island goes away. Then open Doddy: no island appears.
9. **Heartbeat.** Keep a conversation running from another app for 3+ minutes without saying anything: the island must *not* turn stale while Doddy is still connected (the heartbeat refreshes it every 40 s). If it does, note the time it took: that is the point where iOS stopped the app, and the "Lost Doddy" state is the correct outcome.
10. **Lock Screen stale state.** Same as 8 with the phone locked: the banner shows the warning text and only Dismiss.
11. **Light and dark (ADR-106).** Lock the phone mid-conversation in Light mode: paper card, dark text, orange waveform. Switch to Dark mode (Control Centre): Night card, light text, Doddy on a small paper backing. The island looks the same in both: Doddy on a paper backing on black.
12. **Muted.** Mute from the Lock Screen: orange disappears, "Muted · Doddy can't hear you", Unmute is the filled button.
13. **Ended card.** Save one note, then tap End on the Lock Screen: the card changes to fist-pump Doddy (sitting Doddy if nothing was saved), "Conversation ended", "Doddy isn't listening · 1 note saved · m:ss total", Open Doddy. It disappears after about 2 minutes; the island is gone at once. A failed connection instead removes the card at once.
14. **Art.** The island no longer uses the full-body pose (too small at 26 pt): it draws the Lean In face from the owner's pack (ADR-238). The Lock Screen keeps the pose art at 52 pt, from 160/240 px-tall downscales of the pack images; if it looks soft, ask design for a native small export of the same poses.
15. **Lean In island (ADR-238).** Compare the island against `design/dynamic-island-v4/01-boards/01-voice.svg`: listening (smile, hand, orange arc, bars, "VOICE ● LIVE"), speaking (open mouth), thinking (brow up, dots), muted (calm face, no hand, no orange, mic-slash, Unmute is the cream pill), Confirm in Doddy (brow up, hand symbol), lost (calm face, yellow line, Dismiss only). Check the face is centred and nothing touches the camera; the pills are tappable (the board's 34 pt pill sits in a proposed 44 pt target, not proven); the time does not push the label off; minimal shows face + bars beside another app's activity. Text sizes are fixed points from the board, so check the largest text setting too.
16. **Styles (ADR-239).** Settings → Voice → Dynamic Island style: the previews show all seven; pick each in turn, start a conversation, go Home and compare the island with its board in `design/dynamic-island-v4/01-boards/` (Orbit 05, Ink Ripple 06, Negative Space 07, Editorial 09, Abstract Horizon 10, Here With You 04). Check that orange turns grey when muted, and Here With You's compact shows the time.
17. **Moments (ADR-240).** From another app: ask Doddy to remember something → Thought Pocket "Save this note?"; tap the island, Save → "Note saved" for about 8 s, then back to the voice style. Ask for two changes at once → Step Stones "Plan ready"; confirm → "Doing the plan · Step i of N". Ask for a reminder → Reminder Knot; Add → "Adding reminder" then "Reminder set" for about 8 s. Lock the phone during each: nothing the note or reminder says appears on the island.
18. **Focus (ADR-241).** Home → Focus, 15 min, type a line, Start. Go Home: Tiny Promise with the countdown ticking and your line. Pause from the island (time stops, "Paused"), Resume, then lock the phone: Lock Screen card with Pause/Stop. Let it run out with the app in the background: the island says "Time's up" and a "Focus done" notification arrives. Force-quit Doddy mid-focus, then tap Pause on the island: it still works (iOS starts Doddy for it). Turn notifications off for Doddy and start one: the screen says there may be no alert.
19. **Breathing (ADR-242).** Home → Breathe, 1 min: the tide drawing and "Breathe in"/"Breathe out" switch every 4/6 s; Reduce Motion on: no scaling, words still switch. Go Home: the island shows "Breathing" and the time left, no In/Out. After the minute: "Breathing done".
20. **Read aloud (ADR-243).** Open a note → Read aloud: iPhone voice reads it (a Polish note in a Polish voice if one is installed). Go Home: Story Spool "Reading aloud · Your note", no words of the note. Pause/Resume/Stop from the island. Start a conversation while it reads: reading stops. Force-quit while reading: within about 90 s the island says "Stopped".
21. **Translating (ADR-244).** Home → Translate, face to face, English and French, Start; go Home. The island shows Language Bridge: "TRANSLATE ● LIVE", "Translating", "EN ⇄ FR", "EN" and "FR" in the two bubbles (centred, not clipped, black on cream; compare `design/dynamic-island-v4/02-states/language-bridge-0-expanded.svg`), compact "⇄ FR", minimal "FR" beside another app's activity. Talk both ways for a minute, with the phone locked and unlocked: **no word of what either person said ever appears on the island or the Lock Screen**, only the codes. Repeat with "Detect when they talk": "EN ⇄ ?" until they speak, then their code. Listen only, Italian: "IT → EN". Turn on "Noisy place: hold to talk": between holds the orange line is grey. Say "stop translating": the island goes back to your voice style. It never shows "Translation ready" or "Hear it". Three-letter codes (e.g. `ast` if offered) fit in the bubbles at the largest text setting.

## Verified on Linux — 2026-10-09 (second session, after ADR-055)
| Step | Result |
|---|---|
| Environment | Ubuntu 24.04 x86_64, Swift 6.1.2 toolchain (downloaded for this run; not part of the repo) |
| `scripts/check_forbidden_capabilities.sh` | PASS (scans `DoddyApp`, `DoddyWidgets`, `Shared`, `Config`; microphone the only permission) |
| `scripts/verify_imported_pack.py` | PASS (259 files match the manifest, no font binaries) |
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` | PASS: **49 tests, 0 failures** (DoddyCore 40 incl. BackTapSetup and VoiceContext; DoddyDesignTokens 7; DoddyPersistence 2 on real SQLite) |
| `swiftc -parse` on every file in `DoddyApp/`, `DoddyWidgets/`, `Shared/`, `DoddyTests/`, `DoddyUITests/` | PASS, 27 files (syntax only; ActivityKit/WidgetKit/SwiftUI cannot be type-checked on Linux) |
| `Config/*.plist` | parse as valid plists |
| iOS app build, widget extension build, unit + UI tests | **NOT RUN** (no Xcode here) — items 1–10 above are the owner's device checklist |
