# A real stopwatch, and a shop list that says what is left (ADR-621)

Date: 2026-10-24. Owner (24 Oct, in Polish, from the list in `docs/product/NOTIFICATION_IDEAS.md`): "1 i 3" = (1) the list-at-a-shop reminder says how many things are left, and (3) a real count-up stopwatch. Branch `claude/stopwatch-and-shop-list`, stacked on `claude/notifications-sound-timers` (ADR-612, ADR-613). Not merged.

## 1. A list's reminder at a place says what is left

- **Before:** arriving at a place the user picked for a list gave the private text only ("Lista czeka", with Open and Done).
- **Now:** "4 rzeczy na liście" / "4 items on the list"; "1 rzecz na liście"; "wszystko odhaczone" ("everything is ticked off") when nothing is open. With "Show note text in notifications" on, the list's name goes in front ("Zakupy · 4 rzeczy na liście"). The place's name is never in the notification (unchanged privacy rule, `ReminderPlace`).
- **Buttons:** "Open list" (the same action id as "Open note", so the existing handler opens the list) and Done. A new category, `DODDY_LIST_PLACE_REMINDER`, carries them.
- **Count:** read from SQLite when the reminder is set and again whenever the list changes (`refreshContent`): `SELECT COUNT(*) FROM list_items WHERE list_id = ? AND done_at_ms IS NULL`. If the count can't be read, the plain private text stays; a number is never guessed.
- **Not in the text:** item names. Only a count, so nothing private reaches the Lock Screen that "Show note text" would have kept off.

## 3. The stopwatch (counts up)

- **Where:** Home › Stopwatch (new, next to Focus). One stopwatch at a time, on this iPhone. Start (optional label, 40 characters at most), Pause/Resume, Stop. A stopped one keeps its time on screen until dismissed ("Zatrzymany na 12 min 7 s").
- **Lock Screen and island:** a Live Activity of the existing tool kind (`DoddyToolAttributes.Kind.stopwatch`). The time is a self-ticking `Text(timerInterval:)` counting up from a clock start the app computes (`Stopwatch.clock`), so it keeps running with the app closed and nothing is redrawn every second (this is what stuttered in the old timer design). Paused: the activity shows the fixed time. The island's minimal view is `stopwatch.fill`; the big view is the time, the label on top ("STOPWATCH").
- **No notification:** nothing ends, so nothing rings or buzzes. It is not a timer; for a countdown that rings, `set_timer` (ADR-612) is unchanged.
- **Limit:** 24 hours (`Stopwatch.maxElapsed`). A stopwatch left running is stopped at exactly 24 h the next time the app starts or comes to the foreground (`refresh`, `stopIfAtLimit`); until then the Lock Screen clock keeps counting, because nothing runs in the app while it is closed. Kept in UserDefaults (`stopwatch`), so a relaunch or a reboot loses nothing; the elapsed time is always computed from stored dates, never from a counter that could stop when the app is suspended.
- **Buttons on the Lock Screen and in the island:** Pause/Resume and Stop, the same pills and intents as Focus (`ToggleDoddyToolPauseIntent`, `StopDoddyToolIntent`), wired to the stopwatch through `ToolActivityActions` (registered for `.stopwatch`).
- **Voice:** three tools in `voice-agent/tools.json`: `start_stopwatch` (optional `label`), `stop_stopwatch`, `check_stopwatch`. In the app they ask first (ASK-01): a tap card for start and stop, "Yes, read it" for the reading. A second start doesn't start another: it reports the one running. The replies come from the stored stopwatch only ("The stopwatch is running: 12 minutes 7 seconds so far."), never from a guess. Pause all and car mode are handled (start/stop are off in car mode; the reading is allowed).
- **Said only when true:** "started" only after the stopwatch was stored; "stopped at …" only with the time the store returned; "no stopwatch" when there is none.

## Files

- **DoddyCore:** `Stopwatch.swift` (new: `Stopwatch`, `State`, `clock`, `spoken`, `cleanLabel`), `StopwatchVoice.swift` (new: tool names, `VoiceToolReply` for the stopwatch), `NoteReminders.swift` (`listPlaceBody`, `itemsOnList`, `NoteReminderCategory.placeList`, `openItems` on `requests`, `openItemCount` on the repository protocol), `VoiceTools.swift`, `ToolCatalog.swift`, `AskFirst.swift`, `ConnectionPause.swift`, `CarProfile.swift`, `ActivityLog.swift`, `ActivityText.swift`. `DoddyPersistence`: `SQLiteNoteReminderRepository.openItemCount`.
- **App:** `Features/Stopwatch/StopwatchController.swift`, `StopwatchView.swift` (new); `Features/Voice/VoiceSessionController.swift` (three cases); `Features/Home/HomeView.swift`, `RootView.swift`, `App/DoddyApp.swift`, `Features/Tools/ToolLiveActivity.swift`; `Infrastructure/Connections/NoteReminderNotifications.swift` (the list category).
- **Shared / widgets:** `Shared/ToolActivity/DoddyToolAttributes.swift` (`countsFrom`, `elapsed`), `Shared/IslandArt/IslandScene.swift`, `IslandViews.swift`, `DoddyWidgets/DoddyToolLiveActivity.swift`, `DoddyWidgetPreviews.swift`, `tools/island_boards/IslandSceneChecks.swift`.
- **Spec and text:** `voice-agent/tools.json` (97 tools, was 94), `instructions.md`, `l10n/pl.json` (10 new lines), regenerated catalogs, `backend/src/web/logbook.ts` (the three ids; a test compares the list with `tools.json`), `web/src/logbook/catalog.ts` and `web/src/i18n/logbookMessages.ts` (names; example weight 0, so the example week's numbers don't move).

## Verified (Linux, Swift 6.1.2)

- DoddyCore: 1,749 tests, 0 failures (was 1,725 before this change), with 24 new tests (`StopwatchTests` 10, `StopwatchVoiceTests` 8, `ListPlaceReminderTests` 5, `OpenItemCountTests` 1).
- `scripts/typecheck_app_logic.sh` (28 files), the capability guard, the string catalogs, `voice_agent_spec.py check` (97 tools).
- Backend `logbook.test.js` (37 pass) after adding the ids; web unit tests (99 pass) and type-check. The core CI run caught the backend test that compares `LOGBOOK_TOOL_IDS` with `tools.json`: that was this change's miss, fixed here.
- Island art checks: the stopwatch scene in `IslandSceneChecks.swift`.
- Web end-to-end: 16 passed, 4 skipped, with `PLAYWRIGHT_CHROMIUM=/opt/pw-browsers/chromium` (without it this container fails to launch its Chromium: the installed build is newer than the one Playwright expects; unrelated to this change).

## NOT RUN

- No Xcode build: the SwiftUI screen, the Live Activity and widget code, the App Intents buttons and `VoiceSessionController`'s three cases are uncompiled until the hosted Mac job.
- No device. Checklist (iOS 17+):
  1. Home › Stopwatch › Start with the label "Gotowanie": the Lock Screen and the island show the label and a time counting up, second by second, with no stutter, app closed.
  2. Pause on the Lock Screen: the time freezes. Resume: it carries on from there, not from the wall clock.
  3. Force-quit the app, wait two minutes, open it: the time includes the two minutes; stopped, it keeps the final time and shows "Zatrzymany na …".
  3b. Buttons: Pause and Stop on the Lock Screen and in the expanded island both work.
  4. Start a second one while one runs (button and voice): nothing new starts; the voice says the time of the one running.
  5. By voice (needs the live agent changed, see below; or OpenAI voice, which reads the same files): "Włącz stoper" → tap card → started; "Ile już minęło?" → the reading; "Zatrzymaj stoper" → tap card → "Zatrzymany na …".
  6. A list with a place: leave and arrive. The notification says "N rzeczy na liście" and no place name; tick one item off and the count is right the next time; "Open list" opens the list.
  7. A list with everything ticked: "wszystko odhaczone".
  8. Car mode: "Stop stopwatch" is refused; "How long?" answers.
- The Polish lines are agent-written.

## Live agent (needs the owner's yes)

The three stopwatch tools do not exist on the live ElevenLabs agent, so by voice it can't start one yet. Nothing was changed there. To do, after the owner's explicit yes: create `start_stopwatch`, `stop_stopwatch` and `check_stopwatch` as client tools exactly as in `voice-agent/tools.json`, attach them to the agent, and add the stopwatch lines from `instructions.md` to the prompt. Read the live version first and keep its rollback id, as `voice-agent/README.md` says. Until then the stopwatch works from Home and the Lock Screen only.

## Constitution evidence log

| Rule | Enforcing code | Tests run | Gaps |
|---|---|---|---|
| ASK-01 / DOD-07 scoped_action_approval | `AskFirst.need`: start and stop are `.tapFirst`, the reading `.yesFirst`; the handler runs only after the card | `AskFirstTests` (every voice tool has a card or a reason), `testStartingAndStoppingNeedATapAndReadingAsksYes`, `testTheCatalogAgreesWithTheCards` | UI not compiled |
| DOD-08 verified_status_and_receipts | Replies are built from the stored `Stopwatch` (`stopwatchStarted`, `stopwatchStopped(elapsed:)`, `stopwatchReading`); "none" is said as none | `StopwatchVoiceTests` | With Live Activities turned off in iOS Settings the Lock Screen shows nothing; the stopwatch still runs and the Home screen shows it. Not tried on a device |
| DOD-09 correction_and_recovery | A second start changes nothing and reports; a stop with none says so; a 24 h stop is recorded as such | `StopwatchTests`, `StopwatchVoiceTests` | — |
| DOD-11 observable_privacy | A list's notification carries a count only, never item or place names; the list's name only with "Show note text" on | `ListPlaceReminderTests` | The stopwatch's label is shown on the Lock Screen by design; the user typed it |
| DOD-10 nonmanipulative_companionship | No notification, streak or nudge for the stopwatch | — | — |

Claims to limit: don't say "the stopwatch works on the Lock Screen" or "the list reminder shows the count" until checklist rows 1 to 3 and 6 pass on a device; don't say "by voice" until the live agent has the tools.
