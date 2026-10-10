import DoddyCore
import SwiftUI

struct FindMemoriesView: View {
    @Environment(MemoryStore.self) private var store
    @State private var query = ""
    @State private var outcome: RecallOutcome?
    @State private var searchError: String?
    @State private var isRunning = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                JourneyHeading(eyebrow: "A little help finding it", title: "What was\nthat thing?",
                               subtitle: "Start with a word you remember.")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search saved notes").font(.subheadline)
                    HStack {
                        TextField("Try a word from your note", text: $query)
                            .textFieldStyle(.plain).submitLabel(.search).focused($focused)
                            .accessibilityIdentifier("memories.query")
                            .onSubmit { focused = false }
                        Button { focused = false } label: { Image(systemName: "arrow.right").frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss keyboard and view matches")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator, lineWidth: 1))
                }
                if let problem = store.environment.storageProblem ?? store.loadError ?? searchError {
                    ProblemView(message: problem)
                } else if isRunning {
                    ProgressView("Finding saved words")
                } else {
                    RecallResultsView(outcome: outcome, query: query)
                }
            }.padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas).foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { DoddyWordmark() } }
        .task(id: "\(query)|\(store.revision)") { await runSearch() }
    }

    private func runSearch() async {
        let question = query
        outcome = nil
        searchError = nil
        guard !question.allSatisfy(\.isWhitespace) else { isRunning = false; return }
        isRunning = true
        do {
            try await Task.sleep(for: .milliseconds(250))
            let result = try await store.recall(question)
            guard !Task.isCancelled else { return }
            outcome = result
            isRunning = false
        } catch is CancellationError {
            // The newer task owns the spinner and results; don't publish stale state.
        } catch {
            guard !Task.isCancelled else { return }
            isRunning = false
            searchError = UserFacingError.message(for: error)
        }
    }
}

private struct RecallResultsView: View {
    let outcome: RecallOutcome?
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch outcome {
            case .some(.matches(let candidates)):
                Text(candidates.count == 1 ? "ONE POSSIBLE MATCH" : "\(candidates.count) POSSIBLE MATCHES")
                    .font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
                let mayDisagree = RecallConflicts.flagged(candidates)
                if !mayDisagree.isEmpty {
                    Label("\(mayDisagree.count) of these give different numbers for the same thing. Check which one is current; nothing was changed.", systemImage: "exclamationmark.2")
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("memories.mayDisagree")
                }
                LazyVStack(spacing: 12) {
                    ForEach(candidates, id: \.memoryID) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            if mayDisagree.contains(candidate.memoryID) {
                                Label("May disagree with another note", systemImage: "exclamationmark.2")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accentText)
                            }
                            MemoryLinkCard(record: candidate.record, matchedTerms: candidate.matchedTerms)
                        }
                    }
                }
                Label("Always linked to your original note.", systemImage: "book.closed")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            case .some(.noMatch):
                UploadedCharacterView(assetName: "UploadedDoddy_Inspect", height: 170).frame(maxWidth: .infinity)
                JourneyHeading(eyebrow: "No match in your saved notes", title: "I haven't\nfound that.",
                               subtitle: "I won't fill in the gaps. Try a distinctive word from the note.")
                Text(RecallCopy.noMatch).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("memories.noMatch")
                Text(query).font(.subheadline).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
            case .none:
                UploadedCharacterView(assetName: "UploadedDoddy_Inspect", height: 100).frame(maxWidth: .infinity)
                Text("Nothing guessed. Just what you kept.").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
