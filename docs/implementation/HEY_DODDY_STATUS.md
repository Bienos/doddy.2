# "Hey Doddy" — status

Date: 2026-10-11. Owner request: "create a Dodi that can listen in the background and can be waken up on a call, hey
Dodi, and then … the Dodi dynamic island pop-up shows up and says, hey bud, what's up? … for me right now … just Pat".
Owner choices: "Own listening mode", detector "Picovoice (Recommended)". Decision: `DECISIONS.md` ADR-234.

**Built and tested on Linux only. The iOS app has not been compiled or run with this change.**

## What iOS allows
- Only Siri has a true system wake word. No other app can hear "Hey Doddy" while it is closed.
- An app can keep the microphone running in the background **if it started while the app was open** (Doddy already
  has the `audio` background mode). iOS shows the orange microphone dot the whole time.
- So: turn it on, open Doddy once, and it listens until iOS ends the app, you stop it, Low Power Mode comes on, or a
  call or another app takes the microphone. After a restart (or iOS closing Doddy) open Doddy again.

## What the user gets
| Where | Behaviour |
|---|---|
| Settings → Hey Doddy | **Off unless turned on.** A "Now" line with the listener's real state (never "Listening" when it isn't). The Picovoice AccessKey (saved in the Keychain) and the keyword file (.ppn chosen from Files). A link to the Picovoice Console. A plain explanation of what it does, battery, false wake-ups and costs |
| Dynamic Island / Lock Screen while listening | Doddy sitting, **"Say “Hey Doddy”"**, "Listening on this iPhone for “Hey Doddy” only", and **Stop listening** (turns the switch off). No Mute, no timer |
| After "Hey Doddy" | The island says **"Hey Pat, what's up?"** at once, then a normal conversation starts on the same island. The timer counts from the wake word. The greeting stays until you first speak |
| Name in the greeting | Nickname (Doddy's personality settings), else the first word of the About you name, else "bud". Cleaned like a nickname. Polish: "Hej Pat, co słychać?" / "Hej, co słychać?" |
| Voice screen | Opens straight away if Doddy is on screen; otherwise when you next open Doddy, if the conversation is still running or left a "Worth keeping?" card |
| After the conversation | The island says "“Hey Doddy” paused · Not listening right now" until the conversation's audio has shut down (after End, or 1.5 s after the agent hangs up), then listening starts again on the same island. If iOS refuses the microphone in the background, the island ends and Settings says to open Doddy |
| During a call or another app's recording | The island says "“Hey Doddy” paused"; Porcupine's recorder resumes by itself if iOS allows |

## Safeguards
- **Settle time:** detections in the first 4 s after listening (re)starts are ignored, so Doddy's last words or
  "thanks, bye" don't wake him straight back up.
- **Silent wake:** a conversation the wake word started ends by itself if you say nothing for 20 s after Doddy is
  ready (most likely a false wake; an open conversation keeps the microphone and ElevenLabs minutes running).
- **Rest:** more than 12 wake-ups in an hour pauses listening until the hour has passed.
- **Pauses** for a conversation or the voice screen, the brief read aloud and voice samples (which need playback
  audio), Low Power Mode, and calls/other apps taking the microphone.
- UI-test launches never listen.

## Privacy
- What the microphone hears while waiting is processed by Porcupine **on the iPhone**; it isn't kept or sent.
- Picovoice receives the **AccessKey** when listening starts, to check it (and count it against the user's plan).
- After the wake word the conversation is exactly a tap conversation: ElevenLabs, notes, profile, approvals.
- The key is in the Keychain (this device only, after first unlock); the keyword file is in Application Support, not
  backed up. Neither is in the repository. Removing them in Settings deletes them.
- Microphone permission text, the Settings privacy paragraph, the Microphone row and What leaves this iPhone
  (Picovoice row and a "stays on this iPhone" line) say this.
- Constitution: overt and opt-in (no covert listening); the island never claims listening it can't back up (stale
  activity says "Not listening — open Doddy"); no claim that anything is saved.

## The spoken greeting (not live yet)
The app sends the dynamic variable `opening_line` with every conversation: the greeting after the wake word, otherwise
Doddy's usual opening ("Hey, it's Doddy. What's on your mind?" / "Hej, tu Doddy. Co słychać?"). `voice-agent/session.json`
now has first message `{{opening_line}}` with that placeholder. **The live ElevenLabs agent has not been changed.**
Until the owner approves that change (first message plus a dynamic-variable placeholder for `opening_line`), Doddy
says his usual opening out loud and only the island shows "Hey Pat, what's up?". An agent without the placeholder
ignores the extra variable, so this build works either way.

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/WakeWord.swift` | `WakeGreeting`, `WakeListenerState` and `WakeListenerPolicy` (when to listen), `WakeGate` (settle time, hourly limit, silent-wake timeout), `WakeAccessKey`, `WakeKeywordFile` checks |
| `DoddyApp/Features/Voice/WakeWordListener.swift` | The only file using Porcupine: engine start/stop, wake word → conversation, island hand-off, system events |
| `DoddyApp/Features/Voice/WakeWordSetup.swift` | Keychain store for the AccessKey; keyword file import |
| `DoddyApp/Features/Settings/HeyDoddySettingsSection.swift`, `SettingsView.swift` | Settings |
| `Shared/VoiceActivity/DoddyVoiceAttributes.swift`, `VoiceActivityIntents.swift`, `DoddyWidgets/DoddyVoiceLiveActivity.swift` | `.wakeListening` status, `greeting`, `conversationStartedAt`; Stop listening |
| `DoddyApp/Features/Voice/VoiceLiveActivity.swift`, `VoiceSessionController.swift`, `VoiceView.swift` | Shared island, `wakeGreeting`, `opening_line`, silent-wake timer, the voice screen taking the wake conversation |
| `DoddyApp/App/RootView.swift`, `DoddyApp.swift`, `BriefSpeaker.swift`, `VoicePreviewPlayer.swift`, `Features/Privacy/DataFlowView.swift`, `DataFlow.swift` | Foreground/background, pauses for app sound, privacy rows |
| `project.yml`, `scripts/check_forbidden_capabilities.sh`, `voice-agent/session.json`, `DEPENDENCIES_AND_LICENSES.md` | Package pin and microphone text, guard rule, `opening_line`, licence |

## Verified (Linux, Swift 6.1.2)
- `WakeWordTests` (20): greeting and name fallbacks, Polish, unsafe names refused, the tap opening unchanged; every
  listener state including background (keeps running, can't start), conversation first, pauses, start failures,
  summaries never claiming listening; settle time and hourly limit; AccessKey and keyword-file checks.
- `DataFlowTests`: the Picovoice row follows the switch; the "stays on this iPhone" line.
- `scripts/ci.sh --core-only`: PASS for core-only scope, 511 DoddyCore package tests (490 before), backend 123,
  voice agent spec PASS with the new first message.
- Island state (`DoddyVoiceAttributes`) compiled in Swift 6 with an ActivityKit stand-in and exercised: older content
  without the new keys decodes; the greeting shows only while connecting/listening and never over Speaking, Muted or a
  card; the wake-listening state has no live cue and no mute.
- Guard script PASS, and FAIL when `import Porcupine` was added to another file.
- Every changed app, widget and shared file syntax-parses.
- Porcupine's API and recorder read at the pinned commit: `PorcupineManager(accessKey:keywordPath:…)`, `start/stop/delete`,
  its recorder sets `playAndRecord` + `mixWithOthers` and doesn't deactivate the session on stop; activation errors exist,
  so the key is checked online.

## Not verified (needs the Mac, an iPhone and a Picovoice account)
Everything in checklist H1–H14 (`MAC_VERIFICATION_CHECKLIST_2026-10-10.md`), above all:
- That it compiles (Porcupine package by revision; Swift 6 isolation of the detection callbacks).
- **Restart in the background after a conversation.** LiveKit may deactivate the audio session when the call ends;
  iOS then refuses to start recording in the background and listening waits until Doddy is opened. Untested either way.
- The hand-off: the gap between Porcupine letting go and the conversation taking the microphone in the background,
  covered by a background task; and the island update from "Say “Hey Doddy”" to the greeting.
- False wake-up rate with Porcupine's default sensitivity (0.5), battery cost per hour, behaviour with calls and other apps.
- App Store review: always-on listening in the background may draw questions under Apple's guidelines; not assessed.
- Commercial use needs a Picovoice plan (owner decision before any release).
