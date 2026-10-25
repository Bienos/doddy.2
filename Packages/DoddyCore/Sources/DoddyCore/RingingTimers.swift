import Foundation

// Timers that ring, and how loudly each Doddy notification may come through (ADR-650).
//
// Before ADR-650 a voice timer was an ordinary notification with the short default sound: in
// Silent mode it only buzzed, a Focus held it back completely, and nothing showed the time left
// on the Lock Screen. On iOS 26 a timer now goes to AlarmKit, which rings it like the Clock app's
// timer (through Silent mode and a Focus) and shows the countdown on the Lock Screen and in the
// Dynamic Island. Older iPhones, or anyone who refused alarms, still get the notification, now
// marked Time Sensitive. The plain rules are here for the Linux tests; AlarmKit and
// UserNotifications are only on the iPhone (`TimerRinger`, `DeviceConnections`).

// MARK: How a timer rings

/// How a running timer will reach the user. Told to the agent so it never promises a ring the
/// iPhone can't make.
public enum TimerRing: String, Codable, Equatable, Sendable {
    /// AlarmKit: rings like the Clock app's timer, even in Silent mode or a Focus.
    case alarm
    /// A Time Sensitive notification: it gets through a Focus where iOS allows it, but in Silent
    /// mode it only vibrates.
    case notification
}

extension TimerIdempotency {
    /// The UUID at the end of a Doddy timer identifier. AlarmKit timers use it as their id, so the
    /// identifier the action status model reads back (ADR-320) names the same timer.
    public static func alarmID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix), let dot = identifier.lastIndex(of: ".") else { return nil }
        return UUID(uuidString: String(identifier[identifier.index(after: dot)...]))
    }
}

/// A timer Doddy handed to AlarmKit, as noted on this iPhone (UserDefaults) so it can be found and
/// named again. AlarmKit is the truth about whether it still runs; this only remembers what was
/// asked (the identifier with its key, the ring time and the label).
public struct RingingTimer: Codable, Equatable, Sendable {
    public let alarmID: UUID
    public let identifier: String
    public let firesAt: Date
    public let label: String?
    /// When Doddy noted it, before AlarmKit was asked.
    public let noted: Date

    public init(alarmID: UUID, identifier: String, firesAt: Date, label: String?, noted: Date) {
        self.alarmID = alarmID
        self.identifier = identifier
        self.firesAt = firesAt
        self.label = label
        self.noted = noted
    }

    public var pending: PendingTimer { PendingTimer(identifier: identifier, firesAt: firesAt, ring: .alarm) }
}

public enum RingingTimerBook {
    /// How long a note is kept although AlarmKit doesn't list it: AlarmKit may list a timer it has
    /// just been given a moment late, and a retry must still find it (as for alarms, ADR-320).
    public static let grace: TimeInterval = 600

    /// The notes worth keeping: timers AlarmKit still lists, and any noted in the last `grace`.
    public static func kept(_ notes: [RingingTimer], listed: Set<UUID>, now: Date) -> [RingingTimer] {
        notes.filter { listed.contains($0.alarmID) || now.timeIntervalSince($0.noted) < grace }
    }

    /// Doddy's timers AlarmKit lists, soonest first. A note AlarmKit doesn't list is not running.
    public static func pending(_ notes: [RingingTimer], listed: Set<UUID>) -> [PendingTimer] {
        notes.filter { listed.contains($0.alarmID) }.sorted { $0.firesAt < $1.firesAt }.map(\.pending)
    }
}

// MARK: How loudly a notification comes through

/// iOS's interruption levels, without UserNotifications (the app maps them).
public enum NotificationUrgency: String, Equatable, Sendable {
    /// Breaks through a Focus where the user allows Time Sensitive notifications, and is not held
    /// for the scheduled summary. Only for a moment the user set themselves.
    case timeSensitive
    /// iOS's usual: the screen lights up, but a Focus holds it.
    case active
}

/// Every notification Doddy schedules on the iPhone, with how it may come through (ADR-650).
/// Only what the user set for a moment is Time Sensitive; Doddy's own routines never push through
/// a Focus (no pressure, DOD-10 nonmanipulative_companionship).
public enum DoddyNotificationKind: String, CaseIterable, Sendable {
    case timer, focusDone, noteReminder, leaveBy, eventNudge
    case morningCheckIn, eveningWrapUp, weeklyLookBack, tidyUp, birthday, openWays
    /// The Monday plan (ADR-651).
    case weeklyPlan

    public var urgency: NotificationUrgency {
        switch self {
        case .timer, .focusDone, .noteReminder, .leaveBy, .eventNudge: .timeSensitive
        case .morningCheckIn, .eveningWrapUp, .weeklyLookBack, .tidyUp, .birthday, .openWays, .weeklyPlan: .active
        }
    }

    /// Whether it plays the notification sound. The evening, weekly and tidy-up routines arrive
    /// without one, as they always have, and so does the weekly plan.
    public var playsSound: Bool {
        switch self {
        case .eveningWrapUp, .weeklyLookBack, .tidyUp, .weeklyPlan: false
        default: true
        }
    }
}

// MARK: Words

/// What a timer and the focus timer say on the iPhone, in its language (Polish or English, as
/// the other notifications, ADR-213). Only the label the user asked for, never a note.
public enum TimerCopy {
    public enum Button: Sendable {
        case stop, repeatTimer, pause, resume
    }

    /// The ringing timer's title in AlarmKit, and the notification's title.
    public static func title(label: String?, _ language: NotificationLanguage) -> String {
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        return language == .polish ? "Minutnik" : "Timer"
    }

    /// The notification a timer falls back to (no AlarmKit).
    public static func notificationTitle(_ language: NotificationLanguage) -> String {
        language == .polish ? "Czas minął" : "Time's up"
    }

    public static func notificationBody(label: String?, seconds: Int, _ language: NotificationLanguage) -> String {
        let length = shortDuration(seconds, language)
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return language == .polish ? "\(label) · minutnik na \(length)" : "\(label) · \(length) timer"
        }
        return language == .polish ? "Minutnik na \(length) skończył odliczanie." : "Your \(length) timer is done."
    }

    public static func button(_ button: Button, _ language: NotificationLanguage) -> String {
        switch (button, language) {
        case (.stop, .polish): "Zatrzymaj"
        case (.stop, .english): "Stop"
        case (.repeatTimer, .polish): "Powtórz"
        case (.repeatTimer, .english): "Repeat"
        case (.pause, .polish): "Pauza"
        case (.pause, .english): "Pause"
        case (.resume, .polish): "Wznów"
        case (.resume, .english): "Resume"
        }
    }

    public static func paused(_ language: NotificationLanguage) -> String {
        language == .polish ? "Pauza" : "Paused"
    }

    public static func focusTitle(_ language: NotificationLanguage) -> String {
        language == .polish ? "Koniec skupienia" : "Focus done"
    }

    public static func focusBody(label: String?, minutes: Int, _ language: NotificationLanguage) -> String {
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        return language == .polish ? "Minęło \(minutes) min skupienia." : "Your \(minutes)-minute focus is over."
    }

    /// "10 min", "1 h 30 min", "45 s": short, so Polish needs no plural forms.
    public static func shortDuration(_ seconds: Int, _ language: NotificationLanguage) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3_600, minutes = (seconds % 3_600) / 60, rest = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) h") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if rest > 0 || parts.isEmpty { parts.append("\(rest) s") }
        return parts.joined(separator: " ")
    }
}
