# Round report: "do all of them" (2026-10-11, ADR-250 to ADR-258)
Branch `claude/hopeful-fermat-1a63x0`. Owner's list of nine; item 1 was left to the other session at the owner's request.

## Shipped (written and checked on Linux; nothing compiled with Xcode)
| # | Feature | ADR | Status doc |
|---|---|---|---|
| 1 | Join `claude/sleepy-gates-f9najr`: left to `claude/peaceful-hopper-v3gx75`; the owner's choices are recorded for it | 250 | DECISIONS.md |
| 2 | List reminders at a place or time, by voice | 251 | `LIST_REMINDERS_STATUS.md` |
| 3 | Shopping mode (Live Activity for a list) | 252 | `SHOPPING_MODE_STATUS.md` |
| 4 | Undo for voice changes and imports | 253 | `UNDO_STATUS.md` |
| 5 | Delete events and reminders by voice | 254 | `DELETE_STATUS.md` |
| 6 | Alarms (AlarmKit, iOS 26) | 255 | `ALARMS_STATUS.md` |
| 7 | Evening wrap-up | 256 | `EVENING_WRAPUP_STATUS.md` |
| 8 | Watch complications and Smart Stack | 257 | `WATCH_COMPLICATIONS_STATUS.md` |
| 9 | Shared lists through iCloud (opt-in) | 258 | `SHARED_LISTS_STATUS.md` |

## Tests actually run
- `scripts/ci.sh --core-only` on Linux, Swift 6.2.1, before each commit. Final run: **RESULT: PASS for core-only scope; iOS app NOT verified**:
  - DoddyCore: 545 tests, 0 failures;
  - 14-file app-logic type-check;
  - the capability guard, agent specs and Polish catalogs;
  - backend, gateway and messaging tests.
- Skipped: the messaging server database tests (no `TEST_DATABASE_URL`).
- One flaky test of this round (`testWhatComesFromICloudIsCheckedLikeAnythingTyped`) depended on random UUID order. The test was fixed; the code was correct. It passed four runs in a row afterwards.
- `swiftc -parse` on every new or changed SwiftUI, App Intents, WidgetKit, CloudKit and AlarmKit file.

## NOT RUN
- **No Xcode build** of the app, widgets, watch app or the new watch extension. Hosted CI still starts no jobs (account billing; see `FIRST_BUILD_GUIDE.md`).
- Nothing was tried on a device or watch, against iCloud, or with AlarmKit.

## Live voice agent
- Agent `agent_0501m4et27vyeawrwqfdxxfszfa6` was re-read first. It had `said_time` guidance from `claude/peaceful-hopper-v3gx75`, which was kept.
- New version `agtvrsn_8201m4mf5fqhf9087wkrjz8kjenp`, 35 tools:
  - `delete_calendar_event` `tool_5501m4mf3h7cf9vtm3j2hrwnby39`;
  - `delete_reminder` `tool_1801m4mf3j0xfefs440sf2gp3ebm`;
  - `set_alarm` `tool_2701m4mf3jrre9ts0cksqvg7e2s5`;
  - `remind_me_about_note` gained `list` (its `said_time` kept).
- The stored prompt was read back from the update.
- **Drift to reconcile at the join:** the live agent's `said_time` parameters and prompt lines aren't in this branch's `voice-agent/` spec. This branch's app ignores unknown arguments. The change tools' live descriptions lack the "use delete_… for that" pointer sentence that the spec has.

## Security and privacy
- New data leaving the phone, only when the user opts in: a shared list's name and items go to the user's iCloud and to the people they invite. The data-flow screen and Privacy paragraph say so. It's off unless the build is set up for iCloud.
- Watch faces show only times, counts and a list name, never note text.
- Deletes are irreversible in Doddy, and the card says so before the tap.
- Alarms ring through Silent and Focus, and the card says so.

## Decisions for the owner
1. Turn on shared lists? This needs a paid team, an iCloud container and the CloudKit schema deployed to Production (`SHARED_LISTS_STATUS.md`).
2. App Group signing for the watch complications (`DODDY_WATCH_ENTITLEMENTS`).
3. Fix GitHub Actions billing, or do a Mac build (`FIRST_BUILD_GUIDE.md`). Everything above waits on a first compile.

## Next recommended step
The first real Xcode build (Way A or B in `FIRST_BUILD_GUIDE.md`), then the device checks. After that, the join of `claude/peaceful-hopper-v3gx75`, following ADR-250. Its vectors migration goes after `v9_list_shares`.

## Constitution evidence log
| Rule | Enforcing code | Tests run | Gaps | Claims to limit |
|---|---|---|---|---|
| DOD-07 scoped_action_approval | Delete, alarm, wrap-up and share cards; nothing preselected; stale checks at the tap | `CalendarChangeTests`, `AlarmTests`, `EveningWrapUpTests` | UI not compiled | Don't say "users can now…" before a build |
| DOD-08 verified_status_and_receipts | Read-back for delete, alarm, move, snapshot write, share and sync; "unknown" is never success | `SQLiteListShareTests`, `SharedListMergeTests` | No device or iCloud run | "Checked" means checked in code, not observed on a device |
| DOD-09 correction_and_recovery | Undo (ADR-253); Settings › Alarms; Leave/Stop sharing; failed syncs retry from the same base | as above | — | — |
| DOD-10 nonmanipulative_companionship | Wrap-up and complications: opt-in, no streaks, relevance only from the user's own times | `WatchComplicationTests`, `EveningWrapUpTests` | — | — |
| DOD-11 observable_privacy | Guard: AlarmKit only in Alarms, CloudKit only in Sharing; data-flow iCloud row | guard script, `SharedListDataFlowTests` | — | Never "privacy guaranteed" |
