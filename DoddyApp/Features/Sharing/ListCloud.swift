import CloudKit
import DoddyCore
import Foundation

// Shared lists (ADR-263): the only code that talks to CloudKit (scripts/check_forbidden_capabilities.sh).
// One zone per shared list. In it: one "DoddyList" record ("list": the name) and one
// "DoddyListItem" record per item (record name = the item's id). The zone is shared as a whole
// (`CKShare(recordZoneID:)`). The owner's zone is in their private database; people who joined
// see it in their shared database.

/// Main-actor, like the controller that uses it; CloudKit does the waiting on its own queues.
@MainActor
struct ListCloud {
    static let listType = "DoddyList"
    static let itemType = "DoddyListItem"
    static let listRecordName = "list"
    /// A place someone shared for the list's reminder (ADR-307): one record, apart from the list
    /// and items, so syncing items never touches it.
    static let placeType = "DoddyListPlace"
    static let placeRecordName = "place"

    let container: CKContainer

    /// The iCloud container from the app's Info.plist (`DoddyCloudContainer`), set only in builds
    /// signed with the iCloud entitlement (project.yml, `DODDY_CLOUD_CONTAINER`). Without it,
    /// sharing isn't offered and CloudKit is never touched.
    static var containerID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DoddyCloudContainer") as? String,
              id.hasPrefix("iCloud."), !id.contains("$(") else { return nil }
        return id
    }

    static func make() -> ListCloud? {
        containerID.map { ListCloud(container: CKContainer(identifier: $0)) }
    }

    func database(_ role: ListShareRole) -> CKDatabase {
        role == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    static func zoneID(_ share: ListShare) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: share.zoneName, ownerName: share.zoneOwner)
    }

    /// Signed in to iCloud and allowed to use it.
    func isSignedIn() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: Reading

    struct Zone {
        let list: CKRecord?
        let items: [CKRecord]
        var place: CKRecord? = nil

        /// The shared place, only when every field is there and makes sense (ADR-307).
        var sharedPlace: SharedListPlace? {
            guard let place else { return nil }
            return SharedListPlace.validated(
                name: place["name"] as? String, latitude: (place["latitude"] as? NSNumber)?.doubleValue,
                longitude: (place["longitude"] as? NSNumber)?.doubleValue, radiusMeters: (place["radius"] as? NSNumber)?.intValue,
                onArrival: (place["onArrival"] as? NSNumber)?.boolValue, sharedBy: place["sharedBy"] as? String)
        }

        var state: SharedListState? {
            guard let list, let name = list["name"] as? String else { return nil }
            let parsed = items.compactMap { record -> SharedListItem? in
                guard let id = UUID(uuidString: record.recordID.recordName), let text = record["text"] as? String,
                      let added = record["addedAt"] as? Date else { return nil }
                return SharedListItem(
                    id: id, text: text, doneAt: record["doneAt"] as? Date,
                    position: (record["position"] as? NSNumber)?.intValue ?? 0, addedAt: added)
            }
            return SharedListState.validated(name: name, items: parsed)
        }

        /// Who added and who ticked each item (ADR-285): the fields Doddy writes, else the
        /// record's creator. User record names only; names come from the share.
        var people: [UUID: SharedItemPeople] {
            var result: [UUID: SharedItemPeople] = [:]
            for record in items {
                guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
                result[id] = SharedItemPeople(
                    addedBy: record["addedBy"] as? String ?? record.creatorUserRecordID?.recordName,
                    doneBy: record["doneBy"] as? String)
            }
            return result
        }
    }

    /// This user's iCloud user record name, to write who added or ticked an item.
    func myRecordName() async -> String? {
        try? await container.userRecordID().recordName
    }

    /// Display names of the people on a share, by user record name (ADR-285). Shown on this
    /// iPhone only.
    static func names(in share: CKShare) -> [String: String] {
        var names: [String: String] = [:]
        for participant in share.participants {
            guard let id = participant.userIdentity.userRecordID?.recordName,
                  let components = participant.userIdentity.nameComponents else { continue }
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
            if !name.isEmpty { names[id] = name }
        }
        return names
    }

    /// Everything in the zone. Nil when the zone is gone: sharing was stopped, or this user left
    /// or was removed.
    func fetch(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> Zone? {
        var token: CKServerChangeToken?
        var records: [CKRecord] = []
        while true {
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool)
            do {
                changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            } catch let error as CKError where [.zoneNotFound, .userDeletedZone, .unknownItem].contains(error.code) {
                return nil
            }
            for result in changes.modificationResultsByID.values {
                if case .success(let modification) = result { records.append(modification.record) }
            }
            token = changes.changeToken
            if !changes.moreComing { break }
        }
        return Zone(
            list: records.first { $0.recordType == Self.listType && $0.recordID.recordName == Self.listRecordName },
            items: records.filter { $0.recordType == Self.itemType },
            place: records.first { $0.recordType == Self.placeType && $0.recordID.recordName == Self.placeRecordName })
    }

    // MARK: Writing

    /// Makes iCloud hold exactly `state`, changing only what differs from `zone`. Every record
    /// must still be as fetched (`.ifServerRecordUnchanged`), all or nothing (`atomically`).
    func push(_ state: SharedListState, over zone: Zone, zoneID: CKRecordZone.ID, in database: CKDatabase, me: String? = nil) async throws {
        var saving: [CKRecord] = []
        let list = zone.list ?? CKRecord(recordType: Self.listType, recordID: CKRecord.ID(recordName: Self.listRecordName, zoneID: zoneID))
        if list["name"] as? String != state.name {
            list["name"] = state.name
            saving.append(list)
        }
        let existing = Dictionary(zone.items.map { ($0.recordID.recordName, $0) }, uniquingKeysWith: { first, _ in first })
        for item in state.items {
            let isNew = existing[item.id.uuidString] == nil
            let record = existing[item.id.uuidString]
                ?? CKRecord(recordType: Self.itemType, recordID: CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID))
            let wasDone = record["doneAt"] as? Date != nil
            if Self.write(item, to: record) {
                // Who did it (ADR-285): the adder on a new item, the ticker when it gets ticked.
                if let me {
                    if isNew { record["addedBy"] = me }
                    if item.doneAt != nil, !wasDone { record["doneBy"] = me }
                }
                if item.doneAt == nil { record["doneBy"] = nil }
                saving.append(record)
            }
        }
        let kept = Set(state.items.map(\.id.uuidString))
        let deleting = zone.items.map(\.recordID).filter { !kept.contains($0.recordName) }
        guard !saving.isEmpty || !deleting.isEmpty else { return }
        let result = try await database.modifyRecords(
            saving: saving, deleting: deleting, savePolicy: .ifServerRecordUnchanged, atomically: true)
        for outcome in result.saveResults.values { _ = try outcome.get() }
        for outcome in result.deleteResults.values { try outcome.get() }
    }

    /// Shares `place` with everyone on the list, or stops sharing it (nil). The record must still
    /// be as fetched; then the zone is read again and must show exactly that (ADR-307).
    func setPlace(_ place: SharedListPlace?, over zone: Zone, zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> Bool {
        if let place {
            let record = zone.place ?? CKRecord(recordType: Self.placeType, recordID: CKRecord.ID(recordName: Self.placeRecordName, zoneID: zoneID))
            record["name"] = place.place.name
            record["latitude"] = place.place.latitude
            record["longitude"] = place.place.longitude
            record["radius"] = place.place.radiusMeters
            record["onArrival"] = place.place.onArrival
            record["sharedBy"] = place.sharedBy
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            for outcome in result.saveResults.values { _ = try outcome.get() }
        } else if let existing = zone.place {
            let result = try await database.modifyRecords(saving: [], deleting: [existing.recordID], savePolicy: .ifServerRecordUnchanged, atomically: true)
            for outcome in result.deleteResults.values { try outcome.get() }
        }
        let back = try await fetch(zoneID, in: database)
        return back?.sharedPlace == place
    }

    /// Sets the record's fields from `item`; true when anything changed.
    private static func write(_ item: SharedListItem, to record: CKRecord) -> Bool {
        var changed = false
        if record["text"] as? String != item.text { record["text"] = item.text; changed = true }
        if record["doneAt"] as? Date != item.doneAt {
            if let doneAt = item.doneAt { record["doneAt"] = doneAt } else { record["doneAt"] = nil }
            changed = true
        }
        if (record["position"] as? NSNumber)?.intValue != item.position { record["position"] = item.position; changed = true }
        if record["addedAt"] as? Date != item.addedAt { record["addedAt"] = item.addedAt; changed = true }
        return changed
    }

    // MARK: Updates straight away (ADR-284)

    static func subscriptionID(_ role: ListShareRole) -> String { "doddy-lists-\(role.rawValue)" }

    /// Asks iCloud to wake Doddy with a silent notification when anything in this database
    /// changes. The notification carries no list content; Doddy then syncs as usual. Read back.
    func subscribe(_ role: ListShareRole) async throws -> Bool {
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID(role))
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        let result = try await database(role).modifySubscriptions(saving: [subscription], deleting: [])
        for outcome in result.saveResults.values { _ = try outcome.get() }
        return (try? await database(role).subscription(for: Self.subscriptionID(role))) != nil
    }

    /// Stops the wake-ups once no list of that kind is shared any more.
    func unsubscribe(_ role: ListShareRole) async {
        _ = try? await database(role).modifySubscriptions(saving: [], deleting: [Self.subscriptionID(role)])
    }

    /// True for a silent notification from iCloud about Doddy's lists.
    static func isListNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKDatabaseNotification else { return false }
        return notification.subscriptionID?.hasPrefix("doddy-lists-") == true
    }

    // MARK: Sharing

    /// Puts the list in a new zone in the user's own iCloud and shares the zone. Nobody is
    /// invited yet; that happens in Apple's sharing screen. Returns the saved share.
    func share(_ state: SharedListState, listID: UUID) async throws -> CKShare {
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: ListShare.zoneName(for: listID))
        let zones = try await database.modifyRecordZones(saving: [zone], deleting: [])
        for outcome in zones.saveResults.values { _ = try outcome.get() }
        try await push(state, over: Zone(list: nil, items: []), zoneID: zone.zoneID, in: database)
        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = state.name
        share.publicPermission = .none
        let saved = try await database.modifyRecords(saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let stored = try saved.saveResults[share.recordID]?.get() as? CKShare else { throw CKError(.internalError) }
        return stored
    }

    /// The zone's share, for Apple's sharing screen (adding or removing people).
    func existingShare(_ link: ListShare) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: Self.zoneID(link))
        return try await database(link.role).record(for: id) as? CKShare
    }

    /// The owner deletes the zone (everyone loses it, and the copy in iCloud goes); someone who
    /// joined removes it from their shared database, which takes them off the share. The local
    /// list stays. True only when the zone can no longer be read.
    func stop(_ link: ListShare) async throws -> Bool {
        let zoneID = Self.zoneID(link)
        let database = database(link.role)
        let result = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
        for outcome in result.deleteResults.values { try outcome.get() }
        return try await fetch(zoneID, in: database) == nil
    }

    /// Joins a list someone shared, after the user tapped Join, and reads what's in it.
    func accept(_ metadata: CKShare.Metadata) async throws -> (zoneID: CKRecordZone.ID, state: SharedListState)? {
        _ = try await container.accept(metadata)
        let zoneID = metadata.share.recordID.zoneID
        guard let state = try await fetch(zoneID, in: container.sharedCloudDatabase)?.state else { return nil }
        return (zoneID, state)
    }
}
