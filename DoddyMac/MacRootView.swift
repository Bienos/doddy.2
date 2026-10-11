import DoddyCore
import SwiftUI

/// The Mac app's window (ADR-351): a sidebar, a list and a detail pane. Notes and lists are the
/// same ones the iPhone app has, but kept on this Mac only.
struct MacRootView: View {
    @Environment(MacStore.self) private var store
    @State private var selectedNoteID: UUID?
    @State private var selectedListID: UUID?
    @State private var selectedClipID: UUID?
    @State private var search = ""

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            sidebar(store: store)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detail
        }
        .navigationTitle("Doddy")
        .toolbar {
            ToolbarItem {
                Button { store.newNote = NewNoteRequest() } label: { Label("New note", systemImage: "square.and.pencil") }
                    .help("New note (⌘N)")
                    .disabled(!store.isStorageAvailable)
                    .accessibilityIdentifier("mac.newNote")
            }
        }
        .sheet(item: $store.newNote) { request in
            NewNoteSheet(request: request)
        }
        .overlay(alignment: .top) {
            if let problem = store.loadError ?? store.clipProblem {
                Text(problem)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .accessibilityIdentifier("mac.problem")
            }
        }
        .task {
            await store.reload()
            while !Task.isCancelled {
                store.refreshClips()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshClips()
        }
    }

    // MARK: Sidebar

    private func sidebar(store: Bindable<MacStore>) -> some View {
        List(selection: store.section) {
            Section {
                Label("Notes", systemImage: "note.text").tag(MacSection.notes)
                Label("Lists", systemImage: "checklist").tag(MacSection.lists)
                Label("Clips", systemImage: "tray")
                    .badge(self.store.clips.count)
                    .tag(MacSection.clips)
                Label("Talk to Doddy", systemImage: "waveform").tag(MacSection.voice)
            }
            let tags = NoteTags.counts(self.store.notes)
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags.prefix(12), id: \.tag) { item in
                        Button { show(search: "#\(item.tag)") } label: {
                            Label("#\(item.tag)", systemImage: "number").badge(item.count)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: NSLocalizedString("Tag %@, %lld notes", comment: ""), item.tag, item.count))
                    }
                }
            }
            let people = NotePeople.people(self.store.notes)
            if !people.isEmpty {
                Section("People") {
                    ForEach(people.prefix(12)) { person in
                        Button { show(search: "@\(person.name)") } label: {
                            Label("@\(person.name)", systemImage: "person").badge(person.count)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: NSLocalizedString("%@, %lld notes", comment: ""), person.name, person.count))
                    }
                }
            }
        }
        .accessibilityIdentifier("mac.sidebar")
    }

    private func show(search text: String) {
        search = text
        store.section = .notes
    }

    // MARK: Columns

    @ViewBuilder private var content: some View {
        switch store.section ?? .notes {
        case .notes: MacNotesColumn(selection: $selectedNoteID, search: $search)
        case .lists: MacListsColumn(selection: $selectedListID)
        case .clips: MacClipsColumn(selection: $selectedClipID)
        case .voice: Color.clear
        }
    }

    @ViewBuilder private var detail: some View {
        switch store.section ?? .notes {
        case .notes:
            if let id = selectedNoteID, store.notes.contains(where: { $0.id == id }) {
                MacNoteDetail(noteID: id).id(id)
            } else {
                ContentUnavailableView("Pick a note", systemImage: "note.text",
                                       description: Text("Or press ⌘N to write one. Your notes stay on this Mac."))
            }
        case .lists:
            if let id = selectedListID, store.lists.contains(where: { $0.id == id }) {
                MacListDetail(listID: id).id(id)
            } else {
                ContentUnavailableView("Pick a list", systemImage: "checklist")
            }
        case .clips:
            if let id = selectedClipID, let clip = store.clips.first(where: { $0.id == id }) {
                MacClipDetail(clip: clip).id(id)
            } else {
                ContentUnavailableView("No clip picked", systemImage: "tray",
                                       description: Text("Pages from Safari and things from the Share menu wait here until you save them."))
            }
        case .voice:
            MacVoicePlaceholder()
        }
    }
}

/// Talking to Doddy is the iPhone's voice; it isn't built for the Mac yet (ADR-351).
struct MacVoicePlaceholder: View {
    var body: some View {
        ContentUnavailableView("Talking to Doddy isn't on the Mac yet", systemImage: "waveform",
                               description: Text("For now, talk to Doddy on your iPhone. On this Mac you can write notes and lists, and send pages from Safari or the Share menu."))
            .accessibilityIdentifier("mac.voice")
    }
}
