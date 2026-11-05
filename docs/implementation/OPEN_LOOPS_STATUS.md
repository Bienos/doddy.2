# Open loops, step L0: status (ADR-728)

Branch `claude/eloquent-lovelace-ldlkec`, 5 Nov 2026. Owner: asked how Doddy can help the user remember and remind about important things, then "rób wszystko co trzeba". Design: `docs/product/KEEP_TRACK_AND_REMIND_DESIGN.md` (this is its step **L0**, the first milestone it recommends). Companion: `docs/product/PROACTIVE_COMPANION_PROMPT.md` (step L4).

## What was built

One pure function, `OpenLoopsBuilder.build(_:now:calendar:limitPerSection:)`, that turns what already exists on this iPhone into one ordered list of what Doddy is holding, in four sections: **Today**, **Waiting**, **Watching**, **Later**. It is the data behind the future "Na oku" page (name still open) and Home's "Teraz" card.

| Source | Row appears when | Section and status |
|---|---|---|
| Reminder on a note (`MemoryReminder`) | always | one-off: overdue or due today → Today, otherwise Later; repeating: due until marked done, then its next time (today or later); place: Later with the place's name, no time |
| Apple Reminders (`ReminderSummary`) | always | overdue or due today → Today; later → Later; no date → Later |
| Calendar event (`CalendarEventSummary`) | it is still to come today, or Doddy holds a nudge for it | Today, or Later with "nudge set" / "nudge at the old time" |
| Task handed over (`StoredErrand`) | queued, running, or finished (done or failed) within 7 days | queued and running → Waiting; done or failed → Today; `unknown` → Waiting as "cannot confirm"; draft and cancelled are never shown |
| Price watch (`WatchSummary`) | active; triggered or failed within 7 days | active → Watching; triggered → Today ("price reached", with the server's confirmed price); failed → Today; `unknown` → Watching as "cannot confirm", never as active; draft, stopped and expired are never shown |
| Parcel (`ParcelEntry`) | not delivered and not returned | ready to collect or a problem → Today; in transit, preparing, never checked or an unknown status → Waiting |

Rules in code, each with a test:
- **Honest about sources.** `OpenLoopsInput.unavailable` names a source the caller could not read (a permission is off, a store failed). Its rows are not shown and the agenda lists it in `unavailable`; an agenda with an unreadable source is not `isEmpty`.
- **Unknown is never success.** A task or a watch in `unknown` shows as `cannotConfirm`.
- **The carrier closes a parcel**, not Doddy: delivered and returned disappear.
- **Private words stay private.** A reminder on a private note arrives with `.hidden` words and keeps them hidden. The caller decides what to pass (ADR-310).
- **Deterministic.** Earliest moment first, rows without one last, then source, words and id. Reversing the input changes nothing. Two records with the same id are one row.
- **Limits.** `limitPerSection` (default 20) cuts each section and `more` counts what was cut.

What it does **not** do: it stores nothing, schedules nothing, sends nothing, creates no notification, reads no permission of its own and decides nothing. There is no trigger, no importance, no capture and no model. Those are steps L1 to L4 of the design and are not started.

## The app layer (written the same day; owner: "nie wiem, zrób jak trzeba")

| Piece | What it does | State |
|---|---|---|
| `OpenLoops/OpenLoopsText.swift` (DoddyCore) | The page's words in Polish and English: section titles, a sentence per status, "can't read right now" per source, the empty line. No exclamation marks; `cannotConfirm` never reads as done or active. Other languages show English until the catalogs have them | tested on Linux (5 tests) |
| `Features/OpenLoops/OpenLoopsModel.swift` | The page's state: progress until the first read, then the agenda; one read at a time (a call during a read is folded into one more read after it) | tested on Linux (6 tests) and type-checked in Swift 6 |
| `Features/OpenLoops/OpenLoopsSources.swift` | The only code that reads the stores. Private notes' words are `.hidden` unless Face ID unlocked them (the rule of Home's "Due now"); a source the person turned on but the app can't read (permission revoked, Pause all, store failed) goes in `unavailable`; a source never turned on is not asked | **NOT COMPILED** |
| `Features/OpenLoops/OpenLoopsView.swift` | The list: sections, rows, a warning line per unreadable source, pull to refresh. A note's row opens the note and a task's row opens the task; the other rows are read-only | **NOT COMPILED** |
| `Features/Errands/ErrandsView.swift` | A row "Na oku" at the top of the Tasks screen opens the page | **NOT COMPILED** |
| `scripts/test_open_loops_model.sh`, `scripts/ci.sh`, `scripts/typecheck_app_logic.sh` | The new checks, added to the Linux CI steps | ran here |

Choices I made for the owner, to confirm or change:
- **Name:** "Na oku" (English "On the radar"). Open.
- **Entry:** the Tasks screen, not Home's ••• menu: a comment in `HomeView` says the menu fits eleven rows and a twelfth pushed "What I can do" and "What leaves this iPhone" out of reach. Home's "Teraz" card is the better place later.
- **No new network use.** Tasks are read from this iPhone's copy, parcels are not looked up, and price watches are re-read from Doddy's server only if the Tasks screen already loaded them in this session. So a watch shows on this page only after Tasks was opened once in the session; reading it earlier could create the anonymous Doddy account just by opening a page. Known gap.
- **Events:** today's, plus the next seven days only while a nudge holds them. A Reminders item with no date isn't fetched (the Today card's call returns dated ones).
- **A time is shown** unless the moment is exactly midnight, then only the date (an all-day event has no time).

## Files

- `Packages/DoddyCore/Sources/DoddyCore/OpenLoops/OpenLoops.swift`: types and the builder. Foundation only, so it builds on every platform (iPhone; Watch and Mac are paused and don't use it).
- `Packages/DoddyCore/Tests/DoddyCoreTests/OpenLoopsTests.swift` (14 tests), `OpenLoopsTextTests.swift` (5), `DoddyTests/OpenLoopsModelTests.swift` (6).
- `Packages/DoddyCore/Sources/DoddyCore/OpenLoops/OpenLoopsText.swift`, `DoddyApp/Features/OpenLoops/*` (see the table above).
- `DECISIONS.md`: ADR-728.
- `docs/product/KEEP_TRACK_AND_REMIND_DESIGN.md`, `docs/product/PROACTIVE_COMPANION_PROMPT.md`: the design and the prompt proposal.

## Checks run (Linux, Swift 6.1.3, 5 Nov 2026)

| Check | Result |
|---|---|
| `swift test --filter OpenLoopsTests` (DoddyCore, with the repo's Linux SQLite flags) | 14 tests, 0 failures |
| Mutation 1: an `unknown` task changed to show as finished | the suite fails (3 assertions), file restored |
| Mutation 2: unreadable sources no longer skipped | the suite fails (1 assertion), file restored |
| `scripts/check_forbidden_capabilities.sh` | PASS |
| `swift test --filter OpenLoopsTextTests` | 5 tests, 0 failures |
| `scripts/test_open_loops_model.sh` (the model linked into the DoddyCore test target) | 6 tests, 0 failures; mutation: overlapping refreshes not folded → the suite fails, file restored |
| `scripts/typecheck_app_logic.sh` | PASS, 35 app files in Swift 6 including `OpenLoopsModel.swift` |
| `tools/build_strings_catalog.py --check` | PASS (the page adds no catalog string) |
| Full DoddyCore suite (`swift test`, same flags) | 2,394 tests, 0 failures |

Not run here: the other `scripts/ci.sh --core-only` steps (backend, messaging server, web, site, string catalogs, app-logic type-check). This change touches none of them.

## Not done, and why

- **The SwiftUI page, the collector and the Tasks row are written but NOT COMPILED.** This session has Swift for Linux but no Xcode or iOS SDK, so SwiftUI, EventKit and the app's own stores can't be built here. The type-check covers the model only. The hosted Mac job (a pull request's CI) is the first build; I did not open one because nobody asked for it. If it fails to compile or a UI test about the Tasks screen breaks, that is expected work for the next session, not a surprise to hide.
- **Nothing on a device.** No row has been seen on a phone; the Face ID and Pause all paths are untested.
- **Home's "Teraz" card, the importance and loudness choices, triggers, the budget and the Doddy card in Messages (L1 to L4)** are not started. They wait for the design's decisions.

## Constitution evidence log

| Rule | Enforced by | Tests | Gap / claim to limit |
|---|---|---|---|
| DOD-08 verified status; unknown is never success | `errand` and `watch` map `unknown` to `cannotConfirm`; a parcel is closed only by the carrier's status | `testTasksRunning…UnknownIsNeverSuccess`, `testWatchesActive…`, `testParcels…` | The builder trusts the state the source gives it |
| DOD-06 nothing invented | Every row is one source record; no model, no inference | all | - |
| ADR-310 / ADR-723 private words | `OpenLoopTitle.hidden`; `OpenLoopsSources` passes it for a private note unless Face ID unlocked private notes | `testAPrivateNoteKeepsItsWordsHidden` | The collector is not compiled or run |
| DOD-11 observable privacy | No new data flow: tasks and parcels are read locally, a watch re-read is the request the Tasks screen already makes | the capability guard | "What leaves this iPhone" is unchanged and still correct; the page itself is not seen on a device |
| DOD-03 / DOD-10 no pressure | No notification or message is created | - | Applies to L1 and later, not here |

Claims to limit: do not say "Doddy keeps track of everything" or "reminds you" about L0. It is a read-only list; the rules behind it are tested, the screen is not compiled or seen yet.

## Next step and decisions needed

1. **Compile and check the page**: open a pull request (or build on a Mac), fix whatever the hosted Mac job reports, then walk the device checklist: with Calendar and Reminders on and off, Pause all on, a private note's reminder with and without Face ID, a task running and finished, a parcel ready, a watch active, a source that fails. Say what you saw.
2. **Name** for the page: "Na oku" is a working choice; "Pilnuję" or "Sprawy" are the alternatives.
3. **Home's "Teraz" card** and **L1 and later** wait for the design's owner decisions (section 16 of the design).
