import Foundation

// Alarms by voice (ADR-260). "Wake me at seven" becomes a real alarm, the kind that rings through
// Silent mode and Focus, set with Apple's AlarmKit on iOS 26 and later. Only the phone app uses
// AlarmKit (DoddyApp/Features/Alarms); this file is the plain-Swift part the Linux tests cover:
// the tool's arguments, the rules, and what the agent is told. Like every other write, the alarm
// is shown on a card first and set only on Set alarm; then AlarmKit is asked whether it has it.
// On an older iOS the agent is told alarms need iOS 26, and offers a timer or a reminder.

extension VoiceToolName {
    public static let setAlarm = "set_alarm"
}

/// Which days a repeating alarm rings on.
public enum AlarmRepeat: String, CaseIterable, Equatable, Sendable {
    case everyDay = "every_day"
    case weekdays
    case weekends

    /// Gregorian weekday numbers (1 = Sunday … 7 = Saturday).
    public var weekdays: [Int] {
        switch self {
        case .everyDay: [1, 2, 3, 4, 5, 6, 7]
        case .weekdays: [2, 3, 4, 5, 6]
        case .weekends: [1, 7]
        }
    }

    public var text: String {
        switch self {
        case .everyDay: "every day"
        case .weekdays: "on weekdays"
        case .weekends: "at weekends"
        }
    }
}

/// An alarm the agent proposed. Nothing is set until the user taps Set alarm on the card.
public struct AlarmDraft: Equatable, Sendable {
    public static let maxLabelLength = 60
    /// Snooze on a Doddy alarm rings again after this many minutes (ADR-283).
    public static let snoozeMinutes = 9

    /// The first time it rings, as the user's wall clock. For a repeating alarm, the day it was
    /// asked for; AlarmKit then rings at `hour`:`minute` on every matching day.
    public let first: ReminderDue
    public let repeats: AlarmRepeat?
    public let label: String?

    public init(first: ReminderDue, repeats: AlarmRepeat?, label: String?) {
        self.first = first
        self.repeats = repeats
        self.label = label
    }

    public var hour: Int { first.hour ?? 0 }
    public var minute: Int { first.minute ?? 0 }
    public var clock: String { String(format: "%02d:%02d", hour, minute) }

    /// "07:00, 2026-10-12" or "07:00 on weekdays", for the agent and the log.
    public var summary: String {
        if let repeats { return "\(clock) \(repeats.text)" }
        return "\(clock) on \(first.localText.prefix(10))"
    }
}

/// What the app says about alarms on this iPhone, before any card is shown.
public enum AlarmSupport: Equatable, Sendable {
    case available
    /// iOS older than 26: no AlarmKit.
    case needsNewerIOS
    /// The user said no to alarms in iOS Settings.
    case notAllowed
}

extension VoiceToolRequest {
    /// `time` (YYYY-MM-DDTHH:MM, local, later than now), optional `repeat` and `label`.
    static func parseAlarm(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let timeText = args.text("time") else { return .invalid(name: name, reason: "missing time") }
        let first: ReminderDue
        switch ReminderDueRules.check(timeText, now: now, calendar: calendar) {
        case .due(let due): first = due
        case .clarify(let clarification): return .needsClarification(name: name, clarification)
        }
        guard first.hasTime else { return .invalid(name: name, reason: "time needs a time of day (YYYY-MM-DDTHH:MM)") }
        var repeats: AlarmRepeat?
        if let repeatText = args.text("repeat") {
            guard let parsed = AlarmRepeat(rawValue: repeatText) else {
                return .invalid(name: name, reason: "repeat must be every_day, weekdays or weekends")
            }
            repeats = parsed
        }
        let label = args.text("label").map { String($0.prefix(AlarmDraft.maxLabelLength)) }
        return .setAlarm(AlarmDraft(first: first, repeats: repeats, label: label))
    }
}

extension VoiceToolReply {
    public static func alarmSet(_ draft: AlarmDraft) -> String {
        let what = draft.label.map { "\"\($0)\" " } ?? ""
        return "added: alarm \(what)at \(draft.summary). It rings even in Silent mode or a Focus. Checked."
    }

    public static let alarmNeedsNewerIOS = "failed: alarms need iOS 26 or later, and this iPhone has an older version. Nothing was set. Offer a timer (up to 24 hours) or a reminder instead."
    public static let alarmNotAllowed = "failed: Doddy isn't allowed to set alarms on this iPhone (iOS Settings, Doddy, Alarms). Nothing was set. Tell the user where to turn it on."
    public static let declinedAlarm = "declined: the user chose not to set this alarm. Nothing was set."
    public static let alarmUnconfirmed = "unknown: the iPhone didn't confirm the alarm. Ask the user to check before trying again."
}

// MARK: Asking about and turning off alarms by voice (ADR-283)

extension VoiceToolName {
    public static let listAlarms = "list_alarms"
    public static let cancelAlarm = "cancel_alarm"
}

/// One of Doddy's alarms as the iPhone keeps it: AlarmKit's id, and the time and label Doddy
/// remembered when it set it. Only alarms Doddy set; the Clock app's alarms aren't visible.
public struct AlarmEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// "07:00".
    public let clock: String
    public let label: String?
    /// "07:00 on weekdays" or "07:00 on 2026-10-12".
    public let summary: String
    /// `AlarmIdempotency.key` of the draft it was set from (ADR-292). Nil for alarms set before.
    public let key: String?

    public init(id: UUID, clock: String, label: String?, summary: String, key: String? = nil) {
        self.id = id
        self.clock = clock
        self.label = label
        self.summary = summary
        self.key = key
    }
}

public enum AlarmMatch {
    /// Alarms at this time (HH:MM), narrowed by the label when one is given; nothing guessed.
    public static func match(clock: String, label: String?, in alarms: [AlarmEntry]) -> ListMatchResult<AlarmEntry> {
        var found = alarms.filter { $0.clock == clock }
        if let label, !label.isEmpty {
            let wanted = SearchFolding.tokens(label).joined(separator: " ")
            let named = found.filter { SearchFolding.tokens($0.label ?? "").joined(separator: " ") == wanted }
            if !named.isEmpty { found = named }
        }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// "HH:MM" from "7:05", "07:05" or "07:05:00"; nil otherwise.
    public static func clock(_ text: String) -> String? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2 || parts.count == 3, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }
}

extension VoiceToolRequest {
    static func parseCancelAlarm(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let text = args.text("time"), let clock = AlarmMatch.clock(text) else {
            return .invalid(name: name, reason: "time is the alarm's time as HH:MM")
        }
        return .cancelAlarm(clock: clock, label: args.text("label"))
    }
}

extension VoiceToolReply {
    public static func alarms(_ alarms: [AlarmEntry]) -> String {
        guard !alarms.isEmpty else { return "alarms: none set by Doddy. (Alarms from the Clock app aren't visible to Doddy.)" }
        let lines = alarms.map { alarm in alarm.summary + (alarm.label.map { " (\"\($0)\")" } ?? "") }
        return "alarms set by Doddy: \(lines.joined(separator: "; ")). (Alarms from the Clock app aren't visible to Doddy.)"
    }

    public static func alarmNotFound(_ clock: String) -> String {
        "not found: Doddy has no alarm at \(clock). Nothing changed. (Doddy can't see or change the Clock app's alarms.)"
    }

    public static func alarmAmbiguous(_ alarms: [AlarmEntry]) -> String {
        "not changed: more than one alarm matches (\(alarms.map(\.summary).joined(separator: "; "))). Ask the user which one."
    }

    public static func alarmCancelled(_ alarm: AlarmEntry) -> String {
        "turned off: the alarm at \(alarm.summary) is off. Checked."
    }

    public static let alarmCancelDeclined = "declined: the user kept the alarm. Nothing changed."
    public static let alarmCancelUnconfirmed = "unknown: the iPhone didn't confirm the alarm is off. Ask the user to check Settings, Alarms in Doddy."
}
