import Foundation

/// The person's two switches for recaps (decision 2026-11-09-conversation-recaps). Both are off until
/// the person turns them on; the app keeps them in UserDefaults under these keys.
public enum RecapSettings {
    /// "Remember what we talked about": once on, each recap is saved as a note without a tap.
    public static let rememberKey = "recaps.remember.v1"
    public static let rememberDefault = false
    /// The yes to sending a conversation's text to Doddy's server for a recap, when this iPhone can't
    /// write one itself.
    public static let serverWriterKey = "recaps.serverWriter.v1"
    public static let serverWriterDefault = false
}

/// Whether a conversation gets a recap, and who writes it. Pure rules, so they are tested on Linux.
public enum RecapPolicy {
    public enum Skip: String, Equatable, Sendable {
        /// "Remember what we talked about" is off.
        case switchedOff
        /// A Private conversation (ADR-310): never recapped, never remembered.
        case privateConversation
        /// The person said too little for there to be anything to remember.
        case tooShort
        /// No model on this iPhone and no yes to the server.
        case noWriter
    }

    public enum Decision: Equatable, Sendable {
        case recap(RecapWriter)
        case skip(Skip)
    }

    /// `wordsFromPerson` counts the person's words only (Doddy's own lines don't make a conversation worth
    /// remembering). A call Doddy made for the person is recapped by the rules from its answer card, so it
    /// needs neither a model nor a word count.
    public static func decide(kind: ConversationRecapKind, rememberOn: Bool, isPrivate: Bool, wordsFromPerson: Int,
                              onDeviceAvailable: Bool, serverYes: Bool) -> Decision {
        guard rememberOn else { return .skip(.switchedOff) }
        guard !isPrivate else { return .skip(.privateConversation) }
        if kind == .callForYou { return .recap(.rules) }
        guard wordsFromPerson >= RecapRules.minimumWordsFromPerson else { return .skip(.tooShort) }
        // The phone line's recap is made on the server, which already has the call (step 5); the app only
        // receives it, so the person's yes to the server writer is not what decides it.
        if kind == .phoneLine { return .recap(.server) }
        if onDeviceAvailable { return .recap(.onDevice) }
        if serverYes { return .recap(.server) }
        return .skip(.noWriter)
    }

    /// The person's words in a conversation, counted the way `RecapRules` compares them.
    public static func wordCount(_ text: String) -> Int { RecapRules.words(text).count }
}

/// The note a recap becomes. The words around the points are passed in (`Labels`) because the app
/// localizes them; the points are in the conversation's language.
public enum RecapMemoryText {
    public struct Labels: Equatable, Sendable {
        public var title: String
        public var discussed: String
        public var agreed: String
        public var toDo: String
        public var writtenBy: String

        public init(title: String, discussed: String, agreed: String, toDo: String, writtenBy: String) {
            self.title = title
            self.discussed = discussed
            self.agreed = agreed
            self.toDo = toDo
            self.writtenBy = writtenBy
        }
    }

    /// The note's text: the title, then each list that has points, then what wrote it. Throws when it
    /// would not fit in a note; it is never cut down.
    public static func text(_ recap: ConversationRecap, labels: Labels) throws(RecapError) -> String {
        var out: [String] = [labels.title]
        for (label, points) in [(labels.discussed, recap.discussed), (labels.agreed, recap.agreed), (labels.toDo, recap.toDo)]
        where !points.isEmpty {
            out.append("")
            out.append(label)
            out.append(contentsOf: points.map { "• \($0)" })
        }
        out.append("")
        out.append(labels.writtenBy)
        let text = out.joined(separator: "\n")
        let length = text.unicodeScalars.count
        guard length <= MemoryLimits.maxTextLength else { throw .tooLongForANote(length: length) }
        return text
    }

    /// The validated note to save: source `conversation_recap`, dated when the conversation ended.
    public static func newMemory(_ recap: ConversationRecap, labels: Labels) throws -> NewMemory {
        try NewMemory(text: try text(recap, labels: labels), category: .other, source: .conversationRecap,
                      capturedAt: recap.endedAt)
    }
}
