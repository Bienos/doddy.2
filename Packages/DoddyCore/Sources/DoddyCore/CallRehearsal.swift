import Foundation

// "Dzwonię sam" (owner backlog #20/#116, ADR-507): afterwards the user picks "Doddy dzwoni" (the approval
// card) or "Dzwonię sam" (this script on screen, and the number to dial themselves). The spoken
// rehearsal that used to come before it ran on OpenAI Realtime and was removed with OpenAI voice
// (owner decision, 9 Nov 2026).

/// "Dzwonię sam": what to say, in order, built from the approved preview. Gender-neutral phrasing,
/// since the app doesn't know how the user speaks of themselves.
public enum SelfCallScript {
    public struct Step: Equatable, Sendable {
        public let label: String
        public let text: String
    }

    public static func steps(from preview: CallPreview) -> [Step] {
        var steps = [
            Step(label: "Na początek", text: "Dzień dobry, nazywam się \(preview.principal.name)."),
            Step(label: "Pytanie", text: "Mam pytanie: \(preview.question)"),
        ]
        for fact in preview.facts {
            steps.append(Step(label: "Jeśli zapytają", text: fact.text))
        }
        steps.append(Step(label: "Gdy chcą czegoś więcej", text: "Muszę to sprawdzić, oddzwonię."))
        steps.append(Step(label: "Na koniec", text: "Dziękuję bardzo, do widzenia."))
        return steps
    }

    /// The number as shown on the card, for a `tel:` link (digits and a leading +).
    public static func dialString(from preview: CallPreview) -> String? {
        if case .allowed(let e164, _) = PolishNumber.classify(preview.callee.phone) { return e164 }
        return nil
    }
}
