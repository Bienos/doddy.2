import DoddyCore
import Observation
import SwiftUI

/// What Today and the morning brief (ADR-230) read: the same switches, permissions and pause.
@MainActor
enum TodayReading {
    static func read(_ devices: DeviceConnections, now: Date, calendar: Calendar) async -> BriefSource {
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) { return .paused }
        func isOn(_ connection: VoiceConnection) -> Bool {
            UserDefaults.standard.bool(forKey: connection.preferenceKey) && devices.access(for: connection) == .granted
        }
        let calendarOn = isOn(.calendar), remindersOn = isOn(.reminders)
        guard calendarOn || remindersOn else { return .notConnected }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let events = calendarOn ? devices.events(in: VoiceTimeRange(start: start, end: end)) : []
        let reminders = remindersOn ? await devices.remindersDue(by: end, calendar: calendar) : []
        return .agenda(
            TodayAgenda(events: events, reminders: reminders, now: now, calendar: calendar),
            calendarRead: calendarOn, remindersRead: remindersOn)
    }
}

/// Home → Today: the rest of today from the user's Calendar and Reminders on this iPhone, with
/// optional "before this event" nudges. Read only when the matching switch in Settings →
/// Connections is on and iOS allows it. Nothing here is sent anywhere.
@MainActor
@Observable
final class TodayModel {
    enum Content: Equatable {
        case loading
        /// Calendar and Reminders are both off (or blocked by iOS).
        case notConnected
        /// Settings → Pause all is on: nothing is read.
        case paused
        case agenda(TodayAgenda)
    }

    private let devices = DeviceConnections()
    private(set) var content: Content = .loading
    private(set) var nudges: [ScheduledNudge] = []
    /// The last nudge result: a receipt read back from iOS, or what went wrong.
    private(set) var notice: String?

    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        switch await TodayReading.read(devices, now: now, calendar: calendar) {
        case .paused:
            content = .paused
        case .notConnected:
            content = .notConnected
        case .agenda(let agenda, _, _):
            content = .agenda(agenda)
            nudges = await devices.pendingNudges()
        }
    }

    /// The nudge set for this event, if any.
    func nudge(for event: CalendarEventSummary) -> ScheduledNudge? {
        nudges.first { $0.eventID == event.id && $0.eventID != nil }
    }

    func setNudge(for event: CalendarEventSummary, leadMinutes: Int) async {
        let plan: EventNudgePlan
        do {
            plan = try EventNudgePlan(event: event, leadMinutes: leadMinutes, now: .now)
        } catch {
            notice = "That time has already passed, so no nudge was set."
            return
        }
        var access = await devices.notificationAccess()
        if access == .notDetermined { access = await devices.request(.timers) }
        guard access == .granted else {
            notice = "Notifications are off for Doddy. Turn them on in iPhone Settings, Notifications, Doddy."
            return
        }
        // Setting a different lead time replaces the earlier nudge for this event.
        if let old = nudge(for: event), old.id != plan.identifier { _ = await devices.cancelNudge(id: old.id) }
        do {
            let time = event.start.formatted(date: .omitted, time: .shortened)
            switch try await devices.scheduleNudge(plan, time: time) {
            case .verified:
                notice = "Nudge set for \(plan.fireAt.formatted(date: .omitted, time: .shortened)): \(event.title)."
            case .unconfirmed:
                notice = "iOS took the nudge but didn't confirm it. Check before relying on it."
            }
        } catch {
            notice = "The nudge wasn't set. \(error.localizedDescription)"
        }
        nudges = await devices.pendingNudges()
    }

    func cancel(_ nudge: ScheduledNudge, title: String) async {
        notice = await devices.cancelNudge(id: nudge.id)
            ? "Nudge removed: \(title)."
            : "iOS still lists that nudge. Try again."
        nudges = await devices.pendingNudges()
    }
}

struct TodayCard: View {
    /// Opens Settings, where Connections is.
    let openSettings: () -> Void

    @State private var model = TodayModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            switch model.content {
            case .loading:
                ProgressView()
            case .notConnected:
                Text("See today's events and reminders here: turn on Calendar or Reminders in Settings, Connections. They're read on this iPhone only.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button("Open Settings", action: openSettings)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("today.openSettings")
            case .paused:
                Text("Connections are paused, so Doddy isn't reading your calendar or reminders. Turn them back on in Settings, Connections.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button("Open Settings", action: openSettings)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("today.openSettings.paused")
            case .agenda(let agenda):
                agendaView(agenda)
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("today.notice")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        // A container keeps its own identifier only as an element; otherwise SwiftUI copies it onto
        // every child and the Open Settings button would lose `today.openSettings`.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.today")
    }

    @ViewBuilder
    private func agendaView(_ agenda: TodayAgenda) -> some View {
        if agenda.isEmpty {
            Text("Nothing left on your calendar or reminders today.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        ForEach(agenda.events, id: \.rowID) { event in
            eventRow(event)
        }
        if agenda.moreEvents > 0 {
            Text("And \(agenda.moreEvents) more in Calendar.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        ForEach(agenda.reminders) { reminder in
            reminderRow(reminder)
        }
        if agenda.moreReminders > 0 {
            Text("And \(agenda.moreReminders) more in Reminders.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func eventRow(_ event: CalendarEventSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                if let nudge = model.nudge(for: event) {
                    Text(nudgeText(nudge, event: event))
                        .font(.footnote)
                        .foregroundStyle(nudge.fits(event) == false ? Theme.error : Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if !event.allDay, event.start > .now {
                nudgeMenu(event)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func nudgeText(_ nudge: ScheduledNudge, event: CalendarEventSummary) -> String {
        let time = nudge.fireAt?.formatted(date: .omitted, time: .shortened) ?? "?"
        return nudge.fits(event) == false
            ? "Nudge at \(time), the old time: the event moved. Set it again."
            : "Nudge at \(time)"
    }

    private func nudgeMenu(_ event: CalendarEventSummary) -> some View {
        Menu {
            ForEach(EventNudgePlan.leadMinuteOptions, id: \.self) { minutes in
                Button(minutes == 60 ? "1 hour before" : "\(minutes) minutes before") {
                    Task { await model.setNudge(for: event, leadMinutes: minutes) }
                }
            }
            if let nudge = model.nudge(for: event) {
                Button("Remove nudge", role: .destructive) {
                    Task { await model.cancel(nudge, title: event.title) }
                }
            }
        } label: {
            Image(systemName: model.nudge(for: event) == nil ? "bell" : "bell.fill")
                .accessibilityLabel("Nudge before \(event.title)")
        }
        .accessibilityIdentifier("today.nudge")
    }

    private func reminderRow(_ reminder: ReminderSummary) -> some View {
        let overdue = TodayAgenda.isOverdue(reminder, now: .now, calendar: .current)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "circle")
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                if overdue {
                    Text("Overdue").font(.footnote).foregroundStyle(Theme.error)
                } else if reminder.dueHasTime, let due = reminder.due {
                    Text("Due \(due.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension CalendarEventSummary {
    /// Events from the device always have an id; the fallback keeps ForEach stable regardless.
    var rowID: String { id ?? "\(title)@\(start.timeIntervalSince1970)" }
}
