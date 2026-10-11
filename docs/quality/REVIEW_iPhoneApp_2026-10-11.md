# Review — iPhone app (`DoddyApp`, `Shared`, `DoddyWidgets`, `DoddyWatch`, `project.yml`), 2026-10-11

Static, read-only review by five parallel reviewers, one per area; about 25,000 lines of Swift. Nothing was built: there is no Xcode here, and GitHub Actions currently assigns no runners in this repository. Items already in `REVIEW_DoddyCore_2026-10-11.md` were skipped. Line numbers are against `5913f80`.

**Compile status column:**
- **typecheck** = the file is covered by `scripts/typecheck_app_logic.sh` (Linux, Swift 6.2.1), so a fix can be type-checked here.
- **Xcode** = the file needs Xcode or the macOS CI to compile, so a fix cannot be verified here.

## E. Connected features (Calls, Updates, News, Today, check-ins, Home)

| # | Where | Problem → failure | Sev / rule | Compile |
|---|---|---|---|---|
| E1 | `Features/Calls/MemoryCopySync.swift:152-161`, `App/RootView.swift:160` | A failed or interrupted memory-copy upload is never retried. → A memory deleted while offline stays on the server and can be read out on calls. | medium, DOD-06/11 | Xcode |
| E2 | `Features/Calls/CallsModel.swift:48-55,96` | Turning the memory copy on: if the upload fails, the server side stays on while the switch shows off. | medium, DOD-11/08 | Xcode |
| E3 | `Features/Updates/UpdatesModel.swift:120`, `CallsModel.swift:96` | A consent write that succeeds, followed by a failed read-back, shows "nothing changed" while the server holds consent. | medium, DOD-08 | Xcode |
| E4 | `Features/MorningCheckIn/MorningCheckInViews.swift:101`, `MorningCheckInScheduler.swift:20`, `EveningWrapUp/EveningWrapUpViews.swift:215` | Unserialised reschedule tasks can leave duplicate or stale notifications. The read-back checks only the identifiers. | medium, DOD-08 | Xcode |
| E5 | `Features/News/NewsSettingsView.swift:27`, `NewsModel.swift:38` | Reappearing on screen overwrites unsaved draft settings, then "Saved." is shown. | low, DOD-08 | Xcode |
| E6 | `Features/Today/TodayCard.swift:68` | The old nudge is cancelled before the new one is scheduled. A failure leaves no nudge at all. | low, DOD-08 | Xcode |
| E7 | `EveningWrapUp/EveningWrapUpViews.swift:172` | `.unconfirmed` is counted as "couldn't be moved". | low, DOD-08 | Xcode |
| E8 | `CallsModel.swift:74` | "Save to memories" retry creates a duplicate when the server delete failed. | low, DOD-06 | Xcode |
| E9 | `ConnectedApps/ConnectedAppsView.swift:262,301` | Event "Save" has no in-flight guard, so a double tap saves twice. | low, DOD-06 | Xcode |
| E10 | `Home/HomeView.swift:118` | "Notes stay on this iPhone" is shown even with the memory copy on. | low, DOD-11 | Xcode |
| E11 | `CallsModel.swift:112` | A 502 on "Call me now" says "The text service didn't answer". | low, DOD-08 | Xcode |
| E12 | `News/NewsModel.swift:68,85` | Own topics with no keywords are silently dropped, then "Saved." is shown. | low, DOD-08 | Xcode |

## F. Notes, lists, reminders, alarms, Ask, Tidy-up

| # | Where | Problem → failure | Sev / rule | Compile |
|---|---|---|---|---|
| F1 | `Features/Sharing/SharedListsController.swift:151-169` | The shared-list sync merges a copy read before the network fetch, then overwrites. → An edit made during the sync is lost on every device. | **critical**, DOD-06 | Xcode |
| F2 | `TidyUp/TidyUpViews.swift:106,142` | Deleting a shared list from Tidy-up never stops sharing, so the iCloud copy and the invitees remain. | medium, DOD-11/07 | Xcode |
| F3 | `TidyUp/TidyUpViews.swift:127,144` | The Undo bar is hidden under the sheet, and the dialog omits that the reminder is cancelled. | medium, DOD-09 | Xcode |
| F4 | `NoteReminders/NoteReminderViews.swift:286` | Turning off "show note text" leaves already-delivered notifications showing the text. | medium, DOD-11 | Xcode |
| F5 | `Alarms/AlarmScheduler.swift:154,57,69` | A failed alarms read becomes "no alarms", which erases the AlarmBook, and a failed cancel is shown as off. | medium, DOD-08 | typecheck |
| F6 | `Lists/ListViews.swift:227` | Deleting an owned shared list doesn't warn that invitees lose it and that Undo won't re-share. | medium, DOD-07/09 | Xcode |
| F7 | `Lists/ListViews.swift:387` | The `ListUndoBar` "failed" state carries over to the next undo. | low, DOD-09 | Xcode |
| F8 | `NoteReminders/NoteReminderStore.swift:112-193` | Cancel, done and cancel-all swallow errors and clear receipts anyway. | low, DOD-08 | typecheck |
| F9 | `NoteReminders/NoteReminderSheet.swift:230`, `NoteReminderViews.swift:155` | "Notifications are off" is shown while the permission was never asked. | low, DOD-08 | Xcode |
| F10 | `Memories/FindMemoriesView.swift:44,218` | "I haven't found that" is shown next to list matches. | low | Xcode |

## G. App setup, storage, settings, backup and import

| # | Where | Problem → failure | Sev / rule | Compile |
|---|---|---|---|---|
| G1 | `Infrastructure/MemoryStore.swift:53-78`, `App/RootView.swift:160` | `reload()` bumps `revision` even after a failed read. → An empty memory copy is uploaded and the server copy is wiped. | medium, DOD-06 | typecheck (+RootView: Xcode) |
| G2 | `Settings/SettingsView.swift:184,562` | "Delete all N memories" counts only notes but deletes lists too. A user with only lists can't export. | medium, DOD-06/11 | Xcode |
| G3 | `Settings/SettingsView.swift:191,233` | "Memories live only on this iPhone" is wrong with the memory copy or shared lists on. Delete all doesn't stop iCloud sharing or wait for the empty-copy upload. | medium, DOD-11/06 | Xcode |
| G4 | `Infrastructure/MemoryStore.swift:57` | A failed lists read becomes `[]`. → Backups miss every list, "removed" receipts are false, and sharing links are dropped. | medium, DOD-08/06 | typecheck |
| G5 | `Import/NoteImportViews.swift:198`, `Infrastructure/MemoryStore+Lists.swift:224` | `importList` creates, then ticks in a separate step. A failed tick leaves a half-imported list that Undo misses. | low/medium, DOD-06/08 | typecheck (+view: Xcode) |
| G6 | `Infrastructure/ConversationLogStore.swift:40-64`, `ActivityLogStore.swift:34,52` | `clear()` and `remove()` change memory before the write. A failed write brings the logs back on relaunch. | low/medium, DOD-06 | typecheck / check |
| G7 | `Backup/BackupViews.swift:146,153` | Unreadable photos and recordings are silently skipped, then "Saved" is shown. | low/medium, DOD-08 | Xcode |
| G8 | `Infrastructure/URLSessionTransport.swift:25` | The Connected Apps transport follows redirects, so the bearer token can go to another host. | low/medium, DOD-11 | Xcode |
| G9 | `Infrastructure/Server/ServerKeychainStore.swift:7`, `KeychainSessionStore.swift:6` | Keychain items survive reinstall, unlike `KeychainCredentialStore`. | low, DOD-11 | Xcode |
| G10 | `project.yml:102` | The Contacts permission text says details stay on screen, but names go to the voice service. | low, DOD-11 | project.yml |

## H. Voice, Siri, Intents, Translator

| # | Where | Problem → failure | Sev / rule | Compile |
|---|---|---|---|---|
| H1 | `Voice/VoiceSessionController.swift:436` | Start, stop while connecting, then start again: the first conversation is never ended. → Its microphone stream to ElevenLabs stays open and its tool calls still arrive. | **critical**, DOD-11 | Xcode |
| H2 | `VoiceSessionController.swift:1223` | `fail()` doesn't end the SDK conversation, so the microphone can stay held. (Depends on the SDK; not verified.) | medium, DOD-11 | Xcode |
| H3 | `VoiceSessionController.swift:902` | Translator started mid-conversation keeps saved notes, profile and lists in the agent's context. | medium, DOD-11 | Xcode |
| H4 | `Voice/VoiceView.swift:331,342` | Event and reminder `notes` are written but not shown on the card. | medium, DOD-07 | Xcode |
| H5 | `Intents/ListIntents.swift:33,51` | Siri list lookup on cold launch reads lists before they load. → "List not found". | medium | Xcode |
| H6 | `Voice/ReadAloudController.swift:52,128` | Switching from note A to note B: A's cancel callback ends B's state. | medium, DOD-11 | Xcode |
| H7 | `VoiceSessionController.swift:1464` | Overlapping `propose_plan` calls share approvals, so a card can run with another plan's approval. | medium, DOD-07 | Xcode |
| H8 | `VoiceSessionController.swift:1702` | The place selection resets even when the new card is refused. → The reminder is set at an unchosen place. | low, DOD-07 | Xcode |
| H9 | `VoiceSessionController.swift:1288` | Queued tool calls run after End (e.g. list removal). | low, DOD-08 | Xcode |
| H10 | `VoiceSessionController.swift:954` | Translator copy goes to Universal Clipboard with no expiry. | low, DOD-11 | Xcode |
| H11 | `Voice/VoiceTokenClient.swift:18` | A new URLSession is created for every token fetch and never invalidated. | low | Xcode |

## I. Widgets, Watch, sharing, photos, voice memos

| # | Where | Problem → failure | Sev / rule | Compile |
|---|---|---|---|---|
| I1 | `Shared/Widgets/WidgetSnapshotFile.swift:41`, `Features/Widgets/WidgetSync.swift:51` | The read-back compares a sub-millisecond `Date`. A correct write "fails", so widgets aren't reloaded and keep showing deleted or turned-off content. (Python IEEE simulation: about 51% of round trips.) | **critical**, DOD-08/06/11 | Xcode (+ DoddyCore `WidgetSnapshot.make` fix: testable) |
| I2 | `Sharing/SharedListsController.swift:160-194` | A failing sync loops without pause (revision → `listsChanged` → `syncAgain`). → Battery drain and CloudKit throttling. | medium | Xcode |
| I3 | `SharedListsController.swift:196` | Delete all, or delete without Stop, leaves the iCloud zone and invitees. Same root cause as F2/G3. | medium, DOD-06/11 | Xcode |
| I4 | `Sharing/ListCloud.swift:205` | A failed share leaves content in iCloud, and every retry fails with `serverRecordChanged`. | medium, DOD-08/11 | Xcode |
| I5 | `Sharing/SharingViews.swift:60` | "Stop Sharing" in Apple's sheet leaves the link and the zone. The save error is ignored. | medium, DOD-08 | Xcode |
| I6 | `Watch/PhoneWatchLink.swift:76` | A verified save is answered "failed" when the reload fails. → Duplicate on retry. | low, DOD-08/06 | Xcode |
| I7 | `DoddyWatch/WatchViews.swift:35,98`, `PhoneWatchLink.swift:17` | The watch switch defaults to on, and there's no `.privacySensitive()`. → Pinned notes are readable on Always On. | low, DOD-11 | Xcode |
| I8 | `VoiceMemos/VoiceMemoAudio.swift:39` | Recordings in tmp are never cleaned at launch. | low, DOD-11 | Xcode |
| I9 | `VoiceMemos/VoiceMemoAudio.swift:50` | Recording continues in the background up to 5 min with no in-app sign. | low, DOD-11 | Xcode |
| I10 | `SharedListsController.swift:145` | Joining isn't atomic, so a duplicate "Name (shared)" can appear. | low | Xcode |
| I11 | `WidgetSync.swift:33`, `PhoneWatchLink.swift:37`, `DoddyWatch/WatchLink.swift` | Snapshot building and the content comparison are duplicated, and a comment has drifted. | low | Xcode |

## Strong points (confirmed by the reviewers)
- Keychain items are all `AfterFirstUnlockThisDeviceOnly`. The database and logs are file-protected. ATS has no exceptions.
- Cloud writes need a server approval bound to the exact arguments. EventKit and alarm writes report verified, unconfirmed and changed-elsewhere separately.
- List, Siri and readback intents need an unlocked phone. Widget ticks are ignored if the item changed.
- OAuth callbacks are matched to the attempt. Outbound calls are locked against parallel taps.
- Photos are re-encoded without EXIF or location. Orphaned photo and audio files are cleaned.
- Ask keeps history in memory only and shows its sources.

## Missing tests (summary)
`DoddyTests` has only 3 files. There are no tests for:
- `VoiceSessionController`, `SharedListsController`, `CallsModel`, `UpdatesModel`, `NewsModel`, `NoteReminderStore`, `AlarmScheduler`.
- A widget snapshot round trip with a real `Date.now`.
- `MemoryStore.reload` with failed reads.
- Delete all with shared lists or the memory copy on.

## Fix plan (owner asked to fix all)
1. **Fixes that can be verified here:** findings in DoddyCore, or in files covered by `typecheck_app_logic.sh` (F5, F8, G1 core part, G4, G5 core part, G6, I1 core part). These get tested and committed, then go in the PR.
2. **Fixes in files that need Xcode:** these go to a separate **draft PR marked "not compiled"**. It must pass the macOS CI (`xcodebuild` in `.github/workflows/ios.yml`) before merging. That CI can't run until GitHub Actions assigns runners again.
