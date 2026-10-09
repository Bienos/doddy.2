import DoddyCore
import SwiftUI

/// Home: today's events and due reminders, read from this iPhone. Shown only when connected;
/// otherwise a link to Connections. A bell next to an event schedules a local nudge.
struct TodayCard: View {
    @Environment(ConnectionsStore.self) private var connections
    @State private var nudgeTarget: CalendarEvent?
    @State private var notice: Notice?

    private struct Notice: Equatable {
        let text: String
        let isError: Bool
    }

    private var calendarState: ConnectionState { connections.state(.calendar) }
    private var remindersState: ConnectionState { connections.state(.reminders) }

    private var upcomingEvents: [CalendarEvent] {
        let now = Date()
        return connections.todayEvents.filter { $0.isAllDay || $0.end > now }
    }

    var body: some View {
        if calendarState.canRead || remindersState.canRead {
            card
        } else if connections.isAvailable(.calendar) {
            NavigationLink {
                ConnectionsView()
            } label: {
                HStack {
                    Image(systemName: "calendar").accessibilityHidden(true)
                    Text("Connect Calendar to see your day here")
                    Spacer()
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("home.connect")
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            if calendarState.canRead {
                if upcomingEvents.isEmpty {
                    Text("Nothing else in your calendar today.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(upcomingEvents.prefix(5)) { event in
                        eventRow(event)
                    }
                    if upcomingEvents.count > 5 {
                        Text("and \(upcomingEvents.count - 5) more")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            if remindersState.canRead, !connections.todayReminders.isEmpty {
                Divider()
                Text("Reminders due")
                    .font(.subheadline.bold())
                ForEach(connections.todayReminders.prefix(4)) { reminder in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "circle").font(.footnote).accessibilityHidden(true)
                        Text(reminder.title)
                        Spacer(minLength: 8)
                        Text(dueText(reminder))
                            .font(.footnote)
                            .foregroundStyle(isOverdue(reminder) ? Theme.error : Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if let notice {
                Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle" : "bell.fill")
                    .font(.footnote)
                    .foregroundStyle(notice.isError ? Theme.error : Theme.confirmed)
                    .accessibilityIdentifier("today.notice")
            }
            if let problem = connections.todayProblem {
                ProblemView(message: problem)
            }

            Text("From Calendar and Reminders on this iPhone.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("home.today")
        .confirmationDialog(
            "Nudge me before \(nudgeTarget?.title ?? "this event")",
            isPresented: Binding(get: { nudgeTarget != nil }, set: { if !$0 { nudgeTarget = nil } }),
            titleVisibility: .visible,
            presenting: nudgeTarget
        ) { event in
            ForEach(EventNudgePlan.leadMinuteOptions, id: \.self) { minutes in
                if event.start.addingTimeInterval(-Double(minutes) * 60) > Date() {
                    Button(Self.leadLabel(minutes)) { Task { await schedule(event, minutes) } }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Doddy asks iOS to show a notification on this iPhone. Nothing is sent anywhere.")
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        let nudge = connections.nudges(for: event).first
        return HStack(alignment: .top, spacing: 12) {
            Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text([event.location, event.calendarTitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if let nudge, let fireAt = nudge.fireAt {
                    Text(nudge.matches(event) == false
                         ? "Nudge at old time \(fireAt.formatted(date: .omitted, time: .shortened)). Set it again."
                         : "Nudge at \(fireAt.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(nudge.matches(event) == false ? Theme.error : Theme.accentText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if !event.isAllDay, connections.nudgesAvailable, event.start > Date() {
                Button {
                    notice = nil
                    nudgeTarget = event
                } label: {
                    Image(systemName: nudge == nil ? "bell" : "bell.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(nudge == nil ? "Nudge me before \(event.title)" : "Change nudge for \(event.title)")
            }
        }
    }

    private func schedule(_ event: CalendarEvent, _ minutes: Int) async {
        do {
            let nudge = try await connections.scheduleNudge(for: event, leadMinutes: minutes)
            let time = nudge.fireAt?.formatted(date: .omitted, time: .shortened) ?? "the chosen time"
            notice = Notice(text: "Nudge set for \(time). Scheduled on this iPhone.", isError: false)
        } catch {
            notice = Notice(text: ConnectionsCopy.message(for: error), isError: true)
        }
    }

    private func dueText(_ reminder: ReminderItem) -> String {
        guard let due = reminder.due else { return "" }
        if isOverdue(reminder) { return "Overdue" }
        return reminder.dueIncludesTime ? due.formatted(date: .omitted, time: .shortened) : "Today"
    }

    private func isOverdue(_ reminder: ReminderItem) -> Bool {
        guard let due = reminder.due else { return false }
        return reminder.dueIncludesTime ? due < Date() : due < Calendar.current.startOfDay(for: Date())
    }

    static func leadLabel(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) hour\(minutes == 60 ? "" : "s") before" : "\(minutes) minutes before"
    }
}
