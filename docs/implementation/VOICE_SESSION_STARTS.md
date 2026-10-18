# Voice sessions that start twice, or start silent (investigation, 18 Oct 2026)

STATUS.md lists three symptoms from the ElevenLabs logs of 9–11 October: two sessions starting in the same second, a "ghost" session that connects but never sends its start data and stays silent for 30 s, and a session that can't hear the user. This page is what the code and the ElevenLabs log show now, and what a phone log needs to show to settle it.

**Nothing here was run on a phone.** The evidence is the ElevenLabs conversation list (start time, length, message count and how it ended: no transcripts were opened), the app code on the default branch, and the source of the ElevenLabs Swift SDK the app pins (3.3.1).

## What the ElevenLabs log shows (agent `agent_0501m4et27vyeawrwqfdxxfszfa6`)
83 conversations between 9 Oct and the last one on 16 Oct 16:36 UTC. The last build seen on the owner's phone (`ce02763`, 11 Oct 18:22 UTC) includes the "review H1" fix (`fa88ec2c`, 11 Oct 11:19 UTC): a start that was ended and replaced while it connected now ends its own conversation.

**Two starts within 5 seconds** (3 before that build, 1 after):

| Start (UTC) | Gap | First | Second |
|---|---|---|---|
| 10-09 09:57:19 | 4 s | 21 s, 3 messages | 1 s, 1 message |
| 10-09 13:20:29 | 0 s | 20 s, 3 messages | 0 s, 1 message |
| 10-10 21:42:43 | 0 s | 31 s, **0 messages** | 172 s, 28 messages |
| 10-11 20:32:17 (after the build) | 4 s | 30 s, **0 messages** | 13 s, 3 messages |

**Silent "ghost" sessions: about 30 s, 0 messages, closed by the app** ("Client disconnected: 1000"). They are still happening after the build:

| Start (UTC) | Length |
|---|---|
| 10-10 21:42:43 | 31 s |
| 10-11 20:32:17 | 30 s |
| 10-14 18:18:09 | 30 s |
| 10-16 02:42:03 | 31 s |
| 10-16 02:42:15 | 30 s |
| 10-16 02:46:20 | 30 s |
| 10-16 02:47:31 | 31 s |

Zero messages means the agent never even said its opening line, so the session's start data never arrived. The four on 16 Oct came within five minutes, at 04:42–04:47 Warsaw time.

There are also many 1–10 s sessions with one message (Doddy's opening line, then the app closed). Those look like ordinary "said hello, ended it", or a wake word that was nobody talking.

**Reading:**
- **Two at once (symptom 1) mostly predates the H1 fix.** The one case after it pairs a ghost with a real conversation four seconds later, which looks like a stalled start followed by the user trying again.
- **The ghosts (symptom 2) are the problem that remains.**
- **"Can't hear the user" (symptom 3)** fits two sessions holding the microphone at once (before H1), or a session whose audio never started.

## What the SDK does at startup (elevenlabs-swift-sdk 3.3.1)
In order (`WebRTCConnectionManager.connect`):
1. Get the room token.
2. Connect the LiveKit room. **ElevenLabs counts a conversation from here.**
3. Wait for the agent to join, **3 s by default** (`ConversationStartupConfiguration.agentReadyTimeout`).
4. Only then send `conversation_initiation_client_data`, the "start data".

If the agent doesn't join in time, or the start is cancelled, the SDK disconnects the room (`handleStartupFailure`, `handleStartupCancellation`). A failed start should therefore show as a session of a few seconds, not 30.

**So a 30-second silent session means the app stopped running in the middle of startup.**
- The room was connected, and the start data never went out.
- The connection was closed about 30 s later. That's either the app being suspended or killed, or the network layer giving up on an app that isn't running.

## Leading suspect: a "Hey Doddy" start from the background
`WakeWordListener.heard()` handles the wake word in four steps:
1. It lets go of the microphone (`stopEngine()`).
2. It asks iOS for extra running time with `beginBackgroundTask(withName: "Hey Doddy")`. That gives **about 30 seconds**, and no expiry handler is set.
3. It starts a conversation.
4. It ends that background task only when `start()` returns.

**Why this fits:**
- The wake word works while Doddy is in the background.
- The 30 s ghost length matches iOS's background allowance almost exactly.
- The 16 Oct cluster (four in five minutes, 04:42–04:47 Warsaw) looks like false wake-ups with the phone locked.

**Two ways it could fail:**
- **Microphone never starts.** If the conversation can't start its microphone or audio session from the background once the listener has let go, startup stalls before the start data. iOS then suspends Doddy when the allowance runs out.
- **The app is killed.** If a background task isn't ended before it expires, iOS may terminate the app.

**Not verified:** whether the app was in the background at those times; whether the provider was ElevenLabs because of the Home switch or something else (OpenAI has been the default since 13 Oct, ADR-442); and what the audio session did.

## Second suspect: two controllers at once
Each voice screen makes its own `VoiceSessionController`, and "Hey Doddy" makes another. "Don't start while one is live" (`guard !isLive`) and the attempt numbers work within one controller, not across them.

- **Screen and wake word:** the voice screen pauses the wake listener when it opens (RootView's `onChange(of: isVoicePresented)` calls `WakeWordListener.refresh()`). The one gap is a wake word handled just before that pause runs.
- **Re-presented screen:** a voice screen dismissed and shown again quickly (a new `VoiceView`) makes a new controller while the old one stops. The H1 fix ends the old one's connection if it got that far, but ElevenLabs still logs a short second session.

## What this change adds (diagnostics only, no behaviour change)
- **In `VoiceSessionController.start`**, log lines (category `voice-audio`) for:
  - each start: its attempt number, whether the wake word started it, whether Doddy was in the background;
  - a token that didn't arrive;
  - the moment it connects to ElevenLabs;
  - a replaced start being ended;
  - a start that failed.
  - It already logged `conversation started` on success.
- **"Wake word heard"** now says whether Doddy was in the foreground (category `hey-doddy`).
- **Errors are logged by kind only** (`LogSafeError.kind(of:)` in DoddyCore, tested): a network error's text can include the address it tried, and a voice address can carry its conversation token.

## What to capture on the phone
1. Build this branch on the phone. Connect it to a Mac, open Console.app, and filter on subsystem `com.bienos.doddy2.dev`. The SDK's own warnings, such as "Agent not ready within…", also appear when you filter on the process.
2. Choose ElevenLabs on Home, switch on Hey Doddy, lock the phone, wait a minute, and say "Hey Doddy" once.
3. Read the log:
   - **Healthy start:** `wake word heard (Doddy in foreground: false)` → `starting a conversation: … in background true` → `connecting to ElevenLabs` → `conversation started`.
   - **Background stall:** a log that stops after `connecting to ElevenLabs`, with ElevenLabs showing a 30 s, 0-message session at that minute. That confirms the leading suspect.
4. Repeat with Doddy open on screen. If that works and the locked case doesn't, it's the background start.

## Fixes to choose from once the log confirms (not built)
- **Bound the start:** run `ElevenLabs.startConversation` with a time limit, about 10 s, and cancel it when the limit passes. The SDK then disconnects the room cleanly. Pair it with an expiry handler on the "Hey Doddy" background task that stops the conversation and ends the task, so iOS never kills Doddy for it.
- **Keep the audio session active across the hand-over** from the wake listener to the conversation, so a background start can open the microphone. This needs device testing.
- **If it can't work from the background,** say so: put a "Tap to talk" greeting on the island instead of starting a conversation that can't hear.
- **One conversation at a time across the app:** a shared gate in DoddyCore so a second controller can't start while one is connecting or live. It's cheap, and it closes the cross-controller gap above.
