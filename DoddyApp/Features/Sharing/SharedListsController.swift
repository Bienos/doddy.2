import CloudKit
import DoddyCore
import Foundation
import Observation

/// Shared lists (ADR-263) on the main actor. Shares a list, syncs shared lists, joins one from a
/// link, and stops sharing or leaves. Every sync is: read iCloud, merge with this iPhone and the
/// last sync (`SharedListMerge`), write what changed on each side, read both back, and only then
/// remember the result as the new "last sync". If anything fails, nothing is remembered and the
/// next sync starts again from the same place, so nothing is lost or counted twice.
@MainActor
@Observable
final class SharedListsController {
    static let shared = SharedListsController()

    var store: MemoryStore?
    /// Shared lists on this iPhone, by list id.
    private(set) var links: [UUID: ListShare] = [:]
    private(set) var isSyncing = false
    /// The last sync problem, in words, or nil.
    private(set) var problem: String?
    /// A list someone shared, waiting for the user's Join or Not now.
    private(set) var invite: Invite?

    struct Invite: Identifiable {
        let id = UUID()
        let metadata: CKShare.Metadata
        var title: String { metadata.share[CKShare.SystemFieldKey.title] as? String ?? NSLocalizedString("A shared list", comment: "") }
        var owner: String? {
            metadata.ownerIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
        }
    }

    /// iCloud wakes Doddy when a shared list changes (ADR-284). False: changes arrive when
    /// Doddy comes to the front (the build has no push entitlement, or registering failed).
    private(set) var liveUpdates = false

    /// Who added or ticked items on shared lists, and the people's names (ADR-285). Memory only,
    /// refreshed at each sync; never sent to Doddy's voice.
    private var people: [UUID: SharedItemPeople] = [:]
    private var names: [String: String] = [:]
    private var me: String?

    /// What a list row says under an item of a shared list: other people's names only.
    func label(for item: ListItem) -> SharedItemLabel {
        guard links[item.listID] != nil else { return SharedItemLabel(addedBy: nil, doneBy: nil) }
        return SharedItemLabel.make(people[item.id], isDone: item.isDone, me: me, names: names)
    }

    private var syncAgain = false
    /// After a failed sync, a local change doesn't start another one until then (review I2).
    private var retryAfter: Date?
    private var retryTask: Task<Void, Never>?
    static let retryPause: TimeInterval = 60
    private let cloud = ListCloud.make()

    private init() {}

    /// The build is set up for iCloud (`DoddyCloudContainer`). Otherwise sharing isn't offered.
    var isAvailable: Bool { cloud != nil }

    func isShared(_ listID: UUID) -> ListShare? { links[listID] }

    private var repository: (any ListShareRepository)? { store?.environment.listShareRepository }

    func load() async {
        guard let repository, let all = try? await repository.shares() else { return }
        links = Dictionary(all.map { ($0.listID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Sharing a list

    /// After the user confirmed: the list goes to a new zone in their iCloud and is shared with
    /// nobody yet. Returns the share for Apple's sharing screen, where they invite people.
    func share(_ list: DoddyList) async throws -> CloudShareSheet {
        guard let cloud, let repository else { throw SharingError.notSetUp }
        guard await cloud.isSignedIn() else { throw SharingError.notSignedIn }
        let state = SharedListState(list)
        let share = try await cloud.share(state, listID: list.id)
        // Read back before remembering the link.
        let zoneID = share.recordID.zoneID
        guard try await cloud.fetch(zoneID, in: cloud.container.privateCloudDatabase)?.state == state else { throw SharingError.unconfirmed }
        let link = ListShare(listID: list.id, zoneName: zoneID.zoneName, zoneOwner: zoneID.ownerName, role: .owner, base: state, syncedAt: .now)
        try await repository.save(link)
        links[list.id] = link
        await startLiveUpdates()
        return CloudShareSheet(share: share, container: cloud.container)
    }

    /// The share of a list that is already shared, for adding or removing people.
    func existingShare(_ listID: UUID) async throws -> CloudShareSheet? {
        guard let cloud, let link = links[listID], let share = try await cloud.existingShare(link) else { return nil }
        return CloudShareSheet(share: share, container: cloud.container)
    }

    /// Stop sharing (owner: the copy in iCloud is deleted and everyone loses it) or leave (the
    /// list comes off this user's iCloud). The list stays on this iPhone as an ordinary list.
    func stop(_ listID: UUID) async throws {
        guard let cloud, let repository, let link = links[listID] else { return }
        guard try await cloud.stop(link) else { throw SharingError.unconfirmed }
        try await repository.remove(listID: listID)
        links[listID] = nil
        if !links.values.contains(where: { $0.role == link.role }) { await cloud.unsubscribe(link.role) }
    }

    /// Every delete of one list calls this first (review F2/I3). A shared list stops being shared
    /// (owner: the copy in iCloud is deleted and the people invited lose it; joined: this user
    /// leaves), so deleting it here leaves nothing in iCloud. Throws when that isn't confirmed;
    /// then the list must not be deleted. A list that isn't shared has nothing to stop; a build
    /// without iCloud can't reach it (`stop` does nothing there).
    func stopSharingBeforeDeleting(_ listID: UUID) async throws {
        guard links[listID] != nil else { return }
        try await stop(listID)
    }

    /// Delete all (Settings): stops sharing every list this user shares, so no copy and no
    /// invitees are left in iCloud (review G3/I3). Returns the lists whose stop wasn't confirmed
    /// (all of them in a build without iCloud). While Doddy stays open, the next sync tries those
    /// again once their lists are gone (see `sync`).
    func stopAllOwnedShares() async -> [UUID] {
        let owned = links.values.filter { $0.role == .owner }.map(\.listID).sorted { $0.uuidString < $1.uuidString }
        guard cloud != nil else { return owned }
        var failed: [UUID] = []
        for listID in owned {
            do {
                try await stop(listID)
            } catch {
                failed.append(listID)
            }
        }
        return failed
    }

    // MARK: Updates straight away (ADR-284)

    /// While any list is shared: register for silent notifications (no permission prompt; the
    /// device token is not sent anywhere, iCloud uses it directly) and subscribe each database
    /// that has a shared list. Needs the push entitlement; without it, nothing changes and
    /// updates keep arriving when Doddy is opened.
    func startLiveUpdates() async {
        guard let cloud, !links.isEmpty else { liveUpdates = false; return }
        guard (try? await PushRegistrar.shared.currentDeviceToken()) != nil else { liveUpdates = false; return }
        var subscribed = true
        for role in Set(links.values.map(\.role)) {
            subscribed = ((try? await cloud.subscribe(role)) ?? false) && subscribed
        }
        liveUpdates = subscribed
    }

    /// A silent notification arrived. True when it was iCloud about the lists (then they sync).
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard isAvailable, ListCloud.isListNotification(userInfo) else { return false }
        await load()
        await syncAll()
        return true
    }

    // MARK: Joining

    /// From the scene delegate when the user opened a share link. Nothing happens until Join.
    func received(_ metadata: CKShare.Metadata) {
        guard isAvailable else { return }
        invite = Invite(metadata: metadata)
    }

    func declineInvite() { invite = nil }

    /// Join: accept the share, read the list, make it a list on this iPhone with the same items.
    /// A name already used here gets " (shared)" on this iPhone only. Returns the new list.
    func join(_ invite: Invite) async throws -> DoddyList {
        self.invite = nil
        guard let cloud, let store, let repository else { throw SharingError.notSetUp }
        guard let joined = try await cloud.accept(invite.metadata) else { throw SharingError.gone }
        let name = store.lists.contains { ListMatch.key($0.name) == ListMatch.key(joined.state.name) }
            ? String((joined.state.name + NSLocalizedString(" (shared)", comment: "")).prefix(ListLimits.nameLength))
            : joined.state.name
        let created = try await store.createList(name: name, items: [], source: .typed)
        let local = SharedListState(name: name, items: joined.state.items)
        let list = try await store.replaceShared(created.id, with: local)
        let link = ListShare(
            listID: list.id, zoneName: joined.zoneID.zoneName, zoneOwner: joined.zoneID.ownerName,
            role: .participant, base: joined.state, syncedAt: .now)
        try await repository.save(link)
        links[list.id] = link
        await startLiveUpdates()
        return list
    }

    // MARK: Syncing

    /// After a local change: syncs only the shared lists that differ from their last sync.
    func listsChanged() {
        guard isAvailable, !links.isEmpty, let store else { return }
        if let retryAfter, retryAfter > Date() { return }
        let changed = links.values.contains { link in store.list(id: link.listID).map(SharedListState.init) != link.base }
        if changed { Task { await syncAll() } }
    }

    /// Every shared list, one at a time. Called when Doddy comes to the front, when a list opens,
    /// after a local change, and from "Sync now".
    func syncAll() async {
        guard let cloud, let store, !links.isEmpty else { return }
        if isSyncing { syncAgain = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            guard await cloud.isSignedIn() else {
                problem = NSLocalizedString("Sign in to iCloud in iOS Settings to keep shared lists up to date.", comment: "")
                return
            }
            if me == nil { me = await cloud.myRecordName() }
            var failed = false
            for link in links.values.sorted(by: { $0.listID.uuidString < $1.listID.uuidString }) {
                do {
                    try await sync(link, cloud: cloud, store: store)
                } catch {
                    failed = true
                }
            }
            problem = failed ? NSLocalizedString("A shared list couldn't be updated. Doddy will try again.", comment: "") : nil
            if failed {
                // A failing sync must not start itself again straight away (review I2): its own
                // writes change the lists, which asked for another sync, and that looped without a
                // pause. Local changes wait `retryPause`, then one retry; opening Doddy, Update
                // now and iCloud's wake-ups still sync at once.
                syncAgain = false
                retryAfter = Date(timeIntervalSinceNow: Self.retryPause)
                retryTask?.cancel()
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.retryPause))
                    guard !Task.isCancelled else { return }
                    self?.listsChanged()
                }
            } else {
                retryAfter = nil
            }
        } while syncAgain
    }

    private func sync(_ link: ListShare, cloud: ListCloud, store: MemoryStore) async throws {
        guard let repository else { return }
        // The list is read, iCloud is read, and the merge is written over the list. A change made
        // on this iPhone while iCloud was being read would be overwritten and lost everywhere
        // (review F1), so the list is read again just before writing; if it changed, the merge
        // starts again from the new list. After three tries the next sync picks it up.
        for _ in 1...3 {
            await store.reload()
            guard let list = store.list(id: link.listID) else {
                // Deleted on this iPhone; the stored link went with it (cascade). If it was deleted
                // without stopping first, or the stop failed, stop now so no copy and no invitees
                // are left in iCloud (review I3). Only when the stored links agree the list is gone:
                // a failed read of the lists must never delete a shared list's zone.
                let stored = try await repository.shares()
                guard !stored.contains(where: { $0.listID == link.listID }) else { throw SharingError.unconfirmed }
                guard try await cloud.stop(link) else { throw SharingError.unconfirmed }
                links[link.listID] = nil
                if !links.values.contains(where: { $0.role == link.role }) { await cloud.unsubscribe(link.role) }
                return
            }
            let database = cloud.database(link.role)
            let zoneID = ListCloud.zoneID(link)
            guard let zone = try await cloud.fetch(zoneID, in: database), let remote = zone.state else {
                // Sharing stopped, or this user left or was removed: keep the list here, unshared.
                try await repository.remove(listID: link.listID)
                links[link.listID] = nil
                problem = String(format: NSLocalizedString("“%@” is no longer shared. It stays on this iPhone.", comment: ""), list.name)
                return
            }
            let local = SharedListState(list)
            // Read again after iCloud; nothing is written over a list that changed meanwhile.
            await store.reload()
            guard store.list(id: link.listID).map(SharedListState.init) == local else { continue }
            var result = SharedListMerge.merge(base: link.base, local: local, remote: remote)
            if result.localChanged {
                do {
                    _ = try await store.replaceShared(link.listID, with: result.merged)
                } catch ListError.nameTaken {
                    // Another list here has the new name: this iPhone keeps its name, and sends it.
                    guard store.list(id: link.listID).map(SharedListState.init) == local else { continue }
                    let keepName = SharedListState(name: local.name, items: result.merged.items)
                    result = SharedListMerge.Result(merged: keepName, localChanged: true, remoteChanged: true, conflicts: result.conflicts)
                    _ = try await store.replaceShared(link.listID, with: keepName)
                }
            }
            if result.merged != remote {
                try await cloud.push(result.merged, over: zone, zoneID: zoneID, in: database, me: me)
            }
            // Both sides read back before the merge is remembered as the last sync.
            await store.reload()
            let back = try await cloud.fetch(zoneID, in: database)
            guard store.list(id: link.listID).map(SharedListState.init) == result.merged, back?.state == result.merged
            else { throw SharingError.unconfirmed }
            if let back { people.merge(back.people) { _, new in new } }
            if let share = try? await cloud.existingShare(link) { names.merge(ListCloud.names(in: share)) { _, new in new } }
            let synced = ListShare(
                listID: link.listID, zoneName: link.zoneName, zoneOwner: link.zoneOwner, role: link.role,
                base: result.merged, syncedAt: .now)
            try await repository.save(synced)
            links[link.listID] = synced
            return
        }
        // Changed on this iPhone during every try: nothing was written, and the next sync merges it.
        throw SharingError.unconfirmed
    }
}

enum SharingError: Error, Equatable {
    case notSetUp
    case notSignedIn
    /// Written, but reading it back didn't show it. Treated as not done.
    case unconfirmed
    /// The list was no longer shared by the time the user joined.
    case gone

    var message: String {
        switch self {
        case .notSetUp: NSLocalizedString("Sharing lists isn't set up in this version of Doddy.", comment: "")
        case .notSignedIn: NSLocalizedString("Sign in to iCloud in iOS Settings to share lists.", comment: "")
        case .unconfirmed: NSLocalizedString("iCloud didn't confirm it. Nothing is counted as done; try again.", comment: "")
        case .gone: NSLocalizedString("That list is no longer shared.", comment: "")
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? SharingError { return error.message }
        if let error = error as? CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure: return NSLocalizedString("No internet connection. Try again.", comment: "")
            case .quotaExceeded: return NSLocalizedString("Your iCloud storage is full.", comment: "")
            case .notAuthenticated: return NSLocalizedString("Sign in to iCloud in iOS Settings to share lists.", comment: "")
            default: break
            }
        }
        return UserFacingError.listMessage(for: error)
    }
}
