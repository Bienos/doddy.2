import DoddyCore
import SwiftUI

/// iPad on a wide screen (ADR-430): Home, Memories, Settings and the user's lists in a sidebar,
/// the chosen screen beside it. Which row is highlighted and what a row opens are decided by
/// `SidebarNavigation` (DoddyCore). A list row opens the list on Home, the route a widget or a
/// Spotlight result takes. Phone and narrow iPad windows keep `DoddyTabBar` (RootView).
struct SidebarLayout<Detail: View>: View {
    @Environment(MemoryStore.self) private var store
    @Binding var selectedTab: AppTab
    @Binding var homePath: [UUID]
    @ViewBuilder var detail: Detail
    /// Both columns from the start, in portrait too. The system button can still hide the sidebar.
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: selection) {
                Section {
                    // The tab bar's identifiers, so the same UI tests find them on iPad.
                    row(.home, title: "Home", icon: "house", id: "tab.home")
                    row(.memories, title: "Memories", icon: "book.closed", id: "tab.memories")
                    row(.settings, title: "Settings", icon: "slider.horizontal.3", id: "tab.settings")
                }
                if !lists.isEmpty {
                    Section("Lists") {
                        ForEach(lists) { list in
                            // The user's own words: shown as written, never looked up for translation.
                            Label(list.name, systemImage: "checklist")
                                .lineLimit(2)
                                .tag(SidebarItem.list(list.id))
                                .accessibilityIdentifier("sidebar.list")
                        }
                    }
                }
            }
            .navigationTitle("Doddy")
            .accessibilityLabel("App navigation")
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Lists in the order Home's lists section shows them (`ListsOverview`).
    private var lists: [DoddyList] { FocusFilterState.shared.settings.ordered(store.lists) }
    private var listIDs: Set<UUID> { Set(store.lists.map(\.id)) }

    private var navigation: SidebarNavigation {
        SidebarNavigation(section: SidebarSection(selectedTab), homePath: homePath)
    }

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { navigation.selection(listIDs: listIDs) },
            set: { item in
                guard let item else { return }
                var next = navigation
                next.choose(item, listIDs: listIDs)
                selectedTab = AppTab(next.section)
                homePath = next.homePath
            })
    }

    private func row(_ section: SidebarSection, title: LocalizedStringKey, icon: String, id: String) -> some View {
        Label(title, systemImage: icon)
            .tag(SidebarItem.section(section))
            .accessibilityIdentifier(id)
    }
}

extension SidebarSection {
    init(_ tab: AppTab) {
        switch tab {
        case .home: self = .home
        case .memories: self = .memories
        case .settings: self = .settings
        }
    }
}

extension AppTab {
    init(_ section: SidebarSection) {
        switch section {
        case .home: self = .home
        case .memories: self = .memories
        case .settings: self = .settings
        }
    }
}
