# "Hey Doddy" — status

## Current engine (ADR-472, 2026-10-13): Apple's on-device speech recognition, no Picovoice

**Why:** Picovoice's free plan is for personal, non-commercial use, so Porcupine could not ship in a commercial app
(owner: "it must be ok to use commercially"). It is removed from `project.yml`, `project-iphone.yml` and the code.

**How it works now:** `DoddyApp/Features/Voice/SpeechWakeEngine.swift` listens with `AVAudioEngine` and an
`SFSpeechAudioBufferRecognitionRequest` with `requiresOnDeviceRecognition = true` (the capability guard checks it), and
`WakePhraseMatcher` (DoddyCore, tested on Linux) looks for a greeting straight before a spelling of "Doddy" in the partial
transcript. An iPhone that can't recognize English on the device does not listen at all; it never falls back to Apple's
servers. The request is renewed every 45 s because iOS ends a request after about a minute. Nothing for the user to bring:
Settings → Hey Doddy is a switch, and turning it on asks for the microphone and speech recognition. `WakeWordListener`,
`WakeGate` (4 s settle time, 12 wake-ups an hour, 20 s silent-wake timeout), the island and the Home card are unchanged.

**What is verified and what is not**
- Verified on Linux: the phrase matcher, the listener's rules (`WakeListenerPolicy`) and their tests; the capability guard
  (including that it fails when the on-device line is removed).
- Compiled and UI-tested: see the CI result recorded in ADR-472 (hosted macOS build).
- **Not verified on a device (do this first):** that recognition keeps running with the screen locked and the app in the
  background (iOS may stop speech recognition there even with the audio background mode on); how often it hears "Hey
  Doddy" in a noisy room and how often it wakes by mistake; battery use over an hour; that "Doddy" is written in one of the
  spellings `WakePhraseMatcher` accepts; the 45 s renewal not losing a phrase. If background listening doesn't hold, "Hey
  Doddy" works only while Doddy is open, and the status line and this page must say so.
- Weaker than Porcupine on purpose-built accuracy, latency and battery. Only English is heard; the phrase is "Hey Doddy".

Everything below this line describes the first version (Picovoice Porcupine, ADR-254) and is kept for history. Where it
mentions the AccessKey, keyword file, token-server key or Picovoice Console, that no longer exists.

---

Date: 2026-10-11. Owner request: "create a Dodi that can listen in the background and can be waken up on a call, hey
Dodi, and then … the Dodi dynamic island pop-up shows up and says, hey bud, what's up? … for me right now … just Pat".
Owner choices: "Own listening mode", detector "Picovoice (Recommended)". Decision: `DECISIONS.md` ADR-254.

**Built and tested on Linux only. The iOS app has not been compiled or run with this change.**

**Ported 2026-10-11** from `claude/sleepy-gates-f9najr` (where it was ADR-234) onto the default branch (owner: "close
both and port hey doddy"). Fitted to what the default branch has that the source branch didn't:
- The island is drawn by the scene model with the user's island style (ADR-239). While waiting it shows the label
  "HEY DODDY", no timer and only **Stop listening**.
- Listening also steps aside for a note read aloud (ADR-243) and voice-memo recording and playback (ADR-230). Each
  sound is tracked on its own, so one finishing doesn't restart listening while another is still going.
- A conversation the wake word starts opens on screen only when no other sheet is up (the check-in, the tidy-up, a
  shared draft, Back Tap setup, onboarding): the same rule as listening on open (ADR-225).
- The source branch's morning brief (and its read-aloud hook) isn't on the default branch, so it wasn't ported.

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
| Dynamic Island while listening | The island style picked in Settings, label **HEY DODDY**, **"Say “Hey Doddy”"**, "Listening on this iPhone for “Hey Doddy” only", and **Stop listening** (turns the switch off). No Mute, no timer, no orange (it isn't a conversation) |
| Lock Screen while listening | Doddy sitting, "Hey Doddy is on", the same two lines and Stop listening |
| After "Hey Doddy" | The island says **"Hey Pat, what's up?"** at once, then a normal conversation starts on the same island. The timer counts from the wake word. The greeting stays until you first speak |
| Name in the greeting | Nickname (Doddy's personality settings), else the first word of the About you name, else "bud". Cleaned like a nickname. Polish: "Hej Pat, co słychać?" / "Hej, co słychać?" |
| Voice screen | Opens straight away if Doddy is on screen and no other sheet is up; otherwise when you next open Doddy, if the conversation is still running or left a "Worth keeping?" card |
| After the conversation | The island says "“Hey Doddy” paused · Not listening right now" until the conversation's audio has shut down (after End, or 1.5 s after the agent hangs up), then listening starts again on the same island. If iOS refuses the microphone in the background, the island ends and Settings says to open Doddy |
| During a call or another app's recording | The island says "“Hey Doddy” paused"; Porcupine's recorder resumes by itself if iOS allows |

## Safeguards
- **Settle time:** detections in the first 4 s after listening (re)starts are ignored, so Doddy's last words or
  "thanks, bye" don't wake him straight back up.
- **Silent wake:** a conversation the wake word started ends by itself if you say nothing for 20 s after Doddy is
  ready (most likely a false wake; an open conversation keeps the microphone and ElevenLabs minutes running).
- **Rest:** more than 12 wake-ups in an hour pauses listening until the hour has passed.
- **Pauses** for a conversation or the voice screen (translator mode included), a note read aloud, recording or
  playing a voice memo, voice samples, Low Power Mode, and calls/other apps taking the microphone.
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

## The spoken greeting
The app sends the dynamic variable `opening_line` with every conversation: the greeting after the wake word, otherwise
Doddy's usual opening ("Hey, it's Doddy. What's up?" / "Hej, tu Doddy. Co słychać?", matching the live agent's text). `voice-agent/session.json`
now has first message `{{opening_line}}` with that placeholder. **Applied to the live ElevenLabs agent on 2026-10-11** (owner: "you do it"): English and Polish first message
`{{opening_line}}`, placeholder `opening_line` = "Hey, it's Doddy. what's up?" (the previous live text, so builds that
don't send it sound the same); the other 35 language presets and all other placeholders unchanged; read back after
saving. Live version `agtvrsn_6701m4mc9b7wekgb2jeg1c6pwnyv`; rollback `agtvrsn_5701m4m4268zfx2s83k8xcdg5bgm`. Not yet
heard on a device: checklist H6 now also checks that Doddy *says* "Hey Pat, what's up?".
Read again on 2026-10-11 during the port, after the default branch's later agent syncs: live version
`agtvrsn_8201m4mf5fqhf9087wkrjz8kjenp` still has English and Polish first message `{{opening_line}}` with that
placeholder. Builds without this change don't send `opening_line`, so they hear the placeholder, which is the same
words as before.

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/WakeWord.swift` | `WakeGreeting`, `WakeListenerState` and `WakeListenerPolicy` (when to listen), `WakeGate` (settle time, hourly limit, silent-wake timeout), `WakeAccessKey`, `WakeKeywordFile` checks |
| `DoddyApp/Features/Voice/WakeWordListener.swift` | The only file using Porcupine: engine start/stop, wake word → conversation, island hand-off, system events |
| `DoddyApp/Features/Voice/WakeWordSetup.swift` | Keychain store for the AccessKey; keyword file import |
| `DoddyApp/Features/Settings/HeyDoddySettingsSection.swift`, `SettingsView.swift` | Settings |
| `Shared/VoiceActivity/DoddyVoiceAttributes.swift`, `VoiceActivityIntents.swift`, `DoddyWidgets/DoddyVoiceLiveActivity.swift` | `.wakeListening` status, `greeting`, `conversationStartedAt`; Stop listening |
| `Shared/IslandArt/IslandScene.swift`, `tools/island_boards/IslandSceneChecks.swift` | The waiting island in every style (label, no timer, stale wording) and its checks |
| `DoddyApp/Features/Voice/VoiceLiveActivity.swift`, `VoiceSessionController.swift`, `VoiceView.swift` | Shared island, `wakeGreeting`, `opening_line`, silent-wake timer, the voice screen taking the wake conversation |
| `DoddyApp/App/RootView.swift`, `DoddyApp.swift`, `Infrastructure/ShortcutRouter.swift` | Foreground/background; opening the wake conversation only when no other sheet is up |
| `Features/Voice/ReadAloudController.swift`, `VoicePreviewPlayer.swift`, `Features/VoiceMemos/VoiceMemoAudio.swift` | Pauses for app sound, one entry per player or recorder |
| `Features/Privacy/DataFlowView.swift`, `DataFlow.swift`, `l10n/pl_infoplist.json` | Privacy rows; the microphone prompt in Polish (draft) |
| `project.yml`, `scripts/check_forbidden_capabilities.sh`, `voice-agent/session.json`, `DEPENDENCIES_AND_LICENSES.md` | Package pin and microphone text, guard rule, `opening_line`, licence |

## Verified after the port (2026-10-11, Linux, Swift 6.2.1)
- `scripts/ci.sh --core-only`: **RESULT: PASS for core-only scope**. 608 DoddyCore package tests (587 before the
  port, plus `WakeWordTests` 20 and one `DataFlowTests`), the app-logic type-check (14 files, including
  `ShortcutRouter`), voice agent spec, guard script, Polish catalogs, backend and token-server tests. Messaging
  database tests SKIPPED (no `TEST_DATABASE_URL`). iOS build NOT RUN.
- `scripts/check_island_art.sh`: PASS with new scene checks for the waiting island in all 7 styles (not live, label,
  no timer, title), the stale wording, the greeting's precedence and its round trip. A planted bug (a timer while
  waiting) failed them in every style.
- Every changed Swift file parses (`swiftc -parse`).
- The live agent was read (not changed): `{{opening_line}}` is still its English and Polish first message.

## Verified on the source branch (Linux, Swift 6.1.2)
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

## One tap for everyone (ADR-328, 2026-10-11)
- The keyword file can ship in the app (`DoddyApp/Resources/WakeWord/hey-doddy.ppn`, the owner's) and the
  AccessKey comes from the token server (`{"provider":"picovoice"}` → `PICOVOICE_ACCESS_KEY`), kept in the
  Keychain under its own account. A user's own key and file still win.
- Settings shows only the switch when one tap is enough; the Picovoice fields are under "Use my own Picovoice
  key and file".
- Home offers it once, after 3 conversations that really connected (`HeyDoddyOffer`).
- Owner to do: set the server secret, add the .ppn file, check the Picovoice plan (active users; free-plan
  keyword files expire after 30 days). Until then the card never shows and Settings works as before.

