# V1 status — voice inside the app (ElevenLabs Agents)
Date: 2026-10-08. Live check: 2026-10-09 (read-only, against the live ElevenLabs agent). Owner instruction: build with ElevenLabs (owner has the Creator plan).

## ElevenLabs setup (live state at the 2026-10-09 check)
| Item | Value |
|---|---|
| Agent | "Doddy (dev prototype)" `agent_0501m4et27vyeawrwqfdxxfszfa6`, tags doddy/dev |
| Mode | **Public (no auth)**: development only, on the owner's own phone |
| LLM | gemini-3.5-flash, temperature 0.5, timezone Europe/Warsaw (the 10-08 entry said gemini-2.5-flash / 0.3; the live agent changed after that) |
| Speech | Scribe realtime (in), eleven_v4_turbo (out), default voice for now; max 10 min per conversation |
| Languages | English default, Polish preset ("Hej, tu Doddy. Co słychać?"), automatic language detection |
| Limits | Concurrency unlimited (-1); daily cap 100,000 calls; recording on; retention not set (-1); all guardrails off |
| Client tools the app answers | `search_memories(query)` `tool_6701m4et16pveywrpymdw3h3v0wp`, `save_memory(text)` `tool_9401m4et17pfe598c1wmvdhpwhcv` (both expect a response) |
| Other tools on the agent (kept) | Client tools `read_calendar`, `create_calendar_event`, `create_reminder`, `lookup_contact`: the app has no handler, so it replies "not available yet". Webhook tools `geocode_place`, `get_weather` (Open-Meteo) and `wikipedia_search`, `wikipedia_summary` (Wikipedia): ElevenLabs calls these directly, not the phone. |
| Prompt | AI disclosure, short spoken replies, strict memory rules (answer only from tool results, say "couldn't find it", never claim a save without "saved"). It also describes calendar, reminder and contact tools as usable "in the app under Settings, Connections"; that screen does not exist yet. |
| Prompt placeholders | `{{saved_notes}}`, `{{saved_notes_count}}`, `{{saved_notes_truncated}}`, `{{recent_conversations}}` have default text. The app does not send them, so the agent always sees "did not send any saved notes". |

## App
- Home → **Talk to Doddy** opens `VoiceView` (foreground only). It ends when the screen closes or the app goes to the background.
- `VoiceSessionController` uses the ElevenLabs Swift SDK 3.3.1 (`ElevenLabs.startConversation(agentId:…)`). Status (connecting, listening, thinking, speaking, ended) comes from real SDK events.
- `search_memories` runs the local SQLite recall and returns only stored text (`VoiceToolReply.search`).
- `save_memory` shows a **Save this note?** card; nothing is stored until the user taps Save. The agent is told saved, declined or failed.
- Microphone denied → explanation + Open Settings; the rest of the app keeps working.
- Settings → Voice: the agent ID (prefilled with the dev agent). Privacy rows say "Only while talking (ElevenLabs)". The privacy note now also says that weather and fact lookups are made by ElevenLabs: place name and coordinates to Open-Meteo, search words to Wikipedia.
- Privacy manifest declares audio data and other user content (app functionality, not linked, no tracking).

## Verified
Linux: core package 30 tests passed in an earlier session (incl. tool parsing and replies), guard passed (and fails on audio code outside `Features/Voice`), all Swift files syntax-parse, XcodeGen resolves the project with the ElevenLabs package. No Swift toolchain was available in the 2026-10-09 session, so nothing was recompiled or retested then.

Live check (2026-10-09, ElevenLabs connector, read-only):
- At least 10 conversations from today were started by the app (`swift_sdk`), with normal disconnects. Tool calls seen: `language_detection`, `wikipedia_search`, `wikipedia_summary`, `geocode_place`, `get_weather`. One conversation switched to Polish.
- Tool totals: `search_memories` 4 calls, `save_memory` 2 calls. The per-call results were not visible through the connector, so whether the save round-trip completed is still open.

## Not verified (needs the Mac and a real iPhone)
App compile with the SDK; microphone prompt; a real conversation in English and Polish on the owner's device (server records show a Polish switch); that client tool calls arrive (the agent's `client_events` list does not name `client_tool_call`; SDK and docs suggest they are always sent); the save confirmation round-trip within the 90 s tool timeout; ending on background.

## Open items
1. **Dynamic variables (saved notes in the prompt):** not implemented. The ElevenLabs Swift SDK docs for 3.3.1 do not document a way to pass dynamic variables, and no Swift toolchain was available to check the source. Verify the `ConversationConfig` API in Xcode Quick Help before writing code, or remove the placeholder block from the prompt.
2. **Calendar, reminder and contact tools:** kept on the agent, but the app does not implement them. Building them needs EventKit or Contacts permissions, which the guard script (ADR-037) currently forbids. That needs an owner decision.
3. **Prompt text:** the "Settings, Connections" wording refers to a screen that does not exist.

## Before anyone else uses it
1. Turn on agent authentication and add a small token server (`conversationToken` path in the SDK).
2. Lower concurrency and daily limits, and turn on the prompt-injection guardrail.
3. Pick or design Doddy's own voice (library voices must first be added to the account).
4. Decide on data handling with ElevenLabs (zero retention and EU residency are Enterprise-only).
