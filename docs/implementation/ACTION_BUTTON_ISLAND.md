# Action Button → Dynamic Island → voice (ADR-579)

Owner, 22 Oct 2026: "When I press the physical iPhone Action Button, DODDY frequently opens its full application instead of starting the intended Dynamic Island experience." Wanted: **Action Button → Doddy in the Dynamic Island → talk**, without the app.

## Why the Action Button opened the app

Found in the code, not guessed. Two code defects and one setup trap.

1. **Code: the main control always opened the app.** The "Talk to Doddy" control (`DoddyWidgets/TalkToDoddyControl.swift`, kind `com.bienos.doddy2.talk`) ran `TalkToDoddyIntent`, which has `openAppWhenRun = true`. So did the App Shortcut "Talk to Doddy" (`DoddyShortcuts.swift`), the one iOS lists under Action Button › Shortcut. iOS shows an app's own Live Activity in the Dynamic Island only while that app is *not* on screen, so with the voice screen in front there was never an island to see.
2. **Code: the setting promised something it couldn't do.** Settings › Back Tap and Siri › "When I use Talk to Doddy: Big island / Small island / Only open Doddy" (`BackTapAction`) only decided whether the island would later *expand*. The app still opened first every time. "Big island" read like "use the island instead of the app", and it wasn't.
3. **Setup trap: the background path was a second, hidden control.** ADR-577 added "Talk in the Island" (`TalkInIslandIntent`: `AudioRecordingIntent` + `LiveActivityIntent`, `openAppWhenRun = false`), which does start without opening. But it was only a *second* control, found only in Action Button › Controls. Anyone who had picked "Talk to Doddy" (the obvious name, in either list) kept getting the app.

**Not the cause, checked:**
- **`VoiceLiveActivity.endStale()`** runs once, in `DoddyApp.init`. It reads `Activity.activities` synchronously, before any intent of this run can request one. A cold start for the Action Button therefore can't end its own new island. It now also skips the activity this run owns and any that started after the run did, so a later caller can't break that either.
- **Background activity creation.** `Activity.request` is called from inside the `LiveActivityIntent`'s `perform()` (via `phase = .connecting`), which is where iOS allows it. A start without opening checks `island.isShowing` and takes the audio session before connecting, and fails plainly when iOS refuses (ADR-577).
- **The widget extension.** The intents are pinned to the app process (`allowedExecutionTargets = .main` on iOS 27, ADR-131). The preference is read there, so the extension never needs it and no App Group key was added.

**Also fixed: a real bug with rapid presses.** `TalkInIsland.start()` checked "is a conversation running?" and then awaited the voice sign-in and the profile load before creating its controller. A second press in that gap passed the check and made a second controller. The gate (ADR-496) stopped that one from connecting, but the code also replaced `TalkInIsland.started`, the only strong reference to the first conversation, which could then be freed mid-conversation. Now a synchronous `isStarting` flag is set before the first `await`, and repeat presses follow `TalkLaunchPlanner`.

## What happens now

**One control: "Talk to Doddy"** (same kind, so a button that already has it keeps it). It runs `TalkButtonIntent` (`Shared/Shortcuts/TalkButtonIntent.swift`): `AudioRecordingIntent`, `LiveActivityIntent` and `ForegroundContinuableIntent`, with `openAppWhenRun = false`, `supportedModes = [.background, .foreground(.dynamic)]` on iOS 26, and requires an unlocked iPhone. What a press does follows **Doddy › Settings › Action Button** (`TalkLaunchMode`, DoddyCore):

| Choice | First press | When something only the app can fix is missing* |
|---|---|---|
| **Dynamic Island** (default) | Starts the conversation without opening Doddy. He greets you, the island shows his status, Mute, Open and Stop | iOS asks "Open Doddy?" with the reason |
| **Open App** | Opens Doddy on the conversation screen (iOS 26: no prompt; iOS 18–25: iOS's own confirmation, the only supported way there) | n/a |
| **Automatic** | As Dynamic Island | Opens Doddy without asking (iOS 26); iOS 18–25 asks first |

\* The Terms not accepted, voice unavailable, the Face ID lock on, Live Activities off, the microphone never allowed, voice not signed in or its data notice not accepted, or iOS refusing the island or the microphone in the background. A failure of the conversation itself (offline, the provider refusing) is said, and nothing opens.

**Every press** (`TalkLaunchPlanner.step`, tested on Linux):
- Doddy is the app on screen: the conversation opens there (iOS doesn't show his own island over him).
- A press while one is starting, or within 2 s of the start: ignored. No second conversation or audio session.
- A press while one is running (2 s or more): **ends it**. Press to talk, press again to stop.

**The island** (`DoddyWidgets/DoddyVoiceLiveActivity.swift`, unchanged layouts from ADR-239/264/577): compact = Doddy + a live sign; expanded = label, elapsed time, status, Mute/Unmute, Open, Stop; Lock Screen = Doddy, status and time, Mute and End, with no words from the conversation. The states come only from SDK events: Connecting, Listening, Working on it, Speaking, Muted, Confirm in Doddy, then Ended. **New: Failed.** When a start fails after the island showed, or the connection drops, the Lock Screen shows "Conversation stopped · Doddy isn't listening · open Doddy to try again" with Open Doddy for a minute, never a live status. The Dynamic Island drops ended activities at once (iOS). "Ready" is no activity at all: Doddy isn't running a conversation.

**Expansion** stays ADR-577's request (an alert update when Doddy starts speaking, at most every 20 s). iOS decides the size and priority, so it is not a guarantee. Its switch is now **Settings › Expand when Doddy speaks**. Back Tap's old "Small island" moves there once at launch (`LaunchPreferencesMigration`), and Back Tap goes back to "Start a conversation", so the user keeps what they had.

**Siri, Back Tap, the Shortcuts app** keep the App Shortcut "Talk to Doddy" (`TalkToDoddyIntent`), which opens the app. It has to stay an iOS 17 type, and the App Shortcuts list can't hold the iOS 18 intent (ADR-577). Its choice is Settings › Siri and Back Tap › "When Siri or Back Tap opens Doddy".

**"Talk in the Island"** (the ADR-577 control) stays registered so a button that has it keeps working. It always uses the island. The guide and Settings now point only at "Talk to Doddy".

## Setting it up (owner)

1. Open Doddy once, accept the terms, and start a conversation from Home (microphone, voice sign-in, voice data notice).
2. iPhone Settings › Doddy › Live Activities: on.
3. iPhone Settings › Action Button › swipe to **Controls** › tap the control › search "Doddy" › **Talk to Doddy**. Not **Shortcut**: the shortcut always opens the app.
4. Doddy › Settings › Action Button: Dynamic Island (default), Open App or Automatic.

Doddy can't assign the button or see what it is set to; the Settings footer and the Ways to open Doddy guide say so.

## Test matrix

Automated coverage: `TalkLaunchTests` (12, DoddyCore, Linux: modes, repeat presses, fallbacks, migration), `LegalAcceptanceTests` (8), the island scene checks (`scripts/check_island_art.sh`: the failed card), `TalkButtonAndLegalTests` (app target, hosted CI only). **Everything below needs an iPhone with an Action Button and is NOT VERIFIED**: no device was available, and compiling (hosted CI) doesn't exercise hardware.

| # | Scenario | Expected | Observed |
|---|---|---|---|
| 1 | Doddy closed (not running) | Island appears, greeting, conversation. If iOS refuses the background microphone: Dynamic Island asks to open Doddy; Automatic opens him | NOT VERIFIED |
| 2 | Doddy in the background | Same as 1 | NOT VERIFIED |
| 3 | Doddy open on screen | The conversation opens in the app | NOT VERIFIED |
| 4 | iPhone locked | iOS asks to unlock (`requiresAuthentication`), then as 1 | NOT VERIFIED |
| 5 | Microphone never allowed | Nothing records. Dynamic Island: "Open Doddy?" with the reason; Automatic: opens Doddy | NOT VERIFIED |
| 6 | Live Activities off | Nothing records; same fallback as 5 | NOT VERIFIED |
| 7 | Another Doddy conversation running | The press ends it (≥ 2 s old) | NOT VERIFIED |
| 8 | No internet | Island shows Connecting, then the Lock Screen shows "Conversation stopped"; the intent says "You're offline" | NOT VERIFIED |
| 9 | Pressed rapidly several times | One conversation; presses within 2 s ignored; a later press ends it | Logic tested on Linux; device NOT VERIFIED |
| 10 | After force-quit | As 1; any island left from the killed run is cleared at launch | NOT VERIFIED |
| 11 | Changing the choice in Settings | The next press follows it; no relaunch needed (read at each press) | NOT VERIFIED |
| 12 | Back to the island after another app | Island still there; expands at Doddy's next answer if on | NOT VERIFIED |
| 13 | Stop on the island | Conversation ends, microphone released, "Conversation ended" on the Lock Screen | NOT VERIFIED |
| 14 | Stop after a connection failure | The failed card shows Open Doddy only; Dismiss/End clears it | NOT VERIFIED |
| 15 | Reboot, then press | As 1 (first unlock needed for Data Protection) | NOT VERIFIED |
| 16 | iOS 17 or no Action Button | iOS 17: controls don't exist; the Shortcut opens the app. iPhone without the button: Control Center control or Back Tap | NOT VERIFIED |

Console while testing: subsystem `com.bienos.doddy2.dev`, category `voice-audio`: "talk button: <step>, mode <mode>", "talk in the island not started: <check>", "audio session refused without opening: …, code N".

## Constitution evidence log

| Rule | Enforcing code | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-08 verified status | The island shows only SDK states; the failed card says "isn't listening"; `backgroundStartRefused` reports iOS's refusal, not a conversation | `check_island_art.sh` PASS (failed card never live or muted) | Not seen on a device |
| No hidden recording | Background start only after an explicit press, with the microphone already allowed, the island up and the audio session granted; otherwise nothing records | `TalkLaunchTests` | iOS's behaviour on a cold background start is unverified |
| DOD-11 privacy | No conversation words on the island or Lock Screen; logs carry the step and mode only | — | — |
| One conversation at a time (ADR-496) | `isStarting`, `TalkLaunchPlanner`, the gate | `TalkLaunchTests`, `VoiceConversationGateTests` | — |

Don't call the Action Button flow "working" until rows 1, 5, 9 and 13 are recorded on a device.
