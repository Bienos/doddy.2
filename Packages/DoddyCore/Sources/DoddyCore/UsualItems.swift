import Foundation

// "The usual" (ADR-343). Doddy remembers, on this iPhone, which items the user ticked off on
// each list, counted by the list's name (so a new "Shopping" list learns from the old ones).
// When they open a list, the items ticked at least twice that aren't on it now are offered,
// unticked, to add in one go. Nothing is added by itself, nothing leaves the iPhone, and
// "Forget" clears it. Only ticks are counted: an item typed and removed again is not "usual".

public struct UsualItem: Codable, Equatable, Sendable {
    /// As the user last wrote it.
    public var text: String
    public var count: Int
    public var last: Date
}

public struct UsualItems: Codable, Equatable, Sendable {
    public static let storageKey = "lists.usual"
    public static let minCount = 2
    public static let suggestionLimit = 12
    static let maxSeen = 3000
    static let maxPerList = 200

    /// Folded list name → folded item text → stats.
    public private(set) var byList: [String: [String: UsualItem]] = [:]
    /// Ticked items already counted, so a tick is counted once however often the lists reload.
    private(set) var seen: [UUID] = []

    public init() {}

    public init(stored: Data?) {
        self = stored.flatMap { try? JSONDecoder().decode(UsualItems.self, from: $0) } ?? UsualItems()
    }

    public var stored: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// Counts every ticked item not counted before. Returns true when something changed.
    @discardableResult
    public mutating func record(_ lists: [DoddyList]) -> Bool {
        var known = Set(seen)
        var changed = false
        for list in lists {
            let listKey = Self.fold(list.name)
            guard !listKey.isEmpty else { continue }
            for item in list.items {
                guard let doneAt = item.doneAt, !known.contains(item.id) else { continue }
                known.insert(item.id)
                seen.append(item.id)
                let itemKey = Self.fold(item.text)
                guard !itemKey.isEmpty else { continue }
                var stats = byList[listKey, default: [:]]
                var entry = stats[itemKey] ?? UsualItem(text: item.text, count: 0, last: doneAt)
                entry.count += 1
                if doneAt >= entry.last {
                    entry.last = doneAt
                    entry.text = item.text
                }
                stats[itemKey] = entry
                if stats.count > Self.maxPerList {
                    // Drop the least used, oldest first.
                    if let weakest = stats.min(by: { ($0.value.count, $0.value.last) < ($1.value.count, $1.value.last) })?.key {
                        stats[weakest] = nil
                    }
                }
                byList[listKey] = stats
                changed = true
            }
        }
        if seen.count > Self.maxSeen { seen.removeFirst(seen.count - Self.maxSeen) }
        return changed
    }

    /// Items ticked at least `minCount` times on lists with this name and not open on it now,
    /// most often first, then most recent.
    public func suggestions(for list: DoddyList) -> [UsualItem] {
        let open = Set(list.open.map { Self.fold($0.text) })
        return (byList[Self.fold(list.name)] ?? [:])
            .filter { $0.value.count >= Self.minCount && !open.contains($0.key) }
            .map(\.value)
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
            .prefix(Self.suggestionLimit)
            .map { $0 }
    }

    /// "Forget" on one list's name.
    public mutating func forget(listNamed name: String) { byList[Self.fold(name)] = nil }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
