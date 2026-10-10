# Change events and reminders by voice: status (ADR-229)
Date: 2026-10-10. Owner: "do all of them" (item 5).

## What ships
- **Two new phone tools** in `voice-agent/tools.json`:
  - `change_calendar_event` takes the event's title and start exactly as `read_calendar` returned them. It also takes at least one of `new_start`, `new_end` or `new_title`.
  - `change_reminder` takes the reminder's exact title, plus either `new_due` or `done: true` (never both).
- **Parsing** (`VoiceToolRequest.parseEventChange` / `parseReminderChange`) uses the same strict date rules as adding: written out, local, not skipped or repeated by a clock change. A new start or due in the past gets a question back, never a guess.
- **Finding the item on the iPhone:**
  - Events: the same words (ignoring case, accents and punctuation) starting in the same minute. For an all-day event, the same day.
  - Reminders: open reminders with the same words.
  - If there is no match, the agent is told to read the calendar again or ask for the exact name. If there are several, it is given up to 4 and asked to let the user choose. Nothing changes in either case.
- **The card** shows "Now" and "After" (title and time), or the reminder, its list and its old and new due. The buttons are "Change" / "Don't change", or "Mark done" for a reminder being completed.
- **At the tap**, the app checks four things again:
  - permission and the Connections switch;
  - that the new time hasn't passed while the card waited;
  - that the event or reminder still looks exactly as it did on the card (found again by its id);
  - if anything differs, nothing is written ("changed elsewhere").
- **The write:**
  - A moved event keeps its length. An all-day event stays all-day, keeping its number of days.
  - A repeating event changes only this occurrence (`span: .thisEvent`).
  - A reminder's alarm set at the old due moves to the new due.
- **Read-back:** the event or reminder is read back from Calendar or Reminders before the agent hears "changed" or "completed". If the read-back fails, the agent hears "unknown", which is never treated as success.
- **What it never does:** delete anything, or change an event's place, notes or guests. The prompt's "cannot do yet" list now says so.
- **Pause all** blocks both tools. Both are logged in "What Doddy did" ("Change event" / "Change reminder").

## Files
- **Core:**
  - `CalendarChanges.swift`: drafts, matching, the plan, the stale-card checks, due comparison and replies;
  - `VoiceTools.swift`: cases, parsing and connections;
  - `ConnectionPause.swift`;
  - `ActivityLog.swift`.
- **App:**
  - `VoiceSessionController`: `PendingAction.changeEvent` / `.changeReminder`, the look-up before the card, and the checks at the tap;
  - `VoiceView`: the card, with Now/After rows;
  - `DeviceConnections.changeEvent` / `changeReminder`: the write and the read-back.
- **Agent:**
  - `voice-agent/tools.json`: 2 tools, 32 in total;
  - `voice-agent/instructions.md`: a tools line and the "cannot do yet" wording.
- **Tests:** `CalendarChangeTests` (6).

## Verified (Linux)
- `CalendarChangeTests` pass. They cover:
  - parsing (a change with nothing new is refused; a past new time is asked about; never new due and done together);
  - exact matching (same minute, same day for day-only, no match);
  - keeping the length, renaming, refusing an end before the start or a change that changes nothing;
  - all-day moves;
  - open reminders only;
  - the stale-card time check;
  - due comparison by wall clock;
  - Pause all and the activity title.
- `scripts/voice_agent_spec.py check` passes (32 tools). `swiftc -parse` passes on the changed app files.

## NOT RUN / UNVERIFIED
- No Xcode build and no device run. Not yet checked with real EventKit data:
  - whether a detached occurrence keeps its `calendarItemIdentifier` (the read-back also accepts the same `eventIdentifier`);
  - how moving an alarm behaves for reminders created in the Reminders app;
  - all-day multi-day moves across a daylight-saving change.
- **Live agent (2026-10-10):**
  - Both tools were created on agent `agent_0501m4et27vyeawrwqfdxxfszfa6` (`tool_3801m4m3zx3kfh8bzrf55j0qh541`, `tool_8901m4m3zy2verh9ssjb9kyrv2rc`). The prompt was updated (version `agtvrsn_5701m4m4268zfx2s83k8xcdg5bgm`, 32 tools) and its stored text was read back from the update.
  - The live prompt also keeps `said_time` guidance for `create_calendar_event`, `create_reminder` and `remind_me_about_note`. Another branch added it to the live agent; it isn't in this branch's `instructions.md` or `tools.json`, and this branch's app ignores that argument. Reconcile it when the lines are joined.
  - Not yet tried in a real conversation.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | A card with exactly what changes; the write runs only on the tap; checked again at the tap that the item still looks as shown | `testMatchesExactlyOneEventAndNeverGuesses`, `testTheCardCanGoStaleAndReadBackComparesWallClock` | UI not compiled |
| DOD-08 verified_status_and_receipts | "changed"/"completed" only after the read-back; otherwise "unknown" | `testRemindersMatchOpenOnesOnly` (reply prefix) | EventKit read-back is untested on a device |
| DOD-09 correction_and_recovery | No deletes; the old time is on the card; the user can change it back the same way | — | No one-tap Undo for a change |
| DOD-08 (agent) | Prompt rule: say "changed"/"completed" only from the result | live prompt read back | Not tried in a conversation |
| DOD-02 honesty_over_agreeableness | No match or several matches: nothing is guessed, the agent asks | `testMatchesExactlyOneEventAndNeverGuesses` | — |
