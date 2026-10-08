import DoddyCore
import SwiftUI

/// Saved memories (newest first) and lexical search. Results are always real stored records;
/// no match is said plainly.
struct MemoriesView: View {
    @Environment(MemoryStore.self) private var store
    @State private var query = ""
    @State private var outcome: RecallOutcome?
    @State private var searchError: String?
    @State private var showCapture = false

    private var isSearching: Bool { !query.allSatisfy(\.isWhitespace) }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
                .navigationTitle("Memories")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
                .searchable(text: $query, prompt: "Find something")
                .task(id: "\(query)|\(store.revision)") { await runSearch() }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showCapture = true } label: { Label("Save a detail", systemImage: "plus") }
                            .disabled(!store.isStorageAvailable)
                    }
                }
                .sheet(isPresented: $showCapture) { CaptureView() }
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var content: some View {
        if let problem = store.environment.storageProblem ?? store.loadError {
            ScrollView { ProblemView(message: problem).padding(24) }
        } else if isSearching {
            searchResults
        } else if store.memories.isEmpty {
            if store.hasLoaded { emptyState } else { ProgressView() }
        } else {
            List {
                ForEach(store.memories) { record in
                    NavigationLink(value: record.id) { MemoryRow(record: record) }
                        .listRowBackground(Theme.canvas)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let searchError {
            ScrollView { ProblemView(message: searchError).padding(24) }
        } else {
            switch outcome {
            case .some(.matches(let candidates)):
                List {
                    Section {
                        ForEach(candidates, id: \.memoryID) { candidate in
                            NavigationLink(value: candidate.memoryID) {
                                MemoryRow(record: candidate.record, matchedTerms: candidate.matchedTerms)
                            }
                            .listRowBackground(Theme.canvas)
                        }
                    } header: {
                        Text(candidates.count == 1 ? "1 saved memory matches" : "\(candidates.count) saved memories match")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            case .some(.noMatch):
                VStack(spacing: 8) {
                    Text(RecallCopy.noMatch)
                        .font(.headline)
                        .accessibilityIdentifier("memories.noMatch")
                    Text("Search looks for the words in your notes. It doesn't guess.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            case .none:
                ProgressView()
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                CandidateCharacterView(assetName: "Doddy_memory_card", size: 150)
                Text("No memories yet")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Only what you choose to save appears here. Nothing is added automatically.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    showCapture = true
                } label: {
                    HStack { Text("Save a detail"); Spacer(); Image(systemName: "arrow.right") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!store.isStorageAvailable)
            }
            .padding(24)
            .accessibilityIdentifier("memories.empty")
        }
    }

    private func runSearch() async {
        let question = query
        guard !question.allSatisfy(\.isWhitespace) else {
            outcome = nil
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do {
            let result = try await store.recall(question)
            guard !Task.isCancelled else { return }
            outcome = result
            searchError = nil
        } catch {
            guard !Task.isCancelled else { return }
            outcome = nil
            searchError = UserFacingError.message(for: error)
        }
    }
}
