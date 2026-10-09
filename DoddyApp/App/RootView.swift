import DoddyCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "appearance"
    static let hideCharacterArt = "hideCharacterArt"
    static let hasSeenFirstHello = "hasSeenFirstHello"
    static let voiceAgentID = "voiceAgentID"

    /// The user's in-app switch for a connection (not the iOS permission).
    static func connectionEnabled(_ kind: ConnectionKind) -> String { "connection.\(kind.rawValue).enabled" }
}

enum AppTab: Hashable {
    case home, memories, settings
}

struct RootView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ConnectionsStore.self) private var connections
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hasSeenFirstHello) private var hasSeenFirstHello = false
    @State private var selectedTab: AppTab = .home

    private var colorScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearanceRaw) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            MemoriesView()
                .tabItem { Label("Memories", systemImage: "note.text") }
                .tag(AppTab.memories)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Theme.accentText)
        .preferredColorScheme(colorScheme)
        .task {
            await store.reload()
            await connections.refresh()
        }
        // Permissions can change in iOS Settings while Doddy is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await connections.refresh() } }
        }
        .fullScreenCover(isPresented: .constant(!hasSeenFirstHello)) {
            FirstHelloView { hasSeenFirstHello = true }
                .preferredColorScheme(colorScheme)
        }
    }
}
