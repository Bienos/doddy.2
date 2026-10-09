# V1 status — voice inside the app (ElevenLabs Agents)
Date: 2026-10-08. Updated 2026-10-09 after a read-only live check of the ElevenLabs agent, when the Connections functions were built, and when timers, maps, Shortcuts and drafted messages were added to the agent. Owner instruction: build with ElevenLabs (owner has the Creator plan).

## ElevenLabs setup (live state after the 2026-10-09 update)
| Item | Value |
|---|---|
| Agent | "Doddy (dev prototype)" `agent_0501m4et27vyeawrwqfdxxfszfa6`, tags doddy/dev. Latest version `agtvrsn_6101m4gj4ms9et0rcf0qy53f8nvy` (14 custom tools attached). |
| Mode | **Public (no auth)**: development only, on the owner's own phone. The owner decided on 2026-10-09 not to lock it down yet; it must change before anyone else uses it. |
| LLM | gemini-3.5-flash, temperature 0.5, timezone Europe/Warsaw (the 10-08 entry said gemini-2.5-flash / 0.3; the live agent changed after that) |
| Speech | Scribe realtime (in), eleven_v4_turbo (out), default voice for now; max 10 min per conversation |
| Languages | English default, Polish preset ("Hej, tu Doddy. Co słychać?"), automatic language detection |
| Limits | Concurrency unlimited (-1); daily cap 100,000 calls; recording on; retention not set (-1); all guardrails off |
| Prompt | Updated 2026-10-09: AI disclosure, short spoken replies, strict memory rules, and sections on calendar, reminders, contacts, timers, maps, Shortcuts and messages. Each tool's result prefix ("added", "opened", "declined", "failed", "unknown") is named in the prompt. |
| Prompt placeholders | `{{saved_notes}}`, `{{saved_notes_count}}`, `{{saved_notes_truncated}}`, `{{recent_conversations}}` have default text. The app does not send them yet, so the agent always sees "did not send any saved notes" (open item 1). |

### Tools on the agent and what the app does with each
| Tool | Runs on | App behaviour |
|---|---|---|
| `search_memories` `tool_6701m4et16pveywrpymdw3h3v0wp` | phone | Searches local notes; returns stored text only. Always on. |
| `save_memory` `tool_9401m4et17pfe598c1wmvdhpwhcv` | phone | Card with **Save**; nothing stored until the tap. Always on. |
| `read_calendar` | phone, Calendar switch | Returns titles and times for today, tomorrow, the week, or a range. Nothing is added. |
| `create_calendar_event` | phone, Calendar switch | Card with **Add**; added only after the tap, then read back to verify. |
| `create_reminder` | phone, Reminders switch | Card with **Add**; added only after the tap, then read back to verify. |
| `lookup_contact` | phone, Contacts switch | Agent gets names only; numbers and emails show on screen only, with Call, Text and Email buttons that each need a tap. |
| `set_timer` `tool_8601m4gj35c6enz912e0zhax003f` | phone, Timers switch (+ notification permission) | Card with **Start**; scheduled as a local notification, read back to verify. Banner shows even while Doddy is open. |
| `open_map` `tool_6101m4gj36nbe1tv5mpj73rzbqsa` | phone, Maps switch | Card with **Open in Maps**; opens Apple Maps, which leaves the app. |
| `run_shortcut` `tool_1601m4gj37f5etbres37pgtvrq3c` | phone, Shortcuts switch | Card with **Run**; asks Shortcuts to run it. Doddy cannot see whether it finished. |
| `draft_message` `tool_9001m4gj38k8fmwbr3gy4qz3wygw` | phone, Messages switch + Contacts | Looks up the contact; card with **Open in Messages** or **Open in Mail**. The user sends it there. Doddy never sends. |
| `geocode_place`, `get_weather` | ElevenLabs → Open-Meteo | Cannot be switched off from the phone. Place name and coordinates go to Open-Meteo. |
| `wikipedia_search`, `wikipedia_summary` | ElevenLabs → Wikipedia | Cannot be switched off from the phone. Search words go to Wikipedia. |

A function that is off, or whose iOS permission is refused, returns "isn't connected" to the agent, which tells the user to turn it on in Settings, Connections. During a call, a card offers to turn it on.

## App
- Home → **Talk to Doddy** opens `VoiceView` (foreground only). It ends when the screen closes or the app goes to the background. Opening Maps, Shortcuts, Messages or Mail sends the app to the background, so the conversation ends.
- `VoiceSessionController` uses the ElevenLabs Swift SDK 3.3.1 (`ElevenLabs.startConversation(agentId:…)`). Status (connecting, listening, thinking, speaking, ended) comes from real SDK events.
- One card at a time: a note, event, reminder, timer, map, Shortcut or draft waits for its tap. A second proposal while one waits is refused, so every tool call still gets an answer.
- Settings → **Connections** opens a card screen in three groups: Your day (Calendar, Reminders, Timers), People (Contacts, Messages and email), Places and apps (Maps, Shortcuts). Each card shows an example phrase and an Off / On / Blocked pill. A tap opens a sheet with what Doddy can do, what leaves the phone, and what stays on the iPhone. Turning one on is a separate tap, and it asks iOS for permission first.
- EventKit and Contacts code lives only in `DoddyApp/Infrastructure/Connections/`. The guard script enforces that.
- Settings → Voice: the agent ID (prefilled with the dev agent). The privacy note says that notes, calendar entries, contact names and message drafts used in a conversation go to ElevenLabs, and that weather and fact lookups go to Open-Meteo and Wikipedia.
- Privacy manifest declares audio data, other user content (calendar, reminder and draft text), and name (contact names sent to the agent). All are app functionality, not linked, no tracking. Confirm these in App Store Connect.
- Permission strings: microphone, calendars (full access), reminders (full access), contacts. Notifications for timers use iOS's own prompt, with no usage string.

## Verified
- Linux, Swift 6.0.3 (2026-10-09): `DoddyCoreTests` and `DoddyDesignTokensTests` pass, 46 tests, 0 failures. The GRDB persistence target was left out of the scratch copy because it needs a GitHub clone this environment can't make. Parsing for every tool, date and duration validation, reply wording, and the Maps, Shortcuts, tel, sms and mailto link strings are covered by `VoiceToolsTests`.
- Linux: the capability guard passes (EventKit and Contacts only in `Infrastructure/Connections`; four permission keys only).
- `PrivacyInfo.xcprivacy` and the Info keys in `project.yml` are well-formed.
- Linux: `swiftc -parse` passes for every changed Swift file. This checks syntax only.
- Live agent (2026-10-09, ElevenLabs connector): the four new tools were created and attached; the prompt update returned the 14 tool IDs and the new prompt text.
- Live check earlier the same day (read-only): at least 10 conversations from that day were started by the app (`swift_sdk`), with normal disconnects. Tool calls seen: `language_detection`, `wikipedia_search`, `wikipedia_summary`, `geocode_place`, `get_weather`. One conversation switched to Polish.
- Tool totals on the live agent before the update: `search_memories` 4 calls, `save_memory` 2 calls. Per-call results were not visible through the connector.

## Not verified (needs the Mac and a real iPhone)
- **The iOS app has not been compiled with this code.** The EventKit, Contacts, UserNotifications, SwiftUI and ElevenLabs SDK code has only been syntax-checked. Run `make project` and the build on a Mac first.
- EventKit and Contacts permission prompts and what happens on refusal; real event and reminder adds, and whether the read-back check passes; contact lookup on a device with real contacts.
- Timers: the notification permission prompt, the banner while the app is open, and the ring time.
- Maps, Shortcuts, Messages and Mail: each opens the right app with the right address and body, and the Shortcut name matches the user's real Shortcut.
- Microphone prompt; a real conversation in English and Polish on the owner's device.
- ~~That client tool calls arrive~~: confirmed on a device on 2026-10-09 by another branch (`save_memory` round trip in 5.7 s; see `claude/inspiring-einstein-j3lvjc`).
- The confirmation round-trip within the 90 s tool timeout; ending on background.

## Open items
1. **Dynamic variables (saved notes in the prompt):** not implemented. The SDK 3.3.1 Swift docs do not document a way to pass them, and no Swift toolchain was available to check the source. Before writing code, check `ConversationConfig` in Xcode Quick Help. Filling the placeholders would also send every saved note to ElevenLabs at the start of each conversation, not only when Doddy searches. The Settings text would have to say so.
2. **Not added:** alarms (AlarmKit needs iOS 26 and a new permission), and anything needing health, location, music or home data (sensitive permissions or entitlements). Webhook lookups such as exchange rates could be added to the agent without app code, but each adds a third-party disclosure.
3. **Weather and Wikipedia** run on ElevenLabs and cannot be turned off from the phone. A switch for them would need an agent change.
4. **Leaving the app ends the call:** Maps, Shortcuts, Messages and Mail open another app, so the voice conversation ends. Background voice is a later step.

## Before anyone else uses it
1. Turn on agent authentication and add a small token server (`conversationToken` path in the SDK). **Server live 2026-10-09** at `https://doddy-voice-token-bienos.vercel.app/api/voice-token` (`server/voice-token`, see `docs/implementation/VOICE_TOKEN_SERVER_STATUS.md`); API key/codes and agent auth pending.
2. Lower concurrency and daily limits, and turn on the prompt-injection guardrail. (The owner decided not to do this for the dev agent on 2026-10-09; this is still a requirement before any other user.)
3. Pick or design Doddy's own voice (library voices must first be added to the account).
4. Decide on data handling with ElevenLabs (zero retention and EU residency are Enterprise-only).
