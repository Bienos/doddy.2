import ActivityKit
import Foundation

/// The Live Activity for Doddy's small tools: the focus timer (ADR-241), breathing (ADR-242),
/// reading a note aloud (ADR-243), the kitchen timer and the wind-down (ADR-337) and the short
/// "Note saved" after a save (ADR-338). One type with a `kind`, so the island, the Pause and
/// Stop buttons and the clean-up are shared. Compiled into the app, which starts, updates and
/// ends it, and into the widget extension, which draws it. It carries no note text; the focus
/// or timer line is only what the user typed or said for it, knowing it shows on the Lock Screen.
struct DoddyToolAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable {
        case focus, breathing, readAloud
        /// A plain countdown with an optional label ("Pasta"), by voice or from Home (ADR-337).
        case timer
        /// A quiet countdown before bed, made for StandBy (ADR-337). No label, no fist pump.
        case windDown
        /// Shown for a few seconds after a note is saved and read back (ADR-338). Never its words.
        case noteSaved
    }

    struct ContentState: Codable, Hashable {
        var isPaused: Bool
        /// When the countdown reaches zero (running focus, breathing); nil otherwise.
        var endsAt: Date?
        /// Time left while a focus is paused.
        var remaining: TimeInterval = 0
        /// Focus and timer only: the line the user typed or said.
        var label: String?
        /// The time ran out, the exercise ended or the note was read to the end.
        var isFinished = false
        /// The island style picked in Settings when this was sent (ADR-299): with Whole Doddy the
        /// read-aloud island shows his reading pose. Nil from older builds: the board's art.
        var islandStyle: IslandStyle?
    }

    var kind: Kind
    var startedAt: Date
    /// Focus and breathing: the length chosen.
    var duration: TimeInterval
}
