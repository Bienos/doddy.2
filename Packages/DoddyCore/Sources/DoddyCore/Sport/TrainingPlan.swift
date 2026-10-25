import Foundation

// Sport mode step 4 (ADR-624): running and strength plans, worked out by code, not by a model.
// The owner chose plans next ("2", 24 Oct 2026). `PlanEngine` builds a plan from the person's answers
// and the safety rules of the research (docs/research/2026-10-24/research_sport_mode.md); a model may
// later explain or reword a plan, never change its numbers. Every plan the engine makes has no
// `PlanRules.violations`. Nothing here is medical advice, and the refusals say who to ask instead.

public enum PlanGoal: String, CaseIterable, Sendable, Codable {
    /// From zero to running 5 km: run/walk sessions.
    case firstFiveK
    case tenK
    case halfMarathon
    /// Bodyweight and a backpack at home.
    case strengthHome
    case strengthGym

    public var isRunning: Bool { self == .firstFiveK || self == .tenK || self == .halfMarathon }
}

public enum PlanLevel: String, CaseIterable, Sendable, Codable {
    /// Doesn't train now.
    case beginner
    /// Trains now and then.
    case some
    /// Trains most weeks.
    case regular
}

/// The questions before a plan above light activity (research, safety rules 2 and 5), in Doddy's own
/// words, after the logic of ACSM's 2015 screening (not the copyrighted PAR-Q+). Any "yes" to the first
/// five means no plan, and the refusal says who to see.
public struct PlanScreening: Equatable, Sendable, Codable {
    /// A heart, lung, kidney or metabolic condition (diabetes, for example).
    public var knownCondition: Bool
    /// Chest pain, fainting or dizziness, unusual breathlessness, or a racing heart, now or with effort.
    public var symptoms: Bool
    /// A doctor said to limit exercise.
    public var doctorAdvisedLimits: Bool
    public var pregnantOrRecentlyGaveBirth: Bool
    /// An injury or pain that exercise could make worse.
    public var injuryOrPain: Bool
    public var age: Int

    public init(knownCondition: Bool, symptoms: Bool, doctorAdvisedLimits: Bool, pregnantOrRecentlyGaveBirth: Bool,
                injuryOrPain: Bool, age: Int) {
        self.knownCondition = knownCondition
        self.symptoms = symptoms
        self.doctorAdvisedLimits = doctorAdvisedLimits
        self.pregnantOrRecentlyGaveBirth = pregnantOrRecentlyGaveBirth
        self.injuryOrPain = injuryOrPain
        self.age = age
    }

    /// Every answer "no".
    public static func clear(age: Int) -> PlanScreening {
        PlanScreening(knownCondition: false, symptoms: false, doctorAdvisedLimits: false,
                      pregnantOrRecentlyGaveBirth: false, injuryOrPain: false, age: age)
    }

    /// 16 and 17: a plan with the youth limits (lighter strength work, no half marathon).
    public var isYouth: Bool { age < 18 }
}

public struct PlanRequest: Equatable, Sendable, Codable {
    public let goal: PlanGoal
    public let level: PlanLevel
    /// 2 to 5; more is treated as 5 for running and 4 for strength.
    public let daysPerWeek: Int
    /// The time a weekday session may take. The long run is on the weekend and may be longer.
    public let minutesPerSession: Int
    /// The longest run of the last 30 days, in minutes, if the person knows it (or Apple Health has it).
    public let longestRecentRunMinutes: Int?
    public let screening: PlanScreening

    public init(goal: PlanGoal, level: PlanLevel, daysPerWeek: Int, minutesPerSession: Int,
                longestRecentRunMinutes: Int? = nil, screening: PlanScreening) {
        self.goal = goal
        self.level = level
        self.daysPerWeek = daysPerWeek
        self.minutesPerSession = minutesPerSession
        self.longestRecentRunMinutes = longestRecentRunMinutes
        self.screening = screening
    }
}

/// Why there is no plan. Each one says what to do instead; none is a diagnosis.
public enum PlanRefusal: Equatable, Sendable {
    /// A condition, symptoms or a doctor's limit: see a doctor before a plan.
    case seeDoctorFirst
    /// Pregnant or recently gave birth: only general advice, and ask a doctor or midwife.
    case pregnancy
    /// An injury or pain: a physiotherapist or doctor first.
    case injury
    /// Under 16: with a parent, a PE teacher or a coach, not an app plan.
    case tooYoung
    case needsMoreTime(minimumMinutes: Int)
    case needsMoreDays(minimum: Int)
    /// The goal is too big a step from here; the suggested goal comes first.
    case notReadyFor(PlanGoal, suggested: PlanGoal)
}

public enum PlanDecision: Equatable, Sendable {
    case plan(TrainingPlan)
    case refused(PlanRefusal)
}

/// How hard it should feel, on a 0–10 scale of effort: easy 3–4 (you can talk in full sentences),
/// steady 5–6, hard 7–8 (a few words at a time).
public enum Effort: String, Sendable, Codable {
    case easy, steady, hard
}

public enum SessionKind: String, Sendable, Codable {
    case runWalk, easyRun, longRun, tempoRun, intervals, strength
}

/// Run/walk repeats for a first 5 km.
public struct RunWalk: Equatable, Sendable, Codable {
    public let runSeconds: Int
    public let walkSeconds: Int
    public let repeats: Int

    /// The run/walk block itself, warm-up and cool-down walks not included.
    public var blockSeconds: Int { repeats * runSeconds + max(0, repeats - 1) * walkSeconds }
}

public struct Intervals: Equatable, Sendable, Codable {
    public let repeats: Int
    public let workSeconds: Int
    public let recoverySeconds: Int
}

public enum StrengthUnit: String, Sendable, Codable {
    case reps, seconds
}

public struct StrengthExercise: Equatable, Sendable, Codable {
    /// A stable key for the exercise base (wger later); `name` is the English name.
    public let key: String
    public let name: String
    public let lowerBody: Bool
    public let sets: Int
    public let low: Int
    public let high: Int
    public let unit: StrengthUnit
    /// Stop each set with this many reps still in the tank (ACSM 2026: failure isn't needed).
    public let repsInReserve: Int
}

public struct PlanSession: Equatable, Sendable, Codable {
    /// 1 is Monday, 7 Sunday.
    public let day: Int
    public let kind: SessionKind
    /// The whole session, warm-up and cool-down included.
    public let minutes: Int
    /// Minutes at hard effort, for the 80/20 rule.
    public let hardMinutes: Int
    public let runWalk: RunWalk?
    public let intervals: Intervals?
    public let tempoMinutes: Int?
    public let exercises: [StrengthExercise]

    public init(day: Int, kind: SessionKind, minutes: Int, hardMinutes: Int = 0, runWalk: RunWalk? = nil,
                intervals: Intervals? = nil, tempoMinutes: Int? = nil, exercises: [StrengthExercise] = []) {
        self.day = day
        self.kind = kind
        self.minutes = minutes
        self.hardMinutes = hardMinutes
        self.runWalk = runWalk
        self.intervals = intervals
        self.tempoMinutes = tempoMinutes
        self.exercises = exercises
    }

    public var isRun: Bool { kind != .strength }
    public var isHard: Bool { kind == .tempoRun || kind == .intervals }

    /// Time on your feet for the longest-run rule: the run/walk block for a first 5 km (the walks
    /// around it don't count), otherwise the whole run.
    public var timeOnFeetSeconds: Int { runWalk?.blockSeconds ?? minutes * 60 }

    public var effort: Effort { isHard ? .hard : kind == .strength ? .steady : .easy }
}

public struct PlanWeek: Equatable, Sendable, Codable {
    public let number: Int
    public let sessions: [PlanSession]
    /// Every fourth week is lighter, so the body catches up.
    public let easier: Bool
    /// The last week before the goal: less, so you arrive fresh.
    public let taper: Bool

    public init(number: Int, sessions: [PlanSession], easier: Bool = false, taper: Bool = false) {
        self.number = number
        self.sessions = sessions
        self.easier = easier
        self.taper = taper
    }
}

public struct TrainingPlan: Equatable, Sendable, Codable {
    public let request: PlanRequest
    public let weeks: [PlanWeek]
    /// The longest recent run the plan starts from, in minutes; nil for a first 5 km and strength.
    public let baselineRunMinutes: Int?

    public init(request: PlanRequest, weeks: [PlanWeek], baselineRunMinutes: Int?) {
        self.request = request
        self.weeks = weeks
        self.baselineRunMinutes = baselineRunMinutes
    }
}
