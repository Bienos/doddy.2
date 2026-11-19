import Foundation

/// Authority comes from the user's final transcript, never from a tool's arguments or retrieved text.
/// A narrowly matched request can replace a redundant confirmation, once, in this conversation.
/// Payments, bookings, orders, messages and arbitrary external writes have no grant here.
public struct RequestedWorkSession: Sendable {
    public enum Scope: Hashable, Sendable { case research, inquiryCall }
    public struct Grant: Sendable {
        public let language: String?
        public let destinationSource: CallNumberSource?
        fileprivate let turn: UUID
        fileprivate let scope: Scope
        fileprivate let request: VoiceToolRequest
    }

    public static let lifetime: TimeInterval = 120
    private var turn = UUID()
    private var words = ""
    private var spokenAt = Date.distantPast
    private var consumed: Set<Scope> = []
    private var destinations: [CallTaskPlace] = []

    public init() {}

    public mutating func userSaid(_ text: String, at now: Date) {
        turn = UUID()
        words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject overlong authority text rather than truncating away a later constraint or negation.
        if words.utf16.count > ErrandDraft.maxWords { words = "" }
        spokenAt = now
        consumed = []
    }

    /// Only pass structured destinations returned by a successful, live `find_places` request.
    /// Never parse destinations out of model speech, descriptions, Markdown or search snippets.
    public mutating func foundDestinations(_ places: [CallTaskPlace]) {
        destinations = Array(places.prefix(5))
    }

    public func grant(for request: VoiceToolRequest, at now: Date) -> Grant? {
        guard fresh(at: now) else { return nil }
        switch request {
        case .handOverErrand(let draft):
            guard !consumed.contains(.research), draft.validationIssues().isEmpty,
                  Self.key(draft.words) == Self.key(words), Self.key(draft.brief) == Self.key(words),
                  Self.startsResearch(words),
                  draft.priorities.allSatisfy({ Self.contains(words, phrase: $0) }) else { return nil }
            return Grant(language: nil, destinationSource: nil, turn: turn, scope: .research, request: request)
        case .callPlaces(let draft):
            guard !consumed.contains(.inquiryCall), draft.booking == nil, draft.order == nil,
                  !draft.textResult, draft.places.count == 1, !draft.question.isEmpty,
                  let split = Self.callParts(words), Self.key(split.question) == Self.key(draft.question),
                  Self.isInquiry(draft.question) else { return nil }
            let place = draft.places[0]
            let number = Self.number(place.phone)
            guard !number.isEmpty else { return nil }
            let explicitNumber = split.destination.split(separator: " ").allSatisfy { part in
                part.allSatisfy { $0.isASCII && $0.isNumber }
            } && Self.number(split.destination) == number
            let found = destinations.filter { Self.key($0.name) == Self.key(place.name) }
            let knownName = Self.specificName(place.name) && Self.key(split.destination) == Self.key(place.name)
                && Set(found.map { Self.number($0.phone) }) == [number]
            guard explicitNumber || knownName else { return nil }
            return Grant(language: Self.command(words).hasPrefix("call ") ? "en" : "pl", destinationSource: explicitNumber ? .typed : .places,
                         turn: turn, scope: .inquiryCall, request: request)
        default: return nil
        }
    }

    /// Consume immediately before dispatch. A changed turn, expiry or concurrent second tool cannot reuse it.
    public mutating func consume(_ grant: Grant, for request: VoiceToolRequest, at now: Date) -> Bool {
        guard fresh(at: now), grant.turn == turn, grant.request == request, !consumed.contains(grant.scope) else { return false }
        consumed.insert(grant.scope)
        return true
    }

    public func hasConsumed(_ scope: Scope, at now: Date) -> Bool {
        fresh(at: now) && consumed.contains(scope)
    }

    /// Recheck the server's compiled payload before consuming a direct-call grant. The existing server digest
    /// still binds the approval, and all account, calling-hours, agent, number and spending gates still run.
    public static func previewMatches(_ preview: CallTaskPreview, draft: CallTaskDraft, language: String = "pl",
                                      source: CallNumberSource = .places) -> Bool {
        guard preview.kind == "ask", preview.places.count == 1, draft.places.count == 1,
              preview.textResult == false, preview.callableNow == true, preview.language == language,
              draft.booking == nil, draft.order == nil, !draft.textResult else { return false }
        let p = preview.places[0]
        return p.booking == nil && p.order == nil && p.facts.isEmpty && !p.recordsAudio && p.callee.source == source
            && p.notice == "off" && key(p.callee.name) == key(draft.places[0].name)
            && number(p.callee.phone) == number(draft.places[0].phone)
            && key(p.question) == key(draft.question) && key(p.goal) == key(draft.goal)
    }

    private func fresh(at now: Date) -> Bool {
        !words.isEmpty && now >= spokenAt && now.timeIntervalSince(spokenAt) < Self.lifetime
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pl_PL"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func contains(_ text: String, phrase: String) -> Bool {
        let phrase = key(phrase)
        return !phrase.isEmpty && (" " + key(text) + " ").contains(" " + phrase + " ")
    }

    private static func command(_ text: String) -> String {
        var value = key(text)
        for prefix in ["doddy ", "please ", "prosze ", "can you ", "could you ", "czy mozesz "] {
            if value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        }
        return value
    }

    private static func startsResearch(_ text: String) -> Bool {
        let value = command(text)
        guard !["do not start", "dont start", "don t start", "do not begin", "dont begin", "don t begin",
                "before starting", "before beginning", "nie zaczynaj", "nie uruchamiaj", "tylko plan", "just a plan", "only a plan"]
            .contains(where: { contains(value, phrase: $0) }) else { return false }
        return ["find ", "research ", "compare ", "look up ", "check ", "prepare a report ", "analyze ", "analyse ",
                "znajdz ", "zbadaj ", "porownaj ", "sprawdz ", "przygotuj raport ", "przeanalizuj "]
            .contains { value.hasPrefix($0) }
    }

    private static func isInquiry(_ text: String) -> Bool {
        let words = key(text).split(separator: " ")
        let effects = ["book", "reserve", "order", "cancel", "change", "move", "pay", "send", "delete", "call", "buy", "purchase", "transfer", "share",
                       "rezerw", "zarezerw", "zamow", "odwol", "zmien", "przeloz", "zaplac", "wyslij", "usun", "zadzwon", "przelej", "udostepn", "kup"]
        return !words.contains { word in effects.contains { word.hasPrefix($0) } }
    }

    private static func callParts(_ text: String) -> (destination: String, question: String)? {
        let value = command(text)
        let start: String
        if value.hasPrefix("call ") { start = "call " }
        else if value.hasPrefix("zadzwon ") { start = "zadzwon " }
        else { return nil }
        let rest = String(value.dropFirst(start.count))
        for marker in [" and ask ", " i zapytaj "] {
            guard let range = rest.range(of: marker) else { continue }
            var destination = String(rest[..<range.lowerBound])
            // Deferred calls require the scheduling flow; a direct request means this call now.
            guard !["tomorrow", "later", "jutro", "pozniej", "at", "on", "o", "za", "w", "next"]
                .contains(where: { contains(destination, phrase: $0) }) else { return nil }
            for prefix in ["to ", "do "] where destination.hasPrefix(prefix) {
                destination.removeFirst(prefix.count)
            }
            return (destination, String(rest[range.upperBound...]))
        }
        return nil
    }

    private static func number(_ text: String) -> String {
        let digits = String(text.filter { $0.isASCII && $0.isNumber })
        if digits.count == 9 { return "48" + digits }
        if digits.hasPrefix("00") { return String(digits.dropFirst(2)) }
        return (10...15).contains(digits.count) ? digits : ""
    }

    private static func specificName(_ text: String) -> Bool {
        let generic: Set<String> = ["my", "the", "mydentist", "thedentist", "dentist", "mechanic", "restaurant", "clinic", "mój", "moj", "moja",
                                    "dentysta", "dentysty", "mechanik", "mechanika", "restauracja", "restauracji", "klinika", "kliniki"]
        return key(text).split(separator: " ").contains { $0.count >= 3 && !generic.contains(String($0)) }
    }

}
