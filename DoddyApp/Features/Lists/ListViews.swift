import DoddyCore
import SwiftUI

// Lists (ADR-216), after the "Doddy Lists" canvas: overview (1), a list (2), its menu (3).
// Everything shown is what the store read back; every change has an Undo.

/// Memories › Lists: one card per list, and New list.
struct ListsOverview: View {
    @Environment(MemoryStore.self) private var store
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.lists.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    // No lists yet: he waits, cross-legged (ADR-313).
                    WholeDoddyView(pose: .crosslegged, height: 80)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No lists yet").font(.title3.weight(.medium)).accessibilityAddTraits(.isHeader)
                        Text("Make one here, or tell Doddy: “add milk to my shopping list”. Lists stay on this iPhone.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityIdentifier("lists.empty")
            }
            // A Focus can bring one list to the front (ADR-312).
            ForEach(FocusFilterState.shared.settings.ordered(store.lists)) { list in
                NavigationLink(value: MemoryNavigationRoute.note(list.id)) {
                    ListCard(list: list)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lists.card")
            }
            Button { creating = true } label: {
                HStack { Image(systemName: "plus"); Text("New list"); Spacer() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!store.isStorageAvailable || store.lists.count >= ListLimits.lists)
            .accessibilityIdentifier("lists.new")
            if !store.lists.isEmpty {
                Label("Or just tell Doddy: “add milk to my shopping list”.", systemImage: "mic")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .sheet(isPresented: $creating) { NewListSheet() }
    }
}

private struct ListCard: View {
    @Environment(NoteReminderStore.self) private var reminders
    let list: DoddyList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(list.name).font(.headline)
                Spacer()
                Text(list.summary).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            if !list.open.isEmpty {
                Text(list.open.prefix(5).map(\.text).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
            if let reminder = reminders.reminders.first(where: { $0.memoryID == list.id }) {
                Label("Reminds you \(ReminderFormat.short(reminder))", systemImage: "bell")
                    .font(.footnote)
                    .foregroundStyle(Theme.confirmed)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the list")
    }
}

/// A note or a list, by id: lists open their own screen.
struct MemoryOrListView: View {
    @Environment(MemoryStore.self) private var store
    let id: UUID

    var body: some View {
        if store.list(id: id) != nil {
            ListDetailView(listID: id)
        } else {
            MemoryDetailView(memoryID: id)
        }
    }
}

/// One list (canvas 2 and 3): add field, open items, Done, menu, Undo receipt, reminder.
struct ListDetailView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let listID: UUID
    @State private var newItem = ""
    @State private var errorMessage: String?
    @State private var addNote: String?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var showReminder = false
    /// The usual (ADR-343).
    @State private var usualFor: DoddyList?
    @State private var confirmShopping = false
    @FocusState private var addFocused: Bool
    private let shopping = ShoppingModeController.shared
    private let sharing = SharedListsController.shared
    @State private var confirmSharing = false
    @State private var confirmStopSharing = false
    @State private var cloudShare: CloudShareSheet?
    @State private var isSharing = false
    /// The last open item was just ticked (ADR-313): Doddy jumps, once.
    @State private var finishedNow = false
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        Group {
            if let list = store.list(id: listID) {
                content(list)
            } else {
                VStack(spacing: 12) {
                    Text("This list no longer exists.").foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        // Only a change seen here counts: opening a list that was already finished doesn't jump.
        .onChange(of: store.list(id: listID)?.open.count ?? 0) { old, new in
            finishedNow = old > 0 && new == 0 && !(store.list(id: listID)?.items.isEmpty ?? true)
        }
    }

    private func content(_ list: DoddyList) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name).font(.largeTitle.weight(.medium)).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("list.name")
                    Text(list.summary).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.canvas)
                if let link = sharing.isShared(list.id) {
                    SharedListStatusRow(list: list, link: link) { Task { await openPeople(list) } }
                        .listRowBackground(Theme.canvas)
                }
                if shopping.isOn(for: list.id) {
                    HStack {
                        Label("Shopping mode is on: this list is on your Lock Screen.", systemImage: "cart")
                            .font(.footnote)
                        Spacer()
                        Button("End") { shopping.end() }.frame(minHeight: 44)
                    }
                    .listRowBackground(Theme.canvas)
                    .accessibilityIdentifier("list.shoppingMode")
                }
                if let problem = shopping.problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.error).listRowBackground(Theme.canvas)
                }
                HStack(spacing: 8) {
                    TextField("Add an item", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await add(list) } }
                        .accessibilityIdentifier("list.addField")
                    Button { Task { await add(list) } } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ink)
                    .accessibilityLabel("Add")
                    .disabled(ListText.cleaned(newItem) == nil)
                }
                .listRowBackground(Theme.canvas)
                if let addNote {
                    Text(addNote).font(.footnote).foregroundStyle(Theme.secondaryText).listRowBackground(Theme.canvas)
                }
                if let errorMessage {
                    ProblemView(message: errorMessage).listRowBackground(Theme.canvas)
                }
            }
            Section {
                if list.open.isEmpty {
                    HStack(spacing: 14) {
                        // Empty: he waits, cross-legged. Just finished: a jump (ADR-313).
                        if list.items.isEmpty {
                            WholeDoddyView(pose: .crosslegged, height: 70)
                        } else if finishedNow {
                            DoddyMotionView(motion: .jump, height: 70)
                        }
                        Text(list.items.isEmpty ? "Nothing on this list yet." : "Nothing left.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .listRowBackground(Theme.canvas)
                }
                ForEach(list.open) { item in
                    row(item, list: list)
                }
            }
            if !list.done.isEmpty {
                Section {
                    ForEach(list.done) { item in
                        row(item, list: list)
                    }
                } header: {
                    HStack {
                        Text("Done (\(list.done.count))")
                        Spacer()
                        Button("Clear ticked") { run { try await store.clearTicked(listID: list.id) } }
                            .font(.subheadline)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("list.clearTicked")
                    }
                }
            }
            Section {
                NoteReminderSection(memoryID: list.id)
                    .listRowBackground(Theme.canvas)
                // A shared list's place for everyone (ADR-307).
                if sharing.isShared(list.id) != nil {
                    SharedPlaceRow(list: list)
                        .listRowBackground(Theme.canvas)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let undo = store.listUndo, undo.listID == listID {
                ListUndoBar(undo: undo)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { menu(list) }
        }
        .alert("Rename list", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { run { try await store.renameList(list.id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(list.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                Task {
                    do {
                        // A shared list stops being shared first (ADR-263), so nothing is left in iCloud.
                        if sharing.isShared(list.id) != nil { try await sharing.stop(list.id) }
                        try await store.delete(id: list.id)
                        dismiss()
                    } catch {
                        errorMessage = UserFacingError.listMessage(for: error)
                    }
                }
            }
        } message: {
            Text("The list and its \(list.items.count) item\(list.items.count == 1 ? "" : "s") are removed from this iPhone. You can undo for a few seconds afterwards.")
        }
        .sheet(isPresented: $showReminder) { NoteReminderSheet(memoryID: list.id, startAtTime: false) }
        .sheet(item: $usualFor) { UsualItemsSheet(list: $0) }
        .confirmationDialog("Share “\(list.name)” through iCloud?", isPresented: $confirmSharing, titleVisibility: .visible) {
            Button("Share") { Task { await startSharing(list) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The list's name and items are copied to your iCloud, and you choose who to invite. Everyone you invite can see, add and tick items; their changes come back here. Your notes and other lists aren't shared.")
        }
        .confirmationDialog(sharing.isShared(list.id)?.role == .participant ? "Leave this shared list?" : "Stop sharing this list?",
                            isPresented: $confirmStopSharing, titleVisibility: .visible) {
            Button(sharing.isShared(list.id)?.role == .participant ? "Leave" : "Stop sharing", role: .destructive) {
                run { try await sharing.stop(list.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(sharing.isShared(list.id)?.role == .participant
                 ? "The list stays on this iPhone as your own. You won't see others' changes any more."
                 : "The copy in your iCloud is deleted and the people you invited lose the list. It stays on this iPhone.")
        }
        .sheet(item: $cloudShare) { sheet in
            CloudSharingView(sheet: sheet, listName: list.name) {
                Task { await sharing.load() }
            }
        }
        .confirmationDialog("Show this list on your Lock Screen?", isPresented: $confirmShopping, titleVisibility: .visible) {
            Button("Start shopping mode") { shopping.start(list) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its items show on the Lock Screen and in the Dynamic Island until every item is ticked or you end it, so anyone who sees your iPhone can read them. Ticking there ticks here.")
        }
    }

    private func row(_ item: ListItem, list: DoddyList) -> some View {
        HStack(spacing: 12) {
            Button {
                run { try await store.setDone([item], done: !item.isDone, listID: list.id) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(item.isDone ? Theme.confirmed : Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.text)
            .accessibilityValue(item.isDone ? "Ticked" : "Not ticked")
            .accessibilityAddTraits(.isToggle)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? Theme.secondaryText : Theme.ink)
                // Shared lists (ADR-285): who else added or ticked it, on this iPhone only.
                let who = sharing.label(for: item)
                if !who.isEmpty {
                    Text(Self.whoText(who))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityHidden(true)
            Spacer()
        }
        .listRowBackground(Theme.canvas)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                run { try await store.removeFromList([item], listID: list.id) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func saveTemplate(_ list: DoddyList) {
        errorMessage = nil
        switch ListTemplateStore.save(list) {
        case .saved(let template):
            addNote = String(format: NSLocalizedString("Saved \u{201C}%@\u{201D} as a template with %lld items. Start a new list from it under New list, or ask Doddy.", comment: ""), template.name, template.items.count)
        case .replaced(let template):
            addNote = String(format: NSLocalizedString("Updated the \u{201C}%@\u{201D} template: %lld items.", comment: ""), template.name, template.items.count)
        case .empty:
            addNote = NSLocalizedString("This list is empty, so there's nothing to keep as a template.", comment: "")
        case .full:
            errorMessage = String(format: NSLocalizedString("You have %lld templates, the most Doddy keeps. Remove one under New list first.", comment: ""), ListTemplates.maxTemplates)
        case nil:
            errorMessage = NSLocalizedString("That couldn't be saved on this iPhone. Try again.", comment: "")
        }
    }

    private func menu(_ list: DoddyList) -> some View {
        Menu {
            Button { run { try await store.untickAll(listID: list.id) } } label: {
                Label("Untick all", systemImage: "arrow.counterclockwise")
            }
            .disabled(list.done.isEmpty)
            Button { showReminder = true } label: { Label("Remind me", systemImage: "bell") }
            // Shopping mode (ADR-257): this list on the Lock Screen and in the Dynamic Island.
            if shopping.isOn(for: list.id) {
                Button { shopping.end() } label: { Label("End shopping mode", systemImage: "cart.badge.minus") }
            } else {
                Button { confirmShopping = true } label: { Label("Shopping mode", systemImage: "cart") }
                    .disabled(list.open.isEmpty)
            }
            ShareLink(item: list.shareText, preview: SharePreview(list.name)) {
                Label("Share as text", systemImage: "square.and.arrow.up")
            }
            // The same words as a picture, with Doddy (ADR-313); no Doddy in the preview either
            // when his pictures are hidden (ADR-331).
            if hideCharacterArt {
                ShareLink(item: ListShareCard(list: list), preview: SharePreview(list.name)) {
                    Label("Share as a picture", systemImage: "photo")
                }
            } else {
                ShareLink(item: ListShareCard(list: list), preview: SharePreview(list.name, image: Image("WholeDoddy_wave"))) {
                    Label("Share as a picture", systemImage: "photo")
                }
            }
            // Shared lists through iCloud (ADR-263), only in builds set up for it.
            if sharing.isAvailable {
                if let link = sharing.isShared(list.id) {
                    Button { Task { await openPeople(list) } } label: { Label("People", systemImage: "person.2") }
                    Button(role: .destructive) { confirmStopSharing = true } label: {
                        Label(link.role == .owner ? "Stop sharing" : "Leave shared list", systemImage: "person.2.slash")
                    }
                } else {
                    Button { confirmSharing = true } label: { Label("Share with people…", systemImage: "person.2") }
                }
            }
            // The usual (ADR-343): items ticked at least twice on lists with this name.
            Button { usualFor = list } label: { Label("The usual…", systemImage: "arrow.clockwise.circle") }
                .disabled(UsualItemsStore.current().suggestions(for: list).isEmpty)
            // List templates (ADR-334): the items as written, ticks not kept.
            Button { saveTemplate(list) } label: { Label("Save as template", systemImage: "square.on.square") }
                .disabled(list.items.isEmpty)
            Button { newName = list.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
            Button { run { try await store.clearTicked(listID: list.id) } } label: {
                Label("Clear ticked (\(list.done.count))", systemImage: "checkmark")
            }
            .disabled(list.done.isEmpty)
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete list", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
        }
        .accessibilityLabel("List options")
        .accessibilityIdentifier("list.menu")
    }

    /// After Share on the confirmation: the list goes to iCloud, then Apple's screen to invite people.
    private func startSharing(_ list: DoddyList) async {
        guard !isSharing else { return }
        isSharing = true
        defer { isSharing = false }
        errorMessage = nil
        do {
            cloudShare = try await sharing.share(list)
        } catch {
            errorMessage = SharingError.message(for: error)
        }
    }

    private func openPeople(_ list: DoddyList) async {
        do {
            cloudShare = try await sharing.existingShare(list.id)
        } catch {
            errorMessage = SharingError.message(for: error)
        }
    }

    /// "Added by Marta · Ticked by Tom" (ADR-285).
    static func whoText(_ label: SharedItemLabel) -> String {
        func shown(_ name: String) -> String { name == "someone else" ? NSLocalizedString("someone else", comment: "") : name }
        let label = SharedItemLabel(addedBy: label.addedBy.map(shown), doneBy: label.doneBy.map(shown))
        return [label.addedBy.map { String(format: NSLocalizedString("Added by %@", comment: ""), $0) },
         label.doneBy.map { String(format: NSLocalizedString("Ticked by %@", comment: ""), $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func add(_ list: DoddyList) async {
        guard let text = ListText.cleaned(newItem) else { return }
        errorMessage = nil
        do {
            let result = try await store.addToList([text], listID: list.id, source: .typed)
            if !result.added.isEmpty { newItem = "" }
            addNote = result.alreadyThere.isEmpty ? (result.tooLong.isEmpty ? (result.noRoom.isEmpty ? nil
                : "The list is full (\(ListLimits.itemsPerList) items).")
                : "An item can be up to \(ListLimits.itemLength) characters.")
                : "“\(text)” is already on the list."
            addFocused = true
        } catch {
            errorMessage = UserFacingError.listMessage(for: error)
        }
    }

    private func run(_ change: @escaping () async throws -> Void) {
        Task {
            errorMessage = nil
            do { try await change() } catch { errorMessage = UserFacingError.listMessage(for: error) }
        }
    }
}

/// "Added eggs · Undo" after any list change; it goes away after a few seconds.
struct ListUndoBar: View {
    @Environment(MemoryStore.self) private var store
    let undo: ListUndo
    @State private var failed = false

    var body: some View {
        HStack(spacing: 12) {
            Text(failed ? "Couldn't undo. Nothing changed." : undo.message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            if !failed {
                Button("Undo") {
                    Task {
                        do { try await store.undoListChange(undo) } catch { failed = true }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("list.undo")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Theme.quietSurface)
        .task(id: undo.id) {
            try? await Task.sleep(for: .seconds(8))
            if store.listUndo == undo { store.listUndo = nil }
        }
    }
}

/// New list (canvas 1): a name and, if you like, the first items, one per line.
struct NewListSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var items = ""
    @State private var errorMessage: String?
    /// What came from a photo (ADR-286), said once above the items.
    @State private var photoNote: String?
    /// Saved list templates (ADR-334).
    @State private var templates = ListTemplateStore.current()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Shopping", text: $name)
                        .accessibilityIdentifier("newList.name")
                }
                Section("First items, one per line (optional)") {
                    TextEditor(text: $items)
                        .frame(minHeight: 120)
                        .accessibilityLabel("First items, one per line")
                }
                if !templates.all.isEmpty {
                    Section("Start from a template") {
                        ForEach(templates.all) { template in
                            Button {
                                if ListText.cleaned(name) == nil { name = template.name }
                                let existing = items.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                                items = ListTemplates.items(from: template, plus: existing).joined(separator: "\n")
                            } label: {
                                HStack {
                                    Text(template.name)
                                    Spacer()
                                    Text(String(format: NSLocalizedString("%lld items", comment: ""), template.items.count))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    if ListTemplateStore.remove(template.id) { templates = ListTemplateStore.current() }
                                } label: { Label("Remove template", systemImage: "trash") }
                            }
                        }
                    }
                }
                Section {
                    ListPhotoPicker { proposal in
                        if ListText.cleaned(name) == nil, let suggested = proposal.name { name = suggested }
                        let existing = items.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        items = (existing + proposal.items).joined(separator: "\n")
                        photoNote = proposal.leftOut == 0
                            ? String(format: NSLocalizedString("Read %lld lines from the photo. Check them before Create.", comment: ""), proposal.items.count)
                            : String(format: NSLocalizedString("Read %lld lines from the photo; %lld were too long or past the limit. Check them before Create.", comment: ""), proposal.items.count, proposal.leftOut)
                    }
                    if let photoNote {
                        Text(photoNote).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                if let errorMessage {
                    Section { ProblemView(message: errorMessage) }
                }
            }
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            do {
                                _ = try await store.createList(
                                    name: name, items: items.components(separatedBy: .newlines), source: .typed)
                                dismiss()
                            } catch {
                                errorMessage = UserFacingError.listMessage(for: error)
                            }
                        }
                    }
                    .disabled(ListText.cleaned(name) == nil)
                    .accessibilityIdentifier("newList.create")
                }
            }
        }
    }
}
