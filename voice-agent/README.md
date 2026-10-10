# Doddy voice agent — spec in OpenAI Realtime shape

Owner decision 2026-10-09 (ADR-058): Doddy runs on **ElevenLabs Agents**, but everything that
defines Doddy is kept here in **OpenAI Realtime** form, so moving to OpenAI Realtime later means
adding one adapter, not rewriting the app or the agent.

| File | What it is | ElevenLabs today | OpenAI Realtime later |
|---|---|---|---|
| `instructions.md` | Doddy's system prompt with `{{placeholders}}` | Agent prompt; placeholders are dynamic variables the app passes at `startConversation` | `session.instructions`, rendered on the phone by `RealtimeInstructions.render` |
| `tools.json` | 10 function tools (`type`, `name`, `description`, `parameters`) + `x_doddy` | Client tools (`runs_on: phone`) and webhook tools (`runs_on: web`) | `session.tools` (drop `x_doddy`); every call comes to the app |
| `session.json` | First message, languages, variables, turn-taking, per-provider settings | Agent settings | `session.update` body |

## Source of truth and syncing

1. Change the files here first.
2. `python3 -I scripts/voice_agent_spec.py check` (also runs in `scripts/ci.sh`).
3. Push to ElevenLabs: `python3 -I scripts/voice_agent_spec.py elevenlabs` prints each tool in
   ElevenLabs form; apply them (and the prompt) to agent `agent_0501m4et27vyeawrwqfdxxfszfa6`
   through the ElevenLabs connector or dashboard. The tool ids are in `x_doddy.elevenlabs_tool_id`.
4. Check for drift: export the live tools (`agents_list_tools` for the agent) and prompt into
   `{"prompt": "...", "tools": [...]}` and run `voice_agent_spec.py compare EXPORT.json`.

Editing the agent in the ElevenLabs dashboard without updating these files is drift; the compare
step catches it. Last synced 2026-10-10 (agent version `agtvrsn_1601m4k85xy5ew7awn6n9yxwas7v`, ADR-198: `remind_me_about_note`; before that `agtvrsn_5801m4k5544wevk9bz7wezwneh88`, ADR-177: AI disclosure line; before that `agtvrsn_3401m4k47e2revvv01sk7xv1tb26`, ADR-173: `web_search` added; before that `agtvrsn_5801m4jtvazveprbj3znhn66j4tt`, ADR-129): `instructions.md` is the live prompt verbatim, including the `{{doddy_personality}}` and `{{user_profile}}` sections, and `tools.json` lists all 21 live tools (22 since ADR-198) (the four Connections tools that had drifted were added together with the six online-account tools; see `docs/integrations/ONLINE_ACCOUNTS.md`). Previous version, for rollback: `agtvrsn_5801m4jtvazveprbj3znhn66j4tt` (before web search).

**Applied to the live agent 2026-10-10 (ADR-129):** the M4 Reminders wording (ADR-126) and the calendar
date rules (ADR-127, ADR-128) in `create_reminder`, `create_calendar_event` and the prompt. The opening line
of `instructions.md` is the owner's dashboard edit, copied back so the spec matches the live prompt.

**Applied to the live agent 2026-10-10 (ADR-191):** the opening line again says plainly that Doddy is an AI
when asked (the dashboard edit had told it to give a "vague answer"). Only that line was changed, on live
version `agtvrsn_3401m4k47e2revvv01sk7xv1tb26` → `agtvrsn_5801m4k5544wevk9bz7wezwneh88`; tools untouched.

**Applied to the live agent 2026-10-10 (ADR-198):** new client tool `remind_me_about_note`
(`tool_7401m4k84jjgf1ctk26vj03kextq`) attached next to the 21 existing tools, and two prompt lines (its tool
bullet and one reminder rule). Version `agtvrsn_1401m4k5nha9ffv81j7c6m6sze2n` → `agtvrsn_1601m4k85xy5ew7awn6n9yxwas7v`;
compare run against the new tool and the full prompt (no drift). For rollback, the previous version has 21 tools.

**Applied to the live agent 2026-10-10 (ADR-205):** `remind_me_about_note` (`tool_7401m4k84jjgf1ctk26vj03kextq`)
gained the `repeat` parameter and one sentence in its description, updated in place; the prompt and the agent's
tool list are unchanged.

**Applied to the live agent 2026-10-10 (ADR-206): European languages.**
- **Language presets:** 36 non-English presets (the `languages` list in `session.json`), each overriding only the first message. ElevenLabs refused Basque (`eu`) and Albanian (`sq`), so they are left out. The built-in `language_detection` tool was already on with `only_at_conversation_start: false`; with the presets it switches between all of them mid-conversation.
- **Prompt:** three lines changed: the reply language, the Wikipedia language code, and the languages for note search.
- **Wikipedia tools:** `wikipedia_search` and `wikipedia_summary` accept the same codes. Summary redirects stay limited to the 20 largest editions, because ElevenLabs allows at most 20 redirect domains.
- **Versions:** `agtvrsn_2801m4knwd04fxfbj25wat868jtp` → `agtvrsn_2301m4kpwmr1fcers0b8vf7th8qr` (presets) → `agtvrsn_7101m4kpz26mf3p8yysmx0y4z6cz` (prompt).
- **Known drift, not from this line:** the live agent also has `propose_plan` (`tool_3001m4knv27zfw09afmn7sjamfcp`) and its prompt line from ADR-204 on the `claude/loving-dirac-uuxoux` line. Both were kept as they are. The live first message is the owner's dashboard text "Hey, it's Doddy. what's up?", now copied into `session.json`.

## App side (DoddyCore `RealtimeVoice.swift`)

- `RealtimeEvent`: what any provider reports, named after Realtime server events
  (`sessionReady`, `userSpeechStarted/Stopped`, `userTranscript`, `responseStarted`,
  `audioStarted`, `assistantTranscript`, `functionCall`, `responseDone`, `error`, `ended`).
- `RealtimeVoiceSession`: the protocol a provider adapter implements: `start(config)`,
  `send(functionOutput)`, `setMicrophoneMuted`, `end()`.
- `RealtimeConversationState`: turns events into the voice screen's phase, transcript and open
  tool calls, identically for both providers.
- `RealtimeToolCatalog.unhandledPhoneTools`: phone tools the app cannot run (each would leave
  the model waiting until its timeout).

**Not wired yet:** the voice screen still talks to the ElevenLabs SDK directly. The
ElevenLabs adapter (`ElevenLabsRealtimeSession`) and the switch of `VoiceSessionController` to
`RealtimeVoiceSession` come after the parallel voice branches are merged (calendar, knowledge,
Island), so the rewrite happens once on the combined code.

ElevenLabs SDK → event mapping for that adapter:

| ElevenLabs Swift SDK | RealtimeEvent |
|---|---|
| `onAgentReady` | `.sessionReady` |
| `onAgentStateChange(.thinking)` | `.responseStarted` |
| `onAgentStateChange(.speaking)` | `.audioStarted` |
| `onAgentStateChange(.listening)` | `.responseDone` |
| `onUserTranscript` | `.userTranscript` |
| `onAgentResponse` / `onAgentResponseCorrection` | `.assistantTranscript` / `.assistantTranscriptCorrected` |
| `onUnhandledClientToolCall` | `.functionCall` (`toolCallId`, `toolName`, parameters as JSON) |
| `sendToolResult(for:result:isError:)` | `send(RealtimeFunctionOutput)` |
| `onError` / `onDisconnect` | `.error` / `.ended` |

ElevenLabs does not expose speech-start/stop events, so `userSpeechStarted/Stopped` only come
from the OpenAI adapter; the screen works without them.

## What moving to OpenAI Realtime needs (not built)

1. A token server that mints short-lived client secrets (the API key never ships in the app).
2. `OpenAIRealtimeSession`: WebRTC connection, `session.update` from `voice_agent_spec.py openai`
   with instructions rendered on the phone, events mapped as named above.
3. Run the four `web` tools (weather, Wikipedia) in the app or on the token server from
   `x_doddy.http`, because OpenAI sends every function call to the client.
4. Pick a voice. OpenAI has preset voices only; Doddy's ElevenLabs voice does not carry over.
5. Bake-off on the same Polish/English phrases before switching (latency, interruptions, cost).

## Speed settings (2026-10-09)

| Setting | Before | Now | Why |
|---|---|---|---|
| Turn eagerness | normal | **eager** | Replies sooner after the user pauses (≈ Realtime `semantic_vad` eagerness high). May cut in on long pauses. |
| Speculative turn | on | on | Starts the reply before the turn is certain. |
| Reasoning / thinking budget | — | — | Not supported for `gemini-3.5-flash` (ElevenLabs rejects the setting). |
| Background voice detection | off | **on** | A video playing nearby was transcribed as one endless user turn, so Doddy never got to reply (conversation conv_6101m4g87cmjefgvjek1gdpxvqmp). Filters voices that are not the user. |
| Voice model | eleven_v4_turbo | unchanged | Changing it changes how the chosen voice sounds; compare on device first. |

## Phone agent (`phone/`, S2)

`voice-agent/phone/` defines the separate ElevenLabs agent **"Doddy (phone)"** that answers and
places phone calls through the Twilio number (ADR-152, ADR-172). Same three files, same rules:

| File | What it is |
|---|---|
| `phone/instructions.md` | The phone prompt, with `{{doddy_caller}}`, `{{doddy_direction}}`, `{{doddy_memory}}`, `{{doddy_pin}}` filled by the messaging server's call-start webhook |
| `phone/tools.json` | `verify_pin`, `search_memories`, `save_note`: webhooks to `server/messaging`. Instead of a fixed url they give `x_doddy.http.base` (the `PUBLIC_BASE_URL` env name), a `path_template` and `body` parameters; headers reference the workspace secret `doddy_tool_secret` and the secret variable `secret__doddy_session` |
| `phone/session.json` | First message, LLM, privacy (no audio recording, 30-day transcripts), placeholders, the call-start webhook path |

- Check: `python3 -I scripts/voice_agent_spec.py check --agent phone` (in `scripts/ci.sh`).
- Create the agent: `server/messaging/scripts/setup-phone-agent.mjs` reads these files; `--dry-run` prints every request.
- Drift: export the live phone agent's prompt and tools as above and run `voice_agent_spec.py compare EXPORT.json --agent phone`.
- Status: **not created yet** (needs the deployed messaging server, a Twilio number and the owner's go-ahead).

