import ActivityKit
import Foundation

/// The Live Activity for Doddy's small tools: the focus timer (ADR-241), breathing (ADR-242)
/// and reading a note aloud (ADR-243). One type with a `kind`, so the island, the Pause and
/// Stop buttons and the clean-up are shared. Compiled into the app, which starts, updates and
/// ends it, and into the widget extension, which draws it. It carries no note text; the focus
/// line is only what the user typed for it, knowing it shows on the Lock Screen.
struct DoddyToolAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable {
        case focus, breathing, readAloud
    }

    struct ContentState: Codable, Hashable {
        var isPaused: Bool
        /// When the countdown reaches zero (running focus, breathing); nil otherwise.
        var endsAt: Date?
        /// Time left while a focus is paused.
        var remaining: TimeInterval = 0
        /// Focus only: the line the user typed.
        var label: String?
        /// The time ran out, the exercise ended or the note was read to the end.
        var isFinished = false
    }

    var kind: Kind
    var startedAt: Date
    /// Focus and breathing: the length chosen.
    var duration: TimeInterval
}
