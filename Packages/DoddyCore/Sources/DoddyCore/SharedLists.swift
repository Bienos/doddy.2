import Foundation

// Shared lists through iCloud (ADR-263). Off unless the build is set up for iCloud and the user
// shares a list. Sharing a list copies its name and items to a zone in the user's own iCloud
// (Apple's CloudKit) and invites people with Apple's share sheet; they join from the link, and
// everyone's changes meet in that zone. This file is the plain-Swift part: what is synced, the
// three-way merge of "this iPhone", "iCloud" and "what both had at the last sync", and the
// link between a local list and its zone. Only DoddyApp/Features/Sharing talks to CloudKit.
//
// Merge rules, per item and per field:
//  - a change on one side only wins;
//  - the same field changed on both sides: iCloud's version wins (it is what the others see);
//  - an item deleted on one side and changed on the other (its words or its tick) is kept: an
//    edit beats a delete;
//  - items added on either side are all kept;
//  - positions are renumbered 0, 1, 2… in the merged order, the same way on every device.

public enum ListShareRole: String, Codable, CaseIterable, Sendable {
    /// This iPhone shared the list; the zone is in the user's own iCloud.
    case owner
    /// The list was shared with this user; the zone is in someone else's iCloud.
    case participant
}

/// One item as it is synced. Who added it and how (typed or said) stay on each iPhone.
public struct SharedListItem: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let doneAt: Date?
    public let position: Int
    public let addedAt: Date

    public init(id: UUID, text: String, doneAt: Date?, position: Int, addedAt: Date) {
        self.id = id
        self.text = text
        self.doneAt = doneAt.map(Self.milliseconds)
        self.position = position
        self.addedAt = Self.milliseconds(addedAt)
    }

    public init(_ item: ListItem) {
        self.init(id: item.id, text: item.text, doneAt: item.doneAt, position: item.position, addedAt: item.addedAt)
    }

    /// Dates are kept to the millisecond, as the database stores them, so both sides compare equal.
    static func milliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }

    func hasNewContent(_ other: SharedListItem) -> Bool { text != other.text || doneAt != other.doneAt }

    func with(position: Int) -> SharedListItem {
        SharedListItem(id: id, text: text, doneAt: doneAt, position: position, addedAt: addedAt)
    }
}

/// A list as it is synced: its name and its items in list order.
public struct SharedListState: Codable, Equatable, Sendable {
    public let name: String
    public let items: [SharedListItem]

    public init(name: String, items: [SharedListItem]) {
        self.name = name
        self.items = items.sorted { ($0.position, $0.addedAt, $0.id.uuidString) < ($1.position, $1.addedAt, $1.id.uuidString) }
    }

    public init(_ list: DoddyList) {
        self.init(name: list.name, items: list.items.map(SharedListItem.init))
    }

    /// What came from iCloud is checked like anything typed: a name and item texts within the
    /// limits (cleaned the same way), at most `ListLimits.itemsPerList` items, no repeated ids.
    /// Nil when the name isn't usable.
    public static func validated(name: String, items: [SharedListItem]) -> SharedListState? {
        guard let name = try? ListText.checkedName(name) else { return nil }
        var seen: Set<UUID> = []
        let kept = items.compactMap { item -> SharedListItem? in
            guard seen.insert(item.id).inserted, let text = ListText.cleaned(item.text), text.count <= ListLimits.itemLength else { return nil }
            return SharedListItem(id: item.id, text: text, doneAt: item.doneAt, position: max(item.position, 0), addedAt: item.addedAt)
        }
        return SharedListState(name: name, items: Array(kept.prefix(ListLimits.itemsPerList)))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data) -> SharedListState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(SharedListState.self, from: data)
    }
}

/// The link between a local list and its iCloud zone, with what both sides had at the last sync.
public struct ListShare: Equatable, Sendable {
    public let listID: UUID
    public let zoneName: String
    /// The zone owner's CloudKit user record name ("__defaultOwner__" for this user's own zone).
    public let zoneOwner: String
    public let role: ListShareRole
    public let base: SharedListState
    public let syncedAt: Date

    public init(listID: UUID, zoneName: String, zoneOwner: String, role: ListShareRole, base: SharedListState, syncedAt: Date) {
        self.listID = listID
        self.zoneName = zoneName
        self.zoneOwner = zoneOwner
        self.role = role
        self.base = base
        self.syncedAt = SharedListItem.milliseconds(syncedAt)
    }

    /// The zone a newly shared list goes in: one zone per list.
    public static func zoneName(for listID: UUID) -> String { "doddy-list-\(listID.uuidString)" }
}

public protocol ListShareRepository: Sendable {
    func shares() async throws -> [ListShare]
    /// Adds or replaces the link, then reads it back.
    func save(_ share: ListShare) async throws
    func remove(listID: UUID) async throws
}

public struct UnavailableListShareRepository: ListShareRepository {
    public init() {}
    private var error: DoddyError { .capabilityUnavailable(.memoryStorage) }
    public func shares() async throws -> [ListShare] { throw error }
    public func save(_ share: ListShare) async throws { throw error }
    public func remove(listID: UUID) async throws { throw error }
}

public enum SharedListMerge {
    public struct Result: Equatable, Sendable {
        public let merged: SharedListState
        /// This iPhone's list must change to `merged`.
        public let localChanged: Bool
        /// iCloud must change to `merged`.
        public let remoteChanged: Bool
        /// Fields changed on both sides, where iCloud's version was kept.
        public let conflicts: Int
    }

    public static func merge(base: SharedListState?, local: SharedListState, remote: SharedListState) -> Result {
        var conflicts = 0
        func pick<T: Equatable>(_ base: T?, _ local: T, _ remote: T) -> T {
            if local == remote { return local }
            if let base {
                if local == base { return remote }
                if remote == base { return local }
            }
            conflicts += 1
            return remote
        }

        let baseItems = Dictionary((base?.items ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localItems = Dictionary(local.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteItems = Dictionary(remote.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(baseItems.keys).union(localItems.keys).union(remoteItems.keys)

        var kept: [SharedListItem] = []
        for id in ids {
            let old = baseItems[id]
            switch (localItems[id], remoteItems[id]) {
            case (let mine?, let theirs?):
                kept.append(SharedListItem(
                    id: id,
                    text: pick(old?.text, mine.text, theirs.text),
                    doneAt: pick(old.map { $0.doneAt }, mine.doneAt, theirs.doneAt),
                    position: pick(old?.position, mine.position, theirs.position),
                    addedAt: theirs.addedAt))
            case (let mine?, nil):
                // New here, or deleted in iCloud: kept if it's new or its words or tick changed
                // here since (a new position alone, from other items moving, doesn't count).
                if old.map({ $0.hasNewContent(mine) }) ?? true { kept.append(mine) }
            case (nil, let theirs?):
                if old.map({ $0.hasNewContent(theirs) }) ?? true { kept.append(theirs) }
            case (nil, nil):
                break
            }
        }
        let name = pick(base?.name, local.name, remote.name)
        let ordered = SharedListState(name: name, items: kept).items.enumerated().map { $1.with(position: $0) }
        let merged = SharedListState(name: name, items: ordered)
        return Result(merged: merged, localChanged: merged != local, remoteChanged: merged != remote, conflicts: conflicts)
    }
}

extension ListRepository {
    /// Default for repositories that can't hold shared lists.
    public func replaceShared(listID: UUID, with state: SharedListState) async throws -> DoddyList {
        throw DoddyError.capabilityUnavailable(.memoryStorage)
    }
}

// MARK: Who added or ticked an item (ADR-285)

/// For one item on a shared list: the iCloud user who added it and who ticked it, as user
/// record names. Kept in memory on this iPhone only; never sent to the voice agent.
public struct SharedItemPeople: Equatable, Sendable {
    public let addedBy: String?
    public let doneBy: String?

    public init(addedBy: String?, doneBy: String?) {
        self.addedBy = addedBy
        self.doneBy = doneBy
    }
}

/// What a list row says under an item: only other people's names; your own changes need no label.
public struct SharedItemLabel: Equatable, Sendable {
    public let addedBy: String?
    public let doneBy: String?

    public init(addedBy: String?, doneBy: String?) {
        self.addedBy = addedBy
        self.doneBy = doneBy
    }

    public var isEmpty: Bool { addedBy == nil && doneBy == nil }

    /// `me` is this user's record name; `names` maps record names to display names (from the
    /// share's participants). Someone with no known name is "someone else", never guessed.
    public static func make(_ people: SharedItemPeople?, isDone: Bool, me: String?, names: [String: String]) -> SharedItemLabel {
        func name(_ id: String?) -> String? {
            guard let id, !id.isEmpty, id != me, id != ListShare.currentUserPlaceholder else { return nil }
            return names[id] ?? "someone else"
        }
        return SharedItemLabel(addedBy: name(people?.addedBy), doneBy: isDone ? name(people?.doneBy) : nil)
    }
}

extension ListShare {
    /// CloudKit's stand-in for "the current user" in record ids.
    public static let currentUserPlaceholder = "__defaultOwner__"
}

// MARK: A shared list's place reminder for everyone (ADR-298)

/// A place one person on a shared list chose to share, so the others can be reminded there too.
/// Shared only when that person taps Share this place; each other person sets their own reminder
/// with Remind me too (iOS watches the place on their iPhone, as for any place reminder, ADR-196).
/// Nobody's whereabouts are shared: only the place that was picked, its name and radius.
public struct SharedListPlace: Equatable, Sendable {
    public let place: ReminderPlace
    /// The iCloud user record name of whoever shared it; names come from the share.
    public let sharedBy: String?

    public init(place: ReminderPlace, sharedBy: String?) {
        self.place = place
        self.sharedBy = sharedBy
    }

    /// From what iCloud holds; nil unless every field is there and makes sense.
    public static func validated(name: String?, latitude: Double?, longitude: Double?, radiusMeters: Int?, onArrival: Bool?, sharedBy: String?) -> SharedListPlace? {
        guard let name, let latitude, let longitude, let radiusMeters, let onArrival,
              let place = try? ReminderPlace(name: name, latitude: latitude, longitude: longitude, radiusMeters: radiusMeters, onArrival: onArrival)
        else { return nil }
        return SharedListPlace(place: place, sharedBy: sharedBy)
    }

    /// Two reminders count as the same place within this distance, arriving or leaving alike.
    public static let sameSpotMeters: Double = 50

    public static func isSame(_ a: ReminderPlace, _ b: ReminderPlace) -> Bool {
        a.onArrival == b.onArrival
            && Parking.distance(from: (a.latitude, a.longitude), to: (b.latitude, b.longitude)) <= sameSpotMeters
    }
}

/// What the list screen offers about a shared place.
public enum SharedPlaceOffer: Equatable, Sendable {
    /// Not shared, or nothing to offer.
    case nothing
    /// This iPhone has a place reminder for the list and nobody's place is shared: offer to share it.
    case canShare(ReminderPlace)
    /// Someone else shared a place this iPhone isn't reminded at: offer Remind me too.
    case remindMeToo(SharedListPlace, by: String?)
    /// The shared place is this iPhone's own reminder (shared from here, or already set the same).
    case shared(SharedListPlace, byMe: Bool)

    /// `mine`: this iPhone's place reminder for the list, if any. `names`: user record name → name.
    public static func make(isShared: Bool, shared: SharedListPlace?, mine: ReminderPlace?, me: String?, names: [String: String]) -> SharedPlaceOffer {
        guard isShared else { return .nothing }
        guard let shared else { return mine.map { .canShare($0) } ?? .nothing }
        let byMe = shared.sharedBy != nil && shared.sharedBy == me
        if byMe || mine.map({ SharedListPlace.isSame($0, shared.place) }) == true {
            return .shared(shared, byMe: byMe)
        }
        return .remindMeToo(shared, by: shared.sharedBy.flatMap { names[$0] })
    }
}
