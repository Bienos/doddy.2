import Foundation

/// Builds a plan from a request, or says why not (ADR-624). Deterministic: the same answers give the
/// same plan. The numbers follow the research's safety rules: no run more than 10% longer than the
/// longest of the previous four weeks (BJSM 2025), at most 20% of running time hard, a lighter week
/// every fourth week, no hard day right after another, strength sets stopped with 2–3 reps in reserve.
public enum PlanEngine {
    public static func make(_ request: PlanRequest) -> PlanDecision {
        if let refusal = screen(request) { return .refused(refusal) }
        switch request.goal {
        case .firstFiveK: return firstFiveK(request)
        case .tenK, .halfMarathon: return distance(request)
        case .strengthHome, .strengthGym: return strength(request)
        }
    }

    /// Safety first, then whether the goal fits. Injury and pregnancy come before the general
    /// doctor's question because their answers name a different person to ask.
    static func screen(_ request: PlanRequest) -> PlanRefusal? {
        let s = request.screening
        if s.injuryOrPain { return .injury }
        if s.pregnantOrRecentlyGaveBirth { return .pregnancy }
        if s.knownCondition || s.symptoms || s.doctorAdvisedLimits { return .seeDoctorFirst }
        if s.age < 16 { return .tooYoung }
        if request.daysPerWeek < 2 { return .needsMoreDays(minimum: 2) }
        switch (request.goal, request.level) {
        case (.tenK, .beginner), (.halfMarathon, .beginner): return .notReadyFor(request.goal, suggested: .firstFiveK)
        case (.halfMarathon, _) where s.isYouth: return .notReadyFor(.halfMarathon, suggested: .tenK)
        default: return nil
        }
    }

    // MARK: Running days

    /// Spread across the week, the last one on the weekend for the long run.
    static func runDays(_ count: Int) -> [Int] {
        switch count {
        case ...2: [2, 6]
        case 3: [2, 4, 6]
        case 4: [1, 3, 5, 7]
        default: [1, 2, 4, 5, 7]
        }
    }

    // MARK: From zero to 5 km

    /// Run/walk blocks, week by week, up to 30 minutes of running without stopping (for many people
    /// that is 4 to 5 km): Doddy's own table, built so each block is at most 10% longer than the
    /// longest of the four weeks before (the walks count as time on your feet).
    static let fiveKTable: [RunWalk] = [
        RunWalk(runSeconds: 60, walkSeconds: 90, repeats: 8),
        RunWalk(runSeconds: 90, walkSeconds: 90, repeats: 7),
        RunWalk(runSeconds: 120, walkSeconds: 90, repeats: 6),
        RunWalk(runSeconds: 180, walkSeconds: 90, repeats: 5),
        RunWalk(runSeconds: 300, walkSeconds: 90, repeats: 3),
        RunWalk(runSeconds: 480, walkSeconds: 90, repeats: 2),
        RunWalk(runSeconds: 600, walkSeconds: 90, repeats: 2),
        RunWalk(runSeconds: 1320, walkSeconds: 0, repeats: 1),
        RunWalk(runSeconds: 1440, walkSeconds: 0, repeats: 1),
        RunWalk(runSeconds: 1560, walkSeconds: 0, repeats: 1),
        RunWalk(runSeconds: 1680, walkSeconds: 0, repeats: 1),
        RunWalk(runSeconds: 1800, walkSeconds: 0, repeats: 1),
    ]

    /// With two days a week the same steps take fourteen weeks: the first and the fourth twice. Only
    /// early steps repeat, so every later step still has the step before it in its four-week window.
    static let fiveKTwoDayWeeks = [0, 0, 1, 2, 3, 3, 4, 5, 6, 7, 8, 9, 10, 11]

    /// A five-minute walk before and after each block.
    static let fiveKWalkMinutes = 5

    static func firstFiveK(_ request: PlanRequest) -> PlanDecision {
        let longest = fiveKTable.map(\.blockSeconds).max() ?? 0
        let needed = 2 * fiveKWalkMinutes + Int((Double(longest) / 60).rounded(.up))
        guard request.minutesPerSession >= needed else { return .refused(.needsMoreTime(minimumMinutes: needed)) }
        let twoDays = request.daysPerWeek <= 2
        let days = twoDays ? [2, 6] : [2, 4, 6]
        let steps = twoDays ? fiveKTwoDayWeeks : Array(fiveKTable.indices)
        let weeks = steps.enumerated().map { index, step in
            let block = fiveKTable[step]
            let minutes = 2 * fiveKWalkMinutes + Int((Double(block.blockSeconds) / 60).rounded(.up))
            return PlanWeek(number: index + 1, sessions: days.map {
                PlanSession(day: $0, kind: .runWalk, minutes: minutes, runWalk: block)
            })
        }
        return .plan(TrainingPlan(request: request, weeks: weeks, baselineRunMinutes: nil))
    }

    // MARK: 10 km and half marathon

    /// The long run the plan builds to, in minutes: roughly the goal distance at an easy pace.
    static func targetLongRun(_ goal: PlanGoal) -> Int { goal == .halfMarathon ? 120 : 70 }

    static func defaultBaseline(_ level: PlanLevel) -> Int { level == .regular ? 45 : 30 }

    static func distance(_ request: PlanRequest) -> PlanDecision {
        guard request.minutesPerSession >= 20 else { return .refused(.needsMoreTime(minimumMinutes: 20)) }
        let weekCount = request.goal == .halfMarathon ? 12 : 8
        let baseline = max(20, request.longestRecentRunMinutes ?? defaultBaseline(request.level))
        let target = targetLongRun(request.goal)
        let days = runDays(min(request.daysPerWeek, 5))

        var longs: [Int] = []
        var weeks: [PlanWeek] = []
        for number in 1...weekCount {
            let taper = number == weekCount
            let easier = !taper && number % 4 == 0 && number < weekCount - 1
            let cap = Int((Double(([baseline] + longs.suffix(4)).max() ?? baseline) * 1.1).rounded(.down))
            let long: Int
            if easier, let last = longs.last {
                long = max(20, Int((Double(last) * 0.8).rounded()))
            } else {
                long = min(target, cap)
            }
            longs.append(long)
            weeks.append(PlanWeek(number: number, sessions: runWeek(request, days: days, week: number, long: long,
                                                                     easier: easier, taper: taper),
                                  easier: easier, taper: taper))
        }
        return .plan(TrainingPlan(request: request, weeks: weeks, baselineRunMinutes: baseline))
    }

    /// One week: easy runs, at most one hard session, the long run last. Every run is at most this
    /// week's long run, and weekday runs fit the person's time.
    static func runWeek(_ request: PlanRequest, days: [Int], week: Int, long: Int, easier: Bool, taper: Bool) -> [PlanSession] {
        let weekdayLimit = min(request.minutesPerSession, long)
        let easyBase = max(20, Int((Double(long) * 0.7).rounded(.down)))
        let easy = min(weekdayLimit, taper ? max(20, Int((Double(easyBase) * 0.7).rounded(.down))) : easyBase)
        let wantsQuality = days.count >= 3 && !easier
            && (request.level == .regular || (request.level == .some && week >= 3))

        var sessions: [PlanSession] = []
        for (index, day) in days.enumerated() {
            if index == days.count - 1 {
                sessions.append(PlanSession(day: day, kind: .longRun, minutes: long))
            } else if index == 1, wantsQuality, let hard = quality(request, day: day, week: week, limit: weekdayLimit, taper: taper) {
                sessions.append(hard)
            } else {
                sessions.append(PlanSession(day: day, kind: .easyRun, minutes: easy))
            }
        }
        return keepEightyTwenty(sessions, easyMinutes: easy)
    }

    /// Tempo in odd weeks, intervals in even weeks. Shrinks to fit; nil when even the smallest
    /// version doesn't fit, and the day stays an easy run.
    static func quality(_ request: PlanRequest, day: Int, week: Int, limit: Int, taper: Bool) -> PlanSession? {
        let regular = request.level == .regular
        if week % 2 == 1 {
            var tempo = taper ? 8 : regular ? min(20, 10 + week) : 10
            while tempo >= 8 {
                for warm in [10, 5] where warm * 2 + tempo <= limit {
                    return PlanSession(day: day, kind: .tempoRun, minutes: warm * 2 + tempo, hardMinutes: tempo, tempoMinutes: tempo)
                }
                tempo -= 2
            }
            return nil
        }
        var repeats = taper ? 3 : regular ? (week > 6 ? 6 : 5) : 4
        while repeats >= 3 {
            let block = repeats * 3 + (repeats - 1) * 2
            for warm in [10, 5] where warm * 2 + block <= limit {
                return PlanSession(day: day, kind: .intervals, minutes: warm * 2 + block, hardMinutes: repeats * 3,
                                   intervals: Intervals(repeats: repeats, workSeconds: 180, recoverySeconds: 120))
            }
            repeats -= 1
        }
        return nil
    }

    /// Turns the hard session into an easy run when the week would be more than 20% hard.
    static func keepEightyTwenty(_ sessions: [PlanSession], easyMinutes: Int) -> [PlanSession] {
        var placed = sessions
        let total = placed.reduce(0) { $0 + $1.minutes }
        let hard = placed.reduce(0) { $0 + $1.hardMinutes }
        if Double(hard) > 0.2 * Double(total), let index = placed.firstIndex(where: \.isHard) {
            placed[index] = PlanSession(day: placed[index].day, kind: .easyRun, minutes: easyMinutes)
        }
        return placed
    }

    // MARK: Strength

    static func strengthDays(_ count: Int) -> [Int] {
        switch count {
        case ...2: [2, 5]
        case 3: [1, 3, 5]
        default: [1, 2, 4, 5]
        }
    }

    /// About two and a half minutes a set with its rest, and ten minutes to warm up.
    static func strengthMinutes(exercises: Int, sets: Int) -> Int { 10 + Int((Double(exercises * sets) * 2.5).rounded(.up)) }

    static func strength(_ request: PlanRequest) -> PlanDecision {
        let minimum = strengthMinutes(exercises: 3, sets: 2)
        guard request.minutesPerSession >= minimum else { return .refused(.needsMoreTime(minimumMinutes: minimum)) }
        let atHome = request.goal == .strengthHome
        let youth = request.screening.isYouth
        // Full-body days need a day between them, so at most three; four only as upper and lower
        // days, for people who train regularly.
        let split = request.level == .regular && request.daysPerWeek >= 4
        let days = strengthDays(split ? 4 : min(request.daysPerWeek, 3))
        let weeks = (1...8).map { number -> PlanWeek in
            let easier = number % 4 == 0
            var sets = request.level == .beginner && number <= 2 ? 2 : 3
            if easier { sets = max(2, sets - 1) }
            let sessions = days.enumerated().map { index, day -> PlanSession in
                let menu = split ? (index % 2 == 0 ? ExerciseMenu.upper(atHome: atHome) : ExerciseMenu.lower(atHome: atHome))
                                 : (index % 2 == 0 ? ExerciseMenu.fullBodyA(atHome: atHome, level: request.level)
                                                   : ExerciseMenu.fullBodyB(atHome: atHome, level: request.level))
                // Too long for the person's time: fewer exercises first (never under three), then
                // fewer sets (never under two; `minimum` guarantees that fits).
                var count = menu.count
                var sessionSets = sets
                while count > 3 && strengthMinutes(exercises: count, sets: sessionSets) > request.minutesPerSession { count -= 1 }
                while sessionSets > 2 && strengthMinutes(exercises: count, sets: sessionSets) > request.minutesPerSession { sessionSets -= 1 }
                let exercises = menu.prefix(count).map { $0.prescribed(sets: sessionSets, youth: youth) }
                return PlanSession(day: day, kind: .strength, minutes: strengthMinutes(exercises: count, sets: sessionSets), exercises: exercises)
            }
            return PlanWeek(number: number, sessions: sessions, easier: easier)
        }
        return .plan(TrainingPlan(request: request, weeks: weeks, baselineRunMinutes: nil))
    }
}

/// The exercises the strength plans use, by English name, in the order they're dropped last to first
/// when a session must be shorter. Descriptions and pictures come from the exercise base later (wger).
struct ExerciseChoice {
    let key: String
    let name: String
    let lowerBody: Bool
    let unit: StrengthUnit

    func prescribed(sets: Int, youth: Bool) -> StrengthExercise {
        switch unit {
        case .seconds:
            StrengthExercise(key: key, name: name, lowerBody: lowerBody, sets: sets, low: 20, high: 40, unit: .seconds, repsInReserve: 2)
        case .reps:
            // 16 and 17: lighter loads, more reps, more in reserve; never near a maximum.
            StrengthExercise(key: key, name: name, lowerBody: lowerBody, sets: sets, low: youth ? 10 : 8, high: youth ? 15 : 12,
                             unit: .reps, repsInReserve: youth ? 3 : 2)
        }
    }
}

enum ExerciseMenu {
    private static func e(_ key: String, _ name: String, lower: Bool, _ unit: StrengthUnit = .reps) -> ExerciseChoice {
        ExerciseChoice(key: key, name: name, lowerBody: lower, unit: unit)
    }

    static func fullBodyA(atHome: Bool, level: PlanLevel) -> [ExerciseChoice] {
        atHome
            ? [e("squat", "Squat", lower: true),
               level == .beginner ? e("incline_push_up", "Incline push-up", lower: false) : e("push_up", "Push-up", lower: false),
               e("backpack_row", "Backpack row", lower: false),
               e("glute_bridge", "Glute bridge", lower: true),
               e("plank", "Plank", lower: false, .seconds)]
            : [level == .regular ? e("back_squat", "Back squat", lower: true) : e("goblet_squat", "Goblet squat", lower: true),
               e("dumbbell_bench_press", "Dumbbell bench press", lower: false),
               e("seated_cable_row", "Seated cable row", lower: false),
               e("romanian_deadlift", "Romanian deadlift", lower: true),
               e("plank", "Plank", lower: false, .seconds)]
    }

    static func fullBodyB(atHome: Bool, level: PlanLevel) -> [ExerciseChoice] {
        atHome
            ? [e("reverse_lunge", "Reverse lunge", lower: true),
               level == .beginner ? e("knee_push_up", "Knee push-up", lower: false) : e("push_up", "Push-up", lower: false),
               e("backpack_row", "Backpack row", lower: false),
               e("single_leg_glute_bridge", "Single-leg glute bridge", lower: true),
               e("side_plank", "Side plank", lower: false, .seconds)]
            : [e("leg_press", "Leg press", lower: true),
               e("lat_pulldown", "Lat pulldown", lower: false),
               e("dumbbell_shoulder_press", "Dumbbell shoulder press", lower: false),
               e("hip_thrust", "Hip thrust", lower: true),
               e("dead_bug", "Dead bug", lower: false)]
    }

    static func upper(atHome: Bool) -> [ExerciseChoice] {
        atHome
            ? [e("push_up", "Push-up", lower: false), e("backpack_row", "Backpack row", lower: false),
               e("pike_push_up", "Pike push-up", lower: false), e("plank", "Plank", lower: false, .seconds)]
            : [e("bench_press", "Bench press", lower: false), e("seated_cable_row", "Seated cable row", lower: false),
               e("dumbbell_shoulder_press", "Dumbbell shoulder press", lower: false), e("lat_pulldown", "Lat pulldown", lower: false)]
    }

    static func lower(atHome: Bool) -> [ExerciseChoice] {
        atHome
            ? [e("squat", "Squat", lower: true), e("reverse_lunge", "Reverse lunge", lower: true),
               e("single_leg_glute_bridge", "Single-leg glute bridge", lower: true), e("side_plank", "Side plank", lower: false, .seconds)]
            : [e("back_squat", "Back squat", lower: true), e("romanian_deadlift", "Romanian deadlift", lower: true),
               e("leg_press", "Leg press", lower: true), e("calf_raise", "Calf raise", lower: true)]
    }
}
