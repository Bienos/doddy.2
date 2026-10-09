# V1 status — voice inside the app (ElevenLabs Agents)
Date: 2026-10-08. Owner instruction: build with ElevenLabs (owner has the Creator plan).

## ElevenLabs setup (done via the ElevenLabs connector)
| Item | Value |
|---|---|
| Agent | "Doddy (dev prototype)" `agent_0501m4et27vyeawrwqfdxxfszfa6`, tags doddy/dev |
| Mode | **Public (no auth)**: development only, on the owner's own phone |
| LLM | gemini-2.5-flash, temperature 0.3, timezone Europe/Warsaw |
| Speech | Scribe realtime (in), eleven_v4_turbo (out), voice **Josh – Conversational Agent** `ZoiZ8fuDWInAcwPXaVeq` (ElevenLabs Voice Library professional voice, English/American, young male, made for dialogue; added to the account's My Voices and set 2026-10-08, agent version `agtvrsn_2401m4eyzmrwepct8ftekgsqtv3z`; the Polish preset has no voice override, so one voice serves both languages); max 10 min per conversation |
| Languages | English default, Polish preset ("Hej, tu Doddy. Co słychać?"), automatic language detection |
| Client tools | `search_memories(query)` `tool_6701m4et16pveywrpymdw3h3v0wp`, `save_memory(text)` `tool_9401m4et17pfe598c1wmvdhpwhcv` (both expect a response) |
| Prompt | AI disclosure, short spoken replies, strict memory rules (answer only from tool results, say "couldn't find it", never claim a save without "saved"), no reminders/messages/other apps. Since 2026-10-09 (version `agtvrsn_1401m4f01rzheztb1sp89ek1wy14`): before `save_memory` runs, Doddy says only "Confirm on screen if I should save this." / "Potwierdź na ekranie, jeśli mam to zapisać." (also in the tool description) |

## App
- Home → **Talk to Doddy** opens `VoiceView` (foreground only). It ends when the screen closes or the app goes to the background.
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

## Before anyone else uses it
1. Turn on agent authentication and add a small token server (`conversationToken` path in the SDK).
2. Voice chosen (owner instruction 2026-10-08): Voice Library voice Josh – Conversational Agent, already in My Voices. Judge Polish pronunciation on a device and check the voice's library licence terms before release.
3. Decide on data handling with ElevenLabs (zero retention and EU residency are Enterprise-only).
