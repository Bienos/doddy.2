import DoddyCore
import Foundation
import Observation

/// Home → Today: the rest of today and the start of tomorrow from the user's Calendar and Reminders
/// on this iPhone (decision 2026-11-10-today-at-a-glance), with optional "before this event" nudges and
/// a tick to complete a reminder. Read only when the matching switch in Settings → Connections is on
/// and iOS allows it. Nothing here is sent anywhere; the next event's place goes to Apple Maps only
/// when the person taps Open in Maps.
@MainActor
@Observable
final class TodayModel {
    enum Content: Equatable {
        case loading
        /// Calendar and Reminders are both off (or blocked by iOS).
        case notConnected
        /// Settings → Pause all is on: nothing is read.
        case paused
        case glance(TodayGlance)
    }

    private let devices = DeviceConnections()
    private(set) var content: Content = .loading
    private(set) var nudges: [ScheduledNudge] = []
    /// The last nudge result: a receipt read back from iOS, or what went wrong.
    private(set) var notice: String?
    /// The last tick or Undo result: read back from Reminders, or what went wrong.
    private(set) var reminderNotice: String?
    /// The reminder just ticked off and read back as done, while Undo is offered.
    private(set) var undoable: ReminderSnapshot?
    /// Reminders being written now; their tick waits.
    private(set) var busyReminders: Set<String> = []
    /// The next event's location as Calendar has it, read on this iPhone for this screen only.
    private(set) var nextLocation: String?

    private var paused: Bool { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) }

    private func isOn(_ connection: VoiceConnection) -> Bool {
        UserDefaults.standard.bool(forKey: connection.preferenceKey) && devices.access(for: connection) == .granted
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        if paused {
            content = .paused
            nextLocation = nil
            return
        }
        let calendarOn = isOn(.calendar), remindersOn = isOn(.reminders)
        guard calendarOn || remindersOn else {
            content = .notConnected
            nextLocation = nil
            return
        }
        // Today and tomorrow in one read each; `TodayGlance` sorts out what goes where.
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? now
        let events = calendarOn ? await devices.readEvents(in: VoiceTimeRange(start: start, end: end)) : []
        let reminders = remindersOn ? await devices.remindersDue(by: end, calendar: calendar) : []
        let glance = TodayGlance(
            events: events, reminders: reminders, now: now, calendar: calendar, calendarOn: calendarOn, remindersOn: remindersOn)
        nextLocation = glance.nextUp
            .flatMap { devices.eventLocation($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        content = .glance(glance)
        nudges = await devices.pendingNudges()
    }

    // MARK: Nudges

    /// The nudge set for this event, if any.
    func nudge(for event: CalendarEventSummary) -> ScheduledNudge? {
        nudges.first { $0.eventID == event.id && $0.eventID != nil }
    }

    func setNudge(for event: CalendarEventSummary, leadMinutes: Int) async {
        let plan: EventNudgePlan
        do {
            plan = try EventNudgePlan(event: event, leadMinutes: leadMinutes, now: .now)
        } catch {
            notice = NSLocalizedString("That time has already passed, so no nudge was set.", comment: "")
            return
        }
        var access = await devices.notificationAccess()
        if access == .notDetermined { access = await devices.request(.timers) }
        guard access == .granted else {
            notice = NSLocalizedString("Notifications are off for Doddy. Turn them on in iPhone Settings, Notifications, Doddy.", comment: "")
            return
        }
        // Setting a different lead time replaces the earlier nudge for this event, but only once
        // the new one is confirmed: a failure keeps the old nudge rather than leaving none (DOD-08).
        let existing = nudge(for: event)
        let old: ScheduledNudge? = existing?.id == plan.identifier ? nil : existing
        do {
            let time = event.start.formatted(date: .omitted, time: .shortened)
            switch try await devices.scheduleNudge(plan, time: time) {
            case .verified:
                if let old { _ = await devices.cancelNudge(id: old.id) }
                notice = "Nudge set for \(plan.fireAt.formatted(date: .omitted, time: .shortened)): \(event.title)."
            case .unconfirmed:
                notice = old == nil
                    ? "iOS took the nudge but didn't confirm it. Check before relying on it."
                    : "iOS took the new nudge but didn't confirm it, so the earlier one was kept too. Check before relying on it."
            }
        } catch {
            notice = old == nil
                ? "The nudge wasn't set. \(error.localizedDescription)"
                : "The new nudge wasn't set; the earlier one is still on. \(error.localizedDescription)"
        }
        nudges = await devices.pendingNudges()
    }

    func cancel(_ nudge: ScheduledNudge, title: String) async {
        notice = await devices.cancelNudge(id: nudge.id)
            ? "Nudge removed: \(title)."
            : "iOS still lists that nudge. Try again."
        nudges = await devices.pendingNudges()
    }

    // MARK: Ticking off a reminder

    /// Ticks off exactly the reminder the row showed: Reminders is read again first and nothing is
    /// written unless it is still open with the same title and due (`ReminderTick`). It says "ticked
    /// off" only once Reminders reads it back as done (`changeReminder`, ADR-229; DOD-08); anything
    /// else says so and asks the person to check.
    func complete(_ reminder: ReminderSummary) async {
        guard !busyReminders.contains(reminder.id) else { return }
        busyReminders.insert(reminder.id)
        defer { busyReminders.remove(reminder.id) }
        undoable = nil
        guard !paused, isOn(.reminders) else {
            reminderNotice = NSLocalizedString("Reminders are off for Doddy, so nothing was ticked off.", comment: "")
            await refresh()
            return
        }
        guard let before = devices.reminderSnapshot(id: reminder.id),
              ReminderTick.stillAsShown(reminder, now: before, local: .current) else {
            reminderNotice = String(format: NSLocalizedString("“%@” changed in Reminders, so it wasn't ticked off. This is how it is now.", comment: ""), reminder.title)
            await refresh()
            return
        }
        do {
            switch try devices.changeReminder(before, .complete) {
            case .verified:
                reminderNotice = String(format: NSLocalizedString("Ticked off: %@. Checked in Reminders.", comment: ""), reminder.title)
                undoable = devices.reminderSnapshot(id: before.id).flatMap { $0.isCompleted ? $0 : nil }
            case .unconfirmed:
                reminderNotice = String(format: NSLocalizedString("Reminders took “%@” but didn't show it as done afterwards. Check it there.", comment: ""), reminder.title)
            case .changedElsewhere:
                reminderNotice = String(format: NSLocalizedString("“%@” changed in Reminders, so it wasn't ticked off. This is how it is now.", comment: ""), reminder.title)
            }
        } catch {
            reminderNotice = String(format: NSLocalizedString("“%@” wasn't ticked off. %@", comment: ""), reminder.title, UserFacingError.message(for: error))
        }
        await refresh()
    }

    /// Undo of the last tick (DOD-09): reopens it only if it is still done as read back, then reads
    /// it again.
    func undoTick() async {
        guard let done = undoable, !busyReminders.contains(done.id) else { return }
        undoable = nil
        busyReminders.insert(done.id)
        defer { busyReminders.remove(done.id) }
        guard !paused, isOn(.reminders) else {
            reminderNotice = NSLocalizedString("Reminders are off for Doddy, so nothing was changed. Open it in Reminders instead.", comment: "")
            await refresh()
            return
        }
        do {
            switch try devices.changeReminder(done, .reopen) {
            case .verified:
                reminderNotice = String(format: NSLocalizedString("Back on your list: %@. Checked in Reminders.", comment: ""), done.title)
            case .unconfirmed:
                reminderNotice = String(format: NSLocalizedString("Reminders took “%@” but didn't show it as open afterwards. Check it there.", comment: ""), done.title)
            case .changedElsewhere:
                reminderNotice = String(format: NSLocalizedString("“%@” changed in Reminders since, so it was left as it is.", comment: ""), done.title)
            }
        } catch {
            reminderNotice = String(format: NSLocalizedString("“%@” wasn't put back. %@", comment: ""), done.title, UserFacingError.message(for: error))
        }
        await refresh()
    }
}
