import DoddyCore
import SwiftUI

/// The middle column when Lists is picked.
struct MacListsColumn: View {
    @Environment(MacStore.self) private var store
    @Binding var selection: UUID?
    @State private var naming = false
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(store.lists) { list in
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                    Text(list.summary).font(.caption).foregroundStyle(.secondary)
                }
                .tag(list.id)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay {
            if store.hasLoaded && store.lists.isEmpty {
                ContentUnavailableView("No lists yet", systemImage: "checklist",
                                       description: Text("Make one with the + button."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button { newName = ""; message = nil; naming = true } label: { Label("New list", systemImage: "plus") }
                    .disabled(!store.isStorageAvailable)
                    .accessibilityIdentifier("mac.newList")
            }
        }
        .alert("New list", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Make list") { Task { await make() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message ?? NSLocalizedString("Give the list a name.", comment: ""))
        }
        .accessibilityIdentifier("mac.lists")
    }

    private func make() async {
        do {
            let list = try await store.createList(name: newName, items: [])
            selection = list.id
        } catch {
            // Show why, and let the person try again.
            message = MacError.message(for: error)
            naming = true
        }
    }
}

/// One list: tick items, add more, clear the ticked ones, rename, delete.
struct MacListDetail: View {
    @Environment(MacStore.self) private var store
    let listID: UUID
    @State private var newItem = ""
    @State private var message: String?
    @State private var renaming = false
    @State private var renameTo = ""
    @State private var confirmDelete = false

    private var list: DoddyList? { store.lists.first { $0.id == listID } }

    var body: some View {
        if let list {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(list.name).font(.title2.bold())
                    Spacer()
                    Menu {
                        Button("Rename…") { renameTo = list.name; renaming = true }
                        Button("Clear ticked items") { run { try await store.clearTicked(listID: listID) } }
                            .disabled(list.done.isEmpty)
                        Divider()
                        Button("Delete list…", role: .destructive) { confirmDelete = true }
                    } label: { Label("List actions", systemImage: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                }
                HStack {
                    TextField("Add an item", text: $newItem)
                        .onSubmit(add)
                        .accessibilityIdentifier("mac.addItem")
                    Button("Add", action: add)
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                List {
                    ForEach(list.open) { row($0) }
                    if !list.done.isEmpty {
                        Section("Done") { ForEach(list.done) { row($0) } }
                    }
                }
                .overlay {
                    if list.items.isEmpty {
                        ContentUnavailableView("Nothing on this list", systemImage: "checklist")
                    }
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("mac.listMessage")
                }
            }
            .padding()
            .alert("Rename list", isPresented: $renaming) {
                TextField("Name", text: $renameTo)
                Button("Rename") { run { try await store.renameList(listID, to: renameTo) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(String(format: NSLocalizedString("Delete “%@”?", comment: ""), list.name), isPresented: $confirmDelete) {
                Button("Delete list", role: .destructive) { run { try await store.deleteList(listID) } }
            } message: {
                Text("The list and its items are removed from this Mac. This can't be undone.")
            }
        } else {
            ContentUnavailableView("This list is gone", systemImage: "checklist")
        }
    }

    private func row(_ item: ListItem) -> some View {
        HStack {
            Button {
                run { try await store.setDone(item, done: !item.isDone) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: item.isDone ? NSLocalizedString("Done: %@. Tap to untick.", comment: "") : NSLocalizedString("%@. Tap to tick.", comment: ""), item.text))
            Text(item.text)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
            Spacer()
            Button(role: .destructive) {
                run { try await store.removeFromList(item) }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(format: NSLocalizedString("Remove %@", comment: ""), item.text))
        }
    }

    private func add() {
        let text = newItem
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            do {
                let result = try await store.addToList([text], listID: listID)
                if result.added.isEmpty {
                    if !result.alreadyThere.isEmpty {
                        message = NSLocalizedString("That item is already on the list.", comment: "")
                    } else if !result.tooLong.isEmpty {
                        message = NSLocalizedString("That item is too long.", comment: "")
                    } else {
                        message = NSLocalizedString("The list is full.", comment: "")
                    }
                } else {
                    message = nil
                    newItem = ""
                }
            } catch {
                message = MacError.message(for: error)
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); message = nil } catch { message = MacError.message(for: error) }
        }
    }
}
