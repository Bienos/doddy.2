import Foundation

// M4: one reliable action, Apple Reminders (docs/implementation/M4_REMINDERS_STATUS.md, ADR-126).
// Everything here is plain Swift so it runs in the Linux tests. The iPhone side is
// `DeviceConnections` (DoddyApp/Infrastructure/Connections), which only reads and saves.
// The rules:
//  - the user reviewed the card and tapped Add;
//  - a due time is local wall-clock time on a day the agent wrote out, in a named time zone, not
//    in the past and not a time the clocks skip or repeat; anything else is sent back as a question;
//  - Doddy looks before it writes, so asking again never makes a second copy;
//  - after writing it reads the reminder back and says "added" only if title and due match;
//  - if a save fails, it looks again before saying anything, and says "unknown" if it can't tell.

// MARK: Due date

/// A due day, or day and time, as wall-clock fields. `timeZoneID` is the zone the user meant;
/// nil only for reminders read back without one (made "floating" in the Reminders app).
public struct ReminderDue: Codable, Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?
    public let timeZoneID: String?

    public init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil, timeZoneID: String?) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = hour == nil ? nil : (minute ?? 0)
        self.timeZoneID = timeZoneID
    }

    public var hasTime: Bool { hour != nil }

    /// "2026-10-12T18:00" or "2026-10-12": the form the agent sends.
    public var localText: String {
        let day = String(format: "%04d-%02d-%02d", year, month, self.day)
        guard let hour else { return day }
        return day + String(format: "T%02d:%02d", hour, minute ?? 0)
    }

    /// Same day and time, ignoring the zone.
    func sameWallClock(as other: ReminderDue) -> Bool {
        year == other.year && month == other.month && day == other.day && hour == other.hour && minute == other.minute
    }

    /// Gregorian calendar in this due's zone (UTC when it has none; weekdays don't depend on it).
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
        return calendar
    }

    /// The moment it is due (start of the day for a day without a time).
    public var date: Date? { date(in: calendar) }

    /// The moment these wall-clock fields name in `calendar`'s zone, read as Gregorian.
    func date(in calendar: Calendar) -> Date? {
        ReminderDueRules.gregorian(calendar).date(
            from: DateComponents(year: year, month: month, day: day, hour: hour ?? 0, minute: minute ?? 0))
    }
}

/// Why a reminder was sent back to the agent instead of shown or added. `problem` and
/// `question` are written for the model, which asks the user and tries again.
public struct ReminderClarification: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Not a day, or a day and time, in local time (a bare time, a word, a zone suffix, Feb 31).
        case unreadable
        case timePassed
        case dayPassed
        /// The clocks skip this time that day (daylight saving starts).
        case timeSkipped
        /// The clocks pass this time twice that day (daylight saving ends).
        case timeRepeated
        /// The user's words for the time and the date sent don't agree (ADR-253).
        case saidDifferently
        /// The words allow two days ("next Friday", "this weekend") (ADR-253).
        case ambiguousDay
        /// The words allow two times ("at 7") (ADR-253).
        case ambiguousTime
        /// A time was sent that the user never said (ADR-253).
        case noTimeSaid
    }

    public let kind: Kind
    public let problem: String
    public let question: String

    /// One line for the screen when the card was already shown (only the "passed" kinds get there).
    public var screenLine: String {
        switch kind {
        case .timePassed, .dayPassed: "That time has already passed, so nothing was added. Ask Doddy again with a new time."
        default: "Doddy needs a clearer day or time, so nothing was added."
        }
    }
}

public enum ReminderDueCheck: Equatable, Sendable {
    case due(ReminderDue)
    case clarify(ReminderClarification)
}

/// Also the rules for calendar times: `check`'s rules for `create_calendar_event` (ADR-127,
/// ADR-128), `wallClock` alone for `read_calendar`, where past days are fine.
public enum ReminderDueRules {
    /// A reminder's due: `wallClock`, and not already passed.
    public static func check(_ text: String, now: Date, calendar: Calendar) -> ReminderDueCheck {
        let checked = wallClock(text, calendar: calendar)
        if case .due(let due) = checked, let late = passed(due, now: now) { return .clarify(late) }
        return checked
    }

    /// Reads "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" (":SS" allowed and dropped) as local time in
    /// `calendar`'s time zone. Strict: no zone suffix, no words, no bare time, no rolled-over dates,
    /// no time the clocks skip or repeat. Past times are allowed here; `check` refuses them.
    public static func wallClock(_ text: String, calendar: Calendar) -> ReminderDueCheck {
        // The agent writes ISO dates, which are Gregorian whatever calendar the phone is set to.
        let calendar = gregorian(calendar)
        let zone = calendar.timeZone.identifier
        guard let fields = fields(text) else { return .clarify(unreadable(text)) }
        var components = DateComponents(year: fields.year, month: fields.month, day: fields.day)
        if let hour = fields.hour {
            components.hour = hour
            components.minute = fields.minute
        }
        guard let date = calendar.date(from: components) else { return .clarify(unreadable(text)) }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard back.year == fields.year, back.month == fields.month, back.day == fields.day else {
            return .clarify(unreadable(text))
        }
        let due = ReminderDue(
            year: fields.year, month: fields.month, day: fields.day, hour: fields.hour, minute: fields.minute, timeZoneID: zone)
        if let hour = fields.hour, let minute = fields.minute {
            let clock = String(format: "%02d:%02d", hour, minute)
            let day = String(due.localText.prefix(10))
            guard back.hour == hour, back.minute == minute else {
                return .clarify(ReminderClarification(
                    kind: .timeSkipped,
                    problem: "\(clock) on \(day) does not exist in \(zone) because the clocks go forward",
                    question: "for a different time"))
            }
            if isRepeated(date, components: back, calendar: calendar) {
                return .clarify(ReminderClarification(
                    kind: .timeRepeated,
                    problem: "\(clock) on \(day) happens twice in \(zone) because the clocks go back",
                    question: "for a different time"))
            }
        }
        return .due(due)
    }

    /// Gregorian, in `calendar`'s time zone.
    static func gregorian(_ calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// Nil while the due time is still ahead (a day without a time counts until that day ends).
    /// Checked when the card is shown and again when the user taps Add.
    public static func passed(_ due: ReminderDue, now: Date) -> ReminderClarification? {
        let calendar = due.calendar
        let zone = calendar.timeZone.identifier
        guard let date = due.date else { return unreadable(due.localText) }
        if due.hasTime {
            guard date < now else { return nil }
            return ReminderClarification(
                kind: .timePassed,
                problem: "\(display(due.localText)) has already passed (it is now \(stamp(now, calendar: calendar, time: true)) in \(zone))",
                question: "which day and time they mean")
        }
        guard calendar.startOfDay(for: date) < calendar.startOfDay(for: now) else { return nil }
        return ReminderClarification(
            kind: .dayPassed,
            problem: "\(due.localText) is already over (today is \(stamp(now, calendar: calendar, time: false)) in \(zone))",
            question: "which day they mean")
    }

    private static func unreadable(_ text: String) -> ReminderClarification {
        ReminderClarification(
            kind: .unreadable,
            problem: "\"\(text)\" is not a day (YYYY-MM-DD) or a day and time (YYYY-MM-DDTHH:MM) in the user's local time, without a time zone",
            question: "which day, and what time if any, they want it")
    }

    /// Another instant up to two hours away shows the same wall clock: that time happens twice.
    private static func isRepeated(_ date: Date, components: DateComponents, calendar: Calendar) -> Bool {
        [-7200.0, -3600, -1800, 1800, 3600, 7200].contains { offset in
            let other = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date.addingTimeInterval(offset))
            return other.year == components.year && other.month == components.month && other.day == components.day
                && other.hour == components.hour && other.minute == components.minute
        }
    }

    private struct Fields {
        let year: Int, month: Int, day: Int
        let hour: Int?, minute: Int?
    }

    private static func fields(_ text: String) -> Fields? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let halves = trimmed.split(separator: "T", omittingEmptySubsequences: false)
        guard halves.count == 1 || halves.count == 2 else { return nil }
        let ymd = halves[0].split(separator: "-", omittingEmptySubsequences: false)
        guard ymd.count == 3, digits(ymd[0], 4), digits(ymd[1], 2), digits(ymd[2], 2),
              let year = Int(ymd[0]), let month = Int(ymd[1]), let day = Int(ymd[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        guard halves.count == 2 else { return Fields(year: year, month: month, day: day, hour: nil, minute: nil) }
        let hms = halves[1].split(separator: ":", omittingEmptySubsequences: false)
        guard hms.count == 2 || (hms.count == 3 && digits(hms[2], 2)),
              digits(hms[0], 2), digits(hms[1], 2),
              let hour = Int(hms[0]), let minute = Int(hms[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return Fields(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    private static func digits(_ text: Substring, _ count: Int) -> Bool {
        text.count == count && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func display(_ localText: String) -> String {
        localText.replacingOccurrences(of: "T", with: " ")
    }

    private static func stamp(_ date: Date, calendar: Calendar, time: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: Idempotency

/// A stable key for "this reminder": the title (case, accents, spacing and end punctuation
/// ignored) and the due wall clock. Doddy stores it in the reminder's URL field as
/// `doddy://reminder/<key>` and looks for it, and for the same title and due, before writing.
/// The tool call id is deliberately not part of it: an agent that asks again after a timeout
/// sends a new id for the same reminder. Changing this function orphans keys already stored.
public enum ReminderIdempotency {
    public static let markerPrefix = "doddy://reminder/"

    public static func normalizedTitle(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(words.reversed().drop(while: { ".!?,;:…".contains($0) || $0.isWhitespace }).reversed())
    }

    public static func key(title: String, due: ReminderDue?) -> String {
        "v1-" + fnv(normalizedTitle(title) + "\u{1F}" + (due?.localText ?? "-"))
    }

    /// FNV-1a, 64 bit, as 16 hex digits: stable across runs and platforms (Swift's Hasher is not).
    static func fnv(_ source: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    public static func markerURL(key: String) -> String { markerPrefix + key }

    /// The key in a Doddy marker URL, or nil for any other URL.
    public static func key(fromMarker url: String?) -> String? {
        guard let url, url.hasPrefix(markerPrefix) else { return nil }
        let key = String(url.dropFirst(markerPrefix.count))
        return key.isEmpty ? nil : key
    }
}

// MARK: Store port

/// What Doddy writes: exactly what the card showed, plus the marker.
public struct ReminderWrite: Equatable, Sendable {
    public let title: String
    public let notes: String?
    public let due: ReminderDue?
    public let key: String
    /// Reminders' own repeat (ADR-282).
    public let repeats: CalendarRepeat?

    public init(_ draft: ReminderDraft) {
        title = draft.title
        notes = draft.notes
        due = draft.due
        repeats = draft.repeats
        key = ReminderIdempotency.key(title: draft.title, due: draft.due)
    }

    public var markerURL: String { ReminderIdempotency.markerURL(key: key) }
}

/// A reminder as read back from the iPhone. Stays on the phone; only the title and due of the
/// one Doddy wrote (or found) go back to the agent.
public struct ReminderSnapshot: Equatable, Sendable {
    public let id: String
    public let title: String
    public let listTitle: String
    public let due: ReminderDue?
    public let markerURL: String?
    public let isCompleted: Bool
    /// The repeat as read back (ADR-282); nil for none, or a rule Doddy doesn't write.
    public let repeats: CalendarRepeat?
    /// As Reminders shows it (ADR-302).
    public let priority: ReminderPriority
    /// The list's identifier on this iPhone; nil when not read.
    public let listID: String?
    /// The notes, read on this iPhone for the card and the stale check of a replace (ADR-314).
    /// Never sent to the voice agent.
    public let notes: String?

    public init(id: String, title: String, listTitle: String, due: ReminderDue?, markerURL: String?, isCompleted: Bool = false,
                repeats: CalendarRepeat? = nil, priority: ReminderPriority = .none, listID: String? = nil, notes: String? = nil) {
        self.notes = notes
        self.repeats = repeats
        self.priority = priority
        self.listID = listID
        self.id = id
        self.title = title
        self.listTitle = listTitle
        self.due = due
        self.markerURL = markerURL
        self.isCompleted = isCompleted
    }
}

public enum ReminderStoreError: Error, Equatable, Sendable {
    case timedOut
    case notAllowed
}

/// The iPhone's Reminders, as M4 needs them. `DeviceConnections` implements it with EventKit;
/// the tests use a fake.
@MainActor
public protocol ReminderStore: AnyObject {
    /// Every incomplete reminder in every list. Throws when they can't be read in time.
    func incompleteReminders() async throws -> [ReminderSnapshot]
    /// Saves and commits one reminder in the default list and returns its identifier.
    /// A throw does not prove that nothing was written.
    func save(_ write: ReminderWrite) throws -> String
}

public enum ReminderMatching {
    /// The incomplete reminder that already is this one: Doddy's marker with the same key, or else
    /// the same title (normalized) with the same due day and time.
    public static func existing(for write: ReminderWrite, in reminders: [ReminderSnapshot]) -> ReminderSnapshot? {
        let open = reminders.filter { !$0.isCompleted }
        if let marked = open.first(where: { ReminderIdempotency.key(fromMarker: $0.markerURL) == write.key }) {
            return marked
        }
        let title = ReminderIdempotency.normalizedTitle(write.title)
        return open.first { candidate in
            ReminderIdempotency.normalizedTitle(candidate.title) == title && sameDue(candidate.due, write.due)
        }
    }

    /// The read-back shows what was written: same title, same due day and time (and zone when
    /// both have one), and no other Doddy marker. A missing marker is allowed: whether iOS keeps
    /// the URL on a reminder is checked on device, not assumed.
    public static func confirms(_ back: ReminderSnapshot, _ write: ReminderWrite) -> Bool {
        guard !back.isCompleted, back.title == write.title, sameDue(back.due, write.due),
              CalendarRepeat.same(back.repeats, write.repeats) else { return false }
        if let marker = back.markerURL, marker != write.markerURL { return false }
        if let a = back.due?.timeZoneID, let b = write.due?.timeZoneID, a != b { return false }
        return true
    }

    private static func sameDue(_ a: ReminderDue?, _ b: ReminderDue?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): a.sameWallClock(as: b)
        default: false
        }
    }
}

// MARK: Outcome

/// What the screen and the agent are told, from the reminder as read back.
public struct ReminderReceipt: Equatable, Sendable {
    public let title: String
    public let listTitle: String
    public let due: ReminderDue?
    public let repeats: CalendarRepeat?
    /// Reminders' own identifier for it (ADR-319). Stays on this iPhone; never sent to the agent.
    public let id: String?

    public init(title: String, listTitle: String, due: ReminderDue?, repeats: CalendarRepeat? = nil, id: String? = nil) {
        self.title = title
        self.listTitle = listTitle
        self.due = due
        self.repeats = repeats
        self.id = id
    }

    public init(_ snapshot: ReminderSnapshot) {
        self.init(title: snapshot.title, listTitle: snapshot.listTitle, due: snapshot.due, repeats: snapshot.repeats, id: snapshot.id)
    }
}

public enum ReminderFailure: Equatable, Sendable {
    /// Reminders is off in Connections or iOS doesn't allow it.
    case notAllowed
    /// The reminders could not be read before writing, so nothing was written.
    case couldNotCheck
    /// The save failed and a fresh look shows it is not there.
    case saveFailed(String)
}

public enum ReminderOutcome: Equatable, Sendable {
    case added(ReminderReceipt)
    /// The same reminder was already there (from an earlier tap or a retry); nothing new was written.
    case alreadyThere(ReminderReceipt)
    case notAdded(ReminderFailure)
    /// Saved, or maybe saved, but the read-back didn't show it. The user must check first.
    case unknown
    case needsClarification(ReminderClarification)
}

public enum ReminderAction {
    /// Runs after the user tapped Add. Never writes twice for the same reminder, and reports
    /// "added" only from what it read back.
    @MainActor
    public static func add(_ draft: ReminderDraft, to store: some ReminderStore, now: Date) async -> ReminderOutcome {
        if let due = draft.due, let late = ReminderDueRules.passed(due, now: now) {
            return .needsClarification(late)
        }
        let write = ReminderWrite(draft)

        // 1. Look first: an earlier tap or a retry may already have added it.
        let before: [ReminderSnapshot]
        do {
            before = try await store.incompleteReminders()
        } catch ReminderStoreError.notAllowed {
            return .notAdded(.notAllowed)
        } catch {
            return .notAdded(.couldNotCheck)
        }
        if let same = ReminderMatching.existing(for: write, in: before) {
            return .alreadyThere(ReminderReceipt(same))
        }

        // 2. Write.
        let id: String
        do {
            id = try store.save(write)
        } catch ReminderStoreError.notAllowed {
            return .notAdded(.notAllowed)
        } catch {
            // 3a. The save failed, but it may still have gone through: look again before answering.
            guard let after = try? await store.incompleteReminders() else { return .unknown }
            guard let found = ReminderMatching.existing(for: write, in: after) else {
                return .notAdded(.saveFailed(message(for: error)))
            }
            return ReminderMatching.confirms(found, write) ? .added(ReminderReceipt(found)) : .unknown
        }

        // 3b. Read it back and compare.
        guard let after = try? await store.incompleteReminders(),
              let back = after.first(where: { $0.id == id }),
              ReminderMatching.confirms(back, write) else {
            return .unknown
        }
        return .added(ReminderReceipt(back))
    }

    private static func message(for error: Error) -> String {
        if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty { return described }
        return "Reminders couldn't save it."
    }
}

// MARK: Text

public enum ReminderText {
    /// "Mon 12 Oct 2026, 18:00 (Europe/Warsaw)", "Mon 12 Oct 2026" or "No due date".
    public static func due(_ due: ReminderDue?) -> String {
        guard let due else { return "No due date" }
        let calendar = due.calendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM yyyy"
        let noon = calendar.date(from: DateComponents(year: due.year, month: due.month, day: due.day, hour: 12))
        let day = noon.map(formatter.string(from:)) ?? String(due.localText.prefix(10))
        guard let hour = due.hour else { return day }
        let zone = due.timeZoneID.map { " (\($0))" } ?? ""
        return day + String(format: ", %02d:%02d", hour, due.minute ?? 0) + zone
    }

    /// "2026-10-12 18:00 (Europe/Warsaw)" for the agent, which repeats it to the user.
    static func agentDue(_ due: ReminderDue) -> String {
        let zone = due.timeZoneID.map { " (\($0))" } ?? ""
        return due.localText.replacingOccurrences(of: "T", with: " ") + zone
    }
}

/// What the voice screen shows after the user tapped Add.
public struct ReminderScreenText: Equatable, Sendable {
    public let headline: String
    public let lines: [String]
    public let isProblem: Bool
}

extension ReminderOutcome {
    /// `draft` is what the card showed; a receipt shows what was read back instead.
    public func screen(for draft: ReminderDraft) -> ReminderScreenText {
        let asked = ["“\(draft.title)”", ReminderText.due(draft.due)]
        switch self {
        case .added(let receipt):
            return ReminderScreenText(headline: "Added to Reminders", lines: lines(receipt), isProblem: false)
        case .alreadyThere(let receipt):
            return ReminderScreenText(
                headline: "Already in Reminders",
                lines: lines(receipt) + ["Doddy didn't add a second one."], isProblem: false)
        case .notAdded(.notAllowed):
            return ReminderScreenText(
                headline: "Not added",
                // ADR-568: the access card below asks for it; Doddy tries again after the tap.
                lines: asked + ["Doddy isn't allowed to use Reminders yet. Allow it on the card below and Doddy will try again."], isProblem: true)
        case .notAdded(.couldNotCheck):
            return ReminderScreenText(
                headline: "Not added",
                lines: asked + ["Doddy couldn't read your reminders to check it isn't already there, so nothing was added. Try again in a moment."],
                isProblem: true)
        case .notAdded(.saveFailed(let reason)):
            return ReminderScreenText(
                headline: "Not added", lines: asked + ["Reminders didn't save it: \(reason)"], isProblem: true)
        case .unknown:
            return ReminderScreenText(
                headline: "Couldn't confirm",
                lines: asked + ["It may or may not be in Reminders. Check the Reminders app before asking again."], isProblem: true)
        case .needsClarification(let clarification):
            return ReminderScreenText(headline: "Not added", lines: asked + [clarification.screenLine], isProblem: true)
        }
    }

    private func lines(_ receipt: ReminderReceipt) -> [String] {
        ["“\(receipt.title)”", ReminderText.due(receipt.due), "List: \(receipt.listTitle)"]
    }
}

extension VoiceToolReply {
    /// Ends the reply for a reminder that was already there; "What Doddy did" reads it (ActivityEntry).
    static let alreadyInRemindersTail = " was already in Reminders, so Doddy did not add it a second time."

    /// The agent's copy of the outcome. The list name stays on the screen. The title follows as
    /// data (ToolData): one already in Reminders was read back from there.
    public static func reminder(_ outcome: ReminderOutcome) -> String {
        func title(_ receipt: ReminderReceipt) -> String { " Its title:\n" + ToolData.block(["Title: \"\(ToolData.clean(receipt.title))\""]) }
        switch outcome {
        case .added(let receipt):
            return "added: reminder \(dueClause(receipt.due)).\(receipt.repeats.map { " Repeats \($0.text)." } ?? "")" + title(receipt)
        case .alreadyThere(let receipt):
            // The tail stays last, after the data, for "What Doddy did" (ActivityEntry).
            return "added: reminder \(dueClause(receipt.due))." + title(receipt) + "\nThat reminder\(alreadyInRemindersTail)"
        case .notAdded(.notAllowed):
            return notAdded("Reminders isn't connected.")
        case .notAdded(.couldNotCheck):
            return notAdded("the app couldn't read Reminders to check it isn't already there.")
        case .notAdded(.saveFailed(let reason)):
            return notAdded(reason)
        case .unknown:
            // Asking again is safe: ReminderAction looks before it writes (ADR-319).
            return unconfirmedLooksFirst(app: .reminders, tool: VoiceToolName.createReminder)
        case .needsClarification(let clarification):
            return reminderClarification(clarification)
        }
    }

    /// Sent instead of a card, or after the tap if the time passed meanwhile. Starts with
    /// "failed" so the current agent prompt already handles it.
    public static func reminderClarification(_ clarification: ReminderClarification) -> String {
        self.clarification(clarification, tool: VoiceToolName.createReminder)
    }

    /// The same for any tool whose day or time could not be read as it was meant (`tool` is the
    /// one the agent should call again: create_reminder or create_calendar_event).
    /// The problem quotes what the agent sent (said_time, a date it couldn't read), so it follows
    /// as data (ToolData); the question is the app's own words.
    public static func clarification(_ clarification: ReminderClarification, tool: String) -> String {
        "failed: not added yet: the day or time can't be used as sent; the problem is below. Ask the user \(clarification.question), then call \(tool) again with their answer. Nothing was added.\n"
            + problemData(clarification)
    }

    /// `Problem: …` between the data markers.
    static func problemData(_ clarification: ReminderClarification) -> String {
        ToolData.block(["Problem: \(ToolData.clean(clarification.problem))"])
    }

    private static func dueClause(_ due: ReminderDue?) -> String {
        guard let due else { return "with no due time" }
        return "due \(ReminderText.agentDue(due))"
    }
}
