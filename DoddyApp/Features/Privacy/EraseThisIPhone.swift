import ActivityKit
import DoddyCore
import Foundation
import UserNotifications

/// "Erase everything on this iPhone": the app's side of the plan. The rules are in DoddyCore, tested on Linux
/// (`DeviceErasure`: one step per store, each with an erase and a read-back, "erased" only when every store was read
/// back as empty, DOD-08; `DeviceStoreID`: the list of stores and the order; `DevicePreferences` and `DeviceKeychain`: what is
/// kept and why). This file gives each store its real erase and its real read-back, through the store's own code where it
/// has one (so a model holding things in memory can't write its old state back) and with a look at the file system where
/// there are files. What each store holds, and what is kept on purpose: `docs/architecture/DEVICE_DATA_STORES.md`.
///
/// The `switch` in `step(for:)` lists every `DeviceStoreID` without a `default`, so a new store is a compile error until it
/// has a step (`DeviceStoreInventoryTests` also checks the file names each one).
///
/// Not compiled on Linux: the hosted `ios-build` job is its first compile. Not run on a device.
@MainActor
enum EraseThisIPhone {
    /// Why a step could not erase or read back its store. For logs; the person sees the store's name.
    enum Failure: Error {
        case notDone(String)
    }

    /// Why nothing was erased.
    enum Refusal: Equatable {
        /// The microphone is still in use (a conversation, a voice memo or a recording that wouldn't stop).
        case listening
        /// The screen is being shared with Doddy; the sharing runs in another process and would write the picture again.
        case sharingScreen
    }

    enum Outcome {
        case refused(Refusal)
        case finished(DeviceErasureReport, scope: DeviceErasureScope)
    }

    // MARK: Running the plan

    /// Stops what is still running, runs every step, then brings the screens up to date. `scope`: `.keepSignIn` (the default)
    /// leaves the signed-in account signed in; `.afterAccountDeleted` is for right after a Doddy account was deleted and
    /// confirmed, and erases the sign-in items and server ties too.
    static func run(store: MemoryStore, profiles: ProfileStore, scope: DeviceErasureScope = .keepSignIn) async -> Outcome {
        // A conversation, a voice memo or a recording still going would write into the stores being emptied. Ended through
        // the same call Siri's "Stop listening" uses; a recording being made is saved first, then erased with the rest.
        let stopped = await ListeningStop.stopAll()
        guard stopped.stillOpen.isEmpty else { return .refused(.listening) }
        guard !ScreenShareFiles.isSharing() else { return .refused(.sharingScreen) }

        let steps = DeviceStoreID.erasureOrder
            .filter(scope.requiredStores.contains)
            .map { step(for: $0, store: store, profiles: profiles, scope: scope) }
        let report = await DeviceErasure.run(steps: steps, required: scope.requiredStores)
        await finish(report, store: store, scope: scope)
        return .finished(report, scope: scope)
    }

    /// For the account deletion's tail (`DoddyAccountServers.deleteAccount(thenErase:)`): the erase that follows a confirmed
    /// deletion, as the line the account's message gets.
    static func lineAfterAccountDeleted(store: MemoryStore, profiles: ProfileStore) async -> String {
        let outcome = await run(store: store, profiles: profiles, scope: .afterAccountDeleted)
        return message(for: outcome, signedIn: false).text
    }

    /// After the steps: what the screens hold is read again (it is nothing now), the widgets and the Home Screen menu follow,
    /// and, only when every store was confirmed empty, nobody owns this iPhone's data any more and the signed-in account
    /// takes the empty iPhone over (decision 2026-11-12-local-data-owner). With anything unconfirmed the owner stays, so
    /// what is left is never handed to the next account.
    private static func finish(_ report: DeviceErasureReport, store: MemoryStore, scope: DeviceErasureScope) async {
        await store.reload()
        await ErrandsModel.shared.load()
        WidgetSync.shared.refresh()
        QuickActions.install()
        DoddyShortcuts.updateAppShortcutParameters()
        guard report.isErased else { return }
        LocalDataOwner.forgetOwner()
        if scope.keepsSignIn { await DoddyAccountServers.claimLocalData() }
    }

    // MARK: The steps

    /// Whether iOS confirmed clearing the search index (it can't be read back).
    private static var spotlightCleared = false

    private static func step(
        for id: DeviceStoreID, store: MemoryStore, profiles: ProfileStore, scope: DeviceErasureScope
    ) -> DeviceErasureStep {
        switch id {
        // MARK: iCloud and the server copy first
        case .sharedListsInICloud:
            // Stopped while the lists and their links still exist: the copy in the person's iCloud goes, the people invited
            // lose the list, and the person leaves the lists others shared with them.
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    let failed = await SharedListsController.shared.stopEveryShare()
                    if !failed.isEmpty { throw Failure.notDone("\(failed.count) shared lists are still shared") }
                },
                verifyEmpty: { @MainActor in try await store.environment.listShareRepository.shares().isEmpty })

        case .memoryCopyOnServer:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    let sync = MemoryCopySync.shared
                    sync.stop() // Forgets an older answer, so the read-back reads this one.
                    try await sync.uploadNow([])
                },
                verifyEmpty: { @MainActor in
                    let sync = MemoryCopySync.shared
                    // Nothing was kept there when the switch is off, or when this iPhone's notes were never sent to the
                    // signed-in account (decision 2026-11-12-local-data-owner).
                    guard sync.isOn, DoddyAccountServers.mayUploadLocalData else { return true }
                    if case .copied(let count, _) = sync.status { return count == 0 }
                    return false
                })

        // MARK: The notes database
        case .notesAndLists:
            // Notes, lists and their items, photos and voice memos' rows, corrections, reminders, the search index.
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in try await store.deleteAll() },
                verifyEmpty: { @MainActor in
                    let environment = store.environment
                    guard try await environment.memoryRepository.list(limit: 1).isEmpty else { return false }
                    guard try await environment.listRepository.allItems().isEmpty else { return false }
                    guard try await environment.memoryRepository.allCorrections().isEmpty else { return false }
                    guard try await environment.photoRepository.allPhotos().isEmpty else { return false }
                    return try await environment.audioRepository.allAudio().isEmpty
                })

        case .learnedFacts:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    if let learning = store.learning {
                        try await learning.deleteAll()
                    } else if let service = store.environment.learningService {
                        try await service.deleteAll()
                    } else {
                        throw Failure.notDone("the learning store isn't open")
                    }
                },
                verifyEmpty: { @MainActor in
                    guard let service = store.environment.learningService else { throw Failure.notDone("the learning store isn't open") }
                    guard try await service.facts.list(status: nil).isEmpty else { return false }
                    guard try await service.procedures.list(status: nil).isEmpty else { return false }
                    return try await service.outcomes.list(since: .distantPast, limit: 1).isEmpty
                })

        case .profile:
            // The "About you" answers. Where the person is in the first-run steps is a flag, kept (docs).
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in try await profiles.forget() },
                verifyEmpty: { @MainActor in try await store.environment.profileRepository.profile().isEmpty })

        case .callCases:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in try await store.environment.callCaseRepository.deleteAll() },
                verifyEmpty: { @MainActor in try await store.environment.callCaseRepository.list().isEmpty })

        case .errands:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in try await store.environment.errandRepository.deleteAll() },
                verifyEmpty: { @MainActor in try await store.environment.errandRepository.list().isEmpty })

        case .messagesThread:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    try await store.environment.messageThreadRepository.deleteAll()
                    // The files Doddy made until now are not offered again (decision 2026-11-12-deleted-files-stay-gone), and an
                    // open Messages screen empties what it holds in memory.
                    FilesShownSinceStore.conversationDeleted()
                    NotificationCenter.default.post(name: ThreadInbox.erased, object: nil)
                },
                verifyEmpty: { @MainActor in try await store.environment.messageThreadRepository.recent(limit: 1).isEmpty })

        case .recordings:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    guard let repository = store.environment.recordingRepository else { throw Failure.notDone("recordings aren't available") }
                    try await repository.deleteAll()
                },
                verifyEmpty: { @MainActor in
                    guard let repository = store.environment.recordingRepository else { throw Failure.notDone("recordings aren't available") }
                    return try await repository.allIDs().isEmpty
                })

        case .trainingLog:
            // Its own SQLite file, made only when the person turned the log on: nothing is opened or made for a phone that
            // never did. The yes is taken back (a delete doesn't), the sessions are deleted and read back.
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    guard TrainingLogDatabase.exists else { return }
                    let log = TrainingLogModel.shared
                    await log.setKeeping(false)
                    guard await log.deleteAll() else { throw Failure.notDone("the training log") }
                },
                verifyEmpty: { @MainActor in
                    guard TrainingLogDatabase.exists else { return true }
                    let log = TrainingLogModel.shared
                    await log.load() // Reads the file again.
                    return log.problem == nil && log.sessions.isEmpty && !log.consent.granted
                })

        // MARK: Files in the app's own folders
        case .notePhotoFiles:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    if let directory = store.environment.photoFiles.directory { try FolderErasure.eraseContents(of: directory) }
                },
                verifyEmpty: { @MainActor in
                    guard let directory = store.environment.photoFiles.directory else { return true }
                    return try FolderErasure.isEmpty(directory)
                })

        case .noteAudioFiles:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    if let directory = store.environment.audioFiles.directory { try FolderErasure.eraseContents(of: directory) }
                },
                verifyEmpty: { @MainActor in
                    guard let directory = store.environment.audioFiles.directory else { return true }
                    return try FolderErasure.isEmpty(directory)
                })

        case .recordingFiles:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in store.environment.recordingFiles.removeAll() },
                verifyEmpty: { @MainActor in
                    guard let directory = store.environment.recordingFiles.directory else { return true }
                    return FolderErasure.fileIsGone(directory)
                })

        case .conversationTranscripts:
            // Recaps still being written for these conversations are dropped, the history is rewritten empty and read back
            // (`ConversationDeletion`), then the folder is emptied.
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    guard ConversationDeletion.clearAll(logs: .shared) else { throw Failure.notDone("the remembered conversations") }
                    if let folder = DeviceFolders.applicationSupport("Conversations") { try FolderErasure.eraseContents(of: folder) }
                },
                verifyEmpty: { @MainActor in
                    guard ConversationLogStore.shared.logs.isEmpty else { return false }
                    guard let folder = DeviceFolders.applicationSupport("Conversations") else { return true }
                    return try FolderErasure.isEmpty(folder)
                })

        case .activityList:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    ActivityLogStore.shared.clear()
                    if let folder = DeviceFolders.applicationSupport("Activity") { try FolderErasure.eraseContents(of: folder) }
                },
                verifyEmpty: { @MainActor in
                    guard ActivityLogStore.shared.entries.isEmpty else { return false }
                    guard let folder = DeviceFolders.applicationSupport("Activity") else { return true }
                    return try FolderErasure.isEmpty(folder)
                })

        case .unfinishedNotes:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    UnfinishedNoteStore.shared.removeAll()
                    if let folder = DeviceFolders.applicationSupport("Drafts") { try FolderErasure.eraseContents(of: folder) }
                },
                verifyEmpty: { @MainActor in
                    guard UnfinishedNoteStore.shared.book.notes.isEmpty else { return false }
                    guard let folder = DeviceFolders.applicationSupport("Drafts") else { return true }
                    return try FolderErasure.isEmpty(folder)
                })

        case .invoiceDraft:
            return DeviceErasureStep(
                store: id,
                erase: {
                    if let folder = DeviceFolders.applicationSupport("Invoices") { try FolderErasure.eraseContents(of: folder) }
                },
                verifyEmpty: {
                    guard let folder = DeviceFolders.applicationSupport("Invoices") else { return true }
                    return try FolderErasure.isEmpty(folder)
                })

        case .madeFiles:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    guard LocalMadeFilesStore.shared.removeAll() else { throw Failure.notDone("the files Doddy made") }
                    if let folder = DeviceFolders.applicationSupport("MadeFiles") { try FolderErasure.eraseContents(of: folder) }
                },
                verifyEmpty: { @MainActor in
                    guard LocalMadeFilesStore.shared.files.isEmpty else { return false }
                    guard let folder = DeviceFolders.applicationSupport("MadeFiles") else { return true }
                    return try FolderErasure.isEmpty(folder)
                })

        case .trips:
            return DeviceErasureStep(
                store: id,
                erase: {
                    if let folder = DeviceFolders.applicationSupport("Trips") { try FolderErasure.eraseContents(of: folder) }
                },
                verifyEmpty: {
                    guard let folder = DeviceFolders.applicationSupport("Trips") else { return true }
                    return try FolderErasure.isEmpty(folder)
                })

        case .trainingPlan:
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    guard TrainingPlanStore.shared.delete() else { throw Failure.notDone("the training plan") }
                },
                verifyEmpty: { @MainActor in
                    let plan = TrainingPlanStore.shared
                    plan.load() // Reads the file again.
                    return plan.state == .nothingKept
                })

        case .studio:
            // Studio's topics and the items opened here. The items themselves are on Doddy's server (said in the doc); the
            // opened copies are in Caches (`workingFiles`).
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in StudioModel.shared.forgetLocal() },
                verifyEmpty: { @MainActor in StudioModel.shared.topics.isEmpty && StudioModel.shared.details.isEmpty })

        case .workingFiles:
            // Temporary files, caches and Documents: everything Doddy wrote there for its own work, whatever its name, so a
            // file nobody remembered can't stay. iOS's own entries in them are left alone.
            return DeviceErasureStep(
                store: id,
                erase: {
                    var failed = false
                    for folder in DeviceFolders.working {
                        do {
                            try FolderErasure.eraseContents(of: folder, keeping: DeviceFolders.systemNames(in: folder))
                        } catch {
                            failed = true
                        }
                    }
                    if failed { throw Failure.notDone("temporary files") }
                },
                verifyEmpty: {
                    for folder in DeviceFolders.working {
                        guard try FolderErasure.isEmpty(folder, ignoring: DeviceFolders.systemNames(in: folder)) else { return false }
                    }
                    return true
                })

        // MARK: The App Group folder
        case .sharedContainer:
            // The widgets' snapshot, an item waiting from "Save to Doddy", the picture of the screen. "Library" is the folder
            // iOS keeps in every group container. A build signed without the App Group has no folder, so nothing is there.
            return DeviceErasureStep(
                store: id,
                erase: {
                    if let folder = ScreenShareFiles.folder { try FolderErasure.eraseContents(of: folder, keeping: ["Library"]) }
                },
                verifyEmpty: {
                    guard let folder = ScreenShareFiles.folder else { return true }
                    return try FolderErasure.isEmpty(folder, ignoring: ["Library"])
                })

        // MARK: Preferences
        case .preferences:
            // Every key is erased unless `DevicePreferences` keeps it with a reason. Logbook's counts are forgotten through its
            // own model first (its switch stays as the person set it), so it can't write them back.
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    Logbook.shared.accountSignedOut()
                    guard let domain = Bundle.main.bundleIdentifier else { throw Failure.notDone("no bundle identifier") }
                    DefaultsErasure.erase(.standard, domain: domain, scope: scope)
                },
                verifyEmpty: {
                    guard let domain = Bundle.main.bundleIdentifier else { throw Failure.notDone("no bundle identifier") }
                    return DefaultsErasure.leftover(.standard, domain: domain, scope: scope).isEmpty
                })

        // MARK: Keychain
        case .keychainPersonalKeys:
            return DeviceErasureStep(
                store: id,
                erase: { try DeviceKeychainEraser.erase(.keychainPersonalKeys, scope: scope) },
                verifyEmpty: { try DeviceKeychainEraser.isEmpty(.keychainPersonalKeys, scope: scope) })

        case .keychainServerHandles:
            return DeviceErasureStep(
                store: id,
                erase: { try DeviceKeychainEraser.erase(.keychainServerHandles, scope: scope) },
                verifyEmpty: { try DeviceKeychainEraser.isEmpty(.keychainServerHandles, scope: scope) })

        // MARK: What iOS keeps for Doddy
        case .notifications:
            return DeviceErasureStep(
                store: id,
                erase: {
                    let center = UNUserNotificationCenter.current()
                    center.removeAllPendingNotificationRequests()
                    center.removeAllDeliveredNotifications()
                },
                verifyEmpty: {
                    let center = UNUserNotificationCenter.current()
                    let pending = await center.pendingNotificationRequests()
                    let delivered = await center.deliveredNotifications()
                    return pending.isEmpty && delivered.isEmpty
                })

        case .alarmsAndTimers:
            // AlarmKit alarms, timers and reminder rings Doddy set. Each is read back by `AlarmScheduler.cancel`; the list not
            // being readable is never "nothing there".
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    guard let ids = AlarmScheduler.scheduledIDs() else { throw Failure.notDone("the alarm list can't be read") }
                    var left = 0
                    for alarmID in ids where !AlarmScheduler.cancel(alarmID) { left += 1 }
                    if left > 0 { throw Failure.notDone("\(left) alarms are still set") }
                },
                verifyEmpty: { @MainActor in
                    guard let ids = AlarmScheduler.scheduledIDs() else { throw Failure.notDone("the alarm list can't be read") }
                    return ids.isEmpty
                })

        case .liveActivities:
            return DeviceErasureStep(
                store: id,
                erase: {
                    await endAll(DoddyVoiceAttributes.self)
                    await endAll(DoddyCallAttributes.self)
                    await endAll(DoddyCaptureAttributes.self)
                    await endAll(DoddyToolAttributes.self)
                    await endAll(ShoppingActivityAttributes.self)
                },
                verifyEmpty: {
                    running(DoddyVoiceAttributes.self) + running(DoddyCallAttributes.self) + running(DoddyCaptureAttributes.self)
                        + running(DoddyToolAttributes.self) + running(ShoppingActivityAttributes.self) == 0
                })

        case .spotlight:
            // iOS offers no way to read the search index back; the delete finishing without an error is its confirmation.
            return DeviceErasureStep(
                store: id,
                erase: { @MainActor in
                    spotlightCleared = false
                    try await SpotlightSync.shared.removeEverything()
                    spotlightCleared = true
                },
                verifyEmpty: { @MainActor in spotlightCleared })
        }
    }

    // MARK: Live Activities

    private static func endAll<A: ActivityAttributes>(_ type: A.Type) async {
        for activity in Activity<A>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Activities of this kind still showing.
    private nonisolated static func running<A: ActivityAttributes>(_ type: A.Type) -> Int {
        Activity<A>.activities.filter { $0.activityState == .active || $0.activityState == .stale }.count
    }
}

/// Where Doddy keeps files, for the steps that sweep a folder.
private enum DeviceFolders {
    /// `Application Support/<name>`, or nil when iOS gives no Application Support folder.
    static func applicationSupport(_ name: String) -> URL? {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?
            .appendingPathComponent(name, isDirectory: true)
    }

    /// The temporary folder, Caches and Documents.
    static var working: [URL] {
        let manager = FileManager.default
        return [manager.temporaryDirectory,
                manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
                manager.urls(for: .documentDirectory, in: .userDomainMask).first].compactMap { $0 }
    }

    /// Entries iOS and its frameworks keep in those folders (`com.apple.…`): not Doddy's, left in place.
    static func systemNames(in folder: URL) -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("com.apple.") })
    }
}
