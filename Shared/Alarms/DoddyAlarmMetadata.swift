#if canImport(AlarmKit)
import AlarmKit

/// What Doddy's alarms and timers carry for their system screens (ADR-260, ADR-283, ADR-607):
/// only whether it is a timer, nothing personal. It is shared by the app, which sets them, and the
/// widget extension, which draws the countdown. AlarmKit is allowed only here (`Shared/Alarms`),
/// in `DoddyApp/Features/Alarms` and in the widget's `AlarmLiveActivity.swift`
/// (scripts/check_forbidden_capabilities.sh).
@available(iOS 26.0, *)
struct DoddyAlarmMetadata: AlarmMetadata {
    enum Kind: String, Codable, Hashable, Sendable {
        case timer
    }

    /// `timer` for a voice timer (ADR-607); nil for an alarm, including every alarm set before.
    var kind: Kind? = nil
    /// The language the app set it in (`NotificationLanguage` raw value), so the card's buttons
    /// use the same words as the ringing screen.
    var language: String? = nil
}
#endif
