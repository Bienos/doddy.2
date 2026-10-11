import SwiftUI

/// Doddy for Mac (ADR-351): notes, lists and clips on this Mac, a menu bar quick note, and a
/// Safari / Share-menu way to send pages in. No voice yet, no sync, no network.
@main
struct DoddyMacApp: App {
    @State private var store = MacStore(environment: .live())

    var body: some Scene {
        Window("Doddy", id: MacWindow.main) {
            MacRootView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 480)
        }
        .commands { MacCommands(store: store) }

        MenuBarExtra("Doddy quick note", systemImage: "note.text") {
            MenuBarQuickNote()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environment(store)
        }
    }
}

/// ⌘N for a new note, ⌘1–⌘3 for the sidebar.
struct MacCommands: Commands {
    let store: MacStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New note") {
                // The window may have been closed; the sheet shows once it is back.
                openWindow(id: MacWindow.main)
                store.newNote = NewNoteRequest()
            }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!store.isStorageAvailable)
        }
        CommandMenu("Go") {
            Button("Notes") { store.section = .notes }.keyboardShortcut("1", modifiers: .command)
            Button("Lists") { store.section = .lists }.keyboardShortcut("2", modifiers: .command)
            Button("Clips") { store.section = .clips }.keyboardShortcut("3", modifiers: .command)
        }
    }
}
