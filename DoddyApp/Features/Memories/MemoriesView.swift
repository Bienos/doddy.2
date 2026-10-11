import DoddyCore
import SwiftUI
import UIKit

/// Real repository records only. No seeded examples or generated personal facts.
struct MemoriesView: View {
    @Environment(MemoryStore.self) private var store
    @Binding var showFind: Bool
    @State private var modal: MemoryModal?
    @State private var path: [MemoryNavigationRoute] = []
    /// Type filter (ADR-182). Ignored once no note of that type is left.
    @State private var category: MemoryCategory?
    @AppStorage(PreferenceKey.memorySort) private var sortRaw = MemorySort.newestFirst.rawValue
    @AppStorage(PreferenceKey.pinnedNotes) private var pinnedRaw = "[]"
    @State private var pinMessage: String?
    /// Notes or Lists (ADR-216).
    @AppStorage(PreferenceKey.memoriesShowsLists) private var showsLists = false

    /// The filter in effect: the chosen type, but only while a filter is offered and a note of
    /// that type exists. When it stops applying the choice is cleared (see `onChange` below),
    /// so it can't spring back later when a note of that type shows up again.
    private var activeCategory: MemoryCategory? {
        MemoryFilter.choices(store.memories).contains { $0.category == category } ? category : nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        DoddyWordmark()
                        Spacer()
                        Button { modal = .capture } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("Save a detail")
                            .accessibilityIdentifier("memories.add").disabled(!store.isStorageAvailable)
                    }
                    JourneyHeading(eyebrow: "Little things, kept", title: "Your memories.",
                                   subtitle: "Your words. Ready when you need them.")
                    // A strip of the memory library, edge to edge, between the heading and the
                    // notes; no text over it (ADR-308).
                    SceneryBackdrop(place: .memory, height: 110, focus: 0.3)
                        .padding(.horizontal, -24)
                    Button { showFind = true } label: {
                        HStack { Image(systemName: "magnifyingglass"); Text("Find something you saved"); Spacer() }
                    }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("memories.find")
                    Picker("Show", selection: $showsLists) {
                        Text("Notes").tag(false)
                        Text("Lists").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("memories.notesOrLists")
                    if let problem = store.environment.storageProblem ?? store.loadError {
                        ProblemView(message: problem, showsDoddy: true)
                    } else if !store.hasLoaded {
                        ProgressView("Loading notes")
                    } else if showsLists {
                        ListsOverview()
                    } else if store.memories.isEmpty {
                        EmptyMemoriesView { modal = .capture }
                    } else {
                        let choices = MemoryFilter.choices(store.memories)
                        let active = choices.contains { $0.category == category } ? category : nil
                        HStack {
                            Text("YOUR SAVED NOTES").font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
                            Spacer()
                            if store.memories.count > 1 {
                                MemorySortMenu(sortRaw: $sortRaw)
                            }
                        }
                        if !choices.isEmpty {
                            MemoryTypeFilterRow(choices: choices, total: store.memories.count, selection: $category, active: active)
                        }
                        let pins = PinnedNotes(stored: pinnedRaw)
                        LazyVStack(spacing: 12) {
                            // Pinned notes first (ADR-187), then the chosen order.
                            ForEach(pins.apply(to: MemorySort(stored: sortRaw).apply(to: MemoryFilter.apply(active, to: store.memories)))) { record in
                                let isPinned = pins.isPinned(record.id)
                                let hides = PrivateNotesStore.current().contains(record.id) && !AppLock.shared.privateUnlocked
                                MemoryLinkCard(record: record, isPinned: isPinned, hidesText: hides)
                                    .contextMenu {
                                        // The same actions as on the note's screen, without opening it (ADR-188).
                                        Button {
                                            let change = PinnedNotes.toggle(record.id, stored: &pinnedRaw, existing: store.memories)
                                            pinMessage = change == .full ? PinnedNotes.fullMessage : nil
                                        } label: {
                                            Label(isPinned ? "Unpin from the top" : "Pin to the top", systemImage: isPinned ? "pin.slash" : "pin")
                                        }
                                        // A private note's words only after Face ID (ADR-310).
                                        if !hides {
                                            Button { UIPasteboard.general.string = record.currentText } label: {
                                                Label("Copy text", systemImage: "doc.on.doc")
                                            }
                                            ShareLink(item: record.currentText) {
                                                Label("Share text", systemImage: "square.and.arrow.up")
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas).foregroundStyle(Theme.ink)
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .navigationDestination(for: MemoryNavigationRoute.self) { route in
                switch route {
                case .find(let query):
                    // A new "Find in Doddy" request resets the screen even with the same words.
                    FindMemoriesView(initialQuery: query).id(ShortcutRouter.shared.findRequest?.id)
                case .note(let id): MemoryOrListView(id: id)
                }
            }
            .onChange(of: activeCategory) { _, active in
                if active == nil { category = nil }
            }
            // An alert, not a label above the list: a long press low in the list would otherwise
            // look like it did nothing.
            .alert(
                "Pin limit reached",
                isPresented: Binding(get: { pinMessage != nil }, set: { if !$0 { pinMessage = nil } })
            ) {
                Button("OK", role: .cancel) { pinMessage = nil }
            } message: {
                Text(pinMessage ?? "")
            }
            .sheet(item: $modal) { _ in CaptureView() }
        }
        .onChange(of: showFind, initial: true) { _, requested in
            guard requested else { return }
            // One typed path owns both search and source detail. Mixing a boolean
            // search destination with value pushes reset the search on iOS 27.
            path = [.find(query: ShortcutRouter.shared.takeFindQuery())]
            showFind = false
        }
    }
}

/// "Newest first / Oldest first / Recently changed". Display only; it remembers the choice.
private struct MemorySortMenu: View {
    @Binding var sortRaw: String

    private static func title(_ sort: MemorySort) -> String {
        switch sort {
        case .newestFirst: NSLocalizedString("Newest first", comment: "")
        case .oldestFirst: NSLocalizedString("Oldest first", comment: "")
        case .recentlyChanged: NSLocalizedString("Recently changed", comment: "")
        }
    }

    var body: some View {
        Menu {
            Picker("Order", selection: $sortRaw) {
                ForEach(MemorySort.allCases, id: \.self) { Text(Self.title($0)).tag($0.rawValue) }
            }
        } label: {
            Label(Self.title(MemorySort(stored: sortRaw)), systemImage: "arrow.up.arrow.down")
                .font(.caption)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Order, \(Self.title(MemorySort(stored: sortRaw)))")
        .accessibilityIdentifier("memories.sort")
    }
}

/// "All" plus one chip per type in use, with counts. Selecting the active chip again clears it.
struct MemoryTypeFilterRow: View {
    let choices: [(category: MemoryCategory, count: Int)]
    let total: Int
    @Binding var selection: MemoryCategory?
    let active: MemoryCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: total, isOn: active == nil) { selection = nil }
                    .accessibilityIdentifier("memories.filter.all")
                ForEach(choices, id: \.category) { choice in
                    chip(choice.category.displayName, count: choice.count, isOn: active == choice.category) {
                        selection = active == choice.category ? nil : choice.category
                    }
                    .accessibilityIdentifier("memories.filter.\(choice.category.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show notes of one type")
    }

    private func chip(_ title: String, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(title) \(count)")
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(isOn ? Theme.ink : Theme.quietSurface, in: Capsule())
                .foregroundStyle(isOn ? Theme.canvas : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "note" : "notes")")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct EmptyMemoriesView: View {
    @Environment(MemoryStore.self) private var store
    let onSave: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            UploadedCharacterView(assetName: "UploadedDoddy_Sitting", height: 150)
            Text("No memories yet").font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text("Only what you choose to save appears here. Nothing is added automatically.")
                .foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            Button("Save a detail", action: onSave).buttonStyle(PrimaryButtonStyle())
                .disabled(!store.isStorageAvailable)
        }
        .frame(maxWidth: .infinity).accessibilityIdentifier("memories.empty")
    }
}

#Preview("Empty local notebook") {
    MemoriesView(showFind: .constant(false)).environment(MemoryStore(environment: .unavailable))
        .environment(NoteReminderStore(coordinator: nil))
}
