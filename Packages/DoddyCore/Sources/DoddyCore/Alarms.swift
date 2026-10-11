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
