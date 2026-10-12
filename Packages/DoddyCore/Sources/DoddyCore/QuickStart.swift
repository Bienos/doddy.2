import Foundation

// Quick start (ADR-324). The last first-use screen, shown once after the introduction: the
// opt-in settings that make Doddy easier to live with, each one tap away instead of buried in
// Settings. Nothing changes until the user taps the button. An unticked item is left exactly as
// it is (never turned off), and so is one already on (its own time is kept). The notifications are
// pre-ticked: they stay on this iPhone, never show a note, and iOS itself asks before any of them
// can ring. The evening wrap-up only when Reminders is connected: without it, its screen has
// nothing to show. Using the "About you"
// answers in voice conversations sends them to ElevenLabs, so it is never pre-ticked and is only
// offered when there are saved answers to send.

public struct QuickStartChoices: Equatable, Sendable {
    public var morningCheckIn: Bool
    public var eveningWrapUp: Bool
    public var weeklyTidyUp: Bool
    public var weeklyLookBack: Bool
    public var useProfileInVoice: Bool

    public init(morningCheckIn: Bool, eveningWrapUp: Bool, weeklyTidyUp: Bool, weeklyLookBack: Bool, useProfileInVoice: Bool) {
        self.morningCheckIn = morningCheckIn
        self.eveningWrapUp = eveningWrapUp
        self.weeklyTidyUp = weeklyTidyUp
        self.weeklyLookBack = weeklyLookBack
        self.useProfileInVoice = useProfileInVoice
    }

    /// What the screen starts with ticked. `remindersConnected`: Reminders is on in Connections and
    /// iOS allows it, the same test the wrap-up screen makes.
    public static func suggested(remindersConnected: Bool) -> QuickStartChoices {
        QuickStartChoices(
            morningCheckIn: true, eveningWrapUp: remindersConnected, weeklyTidyUp: true, weeklyLookBack: true,
            useProfileInVoice: false)
    }

    public var anyNotification: Bool { morningCheckIn || eveningWrapUp || weeklyTidyUp || weeklyLookBack }
}

public enum QuickStart {
    /// 08:00 on weekdays, 21:00 every day, Sunday at 18:00, and the look-back Sunday at 19:00 so it
    /// never arrives in the same minute as the tidy-up (owner, 2026-10-11).
    public static let morning = MorningCheckInSettings(isOn: true, hour: 8, minute: 0, weekdaysOnly: true)
    public static let evening = EveningWrapUpSettings(isOn: true, hour: 21, minute: 0)
    public static let tidyUp = TidyUpSettings(isOn: true, weekday: 1, hour: 18, minute: 0)
    public static let lookBack = WeeklyLookBackSettings(isOn: true, weekday: 1, hour: 19, minute: 0)

    /// What to apply. `nil` means leave that setting as it is.
    public struct Plan: Equatable, Sendable {
        public var morning: MorningCheckInSettings?
        public var evening: EveningWrapUpSettings?
        public var tidyUp: TidyUpSettings?
        public var lookBack: WeeklyLookBackSettings?
        public var useProfileInVoice: Bool

        public var isEmpty: Bool { morning == nil && evening == nil && tidyUp == nil && lookBack == nil && !useProfileInVoice }
    }

    /// What is on already, read from the stored settings when the screen opens.
    public struct Current: Equatable, Sendable {
        public var morningCheckIn: Bool
        public var eveningWrapUp: Bool
        public var weeklyTidyUp: Bool
        public var weeklyLookBack: Bool
        public var useProfileInVoice: Bool

        public init(morningCheckIn: Bool, eveningWrapUp: Bool, weeklyTidyUp: Bool, weeklyLookBack: Bool, useProfileInVoice: Bool) {
            self.morningCheckIn = morningCheckIn
            self.eveningWrapUp = eveningWrapUp
            self.weeklyTidyUp = weeklyTidyUp
            self.weeklyLookBack = weeklyLookBack
            self.useProfileInVoice = useProfileInVoice
        }

        public static let nothingOn = Current(
            morningCheckIn: false, eveningWrapUp: false, weeklyTidyUp: false, weeklyLookBack: false, useProfileInVoice: false)
    }

    /// Profile sharing is applied only when there are saved answers, whatever the choice says.
    /// Anything already on is left out, so a time the user picked in Settings is never replaced.
    public static func plan(_ choices: QuickStartChoices, profileSaved: Bool, current: Current = .nothingOn) -> Plan {
        Plan(
            morning: choices.morningCheckIn && !current.morningCheckIn ? morning : nil,
            evening: choices.eveningWrapUp && !current.eveningWrapUp ? evening : nil,
            tidyUp: choices.weeklyTidyUp && !current.weeklyTidyUp ? tidyUp : nil,
            lookBack: choices.weeklyLookBack && !current.weeklyLookBack ? lookBack : nil,
            useProfileInVoice: choices.useProfileInVoice && profileSaved && !current.useProfileInVoice)
    }

    /// One item's result, from what iOS or the store read back. Only `.set` may be reported as on.
    public enum Outcome: Equatable, Sendable {
        case set
        case needsPermission
        case failed
    }
}
