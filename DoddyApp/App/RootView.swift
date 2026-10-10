import DoddyCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "appearance"
    static let hideCharacterArt = "hideCharacterArt"
    static let hasSeenFirstHello = "hasSeenFirstHello"
    static let voiceAgentID = "voiceAgentID"
    static let serverURL = "serverURL"
    static let pushUpdatesOn = "pushUpdatesOn"
    static let memoryCopyOn = "memoryCopyOn"
}

enum AppTab: Hashable {
    case home, memories, settings
}

struct RootView: View {
    @Environment(MemoryStore.self) private var store
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
            // Finish or check any reminder write a crash or force-quit interrupted (A-22).
            _ = try? await store.environment.reminderExecutor?.recoverInterrupted()
        }
        // Keeps the opt-in server copy (memory on calls) equal to what is on this iPhone.
        .onChange(of: store.revision) { MemoryCopySync.shared.schedule(store.memories) }
        .fullScreenCover(isPresented: .constant(!hasSeenFirstHello)) {
            FirstHelloView { hasSeenFirstHello = true }
                .preferredColorScheme(colorScheme)
        }
    }
}
