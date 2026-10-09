# V1 status — voice inside the app (ElevenLabs Agents)
Date: 2026-10-08. Updated 2026-10-09 after a read-only live check of the ElevenLabs agent, and again when the Connections tools were built. Owner instruction: build with ElevenLabs (owner has the Creator plan).

## ElevenLabs setup (live state at the 2026-10-09 check)
| Item | Value |
|---|---|
| Agent | "Doddy (dev prototype)" `agent_0501m4et27vyeawrwqfdxxfszfa6`, tags doddy/dev |
| Mode | **Public (no auth)**: development only, on the owner's own phone. The owner decided on 2026-10-09 not to lock it down yet; it must change before anyone else uses it. |
| LLM | gemini-3.5-flash, temperature 0.5, timezone Europe/Warsaw (the 10-08 entry said gemini-2.5-flash / 0.3; the live agent changed after that) |
| Speech | Scribe realtime (in), eleven_v4_turbo (out), default voice for now; max 10 min per conversation |
| Languages | English default, Polish preset ("Hej, tu Doddy. Co słychać?"), automatic language detection |
| Limits | Concurrency unlimited (-1); daily cap 100,000 calls; recording on; retention not set (-1); all guardrails off |
| Prompt | AI disclosure, short spoken replies, strict memory rules, and a section on calendar, reminders and contacts that says they work "in the app under Settings, Connections". That section is now real. |
| Prompt placeholders | `{{saved_notes}}`, `{{saved_notes_count}}`, `{{saved_notes_truncated}}`, `{{recent_conversations}}` have default text. The app does not send them yet, so the agent always sees "did not send any saved notes" (open item 1). |

### Tools on the agent and what the app does with each
| Tool | Runs on | App behaviour |
|---|---|---|
| `search_memories` `tool_6701m4et16pveywrpymdw3h3v0wp` | phone | Searches local notes; returns stored text only. Always on. |
| `save_memory` `tool_9401m4et17pfe598c1wmvdhpwhcv` | phone | Card with **Save**; nothing stored until the tap. Always on. |
| `read_calendar` | phone, Calendar toggle | Returns titles and times for today, tomorrow, the week, or a range. Nothing is added. |
| `create_calendar_event` | phone, Calendar toggle | Card with **Add**; added only after the tap, then read back to verify. |
| `create_reminder` | phone, Reminders toggle | Card with **Add**; added only after the tap, then read back to verify. |
| `lookup_contact` | phone, Contacts toggle | Agent gets names only; phone numbers and emails show on screen only. |
| `geocode_place`, `get_weather` | ElevenLabs → Open-Meteo | Cannot be switched off from the phone. Place name and coordinates go to Open-Meteo. |
| `wikipedia_search`, `wikipedia_summary` | ElevenLabs → Wikipedia | Cannot be switched off from the phone. Search words go to Wikipedia. |

A connection that is off, or whose iOS permission is refused, returns "isn't connected" to the agent, which tells the user to turn it on in Settings, Connections.

## App
- Home → **Talk to Doddy** opens `VoiceView` (foreground only). It ends when the screen closes or the app goes to the background.
- `VoiceSessionController` uses the ElevenLabs Swift SDK 3.3.1 (`ElevenLabs.startConversation(agentId:…)`). Status (connecting, listening, thinking, speaking, ended) comes from real SDK events.
- One card at a time: a note, an event or a reminder waits for its tap. A second proposal while one waits is refused, so every tool call still gets an answer.
- Settings → **Connections**: Calendar, Reminders and Contacts toggles, all off by default. Turning one on asks iOS for permission; if refused, the toggle stays off and Settings offers "Open iPhone Settings".
- EventKit and Contacts code lives only in `DoddyApp/Infrastructure/Connections/DeviceConnections.swift`. The guard script enforces that.
- Settings → Voice: the agent ID (prefilled with the dev agent). The privacy note says that notes, calendar entries and contact names used in a conversation go to ElevenLabs, and that weather and fact lookups go to Open-Meteo and Wikipedia.
- Privacy manifest declares audio data, other user content (calendar and reminder text), and name (contact names sent to the agent). All are app functionality, not linked, no tracking. Confirm these in App Store Connect.
- Permission strings: microphone, calendars (full access), reminders (full access), contacts. Nothing else.

## Verified
- Linux, Swift 6.0.3 (2026-10-09): `DoddyCoreTests` and `DoddyDesignTokensTests` pass, 40 tests, 0 failures. The GRDB persistence target was left out of the scratch copy because it needs a GitHub clone this environment can't make. Calendar, reminder and contact parsing, date validation and reply wording are covered by `VoiceToolsTests`.
- Linux: the capability guard passes (EventKit and Contacts only in `Infrastructure/Connections`; four permission keys only).
- `PrivacyInfo.xcprivacy` and the Info keys in `project.yml` are well-formed.
- Linux: `swiftc -parse` passes for every changed Swift file. This checks syntax only.
- Live check (2026-10-09, ElevenLabs connector, read-only): at least 10 conversations from today were started by the app (`swift_sdk`), with normal disconnects. Tool calls seen: `language_detection`, `wikipedia_search`, `wikipedia_summary`, `geocode_place`, `get_weather`. One conversation switched to Polish.
- Tool totals on the live agent: `search_memories` 4 calls, `save_memory` 2 calls. Per-call results were not visible through the connector.

## Not verified (needs the Mac and a real iPhone)
- **The iOS app has not been compiled with this code.** The EventKit, Contacts, SwiftUI and ElevenLabs SDK code has only been syntax-checked. Run `make project` and the build on a Mac first.
- EventKit and Contacts permission prompts and what happens on refusal; real event and reminder adds, and whether the read-back check passes; contact lookup on a device with real contacts.
- Microphone prompt; a real conversation in English and Polish on the owner's device.
- That client tool calls arrive (the agent's `client_events` list does not name `client_tool_call`; SDK and docs suggest they are always sent).
- The save and add confirmation round-trip within the 90 s tool timeout; ending on background.

## Open items
1. **Dynamic variables (saved notes in the prompt):** not implemented. The SDK 3.3.1 Swift docs do not document a way to pass them, and no Swift toolchain was available to check the source. Before writing code, check `ConversationConfig` in Xcode Quick Help. Filling the placeholders would also send every saved note to ElevenLabs at the start of each conversation, not only when Doddy searches. The Settings text would have to say so.
2. **Not added (DECISIONS 039):** timers and alarms (AlarmKit needs iOS 26 and a new permission) and "run my Shortcut" (leaves the app). Say which to add next.
3. **Weather and Wikipedia** run on ElevenLabs and cannot be turned off from the phone. A switch for them would need an agent change.

## Before anyone else uses it
1. Turn on agent authentication and add a small token server (`conversationToken` path in the SDK).
2. Lower concurrency and daily limits, and turn on the prompt-injection guardrail. (The owner decided not to do this for the dev agent on 2026-10-09; this is still a requirement before any other user.)
3. Pick or design Doddy's own voice (library voices must first be added to the account).
4. Decide on data handling with ElevenLabs (zero retention and EU residency are Enterprise-only).
