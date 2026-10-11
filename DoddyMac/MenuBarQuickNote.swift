import DoddyCore
import SwiftUI

/// The menu bar quick note (ADR-353). A box and a Save button: the note is saved only when the
/// person presses Save, and the box clears only after the store read the note back. A failure
/// keeps the text and says what went wrong.
struct MenuBarQuickNote: View {
    @Environment(MacStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var text = ""
    @State private var message: String?
    @State private var failed = false
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick note").font(.headline)
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 300, height: 110)
                .accessibilityLabel("Note text")
                .accessibilityIdentifier("mac.quickNoteText")
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mac.quickNoteMessage")
            }
            HStack {
                Button("Open Doddy") {
                    openWindow(id: MacWindow.main)
                    NSApp.activate(ignoringOtherApps: true)
                }
                if !store.clips.isEmpty {
                    Text(clipsText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !store.isStorageAvailable
                              || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mac.quickNoteSave")
            }
            if let problem = store.loadError, !store.isStorageAvailable {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .onAppear {
            focused = true
            store.refreshClips()
        }
    }

    private var clipsText: String {
        String(format: NSLocalizedString("%lld clips waiting", comment: ""), store.clips.count)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.save(text: text, category: .other)
            text = ""
            failed = false
            message = NSLocalizedString("Saved.", comment: "")
        } catch {
            failed = true
            message = MacError.message(for: error)
        }
    }
}

enum MacWindow {
    static let main = "main"
}
