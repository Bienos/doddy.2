import Foundation

/// What Doddy does differently while one of the user's iOS Focus modes is on (ADR-312). The user
/// picks these in Settings, Focus, on the Focus itself; iOS hands them to the app when that Focus
/// starts, and hands the defaults (nothing changed) when it ends. Separate from Doddy's own
/// focus timer (ADR-241).
public struct FocusFilterSettings: Codable, Equatable, Sendable {
    public static let storageKey = "focusFilter.settings"

    /// This list comes first in Memories, Lists while the Focus is on.
    public var listFirstID: UUID?

    public init(listFirstID: UUID? = nil) {
        self.listFirstID = listFirstID
    }

    /// Nothing changed: no Focus, or a Focus without Doddy's filter.
    public static let none = FocusFilterSettings()

    public var changesNothing: Bool { self == .none }

    /// Read from what was stored; anything unreadable counts as nothing changed.
    public init(stored: String?) {
        guard let data = stored?.data(using: .utf8),
              let settings = try? JSONDecoder().decode(FocusFilterSettings.self, from: data) else {
            self = .none
            return
        }
        self = settings
    }

    public var stored: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The lists in their usual order, with the Focus's list moved to the front. A list that was
    /// deleted since the Focus was set up changes nothing.
    public func ordered<Item: Identifiable>(_ lists: [Item]) -> [Item] where Item.ID == UUID {
        guard let listFirstID, let index = lists.firstIndex(where: { $0.id == listFirstID }) else { return lists }
        var result = lists
        result.insert(result.remove(at: index), at: 0)
        return result
    }
}
