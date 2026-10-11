import Foundation

// Settings → Connections → "Try a plan card" (ADR-206): the plan card with sample steps, so the
// card can be checked on an iPhone without a conversation. Nothing is added, saved or started,
// nothing is logged in "What Doddy did", and every result says so.
public enum PlanPractice {
    /// Four sample steps, built through the same parser as the agent's call, dated next Saturday
    /// (or the Saturday after, if today is Saturday) so they are always in the future.
    public static func steps(now: Date = Date(), calendar: Calendar = .current) -> [PlanStep] {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let ahead = (7 - weekday + 7) % 7
        let saturday = calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: today) ?? today
        let day = VoiceToolReply.localText(saturday, hasTime: false, calendar: ReminderDueRules.gregorian(calendar))
        let json = """
        [{"tool":"save_memory","text":"Spare key: blue tin above the fridge"},\
        {"tool":"create_reminder","title":"Bring the spare key and an umbrella","due":"\(day)T12:00"},\
        {"tool":"create_calendar_event","title":"Lunch at Mom's","start":"\(day)T14:00","end":"\(day)T16:00"},\
        {"tool":"set_timer","minutes":10,"label":"Pasta"}]
        """
        let data = (try? JSONSerialization.data(withJSONObject: ["steps": json])) ?? Data()
        guard case .plan(let steps) = PlanProposal.parse(parametersJSON: data, now: now, calendar: calendar) else { return [] }
        return steps
    }

    public static let banner = "Practice: nothing is added, saved or started, and nothing goes to Doddy's activity list."

    /// What would have happened to one step. Never phrased as done.
    public static func result(for step: PlanStep, ticked: Bool, calendar: Calendar = .current) -> String {
        guard ticked else { return "Unticked: this would be skipped." }
        let what = step.activity(calendar: calendar).map { "\($0.title): \($0.detail ?? "")" } ?? step.toolName
        return "Practice only. In a conversation Doddy would do this now (\(what)). Nothing was done."
    }
}
