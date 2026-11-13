import Foundation

// "Who and why" in one field (decision docs/decisions/2026-11-13-calls-one-field-brief.md). The user writes one
// sentence; Doddy's server asks a model to PROPOSE the brief's words and checks every field in code
// (server/messaging/src/taskCalls/draft.ts). What comes back is only the editor's starting point: the user checks
// it, the editor sends the brief as before, and the card made from that is what the user approves (DOD-07). The
// rules here repeat the important ones on the iPhone: the number is the picked contact's or one found in the
// user's own words, and a detail is kept only if the user wrote it. Shared by iPhone and iPad; Watch and Mac don't
// use it.

/// What `POST /v1/call-cases/draft` returns. Every field may be missing: a missing one is left for the user.
public struct CallBriefSuggestion: Decodable, Equatable, Sendable {
    public struct Callee: Decodable, Equatable, Sendable {
        public let name: String?
        /// Only ever a number found in the user's words (`+48…`), never the model's.
        public let phone: String?

        public init(name: String?, phone: String?) {
            self.name = name
            self.phone = phone
        }
    }

    public struct Fact: Decodable, Equatable, Sendable {
        public let kind: CallFactKind
        public let text: String

        public init(kind: CallFactKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Something the model proposed that the server's checks refused, as codes (`question_commits`, `not_from_text`…).
    public struct Dropped: Decodable, Equatable, Sendable {
        public let field: String
        public let reason: String

        public init(field: String, reason: String) {
            self.field = field
            self.reason = reason
        }
    }

    public let callee: Callee
    public let goal: String?
    public let question: String?
    public let facts: [Fact]
    /// `callee.name`, `callee.phone`, `goal`, `question`: what the user still fills in.
    public let missing: [String]
    public let dropped: [Dropped]

    public init(callee: Callee, goal: String?, question: String?, facts: [Fact] = [], missing: [String] = [], dropped: [Dropped] = []) {
        self.callee = callee
        self.goal = goal
        self.question = question
        self.facts = facts
        self.missing = missing
        self.dropped = dropped
    }
}

/// A contact the user picked with Apple's picker: its name and the one number they tapped.
public struct CallBriefContact: Equatable, Sendable {
    public let name: String
    public let number: String

    public init(name: String, number: String) {
        self.name = name
        self.number = number
    }
}

extension CallBriefDraft {
    /// The one field's length, as the server allows.
    public static let oneFieldMaxLength = 400
    /// Shorter than this isn't yet "who and why" (the server's minimum).
    public static let oneFieldMinLength = 8

    /// Whether the one field can be sent: 8 to 400 characters once trimmed.
    public static func oneFieldReady(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (oneFieldMinLength...oneFieldMaxLength).contains(trimmed.count)
    }

    /// The editor's draft from the server's suggestion. The picked contact's number wins (the user chose it); a
    /// number from the server is used only if its digits are in what the user wrote; a fact only if the user wrote
    /// it. A PESEL or an address stays unticked, as when it is typed in the editor. Nothing else is added.
    public static func drafted(from suggestion: CallBriefSuggestion, text: String, contact: CallBriefContact?,
                               principalName: String) -> CallBriefDraft {
        var draft = CallBriefDraft(principalName: principalName)
        if let contact, !contact.number.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.phone = contact.number
            draft.source = .contacts
            draft.sourceLabel = contact.name.isEmpty ? nil : contact.name
        } else if let phone = suggestion.callee.phone, numberIsWritten(phone, in: text) {
            draft.phone = phone
            draft.source = .typed
        }
        draft.calleeName = suggestion.callee.name ?? contact?.name ?? ""
        draft.goal = suggestion.goal ?? ""
        draft.question = suggestion.question ?? ""
        var seen: Set<String> = []
        for fact in suggestion.facts where draft.facts.count < maxTickedFacts {
            let key = folded(fact.text)
            guard !key.isEmpty, folded(text).contains(key), seen.insert(key).inserted else { continue }
            var made = CallFactDraft.suggested(fact.text)
            // The server's kind only refines a plain fact; it never marks one as PESEL or address, nor unmarks it.
            if made.kind == .general, fact.kind != .pesel, fact.kind != .address { made.kind = fact.kind }
            draft.facts.append(made)
        }
        return draft
    }

    /// When no suggestion came (the server couldn't make one, or is too old): the user's own words as the goal if
    /// they fit, the picked contact as who, and every other field left for the user.
    public static func ownWords(_ text: String, contact: CallBriefContact?, principalName: String) -> CallBriefDraft {
        var draft = CallBriefDraft(principalName: principalName)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { draft.goal = trimmed }
        if let contact {
            draft.calleeName = contact.name
            draft.phone = contact.number
            draft.source = .contacts
            draft.sourceLabel = contact.name.isEmpty ? nil : contact.name
        }
        return draft
    }

    /// Whether the national digits of `phone` (`+48600100200` → `600100200`) appear in the user's words.
    static func numberIsWritten(_ phone: String, in text: String) -> Bool {
        guard case .allowed(let e164, _) = PolishNumber.classify(phone) else { return false }
        let national = String(e164.dropFirst(3))
        return text.filter { $0.isASCII && $0.isNumber }.contains(national)
    }

    private static func folded(_ value: String) -> String {
        PolishText.fold(value).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension DoddyServerClient {
    /// "Who and why": sends the one sentence and, if one was picked, the contact's name (never its number), and
    /// gets back a suggestion for the editor. Nothing is kept on the server and nothing is dialled; a refusal of
    /// the words (a PESEL, card or account number) is `briefRefused(field: "text", …)`.
    public func draftCallBrief(text: String, contactName: String?) async throws -> CallBriefSuggestion {
        let body = DraftBody(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                             contactName: contactName?.isEmpty == false ? contactName : nil)
        // The server waits on a model for up to about 40 seconds.
        let response = try await authorized(.post, "/v1/call-cases/draft", body: try Self.json(body), timeout: 45)
        guard response.status == 200, let suggestion = try? JSONDecoder().decode(CallBriefSuggestion.self, from: response.body)
        else { throw Self.callCaseError(from: response) }
        return suggestion
    }
}

private struct DraftBody: Encodable {
    let text: String
    let contactName: String?
}
