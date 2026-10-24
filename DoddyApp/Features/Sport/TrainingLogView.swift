import DoddyCore
import SwiftUI

/// Settings › Connections › Training log (sport plan stage 3, ADR-632). The person says yes to keeping
/// a log of their sessions on this iPhone, writes down sets, weight, reps, reps left and how it felt,
/// and gets one thing to change before the next session. The rules and the words come from DoddyCore
/// (`TrainingLogRepository`, `TrainingReview`); no model writes or changes anything here, and nothing
/// leaves the phone.
struct TrainingLogView: View {
    @State private var model = TrainingLogModel.shared
    @State private var adding = false
    @State private var confirmDeleteAll = false
    @State private var sessionToDelete: LoggedSession?

    /// Rows shown; older ones are in the export.
    private let shown = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text("Training log")
                        .font(.title2.bold())
                }

                keeping

                if model.consent.granted {
                    Button {
                        adding = true
                    } label: {
                        Label("Add a session", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("log.add")
                }

                if let text = model.reviewText(), model.consent.granted || !model.sessions.isEmpty {
                    PlanSection(title: Text("Before your next session")) {
                        Text(verbatim: text)
                            .accessibilityIdentifier("log.review")
                    }
                }

                if !model.sessions.isEmpty {
                    PlanSection(title: Text("Your sessions")) {
                        ForEach(model.sessions.prefix(shown)) { session in
                            TrainingLogRow(session: session) { sessionToDelete = session }
                        }
                        if model.sessions.count > shown {
                            Text("Older sessions are in the export file.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                if model.consent.granted || !model.sessions.isEmpty {
                    yourData
                }

                if let problem = model.problem {
                    ProblemView(message: problem)
                }

                PlanSafetyNote()

                PlanSection(title: Text("What stays here")) {
                    Text("The log stays on this iPhone, in its own file outside iCloud and backups. Nothing is sent to Doddy's server or to an AI. The notes' Delete all doesn't touch it; use Delete my training log below.")
                }
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.canvas)
        .navigationTitle("Training log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.discardExport() }
        .sheet(isPresented: $adding) {
            NavigationStack {
                LogSessionView(model: model) { adding = false }
            }
        }
        .confirmationDialog(
            "Delete this session?", isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = sessionToDelete?.id { Task { await model.delete(id) } }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("The session is removed from this iPhone. This can't be undone.")
        }
    }

    private var keeping: some View {
        PlanSection(title: Text("Keep a log")) {
            Text("Write down what you did: sets, weight, reps, how many more reps you could have done, and how it felt. Doddy then says what to change before the next session.")
            Toggle("Keep a training log on this iPhone", isOn: Binding(
                get: { model.consent.granted },
                set: { on in Task { await model.setKeeping(on) } }))
                .accessibilityIdentifier("log.keep")
            Text("Turning this off stops saving. What is already saved stays until you delete it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var yourData: some View {
        PlanSection(title: Text("Your data")) {
            VStack(alignment: .leading, spacing: 12) {
                if let url = model.exportURL {
                    ShareLink(item: url) {
                        Label("Share the export file", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("log.share")
                } else {
                    Button("Make an export file") { Task { await model.prepareExport() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("log.export")
                }
                Button("Delete my training log") { confirmDeleteAll = true }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
                    .accessibilityIdentifier("log.deleteAll")
                    .confirmationDialog("Delete the whole training log?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { Task { await model.deleteAll() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Every saved session is removed from this iPhone. This can't be undone. The switch above stays as it is.")
                    }
            }
        }
    }
}

extension TrainingFeeling {
    var label: Text {
        switch self {
        case .easy: Text("Easy")
        case .okay: Text("Okay")
        case .hard: Text("Hard")
        case .pain: Text("Pain")
        }
    }
}

private struct TrainingLogRow: View {
    let session: LoggedSession
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.performedAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.headline)
                HStack(spacing: 10) {
                    session.feeling.label
                    if let minutes = session.runMinutes {
                        Text(verbatim: String(format: NSLocalizedString("Run: %lld min", comment: ""), minutes))
                    }
                    if !session.sets.isEmpty {
                        Text(verbatim: String(format: NSLocalizedString("Sets: %lld", comment: ""), session.sets.count))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Delete this session")
        }
        .padding(.vertical, 4)
    }
}

/// One session to write down: the day, how it felt, and either the minutes of a run or the sets.
struct LogSessionView: View {
    let model: TrainingLogModel
    let done: () -> Void

    private enum Kind: Hashable { case strength, run }

    @State private var kind: Kind = .strength
    @State private var day = Date.now
    @State private var feeling: TrainingFeeling = .okay
    @State private var runMinutes = 30
    @State private var sets: [LoggedSet] = []
    @State private var exercise = LogSessionView.strengthCards.first?.id ?? "squat"
    @State private var reps = 10
    @State private var kilograms = ""
    @State private var reserve: Int? = 2
    @State private var problem: String?
    @State private var saving = false

    /// Every exercise the plan engine can prescribe; the two run cards have no sets.
    private static let strengthCards = ExerciseCatalogue.all.filter { $0.id != "run_walk" && $0.id != "easy_run" }

    init(model: TrainingLogModel, done: @escaping () -> Void) {
        self.model = model
        self.done = done
    }

    private var canSave: Bool { kind == .run || !sets.isEmpty }

    var body: some View {
        Form {
            Section {
                DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
                Picker("Kind", selection: $kind) {
                    Text("Strength").tag(Kind.strength)
                    Text("Run").tag(Kind.run)
                }
                .pickerStyle(.segmented)
                Picker("How it felt", selection: $feeling) {
                    ForEach(TrainingFeeling.allCases, id: \.self) { value in
                        value.label.tag(value)
                    }
                }
            } footer: {
                if feeling == .pain {
                    Text("Pain means pain, not just tiredness. While it is in your log from the last two weeks, Doddy raises nothing.")
                }
            }

            if kind == .run {
                Section {
                    Stepper(value: $runMinutes, in: 1...600) {
                        LabeledContent("Minutes") { Text("\(runMinutes)") }
                    }
                }
            } else {
                setEntry
                if !sets.isEmpty { addedSets }
            }

            if let problem {
                Section { ProblemView(message: problem) }
            }
        }
        .navigationTitle("Add a session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { done() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave || saving)
                    .accessibilityIdentifier("log.save")
            }
        }
    }

    private var isHold: Bool { TrainingReview.isTimedHold(exercise) }

    private var setEntry: some View {
        Section {
            Picker("Exercise", selection: $exercise) {
                ForEach(Self.strengthCards) { card in
                    Text(verbatim: card.name.text(.current)).tag(card.id)
                }
            }
            Stepper(value: $reps, in: 0...200) {
                LabeledContent {
                    Text("\(reps)")
                } label: {
                    if isHold { Text("Seconds") } else { Text("Reps") }
                }
            }
            TextField("Weight in kg (empty for bodyweight)", text: $kilograms)
                .keyboardType(.decimalPad)
            Picker("Reps left", selection: $reserve) {
                Text("Not sure").tag(Int?.none)
                ForEach(0...6, id: \.self) { count in
                    Text("\(count)").tag(Int?.some(count))
                }
            }
            Button("Add this set") { addSet() }
                .accessibilityIdentifier("log.addSet")
        } header: {
            Text("A set")
        } footer: {
            Text("Reps left is how many more you could have done. Without it Doddy raises nothing.")
        }
    }

    private var addedSets: some View {
        Section {
            ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                Text(verbatim: Self.describe(set, language: .current))
            }
            .onDelete { sets.remove(atOffsets: $0) }
        } header: {
            Text("Sets in this session")
        }
    }

    private func addSet() {
        let typed = kilograms.trimmingCharacters(in: .whitespaces)
        var load: Double?
        if !typed.isEmpty {
            guard let value = Double(typed.replacingOccurrences(of: ",", with: ".")) else {
                problem = NSLocalizedString("Weight must be a number, such as 12.5.", comment: "")
                return
            }
            load = value
        }
        do {
            sets.append(try LoggedSet(exerciseKey: exercise, reps: reps, loadKilograms: load, repsInReserve: reserve))
            problem = nil
        } catch {
            problem = TrainingLogModel.message(error)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let session: LoggedSession
            if kind == .run {
                session = try LoggedSession(performedAt: day, feeling: feeling, runMinutes: runMinutes)
            } else {
                session = try LoggedSession(performedAt: day, feeling: feeling, sets: sets)
            }
            if await model.record(session) {
                done()
            } else {
                problem = model.problem
            }
        } catch {
            problem = TrainingLogModel.message(error)
        }
    }

    /// "Goblet squat: 10 × 12.5 kg, 2 left".
    private static func describe(_ set: LoggedSet, language: NotificationLanguage) -> String {
        let name = ExerciseCatalogue.card(forKey: set.exerciseKey)?.name.text(language) ?? set.exerciseKey
        var line = "\(name): \(set.reps)"
        if TrainingReview.isTimedHold(set.exerciseKey) { line += " s" }
        if let kilograms = set.loadKilograms {
            line += " × " + kilograms.formatted(.number.precision(.fractionLength(0...2))) + " kg"
        }
        if let left = set.repsInReserve {
            line += ", " + String(format: NSLocalizedString("%lld left", comment: ""), left)
        }
        return line
    }
}

/// The Connections card that opens the training log.
struct TrainingLogCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.quietSurface, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Training log")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Sets, weight and how it felt, kept on this iPhone if you say yes")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your training log.")
    }
}
