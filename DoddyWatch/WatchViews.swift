import DoddyCore
import SwiftUI

struct WatchRootView: View {
    @Environment(WatchLink.self) private var link

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchNoteEntry()
                } label: {
                    Label("New note", systemImage: "square.and.pencil")
                }
                if let snapshot = link.snapshot {
                    if snapshot.isOn {
                        content(snapshot)
                    } else {
                        Text("Notes and lists are hidden. Turn on “Show notes and lists on Apple Watch” in Doddy's Settings on your iPhone.")
                            .font(.footnote)
                    }
                } else {
                    Text("Open Doddy on your iPhone once to see your notes and lists here.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Doddy")
        }
    }

    /// Words from notes and lists are `privacySensitive` (review I7): watchOS hides them while the
    /// wrist is down and the screen is Always On, where anyone nearby can read it.
    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        if !snapshot.pinned.isEmpty {
            Section("Pinned") {
                ForEach(snapshot.pinned) { note in Text(note.text).font(.footnote).privacySensitive() }
            }
        }
        let upcoming = snapshot.reminders(after: .now)
        if !upcoming.isEmpty {
            Section("Next") {
                ForEach(Array(upcoming.enumerated()), id: \.offset) { _, reminder in
                    VStack(alignment: .leading) {
                        Text(reminder.text ?? "A note reminder").font(.footnote).privacySensitive()
                        Text(reminder.fireAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !snapshot.lists.isEmpty {
            Section("Lists") {
                ForEach(snapshot.lists) { list in
                    NavigationLink {
                        WatchListView(listID: list.id)
                    } label: {
                        HStack {
                            Text(list.name).privacySensitive()
                            Spacer()
                            Text("\(list.openCount)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        Text("As of \(snapshot.writtenAt.formatted(date: .omitted, time: .shortened)) on your iPhone.")
            .font(.caption2).foregroundStyle(.secondary)
    }
}

/// A list's items. A tap asks the iPhone; the item changes here only when the iPhone's next
/// snapshot shows it changed, and the reply is said in words.
struct WatchListView: View {
    @Environment(WatchLink.self) private var link
    let listID: UUID
    @State private var working: UUID?
    @State private var message: String?
    /// An item to add, said (dictation) or written (ADR-287).
    @State private var newItem = ""
    @State private var isAdding = false

    var body: some View {
        List {
            if let list = link.snapshot?.list(id: listID) {
                Section {
                    TextField("Add an item", text: $newItem)
                        .submitLabel(.done)
                        .onSubmit { Task { await add() } }
                    if !newItem.isEmpty {
                        Button(isAdding ? "Adding…" : "Add") { Task { await add() } }
                            .disabled(isAdding)
                    }
                }
                ForEach(list.items) { item in
                    Button {
                        Task { await tick(item) }
                    } label: {
                        HStack {
                            Image(systemName: working == item.id ? "hourglass" : (item.isDone ? "checkmark.square" : "square"))
                            Text(item.text).strikethrough(item.isDone).foregroundStyle(item.isDone ? .secondary : .primary)
                                .privacySensitive()
                        }
                    }
                    .disabled(working != nil)
                    .accessibilityLabel("\(item.text), \(item.isDone ? "ticked" : "not ticked")")
                }
                if list.openCount + list.doneCount > list.items.count {
                    Text("More on your iPhone.").font(.caption2).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.footnote) }
            } else {
                Text("This list is no longer on your iPhone.").font(.footnote)
            }
        }
        .navigationTitle(link.snapshot?.list(id: listID)?.name ?? "List")
    }

    /// Checked here, added by the iPhone, said only from its reply. The item appears in the list
    /// with the iPhone's next snapshot.
    private func add() async {
        if let problem = WatchNote.itemProblem(newItem) {
            message = problem
            return
        }
        isAdding = true
        defer { isAdding = false }
        let outcome = await link.send(.addToList(listID: listID, text: newItem))
        message = outcome.message
        if case .reply(.addedToList) = outcome { newItem = "" }
    }

    private func tick(_ item: WidgetSnapshot.Item) async {
        working = item.id
        defer { working = nil }
        message = await link.send(.tick(listID: listID, itemID: item.id, shownDone: item.isDone)).message
    }
}

/// Write or dictate a note, check it, then Save. Saved only on the iPhone, and only said so
/// when the iPhone confirms.
struct WatchNoteEntry: View {
    @Environment(WatchLink.self) private var link
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if saved {
                    Label("Saved in Doddy on your iPhone.", systemImage: "checkmark.circle")
                    Button("Done") { dismiss() }
                } else {
                    TextField("Your note", text: $text, axis: .vertical)
                    if !text.isEmpty {
                        Text("Check the words, then Save.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || text.allSatisfy(\.isWhitespace))
                    if let message { Text(message).font(.footnote) }
                }
            }
        }
        .navigationTitle("New note")
    }

    private func save() async {
        if let problem = WatchNote.problem(text) {
            message = problem
            return
        }
        isSaving = true
        defer { isSaving = false }
        let outcome = await link.send(.saveNote(text: text))
        if outcome == .reply(.saved) {
            saved = true
        } else {
            message = outcome.message
        }
    }
}
