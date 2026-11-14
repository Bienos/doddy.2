import DoddyCore
import SwiftUI

// Tasks handed to Doddy (ADR-570): the list, and one task's result card. Everything shown comes
// from the store on this iPhone or from the server's answer; a task still working is never shown
// as done, and a link on the card is one the server's run actually saw.
//
// Since 10 Nov 2026 (owner: "lepszy design … w jego kolorach, w jego brandingu, żeby to było łatwiejsze
// do zrozumienia, co można tutaj zrobić, jak z tego korzystać"; decision 2026-11-10-tasks-redesign) the
// screen is drawn like "Cheapest this week": Doddy with one line on what Tasks are, the tasks as cards with
// their state in words, a box to type a new task with examples of what the background worker does, and
// "How it works" in three steps. A typed task is the same request as one handed over by voice: a card shows
// exactly the words, Doddy's note and the title that go to Doddy's server, and only a tap on it starts it.

struct ErrandsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    private let model = ErrandsModel.shared
    @State private var opened: UUID?
    /// The new task being typed.
    @State private var words = ""
    /// The draft the yes card asks about. Set only when it passed the checks here and nothing is paused.
    @State private var asking: TypedAsk?
    /// What the last typed hand-over came to, or why it couldn't be asked.
    @State private var note: HandOverNote?
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.isServerConfigured {
                        Label("Doddy's server isn't set up in this build, so tasks can't run yet.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .tasksCard()
                    }
                    if let message = model.message {
                        Label(message, systemImage: "info.circle")
                            .tasksCard()
                            .accessibilityIdentifier("errands.message")
                    }
                    if let problem = model.loadProblem {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                            Button("Try again") { Task { await model.load() } }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                        .tasksCard()
                    }
                    // Someone with tasks sees them first; someone without sees how to hand one over first.
                    if !model.errands.isEmpty { tasksList }
                    newTaskCard
                    howItWorks
                    if model.errands.isEmpty && model.hasLoaded && model.loadProblem == nil { emptyList }
                    openLoopsLink
                    // Prices Doddy watches for the user (SHOPPING_WATCH.md): nothing here until there is one.
                    WatchesSection()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .readableColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $opened) { id in ErrandDetailView(id: id) }
            .sheet(item: $asking) { ask in
                TypedHandOverSheet(draft: ask.draft) { outcome in finished(outcome) }
            }
            .refreshable {
                await model.refresh()
                await WatchModel.shared.refresh()
            }
            .task {
                await model.load()
                await model.refresh()
                await WatchModel.shared.refresh()
            }
        }
    }

    // MARK: What Tasks are

    /// Doddy reaching up (on the island the pose that waits for the user's yes), and in one line what this screen is for.
    private var hero: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                  : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        return layout {
            WholeDoddyView(pose: .reachingHigh, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                Text("Hand me something to sort out")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("I search the web and read pages in the background, then leave the answer here. I never book, buy or send anything.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: The tasks

    private var tasksList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your tasks").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(model.errands.enumerated()), id: \.element.id) { index, errand in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    Button { opened = errand.id } label: {
                        ErrandCardRow(errand: errand, isNew: model.unseenFinished.contains(errand.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("errands.row")
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        }
    }

    /// No task yet: said plainly, under the ways to hand one over (a failed read never shows as this).
    private var emptyList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your tasks").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text("No tasks yet.").font(.subheadline.weight(.semibold))
            Text("What you hand over shows up here, with what Doddy is doing about it.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .tasksCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("errands.empty")
    }

    // MARK: A new task

    private var newTaskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New task").font(.headline).accessibilityAddTraits(.isHeader)
            TextField("New task", text: $words, prompt: Text("What should Doddy sort out?"), axis: .vertical)
                .lineLimit(2...6)
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.canvas))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                .onChange(of: words) { _, new in if !new.isEmpty { note = nil } }
                .accessibilityIdentifier("errands.newTask")
            if words.utf16.count > ErrandDraft.maxWords - 200 {
                Text(verbatim: "\(words.utf16.count) / \(ErrandDraft.maxWords)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(words.utf16.count > ErrandDraft.maxWords ? Theme.error : Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel(Text(String(format: NSLocalizedString("%lld of %lld characters", comment: "the new task's length"),
                                                    words.utf16.count, ErrandDraft.maxWords)))
            }
            if words.isEmpty { examples }
            Button {
                typing = false
                ask()
            } label: {
                Label("Hand it to Doddy", systemImage: "paperplane.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.isServerConfigured || model.isHandingOver)
            .accessibilityIdentifier("errands.handOver")
            if let note {
                Label(note.text, systemImage: note.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(note.kind.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("errands.handOverNote")
            }
            Text("Or tell Doddy in a conversation: “Sort this out in the background: …”. For shopping, like “find me a quiet dishwasher”, talking works best: Doddy first asks what matters most to you.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tasksCard()
    }

    /// What the background worker does (web search and reading pages: comparisons, places, steps),
    /// in the reader's language. A tap puts the example in the box; nothing is sent until the card's yes.
    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("For example:").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ForEach(Self.exampleTasks, id: \.self) { example in
                Button {
                    words = example
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "text.quote").foregroundStyle(Theme.orangeCue).accessibilityHidden(true)
                        Text(verbatim: example).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Puts this example in the box. Nothing is sent yet."))
                .accessibilityIdentifier("errands.example")
            }
        }
    }

    private static var exampleTasks: [String] {
        [
            NSLocalizedString("Compare flights to Rome for a week next month, under 2000 zł", comment: "an example task"),
            NSLocalizedString("Find three quiet cafés in Kraków's Old Town that open before 8", comment: "an example task"),
            NSLocalizedString("What do I need to renew my ID card? Step by step", comment: "an example task"),
        ]
    }

    /// Checks here first (the server checks again): no link, not too long, Connections not paused.
    /// Only then does the card ask; nothing has been sent at this point.
    private func ask() {
        let language = ErrandDraft.typedLanguage(Bundle.main.preferredLocalizations.first ?? "en")
        let draft = ErrandDraft.typed(words, language: language)
        if let issue = draft.validationIssues().first {
            note = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
            return
        }
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) {
            note = HandOverNote(text: ErrandText.paused, kind: .problem)
            return
        }
        note = nil
        asking = TypedAsk(draft: draft)
    }

    /// The card closed with an answer. "Started" only when the server said it has the task.
    private func finished(_ outcome: ErrandsModel.HandOverOutcome) {
        switch outcome {
        case .started:
            words = ""
            note = HandOverNote(text: NSLocalizedString("Doddy has it. It's in Your tasks, and the result waits there and in Messages when it's done.", comment: ""), kind: .confirmed)
        case .maybeStarted:
            note = HandOverNote(text: NSLocalizedString("Doddy couldn't confirm it started. It may be running: pull down to check before you hand it over again.", comment: ""), kind: .unsure)
        case .notStarted(let error):
            note = HandOverNote(text: ErrandText.notStarted(error), kind: .problem)
        case .invalid(let issue):
            note = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
        case .paused:
            note = HandOverNote(text: ErrandText.paused, kind: .problem)
        case .alreadySending:
            note = nil
        }
    }

    // MARK: How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.headline).accessibilityAddTraits(.isHeader)
            step(1, title: NSLocalizedString("Say what you need", comment: "how tasks work, step 1"),
                 detail: NSLocalizedString("Type it above or tell Doddy in a conversation. Dates, a budget and a place help.", comment: "how tasks work, step 1"))
            step(2, title: NSLocalizedString("Tap yes once", comment: "how tasks work, step 2"),
                 detail: NSLocalizedString("You see exactly what goes to Doddy's server. One tap lets Doddy search the web and read pages in the background, as often as this task needs.", comment: "how tasks work, step 2"))
            step(3, title: NSLocalizedString("Get the answer", comment: "how tasks work, step 3"),
                 detail: NSLocalizedString("When it's done, it waits here and in Messages, with links to the pages Doddy read. Nothing is booked, bought or sent.", comment: "how tasks work, step 3"))
            Text("Open a task to see its result, stop it while it runs, or delete it.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .tasksCard()
        .accessibilityIdentifier("errands.howItWorks")
    }

    private func step(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Theme.inkOnOrange)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.orangeCue))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                Text(verbatim: detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: String(format: NSLocalizedString("Step %lld: %@. %@", comment: "how tasks work, read aloud"), number, title, detail)))
    }

    // MARK: Elsewhere

    /// Everything Doddy holds for the user in one list (ADR-756). Here, not in Home's menu: that menu
    /// fits eleven rows and a twelfth pushed two rows out of reach (the hosted UI tests caught it).
    private var openLoopsLink: some View {
        NavigationLink {
            OpenLoopsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "scope").font(.title3).foregroundStyle(Theme.accentText).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: OpenLoopsText.screenTitle(NotificationLanguage.preferred(Bundle.main.preferredLocalizations)))
                        .font(.subheadline.weight(.semibold))
                    Text("Reminders, events, tasks and watched prices in one list.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .tasksCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("errands.openLoops")
    }
}

/// The draft the yes card asks about.
struct TypedAsk: Identifiable {
    let id = UUID()
    let draft: ErrandDraft
}

/// One line under the hand-over button: its outcome in words, with an icon (never colour alone).
struct HandOverNote: Equatable {
    enum Kind: Equatable {
        case confirmed, unsure, problem

        var symbol: String {
            switch self {
            case .confirmed: "checkmark.circle.fill"
            case .unsure: "questionmark.circle"
            case .problem: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .confirmed: Theme.confirmed
            case .unsure: Theme.ink
            case .problem: Theme.error
            }
        }
    }

    let text: String
    let kind: Kind
}

/// One task in the list: its state in words, its title, the user's words and the day.
struct ErrandCardRow: View {
    let errand: StoredErrand
    let isNew: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ErrandStateChip(errand: errand)
                    if isNew {
                        Text("New result")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.inkOnOrange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.orangeCue))
                    }
                }
                Text(verbatim: errand.title).font(.headline).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(verbatim: String(format: NSLocalizedString("“%@”", comment: ""), errand.draft.words))
                    .font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: DateText.full(errand.createdAt)).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A task's state as a word with an icon, tinted; the word carries the meaning, never the colour.
struct ErrandStateChip: View {
    let errand: StoredErrand

    var body: some View {
        Label {
            Text(verbatim: ErrandText.state(errand))
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch errand.state {
        case .draft, .queued: "clock"
        case .running: "magnifyingglass"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "stop.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch errand.state {
        case .done: Theme.confirmed
        case .failed: Theme.error
        case .draft, .queued, .running: Theme.accentText
        case .cancelled, .unknown: Theme.secondaryText
        }
    }
}

// MARK: - The yes card for a typed task

/// Shows exactly what goes to Doddy's server (the words, Doddy's note and the title, which the
/// approval's digest covers) and what one tap allows. Only "Yes, go" sends anything.
struct TypedHandOverSheet: View {
    let draft: ErrandDraft
    let done: @MainActor (ErrandsModel.HandOverOutcome) -> Void
    @Environment(\.dismiss) private var dismiss
    private let model = ErrandsModel.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .bottom, spacing: 12) {
                        WholeDoddyView(pose: .reachingHigh, height: 88)
                        Text("Hand this to Doddy?")
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        field(NSLocalizedString("Your words", comment: "the typed task's card"), draft.words)
                            .accessibilityIdentifier("errands.ask.words")
                        field(NSLocalizedString("Title in Tasks", comment: "the typed task's card"), draft.title)
                        field(NSLocalizedString("Doddy's note", comment: ""), draft.brief)
                        Text("The same for every typed task: Doddy writes no note of its own.")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                        // "Find me this" from the Shopping screen: the order is part of what the yes covers.
                        if draft.kind == .shopping {
                            field(NSLocalizedString("What matters most, in order", comment: "the typed shopping task's card"), prioritiesText)
                                .accessibilityIdentifier("errands.ask.priorities")
                        }
                    }
                    .tasksCard()
                    VStack(alignment: .leading, spacing: 8) {
                        if draft.kind == .shopping {
                            Label("Doddy looks for offers in shops in Poland in the background and reads each shop's own page. A price he couldn't confirm there isn't shown. The result waits in Shopping, in Tasks and in Messages.", systemImage: "magnifyingglass")
                            Label("Nothing is booked, bought or sent.", systemImage: "hand.raised")
                            Label("All of this goes to Doddy's server; the words, the note and what matters most also go to Anthropic, whose Claude does the research. Search phrases Claude writes from them go to Google Shopping through Serper, and Doddy's server opens shops' pages. The server deletes its copy once this iPhone has saved the result.", systemImage: "lock")
                        } else {
                            Label("Doddy searches the web and reads pages in the background, as often as this needs. The result waits in Tasks and in Messages.", systemImage: "magnifyingglass")
                            Label("Nothing is booked, bought or sent.", systemImage: "hand.raised")
                            Label("All three go to Doddy's server; the words and the note also go to Anthropic, whose Claude does the research. The server deletes its copy once this iPhone has saved the result.", systemImage: "lock")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        Button {
                            Task {
                                let outcome = await model.handOverTyped(draft)
                                done(outcome)
                                dismiss()
                            }
                        } label: {
                            if model.isHandingOver {
                                HStack(spacing: 10) {
                                    ProgressView().tint(Theme.canvas)
                                    Text("Handing it over…")
                                }
                            } else {
                                Text("Yes, go")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.isHandingOver)
                        .accessibilityIdentifier("errands.ask.yes")
                        Button("Not now") { dismiss() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(model.isHandingOver)
                            .accessibilityIdentifier("errands.ask.no")
                    }
                }
                .padding(16)
                .readableColumn()
            }
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(model.isHandingOver)
        .presentationDetents([.large])
    }

    /// The priorities as they are sent, numbered in their order, or that none was chosen.
    private var prioritiesText: String {
        draft.priorities.isEmpty
            ? NSLocalizedString("Nothing chosen", comment: "no shopping priorities")
            : draft.priorities.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " · ")
    }

    /// Each text in full, never cut: the approval covers all of it.
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            Text(verbatim: String(format: NSLocalizedString("“%@”", comment: ""), value))
                .font(.body).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One task

struct ErrandDetailView: View {
    let id: UUID
    private let model = ErrandsModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let errand = model.errand(id) {
                content(errand)
            } else {
                VStack(spacing: 12) {
                    WholeDoddyView(pose: .shrug, height: 120)
                    Text("This task isn't on this iPhone any more.")
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
            }
        }
        .navigationTitle(model.errand(id)?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.markSeen(id) }
    }

    // A Form still, so a shopping task's sections (ShoppingResultSections) sit in it as they are;
    // drawn on Doddy's paper with his surface colour, and a header with Doddy and the state.
    @ViewBuilder
    private func content(_ errand: StoredErrand) -> some View {
        Form {
            Section {
                header(errand)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            Group {
                status(errand)
                if let result = errand.result {
                    if let shopping = result.shopping {
                        // A shopping task (SHOPPING.md): the picks, their prices and the report.
                        ShoppingResultSections(errand: errand, result: result, shopping: shopping)
                    } else {
                        resultSections(result)
                    }
                }
                Section("You said") {
                    Text(verbatim: String(format: NSLocalizedString("“%@”", comment: ""), errand.draft.words)).foregroundStyle(Theme.ink).textSelection(.enabled)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Doddy's note").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        Text(verbatim: errand.draft.brief).foregroundStyle(Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !errand.deletions.isEmpty {
                    Section {
                        Label("Saved on this iPhone. Doddy's server deleted its copy of the words and the result.", systemImage: "lock")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                Section {
                    if errand.state.isOpen {
                        Button { Task { await model.cancel(errand.id) } } label: {
                            Label("Stop this task", systemImage: "stop.circle")
                        }
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("errand.cancel")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("errand.delete")
                }
                if let message = model.message {
                    Section { Label(message, systemImage: "info.circle") }
                }
            }
            .listRowBackground(Theme.quietSurface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .refreshable { await model.refresh() }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { if await model.delete(errand.id) { dismiss() } }
            }
        } message: {
            Text("It's deleted from this iPhone and, if it's still there, from Doddy's server.")
        }
    }

    /// Doddy in the pose for the state (busy, done, facepalm on a failure), the state in words and the title.
    private func header(_ errand: StoredErrand) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            WholeDoddyView(pose: Self.pose(errand.state), height: 96)
            VStack(alignment: .leading, spacing: 6) {
                ErrandStateChip(errand: errand)
                    .accessibilityIdentifier("errand.state")
                Text(verbatim: errand.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: DateText.full(errand.createdAt))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    /// What the state means for the user, in words. Never "done" for a task still working.
    @ViewBuilder
    private func status(_ errand: StoredErrand) -> some View {
        if errand.state == .failed, let failure = errand.failure {
            Section {
                Text(failure.explanation).foregroundStyle(Theme.ink)
            }
        } else if errand.state == .unknown {
            Section {
                Text("Doddy couldn't confirm this task started. Pull down to check again; it isn't sent again by itself.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        } else if errand.state.isOpen || errand.state == .draft {
            Section {
                Text("You can close the app. When it's done, the result waits here and in Messages.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    static func pose(_ state: ErrandState) -> IslandPose {
        switch state {
        case .draft, .queued, .running: .kneelingInspect
        case .done: .fistpump
        case .failed: .facepalm
        case .cancelled: .crosslegged
        case .unknown: .shrug
        }
    }

    @ViewBuilder
    private func resultSections(_ result: ErrandResult) -> some View {
        Section {
            Text(result.answer).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).textSelection(.enabled)
            if let recommendation = result.recommendation, !recommendation.isEmpty {
                Text(recommendation).foregroundStyle(Theme.ink)
            }
            if let budget = result.budget {
                LabeledContent(String(format: NSLocalizedString("Budget: %@", comment: ""), "\u{201C}\(budget.asked)\u{201D}"),
                               value: ErrandText.budget(budget.within))
            }
            if let checked = result.checkedDate {
                Text(String(format: NSLocalizedString("Checked %@. Prices and availability can change.", comment: ""), DateText.full(checked)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in
            Section(section.heading) {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    ErrandItemRow(item: item, checklist: section.kind == .checklist)
                }
            }
        }
        if !result.next.isEmpty {
            Section("What next") {
                ForEach(result.next, id: \.self) { line in
                    Label(line, systemImage: "arrow.turn.down.right").foregroundStyle(Theme.ink)
                }
                Text("Ask Doddy in a conversation to do any of these.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        if !result.sources.isEmpty {
            Section("Sources") {
                ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                    if let url = URL(string: source.url), url.scheme == "https" || url.scheme == "http" {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title).foregroundStyle(Theme.ink)
                                Text(source.site ?? url.host() ?? "").font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ErrandItemRow: View {
    let item: ErrandResult.Item
    let checklist: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                if checklist { Image(systemName: "circle").foregroundStyle(Theme.secondaryText) }
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let price = item.price { Text(price).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink) }
            }
            if let when = item.when { Text(when).font(.footnote).foregroundStyle(Theme.ink) }
            if let detail = item.detail { Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText) }
            if let link = item.url.flatMap({ URL(string: $0) }), link.scheme == "https" || link.scheme == "http" {
                Link(item.site ?? link.host() ?? link.absoluteString, destination: link).font(.footnote)
            } else if let site = item.site {
                Text(site).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Parts

extension View {
    /// A card on the Tasks screen, as on "Cheapest this week": Doddy's quiet surface, 20-pt corners
    /// and a hairline edge.
    func tasksCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }
}

/// Words for a task's state and budget, in the app's languages.
enum ErrandText {
    static func state(_ errand: StoredErrand) -> String {
        switch errand.state {
        case .draft, .queued: NSLocalizedString("Waiting to start", comment: "")
        case .running: NSLocalizedString("Doddy is working on it", comment: "")
        case .done: NSLocalizedString("Done", comment: "")
        case .failed: NSLocalizedString("Couldn't finish", comment: "")
        case .cancelled: NSLocalizedString("Stopped", comment: "")
        case .unknown: NSLocalizedString("Not confirmed", comment: "")
        }
    }

    static func budget(_ fit: ErrandResult.BudgetFit) -> String {
        switch fit {
        case .yes: NSLocalizedString("fits", comment: "")
        case .no: NSLocalizedString("goes over", comment: "")
        default: NSLocalizedString("not sure", comment: "")
        }
    }

    /// Why a typed task can't be asked about yet. Nothing was sent.
    static func issue(_ issue: ErrandDraftIssue) -> String {
        switch issue {
        case .containsLink:
            NSLocalizedString("Take the link out: Doddy finds the pages itself. A site's name on its own, like allegro.pl, is fine.", comment: "")
        case .wordsTooLong:
            NSLocalizedString("That's more than Doddy's server takes (1,000 characters). Make it shorter.", comment: "")
        default:
            NSLocalizedString("Write what Doddy should sort out first.", comment: "")
        }
    }

    static var paused: String {
        NSLocalizedString("Connections are paused, so nothing goes to Doddy's server. Turn them back on in Settings, Connections.", comment: "")
    }

    /// Why a typed task didn't start, from the server's answer. Nothing started in any of these.
    @MainActor
    static func notStarted(_ error: any Error) -> String {
        switch error {
        case ErrandError.tooManyOpenErrands:
            NSLocalizedString("You already have as many open tasks as Doddy's server allows. Wait for one to finish, or stop one. Nothing started.", comment: "")
        case ErrandError.dailyLimit(let forEveryone):
            forEveryone
                ? NSLocalizedString("Doddy's server has taken as many tasks today as it allows for everyone. Try again tomorrow. Nothing started.", comment: "")
                : NSLocalizedString("You've handed over as many tasks today as Doddy's server allows. Try again tomorrow. Nothing started.", comment: "")
        case ErrandError.digestMismatch, ErrandError.notApprovable:
            NSLocalizedString("The request expired or changed before it was approved. Nothing started; you can hand it over again.", comment: "")
        case ErrandError.previewMismatch:
            NSLocalizedString("Doddy's server didn't hold exactly these words, so nothing was approved or started.", comment: "")
        case ErrandError.invalid(_):
            NSLocalizedString("Doddy's server didn't accept this task, so nothing started. If it has a link in it, take the link out.", comment: "")
        default:
            ErrandsModel.describe(error)
        }
    }
}
