import DoddyCore
import SwiftUI

extension MemoryCategory {
    /// Same words the iPhone app uses, so the Polish strings are shared.
    var macName: String {
        switch self {
        case .fact: NSLocalizedString("Fact", comment: "")
        case .preference: NSLocalizedString("Preference", comment: "")
        case .commitment: NSLocalizedString("Commitment", comment: "")
        case .recommendation: NSLocalizedString("Recommendation", comment: "")
        case .decision: NSLocalizedString("Decision", comment: "")
        case .item: NSLocalizedString("Item", comment: "")
        case .place: NSLocalizedString("Place", comment: "")
        case .intention: NSLocalizedString("Intention", comment: "")
        case .other: NSLocalizedString("Other", comment: "")
        case .list: NSLocalizedString("List", comment: "")
        }
    }
}

/// The middle column: every note, or the ones a search finds.
struct MacNotesColumn: View {
    @Environment(MacStore.self) private var store
    @Binding var selection: UUID?
    @Binding var search: String
    @State private var shown: [MemoryRecord] = []

    var body: some View {
        List(selection: $selection) {
            ForEach(shown) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.currentText).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(note.category.macName)
                        if let date = note.capturedAt {
                            Text(date, format: .dateTime.day().month().year())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .tag(note.id)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay {
            if store.hasLoaded && shown.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "note.text",
                                           description: Text("Press ⌘N to write the first one."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: Text("Search notes"))
        .task(id: SearchKey(query: search, revision: store.revision)) {
            // A short pause, so typing doesn't search on every key.
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            shown = await store.notes(matching: search)
        }
        .accessibilityIdentifier("mac.notes")
    }

    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
    }
}

/// One note: read it, correct it, refile it, delete it. Nothing is changed until the user says so,
/// and the screen says "Saved" only after the store read the new text back.
struct MacNoteDetail: View {
    @Environment(MacStore.self) private var store
    let noteID: UUID
    @State private var draft = ""
    @State private var category: MemoryCategory = .other
    @State private var loaded = false
    @State private var message: String?
    @State private var confirmDelete = false

    private var note: MemoryRecord? { store.notes.first { $0.id == noteID } }

    var body: some View {
        if let note {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Note text")
                    .accessibilityIdentifier("mac.noteText")
                HStack {
                    Picker("Type", selection: $category) {
                        ForEach(MemoryCategory.noteCategories, id: \.self) { Text($0.macName).tag($0) }
                    }
                    .frame(maxWidth: 240)
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                    Button("Save changes") { Task { await saveChanges(note) } }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!hasChanges(note))
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("mac.noteMessage")
                }
                footer(for: note)
            }
            .padding()
            .onAppear {
                guard !loaded else { return }
                draft = note.currentText
                category = note.category
                loaded = true
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete) {
                Button("Delete note", role: .destructive) { Task { await delete() } }
            } message: {
                Text("It is removed from this Mac. This can't be undone.")
            }
        } else {
            ContentUnavailableView("This note is gone", systemImage: "note.text")
        }
    }

    private func footer(for note: MemoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let date = note.capturedAt {
                Text(String(format: NSLocalizedString("Written %@", comment: ""), date.formatted(date: .abbreviated, time: .shortened)))
            }
            if note.userEdited, let updated = note.updatedAt {
                Text(String(format: NSLocalizedString("Corrected %@", comment: ""), updated.formatted(date: .abbreviated, time: .shortened)))
            }
            if note.userEdited, note.rawText != note.currentText {
                Text(String(format: NSLocalizedString("First version: %@", comment: ""), note.rawText)).lineLimit(3)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func hasChanges(_ note: MemoryRecord) -> Bool {
        draft != note.currentText || category != note.category
    }

    private func saveChanges(_ note: MemoryRecord) async {
        do {
            if draft != note.currentText { try await store.correct(id: note.id, text: draft) }
            if category != note.category { try await store.setCategory(id: note.id, to: category) }
            // Say saved only if the store now holds what is on screen.
            if let stored = store.notes.first(where: { $0.id == note.id }),
               stored.currentText == draft.trimmingCharacters(in: .whitespacesAndNewlines) || stored.currentText == draft,
               stored.category == category {
                message = NSLocalizedString("Saved.", comment: "")
            } else {
                message = NSLocalizedString("The change couldn't be confirmed, so it isn't counted as saved. Your text is still here.", comment: "")
            }
        } catch {
            message = MacError.message(for: error)
        }
    }

    private func delete() async {
        do {
            try await store.delete(id: noteID)
        } catch {
            message = MacError.message(for: error)
        }
    }
}

/// A new note, written here or filled from a clip. The note is saved only on Save.
struct NewNoteSheet: View {
    @Environment(MacStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: NewNoteRequest
    @State private var text = ""
    @State private var category: MemoryCategory = .other
    @State private var message: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.clip == nil ? "New note" : "Save this clip as a note")
                .font(.headline)
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 160)
                .accessibilityLabel("Note text")
                .accessibilityIdentifier("mac.newNoteText")
            HStack {
                Picker("Type", selection: $category) {
                    ForEach(MemoryCategory.noteCategories, id: \.self) { Text($0.macName).tag($0) }
                }
                .frame(maxWidth: 240)
                Spacer()
                Text("\(text.unicodeScalars.count) / \(MemoryLimits.maxTextLength)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("mac.newNoteMessage")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mac.newNoteSave")
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear {
            text = request.text
            focused = true
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if let clip = request.clip {
                try await store.saveClip(clip, text: text, category: category)
            } else {
                try await store.save(text: text, category: category)
            }
            dismiss()
        } catch {
            // The text stays in the box, and nothing was saved.
            message = MacError.message(for: error)
        }
    }
}
