# V1 status — voice inside the app (ElevenLabs Agents)
Date: 2026-10-08. Owner instruction: build with ElevenLabs (owner has the Creator plan).

## ElevenLabs setup (done via the ElevenLabs connector)
| Item | Value |
|---|---|
| Agent | "Doddy (dev prototype)" `agent_0501m4et27vyeawrwqfdxxfszfa6`, tags doddy/dev |
| Mode | **Public (no auth)**: development only, on the owner's own phone |
| LLM | gemini-2.5-flash, temperature 0.3, timezone Europe/Warsaw |
| Speech | Scribe realtime (in), eleven_v4_turbo (out), default voice for now; max 10 min per conversation |
| Languages | English default, Polish preset ("Hej, tu Doddy. Co słychać?"), automatic language detection |
| Client tools | `search_memories(query)` `tool_6701m4et16pveywrpymdw3h3v0wp`, `save_memory(text)` `tool_9401m4et17pfe598c1wmvdhpwhcv` (both expect a response) |
| Prompt | AI disclosure, short spoken replies, strict memory rules (answer only from tool results, say "couldn't find it", never claim a save without "saved"), no reminders/messages/other apps |

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

## Not verified (needs the Mac and a real iPhone)
App compile with the SDK; microphone prompt; a real conversation in English and Polish; that client tool calls arrive (the agent's `client_events` list does not name `client_tool_call`; SDK and docs suggest they are always sent); the save confirmation round-trip within the 90 s tool timeout; ending on background.

## Before anyone else uses it
1. Turn on agent authentication and add a small token server (`conversationToken` path in the SDK).
2. Pick or design Doddy's own voice (library voices must first be added to the account).
3. Decide on data handling with ElevenLabs (zero retention and EU residency are Enterprise-only).
