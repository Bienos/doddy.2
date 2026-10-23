import Foundation

/// ADR-595: notes and conversations kept on Doddy's server, as text, when the person turns that on.
/// This is the HTTP side and the shapes it sends, kept here so they are tested on Linux; the rules
/// for when to send are `WebMemoryModel`, and the screen is `DoddyApp/Features/Web/WebMemoryView.swift`.
///
/// What the server accepts is an allow-list (`backend/src/memory/contract.ts`): a note is its id,
/// text, how it was saved, its type and when; a conversation is its turns as text. No audio, no
/// private notes (ADR-310), no lists, no sample notes.

public enum WebMemoryError: Error, Equatable, Sendable {
    /// No server or no session in this build.
    case notConfigured
    case unauthenticated
    /// The server says that kind is switched off (403): it was deleted from the web, say. Nothing was stored.
    case off
    /// 413: more than one person may keep on the server.
    case tooLarge
    /// 503: the server has no key for this, so it keeps nothing.
    case notSetUp
    case rateLimited(retryAfterSeconds: Int?)
    case transport
    /// The reply didn't match the contract; nothing is claimed instead.
    case unreadable
    case server(message: String)
}

/// What the server says after the switches are set or everything is deleted.
public struct WebMemoryState: Equatable, Sendable, Decodable {
    public let notes: Bool
    public let conversations: Bool
    public let deletedNotes: Int
    public let deletedConversations: Int

    public init(notes: Bool, conversations: Bool, deletedNotes: Int = 0, deletedConversations: Int = 0) {
        self.notes = notes
        self.conversations = conversations
        self.deletedNotes = deletedNotes
        self.deletedConversations = deletedConversations
    }
}

/// One note as kept on the server. Built only through `from`, which needs the set of private notes,
/// so there is no way to make upload items without leaving them out.
public struct KeptNote: Equatable, Sendable, Encodable {
    /// The server accepts at most this many; over it, the newest are sent.
    public static let maxNotes = 5_000

    public let id: UUID
    public let text: String
    /// A `MemorySource` raw value the server knows.
    public let source: String
    /// A `MemoryCategory` raw value for a note type; nil for none.
    public let kind: String?
    public let capturedAt: String?

    enum CodingKeys: String, CodingKey { case id, text, source, kind, capturedAt }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(capturedAt, forKey: .capturedAt)
    }

    /// Notes the person can see as notes, minus private ones (ADR-310), sample notes, lists (whose text
    /// is only a name) and blank ones, each once. Over `maxNotes`, the newest.
    public static func from(_ records: [MemoryRecord], excluding privateNotes: PrivateNotes) -> [KeptNote] {
        var seen = Set<UUID>()
        var eligible = privateNotes.shareable(records).filter {
            $0.source != .sampleFixture && $0.category != .list
                && !$0.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert($0.id).inserted
        }
        if eligible.count > maxNotes {
            eligible.sort { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            eligible = Array(eligible.prefix(maxNotes))
        }
        return eligible.map {
            KeptNote(id: $0.id, text: $0.currentText, source: $0.source.rawValue, kind: $0.category.rawValue, capturedAt: $0.capturedAt.map(ServerDates.format))
        }
    }
}

/// One finished conversation as kept on the server: the turns as text, nothing else of it.
public struct KeptConversation: Equatable, Sendable, Encodable {
    public struct Turn: Equatable, Sendable, Encodable {
        public let role: String
        public let text: String
    }

    public static let maxTurns = 400
    public static let maxTurnCharacters = 4_000
    /// The server keeps a year; one started before this is not sent.
    public static let sendableDays = 364

    /// Not part of the body: it is in the address.
    public let id: UUID
    public let startedAt: String
    public let endedAt: String
    public let language: String?
    public let endedBy: String?
    public let turns: [Turn]

    enum CodingKeys: String, CodingKey { case startedAt, endedAt, language, endedBy, turns }

    /// Whether this conversation may go to the server at all: only when the person turned that on, it
    /// isn't a private conversation, and something was said. Separate from "Remember recent
    /// conversations", which is about what this iPhone keeps.
    public static func mayBeSent(keptOnServer: Bool, isPrivate: Bool, lineCount: Int) -> Bool {
        keptOnServer && !isPrivate && lineCount > 0
    }

    /// Nil when nothing in it can be sent (no readable line, or too old for the server's year).
    public static func from(_ log: ConversationLog, language: String?, now: Date = Date()) -> KeptConversation? {
        guard now.timeIntervalSince(log.startedAt) < Double(sendableDays) * 86_400 else { return nil }
        let turns = log.lines.compactMap { line -> Turn? in
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Turn(role: line.fromUser ? "user" : "doddy", text: String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(maxTurnCharacters))))
        }
        guard !turns.isEmpty else { return nil }
        return KeptConversation(
            id: log.id,
            startedAt: ServerDates.format(log.startedAt),
            endedAt: ServerDates.format(max(log.endedAt, log.startedAt)),
            language: language.flatMap(validLanguage),
            endedBy: log.ended.flatMap(endedBy),
            turns: Array(turns.suffix(maxTurns)))
    }

    /// `VoiceSessionEnd.code` ("user", "doddy", "quiet", "dropped-…") as the server names it.
    static func endedBy(_ code: String) -> String? {
        switch code {
        case "user": "you"
        case "doddy": "doddy"
        case "quiet": "quiet"
        default: code.hasPrefix("dropped") ? "dropped" : nil
        }
    }

    static func validLanguage(_ code: String) -> String? {
        code.range(of: "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$", options: .regularExpression) != nil ? code : nil
    }
}

public protocol WebMemoryClient: Sendable {
    /// Sets both switches on the server. A kind that goes off is deleted there in the same step.
    func setState(notes: Bool, conversations: Bool) async throws(WebMemoryError) -> WebMemoryState
    /// Replaces the server's notes with exactly these (so a deleted note goes too). Returns how many it holds.
    func replaceNotes(_ items: [KeptNote]) async throws(WebMemoryError) -> Int
    func putConversation(_ conversation: KeptConversation) async throws(WebMemoryError)
    /// Deletes everything kept and switches both kinds off.
    func deleteAll() async throws(WebMemoryError) -> WebMemoryState
}

public struct BackendWebMemoryClient: WebMemoryClient {
    private let baseURL: URL
    private let sessionToken: @Sendable () -> String?
    private let transport: any HTTPTransport

    /// `baseURL` must be https, or http on a loopback host for local development.
    public init?(baseURL: URL, sessionToken: @escaping @Sendable () -> String?, transport: any HTTPTransport) {
        guard BackendConnectedAppsClient.isAllowed(baseURL) else { return nil }
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.transport = transport
    }

    /// Same, with a token that is sent only to the server it was issued for.
    public init?(baseURL: URL, boundToken: @escaping @Sendable () -> BoundSessionToken?, transport: any HTTPTransport) {
        self.init(baseURL: baseURL, sessionToken: { boundToken()?.token(for: baseURL) }, transport: transport)
    }

    public func setState(notes: Bool, conversations: Bool) async throws(WebMemoryError) -> WebMemoryState {
        let state: WebMemoryState = try await call("PUT", "v1/web/memory/state", body: try Self.json(StateBody(notes: notes, conversations: conversations)))
        guard state.notes == notes, state.conversations == conversations else { throw .unreadable }
        return state
    }

    public func replaceNotes(_ items: [KeptNote]) async throws(WebMemoryError) -> Int {
        let reply: CountReply = try await call("PUT", "v1/web/memory/notes", body: try Self.json(NotesBody(items: items)))
        guard reply.count == items.count else { throw .unreadable }
        return reply.count
    }

    public func putConversation(_ conversation: KeptConversation) async throws(WebMemoryError) {
        let reply: StoredReply = try await call("PUT", "v1/web/memory/conversations/\(conversation.id.uuidString.lowercased())", body: try Self.json(conversation))
        guard reply.stored else { throw .unreadable }
    }

    public func deleteAll() async throws(WebMemoryError) -> WebMemoryState {
        try await call("DELETE", "v1/web/memory", body: nil)
    }

    // MARK: - contract

    private struct StateBody: Encodable { let notes: Bool; let conversations: Bool }
    private struct NotesBody: Encodable { let items: [KeptNote] }
    struct CountReply: Decodable { let count: Int }
    struct StoredReply: Decodable { let stored: Bool }

    private static func json<Body: Encodable>(_ body: Body) throws(WebMemoryError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do { return try encoder.encode(body) } catch { throw .unreadable }
    }

    private func call<Response: Decodable>(_ method: String, _ path: String, body: Data?) async throws(WebMemoryError) -> Response {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        var headers = ["authorization": "Bearer \(token)", "accept": "application/json"]
        if body != nil { headers["content-type"] = "application/json" }
        let request = HTTPRequest(method: method, url: baseURL.appendingPathComponent(path), headers: headers, body: body)
        let status: Int
        let payload: Data
        do {
            (status, payload) = try await transport.send(request)
        } catch {
            throw .transport
        }
        return try Self.decode(status: status, data: payload)
    }

    static func decode<Response: Decodable>(status: Int, data: Data) throws(WebMemoryError) -> Response {
        if (200..<300).contains(status) {
            do { return try JSONDecoder().decode(Response.self, from: data) } catch { throw .unreadable }
        }
        if status == 401 { throw .unauthenticated }
        if status == 413 { throw .tooLarge }
        guard let body = try? JSONDecoder().decode(OnlineErrorBody.self, from: data) else { throw .unreadable }
        if status == 429 || body.error.code == "rate_limited" { throw .rateLimited(retryAfterSeconds: body.error.retryAfterSeconds) }
        if status == 403 && body.error.code == "capability_disabled" { throw .off }
        if status == 503 && body.error.code == "live_not_configured" { throw .notSetUp }
        throw .server(message: body.error.message)
    }
}
