import Foundation

/// The type filter on the Memories list (ADR-182). Only types the user has actually used are
/// offered, in the fixed `MemoryCategory` order, so the row never shows empty choices.
public enum MemoryFilter {
    /// Types present in `records`, each with its count. Empty when fewer than two types are
    /// used, because a filter with one choice only repeats the whole list.
    public static func choices(_ records: [MemoryRecord]) -> [(category: MemoryCategory, count: Int)] {
        let counts = Dictionary(grouping: records, by: \.category).mapValues(\.count)
        let present = MemoryCategory.allCases.compactMap { category in
            counts[category].map { (category: category, count: $0) }
        }
        return present.count >= 2 ? present : []
    }

    /// `records` in their existing order, keeping only `category`; all of them for nil.
    public static func apply(_ category: MemoryCategory?, to records: [MemoryRecord]) -> [MemoryRecord] {
        guard let category else { return records }
        return records.filter { $0.category == category }
    }
}
