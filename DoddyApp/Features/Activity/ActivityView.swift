import DoddyCore
import SwiftUI

/// Settings → What Doddy did. Newest first, grouped by day. Each row says what was asked and
/// what actually happened; a reminder Doddy wasn't sure about can be checked in Reminders.
/// The steps of one plan card are shown together under one heading (ADR-208).
struct ActivityView: View {
    @State private var activity = ActivityLogStore.shared
    @State private var devices = DeviceConnections()
    @State private var checking: Set<UUID> = []
    @State private var checkProblem: String?
    @State private var confirmClear = false

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
                    Text("Nothing yet. When Doddy looks something up or adds something for you, it shows here.")
                        .foregroundStyle(Theme.secondaryText)
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
    }

    private func row(_ entry: ActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Text(entry.at, style: .time)
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            if let detail = entry.detail {
                Text(detail).font(.subheadline)
            }
            Text("\(entry.app.title) · \(entry.outcome.text)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color(entry.outcome))
            if let note = entry.note {
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
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// One plan card: a heading with what happened overall, then each step as its own row.
    private func planRow(_ steps: [ActivityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(ActivityPlanSummary.title(steps), systemImage: "list.number")
                    .font(.body.weight(.semibold))
                Text(ActivityPlanSummary.outcomes(steps))
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
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
