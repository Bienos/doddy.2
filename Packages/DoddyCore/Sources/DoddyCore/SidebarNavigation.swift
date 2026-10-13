import Foundation

// The iPad sidebar (ADR-430). On a wide iPad screen the tab bar becomes a sidebar: Home, Memories
// and Settings, then the user's lists. A list row is a shortcut to that list on Home, the same
// route a widget or Spotlight result takes (Home's path starting with the list's id), so the
// sidebar adds no second way of showing a list. Phone and narrow iPad windows keep the tab bar.

public enum SidebarSection: Hashable, Sendable, CaseIterable {
    case home, memories, settings
}

public enum SidebarItem: Hashable, Sendable {
    case section(SidebarSection)
    case list(UUID)
}

public struct SidebarNavigation: Equatable, Sendable {
    public var section: SidebarSection
    /// Home's navigation path: note and list ids, as on the iPhone.
    public var homePath: [UUID]

    public init(section: SidebarSection, homePath: [UUID]) {
        self.section = section
        self.homePath = homePath
    }

    /// The highlighted row. A list's row while Home shows that list (or something opened from
    /// it); otherwise the section's row. A list that no longer exists highlights Home.
    public func selection(listIDs: Set<UUID>) -> SidebarItem {
        if section == .home, let first = homePath.first, listIDs.contains(first) {
            return .list(first)
        }
        return .section(section)
    }

    /// Choosing a row. A list opens on Home in place of whatever Home showed. Choosing Home while
    /// a list's row was highlighted goes back to Home itself; otherwise Home keeps its place, as
    /// switching tabs does on the iPhone.
    public mutating func choose(_ item: SidebarItem, listIDs: Set<UUID>) {
        switch item {
        case .list(let id):
            section = .home
            homePath = [id]
        case .section(let chosen):
            if chosen == .home, case .list = selection(listIDs: listIDs) {
                homePath = []
            }
            section = chosen
        }
    }
}
