import DoddyCore
import SwiftUI

/// Settings › Connections › Training plan (sport mode step 4, ADR-625). Doddy's plan engine makes a
/// running or strength plan from a few answers, after the safety questions; the person can keep it on
/// this iPhone and see where they are in it. No model writes or changes a plan, and nothing here
/// leaves the phone.
struct TrainingPlanView: View {
    @State private var store = TrainingPlanStore.shared
    @State private var makingPlan = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "figure.run")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text("Training plan")
                        .font(.title2.bold())
                }

                switch store.state {
                case .nothingKept:
                    noPlan
                case .plan(let saved):
                    SavedPlanSection(saved: saved)
                    planActions
                case .notThisDoddysPlan:
                    Text("The kept plan isn't the one this version of Doddy makes for its answers, so it isn't shown. Delete it, or make a new plan.")
                    planActions
                case .unreadable:
                    Text("The kept plan couldn't be read. It is still on this iPhone; delete it, or make a new plan.")
                    planActions
                }

                if let problem = store.problem {
                    ProblemView(message: problem)
                }

                PlanSafetyNote()

                PlanSection(title: Text("What stays here")) {
                    Text("The plan, and the answers it was made from, stay on this iPhone, outside iCloud and backups. Nothing is sent to Doddy's server or to an AI.")
                }
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.canvas)
        .navigationTitle("Training plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.load() }
        .sheet(isPresented: $makingPlan) {
            NavigationStack {
                PlanQuestionsView(replaces: store.state != .nothingKept) { makingPlan = false }
            }
        }
    }

    private var noPlan: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A plan for a first 5 km, a 10 km, a half marathon, or strength at home or at the gym. Answer a few questions; Doddy works the plan out with fixed rules.")
            PlanSection(title: Text("How Doddy makes it")) {
                PlanBullet(Text("No run more than 10 percent longer than your longest in the four weeks before"))
                PlanBullet(Text("Most running easy, and never two hard days in a row"))
                PlanBullet(Text("Every fourth week lighter"))
                PlanBullet(Text("Strength sets stop with 2 to 3 reps left, never at failure"))
                Text("After research in the British Journal of Sports Medicine (2025), ACSM's 2026 guidance on strength training and WHO's 2020 guidelines.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                makingPlan = true
            } label: {
                Label("Make a plan", systemImage: "list.bullet.clipboard")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("plan.make")
        }
    }

    private var planActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Make a new plan") { makingPlan = true }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("plan.new")
            Button("Delete this plan") { confirmDelete = true }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
                .accessibilityIdentifier("plan.delete")
                .confirmationDialog("Delete this plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { store.delete() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The plan and its answers are removed from this iPhone. This can't be undone.")
                }
        }
    }
}

/// The kept plan: where today falls, today's session and every week.
private struct SavedPlanSection: View {
    let saved: SavedTrainingPlan

    var body: some View {
        let plan = saved.plan
        let position = PlanCalendar.position(of: plan, start: saved.start, now: .now, calendar: .current)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PlanText.goal(plan.request.goal))
                    .font(.title3.bold())
                Text(PlanText.position(position, plan: plan))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("plan.position")
            }
            if let short = PlanText.shortOfGoal(plan) {
                Text(short)
            }
            if case .inPlan(let number, let day) = position, plan.weeks.indices.contains(number - 1) {
                PlanSection(title: Text("Today")) {
                    if let session = plan.weeks[number - 1].sessions.first(where: { $0.day == day }) {
                        PlanSessionRow(session: session, showsDay: false, isGoalRun: number == plan.weeks.count && plan.reachesGoal)
                    } else {
                        Text("No training today. Rest is part of the plan.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            PlanWeeksList(plan: plan, current: Self.currentWeek(position))
        }
    }
}

private extension SavedPlanSection {
    static func currentWeek(_ position: PlanPosition) -> Int? {
        if case .inPlan(let week, _) = position { return week }
        return nil
    }
}

/// Every week of a plan; the current one (or the first) starts open.
struct PlanWeeksList: View {
    let plan: TrainingPlan
    let current: Int?

    var body: some View {
        PlanSection(title: Text("Week by week")) {
            ForEach(plan.weeks, id: \.number) { week in
                PlanWeekGroup(week: week, count: plan.weeks.count, reachesGoal: plan.reachesGoal,
                              isCurrent: week.number == current, startsOpen: week.number == (current ?? 1))
            }
        }
    }
}

private struct PlanWeekGroup: View {
    let week: PlanWeek
    let count: Int
    let reachesGoal: Bool
    let isCurrent: Bool
    @State private var isOpen: Bool

    init(week: PlanWeek, count: Int, reachesGoal: Bool, isCurrent: Bool, startsOpen: Bool) {
        self.week = week
        self.count = count
        self.reachesGoal = reachesGoal
        self.isCurrent = isCurrent
        _isOpen = State(initialValue: startsOpen)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 14) {
                if let note = PlanText.weekNote(week, reachesGoal: reachesGoal) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(week.sessions, id: \.day) { session in
                    PlanSessionRow(session: session, showsDay: true, isGoalRun: week.number == count && reachesGoal)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text(PlanText.week(week.number, of: count))
                    .font(.headline)
                if isCurrent {
                    Text("This week")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.quietSurface, in: Capsule())
                }
            }
        }
        .tint(Theme.ink)
        .padding(.vertical, 6)
        .accessibilityIdentifier("plan.week.\(week.number)")
    }
}

struct PlanSessionRow: View {
    let session: PlanSession
    let showsDay: Bool
    let isGoalRun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsDay {
                Text(verbatim: PlanText.day(session.day) + " · " + PlanText.title(session))
                    .font(.headline)
            } else {
                Text(PlanText.title(session))
                    .font(.headline)
            }
            Text(PlanText.detail(session, isGoalRun: isGoalRun))
                .foregroundStyle(Theme.secondaryText)
            ForEach(Array(session.exercises.enumerated()), id: \.offset) { _, exercise in
                PlanBullet(Text(PlanText.exercise(exercise)))
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Questions

/// The questions before any plan above light activity (research, safety rules 2 and 5), in Doddy's
/// own words after ACSM's 2015 screening logic. Each must be answered; nothing starts as "no".
enum PlanScreeningQuestion: CaseIterable, Identifiable {
    case condition, symptoms, doctor, pregnancy, injury

    var id: Self { self }

    /// For UI tests: `plan.question.<key>`.
    var key: String { String(describing: self) }

    var text: String {
        switch self {
        case .condition:
            NSLocalizedString("Has a doctor told you that you have a heart, lung, kidney or metabolic condition, such as diabetes?", comment: "Plan screening")
        case .symptoms:
            NSLocalizedString("Do you get chest pain, fainting, dizziness, unusual shortness of breath or a racing heart, at rest or with effort?", comment: "Plan screening")
        case .doctor:
            NSLocalizedString("Has a doctor told you to limit exercise?", comment: "Plan screening")
        case .pregnancy:
            NSLocalizedString("Are you pregnant, or did you give birth in the last 12 months?", comment: "Plan screening")
        case .injury:
            NSLocalizedString("Do you have an injury, or pain in a joint, muscle or bone, that training could make worse?", comment: "Plan screening")
        }
    }
}

struct PlanQuestionsView: View {
    /// A plan is kept already; keeping a new one replaces it.
    let replaces: Bool
    let onKept: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var goal: PlanGoal = .firstFiveK
    @State private var level: PlanLevel = .beginner
    @State private var days = 3
    @State private var minutes = 45
    @State private var knowsLongest = false
    @State private var longest = 30
    @State private var answers: [PlanScreeningQuestion: Bool] = [:]
    @State private var ageText = ""
    @State private var decision: PlanDecision?
    @FocusState private var ageFocused: Bool

    private var isDistance: Bool { goal == .tenK || goal == .halfMarathon }
    private var maxDays: Int { goal.isRunning ? 5 : 4 }

    private var age: Int? {
        guard let value = Int(ageText.trimmingCharacters(in: .whitespaces)), (5...120).contains(value) else { return nil }
        return value
    }

    private var isReady: Bool { answers.count == PlanScreeningQuestion.allCases.count && age != nil }

    var body: some View {
        Form {
            Section {
                Picker("Goal", selection: $goal) {
                    ForEach(PlanGoal.allCases, id: \.self) { goal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PlanText.goal(goal))
                            Text(PlanText.goalDetail(goal))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .tag(goal)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("plan.goal")
            } header: {
                Text("Your goal")
            }

            Section {
                Picker("How much you train now", selection: $level) {
                    ForEach(PlanLevel.allCases, id: \.self) { level in
                        Text(PlanText.level(level)).tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("How much you train now")
            }

            Section {
                Stepper(value: $days, in: 2...maxDays) {
                    Text(verbatim: String(format: NSLocalizedString("Days a week: %lld", comment: ""), days))
                }
                .accessibilityIdentifier("plan.days")
                Stepper(value: $minutes, in: 20...150, step: 5) {
                    Text(verbatim: String(format: NSLocalizedString("Minutes a session: %lld", comment: ""), minutes))
                }
                .accessibilityIdentifier("plan.minutes")
            } header: {
                Text("Your week")
            } footer: {
                if goal.isRunning {
                    Text("The long run, on the weekend, can be longer.")
                }
            }

            if isDistance {
                Section {
                    Toggle("I know my longest run of the last 30 days", isOn: $knowsLongest)
                    if knowsLongest {
                        Stepper(value: $longest, in: 10...240, step: 5) {
                            Text(verbatim: String(format: NSLocalizedString("Longest run: %lld min", comment: ""), longest))
                        }
                    }
                } footer: {
                    Text("If you don't know it, Doddy starts from 30 minutes, or 45 if you train most weeks.")
                }
            }

            Section {
                ForEach(PlanScreeningQuestion.allCases) { question in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question.text)
                        Picker(question.text, selection: answer(question)) {
                            Text("No").tag(Bool?.some(false))
                            Text("Yes").tag(Bool?.some(true))
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("plan.question.\(question.key)")
                    }
                    .padding(.vertical, 4)
                }
                TextField("Your age", text: $ageText)
                    .keyboardType(.numberPad)
                    .focused($ageFocused)
                    .accessibilityIdentifier("plan.age")
            } header: {
                Text("Before a plan")
            } footer: {
                Text("Any yes means no plan from Doddy, and Doddy says who to ask instead. Only your age is kept, with the plan.")
            }

            Section {
                Button("Make the plan") { decision = PlanEngine.make(request) }
                    .disabled(!isReady)
                    .accessibilityIdentifier("plan.questions.make")
            }
        }
        .navigationTitle("New plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            // The number pad has no return key: this closes it, so the button below can be reached.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { ageFocused = false }.accessibilityIdentifier("plan.age.done")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: goal) { _, _ in days = min(days, maxDays) }
        .navigationDestination(isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } })) {
            if let decision {
                PlanResultView(decision: decision, replaces: replaces, onKept: onKept)
            }
        }
    }

    private func answer(_ question: PlanScreeningQuestion) -> Binding<Bool?> {
        Binding(get: { answers[question] }, set: { answers[question] = $0 })
    }

    private var request: PlanRequest {
        // An unanswered question counts as yes; the button needs every answer anyway.
        PlanRequest(goal: goal, level: level, daysPerWeek: days, minutesPerSession: minutes,
                    longestRecentRunMinutes: isDistance && knowsLongest ? longest : nil,
                    screening: PlanScreening(knownCondition: answers[.condition] ?? true, symptoms: answers[.symptoms] ?? true,
                                             doctorAdvisedLimits: answers[.doctor] ?? true,
                                             pregnantOrRecentlyGaveBirth: answers[.pregnancy] ?? true,
                                             injuryOrPain: answers[.injury] ?? true, age: age ?? 0))
    }
}

/// The engine's answer: a plan to keep, or why not and who to ask.
struct PlanResultView: View {
    let decision: PlanDecision
    let replaces: Bool
    let onKept: () -> Void

    @State private var store = TrainingPlanStore.shared
    @State private var startsThisWeek = PlanCalendar.weekday(of: .now, calendar: .current) == 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch decision {
                case .refused(let refusal):
                    Image(systemName: "hand.raised")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text(PlanText.refusalTitle(refusal))
                        .font(.title2.bold())
                        .accessibilityIdentifier("plan.refusal")
                    Text(PlanText.refusalText(refusal))
                    PlanSafetyNote()
                case .plan(let plan):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PlanText.goal(plan.request.goal))
                            .font(.title2.bold())
                        Text(PlanText.summary(plan))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let short = PlanText.shortOfGoal(plan) {
                        Text(short)
                            .accessibilityIdentifier("plan.shortOfGoal")
                    }
                    Picker("Start", selection: $startsThisWeek) {
                        Text("This week").tag(true)
                        Text("Next Monday").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if replaces {
                        Text("Keeping this plan replaces the one you have.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Button {
                        let start = PlanStart.monday(of: .now, weeksLater: startsThisWeek ? 0 : 1, calendar: .current)
                        if store.keep(plan, start: start) { onKept() }
                    } label: {
                        Label("Keep this plan on this iPhone", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("plan.keep")
                    if let problem = store.problem {
                        ProblemView(message: problem)
                    }
                    PlanWeeksList(plan: plan, current: nil)
                    PlanSafetyNote()
                }
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.canvas)
        .navigationTitle("Your plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Shared pieces

/// Safety rules 1 and 10: an AI, not medical advice, and when to stop. Fixed text; no model writes it.
struct PlanSafetyNote: View {
    var body: some View {
        PlanSection(title: Text("Safety")) {
            Text("Doddy is an AI, not a doctor or a coach, and this plan isn't medical advice. Stop at once if you get pain in your chest, neck, jaw or arm, feel faint or dizzy, are unusually short of breath, or your heart races. In an emergency call 112.")
        }
    }
}

struct PlanSection<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlanBullet: View {
    let line: Text

    init(_ line: Text) {
        self.line = line
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Theme.orangeCue)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            line
        }
    }
}

/// The Connections card that opens the training plan.
struct TrainingPlanCard: View {
    @State private var store = TrainingPlanStore.shared

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.quietSurface, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Training plan")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if let saved = store.saved {
                    Text(PlanText.position(PlanCalendar.position(of: saved.plan, start: saved.start, now: .now, calendar: .current), plan: saved.plan))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Running and strength plans, kept on this iPhone")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your training plan.")
    }
}
