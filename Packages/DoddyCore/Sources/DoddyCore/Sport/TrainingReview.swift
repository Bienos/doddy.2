import Foundation

// The weekly review (ADR-632; research section 2.4): what to change before the next session, judged
// on the last two weeks of the person's own log. It is code, not a model: the same log gives the same
// answer, and the words below are fixed. The rules:
//   - one priority, not a list of homework;
//   - change one variable at a time: more load, or more reps, or a harder version, never two at once;
//   - raise nothing without "how many reps were left" on every set (ACSM 2026: failure is not needed),
//     and nothing at all while pain is on record or the last two sessions were hard;
//   - no counting of missed sessions, no streaks, no promise about where this ends up.
// The load and rep rules are `StrengthProgression` from ADR-624; this file chooses which exercise
// speaks first and says it. Nothing is saved or sent, and nothing is changed in the person's plan.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

/// What to do with one exercise next time. Exactly one variable moves.
public enum ExerciseAdvice: Equatable, Sendable {
    /// Add this much and start again from the bottom of the range.
    case addLoad(kilograms: Double)
    /// At home: the next harder version of the exercise.
    case harderVariation
    case addReps
    /// A timed hold: a few seconds longer.
    case longerHold
    case keep
    case lighter

    /// Whether the advice asks for more than last time.
    public var raisesSomething: Bool {
        switch self {
        case .addLoad, .harderVariation, .addReps, .longerHold: true
        case .keep, .lighter: false
        }
    }
}

/// One exercise as it was done in one session.
public struct ExerciseSnapshot: Equatable, Sendable {
    public let performedAt: Date
    /// Reps (seconds for a hold) added up over the sets.
    public let totalReps: Int
    /// The heaviest set, in grams; nil for bodyweight or "not said".
    public let topLoadGrams: Int?
}

public struct ExerciseReview: Equatable, Sendable {
    public let key: String
    public let advice: ExerciseAdvice
    public let latest: ExerciseSnapshot
    /// The session before the latest one that had this exercise, if it was within the two weeks.
    public let previous: ExerciseSnapshot?
    /// A set had no "reps left" note, so nothing could be raised on it.
    public let missingReserve: Bool
    public let timed: Bool
    /// The range the advice was judged against: the person's plan when it has the exercise, else the usual one.
    public let low: Int
    public let high: Int
}

/// The one thing to do before the next session.
public enum ReviewPriority: Equatable, Sendable {
    /// Nothing in the last two weeks to judge from.
    case logFirstSession
    /// A session in the last two weeks was marked pain.
    case stopAndGetChecked
    /// The last two sessions were both hard: the same as last time, nothing added.
    case easeOff
    case lighter(exercise: String)
    case progress(exercise: String, advice: ExerciseAdvice)
    case keepAsPlanned
}

public struct TrainingReviewResult: Equatable, Sendable {
    public let priority: ReviewPriority
    /// Every exercise of the latest sessions, in the order they were done. The screens may show these
    /// under the one priority; the priority is the only one the words name.
    public let exercises: [ExerciseReview]
    public let sessionsLookedAt: Int
}

public enum TrainingReview {
    /// "The last 1–2 weeks": sessions older than this are not looked at.
    public static let windowDays = 14

    /// Holds the engine prescribes in seconds. A test sweeps the engine's plans to keep this honest.
    static let timedKeys: Set<String> = ["plank", "side_plank"]

    public static func review(sessions: [LoggedSession], plan: TrainingPlan? = nil, atHome: Bool = false,
                              now: Date) -> TrainingReviewResult {
        let from = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let until = now.addingTimeInterval(86_400)
        let recent = sessions.filter { $0.performedAt >= from && $0.performedAt <= until }
            .sorted { ($0.performedAt, $0.id.uuidString) > ($1.performedAt, $1.id.uuidString) }
        let home = plan.map { $0.request.goal == .strengthHome } ?? atHome

        guard !recent.isEmpty else {
            return TrainingReviewResult(priority: .logFirstSession, exercises: [], sessionsLookedAt: 0)
        }

        let exercises = exerciseReviews(recent, plan: plan, atHome: home)

        let priority: ReviewPriority
        if recent.contains(where: { $0.feeling == .pain }) {
            priority = .stopAndGetChecked
        } else if let slow = exercises.first(where: { $0.advice == .lighter }) {
            priority = .lighter(exercise: slow.key)
        } else if recent.count >= 2, recent[0].feeling == .hard, recent[1].feeling == .hard {
            priority = .easeOff
        } else if let ready = exercises.first(where: { $0.advice.raisesSomething }) {
            priority = .progress(exercise: ready.key, advice: ready.advice)
        } else {
            priority = .keepAsPlanned
        }
        return TrainingReviewResult(priority: priority, exercises: exercises, sessionsLookedAt: recent.count)
    }

    // MARK: Per exercise

    private static func exerciseReviews(_ recent: [LoggedSession], plan: TrainingPlan?, atHome: Bool) -> [ExerciseReview] {
        var order: [String] = []
        for session in recent {
            for set in session.sets where !order.contains(set.exerciseKey) { order.append(set.exerciseKey) }
        }
        return order.compactMap { key in
            let having = recent.filter { session in session.sets.contains { $0.exerciseKey == key } }
            guard let latestSession = having.first else { return nil }
            let sets = latestSession.sets.filter { $0.exerciseKey == key }
            let facts = prescription(for: key, in: plan)
            let results = sets.map { SetResult(reps: $0.reps, repsInReserve: $0.repsInReserve ?? 0) }
            let progression = StrengthProgression.next(
                after: results, low: facts.low, high: facts.high, lowerBody: facts.lowerBody, atHome: facts.timed ? true : atHome)
            return ExerciseReview(
                key: key, advice: advice(progression, timed: facts.timed), latest: snapshot(latestSession, sets),
                previous: having.dropFirst().first.map { snapshot($0, $0.sets.filter { $0.exerciseKey == key }) },
                missingReserve: sets.contains { $0.repsInReserve == nil }, timed: facts.timed,
                low: facts.low, high: facts.high)
        }
    }

    /// `StrengthProgression` has no timed case: for a hold, every way of doing more means a longer hold.
    private static func advice(_ progression: ProgressionAdvice, timed: Bool) -> ExerciseAdvice {
        switch progression {
        case .addLoad(let kilograms): timed ? .longerHold : .addLoad(kilograms: kilograms)
        case .harderVariation: timed ? .longerHold : .harderVariation
        case .addReps: timed ? .longerHold : .addReps
        case .keep: .keep
        case .lighter: .lighter
        }
    }

    private static func snapshot(_ session: LoggedSession, _ sets: [LoggedSet]) -> ExerciseSnapshot {
        ExerciseSnapshot(performedAt: session.performedAt, totalReps: sets.reduce(0) { $0 + $1.reps },
                         topLoadGrams: sets.compactMap(\.loadGrams).max())
    }

    /// The range and kind of an exercise: from the person's plan when it has the exercise, else from
    /// the card and the usual ranges. An unknown key is treated as an upper-body lift, the smaller step.
    private static func prescription(for key: String, in plan: TrainingPlan?) -> (low: Int, high: Int, lowerBody: Bool, timed: Bool) {
        let planned = plan?.weeks.lazy.flatMap(\.sessions).flatMap(\.exercises).first { $0.key == key }
        if let planned {
            return (planned.low, planned.high, planned.lowerBody, planned.unit == .seconds)
        }
        let timed = timedKeys.contains(key)
        return (timed ? 20 : 8, timed ? 40 : 12, isLowerBody(key), timed)
    }

    /// Whether an exercise works the legs, for the size of the next step (5 kg against 2.5 kg), when
    /// the plan is not there to say. From the exercise card; a sweep test keeps it equal to the engine's.
    static func isLowerBody(_ key: String) -> Bool {
        guard let card = ExerciseCatalogue.card(forKey: key) else { return false }
        return card.pattern == .squat || card.pattern == .hinge || card.primaryMuscles.contains("calves")
    }
}
