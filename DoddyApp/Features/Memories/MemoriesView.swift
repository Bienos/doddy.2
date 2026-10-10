import DoddyCore
import SwiftUI

/// Real repository records only. No seeded examples or generated personal facts.
struct MemoriesView: View {
    @Environment(MemoryStore.self) private var store
    @Binding var showFind: Bool
    @State private var modal: MemoryModal?
    @State private var path: [MemoryNavigationRoute] = []
    /// Type filter (ADR-139). Ignored once no note of that type is left.
    @State private var category: MemoryCategory?

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
                    Button { showFind = true } label: {
                        HStack { Image(systemName: "magnifyingglass"); Text("Find something you saved"); Spacer() }
                    }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("memories.find")
                    if let problem = store.environment.storageProblem ?? store.loadError {
                        ProblemView(message: problem)
                    } else if !store.hasLoaded {
                        ProgressView("Loading notes")
                    } else if store.memories.isEmpty {
                        EmptyMemoriesView { modal = .capture }
                    } else {
                        let choices = MemoryFilter.choices(store.memories)
                        let active = choices.contains { $0.category == category } ? category : nil
                        Text("YOUR SAVED NOTES").font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
                        if !choices.isEmpty {
                            MemoryTypeFilterRow(choices: choices, total: store.memories.count, selection: $category, active: active)
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(MemoryFilter.apply(active, to: store.memories)) { MemoryLinkCard(record: $0) }
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
                case .note(let id): MemoryDetailView(memoryID: id)
                }
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

/// "All" plus one chip per type in use, with counts. Selecting the active chip again clears it.
private struct MemoryTypeFilterRow: View {
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
}
