# Voice provider test switch: ElevenLabs vs OpenAI Realtime (ADR-265)

**Status:** built for testing. Token server and DoddyCore logic tested on Linux. **The app code is not
compiled with Xcode, has never connected to OpenAI and has never been heard on a device.**

## What it is

Home has a segmented switch under **Talk to Doddy**: `ElevenLabs | OpenAI`. It decides who runs the
*next* conversation. ElevenLabs is the default and nothing about it changed.

## Why there is no second database

Everything Doddy knows lives on this iPhone, not with either provider: notes, lists, remembered
conversations, About you, personality, calendar/reminders/contacts access. At the start of each
conversation the app renders the same prompt (`voice-agent/instructions.md`) with the same variables and
hands it to whichever provider runs it, with the same 32 tools. Tool calls come back to the same code and
show the same confirmation cards.

So a second database would make the test *worse*: the two Doddys would know different things, and you
couldn't tell whether a difference came from the provider or from the data. With one database, a note you
save while talking to OpenAI is known to ElevenLabs next time, and the other way round.

## How it works

```
Home switch ──> VoiceSessionController.start
                  ├─ ElevenLabs: token server (no body) → ElevenLabs SDK, exactly as before
                  └─ OpenAI:     token server {"provider":"openai"} → client secret (120 s, model + voice only)
                                 → WebSocket wss://api.openai.com/v1/realtime?model=…
                                 → session.update: rendered prompt + tools + semantic VAD (from the phone)
                                 → mic → PCM16 24 kHz → input_audio_buffer.append
                                 ← response.output_audio.delta → AVAudioPlayerNode
                                 ← response.function_call_arguments.done → same tool handling
```

| Piece | File |
|---|---|
| Client secret endpoint | `server/voice-token/src/handler.js` (`openAISecret`) |
| Wire format, event parsing, provider choice | `Packages/DoddyCore/Sources/DoddyCore/OpenAIRealtime.swift` |
| WebSocket + audio engine | `DoddyApp/Features/Voice/OpenAIRealtimeSession.swift` |
| One interface for both providers | `DoddyApp/Features/Voice/LiveVoiceLink.swift` |
| Routing, event mapping | `DoddyApp/Features/Voice/VoiceSessionController.swift` (`startOpenAI`, `applyOpenAI`) |
| Home switch | `DoddyApp/Features/Home/HomeView.swift` (`voiceProviderSwitch`) |

## What is *not* the same on OpenAI (so you don't mistake it for the model)

- **Weather, Wikipedia and place lookup** are ElevenLabs server-side tools. On OpenAI the app answers them
  "not available in the OpenAI test", and Doddy should say so. Web search, Gmail, Drive, Notion and
  Todoist go through Doddy's server and work on both.
- **Voice:** OpenAI's voice is set on the token server (`OPENAI_REALTIME_VOICE`, default `marin`).
  Settings › Voice and personality (voice, speed, expressiveness) applies to ElevenLabs only.
- **Starting language** picks the greeting; after that OpenAI follows the user's language on its own.
- **No hang-up tool** on OpenAI: tap End.
- **Barge-in:** Doddy's audio stops when you start talking and OpenAI is told how much you heard. The
  transcript line on screen may still show the full sentence.
- **Audio interruptions and route changes** (a call, Siri, AirPods connecting): iOS stops the audio engine; it is restarted when iOS gives the audio back, and Doddy's words that arrived meanwhile are dropped, not queued.

## Setup (owner)

1. On the token server's host (Vercel), add `OPENAI_API_KEY`. Optionally `OPENAI_REALTIME_MODEL`
   (default `gpt-realtime`; e.g. `gpt-realtime-2.1` or `gpt-realtime-mini`) and `OPENAI_REALTIME_VOICE`
   (default `marin`; `cedar` is the other recommended one). Redeploy.
2. **Put a monthly spending limit on that OpenAI project.** The token server has no counters (as with
   ElevenLabs, ADR-068). Realtime audio is billed per minute of audio in and out.
3. In the app, Settings › Voice must use the token server (the public ElevenLabs agent ID can't start OpenAI).
4. Build from Xcode (see `FIRST_BUILD_GUIDE.md`). This is the first compile of this code, so expect fixes.

## How to feel the difference (suggested test)

Same script on both, same room, same headphones or none, back to back:

1. **Latency:** say "What's on my list for today?" and count how long until Doddy starts talking.
2. **Interruptions:** ask for something long ("tell me about my week"), then cut in mid-sentence. Does it stop at once, and does it remember where it was?
3. **Tools:** "Remind me to call Mum at 6", "Save that my locker code is 4412", "What did I save about the locker?" The cards should be identical; watch whether each model picks the right tool and fills the time correctly.
4. **Polish and switching:** start in Polish, switch to English mid-sentence.
5. **Voice and personality:** which one sounds like Doddy, which one stays short?
6. **Background:** open Instagram mid-conversation (ADR-207 issue): does either keep going?

Settings › Remembered conversations shows "Voice: OpenAI" or "Voice: ElevenLabs" on each one, so you can
read back both transcripts afterwards. Note your verdict per point; 5–10 conversations each is enough to decide.

## Privacy

- New destination while the switch says OpenAI: your voice, the conversation, your saved notes, list
  names, personality, recent conversations (if on), profile (if shared), and anything Doddy reads with a
  tool. Same set as ElevenLabs, listed in Settings › What leaves this iPhone as "OpenAI (test voice)".
- The OpenAI API key stays on the token server; the phone gets a 120-second client secret.
- The token server never sees notes or prompts; its logs carry tester label, provider, status and duration only.
- **Not verified:** how long OpenAI keeps Realtime audio and transcripts, and whether they're used for training under the owner's account terms. Check the OpenAI project's data controls before anyone else uses it.

## Tests run (2026-10-11, Linux)

- `node --test server/voice-token/test/handler.test.js`: 14 pass (6 existing + 8 new: secret shape, env model/voice, per-provider config, auth before upstream, unknown provider, explicit elevenlabs, upstream error mapping).
- `swift test` DoddyCore (Swift 6.2 Linux): 650 pass after merging the default branch, including 15 new in `OpenAIRealtimeTests` (provider default, token contract incl. an old server's reply refused, session.update shape against the real `tools.json`, tools without `x_doddy`, greeting from `session.json`, client events, mute silence, server event parsing, privacy row, old conversation logs still load).
- `scripts/ci.sh --core-only`: PASS for the core scope (iOS app build NOT RUN).
- `scripts/check_forbidden_capabilities.sh`, `voice_agent_spec.py check`, `build_strings_catalog.py --check`: pass.
- App files: `swiftc -parse` only (syntax). **Not type-checked, not built, not run.**

## Review of the uncompiled app code

A second read-through (static only) found no definite compile errors and no change to the ElevenLabs path,
and these runtime issues, all fixed before the first build:
- engine stopped by a route change or interruption → restarted on `AVAudioEngineConfigurationChange` /
  interruption end, and audio isn't scheduled while it is stopped (no crash, no "speaking" stuck);
- translator hold-to-talk: 800 ms of silence is sent once on mute so OpenAI hears the user stop;
- one response at a time: tool results and app messages ask for a reply only when none is running,
  otherwise right after `response.done` (OpenAI refuses overlapping responses);
- late audio of an item the user cut off is dropped; truncate counts what was heard per item;
- a failed start doesn't stop an unattached player; a start replaced while waiting for the token server
  never opens a second microphone; OpenAI error messages are not logged (code only).

## Not tested / pending

- First Xcode build of `OpenAIRealtimeSession.swift`, `LiveVoiceLink.swift` and the controller changes.
- That OpenAI accepts the client secret in the WebSocket `Authorization` header from iOS (the documented
  browser route uses a subprotocol instead; native clients can set headers).
- Echo cancellation quality with Apple voice processing on the speaker; Bluetooth routes.
- Every tool and card on OpenAI on a device; translator mode and morning check-in on OpenAI.
