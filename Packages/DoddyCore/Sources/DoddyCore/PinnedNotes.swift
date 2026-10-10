import Foundation

/// Notes the user pinned to the top of the Memories list (ADR-187). Only ids are kept, on the
/// phone, as a display preference: the notes themselves, search, exports and what voice sees are
/// untouched, and a pin that points at a deleted note is simply ignored.
public struct PinnedNotes: Equatable, Sendable {
    /// Few enough that pinning stays a choice rather than a second list.
    public static let maxPins = 10

    /// Oldest pin first.
    public private(set) var ids: [UUID]

    public init(ids: [UUID] = []) {
        var seen = Set<UUID>()
        self.ids = ids.filter { seen.insert($0).inserted }.prefix(Self.maxPins).map { $0 }
    }

    /// Reads the stored value (a JSON array of id strings). Anything unreadable is "no pins",
    /// and individual bad entries are skipped, so a damaged value never hides notes.
    public init(stored: String?) {
        guard let data = stored?.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data)
        else { self.init(); return }
        self.init(ids: strings.compactMap(UUID.init(uuidString:)))
    }

    public var stored: String {
        let strings = ids.map(\.uuidString)
        guard let data = try? JSONEncoder().encode(strings), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    public func isPinned(_ id: UUID) -> Bool { ids.contains(id) }

    public var isFull: Bool { ids.count >= Self.maxPins }

    public enum Change: Equatable, Sendable {
        case pinned, unpinned
        /// Already `maxPins` pinned: nothing changed.
        case full
    }

    /// Pins or unpins `id`. Pins for notes no longer in `existing` are dropped first, so deleted
    /// notes never use up the limit.
    @discardableResult
    public mutating func toggle(_ id: UUID, existing: [MemoryRecord]) -> Change {
        let live = Set(existing.map(\.id))
        ids = ids.filter { live.contains($0) || $0 == id }
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            return .unpinned
        }
        guard !isFull else { return .full }
        ids.append(id)
        return .pinned
    }

    /// Pinned notes first, most recently pinned on top, then the rest in the order given.
    public func apply(to records: [MemoryRecord]) -> [MemoryRecord] {
        guard !ids.isEmpty else { return records }
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = ids.reversed().compactMap { byID[$0] }
        let pinnedIDs = Set(pinned.map(\.id))
        return pinned + records.filter { !pinnedIDs.contains($0.id) }
    }
}
