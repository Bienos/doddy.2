import Foundation

// Voice tool for asking for a plan (ADR-626; owner, 25 Oct 2026: "okej" to a plan asked for by voice or in Messages).
// Its own file, apart from `Sport/PlanAsk.swift`, so the sport files stay free of the voice types and
// `scripts/check_training_plan_store.sh` can compile them alone. ASK-01: a card and a tap. The agent passes a goal and,
// if said, the days and minutes; it never hears the safety answers or the plan.

extension VoiceToolName {
    public static let openTrainingPlan = "open_training_plan"
}

extension VoiceToolRequest {
    static func parseTrainingPlan(_ args: Arguments, name: String) -> VoiceToolRequest {
        let choices = PlanAsk.goalNames.map(\.name).joined(separator: ", ")
        guard let goalText = args.text("goal") else { return .invalid(name: name, reason: "missing goal: one of \(choices)") }
        guard PlanAsk.goal(named: goalText) != nil else { return .invalid(name: name, reason: "goal must be one of \(choices)") }
        func whole(_ key: String) -> Int? {
            guard let value = args.number(key), value == value.rounded(), let whole = Int(exactly: value) else { return nil }
            return whole
        }
        guard let ask = PlanAsk.make(goalName: goalText, daysPerWeek: whole("days_per_week"), minutesPerSession: whole("minutes_per_session")) else {
            return .invalid(name: name, reason: "goal must be one of \(choices)")
        }
        return .openTrainingPlan(ask)
    }
}

extension VoiceToolReply {
    /// After the tap: the plan screen is open. The agent hears what is filled in and, plainly, what it
    /// must not do: it never learns the person's answers or the plan.
    public static func trainingPlanOpened(_ ask: PlanAsk) -> String {
        var filled = ["goal: " + PlanAsk.goalTitle(ask.goal)]
        filled.append(ask.daysPerWeek.map { "days a week: \($0)" } ?? "days a week: not set, the user picks")
        filled.append(ask.minutesPerSession.map { "minutes a session: \($0)" } ?? "minutes a session: not set, the user picks")
        return "opened: the training plan screen is open on the user's iPhone with " + filled.joined(separator: "; ") + ". "
            + "The user answers a few safety questions there, and Doddy's fixed rules make the plan on screen. "
            + "You don't see their answers or the plan. Never ask about their health, injuries, age or medicines, never make up or describe a plan, and never say a plan is made. "
            + "Say in one short sentence that the screen is open. "
            + "If the user already told you about pain, an injury, pregnancy, a medical condition or chest symptoms, tell them to ask a doctor or physiotherapist first."
    }
}
