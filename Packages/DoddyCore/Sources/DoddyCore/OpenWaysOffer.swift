import Foundation

// When Doddy offers "Ways to open Doddy" again, and when it sends the weekly reminder (ADR-547).
// Both stop for good once the person is using one of the ways. Pure rules: the app stores the
// state and talks to iOS, this file only decides.
//
// What counts as "using one": Doddy's own "Talk to Doddy" shortcut ran, which is what Back Tap, the
// Action Button, the control and Siri all start (`TalkToDoddyIntent`), or the user said their Back
// Tap test worked. Doddy can tell that the shortcut ran, not which way ran it, and never that a
// setting exists.

/// What is remembered between launches. Contains no words the user said, only counts and flags.
public struct OpenWaysOfferState: Equatable, Codable, Sendable {
    /// How many times the user put the setup off ("Later", "Maybe later", "Set this up later").
    public var deferrals: Int
    /// Conversations that had really connected when they last put it off.
    public var conversationsAtLastDefer: Int
    /// Doddy's shortcut has run at least once (Back Tap, the Action Button, a control or Siri).
    public var usedAWay: Bool
    /// The user turned the weekly reminder off in Settings.
    public var remindersOff: Bool
    /// When the current round of weekly reminders was put in iOS, if one was.
    public var remindersArmedAt: Date?

    public init(
        deferrals: Int = 0, conversationsAtLastDefer: Int = 0, usedAWay: Bool = false,
        remindersOff: Bool = false, remindersArmedAt: Date? = nil
    ) {
        self.deferrals = deferrals
        self.conversationsAtLastDefer = conversationsAtLastDefer
        self.usedAWay = usedAWay
        self.remindersOff = remindersOff
        self.remindersArmedAt = remindersArmedAt
    }

    public mutating func deferred(atConversations count: Int) {
        deferrals += 1
        conversationsAtLastDefer = count
    }

    public mutating func wayUsed() { usedAWay = true }

    /// Switching the reminder on starts a fresh round, so a person who turned it off and on again
    /// gets four new weeks, not the end of an old round.
    public mutating func setReminders(on: Bool) {
        remindersOff = !on
        if on { remindersArmedAt = nil }
    }
}

public enum OpenWaysOffer {
    /// Conversations that must really connect after the person put it off before the Home card
    /// comes back.
    public static let conversationsBeforeAskingAgain = 3
    /// The card comes back once: after the second "later" it stays gone (Settings still has it).
    public static let deferralsBeforeStopping = 2

    /// The person is already using a way, or said their Back Tap test worked.
    public static func isDone(phase: BackTapSetupPhase, state: OpenWaysOfferState) -> Bool {
        if state.usedAWay { return true }
        if case .userReportedTested = phase { return true }
        return false
    }

    /// Whether Home's card is due. The app also requires an iPhone and a first conversation that
    /// connected, so the card never comes before the person has tried talking.
    public static func cardDue(phase: BackTapSetupPhase, state: OpenWaysOfferState, connectedConversations: Int) -> Bool {
        guard !isDone(phase: phase, state: state) else { return false }
        switch phase {
        case .notStarted:
            return true
        case .deferred:
            // A person who put it off before this existed has no count: they count from zero.
            return state.deferrals < deferralsBeforeStopping
                && connectedConversations >= state.conversationsAtLastDefer + conversationsBeforeAskingAgain
        case .guiding, .testing, .receiptReceived, .userReportedTested:
            return false
        }
    }

    /// Whether the weekly reminder should be in iOS now. Nobody gets it before their first
    /// conversation, after turning it off, or once they use a way.
    public static func reminderWanted(phase: BackTapSetupPhase, state: OpenWaysOfferState, connectedConversations: Int) -> Bool {
        guard !state.remindersOff, connectedConversations >= 1 else { return false }
        return !isDone(phase: phase, state: state)
    }
}

/// The weekly reminder: a short local notification that says the same thing each time. It carries
/// no note and no name, and it is never asked for with an iOS permission prompt of its own.
public enum OpenWaysReminder {
    public static let notificationPrefix = "doddy.open-ways.reminder."
    /// One a week for this many weeks, then it stops by itself, even if the app is never opened.
    public static let weeks = 4
    /// Local time of day. Not the hour of Doddy's other weekly notifications (the tidy-up and
    /// look-back are on Sunday evening, the check-in in the morning).
    public static let hour = 11

    public static func isReminder(notificationID: String) -> Bool { notificationID.hasPrefix(notificationPrefix) }

    public static func ids() -> [String] { (1...weeks).map { "\(notificationPrefix)\($0)" } }

    /// The first one lands a week after `now`, then one a week until `weeks` have been set.
    public static func fireDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        (1...weeks).compactMap { week in
            guard let day = calendar.date(byAdding: .day, value: 7 * week, to: now) else { return nil }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }
    }

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Otwieraj Doddy’ego szybciej" : "Open Doddy faster"
    }

    public static func body(_ language: NotificationLanguage) -> String {
        language == .polish
            ? "Stuknij dwa razy w tył iPhone’a, naciśnij przycisk albo zapytaj Siri. Wybierz sposób, kiedy chcesz."
            : "Double-tap the back of your iPhone, press a button or ask Siri. Pick a way whenever you like."
    }
}
