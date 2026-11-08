# Release scope: the "Hide" switch (decision `2026-11-07-release-scope`, 7 Nov 2026)

One list in DoddyCore says which features a build shows. Before it, a feature could only ship or be deleted (`GO_LIVE_CHECKLIST.md` B2: "There is no switch for this today"). Now a feature can be **hidden**: its ways in go, its code and the person's data stay.

## Where it is

- **The list:** `Packages/DoddyCore/Sources/DoddyCore/ReleaseScope.swift`. `Feature` names every feature that can be hidden; `ReleaseScope.shipping` is the list the app ships with; `ReleaseScope.everything` hides nothing. Each `Feature` says which voice tools, which Settings › Connections switch and which capability (for "What I can do") belong to it.
- **What the app reads:** `DoddyApp/Infrastructure/ReleaseScopeStore.swift`. Always `ReleaseScope.shipping`. A **Debug** build also reads the preference `releaseScope.previewEverything` (Settings › About › Advanced › "Developer: show every feature"), so the owner can try a hidden feature on their phone. A Release or TestFlight build never reads it.
- **The tests:** `ReleaseScopeTests` (DoddyCore) checks every tool in `voice-agent/tools.json` is either core (`ReleaseScope.coreTools`) or belongs to exactly one feature, so a new tool has to be placed on purpose; `ToolGateTests` checks a hidden tool is refused before every other check.

## What "hidden" does

| Way in | What happens |
|---|---|
| Voice tool | `ToolGate.decide` answers `.hidden(feature)` first, before translator mode, the plan card, Pause all and the connection switch. The controller replies `VoiceToolReply.hidden` ("not available: this version of the app doesn't include the tool…"), logs nothing and shows no card. |
| Home ••• menu and bottom bar | Translate, Tasks, Cheapest this week, Following, the Voice picker and Files exist only when their feature is shown; so do the finished-task and leaflet cards. |
| Settings | The rows for Online accounts, Parcels, Invoices, Payments, Doddy on the web, Ask Doddy, Apple Health, Training plan and log, What Doddy knows, Notifications and texts, Birthdays, Daily news, Phone calls, the evening wrap-up, weekly plan, weekly look-back and tidy-up sections, Import notes, the Spotlight toggle, the voice-provider picker and Studio (Settings › Advanced). Home's "A payment wasn't confirmed" banner stays in every build: it shows only after payments were switched on once, and it is about money already sent. |
| Settings › Connections | A switch whose only feature is hidden (Steps, Home, Presentations, BLIK transfers) is not shown; a group with no switch left goes with its heading (`ConnectionGroup.shown(in:)`). |
| Capability catalog | `CapabilityCatalog.hiding(_:)` marks a hidden feature's capabilities "Not in this version of Doddy", so "What I can do" and Home's Messages button follow it without a check of their own. |
| Icon quick actions | "Where I parked" only when the parking spot is shown (`QuickAction.shown(hasParkingSpot:scope:)`); an old item from an earlier menu opens nothing. |
| Language picker | `ReleaseScope.languages`: Polish, English and "same as this iPhone" in the shipping scope; a hidden language a person chose in an older build stays visible until changed. |
| Recordings | `RecordingCoordinator.start` answers `.rejected(.notInThisVersion)` ("Recording isn't in this version of Doddy."), so Siri, the control and the Action Button say why nothing started; `ShortcutRouter.openRecordings` opens nothing. |
| Other screens | The voice memo button on the capture screen, "close in meaning" results in Find, Share with people… and Shopping mode on a list, and "At a place" on a note's reminder. |

Not covered yet (follow-ups): the widget bundle still lists the parking widget and the recording control (the extension builds its list at compile time; hide them in `DoddyWidgetsBundle` once a build can check it); the "Record with DODDY" App Shortcut phrase stays registered (it answers with the sentence above); a routine a person turned on in an older build keeps its schedule until turned off; the "What leaves this iPhone" text is unchanged.

## What the shipping scope shows and hides

**Shown (the beta):** the conversation (ElevenLabs only), the translator (since 8 Nov, decision `2026-11-08-translator-in-beta`), notes, lists, Apple Calendar, Reminders and Contacts by voice, timers, alarms, the stopwatch, sums and conversions, the weather and Wikipedia, photo notes and Doddy's camera, note reminders at a time, the morning check-in (off by default), Face ID lock, backup, export and delete, Share Sheet, widgets, Messages (behind its own consent), Polish and English.

**Hidden:** the plan card, the voice picker, meaning search, import, voice memos, tidy-up, Spotlight, What Doddy knows, recordings, shared lists, shopping mode on the Lock Screen, place reminders, Leave by, parking, birthdays, evening wrap-up, weekly look-back, weekly plan, steps, Files, Doddy Web, cloud memory, online accounts, web search, Claude documents, leaflets, tasks, price watch, Following, daily news, notifications and texts, phone calls (with `call_me_later`), calls for you, Studio, Payments, Apple Health, the training plan, HomeKit, BLIK transfers (back since #226), presentations, invoices (with `draft_invoice`), parcels, the lost-wallet checklist, `text_me` with notifications and texts, and the eight machine-translated languages.

To change it: edit `ReleaseScope.shipping` and run `make test-core`. `ReleaseScopeTests.testHiddenToolsAreSortedAndInTheSpec` prints nothing, but `ReleaseScope.shipping.hiddenTools` is the list of tools to take off the live agent.

## The live agent (owner)

The app refuses a hidden tool whatever the agent has, so the live agent can keep them; Doddy then says the feature isn't in the app. For the beta the tools should come off the agent, so he doesn't offer what he can't do. With the shipping scope the agent keeps **43 of 108 tools** (the 39 core tools, `find_photos`, `open_camera`, `start_translator` and `stop_translator`) and loses these 65:

`accept_outlook_invite, add_todoist_task, answer_google_invite, append_notion_page, ask_claude, call_me_later, change_email, change_google_event, change_outlook_event, check_email, check_errands, check_outlook_email, complete_todoist_task, control_home, create_drive_doc, create_google_event, create_notion_page, create_outlook_event, decline_outlook_invite, delete_google_event, delete_outlook_event, draft_blik_transfer, draft_email, draft_email_reply, draft_invoice, draft_outlook_email, find_deals, find_drive_file, find_places, follow_news, forward_email, forward_outlook_email, hand_over_errand, list_todoist_tasks, lost_wallet, make_document, make_presentation, make_something, mark_outlook_email, move_outlook_email, move_todoist_task, news_search, open_training_plan, parking_spot, pay_for_page, propose_plan, read_email, read_google_calendar, read_health_week, read_notion_page, read_outlook_calendar, read_outlook_email, read_steps, remind_when_to_leave, rename_todoist_task, reply_outlook_email, reply_to_email, search_notion, send_email, send_outlook_email, text_me, trash_email, trash_notion_page, upcoming_birthdays, web_search`

The prompt (`instructions.md`) still describes some of them (shopping, errands); trimming it for the beta is a separate change the owner says yes to, as every live-agent change is (`docs/platforms/iphone.md`). A second agent for the beta, with only the kept tools, would leave the owner's full agent as it is.

## Checked and not checked (7 Nov 2026, Linux, Swift 6.1.3)

- **Run here:** DoddyCore tests (`ReleaseScopeTests` 10, `ToolGateTests` 11 with 2 new; the whole package 2,422 passed, 0 failed), `scripts/typecheck_app_logic.sh` (35 files, `ReleaseScopeStore` included), `voice_agent_spec.py check` (102 tools), `build_strings_catalog.py --check`, the capability guard, the platform specs.
- **After merging `main` (7 Nov):** BLIK transfers had been removed from the app (ADR-810), so the `blik` feature and `draft_blik_transfer` are gone from the scope (60 hidden tools, was 61; 101 in `tools.json`, was 102), and `ToolGateTests` checks "hidden before its switch" with `control_home`. Not compiled or run in that session (no Swift toolchain); the pull request's hosted run is the check.
- **After merging `main` again (8 Nov):** `main` had six new tools (`call_me_later`, `draft_invoice`, `lost_wallet`, `make_something`, `pay_for_page`, `text_me`), so `ReleaseScopeTests` would have failed with them unplaced. They are placed: `draft_invoice` with invoices, `text_me` with notifications and texts, `call_me_later` with phone calls, and three new hidden features, `studio`, `payments` and `lostWallet` (45 features, 43 hidden; 107 tools, 66 hidden, 41 kept). The Payments row and the Studio button go with their features. A static check in Python found every tool placed once and the list above matching; Swift was not compiled or run in that session.
- **After #226 (8 Nov):** the owner reversed ADR-810 and #226 restored BLIK transfer drafts, so the `blik` feature is back (`draft_blik_transfer`, the BLIK switch and the Money group in Connections), hidden in the beta: 46 features, 44 hidden; 108 tools, 67 hidden, 41 kept. The static check agrees.
- **NOT compiled, NOT run:** every SwiftUI, App Intents and `RecordingCoordinator` edit (no Xcode here). The UI tests launch with `-releaseScope.previewEverything YES` so they keep covering every screen; no UI test of the shipping scope exists yet. Nothing seen on a device.
- **8 Nov, the translator shown** (owner: "tlumac ma nie byc ukryty"; decision `2026-11-08-translator-in-beta`): `.translator` left `ReleaseScope.shipping`, so 46 features, 43 hidden; 108 tools, 65 hidden, 43 kept. `start_translator` and `stop_translator` stay on the live agent. `ReleaseScopeTests`, `ToolGateTests` and `VoiceSessionControllerTests.testHiddenFeaturesToolRunsNothingInTheShippingScope` (now with `find_deals`) follow.
