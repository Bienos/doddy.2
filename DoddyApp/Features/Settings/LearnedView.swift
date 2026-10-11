import DoddyCore
import SwiftUI

/// Settings → What Doddy knows → What I've learned (ADR-440, docs/architecture/LEARNING_LOOP.md §7).
/// Every fact and routine Doddy kept, where it came from and until when; edit, delete or say
/// "That's wrong"; export; delete everything. Nothing here is sent anywhere. Rows are what the
/// repositories returned after a read-back.
struct LearnedView: View {
    let learning: LearningStore
    @AppStorage(PreferenceKey.learningOn) private var learningOn = false
    @AppStorage(PreferenceKey.shareLearnedWithVoice) private var shareWithVoice = false
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAll = false
    @State private var editing: EditTarget?
    @State private var editText = ""
    @State private var factToDelete: LearnedFact?
    @State private var procedureToDelete: Procedure?
    @State private var confirmDeleteAll = false
    @State private var deleteError: String?

    var body: some View {
        List {
            switches
            thisWeek
            pending
            reviewSection
            factsSection
            proceduresSection
            takenOff
            gaps
            exportAndDelete
            if let problem = learning.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .navigationTitle("What I've learned")
        .navigationBarTitleDisplayMode(.inline)
        .task { await learning.reload() }
        .sheet(item: $editing) { target in editor(for: target) }
        .confirmationDialog(
            "Delete this?", isPresented: Binding(get: { factToDelete != nil }, set: { if !$0 { factToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let fact = factToDelete { Task { await learning.delete(fact: fact) } }
                factToDelete = nil
            }
            Button("Cancel", role: .cancel) { factToDelete = nil }
        } message: {
            Text("It is removed from this iPhone and from what Doddy can use. This can't be undone.")
        }
        .confirmationDialog(
            "Delete this routine?", isPresented: Binding(get: { procedureToDelete != nil }, set: { if !$0 { procedureToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let procedure = procedureToDelete { Task { await learning.delete(procedure: procedure) } }
                procedureToDelete = nil
            }
            Button("Cancel", role: .cancel) { procedureToDelete = nil }
        } message: {
            Text("It is removed from this iPhone. Anything it already did stays as it is.")
        }
        .confirmationDialog("Delete everything Doddy learned?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task {
                    do { try await learning.deleteAll(); deleteError = nil }
                    catch { deleteError = UserFacingError.message(for: error) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every fact, routine and count of corrections from this iPhone. Your notes aren't touched. Exported files and older backups aren't affected.")
        }
    }

    // MARK: Sections

    private var switches: some View {
        Section {
            Toggle("Learn from how I use Doddy", isOn: $learningOn)
                .accessibilityIdentifier("learned.learningOn")
            Text("When this is on, Doddy may ask after a conversation whether to remember something you said about yourself, or a routine you repeat on three different days. Each card shows the exact words and nothing is saved unless you tap Save. It's worked out on this iPhone from your own words; never for private conversations, and never passwords, card numbers, or health, religion, politics or money details.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Toggle("Use what Doddy learned in voice conversations", isOn: $shareWithVoice)
                .accessibilityIdentifier("learned.shareWithVoice")
            if shareWithVoice {
                Text("The facts and routines you confirmed are handed to the voice service at the start of a conversation, like your notes. You can see this under Privacy, What leaves this iPhone.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            } else {
                Text("Nothing learned is shared. Doddy can't use it in a conversation until you turn this on.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if pauseAll {
                Label("Connections are paused, so no routine is handed over and Doddy asks nothing new.", systemImage: "pause.circle")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var thisWeek: some View {
        Section {
            StatusRow(title: "Corrections this week", value: "\(learning.metrics.correctionsThisWeek)")
            StatusRow(title: "Routines used this week", value: "\(learning.metrics.proceduresUsedThisWeek)")
        } header: {
            Text("This week")
        } footer: {
            Text("Doddy counts how often you undo something, change a step, say \"That's wrong\", ask for the same thing again or leave a card unanswered, so you can see whether he gets better. Only the kind of event and the tool name are kept, for 90 days, on this iPhone, never sent.")
        }
    }

    @ViewBuilder
    private var pending: some View {
        if !learning.pendingFacts.isEmpty || !learning.pendingProcedures.isEmpty {
            Section {
                ForEach(learning.pendingFacts) { fact in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "“\(fact.value)”")
                        HStack {
                            Button("Save") { Task { await learning.confirmPending(fact: fact) } }
                                .buttonStyle(.borderedProminent)
                            Button("Never this", role: .destructive) { Task { await learning.rejectPending(fact: fact) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                ForEach(learning.pendingProcedures) { procedure in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(procedure.triggerText).font(.body.weight(.semibold))
                        ForEach(procedure.steps, id: \.number) { step in
                            Text(Self.stepText(step)).font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        HStack {
                            Button("Save") { Task { await learning.confirmPending(procedure: procedure) } }
                                .buttonStyle(.borderedProminent)
                            Button("Never this", role: .destructive) { Task { await learning.rejectPending(procedure: procedure) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                Text("Waiting for your answer")
            } footer: {
                Text("Cards you tapped Not now on. They go away by themselves after 7 days.")
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if !learning.factsToReview.isEmpty {
            Section {
                ForEach(learning.factsToReview) { fact in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fact.value)
                        Text(Self.detail(fact)).font(.footnote).foregroundStyle(Theme.secondaryText)
                        HStack {
                            Button("Yes, still true") { Task { await learning.stillTrue(fact: fact) } }
                                .buttonStyle(.borderedProminent)
                            Button("That's wrong", role: .destructive) { Task { await learning.thatsWrong(fact: fact) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                Text("Still true?")
            } footer: {
                Text("Doddy doesn't use these until you say they are.")
            }
        }
    }

    private var factsSection: some View {
        Section {
            if learning.confirmedFacts.isEmpty {
                if learning.hasLoaded {
                    Text("Nothing yet. Doddy only keeps what you confirm.")
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("learned.factsEmpty")
                } else {
                    Text("Loading…").foregroundStyle(Theme.secondaryText)
                }
            }
            ForEach(learning.confirmedFacts) { fact in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fact.value)
                        Text(Self.detail(fact)).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Button("Edit") { editText = fact.value; editing = .fact(fact) }
                        Button("That's wrong") { Task { await learning.thatsWrong(fact: fact) } }
                        Button("Delete", role: .destructive) { factToDelete = fact }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More for this fact")
                }
                .accessibilityElement(children: .contain)
            }
        } header: {
            Text("What Doddy knows about you")
        } footer: {
            Text("\"That's wrong\" keeps it below, out of use, so you can see it. Delete removes it.")
        }
    }

    private var proceduresSection: some View {
        Section {
            if learning.confirmedProcedures.isEmpty {
                Text("None yet. After you do the same few things in the same order on three different days, Doddy may offer to save them.")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(learning.confirmedProcedures) { procedure in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(procedure.triggerText).font(.body.weight(.semibold))
                        ForEach(procedure.steps, id: \.number) { step in
                            Text(Self.stepText(step)).font(.footnote)
                        }
                        Text(Self.usage(procedure)).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Button("Rename") { editText = procedure.triggerText; editing = .routine(procedure) }
                        Button("That's wrong") { Task { await learning.thatsWrong(procedure: procedure) } }
                        Button("Delete", role: .destructive) { procedureToDelete = procedure }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More for this routine")
                }
                .accessibilityElement(children: .contain)
            }
        } header: {
            Text("Routines")
        } footer: {
            Text("In a conversation, ask for one by name and Doddy shows one card with these steps. Every step still needs your tap, every time. A routine you don't use for 90 days is taken off below.")
        }
    }

    @ViewBuilder
    private var takenOff: some View {
        if !learning.retiredFacts.isEmpty || !learning.retiredProcedures.isEmpty {
            Section {
                ForEach(learning.retiredFacts) { fact in
                    HStack {
                        Text(fact.value).foregroundStyle(Theme.secondaryText)
                        Spacer(minLength: 8)
                        Button("Delete", role: .destructive) { factToDelete = fact }.buttonStyle(.borderless)
                    }
                }
                ForEach(learning.retiredProcedures) { procedure in
                    HStack {
                        Text(procedure.triggerText).foregroundStyle(Theme.secondaryText)
                        Spacer(minLength: 8)
                        Button("Bring back") { Task { await learning.bringBack(procedure: procedure) } }.buttonStyle(.borderless)
                        Button("Delete", role: .destructive) { procedureToDelete = procedure }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Taken off")
            } footer: {
                Text("Kept so you can see them. Doddy doesn't use anything here.")
            }
        }
    }

    @ViewBuilder
    private var gaps: some View {
        if !learning.metrics.gaps.isEmpty {
            Section {
                ForEach(learning.metrics.gaps.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.rawValue < $1.key.rawValue) }, id: \.key) { gap in
                    StatusRow(title: gap.key.title, value: "\(gap.value)")
                }
            } header: {
                Text("Things I can't do yet")
            } footer: {
                Text("What you asked for that Doddy has no way to do, as a topic only. This stays on your iPhone.")
            }
        }
    }

    private var exportAndDelete: some View {
        Section {
            if let text = learning.exportText {
                ShareLink(item: text, preview: SharePreview("What Doddy learned (JSON)")) {
                    Label("Export as JSON", systemImage: "square.and.arrow.up")
                }
                .disabled(!learning.hasAnything)
            }
            Button("Delete everything Doddy learned", role: .destructive) { confirmDeleteAll = true }
                .disabled(!learning.hasAnything && learning.metrics == .empty)
                .accessibilityIdentifier("learned.deleteAll")
            if let deleteError {
                Label(deleteError, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
            }
        }
    }

    // MARK: Editor

    enum EditTarget: Identifiable {
        case fact(LearnedFact)
        case routine(Procedure)

        var id: UUID {
            switch self {
            case .fact(let fact): fact.id
            case .routine(let procedure): procedure.id
            }
        }
    }

    private func limit(for target: EditTarget) -> Int {
        switch target {
        case .fact: LearnedFact.maxValueLength
        case .routine: Procedure.maxTriggerLength
        }
    }

    private func editor(for target: EditTarget) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What Doddy knows", text: $editText, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("learned.editText")
                } footer: {
                    switch target {
                    case .fact:
                        Text("Saving replaces the words Doddy uses. Earlier wordings are kept in its history.")
                    case .routine:
                        Text("This is the name you say to ask for the routine. Its steps stay as they are.")
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let text = editText
                        editing = nil
                        switch target {
                        case .fact(let fact): Task { await learning.revise(fact: fact, to: text) }
                        case .routine(let procedure): Task { await learning.rename(procedure: procedure, to: text) }
                        }
                    }
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || editText.unicodeScalars.count > limit(for: target))
                }
            }
        }
    }

    // MARK: Text

    static func detail(_ fact: LearnedFact) -> String {
        var parts = [fact.kind.title]
        if let confirmed = fact.confirmedAt {
            parts.append(String(format: NSLocalizedString("confirmed %@", comment: "Learned fact detail"), DateText.full(confirmed)))
        }
        if let source = fact.provenance.episodeDates.first {
            parts.append(String(format: NSLocalizedString("from a conversation on %@", comment: "Learned fact detail"), source.formatted(date: .abbreviated, time: .omitted)))
        }
        if let expires = fact.expiresAt {
            parts.append(String(format: NSLocalizedString("until %@", comment: "Learned fact detail"), expires.formatted(date: .abbreviated, time: .omitted)))
        }
        return parts.joined(separator: " · ")
    }

    /// "1. Add a reminder (Doddy asks: title, due)", in the iPhone's language.
    static func stepText(_ step: ProcedureStep) -> String {
        let title = ProcedureStepTemplates.title(for: step.toolName, polish: NotificationLanguage.current == .polish)
        let name = title.prefix(1).uppercased() + title.dropFirst()
        var text = "\(step.number). \(name)"
        if !step.asked.isEmpty {
            text += " " + String(format: NSLocalizedString("(Doddy asks for: %@)", comment: "Routine step"), step.asked.map(askedLabel).joined(separator: ", "))
        }
        return text
    }

    private static func askedLabel(_ name: String) -> String {
        switch name {
        case "title": NSLocalizedString("the title", comment: "Routine detail Doddy asks")
        case "due": NSLocalizedString("the time", comment: "Routine detail Doddy asks")
        case "start": NSLocalizedString("the start", comment: "Routine detail Doddy asks")
        case "text": NSLocalizedString("the text", comment: "Routine detail Doddy asks")
        case "minutes": NSLocalizedString("the number of minutes", comment: "Routine detail Doddy asks")
        case "list": NSLocalizedString("the list", comment: "Routine detail Doddy asks")
        case "items": NSLocalizedString("the items", comment: "Routine detail Doddy asks")
        case "to": NSLocalizedString("the recipient", comment: "Routine detail Doddy asks")
        case "subject": NSLocalizedString("the subject", comment: "Routine detail Doddy asks")
        case "body": NSLocalizedString("the message", comment: "Routine detail Doddy asks")
        case "content": NSLocalizedString("the task", comment: "Routine detail Doddy asks")
        default: name
        }
    }

    static func usage(_ procedure: Procedure) -> String {
        guard procedure.useCount > 0, let last = procedure.lastUsedAt else { return NSLocalizedString("Not used yet", comment: "Routine usage") }
        let date = last.formatted(date: .abbreviated, time: .omitted)
        return procedure.useCount == 1
            ? String(format: NSLocalizedString("Used once, on %@", comment: "Routine usage"), date)
            : String(format: NSLocalizedString("Used %lld times, last on %@", comment: "Routine usage"), procedure.useCount, date)
    }
}

extension LearnedFactKind {
    var title: String {
        switch self {
        case .preference: NSLocalizedString("Preference", comment: "Kind of learned fact")
        case .fact: NSLocalizedString("Fact", comment: "Kind of learned fact")
        case .routine: NSLocalizedString("Routine", comment: "Kind of learned fact")
        case .person: NSLocalizedString("About a person", comment: "Kind of learned fact")
        case .place: NSLocalizedString("About a place", comment: "Kind of learned fact")
        }
    }
}

extension CapabilityGapCategory {
    var title: String {
        switch self {
        case .sendMessage: NSLocalizedString("Sending messages", comment: "Something Doddy can't do yet")
        case .payment: NSLocalizedString("Payments", comment: "Something Doddy can't do yet")
        case .music: NSLocalizedString("Music", comment: "Something Doddy can't do yet")
        case .smartHome: NSLocalizedString("Smart home", comment: "Something Doddy can't do yet")
        case .otherAppControl: NSLocalizedString("Controlling other apps", comment: "Something Doddy can't do yet")
        case .webAction: NSLocalizedString("Doing things on websites", comment: "Something Doddy can't do yet")
        case .unknown: NSLocalizedString("Something else", comment: "Something Doddy can't do yet")
        }
    }
}
