# What the user asks for runs at once; a card only before a change

- **Date:** 2026-11-11
- **Decided by:** owner: "jak ja pytam się do niego coś, to on cały czas musi mieć zatwierdzenie jakieś zakładki. On powinien być taki bardziej proaktywny, że nie dopytywać się wszystkiego, tylko od razu powinien pokazywać albo mówić informacje, a nie tak bardzo dużo kroków zajmować, żeby cokolwiek z nim zrobić." And: "nie, że na przykład o, nie mam narzędzia, to tego nie zrobię … musi być taki niedopytujący się i bardziej proaktywniejszy." And about the screen: "ja się go pytam, a on pyta się, czy może wejść, pozwolenie dostać. Pokazuje mi kartę, nawet jak nie jestem w aplikacji, to muszę wejść w aplikację, to jest bez sensu."
- **Status:** applied in the pull request that adds this file (app and repo spec). The live voice agent is not changed by it: see "Owner steps".
- **Replaces:** the "reads included" part of ASK-01 (ADR-483, owner, 18 Oct 2026); "each look asks first" in `2026-11-09-doddy-looks-at-the-screen`; the first of the two cards of `remind_when_to_leave` (ADR-718); the tap on Doddy's own stopwatch, focus timer and wind-down (ADR-652, `2026-11-10-timers-by-voice`), on adding to and ticking off a list, on following a topic (ADR-657), on opening the training plan screen (ADR-626) and on the capability-gap row (ADR-440).

## Why
ASK-01 made 103 of the 116 voice tools wait for a yes or a tap, reads included, and forced the agent to say a question before each of them (`speak_before: force`). Asking "what's in my calendar tomorrow?" took four steps: Doddy asks "Mam sprawdzić kalendarz?", the app shows a card, the person says yes or taps, then the answer comes. The card lives in the app, so outside the app (Action Button, the island) the person had to open Doddy to answer it. A spoken yes often did not count: only a short list of exact phrases is a yes, and the colloquial Polish "no", "no tak", "no jasne" are refused because "no" is a veto word. When Doddy couldn't do something, the prompt told him to call `note_capability_gap`, which showed one more card ("Zanotować, czego Doddy nie umie?") and replaced whatever card was waiting.

Read from the code on 11 Nov 2026 (`AskFirst.swift`, `VoiceSessionController.swift`, `voice-agent/tools.json`, `voice-agent/instructions.md`); not measured on a device.

## Decision
What the user asks for is the yes.

1. **Looks run at once, with no card and no spoken question.** On the phone: `search_memories`, `read_list`, `read_calendar`, `find_free_time`, `lookup_contact`, `upcoming_birthdays`, `find_photos`, `read_steps`, `read_health_week`, `list_alarms`, `check_stopwatch`, `check_focus`, `parking_spot` find, `check_errands`, `find_deals`. Through Doddy's server: every tool that is not a write (the Gmail, Outlook, Google Calendar, Drive, Notion and Todoist reads, `ask_claude`, `make_document`); the server's single-use approval is still made for exactly the call and used straight away.
2. **`look_at_screen` runs at once while the person shares their screen.** They start sharing themselves in iOS's own sheet and iOS shows that it is on the whole time; that is the yes for Doddy to look while it stays on. With sharing off nothing is looked at.
3. **Doddy's own small actions run at once:** `start_stopwatch`, `stop_stopwatch`, `start_focus`, `stop_focus`, `start_wind_down`, `stop_wind_down`, `add_to_list`, `check_off`, `follow_news`, `open_training_plan`, `note_capability_gap`. Each is undone in one step and none reaches another app, an account or another person.
4. **`remind_when_to_leave` shows one card, not two:** the trip is worked out at once and the payload card (the place Maps found, the travel time, when to leave) is the tap that sets the notification.
5. **Unchanged: a tap on a card with the exact payload** for everything that changes something outside Doddy's own lists and timers, sends, deletes, moves, shares, calls, books or pays: notes, calendar, reminders, alarms, timers, messages, BLIK, HomeKit, shortcuts, Maps, every account write, removing from a list, forgetting the parking spot, a handed-over task (ADR-716), a Studio job (ADR-742), calls. DOD-07 (no model-only approval of a change) is unchanged.
6. **The standing consents stay where they were.** Each Connections switch (Calendar, Contacts, Photos, Steps, Apple Health with its own voice consent …) is allowed once on its own sheet; an online account is connected once; Messages' and voice's own consents are unchanged; iOS asks for location, photos and screen broadcast itself.
7. **The prompt:** Doddy calls the tool and answers; he does not announce or ask. He never says he has no tool before trying the nearest one (`web_search`, `ask_claude`, his notes and lists, the leaflets); only when nothing of his can do it does he say in one sentence what he can do instead. He asks a question only when he cannot act without the answer.

## Consequences
- Fewer steps: a question about the person's own things is one turn. Nothing has to be answered inside the app for a look.
- A look can now happen because the agent misheard a request. It reads; it changes nothing. What Doddy did is still listed under "What Doddy did".
- More of the person's own data reaches the voice provider without a per-call yes: the result of a look is spoken by the agent, so it goes to ElevenLabs as before, only without the extra question. The switches in Settings › Connections are the place to stop a kind of data; "Pause all" still stops everything.
- `ask_claude` and `make_document` cost Doddy money without a yes; the server's daily caps (`DODDY_LIMIT_USER_DAILY_CLAUDE`, `DODDY_DOCUMENT_CLAUDE_UNITS`) are the brake. `make_document` still asks for missing details first (decision `2026-11-10-files-ask-for-details`).
- Privacy text: the policy draft describes a yes before each read; it needs a line saying a look the person asks for runs at once (owner queue).
- The spoken-yes rules (`SpokenYes`, `AskLedger`) stay in the code and tested; no tool uses a spoken yes today.

## Owner steps
The app change works by itself: the card and the wait are gone as soon as a build with it is installed. Until the live agent is synced it still says its question first ("Mam sprawdzić kalendarz?") because the live tools force speech before each call, and then answers without waiting.
- **Live voice agent (owner's instruction needed):** for the 38 tools whose `x_doddy.ask` changed to `runs_now`, apply the new description and turn off forced speech (`python3 -I scripts/voice_agent_spec.py elevenlabs` renders them); replace the prompt's ASK-01 section and the changed tool lines with `voice-agent/instructions.md`.

## Evidence
- Rule as code: `Packages/DoddyCore/Sources/DoddyCore/AskFirst.swift` (`ownLooks`, `ownSmallActions`, `runsAtOnce`, `need(for:)`), mirrored in `ToolCatalog.swift`, `voice-agent/tools.json` (`ask`), `scripts/voice_agent_spec.py` and `docs/trust/config/doddy_rules.yaml`; `ToolCatalogTests` and the spec check keep them in step.
- What was run is in the pull request. Not compiled here: the SwiftUI app (`VoiceSessionController.swift`, `HomeView.swift`). Not seen on a device.
