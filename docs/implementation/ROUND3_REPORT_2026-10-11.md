# Round 3 report: "do all of them" (2026-10-11, ADR-280 to ADR-289)
Branch `claude/hopeful-fermat-1a63x0`, restarted from `claude/loving-dirac-uuxoux` after PR #25 merged. Owner's list of ten.

## Shipped (written and checked on Linux; nothing compiled with Xcode)
| # | Feature | ADR | Status doc |
|---|---|---|---|
| 1 | First real build | — | **BLOCKED here**: no Xcode in this session, and GitHub Actions starts no jobs (billing). Round 3 risks are added to `FIRST_BUILD_GUIDE.md` |
| 2 | Several changes on one card (clear a time, move several reminders) | 280 | `BULK_CHANGES_STATUS.md` |
| 3 | Event details by voice (place, add a note) | 281 | `EVENT_DETAILS_STATUS.md` |
| 4 | Repeating events and reminders by voice | 282 | `REPEATS_STATUS.md` |
| 5 | Alarms part 2: list, turn off, 9-minute snooze, Live Activity | 283 | `ALARMS_STATUS.md` |
| 6 | Shared lists update straight away (silent CloudKit push) | 284 | `SHARED_LISTS_STATUS.md` |
| 7 | "Added by Marta" on shared lists | 285 | `SHARED_LISTS_STATUS.md` |
| 8 | Photo of a handwritten list → Doddy list | 286 | `PHOTO_LIST_STATUS.md` |
| 9 | Add to a list from the Apple Watch (dictation) | 287 | `APPLE_WATCH_STATUS.md` |
| 10 | Birthday notifications from contacts (opt-in per person) | 288 | `BIRTHDAYS_STATUS.md` |
| 11 | Offline: say so, and keep a typed note on the phone | 289 | `OFFLINE_STATUS.md` |

## Tests actually run
- `scripts/ci.sh --core-only` on Linux (Swift 6.2.1) before each commit. Final run: **RESULT: PASS for core-only scope; iOS app NOT verified**. It covers:
  - DoddyCore: **672 tests, 0 failures**;
  - the app-logic type-check of the non-UI app files;
  - the capability guard (AlarmKit, CloudKit, Vision/PhotosPicker and Contacts each confined to their folders);
  - the agent specs;
  - the Polish catalogs;
  - the backend, gateway and messaging tests.
- Skipped: the messaging server database tests (no `TEST_DATABASE_URL`).
- New test files:
  - `BulkChangeTests`
  - `EventDetailsTests`
  - `CalendarRepeatTests`
  - `AlarmVoiceTests`
  - `SharedItemLabelTests`
  - `PhotoListTests`
  - `WatchListAddTests`
  - `BirthdayTests`
  - `OfflineTests`
- `swiftc -parse` on every new or changed SwiftUI, WidgetKit, AlarmKit, CloudKit, Contacts and watch file.

## NOT RUN
- **No Xcode build** of the app, widgets, watch app or watch widgets. In particular:
  - nothing in AlarmKit (it needs Xcode 26);
  - nothing in CloudKit subscriptions or participants;
  - nothing in the Contacts enumeration.
- Nothing was tried on a device, a watch or iCloud:
  - no silent push received;
  - no alarm snoozed;
  - no birthday notification delivered;
  - no photo read by Vision.

## Live voice agent
- Agent `agent_0501m4et27vyeawrwqfdxxfszfa6`, re-read first at `agtvrsn_8601m4n87tvmf83azq8ek4wtpst4` (39 tools).
- **Updated in place:**
  - `create_calendar_event` and `create_reminder` gained `repeat` and `repeat_until`;
  - `change_calendar_event` gained `new_location` and `add_note`.
- **New client tools:**
  - `delete_calendar_events` (`tool_8601m4n8q9x6eyjvf1a40p8ktj62`)
  - `move_reminders` (`tool_3901m4n8qapwe24s7y6fk8dm3r6e`)
  - `list_alarms` (`tool_4201m4n8qbg3f40agsjckezvanvq`)
  - `cancel_alarm` (`tool_7901m4n8qcz5f22r1ahkr926kqqm`)
- **New version:** `agtvrsn_7701m4n8vprrem78gmfjjmq77t96`, 43 tools. The stored prompt was read back from the update.
- **Kept as found:** the live agent carries `undo_last`, `upcoming_birthdays`, `calculate` and `convert_units`, with their prompt lines, from the unmerged `claude/affectionate-edison-ktc6i6`. This branch's app answers "unsupported" to them; that line needs joining. ADR-268 to ADR-279 are left for it (the default branch has since used 266 and 267).
- **Mixed versions:** an installed app from before this round answers "unsupported" to the four new tools, and the agent says it couldn't. Nothing is faked.

## Security and privacy
- **Birthdays:**
  - off by default, and opt-in per person;
  - contacts are read on the phone only;
  - the notification names the person only if the user lets notifications show note text;
  - the notification id is a hash, never the contact id.
- **"Added by":** shows the iCloud name of a person already on the share. Nothing new leaves the phone beyond the existing opt-in sharing.
- **Silent push:** it carries no content. It only wakes the app to fetch the zone it already shares.
- **Photo list:** Vision runs on the phone. The user edits the proposal before anything is saved.
- **Watch:** an item goes to the phone over WatchConnectivity and is read back before "Added".
- **Offline:** the typed note is kept on the phone only. Nothing is queued for the agent.

## Decisions for the owner
1. Fix GitHub Actions billing, or run a Mac build (`FIRST_BUILD_GUIDE.md`). Every feature above waits on a first compile.
2. Join `claude/affectionate-edison-ktc6i6`: the live agent already uses its four tools.
3. Shared lists still need a paid team, an iCloud container and the CloudKit schema in Production, now with the `addedBy` and `doneBy` fields.

## Next recommended step
The first real Xcode build, then the device checks in `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`. Stop adding features until it is done: three rounds of Swift are now uncompiled.

## Constitution evidence log
| Rule | Enforcing code | Tests run | Gaps | Claims to limit |
|---|---|---|---|---|
| DOD-07 scoped_action_approval | Bulk card: only ticked items change, one tap. Cancel-alarm card. Repeats and details are shown on the card before Add or Change. Birthdays: each person's switch is off | `BulkChangeTests`, `AlarmVoiceTests`, `CalendarRepeatTests`, `EventDetailsTests`, `BirthdayTests` | UI not compiled | Don't say "users can now…" before a build |
| DOD-08 verified_status_and_receipts | Bulk: each item stale-checked, written and read back; "partly" and "unknown" are never all-done. Repeat rule read back (`CalendarRepeat.from`). Alarm "turned off" only after the list no longer has it. Watch "Added" only after the phone reads it back | as above, `WatchListAddTests` | No device run | "Checked" means checked in code |
| DOD-09 correction_and_recovery | Untick before tapping; place and notes have stale checks; notes are only added to; offline note kept | `OfflineTests`, `EventDetailsTests` | Bulk deletes can't be undone (the card says so) | — |
| DOD-10 nonmanipulative_companionship | Birthday text is plain ("Maybe say hello."), with no streaks and no nudging | `BirthdayTests` | — | — |
| DOD-11 observable_privacy | Guard: Contacts only in Connections, Vision and PhotosPicker only in Photos, CloudKit only in Sharing, AlarmKit only in Alarms. Hashed birthday ids. Notification text gated by the existing setting | guard script, `BirthdayTests`, `SharedItemLabelTests` | — | Never "privacy guaranteed" |
