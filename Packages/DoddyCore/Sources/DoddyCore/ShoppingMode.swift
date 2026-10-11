import Foundation

// Shopping mode (ADR-257). One list on the Lock Screen and in the Dynamic Island while the user
// shops, as a Live Activity, so items can be ticked without opening Doddy. Ticks go through the
// same checked path as a widget tick (`ToggleListItemIntent`, ADR-219), and the activity is
// redrawn from the read-back list. The user starts it from the list, after a reminder that its
// items show on the Lock Screen; it ends from the list, when every item is ticked, or by itself.

public enum ShoppingMode {
    /// Items shown at once (Lock Screen space); the rest are counted.
    public static let maxItems = 6
    public static let maxTextLength = 60
    /// After this long without an update iOS marks it stale and it ends itself.
    public static let staleAfter: TimeInterval = 8 * 3600
    /// How long the "All ticked" card stays on the Lock Screen before it goes.
    public static let finishedCardFor: TimeInterval = 60
}

/// What the Live Activity shows. Open items first, in list order; then the most recently ticked
/// ones while there is room, so a mis-tap can be undone from the Lock Screen.
public struct ShoppingModeState: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public let id: UUID
        public let text: String
        public let isDone: Bool

        public init(id: UUID, text: String, isDone: Bool) {
            self.id = id
            self.text = text
            self.isDone = isDone
        }
    }

    public let listName: String
    public let openCount: Int
    public let doneCount: Int
    public let items: [Item]

    public init(listName: String, openCount: Int, doneCount: Int, items: [Item]) {
        self.listName = listName
        self.openCount = openCount
        self.doneCount = doneCount
        self.items = items
    }

    /// Every item is ticked (and there was at least one).
    public var isFinished: Bool { openCount == 0 && doneCount > 0 }
    /// Open items not shown for lack of room.
    public var moreOpen: Int { max(0, openCount - items.filter { !$0.isDone }.count) }

    public static func make(_ list: DoddyList) -> ShoppingModeState {
        let open = list.open.prefix(ShoppingMode.maxItems).map { Item(id: $0.id, text: shortened($0.text), isDone: false) }
        let room = ShoppingMode.maxItems - open.count
        let done = list.done.prefix(max(0, room)).map { Item(id: $0.id, text: shortened($0.text), isDone: true) }
        return ShoppingModeState(
            listName: shortened(list.name), openCount: list.open.count, doneCount: list.done.count,
            items: Array(open) + Array(done))
    }

    static func shortened(_ text: String) -> String {
        guard text.count > ShoppingMode.maxTextLength else { return text }
        return String(text.prefix(ShoppingMode.maxTextLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
