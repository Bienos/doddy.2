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
        /// A stopwatch that counts up (ADR-614).
        case stopwatch
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
        /// The island style picked in Settings when this was sent (ADR-299): with Whole Doddy the
        /// read-aloud island shows his reading pose. Nil from older builds: the board's art.
        var islandStyle: IslandStyle?
        /// Stopwatch only (ADR-614): when a clock that counts up from zero would have started to
        /// show the time so far; the Lock Screen's text ticks from it with no updates from the app.
        /// Nil while paused or stopped.
        var countsFrom: Date?
        /// Stopwatch only: the time counted so far, shown while paused and after it was stopped.
        var elapsed: TimeInterval?
    }

    var kind: Kind
    var startedAt: Date

    /// Where the count-up clock starts: a stopwatch's moves with every pause and resume, so it
    /// comes from the state; everything else counts from `startedAt`.
    func clockStart(_ state: ContentState) -> Date {
        kind == .stopwatch ? (state.countsFrom ?? startedAt) : startedAt
    }
    /// Focus and breathing: the length chosen.
    var duration: TimeInterval
}
