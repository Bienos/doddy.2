import Foundation

// Sport mode step 2 (ADR-622): "How did my week go?" The iPhone works out the week's numbers from
// Apple Health (HealthGlance), and the person may send a short summary of them to Doddy in Messages,
// where Claude answers (ADR-620, decision 2). Only the text the person saw is sent, only after a
// consent of its own and their own tap on Send. Nothing is sent by these rules: they only count
// and assemble the words.

extension HealthWindow {
    /// The seven days before `lastDays`: the week the summary compares with.
    public static func previousDays(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let current = lastDays(now: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -days, to: current.start) ?? current.start
        return (start, current.start)
    }
}

/// A week of workouts added up.
public struct WeekTotals: Equatable, Sendable {
    public let workouts: Int
    public let duration: TimeInterval
    /// Running only, the runs that have a distance.
    public let runningMeters: Double
    let runningSecondsWithDistance: TimeInterval

    public init(workouts: Int, duration: TimeInterval, runningMeters: Double, runningSecondsWithDistance: TimeInterval) {
        self.workouts = workouts
        self.duration = duration
        self.runningMeters = runningMeters
        self.runningSecondsWithDistance = runningSecondsWithDistance
    }

    public static let none = WeekTotals(workouts: 0, duration: 0, runningMeters: 0, runningSecondsWithDistance: 0)

    /// The average running pace over the runs with a distance, when they add up to 100 m or more.
    public var runningPaceSecondsPerKilometre: Double? {
        guard runningMeters >= 100, runningSecondsWithDistance > 0 else { return nil }
        return runningSecondsWithDistance / (runningMeters / 1000)
    }

    /// The workouts that ended inside the window, the same rule as `HealthWorkout.recent`, with no limit.
    public static func of(_ workouts: [HealthWorkout], in window: (start: Date, end: Date)) -> WeekTotals {
        let inside = workouts.filter { $0.end > window.start && $0.end <= window.end && $0.duration > 0 }
        let runs = inside.filter { $0.activity == .running && $0.distanceMeters != nil }
        return WeekTotals(
            workouts: inside.count,
            duration: inside.reduce(0) { $0 + $1.duration },
            runningMeters: runs.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
            runningSecondsWithDistance: runs.reduce(0) { $0 + $1.duration })
    }
}

/// The person's yes to sending a summary of Health data to Doddy's server and Claude. A new
/// wording of the consent screen raises `version`, and an older yes no longer counts.
public enum HealthShareConsent {
    public static let version = 1

    public static func isGranted(storedVersion: Int) -> Bool { storedVersion >= version }
}

public enum HealthShareText {
    /// The message as it will be sent: the question, the workout lines, then the other lines. When it
    /// is longer than Messages allows, the oldest workouts (the end of `workoutLines`) are left out one
    /// by one and `leftOut(count)` says how many. Nil if even the question and the other lines don't
    /// fit, so nothing half-cut is ever offered.
    public static func assemble(question: String, workoutLines: [String], otherLines: [String],
                                leftOut: (Int) -> String, limit: Int = AssistantLimits.maxQuestionLength) -> String? {
        func join(_ workouts: [String], dropped: Int) -> String {
            var lines = [question, ""]
            lines += workouts
            if dropped > 0 { lines.append(leftOut(dropped)) }
            lines += otherLines
            return lines.joined(separator: "\n")
        }
        var kept = workoutLines
        while true {
            let text = join(kept, dropped: workoutLines.count - kept.count)
            if text.unicodeScalars.count <= limit { return text }
            if kept.isEmpty { return nil }
            kept.removeLast()
        }
    }
}
