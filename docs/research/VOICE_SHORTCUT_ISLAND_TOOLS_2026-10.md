# Voice, shortcut setup, Dynamic Island and iPhone tools — research
Date: 2026-10-08. Status: **research + recommendation, nothing built.** Prices and model names were read from
vendor pages on this date and change often; re-check before budgeting. Items marked *(anecdotal)* come from
developer forums, not Apple.

## 1. Can Doddy "easily set up the shortcut"?

**Yes, as a guided setup — not automatically.** No public API lets an app assign itself to Back Tap, the Action
Button or the side button, or check what is assigned.

| Surface | What the app can do | What the user must do |
|---|---|---|
| **App Shortcuts** (App Intents) | Ship a "Talk to Doddy" shortcut that appears automatically in Shortcuts, Spotlight and Siri — no setup | Nothing |
| **Action Button** (iPhone 15 Pro and later) | Offer the shortcut and/or a Control | Settings → Action Button → choose Doddy |
| **Back Tap** | Show step cards (or speak them) | Settings → Accessibility → Touch → Back Tap → Double Tap → pick the shortcut |
| **Control Center / Lock Screen control** (iOS 18+) | Ship a ControlWidget "Talk to Doddy" | Add it once |
| **Side button instead of Siri** | Not possible in Poland/EU: Apple only allows a third-party side-button assistant in Japan (iOS 26.2+) | — |

How to make it *feel* easy (matches design v1.2 "Guided Back Tap and voice setup"):
1. Doddy ships the App Shortcut, so step "create a shortcut" disappears.
2. A setup screen shows the exact Settings path, one step at a time; optionally Doddy reads the steps aloud.
3. **Tap test:** the shortcut carries a one-time test code; when Doddy is opened by it, Doddy says "That worked." The app records "tested by you", never "verified by iOS".

## 2. Is OpenAI Realtime the best voice model?

**It is one of the two leading options, not clearly the best.** Independent latency comparisons put OpenAI and Google
within ~50–100 ms of each other, a gap smaller than network/region effects. The big differences are **price** and
**how tools work**.

| Option | Price (vendor page, 2026-10-08) | Notes |
|---|---|---|
| OpenAI `gpt-realtime-2.1` | $32 / 1M audio-in tokens, $64 / 1M audio-out | ≈ $0.05–0.10 per conversation minute (third-party estimates). Mature WebRTC path for phones; app-executed function tools. |
| OpenAI `gpt-realtime-2.1-mini` | $10 in / $20 out per 1M | ≈ ⅓ the price; quality to test in Polish |
| OpenAI **GPT-Live** `gpt-live-1` | $0.05 / min (+ backend model and tool cost) | Voice layer that delegates "thinking" to a backend model (e.g. web search) and returns function calls to the app; no built-in approval step — the app must confirm. Server must create sessions (`POST /v1/live/sessions`). |
| Google `gemini-3.8-live` | $0.005 / min audio in, $0.018 / min audio out | Roughly **3–5× cheaper** than gpt-realtime-2.1; Polish (pl-PL) is in the Live API language list. WebSocket transport (less forgiving on bad mobile networks than WebRTC, per one comparison). |
| Apple on-device (Speech + Foundation Models + system voice) | Free, private, offline | Less natural turn-taking/voice; Foundation Models has tool calling but only runs on Apple-Intelligence devices; Apple's new Siri AI is **not offered in the EU on iOS 27**. Good fallback, not the "mate" experience. |

**Recommendation:** build one provider-neutral `VoiceSession` and start with **OpenAI `gpt-realtime-2.1`** (your
preference, best-documented phone path). Before committing, run a one-day **Polish + English bake-off** against
`gpt-realtime-2.1-mini` and `gemini-3.8-live` with the same 20 test phrases (accuracy, interruptions, voice
quality, cost per minute). Switching later is cheap if the interface is neutral.

**Required regardless of provider:** a small server that holds the API key and hands the app a short-lived token
(OpenAI: `POST /v1/realtime/client_secrets`, then the app connects to `/v1/realtime/calls`). Never put the key in
the app. For Polish users, create the OpenAI project with **EU data residency** (only possible when the project is
created) and confirm Realtime is covered.

## 3. Bringing Doddy to the Dynamic Island

**Possible, with real limits.** The Island shows a **Live Activity**: Doddy's face/state (listening, thinking,
speaking), a timer, and Pause/Stop buttons. It is a status display, not a chat window, and it cannot run the
microphone itself.

- **The conversation must start with Doddy in the foreground.** iOS blocks starting a recording audio session from
  the background ("Target is not foreground" *(forum)*). So the flow is: Back Tap / Action Button → Doddy opens →
  talking starts → you can go Home and Doddy keeps listening in the Island.
- Apple's `AudioRecordingIntent` **requires** a Live Activity for the whole time the app records in the background.
- Background audio needs the audio background mode; one developer reports apps being killed ~50 s into background
  recording on iOS 26.5 *(anecdotal)* → must be tested on a real iPhone early.
- The Island cannot be pinned open, cannot show long text, and must stop claiming "listening" the moment audio stops.

## 4. Connecting Doddy to tools inside the iPhone

**Pattern:** the voice model *proposes* a tool call → the app checks it → Doddy says/shows what it will do →
you confirm (tap or "yes") → the app does it → the app checks it really happened → Doddy reports. The voice model
never acts by itself. (Same contract as `docs/architecture/TOOLS_AND_ACTIONS.md`.)

| Can do directly (with your permission) | Framework |
|---|---|
| Your saved memories: search, save (with confirm) | already built (M1) — **best first tools** |
| Reminders, calendar events | EventKit |
| Alarms and timers | AlarmKit (iOS 26+) |
| Contacts lookup | Contacts |
| Location, nearby places, directions | Core Location, MapKit |
| Weather | WeatherKit |
| Music playback | MusicKit |
| Smart home | HomeKit |
| Notifications at a time | UserNotifications |
| **Run any of your own Shortcuts** (which can reach other apps' actions) | `shortcuts://run-shortcut?name=…` — opens the Shortcuts app briefly |

| Needs your tap every time | Why |
|---|---|
| Send a text / email, make a call | iOS only allows the compose/call sheet; no silent sending |

| Not possible for any third-party app | |
|---|---|
| Read other apps' data or your screen; control other apps directly; act in the background unasked; assign Back Tap; stay on screen as an overlay | iOS sandbox |

The reverse direction is also worth doing: expose Doddy's own actions ("Save to Doddy", "Ask Doddy") as App Intents
so Siri and Shortcuts can use them.

## 5. Proposed build order (each step usable on its own)

| Step | What you get | Needs from you |
|---|---|---|
| **V1 Voice in the app** | Tap → talk to Doddy (OpenAI realtime), text fallback, stop/interrupt; Doddy can search and (after you confirm) save memories | Provider + API account, token-server host, monthly spend cap |
| **V2 Shortcut + guided setup** | "Talk to Doddy" App Shortcut, Action Button / Control Center control, Back Tap step cards with tap test | — |
| **V3 Dynamic Island** | Live Activity with listening/speaking state and Pause/Stop while you use other apps | Apple Developer account, real iPhone for testing |
| **V4 iPhone tools** | One at a time with confirm + receipt: Reminders → Calendar → timers/alarms → "run my Shortcut" → weather/places | Which tools first |

## 6. Decisions needed before V1
1. **Provider:** start with OpenAI `gpt-realtime-2.1` and do the bake-off vs mini and Gemini 3.8 Live? (recommended)
2. **Token server:** where to host it (e.g. a small serverless function). This is the first paid/cloud piece of the project.
3. **Budget:** monthly spend cap and per-user minute limit.
4. **Privacy:** EU data residency project; what Doddy may send (proposal: only the conversation + memories it searched for, never the whole memory store).
5. **Languages:** Polish and English at launch?

## Sources
- OpenAI pricing: https://developers.openai.com/api/docs/pricing
- OpenAI Realtime over WebRTC (client secrets, GPT-Live): https://developers.openai.com/api/docs/guides/realtime-webrtc
- OpenAI GPT-Live delegation and tools: https://developers.openai.com/api/docs/guides/live-delegation
- OpenAI EU data residency: https://openai.com/blog/introducing-data-residency-in-europe
- Gemini API pricing: https://ai.google.dev/gemini-api/docs/pricing
- Gemini Live languages: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/live-api/configure-language-voice
- Latency comparisons: https://vadimall.com/posts/openai-realtime-vs-gemini-live-vs-pipecat-voice-ai-typescript , https://zylos.ai/research/2026-07-19-realtime-voice-api-protocol-adaptation/
- AudioRecordingIntent: https://developer.apple.com/documentation/appintents/audiorecordingintent
- Background start limitation (forum): https://developer.apple.com/forums/thread/815725
- Third-party side-button assistant (Japan only): https://appleinsider.com/articles/25/11/17/ios-262-side-button-virtual-assistant-settings-were-actually-meant-for-japan
- Siri AI not in EU on iOS 27: https://mjtsai.com/blog/2026/06/10/no-siri-ai-in-eu/
- Foundation Models tool calling (iOS 27): https://www.blakecrosley.com/blog/foundation-models-tool-calling-ios-27
- Back Tap: https://support.apple.com/guide/iphone/back-tap-iphaa57e7885/ios
