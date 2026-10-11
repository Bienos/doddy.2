# Round 5 report (2026-10-11, owner: "do all of them")

Branch `claude/hopeful-fermat-1a63x0`, ADR-310 to ADR-317 (`DECISIONS.md`, Round 5). The default branch took ADR-308 and ADR-309 while this round was being built and is merged in. **Nothing in this round has been compiled with Xcode.** There is no Xcode in this container, and GitHub Actions still doesn't start jobs.

## What was built

| # | Item | ADR | Where |
|---|---|---|---|
| 1 | Face ID lock and private notes | 310 | `PrivateNotes.swift`, `Features/Privacy/AppLock.swift`, filters at every way out |
| 2 | "Save to Doddy" in the Share Sheet | 311 | new `DoddyShare` target, `ShareInbox.swift`, `Shared/Share/ShareInboxFile.swift` |
| 3 | Doddy in iOS Focus modes | 312 | `FocusFilter.swift`, `Features/Focus/DoddyFocusFilter.swift` |
| 4 | To-dos from a voice memo | 313 | `MemoTodos.swift`, `MemoTodosCard` in `VoiceMemoViews.swift` |
| 5 | Rename and repeat reminders, replace notes | 314 | `ReminderDetails.swift`, `CalendarChanges.swift`, `DeviceConnections.swift`, the card |
| 6 | Gmail reply draft | 316 | `backend/src/tools/catalog.ts` (`draft_email_reply`), app routing |
| 7 | Read one Notion page | 316 | `backend/src/tools/catalog.ts` (`read_notion_page`), app routing |
| 8 | "Where I parked" widget | 315 | `WidgetSnapshot.parking`, `ParkingWidget`, `doddy://parking` |
| 9 | CarPlay | 317 | plan and entitlement request text only: `CARPLAY_PLAN.md` |

The live voice agent has both new tools, the new `change_reminder`/`change_calendar_event` fields and the round 5 prompt lines. It is version `agtvrsn_7001m4nt39q1fhwrhtsyqdegf35g` (51 tools), with the stored prompt read back (`voice-agent/README.md`).

## Tests actually run (Linux, this container)

`scripts/ci.sh --core-only`: **PASS for core-only scope**.
- DoddyCore: **770 tests, 0 failures** (Swift 6.2.1). New this round:
  - `ReminderRenameRepeatTests` and `EventReplaceNotesTests`
  - `PrivateNotesTests` (4)
  - `ShareInboxTests` (4)
  - `FocusFilterTests` (2)
  - `MemoTodosTests` (4)
  - `WidgetSnapshotTests` (parking)
  - `OnlineAccountsTests` (reply not found, activity rows)
- Backend: **168 of 168** (16 new in `reply-notion-tools.test.ts`, mock and fake Composio only).
- App-logic type-check: 17 files, now including `ShareInboxFile.swift`.
- Every changed SwiftUI, extension and widget file parses (`swiftc -parse`).
- Capability guard, voice agent spec (51 tools) and Polish catalog (1171 of 1199 strings) pass.
- **Skipped:** messaging server DB tests (no `TEST_DATABASE_URL`).
- **NOT RUN:** the iOS app, share extension, widget and watch builds.

## Manual checks still needed (device or Mac)

- **Face ID (ADR-310):**
  - lock on and off;
  - relock after a minute away;
  - a private note in lists, Find, detail and Siri;
  - the agent says "no match" for a note that is only private.
- **Share extension (ADR-311):**
  - share from Safari and from Notes, with and without the App Group;
  - the capture screen opens on return;
  - a second share replaces the first.
- **Focus (ADR-312):**
  - add the filter to a Focus, turn the Focus on and off;
  - Hey Doddy pauses and resumes;
  - the list order.
- **Memo to-dos (ADR-313):** a real English and Polish memo; adding to a list and to a new "To do" list.
- **Reminders and events (ADR-314):** renaming, a repeat added and stopped, notes replaced and cleared, and the stale check after an edit in Reminders.
- **Parking widget (ADR-315):** Home and Lock Screen; the tap opens Maps; saving and clearing update it.
- **Gmail and Notion (ADR-316):** a real Gmail account and a real Notion workspace through Composio.
  - Does `GMAIL_FETCH_EMAILS` with `verbose:false` return message and thread ids?
  - Does the pinned Notion toolkit have `NOTION_GET_PAGE_MARKDOWN`?

## Constitution evidence log

| Rule | Enforced by | Tests | Gap / claim to limit |
|---|---|---|---|
| External writes: an exact payload, explicit approval bound to it | **Reply draft:** the server builds the card from Gmail's own sender and subject. The approval is bound to the arguments, the user and that email. The draft goes to the email's conversation, and the agent can't set `to`/`subject`/`thread_id`. | backend `reply-notion-tools.test.ts` | Not run against real Gmail. |
| "Unknown" is never success and never blindly retried | A draft answer without an id gives `outcome_unknown`. The app's `cloudFailed` keeps the "maybe done" wording for writes. | backend tests; `testRepliesNeverClaimMoreThanIsKnown` | |
| A change is said to happen only when verified | **Reminders:** rename, repeat and notes are read back after the save, with a stale check on notes before it. **Lists:** memo to-dos report what the list read back. **Share:** the inbox is read back after the write. **Private set:** read back after each change. | `ReminderRenameRepeatTests`, `EventReplaceNotesTests`, `ShareInboxTests`, `PrivateNotesTests` | EventKit, the App Group and UserDefaults are not run on a device. |
| Never claim memory saved without storage | The share extension saves nothing; Save in the app does. Memo to-dos say "adding them doesn't save the note". | `ShareInboxTests` | |
| Tool, web, email and document content is data | The Notion page text is cut, cleaned and framed as information. The agent prompt says so for `read_notion_page`. | backend Notion tests | The model's behaviour isn't testable here. |
| Privacy | **Private notes:** filtered out of the agent, Siri, Ask Doddy, widgets, the watch, the call copy and the look-back. **Parking widget:** the snapshot has no position. **Share and Focus:** nothing leaves the iPhone. The privacy paragraph (EN/PL) and data-flow rows are updated. | `PrivateNotesTests`, `WidgetSnapshotTests` | **"Private" is not encryption.** The note's words are still in Doddy's database and in a backup file, which the toggle text doesn't say is excluded. Don't describe it as more than hidden and kept from those places. |
| No proprietary assets or fonts | None added. The widget uses SF Symbols. | | |
| Character | No new Doddy art. | | |

Don't say "implemented", "tested" or "privacy guaranteed" about any of this. It is built and checked on Linux only.

## Security and privacy risks

- **App Group file for shares:** the extension writes the shared text with complete file protection, and the app removes it once it is read. If the app is never opened, the text stays up to 7 days and is then dropped. It is never saved.
- **Reply draft sender:** the newest match could be the user's own sent mail. The card would then show the user's own address, and nothing is sent. Filtering that out is left for later.
- **Focus filter:** iOS hands the defaults back when the Focus ends. If it doesn't (a Focus deleted while active), Hey Doddy could stay paused. Settings shows "Paused by your Focus" so the user can see it.

## Decisions needed from the owner

1. **CarPlay:** is a spoken "yes" enough to approve a local, undoable note or list item in the car? Send the entitlement request (`CARPLAY_PLAN.md`)?
2. **Private notes in backups:** keep them in the encrypted backup file (today's behaviour), or leave them out?
3. **Share extension:** turn on `DODDY_SHARE_ENTITLEMENTS` with the App Group for the next device build?

## Next recommended step

The first real build on a Mac (Way B in `FIRST_BUILD_GUIDE.md`). Five rounds of SwiftUI haven't been compiled, and the round 5 risk list is in that guide.
