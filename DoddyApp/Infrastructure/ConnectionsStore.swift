import DoddyCore
import Foundation
import Observation

/// Main-actor state for Connections (V4a). Everything shown comes from a real read of the iOS
/// stores; "Connected" requires the user's switch, a reading permission and a successful read.
/// Writes go through here only after the user tapped Add on a confirmation card.
@MainActor
@Observable
final class ConnectionsStore {
    let environment: AppEnvironment
    private let defaults: UserDefaults

    private(set) var states: [ConnectionKind: ConnectionState]
    private(set) var calendars: [CalendarInfo] = []
    private(set) var todayEvents: [CalendarEvent] = []
    private(set) var todayReminders: [ReminderItem] = []
    private(set) var todayProblem: String?
    private(set) var nudgeAuthorization: NudgeAuthorization = .notDetermined
    private(set) var pendingNudges: [ScheduledNudge] = []
    private(set) var nudgeProblem: String?
    private(set) var lastRefresh: Date?

    init(environment: AppEnvironment, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
        var states: [ConnectionKind: ConnectionState] = [:]
        for kind in ConnectionKind.allCases {
            states[kind] = ConnectionState(kind: kind, enabled: defaults.bool(forKey: PreferenceKey.connectionEnabled(kind)))
        }
        self.states = states
    }

    func state(_ kind: ConnectionKind) -> ConnectionState { states[kind] ?? ConnectionState(kind: kind) }

    func isAvailable(_ kind: ConnectionKind) -> Bool { environment.capabilities.isAvailable(kind.capability) }

    var nudgesAvailable: Bool { environment.capabilities.isAvailable(.localNudges) }

    var connectedCount: Int { ConnectionKind.allCases.filter { state($0).status.isConnected }.count }

    // MARK: Refresh

    /// Re-reads permissions (the user may have changed them in iOS Settings), verifies each
    /// switched-on connection with a real read, then loads today's events, reminders and nudges.
    func refresh(now: Date = Date()) async {
        for kind in ConnectionKind.allCases {
            await refreshConnection(kind, now: now)
        }
        await refreshToday(now: now)
        await refreshNudges()
        lastRefresh = now
    }

    private func refreshConnection(_ kind: ConnectionKind, now: Date) async {
        var state = self.state(kind)
        guard isAvailable(kind) else {
            states[kind] = ConnectionState(kind: kind, enabled: state.enabled)
            return
        }
        state.authorization = authorization(kind)
        state.lastError = nil
        state.verification = nil
        if state.enabled, state.authorization.allowsReading {
            do {
                state.verification = try await verify(kind, now: now)
            } catch {
                state.lastError = ConnectionsCopy.message(for: error)
            }
        }
        if kind == .calendar, !state.canRead { calendars = [] }
        states[kind] = state
    }

    private func verify(_ kind: ConnectionKind, now: Date) async throws -> ConnectionVerification {
        switch kind {
        case .calendar:
            let found = try await environment.calendarGateway.calendars()
            calendars = found
            return ConnectionVerification(verifiedAt: now, evidence: "Read \(Self.count(found.count, "calendar"))")
        case .reminders:
            let lists = try await environment.remindersGateway.listTitles()
            return ConnectionVerification(verifiedAt: now, evidence: "Read \(Self.count(lists.count, "reminder list"))")
        case .contacts:
            let accounts = try await environment.contactsGateway.accountCount()
            return ConnectionVerification(verifiedAt: now, evidence: "Opened \(Self.count(accounts, "contacts account"))")
        }
    }

    private func refreshToday(now: Date) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        var problems: [String] = []
        if state(.calendar).canRead {
            do {
                todayEvents = try await environment.calendarGateway.events(from: startOfDay, to: endOfDay)
            } catch {
                todayEvents = []
                problems.append(ConnectionsCopy.message(for: error))
            }
        } else {
            todayEvents = []
        }
        if state(.reminders).canRead {
            do {
                todayReminders = try await environment.remindersGateway.incompleteReminders(dueBefore: endOfDay)
            } catch {
                todayReminders = []
                problems.append(ConnectionsCopy.message(for: error))
            }
        } else {
            todayReminders = []
        }
        todayProblem = problems.isEmpty ? nil : problems.joined(separator: " ")
    }

    private func refreshNudges() async {
        guard nudgesAvailable else { return }
        nudgeAuthorization = await environment.nudgeScheduler.authorization()
        do {
            pendingNudges = try await environment.nudgeScheduler.pending()
            nudgeProblem = nil
        } catch {
            pendingNudges = []
            nudgeProblem = ConnectionsCopy.message(for: error)
        }
    }

    // MARK: Connect / disconnect

    /// Switches the connection on in Doddy, asks iOS for access if it hasn't been decided (or is
    /// write-only), then verifies with a real read.
    func connect(_ kind: ConnectionKind) async {
        guard isAvailable(kind) else { return }
        setEnabled(true, for: kind)
        let current = authorization(kind)
        if current == .notDetermined || current == .writeOnly {
            do {
                _ = try await requestAccess(kind)
            } catch {
                var state = self.state(kind)
                state.lastError = ConnectionsCopy.message(for: error)
                states[kind] = state
                return
            }
        }
        await refreshConnection(kind, now: Date())
        await refreshToday(now: Date())
    }

    /// Doddy stops using it. The iOS permission stays until the user changes it in Settings.
    func disconnect(_ kind: ConnectionKind) async {
        setEnabled(false, for: kind)
        await refreshConnection(kind, now: Date())
        await refreshToday(now: Date())
    }

    private func setEnabled(_ enabled: Bool, for kind: ConnectionKind) {
        defaults.set(enabled, forKey: PreferenceKey.connectionEnabled(kind))
        var state = self.state(kind)
        state.enabled = enabled
        states[kind] = state
    }

    private func authorization(_ kind: ConnectionKind) -> SystemAuthorization {
        switch kind {
        case .calendar: return environment.calendarGateway.authorization()
        case .reminders: return environment.remindersGateway.authorization()
        case .contacts: return environment.contactsGateway.authorization()
        }
    }

    private func requestAccess(_ kind: ConnectionKind) async throws -> SystemAuthorization {
        switch kind {
        case .calendar: return try await environment.calendarGateway.requestAccess()
        case .reminders: return try await environment.remindersGateway.requestAccess()
        case .contacts: return try await environment.contactsGateway.requestAccess()
        }
    }

    // MARK: Reads (automatic once connected)

    func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        guard state(.calendar).canRead else { throw ConnectionError.notAuthorized(.calendar) }
        return try await environment.calendarGateway.events(from: start, to: end)
    }

    func lookupContacts(_ name: String) async throws -> [ContactMatch] {
        guard state(.contacts).canRead else { throw ConnectionError.notAuthorized(.contacts) }
        return try await environment.contactsGateway.lookup(name: name)
    }

    // MARK: Writes (only after the user tapped Add)

    func addEvent(_ draft: EventDraft) async throws -> CalendarEvent {
        guard state(.calendar).canWrite else { throw ConnectionError.notAuthorized(.calendar) }
        do {
            let event = try await environment.calendarGateway.createEvent(draft)
            await refreshToday(now: Date())
            return event
        } catch {
            await refreshToday(now: Date())
            throw error
        }
    }

    func addReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
        guard state(.reminders).canWrite else { throw ConnectionError.notAuthorized(.reminders) }
        do {
            let item = try await environment.remindersGateway.createReminder(draft)
            await refreshToday(now: Date())
            return item
        } catch {
            await refreshToday(now: Date())
            throw error
        }
    }

    // MARK: Nudges

    /// Asks for notification permission the first time, schedules, and returns the request as
    /// read back from iOS.
    func scheduleNudge(for event: CalendarEvent, leadMinutes: Int) async throws -> ScheduledNudge {
        guard nudgesAvailable else { throw DoddyError.capabilityUnavailable(.localNudges) }
        let plan = try EventNudgePlan(event: event, leadMinutes: leadMinutes, now: Date())
        var authorization = await environment.nudgeScheduler.authorization()
        if authorization == .notDetermined {
            authorization = try await environment.nudgeScheduler.requestAuthorization()
        }
        nudgeAuthorization = authorization
        guard authorization == .authorized else { throw NudgeError.notAuthorized }
        let nudge = try await environment.nudgeScheduler.schedule(plan)
        await refreshNudges()
        return nudge
    }

    func cancelNudge(id: String) async throws {
        try await environment.nudgeScheduler.cancel(id: id)
        await refreshNudges()
    }

    func nudges(for event: CalendarEvent) -> [ScheduledNudge] {
        pendingNudges.filter { $0.eventID == event.id }
    }

    /// Today's event a nudge belongs to, if it is in today's list.
    func event(for nudge: ScheduledNudge) -> CalendarEvent? {
        todayEvents.first { $0.id == nudge.eventID }
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

extension ConnectionKind {
    var capability: Capability {
        switch self {
        case .calendar: .calendar
        case .reminders: .reminders
        case .contacts: .contacts
        }
    }

    var title: String { VoiceToolReply.displayName(self) }

    var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle"
        }
    }
}

/// User-facing words for connection states and errors. Never says "connected" without proof.
enum ConnectionsCopy {
    static func status(_ state: ConnectionState) -> String {
        switch state.status {
        case .off: "Off"
        case .notConnected: "Not connected"
        case .denied: "Off in iOS Settings"
        case .authorizedUnverified:
            state.authorization == .writeOnly ? "Can add only" : "Not checked yet"
        case .connected: "Connected"
        case .error: "Problem"
        }
    }

    static func nudgeStatus(_ authorization: NudgeAuthorization, pending: Int) -> String {
        switch authorization {
        case .notDetermined: pending == 0 ? "None set" : "\(pending) set"
        case .denied: "Notifications off"
        case .authorized: pending == 0 ? "None set" : "\(pending) set"
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? ConnectionError {
            switch error {
            case .notAuthorized(let kind):
                return "\(kind.title) isn't connected. Connect it in Settings → Connections."
            case .unverified(let kind):
                return "iOS took the request but Doddy couldn't read it back, so it isn't confirmed. Check \(kind.title) before trying again."
            case .noWritableCalendar:
                return "There's no default calendar or list to add to. Choose one in iOS Settings."
            case .failed(let reason):
                return "iOS didn't accept it, so nothing was added. (\(reason))"
            }
        }
        if let error = error as? NudgeError {
            switch error {
            case .notAuthorized:
                return "Notifications are off for Doddy, so no nudge was set. You can turn them on in iOS Settings."
            case .unverified:
                return "iOS took the nudge but it isn't in the scheduled list, so it isn't confirmed."
            }
        }
        if let error = error as? NudgePlanError {
            switch error {
            case .fireTimeInPast: return "That time has already passed. Pick a shorter lead time."
            case .leadTimeInvalid: return "That lead time doesn't work."
            }
        }
        if let error = error as? ConnectionDraftError {
            switch error {
            case .emptyTitle: return "It needs a title."
            case .endBeforeStart: return "The end is before the start."
            }
        }
        if error is DoddyError {
            return "This isn't available in this build."
        }
        return "Something went wrong and nothing was changed. (\(error.localizedDescription))"
    }
}
