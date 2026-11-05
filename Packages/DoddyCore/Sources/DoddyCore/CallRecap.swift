import Foundation

/// The recap of a call Doddy made for the person, as a plain text file they can open in Files, share,
/// or send in Messages. Built only from the brief the person approved and the answer card kept on this
/// iPhone; it adds nothing and guesses nothing. A call with no answer card has no recap.
///
/// It never holds what the other side said word for word, except the one short quote that backs the
/// answer: the transcript is the owner's log (ADR-730) and is not part of a recap.
///
/// The words around the facts are passed in (`Labels`) because the app localizes them; the facts
/// themselves, such as the summary, are Polish as the call was.
public enum CallRecap {
    public struct Labels: Equatable, Sendable {
        public var title: String
        public var to: String
        public var goal: String
        public var question: String
        public var outcome: String
        public var when: String
        public var duration: String
        public var answer: String
        public var nextStep: String
        public var checkThis: String

        public init(title: String, to: String, goal: String, question: String, outcome: String, when: String,
                    duration: String, answer: String, nextStep: String, checkThis: String) {
            self.title = title
            self.to = to
            self.goal = goal
            self.question = question
            self.outcome = outcome
            self.when = when
            self.duration = duration
            self.answer = answer
            self.nextStep = nextStep
            self.checkThis = checkThis
        }
    }

    /// The recap, or nil when the case has no answer card yet. `outcomeText` and `whenText` are made by the
    /// app (the outcome in the person's language, the date and time in their locale).
    public static func text(for record: StoredCallCase, labels: Labels, outcomeText: String, whenText: String) -> String? {
        guard let card = record.result else { return nil }
        let rule = String(repeating: "─", count: 28)
        var out: [String] = [labels.title, rule, ""]
        out.append(field(labels.to, record.brief.calleeName))
        out.append(field(labels.when, whenText))
        out.append(field(labels.goal, record.brief.goal))
        out.append(field(labels.question, record.brief.question))
        out.append(field(labels.outcome, outcomeText))
        if let secs = card.durationSecs, secs > 0 { out.append(field(labels.duration, "\(Int(secs.rounded())) s")) }
        out.append("")
        out.append(labels.answer.uppercased())
        out.append(card.summary)
        if let quote = card.quote { out.append("„\(quote.text)”") }
        if !card.nextStep.text.isEmpty {
            out.append("")
            out.append(labels.nextStep.uppercased())
            out.append(card.nextStep.text)
        }
        if !card.warnings.isEmpty {
            out.append("")
            out.append("\(labels.checkThis): \(card.warnings.count)")
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func field(_ label: String, _ value: String) -> String { "\(label): \(value)" }

    /// A file name that is safe on every platform: the callee's name and the date, nothing else.
    public static func fileName(for record: StoredCallCase, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents(in: TimeZone(identifier: "Europe/Warsaw") ?? .current, from: record.createdAt)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let allowed = CharacterSet.alphanumerics
        let name = record.brief.calleeName.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return "Doddy-call-\(name.isEmpty ? "recap" : String(name.prefix(40)))-\(stamp).txt"
    }
}
