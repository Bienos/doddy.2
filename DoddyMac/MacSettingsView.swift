import AppKit
import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

/// A plain-text copy of every note and list, for the export button (ADR-351). Built from what the
/// store holds now; nothing is added or reworded.
struct NotesTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    @MainActor
    static func from(_ store: MacStore) -> NotesTextDocument {
        var parts: [String] = []
        for note in store.notes {
            var header = note.category.macName
            if let date = note.capturedAt { header += " · " + date.formatted(date: .abbreviated, time: .shortened) }
            parts.append("\(header)\n\(note.currentText)")
        }
        for list in store.lists {
            let lines = list.items.map { ($0.isDone ? "[x] " : "[ ] ") + $0.text }
            parts.append("\(list.name)\n" + lines.joined(separator: "\n"))
        }
        return NotesTextDocument(text: parts.joined(separator: "\n\n---\n\n") + "\n")
    }
}

/// Doddy › Settings (⌘,). It says plainly what this Mac app does and doesn't do.
struct MacSettingsView: View {
    @Environment(MacStore.self) private var store
    @State private var exporting = false

    var body: some View {
        TabView {
            notesTab.tabItem { Label("Notes", systemImage: "note.text") }
            extensionsTab.tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
            privacyTab.tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 480, height: 340)
    }

    private var notesTab: some View {
        Form {
            Section {
                if let folder = store.environment.folder {
                    LabeledContent("Notes file", value: folder.path)
                        .textSelection(.enabled)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                } else {
                    Text("The notes file isn't available right now.")
                }
                Text("These notes are kept on this Mac only. They don't sync with Doddy on your iPhone, and they are not backed up by Doddy.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button("Export as a text file…") { exporting = true }
                    .disabled(!store.hasLoaded || (store.notes.isEmpty && store.lists.isEmpty))
                Text("Saves every note and list as one plain text file, where you choose.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileExporter(isPresented: $exporting, document: NotesTextDocument.from(store),
                      contentType: .plainText, defaultFilename: "Doddy notes") { _ in }
    }

    private var extensionsTab: some View {
        Form {
            Section("Safari") {
                Text("Turn on “Doddy” in Safari › Settings › Extensions. Then use its button in the toolbar to send the page you are on, or the text you selected.")
            }
            Section("Share menu") {
                Text("In any app, choose Share › Doddy. If it isn't listed, turn it on in System Settings › Privacy & Security › Extensions › Sharing.")
            }
            Section("Where clips wait") {
                if ClipInboxLocation.isAvailable {
                    Label("Ready. Clips wait in a folder only Doddy and its extensions can open.", systemImage: "checkmark.circle")
                } else {
                    Label("Not set up in this build: the shared folder (App Group) is missing, so the extensions can't hand clips to Doddy.", systemImage: "exclamationmark.triangle")
                }
                Text("A clip is not a note. It becomes one only when you press Save in the Clips list.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        Form {
            Section {
                Text("Everything you write here stays on this Mac. Doddy for Mac doesn't use the internet, has no account, and sends nothing anywhere.")
                Text("The Safari extension sends Doddy only the page title, the address and the text you selected, and only when you press its button. It doesn't read other pages, and it has no network access.")
                Text("Doddy for Mac doesn't talk or listen yet. Talking to Doddy is on your iPhone.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
