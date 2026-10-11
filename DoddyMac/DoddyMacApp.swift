import SwiftUI

/// The Doddy menu-bar app for the Mac (ADR-450): an icon in the menu bar with a small menu, and two
/// windows ("Open Doddy" and Settings). It has no Dock icon (LSUIElement). Voice, Translate and
/// sync with the iPhone are not part of it; the menu says so instead of pretending.
@main
struct DoddyMacApp: App {
    @State private var model = MacModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarIcon.image()
        }
        .menuBarExtraStyle(.window)

        Window("Doddy", id: WindowID.notes) {
            NotesWindow(model: model)
        }
        .defaultSize(width: 520, height: 560)

        Window("Doddy Settings", id: WindowID.settings) {
            MacSettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let notes = "doddy.notes"
    static let settings = "doddy.settings"
}
