import DoddyCore
import SwiftUI

struct FindMemoriesView: View {
    @Environment(MemoryStore.self) private var store
    @State private var query: String
    @State private var outcome: RecallOutcome?
    @State private var searchError: String?
    @State private var isRunning = false
    /// Close in meaning (ADR-227): notes the word search didn't find.
    @State private var meaningHits: [MeaningHit] = []
    @FocusState private var focused: Bool

    /// `initialQuery` comes from the "Find in Doddy" shortcut; the search runs on appear.
    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

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
                    ProblemView(message: problem, showsDoddy: true)
                } else if isRunning {
                    ProgressView("Finding saved words")
                } else {
                    // Lists (ADR-216) are found by their name or items, apart from the notes.
                    let listHits = ListSearch.hits(query, in: store.lists)
                    if !listHits.isEmpty {
                        ListHitsView(hits: listHits)
                    }
                    RecallResultsView(outcome: outcome, query: query, foundElsewhere: !listHits.isEmpty || !meaningHits.isEmpty)
                    if !meaningHits.isEmpty {
                        MeaningHitsView(hits: meaningHits)
                    }
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
        meaningHits = []
        searchError = nil
        guard !question.allSatisfy(\.isWhitespace) else { isRunning = false; return }
        isRunning = true
        do {
            try await Task.sleep(for: .milliseconds(250))
            let result = try await store.recall(question)
            guard !Task.isCancelled else { return }
            outcome = result
            isRunning = false
            // Then, without holding up the word results: notes close in meaning, on this iPhone.
            var found: Set<UUID> = []
            if case .matches(let candidates) = result { found = Set(candidates.map(\.memoryID)) }
            let hits = await MeaningService.index.search(question, in: store.memories, excluding: found)
            guard !Task.isCancelled else { return }
            meaningHits = hits
        } catch is CancellationError {
            // The newer task owns the spinner and results; don't publish stale state.
        } catch {
            guard !Task.isCancelled else { return }
            isRunning = false
            searchError = UserFacingError.message(for: error)
        }
    }
}

/// "Close in meaning" (ADR-227): saved notes the word search missed, worded as a suggestion.
private struct MeaningHitsView: View {
    let hits: [MeaningHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLOSE IN MEANING")
                .font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
            Text("Not the same words. Check it's the one you meant.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            ForEach(hits) { hit in
                NavigationLink(value: MemoryNavigationRoute.note(hit.record.id)) {
                    Group {
                        // A private note's words only after Face ID (ADR-310).
                        if PrivateNotesStore.current().contains(hit.record.id) && !AppLock.shared.privateUnlocked {
                            Label("Private note", systemImage: "lock.fill").foregroundStyle(Theme.secondaryText)
                        } else {
                            Text(hit.record.currentText).lineLimit(3)
                        }
                    }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("memories.meaningHits")
    }
}

/// "In your lists": each list with the items that matched; tapping opens the list.
private struct ListHitsView: View {
    let hits: [ListSearchHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hits.count == 1 ? "IN ONE LIST" : "IN \(hits.count) LISTS")
                .font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
            ForEach(hits) { hit in
                NavigationLink(value: MemoryNavigationRoute.note(hit.list.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(hit.list.name, systemImage: "checklist").font(.headline)
                            Spacer()
                            Text(hit.list.summary).font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(hit.items) { item in
                            Label(item.text, systemImage: item.isDone ? "checkmark.square" : "square")
                                .font(.subheadline)
                                .foregroundStyle(item.isDone ? Theme.secondaryText : Theme.ink)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the list")
            }
        }
        .accessibilityIdentifier("memories.listHits")
    }
}

private struct RecallResultsView: View {
    let outcome: RecallOutcome?
    let query: String
    /// Lists or notes close in meaning are shown with these results (review F10).
    var foundElsewhere = false
    /// Narrows the matches to one note type (ADR-199). Ignored once no match has that type.
    @State private var category: MemoryCategory?
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch outcome {
            case .some(.matches(let candidates)):
                // When no note covers the whole question, say which words no note has instead of
                // presenting these as the answer (ADR-251). The notes stay listed.
                let coverage = RecallCoverage(question: query, candidates: candidates)
                let kind = coverage.isPartial ? "PARTIAL" : "POSSIBLE"
                Text(candidates.count == 1 ? "ONE \(kind) MATCH" : "\(candidates.count) \(kind) MATCHES")
                    .font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
                if coverage.isPartial {
                    let copy = RecallCopy.partial(coverage)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.headline).font(.subheadline.weight(.semibold))
                        Text(copy.detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("memories.partialMatch")
                }
                // Types among these matches. The "may disagree" check below always looks at every
                // match, so the banner counts them all; if the filter hides some of those notes,
                // the banner says how many (ADR-199).
                let choices = MemoryFilter.choices(candidates.map(\.record))
                let active = choices.contains { $0.category == category } ? category : nil
                let shown = active.map { type in candidates.filter { $0.record.category == type } } ?? candidates
                let mayDisagree = RecallConflicts.flagged(candidates)
                if !mayDisagree.isEmpty {
                    let hiddenDisagreeing = mayDisagree.subtracting(shown.map(\.memoryID)).count
                    Label("\(mayDisagree.count) of these give different numbers for the same thing. Check which one is current; nothing was changed.\(hiddenDisagreeing > 0 ? " \(hiddenDisagreeing) of them \(hiddenDisagreeing == 1 ? "is" : "are") hidden by the filter." : "")", systemImage: "exclamationmark.2")
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("memories.mayDisagree")
                }
                if !choices.isEmpty {
                    MemoryTypeFilterRow(choices: choices, total: candidates.count, selection: $category, active: active)
                    if let active {
                        Text("Showing \(shown.count) of \(candidates.count) matches: \(active.displayName) only.")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("memories.findFilterNote")
                    }
                }
                LazyVStack(spacing: 12) {
                    ForEach(shown, id: \.memoryID) { candidate in
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
            case .some(.noMatch) where foundElsewhere:
                // Not "I haven't found that" next to lists or notes that were found (review F10).
                Text("No note has those words.").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("memories.noMatch")
            case .some(.noMatch):
                // Open hands: nothing to show, and nothing made up (ADR-299). With the motion world
                // on (MV3, Q4) the one Doddy comes out and shrugs here himself, at 1.0× (111 pt), on
                // a spot the picture's size (at accessibility sizes a box just his height).
                if DoddyDirector.shared.isActive {
                    let height: CGFloat = textSize.isAccessibilitySize ? 114 : 170
                    Color.clear.frame(width: 122, height: height)
                        .overlay(alignment: .bottom) {
                            Color.clear.frame(width: 96, height: 1).motionSurface(.ledge(MotionHost.findLedge))
                        }
                        .frame(maxWidth: .infinity)
                } else {
                    WholeDoddyView(pose: .shrug, height: 170).frame(maxWidth: .infinity)
                }
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
        // A type chosen for one search is not carried into the next one.
        .onChange(of: query) { category = nil }
    }
}
