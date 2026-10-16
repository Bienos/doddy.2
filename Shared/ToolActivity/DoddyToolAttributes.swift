import ActivityKit
import Foundation

/// The Live Activity for Doddy's small tools: the kitchen timer, focus timer (ADR-241),
/// breathing (ADR-242) and reading a note aloud (ADR-243). One type with a `kind`, so the island,
/// controls and renderer are shared. It carries no private note, transcript or timer label.
struct DoddyToolAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable {
        case timer, focus, breathing, readAloud
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
        /// A failed stop read-back must never make the island claim the timer was cancelled.
        var cancellationUnconfirmed: Bool? = nil
        /// The island style picked in Settings when this was sent (ADR-299): with Whole Doddy the
        /// read-aloud island shows his reading pose. Nil from older builds: the board's art.
        var islandStyle: IslandStyle?
    }

    var kind: Kind
    var startedAt: Date
    /// Focus and breathing: the length chosen.
    var duration: TimeInterval
    /// Local notification id is a non-content identifier used to cancel one exact timer.
    var timerNotificationID: String? = nil
}
