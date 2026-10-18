# V1 status — voice inside the app (ElevenLabs Agents)
Date: 2026-10-08. Updated 2026-10-09 after a read-only live check of the ElevenLabs agent, when the Connections functions were built, and when timers, maps, Shortcuts and drafted messages were added to the agent. Owner instruction: build with ElevenLabs (owner has the Creator plan).

## ElevenLabs setup (live state after the 2026-10-09 update)
| Item | Value |
|---|---|
| Agent | "Doddy (dev prototype)" `agent_0501m4et27vyeawrwqfdxxfszfa6`, tags doddy/dev. Latest version `agtvrsn_8101m4gvnve7fdzsyqk5rjyqcfb8` (14 custom tools attached; personality and profile sections added 2026-10-09). |
| Mode | **Public (no auth)**: development only, on the owner's own phone. The owner decided on 2026-10-09 not to lock it down yet; it must change before anyone else uses it. |
| LLM | gemini-3.5-flash, temperature 0.5, timezone Europe/Warsaw (the 10-08 entry said gemini-2.5-flash / 0.3; the live agent changed after that) |
| Speech | Scribe realtime (in), eleven_v4_turbo (out), voice `oDULUm0GMltHA6mVZkWh` (owner pick 2026-10-09, ADR-051; before that Josh `ZoiZ8fuDWInAcwPXaVeq`, ADR-038); one voice for both languages; max 10 min per conversation |
| Data kept by ElevenLabs | Audio recording **on**, retention **unlimited**, transcripts and audio **not** auto-deleted, zero-retention off. Kept as is by owner decision (ADR-057) |
| Languages | English default, Polish preset ("Hej, tu Doddy. Co słychać?"), automatic language detection |
| Limits | Concurrency unlimited (-1); daily cap 100,000 calls; recording on; retention not set (-1); all guardrails off |
| Prompt | Updated 2026-10-09: AI disclosure, short spoken replies, strict memory rules, and sections on calendar, reminders, contacts, timers, maps, Shortcuts and messages. Each tool's result prefix ("added", "opened", "declined", "failed", "unknown") is named in the prompt. | Before `save_memory` runs, Doddy says only "Confirm on screen if I should save this." / "Potwierdź na ekranie, jeśli mam to zapisać." |
| Prompt placeholders | `{{saved_notes}}`, `{{saved_notes_count}}`, `{{saved_notes_truncated}}`, `{{recent_conversations}}` have default text; the app fills them at the start of each conversation (see Knowledge below). `{{doddy_personality}}` (style settings, always sent) and `{{user_profile}}` (introduction answers, only when the user turns that on in Settings → About you; ADR-092) are in the prompt with defaults. |

### Tools on the agent and what the app does with each
| Tool | Runs on | App behaviour |
|---|---|---|
| `search_memories` `tool_6701m4et16pveywrpymdw3h3v0wp` | phone | Searches local notes; returns stored text only. Always on. |
| `save_memory` `tool_9401m4et17pfe598c1wmvdhpwhcv` | phone | Card with **Save**; nothing stored until the tap. Always on. |
| `read_calendar` | phone, Calendar switch | Returns titles and times for today, tomorrow, the week, or a range. Nothing is added. |
| `create_calendar_event` | phone, Calendar switch | Card with **Add**; added only after the tap, then read back to verify. Start/end follow the reminder date rules (ADR-127): a zone suffix, impossible date, clock-change time or a start that has passed (checked again at the tap, ADR-128) is sent back as a question (`failed: not added yet`), never shifted. |
| `create_reminder` | phone, Reminders switch | Card with **Add**; unclear or past times go back to the agent as a question; after the tap Doddy checks it isn't already there, adds it once, reads it back and shows a receipt (M4, `M4_REMINDERS_STATUS.md`). |
| `lookup_contact` | phone, Contacts switch | Agent gets names only; numbers and emails show on screen only, with Call, Text and Email buttons that each need a tap. |
| `set_timer` `tool_8601m4gj35c6enz912e0zhax003f` | phone, Timers switch (+ notification permission) | Card with **Start**; scheduled as a local notification, read back to verify. Banner shows even while Doddy is open. |
| `propose_plan` `tool_3001m4knv27zfw09afmn7sjamfcp` | phone; each step needs its own switch and permission | One card for 2–5 changes (`save_memory`, `create_calendar_event`, `create_reminder`, `set_timer`, and since ADR-209 `draft_email`, `add_todoist_task`), each with a tick box. Steps run in order through the same code as their single cards; each gets its own result and its own "What Doddy did" entry (ADR-204). |
| `open_map` `tool_6101m4gj36nbe1tv5mpj73rzbqsa` | phone, Maps switch | Card with **Open in Maps**; opens Apple Maps, which leaves the app. |
| `run_shortcut` `tool_1601m4gj37f5etbres37pgtvrq3c` | phone, Shortcuts switch | Card with **Run**; asks Shortcuts to run it. Doddy cannot see whether it finished. |
| `draft_message` `tool_9001m4gj38k8fmwbr3gy4qz3wygw` | phone, Messages switch + Contacts | Looks up the contact; card with **Open in Messages** or **Open in Mail**. The user sends it there. Doddy never sends. |
| `draft_blik_transfer` (not on the live ElevenLabs agent yet) | phone, BLIK transfers switch (+ Contacts if allowed) | Card with the person, their numbers, the amount in złoty and the title, and **I'll send it myself**. The user sends it in their bank app; Doddy never sends money (ADR-483, `BLIK_TRANSFER_STATUS.md`). |
| `geocode_place`, `get_weather` | ElevenLabs → Open-Meteo | Cannot be switched off from the phone. Place name and coordinates go to Open-Meteo. |
| `wikipedia_search`, `wikipedia_summary` | ElevenLabs → Wikipedia | Cannot be switched off from the phone. Search words go to Wikipedia. |

A function that is off, or whose iOS permission is refused, returns "isn't connected" to the agent, which tells the user to turn it on in Settings, Connections. During a call, a card offers to turn it on.

## App
- Home → **Talk to Doddy** opens `VoiceView`. It ends when the screen closes; since V3 it keeps running in the background with a Dynamic Island (`V3_ISLAND_STATUS.md`), so opening Maps, Shortcuts, Messages or Mail no longer has to end it (not yet checked on a device).
- `VoiceSessionController` uses the ElevenLabs Swift SDK 3.3.1 (`ElevenLabs.startConversation(agentId:…)`). Status (connecting, listening, thinking, speaking, ended) comes from real SDK events.
- `search_memories` runs the local SQLite recall and returns only stored text (`VoiceToolReply.search`).
- One card at a time: a note, event, reminder, timer, map, Shortcut or draft waits for its tap. A second proposal while one waits is refused, so every tool call still gets an answer. While a card waits, the Dynamic Island says "Confirm in Doddy".
- Settings → **Connections** opens a card screen in three groups: Your day (Calendar, Reminders, Timers), People (Contacts, Messages and email), Places and apps (Maps, Shortcuts). Each card shows an example phrase and an Off / On / Blocked pill. A tap opens a sheet with what Doddy can do, what leaves the phone, and what stays on the iPhone. Turning one on is a separate tap, and it asks iOS for permission first.
- EventKit and Contacts code lives only in `DoddyApp/Infrastructure/Connections/`. The guard script enforces that.
- Microphone denied → explanation + Open Settings; the rest of the app keeps working.
- Settings → Voice → **Voice and personality**: humour, reply length, tone and mood, sent as `doddy_personality` and used by the live prompt; plus voice, speed and expressiveness, sent as TTS overrides (ADR-105, allowed on the dev agent 2026-10-10; see `docs/product/PERSONALITY_SETTINGS.md`).
- Settings → Voice: the agent ID (prefilled with the dev agent). The privacy note lists what goes to ElevenLabs (voice, conversation, saved notes, recent conversations, and any calendar entries, contact names or drafts used) and that weather and fact lookups go to Open-Meteo and Wikipedia from ElevenLabs' servers.
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
- **Bilingual search and digits (changed 2026-10-09).** The `search_memories` tool and the prompt now tell Doddy to pass key words in both Polish and English (e.g. "kod code paczkomat parcel"), numbers as digits, and to retry once with a different word; `save_memory` now writes numbers, codes, dates and times as digits in the note. Agent version `agtvrsn_2701m4f1e2krfnysbc5w01agz5d2`. Not yet exercised on a device. Since ADR-093 (2026-10-09) the app's search also does this itself: Polish/English counterparts, spoken numbers as digits, word endings and typos, so the question from this log ("what code you have saved?" against "Kod: pięć, sześć, siedem, osiem.") now finds the note (`SQLiteMemoryRepositoryTests.testRecallAcrossLanguagesSpokenNumbersEndingsAndTypos`).

## Knowledge (2026-10-09, personal single-user build; owner instruction "design it for me only")
Owner's picks: saved notes always, memory across conversations, current info from the web. Profile document declined.

| Piece | What it does | Where |
|---|---|---|
| Saved notes at start | The app renders every saved note (newest first, 6,000-character budget, says when cut) and hands it to the agent as dynamic variables `saved_notes`, `saved_notes_count`, `saved_notes_truncated`; the prompt treats the list as memory and falls back to `search_memories` when the list is cut | `VoiceContext.savedNotes` (DoddyCore, tested), `VoiceSessionController.start` |
| Recent conversations | ElevenLabs user memory is **not available on the Creator plan** (`feature_not_available`), so the app keeps the transcript lines of the last 10 conversations as JSON in Application Support/Conversations (file-protected until first unlock), and sends them as `recent_conversations` (4,000-character budget, newest kept). Settings: "Remember recent conversations" toggle (on by default) and "Forget remembered conversations". Since 2026-10-10 (ADR-177) "Remembered conversations" opens a list: read each one in full, see which are "Brought up next time", delete one, or export them all as text. Logs never become memory records | `ConversationLogStore`, `VoiceContext.recentConversations` / `conversationsSentNextTime`, `ConversationLogExport` (tested), `RememberedConversationsView` |
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

## Connections: not verified (needs the Mac and a real iPhone)
- **The iOS app has not been compiled with this code.** The EventKit, Contacts, UserNotifications, SwiftUI and ElevenLabs SDK code has only been syntax-checked. Run `make project` and the build on a Mac first.
- EventKit and Contacts permission prompts and what happens on refusal; real event and reminder adds, and whether the read-back check passes; contact lookup on a device with real contacts.
- Timers: the notification permission prompt, the banner while the app is open, and the ring time.
- Maps, Shortcuts, Messages and Mail: each opens the right app with the right address and body, and the Shortcut name matches the user's real Shortcut.
- The confirmation round-trip within the 90 s tool timeout; ending on background.

## Open items
1. **Dynamic variables:** done on the V3 line (`ConversationConfig(dynamicVariables:userId:)`, see Knowledge); this Connections branch was written before that and its note here is obsolete.
2. **Not added:** alarms (AlarmKit needs iOS 26 and a new permission), and anything needing health, location, music or home data (sensitive permissions or entitlements). Webhook lookups such as exchange rates could be added to the agent without app code, but each adds a third-party disclosure.
3. **Weather and Wikipedia** run on ElevenLabs and cannot be turned off from the phone. A switch for them would need an agent change.
4. **Leaving the app:** with V3's background audio the conversation should keep running while Maps, Shortcuts, Messages or Mail is open. Not yet checked on a device.

## Before anyone else uses it
1. Turn on agent authentication and add a small token server (`conversationToken` path in the SDK; **code done 2026-10-09** in `server/voice-token/`, see `VOICE_TOKEN_SERVER_STATUS.md`; deploy + enable auth pending).
2. Lower concurrency and daily limits, and turn on the prompt-injection guardrail. (The owner decided not to do this for the dev agent on 2026-10-09; this is still a requirement before any other user.)
3. Voice picked by the owner (`oDULUm0GMltHA6mVZkWh`, ADR-051). Judge Polish pronunciation on a device and check the voice's licence terms before release.
4. Decide on data handling with ElevenLabs (zero retention and EU residency are Enterprise-only).
