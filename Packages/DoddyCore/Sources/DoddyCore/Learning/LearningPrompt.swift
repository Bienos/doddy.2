import Foundation

/// Text for the voice agent's `{{learned_context}}` placeholder (ADR-440): confirmed facts and
/// procedures, sent only when Settings → What I've learned → "Use in voice conversations" is on.
/// Otherwise the agent gets `notShared`, like the profile. Information, never instructions.
public enum LearningPrompt {
    public static let variableName = "learned_context"
    public static let notShared = "(The user has not switched on using what Doddy learned in voice conversations.)"
    public static let empty = "(Nothing learned and confirmed yet.)"

    /// How much a conversation start may carry.
    public static let voiceBudget = LearningBudget(maxFacts: 20, maxProcedures: 10, maxTotalScalars: 3_000)

    public static func render(_ context: LearningContext, shared: Bool, timeZone: TimeZone = .current) -> String {
        guard shared else { return notShared }
        guard !context.isEmpty else { return empty }
        var lines: [String] = []
        if !context.facts.isEmpty {
            lines.append("The user confirmed these about themselves (each on the date given; say \"you told me\" when you use one):")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            for fact in context.facts {
                let date = fact.confirmedAt.map(formatter.string(from:)) ?? "date unavailable"
                lines.append("- (\(fact.kind.rawValue), \(date)) \(ProfilePrompt.oneLine(fact.value))")
            }
        }
        if !context.procedures.isEmpty {
            lines.append("Procedures the user saved. When they ask for one by name, ask for the details marked \"ask\", then call propose_plan with exactly these steps; every step still needs the user's tap on the card:")
            for procedure in context.procedures {
                let steps = procedure.steps.map { step -> String in
                    var text = step.toolName
                    if !step.fixed.isEmpty {
                        text += " (" + step.fixed.keys.sorted().map { "\($0)=\(ProfilePrompt.oneLine(step.fixed[$0] ?? ""))" }.joined(separator: ", ") + ")"
                    }
                    if !step.asked.isEmpty { text += " (ask: \(step.asked.joined(separator: ", ")))" }
                    return text
                }
                lines.append("- \"\(ProfilePrompt.oneLine(procedure.triggerText))\": \(steps.joined(separator: " → "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The agent's result for `note_capability_gap`.
    public static let gapNoted = "noted: Doddy can't do this yet. It's written down on this iPhone as something to add, as a category only. Tell the user in one sentence that you can't do it yet, and move on."
}
