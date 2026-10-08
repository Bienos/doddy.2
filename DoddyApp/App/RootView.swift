import DoddyCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "appearance"
    static let hideCharacterArt = "hideCharacterArt"
    static let hasSeenFirstHello = "hasSeenFirstHello"
}

enum AppTab: Hashable {
    case home, memories, ask, settings
}

struct RootView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hasSeenFirstHello) private var hasSeenFirstHello = false
    @AppStorage(CloudAIConsent.storageKey) private var consentVersion = 0
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
            if CloudAIConsent.isGranted(consentVersion) {
                AskView(environment: store.environment)
                    .tabItem { Label("Ask", systemImage: "bubble.left") }
                    .tag(AppTab.ask)
            }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Theme.accentText)
        .preferredColorScheme(colorScheme)
        .task { await store.reload() }
        .fullScreenCover(isPresented: .constant(!hasSeenFirstHello)) {
            FirstHelloView { hasSeenFirstHello = true }
                .preferredColorScheme(colorScheme)
        }
    }
}
