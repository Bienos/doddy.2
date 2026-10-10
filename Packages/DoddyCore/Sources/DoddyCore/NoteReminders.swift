import Foundation

// M4a — note reminders (docs/design/NOTIFICATIONS.md). A note reminder is a local notification the
// user asked for, about one saved memory, at one moment they confirmed on screen. Nothing here
// decides on its own to notify, and nothing is sent off the device. It sits next to, not instead of,
// M4's Apple Reminders (`ReminderAction`): those live in the Reminders app; these stay in Doddy and
// open the exact note. Other local notifications (timers, event nudges) and server pushes share the
// iOS queue, so everything here touches only identifiers with `MemoryReminder.notificationPrefix`.
// A reminder fires either at a time or at a place (ADR-196): for a place, iOS itself watches the
// spot and shows the notification; Doddy never follows where the user goes.

/// A place the user picked for a reminder. Only these numbers are stored; nothing about where the
/// user goes is ever recorded.
public struct ReminderPlace: Hashable, Sendable {
    /// What the user calls it ("Post office"); shown in Doddy, never in the notification.
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Int
    /// `true`: when the user arrives; `false`: when they leave.
    public let onArrival: Bool

    public static let radiusOptions = [100, 200, 500]
    public static let defaultRadius = 200
    public static let maxNameLength = 60

    public init(name: String, latitude: Double, longitude: Double, radiusMeters: Int, onArrival: Bool) throws(NoteReminderError) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maxNameLength,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              latitude.isFinite, longitude.isFinite,
              (Self.radiusOptions.min()!...1_000).contains(radiusMeters)
        else { throw .invalidPlace }
        self.name = trimmed
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.onArrival = onArrival
    }
}

/// When a reminder fires.
public enum ReminderTrigger: Hashable, Sendable {
    /// The absolute moment; travelling does not move it (owner decision D3). The zone it was set
    /// in is shown next to the time so the moment is never ambiguous.
    case time(fireAt: Date, timeZoneID: String)
    /// Each time the user arrives at (or leaves) the place, until they mark it Done.
    case place(ReminderPlace)
}

/// How a time reminder repeats (ADR-211). The weekday, day of the month and clock time come from
/// the reminder's first occurrence, in the zone it was set in.
public enum ReminderRepeat: String, CaseIterable, Hashable, Sendable {
    case daily, weekdays, weekly, monthly

    /// Monthly repeats are offered for days 1–28 only, so every month has the day (owner decision R1).
    public static let maxMonthDay = 28
}

/// One repeating iOS calendar match: fires whenever the clock in `timeZoneID` shows these values.
public struct RepeatMatch: Hashable, Sendable {
    public let hour: Int
    public let minute: Int
    /// 1 = Sunday … 7 = Saturday (Gregorian), for weekly and weekday matches.
    public let weekday: Int?
    /// Day of the month, for monthly matches.
    public let day: Int?
    public let timeZoneID: String

    public init(hour: Int, minute: Int, weekday: Int?, day: Int?, timeZoneID: String) {
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.day = day
        self.timeZoneID = timeZoneID
    }
}

/// Occurrence arithmetic for repeating reminders. Pure, so it is tested on Linux with fixed zones.
public enum ReminderSchedule {
    public static func calendar(_ timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }

    /// The matches iOS repeats on: one, or five for weekdays (Monday to Friday).
    public static func matches(_ rule: ReminderRepeat, anchor: Date, timeZoneID: String) -> [RepeatMatch] {
        let parts = calendar(timeZoneID).dateComponents([.hour, .minute, .weekday, .day], from: anchor)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        switch rule {
        case .daily:
            return [RepeatMatch(hour: hour, minute: minute, weekday: nil, day: nil, timeZoneID: timeZoneID)]
        case .weekdays:
            return (2...6).map { RepeatMatch(hour: hour, minute: minute, weekday: $0, day: nil, timeZoneID: timeZoneID) }
        case .weekly:
            return [RepeatMatch(hour: hour, minute: minute, weekday: parts.weekday, day: nil, timeZoneID: timeZoneID)]
        case .monthly:
            return [RepeatMatch(hour: hour, minute: minute, weekday: nil, day: parts.day, timeZoneID: timeZoneID)]
        }
    }

    /// The first occurrence strictly after `date`.
    public static func next(after date: Date, _ rule: ReminderRepeat, anchor: Date, timeZoneID: String) -> Date? {
        let cal = calendar(timeZoneID)
        return matches(rule, anchor: anchor, timeZoneID: timeZoneID)
            .compactMap { cal.nextDate(after: date, matching: components($0), matchingPolicy: .nextTime) }
            .min()
    }

    /// The latest occurrence at or before `date`, never before `anchor`.
    public static func previous(atOrBefore date: Date, _ rule: ReminderRepeat, anchor: Date, timeZoneID: String) -> Date? {
        guard date >= anchor else { return nil }
        // Every rule recurs within a month, so start at most 40 days back (the anchor is itself an
        // occurrence) and walk forward: at most ~30 steps.
        var cursor = max(anchor.addingTimeInterval(-1), date.addingTimeInterval(-40 * 86_400))
        var latest: Date?
        while let following = next(after: cursor, rule, anchor: anchor, timeZoneID: timeZoneID), following <= date {
            latest = following
            cursor = following
        }
        return latest
    }

    /// Where a repeat starts: its first matching time at least `lead` after `now`, using the
    /// weekday, day and clock time of `picked`. iOS repeating requests can't start later than that.
    public static func firstOccurrence(_ rule: ReminderRepeat, picked: Date, timeZoneID: String, now: Date, lead: TimeInterval) -> Date? {
        next(after: now.addingTimeInterval(lead - 1), rule, anchor: picked, timeZoneID: timeZoneID)
    }

    /// Monthly needs a day from 1 to 28 in the reminder's zone.
    public static func allows(_ rule: ReminderRepeat, picked: Date, timeZoneID: String) -> Bool {
        rule != .monthly || (calendar(timeZoneID).component(.day, from: picked) <= ReminderRepeat.maxMonthDay)
    }

    static func components(_ match: RepeatMatch) -> DateComponents {
        DateComponents(day: match.day, hour: match.hour, minute: match.minute, second: 0, weekday: match.weekday)
    }
}

/// One active reminder for one memory. Done one-off and cancelled reminders are deleted, not kept;
/// a repeating reminder stays until the user stops it.
public struct MemoryReminder: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let memoryID: UUID
    /// For a repeating reminder, `.time` holds its first occurrence (the anchor).
    public let trigger: ReminderTrigger
    public let createdAt: Date
    /// Time reminders only.
    public let repeats: ReminderRepeat?
    /// Repeating: the last "Done this time" (or snooze), so Home shows only newer occurrences as due.
    public let lastDoneAt: Date?
    /// Repeating: one extra reminder the user asked for with a snooze; the repeat carries on.
    public let snoozedUntil: Date?
    /// One-off moved by a snooze: the time it was first set for.
    public let firstSetFor: Date?

    public init(
        id: UUID, memoryID: UUID, trigger: ReminderTrigger, createdAt: Date, repeats: ReminderRepeat? = nil,
        lastDoneAt: Date? = nil, snoozedUntil: Date? = nil, firstSetFor: Date? = nil
    ) {
        self.id = id
        self.memoryID = memoryID
        self.trigger = trigger
        self.createdAt = createdAt
        self.repeats = repeats
        self.lastDoneAt = lastDoneAt
        self.snoozedUntil = snoozedUntil
        self.firstSetFor = firstSetFor
    }

    public init(id: UUID, memoryID: UUID, fireAt: Date, timeZoneID: String, createdAt: Date) {
        self.init(id: id, memoryID: memoryID, trigger: .time(fireAt: fireAt, timeZoneID: timeZoneID), createdAt: createdAt)
    }

    /// A copy with new repeat bookkeeping (same id, same trigger).
    public func with(lastDoneAt: Date?, snoozedUntil: Date?) -> MemoryReminder {
        MemoryReminder(
            id: id, memoryID: memoryID, trigger: trigger, createdAt: createdAt, repeats: repeats,
            lastDoneAt: lastDoneAt, snoozedUntil: snoozedUntil, firstSetFor: firstSetFor)
    }

    /// iOS slots this reminder uses (owner decision R2: weekdays uses 5).
    public var requestSlots: Int { repeats == .weekdays ? 5 : 1 }

    /// The next time it fires after `date`: the snooze or the next repeat, whichever is sooner;
    /// a one-off's own time if still ahead; `nil` for a place.
    public func nextFire(after date: Date) -> Date? {
        guard case .time(let anchor, let zone) = trigger else { return nil }
        guard let repeats else { return anchor > date ? anchor : nil }
        let repeatNext = ReminderSchedule.next(after: max(date, anchor.addingTimeInterval(-1)), repeats, anchor: anchor, timeZoneID: zone)
        let snooze = snoozedUntil.flatMap { $0 > date ? $0 : nil }
        return [repeatNext, snooze].compactMap { $0 }.min()
    }

    public var fireAt: Date? {
        if case .time(let fireAt, _) = trigger { return fireAt }
        return nil
    }

    public var timeZoneID: String? {
        if case .time(_, let zone) = trigger { return zone }
        return nil
    }

    public var place: ReminderPlace? {
        if case .place(let place) = trigger { return place }
        return nil
    }

    /// Every note-reminder request identifier starts with this; nothing else Doddy schedules does.
    public static let notificationPrefix = "doddy.note."

    /// The local notification request identifier.
    public var notificationID: String { Self.notificationID(for: id) }

    public static func notificationID(for reminderID: UUID) -> String { notificationPrefix + reminderID.uuidString }

    /// Weekday requests of a weekdays repeat: "<id>.w2" (Monday) … "<id>.w6" (Friday).
    public static func weekdayNotificationID(for reminderID: UUID, weekday: Int) -> String {
        notificationID(for: reminderID) + ".w\(weekday)"
    }

    /// The one extra request a snooze adds to a repeating reminder.
    public static func snoozeNotificationID(for reminderID: UUID) -> String {
        notificationID(for: reminderID) + ".snooze"
    }

    /// Every identifier this reminder could have used, for removal.
    public static func allNotificationIDs(for reminderID: UUID) -> [String] {
        [notificationID(for: reminderID), snoozeNotificationID(for: reminderID)]
            + (2...6).map { weekdayNotificationID(for: reminderID, weekday: $0) }
    }

    public var allNotificationIDs: [String] { Self.allNotificationIDs(for: id) }

    /// The reminder behind a notification, or `nil` for timers, nudges and server pushes.
    public static func reminderID(fromNotificationID identifier: String) -> UUID? {
        guard identifier.hasPrefix(notificationPrefix) else { return nil }
        let rest = identifier.dropFirst(notificationPrefix.count)
        let uuidLength = 36
        guard rest.count >= uuidLength else { return nil }
        let suffix = rest.dropFirst(uuidLength)
        guard suffix.isEmpty || suffix.hasPrefix(".") else { return nil }
        return UUID(uuidString: String(rest.prefix(uuidLength)))
    }

    /// Shown in Home's "Due now". One-off: its time has passed. Repeating: an occurrence (or the
    /// snooze) has passed since the last "Done this time". Place reminders are never due by the clock.
    public func isDue(at date: Date) -> Bool {
        guard case .time(let anchor, let zone) = trigger else { return false }
        guard let repeats else { return anchor <= date }
        if let snoozedUntil, snoozedUntil <= date { return true }
        guard let latest = ReminderSchedule.previous(atOrBefore: date, repeats, anchor: anchor, timeZoneID: zone) else { return false }
        return lastDoneAt.map { latest > $0 } ?? true
    }

    /// iOS should hold a request for it now: a one-off time still ahead, any repeat, or any place.
    public func wantsPendingRequest(at date: Date) -> Bool {
        place != nil || repeats != nil || !isDue(at: date)
    }
}

public enum NoteReminderLimits {
    /// iOS keeps at most 64 pending local notifications per app, shared with timers and event
    /// nudges; note reminders stay well below that.
    public static let maxActive = 50
    /// iOS watches at most 20 regions per app; place reminders stay well below that.
    public static let maxPlaces = 10
    /// A reminder must be at least this far in the future when it is set.
    public static let minimumLead: TimeInterval = 60
    /// Longest note excerpt shown in a notification when the user turned note text on.
    public static let maxBodyLength = 140
}

public enum NoteReminderError: Error, Equatable, Sendable {
    case timeInPast
    /// Monthly on a day after the 28th, or a repeat on a place reminder.
    case invalidRepeat
    case limitReached(maximum: Int)
    case memoryNotFound
    /// iOS did not confirm the request; nothing was kept.
    case notScheduled
    case invalidPlace
    case placeLimitReached(maximum: Int)
    /// A place reminder needs notifications on, or iOS can't alert at the place. Nothing was kept.
    case placeNeedsNotifications
    /// A place reminder needs location access with precise location. Nothing was kept.
    case placeNeedsLocation(LocationReadiness)
}

/// Whether iOS can watch a place for Doddy. Place reminders need "While Using" with Precise on;
/// Doddy never asks for "Always".
public enum LocationReadiness: Equatable, Sendable {
    case ready
    case notDetermined
    case denied
    /// Precise Location is off; iOS can't watch a place with approximate location.
    case approximateOnly
    /// Location Services are off for the whole iPhone, or not available.
    case unavailable
}

/// What happened after the user confirmed a reminder. Never claims an alert that iOS did not accept.
public enum NoteReminderOutcome: Equatable, Sendable {
    /// Stored and read back from the iOS pending notifications.
    case scheduled(MemoryReminder)
    /// Stored in Doddy only: notifications are off, so it shows on Home when due.
    case savedInAppOnly(MemoryReminder)

    public var reminder: MemoryReminder {
        switch self {
        case .scheduled(let reminder), .savedInAppOnly(let reminder): reminder
        }
    }
}

/// The language of what iOS shows outside Doddy: notification title, body and buttons (ADR-213).
/// Polish when the iPhone's first language is Polish; English otherwise, until other languages
/// have reviewed copy.
public enum NotificationLanguage: String, Sendable {
    case english, polish

    public static func preferred(_ languages: [String]) -> NotificationLanguage {
        languages.first.map { $0.lowercased().hasPrefix("pl") } == true ? .polish : .english
    }

    public static var current: NotificationLanguage { preferred(Locale.preferredLanguages) }
}

public enum NoteReminderCopy {
    public static let title = "Reminder"

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Przypomnienie" : title
    }

    /// Repeating reminders say so in the title, never the note (owner decision R3):
    /// "Reminder · every Monday" / "Przypomnienie · w każdy poniedziałek".
    public static func title(
        repeating rule: ReminderRepeat, anchor: Date, timeZoneID: String, language: NotificationLanguage = .english
    ) -> String {
        "\(title(language)) · \(ReminderFormat.cadence(rule, anchor: anchor, timeZoneID: timeZoneID, language: language))"
    }
    /// Default notification body: the note text never enters the iOS notification store.
    public static let privateBody = "A note you asked to see again."

    public static func privateBody(_ language: NotificationLanguage) -> String {
        // Second person, gender-neutral in Polish.
        language == .polish ? "Notatka, którą chcesz zobaczyć ponownie." : privateBody
    }

    /// Long-press buttons, in the order the categories use them.
    public enum Action: Sendable {
        case openNote, inAnHour, tomorrowMorning, done, doneThisTime
    }

    public static func action(_ action: Action, _ language: NotificationLanguage) -> String {
        switch (action, language) {
        case (.openNote, .english): "Open note"
        case (.openNote, .polish): "Otwórz notatkę"
        case (.inAnHour, .english): "In 1 hour"
        case (.inAnHour, .polish): "Za godzinę"
        case (.tomorrowMorning, .english): "Tomorrow 09:00"
        case (.tomorrowMorning, .polish): "Jutro 09:00"
        case (.done, .english): "Done"
        case (.done, .polish): "Gotowe"
        case (.doneThisTime, .english): "Done this time"
        case (.doneThisTime, .polish): "Gotowe tym razem"
        }
    }

    public static func body(noteText: String, showNoteText: Bool, language: NotificationLanguage = .english) -> String {
        guard showNoteText else { return privateBody(language) }
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > NoteReminderLimits.maxBodyLength else { return trimmed }
        return String(trimmed.prefix(NoteReminderLimits.maxBodyLength - 1)) + "…"
    }
}

/// Which long-press actions a notification offers.
public enum NoteReminderCategory: String, Sendable {
    /// Open note, In 1 hour, Tomorrow 09:00, Done.
    case once
    /// Open note, In 1 hour, Done this time (owner decision R4: no "Tomorrow 09:00").
    case repeating
    /// Open note, Done: a place comes back on the next arrival anyway.
    case place
}

/// Everything a notification adapter needs for one iOS request; built only from a stored reminder.
public struct NoteReminderNotification: Equatable, Sendable {
    public let identifier: String
    public let memoryID: UUID
    public let title: String
    public let body: String
    /// When `repeatMatch` is nil: the one-off moment or the place.
    public let trigger: ReminderTrigger
    /// A repeating calendar match; takes precedence over `trigger`.
    public let repeatMatch: RepeatMatch?
    public let category: NoteReminderCategory

    /// The reminder's main request (a one-off, a place, or a single-match repeat).
    public init(reminder: MemoryReminder, noteText: String, showNoteText: Bool) {
        let all = Self.requests(for: reminder, noteText: noteText, showNoteText: showNoteText, at: .distantPast)
        self = all.first { $0.identifier == reminder.notificationID } ?? all[0]
    }

    init(
        identifier: String, memoryID: UUID, title: String, body: String, trigger: ReminderTrigger,
        repeatMatch: RepeatMatch?, category: NoteReminderCategory
    ) {
        self.identifier = identifier
        self.memoryID = memoryID
        self.title = title
        self.body = body
        self.trigger = trigger
        self.repeatMatch = repeatMatch
        self.category = category
    }

    /// Every iOS request the reminder needs at `date`: none for a one-off already past; one per
    /// match for a repeat (five for weekdays); plus a snooze still ahead.
    public static func requests(
        for reminder: MemoryReminder, noteText: String, showNoteText: Bool, at date: Date,
        language: NotificationLanguage = .english
    ) -> [NoteReminderNotification] {
        let body = NoteReminderCopy.body(noteText: noteText, showNoteText: showNoteText, language: language)
        let plainTitle = NoteReminderCopy.title(language)
        switch reminder.trigger {
        case .place:
            return [NoteReminderNotification(
                identifier: reminder.notificationID, memoryID: reminder.memoryID, title: plainTitle, body: body,
                trigger: reminder.trigger, repeatMatch: nil, category: .place)]
        case .time(let fireAt, let zone):
            guard let rule = reminder.repeats else {
                guard fireAt > date else { return [] }
                return [NoteReminderNotification(
                    identifier: reminder.notificationID, memoryID: reminder.memoryID, title: plainTitle, body: body,
                    trigger: reminder.trigger, repeatMatch: nil, category: .once)]
            }
            let title = NoteReminderCopy.title(repeating: rule, anchor: fireAt, timeZoneID: zone, language: language)
            let matches = ReminderSchedule.matches(rule, anchor: fireAt, timeZoneID: zone)
            var result = matches.map { match in
                NoteReminderNotification(
                    identifier: rule == .weekdays
                        ? MemoryReminder.weekdayNotificationID(for: reminder.id, weekday: match.weekday ?? 0)
                        : reminder.notificationID,
                    memoryID: reminder.memoryID, title: title, body: body, trigger: reminder.trigger,
                    repeatMatch: match, category: .repeating)
            }
            if let snoozedUntil = reminder.snoozedUntil, snoozedUntil > date {
                result.append(NoteReminderNotification(
                    identifier: MemoryReminder.snoozeNotificationID(for: reminder.id), memoryID: reminder.memoryID,
                    title: title, body: body, trigger: .time(fireAt: snoozedUntil, timeZoneID: zone),
                    repeatMatch: nil, category: .repeating))
            }
            return result
        }
    }
}

public enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}

/// Local notifications only. The identifier lists include the app's other notifications (timers,
/// nudges, server pushes); the coordinator filters them by `MemoryReminder.notificationPrefix`.
public protocol NoteNotificationScheduling: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Shows the iOS prompt when not determined. Returns the status afterwards.
    func requestAuthorization() async -> NotificationAuthorization
    func locationReadiness() async -> LocationReadiness
    func add(_ notification: NoteReminderNotification) async throws
    func pendingIdentifiers() async -> Set<String>
    func deliveredIdentifiers() async -> Set<String>
    /// Removes pending and delivered requests with these identifiers.
    func remove(_ identifiers: [String]) async
}

/// Notifications switched off (UI tests, environments without a notification center).
public struct DisabledNoteNotifications: NoteNotificationScheduling {
    public init() {}
    public func authorization() async -> NotificationAuthorization { .denied }
    public func requestAuthorization() async -> NotificationAuthorization { .denied }
    public func locationReadiness() async -> LocationReadiness { .unavailable }
    public func add(_ notification: NoteReminderNotification) async throws { throw NoteReminderError.notScheduled }
    public func pendingIdentifiers() async -> Set<String> { [] }
    public func deliveredIdentifiers() async -> Set<String> { [] }
    public func remove(_ identifiers: [String]) async {}
}

/// Durable reminder storage. Deleting a memory deletes its reminder in the same store.
public protocol NoteReminderRepository: Sendable {
    /// Soonest first.
    func allReminders() async throws -> [MemoryReminder]
    func reminder(id: UUID) async throws -> MemoryReminder?
    func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder?
    func reminderCount() async throws -> Int
    func currentText(ofMemory memoryID: UUID) async throws -> String?
    /// Stores the memory's one reminder, replacing any earlier one; returns it read back.
    /// Throws `NoteReminderError.memoryNotFound` if the memory does not exist.
    func upsertReminder(_ reminder: MemoryReminder) async throws -> MemoryReminder
    @discardableResult
    func deleteReminder(id: UUID) async throws -> Bool
}

/// A quick pick resolved to a moment.
public struct ReminderOption: Hashable, Sendable {
    public let pick: ReminderQuickPick
    public let date: Date
}

/// Quick picks offered in the "When should I bring this back?" sheet (owner decision D5).
public enum ReminderQuickPick: String, CaseIterable, Sendable {
    case thisEvening, tomorrowMorning, mondayMorning

    public static let eveningHour = 18
    public static let morningHour = 9
    /// "This evening" is hidden when less than this remains before 18:00.
    public static let eveningCutoff: TimeInterval = 30 * 60

    /// The picks that make sense now, each with its resolved moment, in display order.
    public static func options(now: Date, calendar: Calendar) -> [ReminderOption] {
        var result: [ReminderOption] = []
        if let evening = calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: now),
           evening.timeIntervalSince(now) >= eveningCutoff {
            result.append(ReminderOption(pick: .thisEvening, date: evening))
        }
        let tomorrow = tomorrowMorning(after: now, calendar: calendar)
        if let tomorrow { result.append(ReminderOption(pick: .tomorrowMorning, date: tomorrow)) }
        if let monday = nextMondayMorning(after: now, calendar: calendar), monday != tomorrow {
            result.append(ReminderOption(pick: .mondayMorning, date: monday))
        }
        return result
    }

    /// 09:00 on the next calendar day. Also the "Tomorrow 09:00" notification action.
    public static func tomorrowMorning(after now: Date, calendar: Calendar) -> Date? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        return calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: nextDay)
    }

    /// 09:00 on the first Monday after today.
    public static func nextMondayMorning(after now: Date, calendar: Calendar) -> Date? {
        let monday = DateComponents(hour: morningHour, minute: 0, second: 0, weekday: 2)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.nextDate(
            after: startOfTomorrow.addingTimeInterval(-1), matching: monday, matchingPolicy: .nextTime)
    }
}

/// Fixed, literal date text for receipts: "Sun 11 Oct, 09:00 · Warsaw time".
public enum ReminderFormat {
    public static func dateTime(_ date: Date, timeZoneID: String, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        formatter.dateFormat = "EEE d MMM, HH:mm"
        return formatter.string(from: date)
    }

    public static func zoneName(_ timeZoneID: String) -> String {
        if ["GMT", "UTC", "Etc/UTC", "Etc/GMT"].contains(timeZoneID) { return "UTC" }
        let city = timeZoneID.split(separator: "/").last.map(String.init) ?? timeZoneID
        return city.replacingOccurrences(of: "_", with: " ") + " time"
    }

    public static func full(_ date: Date, timeZoneID: String, locale: Locale = .current) -> String {
        "\(dateTime(date, timeZoneID: timeZoneID, locale: locale)) · \(zoneName(timeZoneID))"
    }

    /// "When you arrive at Post office" / "When you leave Home".
    public static func place(_ place: ReminderPlace) -> String {
        place.onArrival ? "When you arrive at \(place.name)" : "When you leave \(place.name)"
    }

    /// "every day", "weekdays", "every Monday", "every month on the 12th". English for now; the
    /// Polish copy is open (owner decision D6).
    public static func cadence(
        _ rule: ReminderRepeat, anchor: Date, timeZoneID: String, language: NotificationLanguage = .english
    ) -> String {
        let cal = ReminderSchedule.calendar(timeZoneID)
        if language == .polish {
            switch rule {
            case .daily: return "codziennie"
            case .weekdays: return "w dni robocze"
            case .weekly:
                // Accusative after "w każdy/każdą": Wednesday, Saturday and Sunday are feminine.
                let names = ["", "w każdą niedzielę", "w każdy poniedziałek", "w każdy wtorek", "w każdą środę",
                             "w każdy czwartek", "w każdy piątek", "w każdą sobotę"]
                return names[cal.component(.weekday, from: anchor)]
            case .monthly: return "co miesiąc, \(cal.component(.day, from: anchor)). dnia"
            }
        }
        switch rule {
        case .daily: return "every day"
        case .weekdays: return "weekdays"
        case .weekly:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.timeZone = cal.timeZone
            formatter.dateFormat = "EEEE"
            return "every " + formatter.string(from: anchor)
        case .monthly: return "every month on the " + ordinal(cal.component(.day, from: anchor))
        }
    }

    /// "Every Monday at 20:00", "Weekdays at 08:00".
    public static func repeatPhrase(_ rule: ReminderRepeat, anchor: Date, timeZoneID: String) -> String {
        let cal = ReminderSchedule.calendar(timeZoneID)
        let parts = cal.dateComponents([.hour, .minute], from: anchor)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let text = "\(cadence(rule, anchor: anchor, timeZoneID: timeZoneID)) at \(clock)"
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    public static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch (day % 10, day % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    /// One line for any reminder: the full time with zone, the repeat with zone, or the place phrase.
    public static func summary(_ reminder: MemoryReminder, locale: Locale = .current) -> String {
        switch reminder.trigger {
        case .time(let fireAt, let zone):
            if let rule = reminder.repeats { return "\(repeatPhrase(rule, anchor: fireAt, timeZoneID: zone)) · \(zoneName(zone))" }
            return full(fireAt, timeZoneID: zone, locale: locale)
        case .place(let place): return self.place(place)
        }
    }

    /// Shorter form for sentences ("Reminder set for …").
    public static func short(_ reminder: MemoryReminder, locale: Locale = .current) -> String {
        switch reminder.trigger {
        case .time(let fireAt, let zone):
            if let rule = reminder.repeats {
                let phrase = repeatPhrase(rule, anchor: fireAt, timeZoneID: zone)
                return phrase.prefix(1).lowercased() + phrase.dropFirst()
            }
            return dateTime(fireAt, timeZoneID: zone, locale: locale)
        case .place(let place): return self.place(place).prefix(1).lowercased() + self.place(place).dropFirst()
        }
    }
}

/// The only code path that schedules, moves or removes a reminder. The database is the source of
/// truth; iOS pending requests are a projection that `reconcile()` repairs.
public actor NoteReminderCoordinator {
    private let repository: any NoteReminderRepository
    private let center: any NoteNotificationScheduling
    private let now: @Sendable () -> Date
    private let showNoteText: @Sendable () -> Bool
    private let calendar: @Sendable () -> Calendar
    private let language: @Sendable () -> NotificationLanguage

    public init(
        repository: any NoteReminderRepository,
        center: any NoteNotificationScheduling,
        now: @escaping @Sendable () -> Date = Date.init,
        showNoteText: @escaping @Sendable () -> Bool,
        calendar: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent },
        language: @escaping @Sendable () -> NotificationLanguage = { .english }
    ) {
        self.repository = repository
        self.center = center
        self.now = now
        self.showNoteText = showNoteText
        self.calendar = calendar
        self.language = language
    }

    public func reminders() async throws -> [MemoryReminder] { try await repository.allReminders() }
    public func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder? {
        try await repository.reminder(forMemory: memoryID)
    }
    public func authorization() async -> NotificationAuthorization { await center.authorization() }
    public func requestAuthorization() async -> NotificationAuthorization { await center.requestAuthorization() }

    public func locationReadiness() async -> LocationReadiness { await center.locationReadiness() }

    /// Sets (or replaces) the memory's reminder at a time, once or repeating. Returns `.scheduled`
    /// only after iOS lists every request as pending. If iOS refuses, nothing is kept and any
    /// earlier reminder is restored. A repeat starts at its first matching time from now; `fireAt`
    /// gives its weekday, day of the month and clock time.
    public func schedule(
        memoryID: UUID, at fireAt: Date, timeZone: TimeZone, repeats: ReminderRepeat? = nil
    ) async throws -> NoteReminderOutcome {
        let zone = timeZone.identifier
        guard let repeats else {
            guard fireAt.timeIntervalSince(now()) >= NoteReminderLimits.minimumLead else { throw NoteReminderError.timeInPast }
            return try await store(memoryID: memoryID, trigger: .time(fireAt: Self.wholeSeconds(fireAt), timeZoneID: zone))
        }
        guard ReminderSchedule.allows(repeats, picked: fireAt, timeZoneID: zone),
              let first = ReminderSchedule.firstOccurrence(
                  repeats, picked: Self.wholeMinutes(fireAt), timeZoneID: zone, now: now(), lead: NoteReminderLimits.minimumLead)
        else { throw NoteReminderError.invalidRepeat }
        return try await store(memoryID: memoryID, trigger: .time(fireAt: first, timeZoneID: zone), repeats: repeats)
    }

    /// Sets (or replaces) the memory's reminder at a place. There is no in-app fallback for a place,
    /// so notifications and precise location must both be on; otherwise nothing is stored.
    public func schedule(memoryID: UUID, place: ReminderPlace) async throws -> NoteReminderOutcome {
        guard await center.authorization() == .allowed else { throw NoteReminderError.placeNeedsNotifications }
        let readiness = await center.locationReadiness()
        guard readiness == .ready else { throw NoteReminderError.placeNeedsLocation(readiness) }
        let places = try await repository.allReminders().filter { $0.place != nil && $0.memoryID != memoryID }
        guard places.count < NoteReminderLimits.maxPlaces else {
            throw NoteReminderError.placeLimitReached(maximum: NoteReminderLimits.maxPlaces)
        }
        return try await store(memoryID: memoryID, trigger: .place(place))
    }

    private func store(
        memoryID: UUID, trigger: ReminderTrigger, repeats: ReminderRepeat? = nil, firstSetFor: Date? = nil
    ) async throws -> NoteReminderOutcome {
        let current = now()
        let all = try await repository.allReminders()
        let previous = all.first { $0.memoryID == memoryID }
        let candidate = MemoryReminder(
            id: UUID(), memoryID: memoryID, trigger: trigger, createdAt: Self.wholeSeconds(current),
            repeats: repeats, firstSetFor: firstSetFor)
        // The limit counts iOS slots, so a weekdays repeat uses five (owner decision R2).
        let others = all.filter { $0.memoryID != memoryID }.reduce(0) { $0 + $1.requestSlots }
        if others + candidate.requestSlots > NoteReminderLimits.maxActive {
            throw NoteReminderError.limitReached(maximum: NoteReminderLimits.maxActive)
        }
        guard let text = try await repository.currentText(ofMemory: memoryID) else { throw NoteReminderError.memoryNotFound }
        let reminder = try await repository.upsertReminder(candidate)

        guard await center.authorization() == .allowed else {
            if let previous { await center.remove(previous.allNotificationIDs) }
            return .savedInAppOnly(reminder)
        }
        do {
            try await addVerified(reminder, text: text)
        } catch {
            await center.remove(reminder.allNotificationIDs)
            _ = try? await repository.deleteReminder(id: reminder.id)
            if let previous { _ = try? await repository.upsertReminder(previous) }
            throw NoteReminderError.notScheduled
        }
        if let previous { await center.remove(previous.allNotificationIDs) }
        return .scheduled(reminder)
    }

    /// Adds every request the reminder needs now and checks iOS lists each one as pending.
    private func addVerified(_ reminder: MemoryReminder, text: String) async throws {
        let requests = NoteReminderNotification.requests(
            for: reminder, noteText: text, showNoteText: showNoteText(), at: now(), language: language())
        for request in requests { try await center.add(request) }
        let pending = await center.pendingIdentifiers()
        guard requests.allSatisfy({ pending.contains($0.identifier) }) else { throw NoteReminderError.notScheduled }
    }

    /// "Tomorrow 09:00" (notification action) or Home's Later: same memory, new moment.
    public func snoozeUntilTomorrowMorning(reminderID: UUID) async throws -> NoteReminderOutcome? {
        let cal = calendar()
        guard let tomorrow = ReminderQuickPick.tomorrowMorning(after: now(), calendar: cal) else { return nil }
        return try await snooze(reminderID: reminderID, until: tomorrow)
    }

    /// "In 1 hour" (notification action or Home).
    public func snoozeForAnHour(reminderID: UUID) async throws -> NoteReminderOutcome? {
        try await snooze(reminderID: reminderID, until: now().addingTimeInterval(3_600))
    }

    /// Brings a time reminder back at `date`. A one-off moves there (remembering the time it was
    /// first set for). A repeating one counts this occurrence as handled and gets one extra request;
    /// the repeat carries on. Checked like setting one: if iOS refuses, the reminder is unchanged.
    /// Place reminders have no snooze (`nil`).
    public func snooze(reminderID: UUID, until date: Date) async throws -> NoteReminderOutcome? {
        guard let reminder = try await repository.reminder(id: reminderID),
              case .time(let fireAt, let zone) = reminder.trigger else { return nil }
        guard date.timeIntervalSince(now()) >= NoteReminderLimits.minimumLead else { throw NoteReminderError.timeInPast }
        let until = Self.wholeSeconds(date)
        guard reminder.repeats != nil else {
            return try await store(
                memoryID: reminder.memoryID, trigger: .time(fireAt: until, timeZoneID: zone),
                firstSetFor: reminder.firstSetFor ?? fireAt)
        }
        let snoozed = try await repository.upsertReminder(
            reminder.with(lastDoneAt: Self.wholeSeconds(now()), snoozedUntil: until))
        let snoozeID = MemoryReminder.snoozeNotificationID(for: reminder.id)
        await center.remove([snoozeID])
        guard await center.authorization() == .allowed else { return .savedInAppOnly(snoozed) }
        guard let text = try await repository.currentText(ofMemory: reminder.memoryID) else { throw NoteReminderError.memoryNotFound }
        do {
            try await addVerified(snoozed, text: text)
        } catch {
            await center.remove([snoozeID])
            _ = try? await repository.upsertReminder(reminder)
            throw NoteReminderError.notScheduled
        }
        return .scheduled(snoozed)
    }

    /// Done: a one-off or place reminder is deleted (the note stays). A repeating one is done for
    /// this time only: its next occurrence still comes (owner-approved design, screen 17).
    public func markDone(reminderID: UUID) async throws {
        guard let reminder = try await repository.reminder(id: reminderID) else { return }
        guard reminder.repeats != nil else { return try await remove(reminderID: reminderID) }
        _ = try await repository.upsertReminder(reminder.with(lastDoneAt: Self.wholeSeconds(now()), snoozedUntil: nil))
        // Clears its delivered banners and any snooze. iOS removes pending and delivered requests by
        // the same identifier, so reconcile re-adds the repeat right after.
        let delivered = await center.deliveredIdentifiers().filter { MemoryReminder.reminderID(fromNotificationID: $0) == reminderID }
        await center.remove(Array(delivered.union([MemoryReminder.snoozeNotificationID(for: reminderID)])))
        await reconcile()
    }

    /// Cancel or Stop repeating: the reminder is deleted and all its notifications removed. The memory stays.
    public func remove(reminderID: UUID) async throws {
        try await repository.deleteReminder(id: reminderID)
        await center.remove(MemoryReminder.allNotificationIDs(for: reminderID))
    }

    /// Call after the memory was deleted (its reminder row is deleted with it).
    public func memoryDeleted(reminderID: UUID) async {
        await center.remove(MemoryReminder.allNotificationIDs(for: reminderID))
    }

    /// Call after every memory was deleted. Timers, nudges and server pushes are left alone.
    public func allMemoriesDeleted() async {
        let ours = await center.pendingIdentifiers().union(await center.deliveredIdentifiers())
            .filter { $0.hasPrefix(MemoryReminder.notificationPrefix) }
        if !ours.isEmpty { await center.remove(Array(ours)) }
    }

    /// Note text or the "Show note text" setting changed: replace pending content.
    public func refreshContent(forMemory memoryID: UUID? = nil) async {
        guard await center.authorization() == .allowed,
              let reminders = try? await repository.allReminders() else { return }
        for reminder in reminders where memoryID == nil || reminder.memoryID == memoryID {
            await addIfPossible(reminder)
        }
    }

    /// Makes iOS match the database: re-adds missing requests (future one-offs, repeats, snoozes,
    /// places; e.g. after a restore or after notifications were turned on) and removes requests
    /// that no reminder wants.
    public func reconcile() async {
        guard await center.authorization() == .allowed,
              let reminders = try? await repository.allReminders() else { return }
        let current = now()
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(MemoryReminder.notificationPrefix) }
        var wanted: [String: (MemoryReminder, Set<String>)] = [:]
        for reminder in reminders {
            let ids = Set(NoteReminderNotification.requests(for: reminder, noteText: "", showNoteText: false, at: current).map(\.identifier))
            wanted[reminder.notificationID] = (reminder, ids)
        }
        let allWanted = wanted.values.reduce(into: Set<String>()) { $0.formUnion($1.1) }
        let orphans = pending.subtracting(allWanted)
        if !orphans.isEmpty { await center.remove(Array(orphans)) }
        for (reminder, ids) in wanted.values where !ids.isSubset(of: pending) {
            await addIfPossible(reminder)
        }
    }

    private func addIfPossible(_ reminder: MemoryReminder) async {
        guard let text = try? await repository.currentText(ofMemory: reminder.memoryID) else { return }
        for request in NoteReminderNotification.requests(
            for: reminder, noteText: text, showNoteText: showNoteText(), at: now(), language: language()) {
            try? await center.add(request)
        }
    }

    private static func wholeMinutes(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

public struct UnavailableNoteReminderRepository: NoteReminderRepository {
    public init() {}
    public func allReminders() async throws -> [MemoryReminder] { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func reminder(id: UUID) async throws -> MemoryReminder? { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder? { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func reminderCount() async throws -> Int { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func currentText(ofMemory memoryID: UUID) async throws -> String? { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func upsertReminder(_ reminder: MemoryReminder) async throws -> MemoryReminder { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func deleteReminder(id: UUID) async throws -> Bool { throw DoddyError.capabilityUnavailable(.noteReminders) }
}
