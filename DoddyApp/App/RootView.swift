import SwiftUI
import DoddyCore

enum PreferenceKey {
    static let appearance = "appearance"
    static let hideCharacterArt = "hideCharacterArt"
    static let hasSeenFirstHello = "hasSeenFirstHello"
}

struct RootView: View {
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hasSeenFirstHello) private var hasSeenFirstHello = false

    private var colorScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearanceRaw) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            MemoriesView()
                .tabItem { Label("Memories", systemImage: "note.text") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accentText)
        .preferredColorScheme(colorScheme)
        .fullScreenCover(isPresented: .constant(!hasSeenFirstHello)) {
            FirstHelloView { hasSeenFirstHello = true }
                .preferredColorScheme(colorScheme)
        }
    }
}
