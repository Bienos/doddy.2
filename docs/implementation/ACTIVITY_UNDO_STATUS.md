# Undo in "What Doddy did", and "undo that" by voice: status (ADR-265, ADR-268)

> Not to be confused with `UNDO_STATUS.md` (ADR-258 on the default line: Undo for a change on the voice screen, 10 minutes). This file is Undo in Settings → What Doddy did (ADR-265), for adds and changes, and "undo that" by voice (ADR-268). After either Undo succeeds the other is cleared; both use `EventChange.reversed`.
Date: 2026-10-11. Owner: "build next things", after Claude proposed "Undo the last action" as the first next build.

## What ships
- **An Undo button** on a row in Settings → What Doddy did, for 24 hours after Doddy:
  - **added an event**: Undo removes that event;
  - **added a reminder**: Undo removes that reminder;
  - **moved or renamed an event** (ADR-229): Undo puts back its old time and name;
  - **changed a reminder's due, or marked it done** (ADR-229): Undo puts back the old due, or opens it again.
- **Only for what Doddy did and checked.** The row keeps what Undo needs only when the app's own reply says the change was made and read back ("added:", "changed:", "completed:"). There is no Undo for "Not sure", "Didn't happen", "You said no", or "Already there, nothing added" (Doddy wrote nothing, so the reminder is the user's).
- **A confirmation sheet first**, naming exactly what will happen. For example: "Remove “Dentist” from Calendar?" — "Doddy added this event for … Only this event is removed, and only if it hasn't changed since." Buttons: Remove / Put back / Mark not done, and Cancel.
- **Checked again at the tap, before anything is read or written:** Pause all, and the Calendar or Reminders switch in Settings, Connections. Then iOS permission.
- **It must still look exactly as Doddy left it**, or nothing is written and the row says "Not undone: it changed in Calendar since Doddy did this, so Doddy left it alone."
  - Added event: found by the event identifier read back right after Doddy saved it. Same title, start, end and all-day, and not made repeating since.
  - Added reminder: exactly one open reminder carrying Doddy's marker for that reminder, with the same title and due. The user's own reminder with the same words is never touched.
  - Moved event: found at the time Doddy moved it to, by the same occurrence id as before, looking exactly as Doddy left it. Then the same guarded write and read-back as a change by voice.
  - Changed reminder: found by its id, with the same title and Doddy's due (or still done, for one Doddy ticked off).
- **Read back after the write.** The row says "Calendar · Undone" / "Reminders · Undone" only when Calendar or Reminders agrees. Otherwise "Doddy couldn't confirm the undo. Check Calendar before trying again", and Undo is not offered again.
- **Retry only when nothing was written:** a connection off, Pause all, no permission, Reminders unreadable, or a write that threw while a fresh look shows the item unchanged.
- **Fixed on the way:** a checked change by voice ("changed: …", "completed: …") was listed as "Not sure it happened". It now shows as "Done". "not changed: …" and "not found: …" show as "Didn't happen".

## What it never does
- Remove or change anything Doddy didn't add or change, or anything changed since.
- Run from the voice agent. Undo is a button the user taps. The voice agent's tools and prompt are unchanged.
- Apply to notes, lists, timers, opened apps, messages, Gmail drafts, Todoist tasks or plan-card steps (not yet; see Next).

## Files
- **Core:** `ActivityUndo.swift` (new: what to put back, the "still as Doddy left it" checks, the reversed event plan, the sheet text, Pause/switch gating, the result on the row). `ActivityLog.swift` (`undo` and `undoState` on an entry, kept only for a done change; the outcome fix). `CalendarEventSummary`, `EventChangePlan` and `ReminderDue` are now `Codable`. The occurrence id format moved into DoddyCore (`CalendarEventSummary.occurrenceID`), so the iPhone and Undo build it the same way.
- **App:**
  - `DeviceConnections.addEvent` returns the event identifier with a verified add.
  - `DeviceConnections.undo(_:)`: the guarded write and the read-back.
  - `VoiceSessionController`: records what Undo needs for confirmed adds and changes.
  - `ActivityView`: the Undo button, the sheet and the row status.
- **Tests:** `ActivityUndoTests` (12).

## Verified (Linux, Swift 6.1.2)
- `ActivityUndoTests` (12) pass. They cover:
  - kept only for done changes (not for already there, not sure, declined, failed);
  - the outcome fix;
  - the 24-hour window, including a clock set back;
  - row text and the retry rules after each result;
  - old saved entries still decode, and every kind of undo survives saving;
  - exact-match rules for added events and reminders (the user's own same-named reminder, two copies, renamed, moved, ticked);
  - changed reminders;
  - the reversed event plan;
  - occurrence ids;
  - the sheet text;
  - Pause all and the switch.
- A planted bug (Undo allowed for a reminder ticked off since) was caught by a failing test, then removed.
- `scripts/ci.sh --core-only`: PASS. That's 620 DoddyCore tests, 14 non-UI app files type-checked, guards, voice agent spec, Node services. iOS app NOT RUN.
- `swiftc -parse` passes on `ActivityView.swift`, `DeviceConnections.swift` and `VoiceSessionController.swift`. These import SwiftUI/EventKit, so they are **not type-checked** on Linux.

## NOT RUN / UNVERIFIED
- **No Xcode build and no device run.** The EventKit calls (`remove(_:span:commit:)`, `remove(_:commit:)`, `reset()` after a failed save) and the SwiftUI sheet have only been syntax-checked.
- **EventKit unknowns:**
  - `eventIdentifier` can change after a calendar sync. Undo then finds nothing and leaves it alone, which is safe but means no Undo.
  - A detached occurrence of a repeating event may not keep its `calendarItemIdentifier` (same unknown as ADR-229). Undo then leaves it alone.
- **English only:** the new row and sheet strings are not in `l10n/pl.json`. The rest of What Doddy did isn't translated either.
- **Mac checklist:** U1–U6 below.

## Mac checklist (add to MAC_VERIFICATION_CHECKLIST)
| # | Do this | Expect |
|---|---|---|
| U1 | Ask Doddy to add an event; Settings → What Doddy did → Undo → Remove | The event is gone from Calendar; the row says "Calendar · Undone" |
| U2 | Ask Doddy to add a reminder; rename it in Reminders; Undo | "Not undone: it changed in Reminders since Doddy did this…"; the reminder stays |
| U3 | Have your own reminder "Buy milk", ask Doddy to add "Buy milk" (already there); open What Doddy did | No Undo on that row |
| U4 | Ask Doddy to move an event; Undo → Put back | The event is at its old time and name; row "Undone" |
| U5 | Ask Doddy to mark a reminder done; Undo → Mark not done | Open again in Reminders |
| U6 | Turn on Pause all; Undo | "Not undone: Connections are paused in Settings. Nothing changed."; Undo still offered |

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-09 correction_and_recovery | Undo for Doddy's own adds and changes; retry only when nothing was written | `testAfterUndoTheRowSaysWhatHappenedAndOnlyNothingWrittenCanBeRetried` | Device untested; notes, lists and plan steps not covered |
| DOD-07 scoped_action_approval | Sheet names the exact item and result; write only after the tap; Pause/switch/permission checked at the tap | `testPauseAllAndTheConnectionSwitchStopUndoBeforeAnythingIsTouched`, `testTheSheetNamesExactlyWhatWillHappen` | UI not compiled |
| DOD-08 verified_status_and_receipts | "Undone" only after read-back; otherwise "not sure", never retried; Undo kept only for checked changes | `testUndoIsKeptOnlyForChangesDoddyMadeAndChecked`, `testVerifiedChangesAreDoneAndUnverifiedOnesAreNot` | EventKit read-back untested on a device |
| DOD-02 honesty_over_agreeableness | Anything changed since is left alone and the row says so; the user's same-named reminder is never matched | `testAnAddedReminderIsFoundByDoddysMarkerAndMustBeOpenAndUnchanged`, `testAnAddedEventIsRemovedOnlyIfItIsExactlyAsDoddyLeftIt` | — |
| DOD-11 observable_privacy | What Undo keeps (title, times, local ids) stays in the existing on-device activity file, pruned after 30 days | `testOlderEntriesWithoutUndoStillDecodeAndUndoSurvivesSaving` | — |

## Decisions for the owner
- **Removing items: accepted by the owner 2026-10-11** ("Undo may remove items"). ADR-229 said Doddy never deletes anything. Undo now removes an event or reminder, **but only one Doddy itself added in the last 24 hours, unchanged since, after the user confirms**. Accept, or limit Undo to changes only.
- **24-hour window.** Proposed; could be shorter (e.g. 1 hour) or last until the entry is pruned.

## Next
- "Undo that" by voice (a new agent tool; needs a live agent update).
- Undo for plan-card steps, notes saved by voice, and list changes.

## ADR-268 (2026-10-11, owner: "build next"): plan steps and "undo that" by voice
- **Plan-card steps.** An event or reminder added by a step of a plan card now gets Undo in What Doddy did, exactly like one from its own card. `runPlanStep` returns what Undo needs, and `logPlanStep` keeps it. As before, an unticked or blocked step never ran, so it gets no Undo.
- **"Undo that" by voice:** a new phone tool, `undo_last` (no parameters, 36 tools in total).
  - **What it picks:** the newest row **from this conversation** that can still be undone. Never one from an earlier conversation; for those the agent points to Settings, What Doddy did.
  - **The card** on the conversation screen shows the same question and explanation as the Settings sheet. Buttons: Remove / Put back / Mark not done, and "Keep it".
  - **At the tap:**
    - the row is read again (it may have been undone in Settings, or the day passed);
    - Pause all and the switch are checked;
    - then the same `DeviceConnections.undo`.
  - **The row** records the result (`ActivityLog.undid`). No new row is added.
  - **What the agent hears:** "undone: …" only after the read-back. Otherwise "not undone: … left it alone", "failed: not undone. …" or "unknown: … check".
  - **Other limits:** "Nothing to undo" when there's nothing from this conversation. Blocked by Pause all and by translator mode.
- **Prompt:** one tools line ("undo_last …; say it was undone only when the result starts with undone"). The cannot-do line now reads "delete events or reminders (except undoing one you just added, with undo_last)".
- **Polish:** the card's buttons are translated ("Cofnij", "Zostaw"); the question and explanation come from DoddyCore in English.
- **Tests:** `ActivityUndoTests` now has 16 tests (4 new):
  - an added reminder only when Doddy wrote it;
  - a plan step keeps Undo;
  - "undo that" scope (this conversation, newest, never a not-sure or already-undone row);
  - the replies.
- A planted bug (dropping the "this conversation" rule) was caught. `scripts/ci.sh --core-only` PASS (640 DoddyCore tests; voice agent spec 36 tools).
- **NOT RUN:**
  - the live agent has no `undo_last` yet;
  - iOS app not built: the card and `VoiceSessionController` are syntax-checked only.
- **Mac checklist:** U7–U9.

| # | Do this | Expect |
|---|---|---|
| U7 | Plan card with an event and a reminder → Add; What Doddy did | Both steps show Undo |
| U8 | Ask Doddy to add a reminder, then say "undo that" → Remove | Card names the reminder; it's gone from Reminders; Doddy says it was undone |
| U9 | New conversation, say "undo that" | Doddy says there's nothing to undo from this conversation and points to What Doddy did |

**Live agent updated 2026-10-11** (owner approved): see the last paragraph of `DECISIONS.md` for tool ids and versions; `voice_agent_spec.py compare` MATCH.
