import Foundation

/// A broken safety rule in a plan (ADR-624). The engine's own plans have none; any plan that comes
/// from elsewhere (a model's rewording, a person's edit) is checked against the same rules before it
/// is shown as Doddy's.
public enum PlanViolation: Equatable, Sendable {
    /// A run more than 10% longer than the longest of the four weeks before it (or the starting run).
    case runTooLong(week: Int, day: Int)
    /// More than 20% of the week's running time at hard effort.
    case tooMuchHard(week: Int)
    /// A hard session or the long run the day right after a hard session.
    case hardBackToBack(week: Int, day: Int)
    /// Two full-body strength days in a row.
    case strengthBackToBack(week: Int, day: Int)
    case tooManyDays(week: Int)
    /// A weekday session longer than the person said they have; the long run may be longer.
    case weekdayTooLong(week: Int, day: Int)
    /// Fewer than 2 reps in reserve, more than 5 sets, or (16 and 17) fewer than 10 reps a set.
    case strengthTooHard(week: Int, day: Int, exercise: String)
}

public enum PlanRules {
    public static func violations(_ plan: TrainingPlan) -> [PlanViolation] {
        var found: [PlanViolation] = []
        let request = plan.request
        let allowedDays = request.goal.isRunning ? min(request.daysPerWeek, 5) : min(request.daysPerWeek, 4)
        var previousWeeks: [[PlanSession]] = []
        var lastHardDay: Int? // days counted from the plan's start

        for week in plan.weeks {
            let sessions = week.sessions.sorted { $0.day < $1.day }
            if sessions.count > allowedDays { found.append(.tooManyDays(week: week.number)) }

            // The longest-run rule, against the four weeks before (about 30 days) and the start.
            let recent = previousWeeks.suffix(4).flatMap { $0 }.filter(\.isRun).map(\.timeOnFeetSeconds)
            let reference = (recent + (plan.baselineRunMinutes.map { [$0 * 60] } ?? [])).max()
            for session in sessions where session.isRun {
                if let reference, Double(session.timeOnFeetSeconds) > Double(reference) * 1.1 + 0.5 {
                    found.append(.runTooLong(week: week.number, day: session.day))
                }
                if session.kind != .longRun, session.minutes > request.minutesPerSession {
                    found.append(.weekdayTooLong(week: week.number, day: session.day))
                }
            }

            // 80/20 for distance plans; run/walk weeks have no hard minutes.
            let runMinutes = sessions.filter(\.isRun).reduce(0) { $0 + $1.minutes }
            let hardMinutes = sessions.reduce(0) { $0 + $1.hardMinutes }
            if runMinutes > 0, Double(hardMinutes) > 0.2 * Double(runMinutes) { found.append(.tooMuchHard(week: week.number)) }

            // Spacing: nothing hard, long run included, the day after a hard session.
            for session in sessions where session.isRun {
                let absolute = (week.number - 1) * 7 + session.day
                if let hard = lastHardDay, absolute - hard == 1, session.isHard || session.kind == .longRun {
                    found.append(.hardBackToBack(week: week.number, day: session.day))
                }
                if session.isHard { lastHardDay = absolute }
            }

            // Strength: full-body days apart; every set stopped short of failure.
            let fullBody = sessions.filter { $0.kind == .strength && isFullBody($0) }
            for (first, second) in zip(fullBody, fullBody.dropFirst()) where second.day - first.day == 1 {
                found.append(.strengthBackToBack(week: week.number, day: second.day))
            }
            for session in sessions where session.kind == .strength {
                for exercise in session.exercises {
                    let youthTooHeavy = request.screening.isYouth && exercise.unit == .reps && exercise.low < 10
                    if exercise.repsInReserve < 2 || exercise.sets > 5 || youthTooHeavy {
                        found.append(.strengthTooHard(week: week.number, day: session.day, exercise: exercise.key))
                    }
                }
            }
            previousWeeks.append(sessions)
        }
        return found
    }

    /// Upper and lower days work different muscles, so they may follow each other.
    static func isFullBody(_ session: PlanSession) -> Bool {
        let reps = session.exercises.filter { $0.unit == .reps }
        return reps.contains(where: \.lowerBody) && reps.contains(where: { !$0.lowerBody })
    }
}

// MARK: Strength progression

/// One set as the person did it: reps, and how many more they could have done.
public struct SetResult: Equatable, Sendable {
    public let reps: Int
    public let repsInReserve: Int

    public init(reps: Int, repsInReserve: Int) {
        self.reps = reps
        self.repsInReserve = repsInReserve
    }
}

public enum ProgressionAdvice: Equatable, Sendable {
    case addLoad(kilograms: Double)
    /// At home: the next harder version of the exercise (for example knee push-up to push-up).
    case harderVariation
    case addReps
    case keep
    case lighter
}

public enum StrengthProgression {
    /// Load goes up only after every set reached the top of the range with at least 2 reps in reserve
    /// (research, safety rule 8): 5 kg for the legs, 2.5 kg for the upper body. Sets short of the range
    /// or taken to failure keep the load; two or more short sets mean lighter.
    public static func next(after sets: [SetResult], low: Int, high: Int, lowerBody: Bool, atHome: Bool) -> ProgressionAdvice {
        guard !sets.isEmpty else { return .keep }
        if sets.filter({ $0.reps < low }).count >= 2 { return .lighter }
        if sets.contains(where: { $0.reps < low || $0.repsInReserve <= 0 }) { return .keep }
        let roomLeft = sets.allSatisfy { $0.repsInReserve >= 2 }
        if roomLeft && sets.allSatisfy({ $0.reps >= high }) {
            return atHome ? .harderVariation : .addLoad(kilograms: lowerBody ? 5 : 2.5)
        }
        return roomLeft ? .addReps : .keep
    }
}
