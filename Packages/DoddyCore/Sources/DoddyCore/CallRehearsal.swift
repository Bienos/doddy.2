import Foundation

// Rehearsal (owner backlog #20/#116, ADR-507): before Doddy calls, the user can practise the call
// with Doddy playing the person who answers, in Polish. Nobody is called, nothing is saved, and the
// session has no tools. Afterwards the user picks "Doddy dzwoni" (the approval card) or "Dzwonię
// sam" (this script on screen, and the number to dial themselves).

public enum CallRehearsal {
    public static let banner = "Próba: nikt nie dzwoni, nic nie jest zapisywane. Doddy udaje osobę, która odbiera."

    /// Instructions for the tool-less realtime session. Placeholders are filled from the preview.
    public static let instructionsTemplate = """
    You are helping a user rehearse a short phone call in Polish. You play the person who answers the phone at {{place}}. You are a realistic, polite but busy receptionist. You are an AI, not a person, and this is only practice: nobody is being called.

    The user (or Doddy, the AI assistant they may send later) will call to ask: "{{question}}"
    The goal of the call: {{goal}}

    How to play it:
    - Speak only Polish, naturally and briefly, as a receptionist would. Answer the phone first with: "{{greeting}}"
    - Answer the question plausibly. Sometimes ask for a detail a real receptionist would want (an order number, a name, a date), sometimes say you need a moment to check.
    - Once during the call, ask for something the caller may not want to give or decide on the phone (for example a PESEL number, an address, a payment, or to confirm a booking), so they can practise saying they will check and call back.
    - Never claim this is a real call. Never ask for or repeat real personal data: if the user says a real-looking PESEL, card or account number, say this is only practice and they should not give real numbers.
    - When the user says "koniec próby" or ends the call, step out of the role and give two or three short tips in Polish on how the call went (was the question clear, did they avoid committing to anything, did they get the answer). Be honest and kind, no flattery.
    """

    public static func variables(from preview: CallPreview) -> [String: String] {
        [
            "place": preview.callee.name,
            "question": preview.question,
            "goal": preview.goal,
            "greeting": greeting(for: preview),
        ]
    }

    public static func greeting(for preview: CallPreview) -> String {
        "\(preview.callee.name), dzień dobry, w czym mogę pomóc?"
    }

    /// The rendered instructions; throws if a placeholder is missing (never sent half-filled).
    public static func instructions(from preview: CallPreview) throws -> String {
        try RealtimeInstructions.render(instructionsTemplate, variables: variables(from: preview))
    }

    /// The session's tool list: none. A rehearsal can't do anything.
    public static let toolsJSON = Data(#"{"tools":[]}"#.utf8)
}

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
