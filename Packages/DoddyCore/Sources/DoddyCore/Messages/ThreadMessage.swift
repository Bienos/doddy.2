import Foundation

// The thread with Doddy (ADR-585): typed messages, in bubbles, saved on this iPhone until the user
// deletes them. It grows out of "Ask Doddy" (ADR-115), whose chat lived in memory only, so the same
// consent applies and nothing here is sent anywhere new: what goes to the server on a send is still
// the question, the last few messages and any notes shown under an answer.
// Plain Swift for the Linux tests; the screen follows these rules.

/// A file Doddy made for the person from a message (ADR-606), kept in the thread as a bubble that opens it. The
/// link opens in Safari (Quick Look and Share); until the file is ready its page says so and checks again by itself,
/// so the bubble holds no status. The words of the file are not here: only its name, kind and link.
public struct ThreadDocument: Equatable, Sendable, Codable {
    public let url: URL
    public let name: String
    /// deck, doc, spreadsheet, pdf or text.
    public let kind: String

    public init(url: URL, name: String, kind: String) {
        self.url = url
        self.name = name
        self.kind = kind
    }

    /// The file Doddy's server is making. nil when it failed or the link is not https (nothing is shown instead).
    public init?(_ document: RunDocument) {
        guard document.status != .failed, document.url.scheme?.lowercased() == "https" else { return nil }
        self.init(url: document.url, name: document.name, kind: document.kind)
    }

    /// For the bubble: "Deck", "Document", …
    public var label: String {
        switch kind {
        case "deck": "Deck"
        case "doc": "Document"
        case "spreadsheet": "Spreadsheet"
        case "pdf": "PDF"
        default: "Text"
        }
    }
}

/// One message of the thread. A user message carries its delivery state; a Doddy message is
/// always `.sent` (it exists only because it arrived).
public struct ThreadMessage: Equatable, Sendable, Identifiable, Codable {
    public enum Sender: String, Sendable, Equatable, Codable {
        case user, doddy
    }

    /// Of a message the user sent: on its way, answered, or not delivered. Never "read": nothing
    /// here can know that, so nothing says it.
    public enum Delivery: String, Sendable, Equatable, Codable {
        case sending, sent, failed
    }

    /// Where a Doddy answer comes from, as `VerifiedAnswer` decided: the user's saved notes (the
    /// note ids are kept so the screen can show them), or a general answer that is not from them.
    public enum Basis: String, Sendable, Equatable, Codable {
        case savedNotes, general
    }

    public let id: UUID
    public let sender: Sender
    public let text: String
    public let createdAt: Date
    public var delivery: Delivery
    /// Doddy's messages only.
    public let basis: Basis?
    /// The notes an answer cites, in order (Doddy's messages only).
    public let noteIDs: [UUID]
    /// How many saved notes left the iPhone with the question this answers.
    public let notesSent: Int
    /// Searching the notes failed, so the question went without them.
    public let notesSearchFailed: Bool
    /// A file Doddy made after the person tapped Make (Doddy's messages only, ADR-606).
    public let document: ThreadDocument?

    public init(
        id: UUID = UUID(), sender: Sender, text: String, createdAt: Date, delivery: Delivery,
        basis: Basis? = nil, noteIDs: [UUID] = [], notesSent: Int = 0, notesSearchFailed: Bool = false,
        document: ThreadDocument? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.createdAt = createdAt
        self.delivery = delivery
        self.basis = basis
        self.noteIDs = noteIDs
        self.notesSent = notesSent
        self.notesSearchFailed = notesSearchFailed
        self.document = document
    }

    /// A message the user is sending now.
    public static func user(_ text: String, now: Date = Date(), id: UUID = UUID()) -> ThreadMessage {
        ThreadMessage(id: id, sender: .user, text: text, createdAt: now, delivery: .sending)
    }

    /// Doddy's answer, from what the assistant returned.
    public static func doddy(_ answer: AssistantAnswer, now: Date = Date(), id: UUID = UUID()) -> ThreadMessage {
        ThreadMessage(
            id: id, sender: .doddy, text: answer.answer.text, createdAt: now, delivery: .sent,
            basis: answer.answer.basis == .savedNotes ? .savedNotes : .general,
            noteIDs: answer.answer.sources.map(\.id), notesSent: answer.notesSent.count,
            notesSearchFailed: answer.notesSearchFailed)
    }
}

extension ThreadMessage {
    /// The bubble for a file Doddy made. It is not from the user's notes, so its basis is "general"; its text is the
    /// file's name (never empty, which the table requires).
    public static func file(_ document: ThreadDocument, now: Date = Date(), id: UUID = UUID()) -> ThreadMessage {
        let name = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ThreadMessage(
            id: id, sender: .doddy, text: name.isEmpty ? document.label : name, createdAt: now, delivery: .sent,
            basis: .general, document: document)
    }
}

public enum MessageThreadError: Error, Equatable, Sendable {
    /// A write was read back and did not match, so it is not called saved.
    case verificationFailed
    case notFound
}

/// The thread, on this iPhone.
public protocol MessageThreadRepository: Sendable {
    /// The newest `limit` messages, oldest first.
    func recent(limit: Int) async throws -> [ThreadMessage]
    /// Saves one message, then reads it back; it throws unless it matches.
    func append(_ message: ThreadMessage) async throws
    /// Changes the delivery state of a message the user sent.
    func setDelivery(id: UUID, _ delivery: ThreadMessage.Delivery) async throws
    /// Anything still "sending" when nothing is sending (the app was closed mid-send) is not delivered.
    /// Returns how many.
    func failUnfinished() async throws -> Int
    func delete(id: UUID) async throws
    /// Every message, read back as gone.
    func deleteAll() async throws
    /// Everything kept, for the user's own export.
    func export() async throws -> Data
}

public struct UnavailableMessageThreadRepository: MessageThreadRepository {
    public init() {}
    public func recent(limit: Int) async throws -> [ThreadMessage] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func append(_ message: ThreadMessage) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func setDelivery(id: UUID, _ delivery: ThreadMessage.Delivery) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func failUnfinished() async throws -> Int { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func delete(id: UUID) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func deleteAll() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func export() async throws -> Data { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}
