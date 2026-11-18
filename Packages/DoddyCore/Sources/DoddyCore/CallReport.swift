import Foundation

/// The server's second-pass evidence report. "reported" means the callee said it; it is not a booking receipt.
public struct CallReport: Codable, Equatable, Sendable {
    public struct Evidence: Codable, Equatable, Sendable {
        public let line: Int
        public let atSecs: Double?
        public let quote: String
    }
    public struct Fact: Codable, Equatable, Sendable {
        public let kind: String
        public let value: String
        public let certainty: String
        public let evidence: Evidence
    }
    public struct Verification: Codable, Equatable, Sendable {
        public var uncoveredLines: [Int]? = nil
        public let method: String
        public let accepted: Int
        public let rejected: Int
    }
    public let format: Int
    public let objective: String
    public let domain: String
    public let outcome: String
    public let facts: [Fact]
    public let verification: Verification

    public static func title(polish: Bool) -> String { polish ? "Raport z rozmowy" : "Call report" }
    public static func outcomeTitle(_ outcome: String, polish: Bool) -> String {
        let labels = ["answered": ("Rozmowa odbyła się", "Conversation took place"), "no_answer": ("Nikt nie odebrał", "No answer"),
                      "busy": ("Numer zajęty", "Busy"), "failed": ("Połączenie nie powiodło się", "Call failed"),
                      "not_placed": ("Nie zadzwoniono", "Not dialled"), "voicemail": ("Poczta głosowa", "Voicemail"),
                      "ivr": ("Automatyczne menu", "Automated menu"), "wrong_number": ("Pomyłka", "Wrong number"),
                      "no_conversation": ("Brak rozmowy", "No conversation"), "taken_over": ("Rozmowa przejęta", "Call taken over"),
                      "voice_unavailable": ("Głos niedostępny", "Voice unavailable"), "stopped": ("Rozmowa przerwana", "Call stopped")]
        let pair = labels[outcome] ?? ("Niepotwierdzony stan", "Unconfirmed status")
        return polish ? pair.0 : pair.1
    }

    public var orderedFacts: [Fact] {
        let priority: [String]
        switch domain {
        case "appointment": priority = ["answer", "date", "time", "condition", "price", "person", "location", "commitment", "open_question", "follow_up"]
        case "support": priority = ["answer", "open_question", "follow_up", "date", "condition", "commitment"]
        default: priority = ["answer", "date", "time", "price", "condition", "location", "commitment", "open_question", "follow_up"]
        }
        return facts.enumerated().sorted {
            let a = priority.firstIndex(of: $0.element.kind) ?? priority.count
            let b = priority.firstIndex(of: $1.element.kind) ?? priority.count
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
    public static func factTitle(_ kind: String, polish: Bool) -> String {
        let titles = ["answer": ("Odpowiedź", "Answer"), "person": ("Osoba", "Person"), "organization": ("Organizacja", "Organization"),
                      "date": ("Data", "Date"), "time": ("Godzina", "Time"), "price": ("Cena", "Price"), "location": ("Miejsce", "Location"),
                      "condition": ("Warunki", "Conditions"), "commitment": ("Deklaracja rozmówcy", "Callee's statement"),
                      "open_question": ("Otwarte pytanie", "Open question"), "follow_up": ("Dalszy krok", "Follow-up")]
        let pair = titles[kind] ?? ("Ustalenie", "Finding")
        return polish ? pair.0 : pair.1
    }

    public func markdown(polish: Bool) -> String {
        let labels = polish ? ("Cel", "Wynik", "Cytat z rozmowy", "Niepewne", "Wypowiedź rozmówcy", "Wiersz")
                            : ("Objective", "Outcome", "Call excerpt", "Uncertain", "Reported", "Line")
        // No model text becomes active Markdown/HTML (images, links or scripts) on export.
        func escape(_ text: String) -> String {
            var result = text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            for character in ["!", "[", "]", "(", ")", "*", "_", "#", "|", "`", "~"] {
                result = result.replacingOccurrences(of: character, with: "\\" + character)
            }
            return result.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        var lines = ["# \(Self.title(polish: polish))", "", "**\(labels.0):** \(escape(objective))", "", "**\(labels.1):** \(Self.outcomeTitle(outcome, polish: polish))", ""]
        for fact in orderedFacts {
            lines += ["## \(Self.factTitle(fact.kind, polish: polish))", "", "**\(fact.certainty == "reported" ? labels.4 : labels.3):** \(escape(fact.value))", "",
                      "> \(escape(fact.evidence.quote))", "", "\(labels.2) · \(labels.5) \(fact.evidence.line + 1)\(fact.evidence.atSecs.flatMap { $0.isFinite && $0 >= 0 && $0 < Double(Int.max) ? " · \(Int($0)) s" : nil } ?? "")", ""]
        }
        if facts.isEmpty { lines += [polish ? "Brak szczegółów, które udało się sprawdzić w zapisie rozmowy." : "No details could be verified against the call record.", ""] }
        if verification.rejected > 0 || !(verification.uncoveredLines?.isEmpty ?? true) {
            lines += [polish ? "Nie wszystkie szczegóły udało się sprawdzić. Raport może być niepełny."
                      : "Some details still need review. The report may be incomplete.", ""]
        }
        return lines.joined(separator: "\n")
    }
}
