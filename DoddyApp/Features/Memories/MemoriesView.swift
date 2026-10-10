import DoddyCore
import SwiftUI

/// Real repository records only. No seeded examples or generated personal facts.
struct MemoriesView: View {
    @Environment(MemoryStore.self) private var store
    @Binding var showFind: Bool
    @State private var modal: MemoryModal?
    @State private var path: [MemoryNavigationRoute] = []

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
                        Text("YOUR SAVED NOTES").font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
                        LazyVStack(spacing: 12) {
                            ForEach(store.memories) { MemoryLinkCard(record: $0) }
                        }
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas).foregroundStyle(Theme.ink)
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .navigationDestination(for: MemoryNavigationRoute.self) { route in
                switch route {
                case .find(let query): FindMemoriesView(initialQuery: query)
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
