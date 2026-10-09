# V1 status — voice inside the app (ElevenLabs Agents)
Date: 2026-10-08. Owner instruction: build with ElevenLabs (owner has the Creator plan).

## ElevenLabs setup (done via the ElevenLabs connector)
| Item | Value |
|---|---|
| Agent | "Doddy (dev prototype)" `agent_0501m4et27vyeawrwqfdxxfszfa6`, tags doddy/dev |
| Mode | **Public (no auth)**: development only, on the owner's own phone |
| LLM | gemini-3.5-flash, temperature 0.5, timezone Europe/Warsaw (was gemini-2.5-flash / 0.3 until 2026-10-09, ADR-052) |
| Speech | Scribe realtime (in), eleven_v4_turbo (out), voice `oDULUm0GMltHA6mVZkWh` (owner pick 2026-10-09, ADR-051; before that Josh `ZoiZ8fuDWInAcwPXaVeq`, ADR-038); one voice for both languages; max 10 min per conversation |
| Data kept by ElevenLabs | Audio recording **on**, retention **unlimited**, transcripts and audio **not** auto-deleted, zero-retention off. Kept as is by owner decision (ADR-057) |
| Languages | English default, Polish preset ("Hej, tu Doddy. Co słychać?"), automatic language detection |
| Tools | Client (run on the phone): `search_memories(query)` `tool_6701m4et16pveywrpymdw3h3v0wp`, `save_memory(text)` `tool_9401m4et17pfe598c1wmvdhpwhcv` (both expect a response). Webhooks (run from ElevenLabs servers, keyless, since 2026-10-09): `geocode_place` `tool_5701m4f28p90fm186x0zhn54sy71` and `get_weather` `tool_0601m4f25r0bfdhtb12v4g21x8ac` (Open-Meteo), `wikipedia_search` `tool_0901m4f25swxft090rnfkczn5jhj` and `wikipedia_summary` `tool_1101m4f25rx2fx7ttcempcvx8s89` (pl/en) |
| Prompt | AI disclosure, short spoken replies, strict memory rules (answer only from tool results, say "couldn't find it", never claim a save without "saved"), no reminders/messages/other apps. Since 2026-10-09 (version `agtvrsn_1401m4f01rzheztb1sp89ek1wy14`): before `save_memory` runs, Doddy says only "Confirm on screen if I should save this." / "Potwierdź na ekranie, jeśli mam to zapisać." (also in the tool description) |

## App
- Home → **Talk to Doddy** opens `VoiceView`. It ends when the screen closes; since V3 it keeps running in the background with a Dynamic Island (`V3_ISLAND_STATUS.md`).
- `VoiceSessionController` uses the ElevenLabs Swift SDK 3.3.1 (`ElevenLabs.startConversation(agentId:…)`). Status (connecting, listening, thinking, speaking, ended) comes from real SDK events.
- `search_memories` runs the local SQLite recall and returns only stored text (`VoiceToolReply.search`).
- `save_memory` shows a **Save this note?** card; nothing is stored until the user taps Save. The agent is told saved, declined or failed.
- Microphone denied → explanation + Open Settings; the rest of the app keeps working.
- Settings → Voice: the agent ID (prefilled with the dev agent). Privacy rows now say "Only while talking (ElevenLabs)".
- Privacy manifest declares audio data and other user content (app functionality, not linked, no tracking).

## Verified
Linux: core package 30 tests pass (incl. tool parsing and replies), guard passes (and fails on audio code outside `Features/Voice`), all Swift files syntax-parse, XcodeGen resolves the project with the ElevenLabs package.

**iPhone, 2026-10-09, owner's first real conversation** (owner report + the ElevenLabs conversation log, read through the connector):
- Conversation `conv_3501m4ezj8s4e4tbaqpt3xkqfj80`, source `swift_sdk 3.3.1`, agent version `agtvrsn_2401m4eyzmrwepct8ftekgsqtv3z` (voice Josh), 79 s, 18 messages, ended by the client closing cleanly (`Client disconnected: 1000`). So the app compiles with the SDK, gets the microphone, connects and holds a conversation.
- Started in English, switched to Polish through the built-in language-detection tool, Polish replies were spoken with the Josh voice.
- **Client tool calls reach the phone.** `save_memory` was called with "Moje urodziny są jutro."; the phone answered `saved: "Moje urodziny są jutro." (saved 2026-10-09T02:05:06+02:00)` 5.7 s later, i.e. after the on-screen Save tap and well inside the 90 s tool timeout, and the agent then confirmed the save. This closes the `client_tool_call` question above.
- Per turn: LLM first token ≈ 0.8–1.0 s, first audio after the user stops speaking ≈ 1.3–2.2 s, TTS first byte ≈ 0.1 s.
- Cost of this conversation: 274 credits ≈ $0.05 (239 voice + 35 LLM credits), i.e. about $0.04 per minute all-in on the Creator tier.

**iPhone, same evening, four more conversations (02:05–02:10 local, agent version `agtvrsn_2401…`, before the prompt changes below):**
- **`search_memories` reaches the phone and answers from the local store** in about 0.2 s (4 executions: "parcel number", "about me", "code", "star code"). Every reply was an honest "No saved note matched …" and Doddy said he couldn't find it, never guessed. The recall path works end to end.
- **But recall was useless in practice**, for two reasons that are not app bugs: the user asked in English ("what code you have saved?") while the note had been saved in Polish ("Kod: pięć, sześć, siedem, osiem."), and the tool's query hint said "in the user's language", so the word-based search never saw "kod"; and the spoken code was saved as number words, which no later query matches. Also, "Doddy, send a parcel to the locker" was correctly refused (not built).
- The pre-save line before the change was "[happy] Okay, I'll save that code for you now." (confirms the observation below).

## Not verified yet
- A recall that actually *finds* a note (every search so far ran before the bilingual-keyword fix). Suggested check: "kiedy mam urodziny?" and "what's the locker code?" after saving one with digits.
- Interruption while Doddy speaks, ending when the app goes to the background, and the microphone-denied path (owner to run; the first conversation did end cleanly from the client side).
- The Mac build/test output (`scripts/ci.sh`) is not yet recorded in the repo.
- Note: ElevenLabs rejects an agent voice that is not in the account's My Voices (`voice_not_found`), so a Voice Library voice must be added there first (observed 2026-10-08).

## Observations from the first conversation (decisions, not bugs)
- **Pre-tool speech (changed 2026-10-09, owner approved).** In the first conversation Doddy said "Zapisuję to dla ciebie" (I am saving this for you) before the Save card appeared, which reads oddly if the user taps Don't save. The prompt and the `save_memory` tool description now tell Doddy to say only "Confirm on screen if I should save this." / "Potwierdź na ekranie, jeśli mam to zapisać." before the tool runs (agent version `agtvrsn_1401m4f01rzheztb1sp89ek1wy14`). Not yet heard on a device.
- **Retention.** Audio and transcript, including the user's first name, are kept on ElevenLabs indefinitely (`retention_days: -1`, `record_voice: true`). The retention decision in the list below is still open.
- **Relative dates.** The saved note says "tomorrow"; the app stores the capture time, so it stays interpretable, but recall does not resolve dates.
- **Bilingual search and digits (changed 2026-10-09).** The `search_memories` tool and the prompt now tell Doddy to pass key words in both Polish and English (e.g. "kod code paczkomat parcel"), numbers as digits, and to retry once with a different word; `save_memory` now writes numbers, codes, dates and times as digits in the note. Agent version `agtvrsn_2701m4f1e2krfnysbc5w01agz5d2`. Not yet exercised on a device. The app's search itself is unchanged (prefix-OR over folded terms, `DECISIONS.md` ADR-027).

## Knowledge (2026-10-09, personal single-user build; owner instruction "design it for me only")
Owner's picks: saved notes always, memory across conversations, current info from the web. Profile document declined.

| Piece | What it does | Where |
|---|---|---|
| Saved notes at start | The app renders every saved note (newest first, 6,000-character budget, says when cut) and hands it to the agent as dynamic variables `saved_notes`, `saved_notes_count`, `saved_notes_truncated`; the prompt treats the list as memory and falls back to `search_memories` when the list is cut | `VoiceContext.savedNotes` (DoddyCore, tested), `VoiceSessionController.start` |
| Recent conversations | ElevenLabs user memory is **not available on the Creator plan** (`feature_not_available`), so the app keeps the transcript lines of the last 10 conversations as JSON in Application Support/Conversations (file-protected until first unlock), and sends them as `recent_conversations` (4,000-character budget, newest kept). Settings: "Remember recent conversations" toggle (on by default) and "Forget remembered conversations". Logs never become memory records | `ConversationLogStore`, `VoiceContext.recentConversations` (tested) |
| Weather | `geocode_place` (Open-Meteo geocoding) then `get_weather` (Open-Meteo forecast, current + 3 days); keyless, no account | ElevenLabs webhook tools |
| Facts | `wikipedia_search` then `wikipedia_summary`, Polish or English; keyless | ElevenLabs webhook tools |
| Identity | A random, stable per-install id is sent as the conversation `user_id` | `PreferenceKey.voiceUserID` |
| Agent | Prompt rewritten for the owner (knowledge sections, six tools attached), placeholders for the four variables so a conversation without them still starts, `trust_context: high`; version `agtvrsn_6601m4f2cnn7fw7a0z9f9r1bsqre` | ElevenLabs |

Privacy for this personal build, stated in Settings, Home and the voice screen: every saved note and the last conversations leave the phone at the start of each conversation; weather and Wikipedia lookups are made by ElevenLabs' servers. Retention on ElevenLabs is still the default (forever). General web search is not wired (it needs a paid key); the prompt says today's news and prices cannot be checked.

Not verified: app compile; that the dynamic variables arrive (the prompt renders the placeholders otherwise); the weather tools end to end (the Open-Meteo forecast host could not be reached from the authoring sandbox because of its TLS proxy; geocoding and Wikipedia responded); how Gemini handles a prompt with many notes; the log store's file protection on device. Suggested checks: ask "co wiesz o mnie?", "jaka jest pogoda w Warszawie jutro?", "sprawdź na Wikipedii, kim jest Maria Skłodowska-Curie", then end and start a new conversation and refer back to it.

## 2026-10-09 agent changes (owner: "use this voice", "it is not smart, can't answer much")
- The owner reports the voice feature works in the app.
- Voice `oDULUm0GMltHA6mVZkWh` (ADR-051).
- Cause found in the log (`conv_0401m4fycdz3f65bq81yzrya3zp9`, a build without the knowledge variables): asked for the weather, Doddy said it couldn't; the calendar edit for V4a had replaced the agent's prompt and tool list and dropped the weather/Wikipedia tools and knowledge sections above. Re-attached, LLM upgraded to gemini-3.5-flash, prompt loosened for general knowledge with the knowledge sections kept (ADR-052, version `agtvrsn_0901m4fynwpdfv0agh5qqn1ytyxd`). Ten tools now: 6 phone (memory, calendar, reminders, contacts) + 4 webhooks (weather, Wikipedia).
- Suggested checks: "what's the weather in Warsaw tomorrow?", "who was Maria Skłodowska-Curie?", "explain how a mortgage works", "how are you?".

## Before anyone else uses it
1. Turn on agent authentication and add a small token server (`conversationToken` path in the SDK).
2. Voice picked by the owner (`oDULUm0GMltHA6mVZkWh`, ADR-051). Judge Polish pronunciation on a device and check the voice's licence terms before release.
3. Decide on data handling with ElevenLabs (zero retention and EU residency are Enterprise-only).
