import Foundation

/// The recap of a call Doddy made for the person, as a plain text file they can open in Files,
/// share, or send in Messages. Built only from what is already kept on this iPhone for the case
/// (the brief the person approved and the answer card the server made); it adds nothing and
/// guesses nothing. A call with no answer card has no recap.
///
/// The words around the facts are passed in (`Labels`) because the app localizes them; the
/// facts themselves, such as the summary and the transcript, are Polish as the call was.
public enum CallRecap {
    public struct Labels: Equatable, Sendable {
        public var title: String
        public var to: String
        public var goal: String
        public var question: String
        public var outcome: String
        public var summary: String
        public var quote: String
        public var nextStep: String
        public var warnings: String
        public var transcript: String
        public var duration: String
        public var doddy: String
        public var callee: String

        public init(title: String, to: String, goal: String, question: String, outcome: String, summary: String,
                    quote: String, nextStep: String, warnings: String, transcript: String, duration: String,
                    doddy: String, callee: String) {
            self.title = title
            self.to = to
            self.goal = goal
            self.question = question
            self.outcome = outcome
            self.summary = summary
            self.quote = quote
            self.nextStep = nextStep
            self.warnings = warnings
            self.transcript = transcript
            self.duration = duration
            self.doddy = doddy
            self.callee = callee
        }
    }

    /// The recap, or nil when the case has no answer card yet.
    public static func text(for record: StoredCallCase, labels: Labels, outcomeText: String) -> String? {
        guard let card = record.result else { return nil }
        var out: [String] = [labels.title, ""]
        out.append("\(labels.to): \(record.brief.calleeName)")
        out.append("\(labels.goal): \(record.brief.goal)")
        out.append("\(labels.question): \(record.brief.question)")
        out.append("\(labels.outcome): \(outcomeText)")
        if let secs = card.durationSecs { out.append("\(labels.duration): \(Int(secs.rounded())) s") }
        out.append("")
        out.append("\(labels.summary): \(card.summary)")
        if let quote = card.quote { out.append("\(labels.quote): „\(quote.text)”") }
        if !card.nextStep.text.isEmpty { out.append("\(labels.nextStep): \(card.nextStep.text)") }
        if !card.warnings.isEmpty { out.append("\(labels.warnings): \(card.warnings.count)") }
        if !card.transcript.isEmpty {
            out.append("")
            out.append(labels.transcript)
            for line in card.transcript {
                let who = line.speaker == "doddy" ? labels.doddy : labels.callee
                out.append("\(who): \(line.text)")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

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
