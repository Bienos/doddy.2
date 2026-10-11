import DoddyCore
import SwiftUI

/// Settings → What Doddy did. Newest first, grouped by day. Each row says what was asked and
/// what actually happened; a reminder Doddy wasn't sure about can be checked in Reminders.
/// The steps of one plan card are shown together under one heading (ADR-208). For a day, an
/// event or reminder Doddy added or changed can be undone, after a confirmation (ADR-268).
struct ActivityView: View {
    @Environment(MemoryStore.self) private var store
    @State private var activity = ActivityLogStore.shared
    @State private var devices = DeviceConnections()
    @State private var checking: Set<UUID> = []
    @State private var checkProblem: String?
    @State private var confirmClear = false
    @State private var undoing: Set<UUID> = []
    /// The entry whose Undo sheet is showing.
    @State private var confirmUndo: ActivityEntry?

    private var days: [(day: Date, items: [ActivityItem])] {
        let calendar = Calendar.current
        let items = ActivityItem.items(activity.entries)
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.at) }
        // Dictionary(grouping:) keeps each day's items in the newest-first order given.
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Text("Everything Doddy looked up or did for you in voice conversations, kept on this iPhone for \(ActivityLog.keepDays) days.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if let problem = activity.problem ?? checkProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                }
            }
            if activity.entries.isEmpty {
                Section {
                    HStack(spacing: 14) {
                        // Nothing yet: he waits, cross-legged (ADR-313).
                        WholeDoddyView(pose: .crosslegged, height: 80)
                        Text("Nothing yet. When Doddy looks something up or adds something for you, it shows here.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            ForEach(days, id: \.day) { group in
                Section(Self.dayTitle(group.day)) {
                    ForEach(group.items) { item in
                        switch item {
                        case .single(let entry):
                            row(entry)
                        case .plan(_, let steps):
                            planRow(steps)
                        }
                    }
                }
            }
            if !activity.entries.isEmpty {
                Section {
                    Button("Clear this list", role: .destructive) { confirmClear = true }
                        .accessibilityIdentifier("activity.clear")
                } footer: {
                    Text("Clearing removes this list only. Reminders, events and notes Doddy added stay where they are.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("What Doddy did")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear this list?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { activity.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears Doddy's list only. Nothing in Reminders, Calendar or your notes changes.")
        }
        .confirmationDialog(
            confirmUndo?.undo?.question(.current) ?? "",
            isPresented: Binding(get: { confirmUndo != nil }, set: { if !$0 { confirmUndo = nil } }),
            titleVisibility: .visible,
            presenting: confirmUndo
        ) { entry in
            Button(entry.undo?.buttonTitle(.current) ?? NSLocalizedString("Undo", comment: ""), role: .destructive) {
                Task { await undo(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(entry.undo?.explanation(calendar: .current, language: .current) ?? "")
        }
    }

    private func row(_ entry: ActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title(.current)).font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Text(entry.at, style: .time)
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            if let detail = entry.detail {
                Text(detail).font(.subheadline)
            }
            HStack(spacing: 6) {
                // Undone (ADR-313): Doddy turned back, frame 3 of the pack's turn strip.
                if case .undone? = entry.undoState { DoddyMotionView(motion: .turn, height: 28) }
                Text(entry.statusText(.current))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(entry.undoState == nil ? color(entry.outcome) : Theme.secondaryText)
            }
            if let note = entry.note(.current) {
                Text(note).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if entry.canCheckInReminders {
                Button(checking.contains(entry.id) ? "Checking…" : "Check in Reminders") {
                    Task { await check(entry) }
                }
                .buttonStyle(.borderless)
                .disabled(checking.contains(entry.id))
                .accessibilityHint("Looks in Reminders for this reminder. Nothing is added.")
            }
            if entry.canUndo(now: Date()) {
                Button(undoing.contains(entry.id) ? NSLocalizedString("Undoing…", comment: "") : NSLocalizedString("Undo", comment: "")) { confirmUndo = entry }
                    .buttonStyle(.borderless)
                    .disabled(undoing.contains(entry.id))
                    .accessibilityIdentifier("activity.undo")
                    .accessibilityHint("Asks first. Puts back only what Doddy did, if it hasn't changed since.")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// One plan card: a heading with what happened overall, then each step as its own row.
    private func planRow(_ steps: [ActivityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(ActivityPlanSummary.title(steps, language: .current), systemImage: "list.number")
                    .font(.body.weight(.semibold))
                Text(ActivityPlanSummary.outcomes(steps, language: .current))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            ForEach(steps) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(entry.plan?.step ?? 0).")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                    row(entry)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("activity.plan")
    }

    private func check(_ entry: ActivityEntry) async {
        guard let key = entry.reminderKey else { return }
        checking.insert(entry.id)
        defer { checking.remove(entry.id) }
        guard let found = await devices.reminderIsThere(key: key) else {
            checkProblem = "Doddy couldn't read Reminders, so it can't check. If Reminders access is off, turn it on in Settings, Connections."
            return
        }
        checkProblem = nil
        activity.replace(ActivityLog.checked(entry, found: found, at: Date()))
    }

    /// Checked again at the tap: Pause all and the connection's switch, then the guarded write
    /// and read-back in DeviceConnections. The row then says what actually happened.
    private func undo(_ entry: ActivityEntry) async {
        guard let undo = entry.undo, entry.canUndo(now: Date()), !undoing.contains(entry.id) else { return }
        undoing.insert(entry.id)
        defer { undoing.remove(entry.id) }
        let defaults = UserDefaults.standard
        let result: UndoResult
        if let reason = undo.blocked(
            pauseAll: defaults.bool(forKey: ConnectionPause.preferenceKey),
            connectionOn: undo.connection.map { defaults.bool(forKey: $0.preferenceKey) } ?? true) {
            result = .notDone(reason)
        } else if undo.listID != nil {
            // Lists are Doddy's own (ADR-276): the store reverses and reads them back.
            result = await store.undoFromActivity(undo)
        } else {
            result = await devices.undo(undo)
        }
        // The entry as it is now, in case it changed while Undo ran.
        let current = activity.entries.first { $0.id == entry.id } ?? entry
        activity.replace(ActivityLog.undid(current, result: result, at: Date()))
    }

    private func color(_ outcome: ActivityOutcome) -> Color {
        switch outcome {
        case .done, .alreadyThere: Theme.confirmed
        case .notDone: Theme.error
        case .notSure: Theme.accentText
        case .lookedUp, .opened, .declined, .inProgress: Theme.secondaryText
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return NSLocalizedString("Today", comment: "") }
        if calendar.isDateInYesterday(day) { return NSLocalizedString("Yesterday", comment: "") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
