import Foundation

// Sport mode step 5 (ADR-626): asking for a plan by voice or in Messages (owner, 25 Oct 2026: "okej" to
// "Plan zamawiany głosem albo w Wiadomościach"). Both ways end at the same screen. What a model may
// pass on is a PlanAsk: a goal, and optionally the days a week and the minutes a session the person
// said. It carries no safety answer, no age, no level and no injury: those are asked on the screen, of
// the person, and never reach a model. A model proposes; the person taps; the engine makes the plan.

/// A request for the plan screen, opened with a goal (and maybe days and minutes) already chosen.
public struct PlanAsk: Equatable, Sendable, Codable {
    public let goal: PlanGoal
    /// nil when the person didn't say, or said a number the plan screen doesn't offer: the screen's own default.
    public let daysPerWeek: Int?
    public let minutesPerSession: Int?

    /// The names a model uses for a goal, in the voice tool and in a Messages answer.
    public static let goalNames: [(name: String, goal: PlanGoal)] = [
        ("first_5k", .firstFiveK), ("10k", .tenK), ("half_marathon", .halfMarathon),
        ("strength_home", .strengthHome), ("strength_gym", .strengthGym),
    ]

    /// What the plan screen's steppers offer. Running: 2 to 5 days. Strength: 2 to 4.
    public static func daysRange(for goal: PlanGoal) -> ClosedRange<Int> { 2...(goal.isRunning ? 5 : 4) }
    public static let minutesRange = 20...150
    public static let minutesStep = 5

    public static func goal(named name: String) -> PlanGoal? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return goalNames.first { $0.name == key }?.goal
    }

    public static func name(of goal: PlanGoal) -> String {
        goalNames.first { $0.goal == goal }?.name ?? ""
    }

    /// nil unless the goal is one of the five. Days and minutes outside what the screen offers become nil
    /// (the screen's default), never clamped: the card and the voice's reply show only what was kept.
    /// Minutes are rounded to the nearest 5, as the screen's stepper counts.
    public static func make(goalName: String, daysPerWeek: Int?, minutesPerSession: Int?) -> PlanAsk? {
        guard let goal = goal(named: goalName) else { return nil }
        let days = daysPerWeek.flatMap { daysRange(for: goal).contains($0) ? $0 : nil }
        let minutes = minutesPerSession.flatMap { value -> Int? in
            let rounded = Int((Double(value) / Double(minutesStep)).rounded()) * minutesStep
            return minutesRange.contains(rounded) ? rounded : nil
        }
        return PlanAsk(goal: goal, daysPerWeek: days, minutesPerSession: minutes)
    }

    /// The card's lines: what is filled in, and that the safety questions come next, on the screen.
    public var cardLines: [String] {
        var lines = ["Goal: " + Self.goalTitle(goal)]
        var week: [String] = []
        if let daysPerWeek { week.append("\(daysPerWeek) days a week") }
        if let minutesPerSession { week.append("\(minutesPerSession) min a session") }
        if !week.isEmpty { lines.append(week.joined(separator: ", ")) }
        lines.append("You answer the safety questions yourself, on screen.")
        return lines
    }

    public static func goalTitle(_ goal: PlanGoal) -> String {
        switch goal {
        case .firstFiveK: "First 5 km"
        case .tenK: "10 km"
        case .halfMarathon: "Half marathon"
        case .strengthHome: "Strength at home"
        case .strengthGym: "Strength at the gym"
        }
    }
}
