import Foundation

// A recap of a conversation: what was discussed, agreed and left to do, never the words themselves
// (decision 2026-11-09-conversation-recaps). The rules below are what keeps it a recap; a model's
// output that breaks one is refused, never cut down to fit.

/// The four conversations Doddy can recap.
public enum ConversationRecapKind: String, Codable, CaseIterable, Sendable {
    /// A conversation with Doddy in the app.
    case voiceConversation = "voice_conversation"
    /// A conversation with someone, recorded in Recordings.
    case recording
    /// A call to or from Doddy's phone line.
    case phoneLine = "phone_line"
    /// A call Doddy made for the person (CallCases).
    case callForYou = "call_for_you"
}

/// What wrote the recap. Shown with it, so the person knows how far to trust it.
public enum RecapWriter: String, Codable, CaseIterable, Sendable {
    /// Apple's Foundation Models on this iPhone: nothing left the phone.
    case onDevice = "on_device"
    /// Doddy's server (Claude), after the person's yes.
    case server
    /// Fixed rules from data the person approved (a call Doddy made for them). No model.
    case rules
}

public enum RecapError: Error, Equatable, Sendable {
    case empty
    case tooManyPoints(section: RecapSection, count: Int)
    case pointTooLong(section: RecapSection, length: Int)
    case pointHasLineBreak(section: RecapSection)
    case blankPoint(section: RecapSection)
    /// A point repeats this many words in a row from the conversation: that is the transcript, not a recap.
    case copiesTheConversation(section: RecapSection, words: Int)
    case withTooLong(length: Int)
    /// The finished note would not fit in a note.
    case tooLongForANote(length: Int)
    /// The model's answer isn't the JSON the recap asks for.
    case unreadableModelOutput
}

public enum RecapSection: String, Codable, CaseIterable, Sendable {
    case discussed, agreed, toDo = "to_do"
}

/// The limits that make a recap a recap. Enforced in code (`ConversationRecap.init`), not by a prompt.
public enum RecapRules {
    public static let maxPointsPerSection = 6
    public static let maxPointLength = 240
    public static let maxWithLength = 80
    /// A point that repeats this many words in a row from the conversation is refused.
    public static let longestCopiedRun = 10
    /// Fewer words than this from the person: nothing to recap.
    public static let minimumWordsFromPerson = 30

    /// The words of a text, lowercased, letters and digits only, for comparing a point with the conversation.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// The longest run of words in a row that `point` shares with `source`.
    static func longestSharedRun(_ point: [String], in source: [String]) -> Int {
        guard !point.isEmpty, !source.isEmpty else { return 0 }
        var best = 0
        var previous = [Int](repeating: 0, count: source.count + 1)
        for word in point {
            var current = [Int](repeating: 0, count: source.count + 1)
            for (j, other) in source.enumerated() where other == word {
                current[j + 1] = previous[j] + 1
                best = max(best, current[j + 1])
            }
            previous = current
        }
        return best
    }
}

public struct ConversationRecap: Equatable, Sendable {
    public let kind: ConversationRecapKind
    /// Who the conversation was with, when known ("Serwis Laptop", "Anna"). Never a phone number.
    public let with: String?
    public let endedAt: Date
    public let discussed: [String]
    public let agreed: [String]
    public let toDo: [String]
    public let writtenBy: RecapWriter

    /// Checks every rule. `conversation` is the text the recap was made from (empty when there was none,
    /// as for a call Doddy made, whose recap uses only the brief and the answer card): no point may copy
    /// `RecapRules.longestCopiedRun` words in a row from it.
    public init(kind: ConversationRecapKind, with: String?, endedAt: Date, discussed: [String], agreed: [String],
                toDo: [String], writtenBy: RecapWriter, conversation: String = "") throws(RecapError) {
        let source = RecapRules.words(conversation)
        func check(_ points: [String], _ section: RecapSection) throws(RecapError) -> [String] {
            guard points.count <= RecapRules.maxPointsPerSection else {
                throw .tooManyPoints(section: section, count: points.count)
            }
            for point in points {
                if point.allSatisfy(\.isWhitespace) { throw .blankPoint(section: section) }
                if point.contains(where: \.isNewline) { throw .pointHasLineBreak(section: section) }
                let length = point.unicodeScalars.count
                if length > RecapRules.maxPointLength { throw .pointTooLong(section: section, length: length) }
                let run = RecapRules.longestSharedRun(RecapRules.words(point), in: source)
                if run >= RecapRules.longestCopiedRun { throw .copiesTheConversation(section: section, words: run) }
            }
            return points
        }
        let discussed = try check(discussed, .discussed)
        let agreed = try check(agreed, .agreed)
        let toDo = try check(toDo, .toDo)
        guard !(discussed.isEmpty && agreed.isEmpty && toDo.isEmpty) else { throw .empty }
        var trimmedWith = with?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = trimmedWith, name.unicodeScalars.count > RecapRules.maxWithLength {
            throw .withTooLong(length: name.unicodeScalars.count)
        }
        // A name, never a phone number: a "with" that is mostly digits is dropped.
        if let name = trimmedWith, name.filter(\.isNumber).count >= 7 { trimmedWith = nil }
        self.kind = kind
        self.with = (trimmedWith?.isEmpty ?? true) ? nil : trimmedWith
        self.endedAt = endedAt
        self.discussed = discussed
        self.agreed = agreed
        self.toDo = toDo
        self.writtenBy = writtenBy
    }
}
