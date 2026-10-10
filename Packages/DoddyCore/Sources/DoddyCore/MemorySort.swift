import Foundation

/// How the Memories list is ordered (ADR-186). Display only: the store, search and exports keep
/// their own orders.
public enum MemorySort: String, CaseIterable, Sendable {
    case newestFirst, oldestFirst, recentlyChanged

    /// Anything missing or unknown (an old or damaged stored value) is the default, newest first.
    public init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .newestFirst
    }

    /// `records` ordered by `self`. Ties and unknown dates fall back to the stored order, so the
    /// result is stable. Notes with no known date go last, whichever way the list runs.
    public func apply(to records: [MemoryRecord]) -> [MemoryRecord] {
        let indexed = Array(records.enumerated())
        let ordered: [(offset: Int, element: MemoryRecord)]
        switch self {
        case .newestFirst:
            ordered = indexed.sorted { Self.before($0, $1, by: \.capturedAt, newestFirst: true) }
        case .oldestFirst:
            ordered = indexed.sorted { Self.before($0, $1, by: \.capturedAt, newestFirst: false) }
        case .recentlyChanged:
            // Changed = corrected, else saved. Newest change first.
            ordered = indexed.sorted { Self.before($0, $1, by: { $0.updatedAt ?? $0.capturedAt }, newestFirst: true) }
        }
        return ordered.map(\.element)
    }

    private static func before(
        _ a: (offset: Int, element: MemoryRecord), _ b: (offset: Int, element: MemoryRecord),
        by date: (MemoryRecord) -> Date?, newestFirst: Bool
    ) -> Bool {
        switch (date(a.element), date(b.element)) {
        case let (x?, y?) where x != y: return newestFirst ? x > y : x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.offset < b.offset
        }
    }
}
