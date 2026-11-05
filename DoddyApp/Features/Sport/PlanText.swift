import DoddyCore
import Foundation

/// Words for a training plan in the app's language (ADR-625). The numbers come from DoddyCore's plan
/// engine; nothing here changes them.
enum PlanText {
    // MARK: Answers

    static func goal(_ goal: PlanGoal) -> String {
        switch goal {
        case .firstFiveK: NSLocalizedString("First 5 km", comment: "Training plan goal")
        case .tenK: NSLocalizedString("10 km", comment: "Training plan goal")
        case .halfMarathon: NSLocalizedString("Half marathon", comment: "Training plan goal")
        case .strengthHome: NSLocalizedString("Strength at home", comment: "Training plan goal")
        case .strengthGym: NSLocalizedString("Strength at the gym", comment: "Training plan goal")
        }
    }

    static func goalDetail(_ goal: PlanGoal) -> String {
        switch goal {
        case .firstFiveK: NSLocalizedString("From walking to 30 minutes of running without stopping", comment: "")
        case .tenK: NSLocalizedString("Up to a long run of about 70 minutes, easy", comment: "")
        case .halfMarathon: NSLocalizedString("Up to a long run of about 2 hours, easy", comment: "")
        case .strengthHome: NSLocalizedString("Your body weight and a backpack", comment: "")
        case .strengthGym: NSLocalizedString("Machines, dumbbells and a barbell", comment: "")
        }
    }

    static func level(_ level: PlanLevel) -> String {
        switch level {
        case .beginner: NSLocalizedString("I don't train now", comment: "Training plan level")
        case .some: NSLocalizedString("I train now and then", comment: "Training plan level")
        case .regular: NSLocalizedString("I train most weeks", comment: "Training plan level")
        }
    }

    static func summary(_ plan: TrainingPlan) -> String {
        String(format: NSLocalizedString("%lld weeks, %lld days a week", comment: ""),
               plan.weeks.count, plan.weeks.first?.sessions.count ?? 0)
    }

    // MARK: Days and weeks

    /// Monday for 1 to Sunday for 7, in the app's language.
    static func day(_ day: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols // Sunday first
        guard symbols.count == 7 else { return String(day) }
        return symbols[day % 7].capitalized(with: Locale.current)
    }

    static func week(_ number: Int, of count: Int) -> String {
        String(format: NSLocalizedString("Week %lld of %lld", comment: ""), number, count)
    }

    static func weekNote(_ week: PlanWeek, reachesGoal: Bool) -> String? {
        if week.taper {
            return reachesGoal
                ? NSLocalizedString("The last week: lighter on weekdays, so you arrive fresh for the goal run.", comment: "")
                : NSLocalizedString("The last week: lighter on weekdays, so you arrive fresh for the long run.", comment: "")
        }
        if week.easier { return NSLocalizedString("A lighter week, so your body catches up.", comment: "") }
        return nil
    }

    static func position(_ position: PlanPosition, plan: TrainingPlan) -> String {
        switch position {
        case .startsIn(let days):
            String(format: NSLocalizedString("Starts on Monday. Days to go: %lld", comment: ""), days)
        case .inPlan(let week, _):
            self.week(week, of: plan.weeks.count)
        case .finished:
            NSLocalizedString("This plan is finished. Make a new one when you're ready.", comment: "")
        }
    }

    /// A distance plan that ends before its long run reaches the goal says so, and what comes next.
    static func shortOfGoal(_ plan: TrainingPlan) -> String? {
        guard !plan.reachesGoal, let goal = plan.goalLongRunMinutes, let last = plan.lastLongRunMinutes else { return nil }
        return String(format: NSLocalizedString("This plan builds your long run to %lld min. “%@” at an easy pace takes about %lld min, and runs grow at most 10 percent at a time, so when this plan ends, make the next one from there.", comment: ""),
                      last, self.goal(plan.request.goal), goal)
    }

    // MARK: Sessions

    static func title(_ session: PlanSession) -> String {
        switch session.kind {
        case .runWalk: NSLocalizedString("Run and walk", comment: "Training session")
        case .easyRun: NSLocalizedString("Easy run", comment: "Training session")
        case .longRun: NSLocalizedString("Long run", comment: "Training session")
        case .tempoRun: NSLocalizedString("Tempo run", comment: "Training session")
        case .intervals: NSLocalizedString("Intervals", comment: "Training session")
        case .strength: NSLocalizedString("Strength", comment: "Training session")
        }
    }

    /// `isGoalRun`: the long run of a plan's last week, when it reaches the goal.
    static func detail(_ session: PlanSession, isGoalRun: Bool = false) -> String {
        switch session.kind {
        case .runWalk:
            guard let block = session.runWalk else { return minutes(session.minutes) }
            let walk = PlanEngine.fiveKWalkMinutes
            if block.repeats <= 1 {
                return String(format: NSLocalizedString("Walk %lld min, run %@ without stopping, then walk %lld min.", comment: ""),
                              walk, duration(block.runSeconds), walk)
            }
            return String(format: NSLocalizedString("Walk %lld min. Then run %@ and walk %@, %lld times. Walk %lld min to finish.", comment: ""),
                          walk, duration(block.runSeconds), duration(block.walkSeconds), block.repeats, walk)
        case .easyRun:
            return String(format: NSLocalizedString("%lld min at an easy pace: you can talk in full sentences.", comment: ""), session.minutes)
        case .longRun where isGoalRun:
            return String(format: NSLocalizedString("%lld min, easy. Your goal run.", comment: ""), session.minutes)
        case .longRun:
            return String(format: NSLocalizedString("%lld min, easy. The longest run of the week.", comment: ""), session.minutes)
        case .tempoRun:
            return String(format: NSLocalizedString("%lld min: start easy, run %lld min comfortably hard (a few words at a time), finish easy.", comment: ""),
                          session.minutes, session.tempoMinutes ?? session.hardMinutes)
        case .intervals:
            guard let intervals = session.intervals else { return minutes(session.minutes) }
            return String(format: NSLocalizedString("%lld min: start easy, then %lld × %@ hard with %@ easy between, finish easy.", comment: ""),
                          session.minutes, intervals.repeats, duration(intervals.workSeconds), duration(intervals.recoverySeconds))
        case .strength:
            return String(format: NSLocalizedString("About %lld min with a 10-minute warm-up.", comment: ""), session.minutes)
        }
    }

    static func exercise(_ exercise: StrengthExercise) -> String {
        switch exercise.unit {
        case .reps:
            String(format: NSLocalizedString("%@: %lld × %lld–%lld, stop with %lld reps left", comment: "Exercise, sets × reps"),
                   exerciseName(exercise), exercise.sets, exercise.low, exercise.high, exercise.repsInReserve)
        case .seconds:
            String(format: NSLocalizedString("%@: %lld × %lld–%lld s, stop before your form slips", comment: "Exercise, sets × seconds"),
                   exerciseName(exercise), exercise.sets, exercise.low, exercise.high)
        }
    }

    static func exerciseName(_ exercise: StrengthExercise) -> String {
        switch exercise.key {
        case "squat": NSLocalizedString("Squat", comment: "Exercise")
        case "incline_push_up": NSLocalizedString("Incline push-up", comment: "Exercise")
        case "push_up": NSLocalizedString("Push-up", comment: "Exercise")
        case "knee_push_up": NSLocalizedString("Knee push-up", comment: "Exercise")
        case "pike_push_up": NSLocalizedString("Pike push-up", comment: "Exercise")
        case "backpack_row": NSLocalizedString("Backpack row", comment: "Exercise")
        case "glute_bridge": NSLocalizedString("Glute bridge", comment: "Exercise")
        case "single_leg_glute_bridge": NSLocalizedString("Single-leg glute bridge", comment: "Exercise")
        case "reverse_lunge": NSLocalizedString("Reverse lunge", comment: "Exercise")
        case "plank": NSLocalizedString("Plank", comment: "Exercise")
        case "side_plank": NSLocalizedString("Side plank", comment: "Exercise")
        case "back_squat": NSLocalizedString("Back squat", comment: "Exercise")
        case "goblet_squat": NSLocalizedString("Goblet squat", comment: "Exercise")
        case "dumbbell_bench_press": NSLocalizedString("Dumbbell bench press", comment: "Exercise")
        case "bench_press": NSLocalizedString("Bench press", comment: "Exercise")
        case "seated_cable_row": NSLocalizedString("Seated cable row", comment: "Exercise")
        case "romanian_deadlift": NSLocalizedString("Romanian deadlift", comment: "Exercise")
        case "leg_press": NSLocalizedString("Leg press", comment: "Exercise")
        case "lat_pulldown": NSLocalizedString("Lat pulldown", comment: "Exercise")
        case "dumbbell_shoulder_press": NSLocalizedString("Dumbbell shoulder press", comment: "Exercise")
        case "hip_thrust": NSLocalizedString("Hip thrust", comment: "Exercise")
        case "dead_bug": NSLocalizedString("Dead bug", comment: "Exercise")
        case "calf_raise": NSLocalizedString("Calf raise", comment: "Exercise")
        default: exercise.name
        }
    }

    // MARK: No plan

    static func refusalTitle(_ refusal: PlanRefusal) -> String {
        switch refusal {
        case .seeDoctorFirst: NSLocalizedString("Talk to a doctor first", comment: "")
        case .pregnancy: NSLocalizedString("Ask your doctor or midwife", comment: "")
        case .injury: NSLocalizedString("See a physiotherapist or doctor first", comment: "")
        case .tooYoung: NSLocalizedString("Plan it with an adult", comment: "")
        case .needsMoreTime: NSLocalizedString("This goal needs longer sessions", comment: "")
        case .needsMoreDays: NSLocalizedString("This goal needs more days", comment: "")
        case .notReadyFor(_, let suggested): String(format: NSLocalizedString("Start with “%@”", comment: "Training plan goal"), goal(suggested))
        }
    }

    static func refusalText(_ refusal: PlanRefusal) -> String {
        switch refusal {
        case .seeDoctorFirst:
            NSLocalizedString("Because of your answers, a doctor should say which training suits you. Doddy doesn't make a plan when any of these answers is yes.", comment: "")
        case .pregnancy:
            NSLocalizedString("During pregnancy and after giving birth, your doctor or midwife can say which activity suits you now. Doddy doesn't make a plan for this time.", comment: "")
        case .injury:
            NSLocalizedString("With an injury or pain that training could make worse, have a physiotherapist or doctor look at it first. Doddy doesn't treat injuries or make rehab plans.", comment: "")
        case .tooYoung:
            NSLocalizedString("Under 16, plan training with a parent, a PE teacher or a coach. Doddy doesn't make plans for people under 16.", comment: "")
        case .needsMoreTime(let minimum):
            String(format: NSLocalizedString("Sessions for this goal take at least %lld minutes. Choose more minutes, or another goal.", comment: ""), minimum)
        case .needsMoreDays(let minimum):
            String(format: NSLocalizedString("Plan at least %lld days a week for this goal.", comment: ""), minimum)
        case .notReadyFor(let wanted, let suggested):
            String(format: NSLocalizedString("This goal is a big step from where you are now. Start with “%@”; when you've finished it, come back for “%@”.", comment: ""),
                   goal(suggested), goal(wanted))
        }
    }

    // MARK: Numbers

    static func minutes(_ value: Int) -> String {
        String(format: NSLocalizedString("%lld min", comment: "Minutes"), value)
    }

    /// 90 → "1 min 30 s", 120 → "2 min", 45 → "45 s".
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        if minutes == 0 { return String(format: NSLocalizedString("%lld s", comment: "Seconds"), rest) }
        if rest == 0 { return self.minutes(minutes) }
        return String(format: NSLocalizedString("%lld min %lld s", comment: "Minutes and seconds"), minutes, rest)
    }
}
