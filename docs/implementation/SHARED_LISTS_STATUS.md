# Shared lists through iCloud: status (ADR-263)
Date: 2026-10-11. Owner: "do all of them" (item 9), "iCloud sharing (Recommended)".

## Turning it on (owner decision; off by default)
Sharing needs a paid Apple developer team with iCloud. Until a build is set up like this, Doddy offers no sharing and never touches CloudKit.
1. In the developer account, create the container `iCloud.<bundle id>` and add iCloud (CloudKit) to the app id.
2. In `project.yml` (or on the `xcodebuild` line):
   - `DODDY_CLOUD_CONTAINER = iCloud.$(DODDY_APP_BUNDLE_IDENTIFIER)`;
   - `DODDY_APP_ENTITLEMENTS = Config/Doddy-AppGroup-iCloud.entitlements`, or `Config/Doddy-Push-AppGroup-iCloud.entitlements` with push.
3. Run it once against the CloudKit Development environment (record types `DoddyList` and `DoddyListItem` are created on first write). Then deploy the schema to Production in CloudKit Console before a TestFlight or App Store build.

## What ships
- **Share with people…** (list menu, only when set up):
  - a confirmation says the list's name and items are copied to the user's iCloud, everyone invited can see, add and tick items, and notes and other lists aren't shared;
  - the list goes to its own zone in the user's private CloudKit database (one `DoddyList` record for the name, one `DoddyListItem` per item), is read back, and the zone is shared with no public access;
  - Apple's sharing screen invites people (Messages, Mail, a link). **People** opens it again to add or remove people.
- **Joining:** opening the link starts Doddy (`CKSharingSupported`; a scene delegate receives it). A sheet shows the list's name and who shared it and what joining means. Nothing is joined until **Join list**. The list then appears in Doddy with the same items. If a list here already has that name, the joined one is called "Name (shared)" on this iPhone only.
- **Sync:** when Doddy comes to the front, when a shared list changes on this iPhone, when it opens, and from **Update now**. Each sync:
  1. reads iCloud;
  2. merges it three ways with this iPhone and the last sync (`SharedListMerge`):
     - a change on one side only wins;
     - the same field changed on both sides keeps iCloud's version;
     - an item deleted on one side but changed (words or tick) on the other is kept;
     - every add is kept;
     - positions are renumbered the same way on every device;
  3. writes each side only if it changed. iCloud writes only records still as fetched (`.ifServerRecordUnchanged`), all or nothing;
  4. reads both sides back, and only then remembers the merge as the last sync.
  A failed or unconfirmed sync remembers nothing, says "couldn't be updated, Doddy will try again", and the next sync starts from the same place.
- **Checks on what comes in:** iCloud content is checked like typed text (name and item rules, at most 200 items, no repeated ids). If someone renames the list to a name used by another list here, this iPhone keeps its name and sends it back.
- **Stop sharing / Leave:**
  - the owner's **Stop sharing** deletes the zone: the iCloud copy goes and invited people lose the list;
  - a participant's **Leave** removes it from their iCloud;
  - in both cases the list stays on this iPhone, unshared, checked by reading the zone back as gone;
  - **deleting** a shared list stops sharing (or leaves) first;
  - if the owner stops sharing or removes someone, that person's next sync says the list is no longer shared and keeps it.
- **On the list's screen:** "Shared through your iCloud" / "Shared with you through iCloud", the last update, problems, **Update now** and **People**.
- **Privacy:** What leaves this iPhone has a row for "Your iCloud (Apple) and the people you share lists with", active only while a list is shared. The Privacy paragraph in Settings has a sentence too.
- **No push:** changes from others arrive when Doddy is open or brought to the front. Background push for shared lists would need the push entitlement and is not built.

## Files
- **Core:** `SharedLists.swift` (`SharedListState`, `SharedListItem`, `SharedListMerge`, `ListShare`, `ListShareRepository`), `Lists.swift` (`replaceShared` requirement), `DataFlow.swift`.
- **Persistence:** migration `v9_list_shares`; `SQLiteListShareRepository`; `SQLiteListRepository.replaceShared`.
- **App, only CloudKit code** (`DoddyApp/Features/Sharing`):
  - `ListCloud.swift`: records, fetch, push, share, stop, accept;
  - `SharedListsController.swift`: share, join, sync, stop;
  - `SharingViews.swift`: scene delegate, Apple's sharing screen, invite sheet, status row.
- **Wiring:**
  - `ListViews` (menu, dialogs, status row);
  - `RootView` (invite sheet, sync on foreground);
  - `DoddyApp` (load and first sync);
  - `WidgetSync` (local changes);
  - `AppDelegate` (scene configuration);
  - `AppEnvironment`, `MemoryStore+Lists`, `DataFlowView`, `SettingsView`.
- **Config:**
  - `Config/Doddy-Info.plist` (`DoddyCloudContainer`, `CKSharingSupported`);
  - `Config/Doddy-AppGroup-iCloud.entitlements` and `Config/Doddy-Push-AppGroup-iCloud.entitlements`;
  - `project.yml` (`DODDY_CLOUD_CONTAINER`).
- **Guard:** CloudKit and `UICloudSharingController` only in `DoddyApp/Features/Sharing`.
- **Tests:** `SharedListMergeTests` (7), `SharedListDataFlowTests` (1), `SQLiteListShareTests` (2).

## Verified (Linux)
- Merge, validation, JSON, the data-flow row, `replaceShared` on real SQLite (including a taken name), and the link (save, read back, deleted with its list) pass. The full DoddyCore suite passes (545). `swiftc -parse` on every new and changed app file. The capability guard passes.

## NOT RUN
- No Xcode build. The CloudKit code has never been compiled or run against iCloud.
- Most likely to need fixes in Xcode:
  - Swift 6 Sendable checks on `CKRecord` and `CKShare.Metadata` crossing into the main-actor controller;
  - the exact tuple type of `recordZoneChanges(inZoneWith:since:)`;
  - `UICloudSharingController` presented from a SwiftUI sheet;
  - the scene-delegate class set from `configurationForConnecting` in a SwiftUI app.
- Never tried with two Apple IDs: invite, join, concurrent edits, stop sharing, leaving, being removed, iCloud signed out, storage full, offline.
- Not known: how long CloudKit takes before a change made on one iPhone can be fetched on another (usually seconds).

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Share only after the confirmation; join only after Join list; stop or leave only after its confirmation | — | UI not compiled |
| DOD-08 verified_status_and_receipts | Share, sync and stop are read back before they count; an unconfirmed sync remembers nothing | `testReplaceSharedWritesExactlyTheMergedStateAndReadsItBack`, `testTheLinkIsSavedReadBackAndGoesWithItsList` | Never run against CloudKit |
| DOD-09 correction_and_recovery | Three-way merge never drops an edited item; a failed sync retries from the same base; stop and leave keep the list here | `SharedListMergeTests` (7) | Concurrent-edit behaviour not tried with real people |
| DOD-11 observable_privacy | Off unless set up; only chosen lists; data-flow row and Privacy sentence; CloudKit confined by the guard | `testTheICloudRowFollowsSharedLists` | — |
| Data is not instructions | iCloud content is validated like typed text and never read as commands | `testWhatComesFromICloudIsCheckedLikeAnythingTyped` | — |
