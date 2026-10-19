import Foundation

/// iOS keeps at most 64 pending local notification requests per app. Past that it keeps the 64
/// that fire soonest and quietly drops the rest, with no error; a repeating request counts once.
/// Every Doddy notification shares that one pool. The kinds a person sets up themselves (note
/// reminders and birthdays) check here before adding, so together they never push the pool past
/// the limit and nothing is dropped without a word: the person is told the limit instead
/// (ADR-523).
public enum NotificationBudget {
    /// iOS's limit per app.
    public static let systemLimit = 64

    /// Always left free for what Doddy schedules on its own or for a short time: the morning
    /// check-in (up to 5), the evening wrap-up, weekly look-back and tidy-up (1 each), plus
    /// timers, focus, leave-by, snoozes and event nudges.
    public static let reserved = 14

    /// The kinds a person sets up themselves, which share what `reserved` leaves.
    public enum Kind: Sendable {
        case noteReminders, birthdays
    }

    /// How many pending requests `kind` may hold right now: the limit, minus what the other
    /// user-set kind holds, minus what everything else holds (never less than `reserved`).
    /// `pending` is every identifier iOS lists as pending for the app; `kind`'s own requests in
    /// it are ignored, because the caller counts those itself.
    public static func room(for kind: Kind, pending: some Sequence<String>) -> Int {
        var otherUserSet = 0
        var everythingElse = 0
        for identifier in pending {
            switch Self.kind(of: identifier) {
            case kind?: continue
            case .some: otherUserSet += 1
            case nil: everythingElse += 1
            }
        }
        return max(0, systemLimit - max(reserved, everythingElse) - otherUserSet)
    }

    /// Which user-set kind a pending identifier belongs to, if any.
    public static func kind(of identifier: String) -> Kind? {
        if identifier.hasPrefix(MemoryReminder.notificationPrefix) { return .noteReminders }
        if Birthdays.isBirthday(notificationID: identifier) { return .birthdays }
        return nil
    }
}
