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

## Files

- `Packages/DoddyCore/Sources/DoddyCore/OpenLoops/OpenLoops.swift`: types and the builder. Foundation only, so it builds on every platform (iPhone; Watch and Mac are paused and don't use it).
- `Packages/DoddyCore/Tests/DoddyCoreTests/OpenLoopsTests.swift`: 14 tests.
- `DECISIONS.md`: ADR-728.
- `docs/product/KEEP_TRACK_AND_REMIND_DESIGN.md`, `docs/product/PROACTIVE_COMPANION_PROMPT.md`: the design and the prompt proposal.

## Checks run (Linux, Swift 6.1.3, 5 Nov 2026)

| Check | Result |
|---|---|
| `swift test --filter OpenLoopsTests` (DoddyCore, with the repo's Linux SQLite flags) | 14 tests, 0 failures |
| Mutation 1: an `unknown` task changed to show as finished | the suite fails (3 assertions), file restored |
| Mutation 2: unreadable sources no longer skipped | the suite fails (1 assertion), file restored |
| `scripts/check_forbidden_capabilities.sh` | PASS |
| Full DoddyCore suite (`swift test`, same flags) | 2,389 tests, 0 failures (2,375 before this change plus the 14 new ones) |

Not run here: the other `scripts/ci.sh --core-only` steps (backend, messaging server, web, site, string catalogs, app-logic type-check). This change touches none of them.

## Not done, and why

- **No screen.** The SwiftUI page, Home's "Teraz" card, the Settings row, the string catalog entries (a sentence for each status, in Polish first) and the wiring that collects the inputs from the stores (`ErrandsModel`, the reminder and parcel repositories, `DeviceConnections`, the watches client) are **not written and NOT BUILT**. This session has Swift for Linux but no Xcode or iOS SDK, so SwiftUI cannot be compiled here, and CLAUDE.md says to leave the native build BLOCKED rather than write it unchecked. The hosted Mac job (the PR's CI) is the first place it can be compiled.
- **Nothing on a device.** No row has been seen on a phone.
- **The collection step is the risky part.** Reading the pieces together has to respect the Face ID lock and private notes (ADR-310, ADR-723), the Calendar and Reminders permissions and the parcel list being off by default. The builder takes whatever it is given, so the caller must pass `.hidden` for a private note and must put a source in `unavailable` rather than pass an empty list when it failed to read it.

## Constitution evidence log

| Rule | Enforced by | Tests | Gap / claim to limit |
|---|---|---|---|
| DOD-08 verified status; unknown is never success | `errand` and `watch` map `unknown` to `cannotConfirm`; a parcel is closed only by the carrier's status | `testTasksRunning…UnknownIsNeverSuccess`, `testWatchesActive…`, `testParcels…` | The builder trusts the state the source gives it |
| DOD-06 nothing invented | Every row is one source record; no model, no inference | all | - |
| ADR-310 / ADR-723 private words | `OpenLoopTitle.hidden` | `testAPrivateNoteKeepsItsWordsHidden` | The caller must decide hidden; not yet wired |
| DOD-11 observable privacy | Nothing leaves the phone; no network code | the capability guard | The page that shows it does not exist yet |
| DOD-03 / DOD-10 no pressure | No notification or message is created | - | Applies to L1 and later, not here |

Claims to limit: do not say "Doddy keeps track of everything" or "reminds you" about L0. It is a tested list builder; the user sees nothing yet.

## Next step and decisions needed

1. **App layer for L0** (needs a Mac or the hosted CI): the page, the strings, the collector, a Settings row; then a device check of the rows listed above. Recommended next milestone.
2. **Name** for the screen: "Na oku", "Pilnuję" or "Sprawy" (the last collides with tasks).
3. **L1 and later** wait for the design's owner decisions (section 16 of the design): the importance shape, a Doddy card in Messages, the new self-initiated rule, templates before a model.
