import Foundation

// Home and Lock Screen widgets (ADR-219). Widgets can't open the notes database, so the app
// writes this small snapshot to the App Group folder that only Doddy and its widget extension can
// read: pinned notes, the next time reminders and the lists, each shortened. The app writes it
// after every change and reads it back; the widget only reads it. "Show in widgets" off writes an
// empty snapshot, so nothing of the user's is left in the shared folder.

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maxPinned = 4
    public static let maxReminders = 3
    public static let maxLists = 8
    public static let maxItemsPerList = 12
    public static let maxTextLength = 120

    public struct Note: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let text: String

        public init(id: UUID, text: String) {
            self.id = id
            self.text = text
        }
    }

    public struct Reminder: Codable, Equatable, Sendable {
        public let memoryID: UUID
        public let fireAt: Date
        public let timeZoneID: String
        /// nil when the user keeps note text out of notifications; the widget then says
        /// "A note reminder", as the notification does.
        public let text: String?

        public init(memoryID: UUID, fireAt: Date, timeZoneID: String, text: String?) {
            self.memoryID = memoryID
            self.fireAt = fireAt
            self.timeZoneID = timeZoneID
            self.text = text
        }
    }

    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let text: String
        public let isDone: Bool

        public init(id: UUID, text: String, isDone: Bool) {
            self.id = id
            self.text = text
            self.isDone = isDone
        }
    }

    public struct List: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let openCount: Int
        public let doneCount: Int
        /// Open items in list order, then ticked ones, at most `maxItemsPerList`.
        public let items: [Item]

        public init(id: UUID, name: String, openCount: Int, doneCount: Int, items: [Item]) {
            self.id = id
            self.name = name
            self.openCount = openCount
            self.doneCount = doneCount
            self.items = items
        }
    }

    /// Where-did-I-park for the widget (ADR-315): when it was saved and the user's own words,
    /// never the position. A tap opens Doddy, which hands the spot to Maps.
    public struct Parked: Codable, Equatable, Sendable {
        public let savedAt: Date
        public let note: String?

        public init(savedAt: Date, note: String?) {
            self.savedAt = savedAt
            self.note = note
        }
    }

    public let version: Int
    public let writtenAt: Date
    /// False when the user turned "Show in widgets" off: the widgets say so and show nothing.
    public let isOn: Bool
    public let pinned: [Note]
    public let reminders: [Reminder]
    public let lists: [List]
    /// Absent in snapshots written before ADR-315; those still read, with no parking.
    public let parking: Parked?
    /// "Hide character artwork" is on in the app (ADR-331): widgets, Live Activities and the watch
    /// leave Doddy's pictures out too. Written only when true, so snapshots from before (and with
    /// it off) are unchanged and still read.
    public let hidesDoddy: Bool?

    public init(version: Int = currentVersion, writtenAt: Date, isOn: Bool, pinned: [Note], reminders: [Reminder], lists: [List],
                parking: Parked? = nil, hidesDoddy: Bool = false) {
        self.version = version
        self.writtenAt = writtenAt
        self.isOn = isOn
        self.pinned = pinned
        self.reminders = reminders
        self.lists = lists
        self.parking = parking
        self.hidesDoddy = hidesDoddy ? true : nil
    }

    /// Whether Doddy's pictures are to be left out (ADR-331).
    public var hidesPictures: Bool { hidesDoddy == true }

    public static func off(at date: Date, hidesDoddy: Bool = false) -> WidgetSnapshot {
        WidgetSnapshot(writtenAt: wholeMilliseconds(date), isOn: false, pinned: [], reminders: [], lists: [], hidesDoddy: hidesDoddy)
    }

    /// The date as the file keeps it (`millisecondsSince1970`). A `Date.now` with a finer fraction
    /// often reads back unequal, so a correct write looked failed and widgets weren't reloaded
    /// (review I1); whole milliseconds read back exactly.
    public static func wholeMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// Builds the snapshot from what the app has loaded. Pinned notes in pin order, skipping
    /// ones that no longer exist; the next time reminders after `now`; lists newest first.
    public static func make(
        memories: [MemoryRecord], lists: [DoddyList], pinned: PinnedNotes, reminders: [MemoryReminder],
        showReminderText: Bool, isOn: Bool, now: Date, parking: ParkingSpot? = nil, hidesDoddy: Bool = false
    ) -> WidgetSnapshot {
        guard isOn else { return .off(at: now, hidesDoddy: hidesDoddy) }
        let byID = Dictionary(memories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let notes = pinned.ids.compactMap { id in byID[id].map { Note(id: id, text: shortened($0.currentText)) } }
        let upcoming = reminders.compactMap { reminder -> Reminder? in
            guard case .time(_, let zone) = reminder.trigger, let fire = reminder.nextFire(after: now),
                  let note = byID[reminder.memoryID] else { return nil }
            return Reminder(memoryID: reminder.memoryID, fireAt: wholeMilliseconds(fire), timeZoneID: zone,
                            text: showReminderText ? shortened(note.currentText) : nil)
        }
        .sorted { $0.fireAt < $1.fireAt }
        let shownLists = lists.sorted { ($0.record.capturedAt ?? .distantPast) > ($1.record.capturedAt ?? .distantPast) }.prefix(maxLists).map { list in
            List(id: list.id, name: shortened(list.name), openCount: list.open.count, doneCount: list.done.count,
                 items: (list.open + list.done).prefix(maxItemsPerList).map {
                     Item(id: $0.id, text: shortened($0.text), isDone: $0.isDone)
                 })
        }
        return WidgetSnapshot(
            writtenAt: wholeMilliseconds(now), isOn: true, pinned: Array(notes.prefix(maxPinned)),
            reminders: Array(upcoming.prefix(maxReminders)), lists: Array(shownLists),
            parking: parking.map { Parked(savedAt: wholeMilliseconds($0.savedAt), note: $0.note.map(shortened)) }, hidesDoddy: hidesDoddy)
    }

    /// The first line, cut on a word boundary with "…" when longer than `maxTextLength`.
    public static func shortened(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let line = firstLine.trimmingCharacters(in: .whitespaces)
        guard line.count > maxTextLength else { return line }
        let cut = line.prefix(maxTextLength - 1)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Reminders still ahead of `date`, for a widget timeline entry at that moment.
    public func reminders(after date: Date) -> [Reminder] { reminders.filter { $0.fireAt > date } }

    public func list(id: UUID) -> List? { lists.first { $0.id == id } }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// nil for anything unreadable or from another version: the widget then asks to open Doddy,
    /// never shows half-read data.
    public static func decoded(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }
}

/// `doddy://open/<id>`: a widget's tap opens that note or list on Home. Navigation only.
public enum WidgetLink {
    public static func open(_ id: UUID) -> URL { URL(string: "\(DeepLink.scheme)://open/\(id.uuidString)")! }

    public static func memoryID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == DeepLink.scheme, url.host?.lowercased() == "open" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        return UUID(uuidString: parts[0])
    }
}

/// What a tick from a widget did, checked against the read-back list (ADR-219).
public enum WidgetTick: Equatable, Sendable {
    case ticked, unticked
    /// The item or list is gone, or changed in the app since the widget drew it; nothing changed.
    case notFound
    case failed

    /// The change a tap asks for: the opposite of what the widget showed. `shownDone` guards
    /// against a stale widget toggling an item the app already changed.
    public static func wanted(item: ListItem?, shownDone: Bool) -> Bool? {
        guard let item, item.isDone == shownDone else { return nil }
        return !shownDone
    }

    public static func outcome(after items: [ListItem], itemID: UUID, wantedDone: Bool) -> WidgetTick {
        guard let item = items.first(where: { $0.id == itemID }) else { return .failed }
        guard item.isDone == wantedDone else { return .failed }
        return wantedDone ? .ticked : .unticked
    }
}
