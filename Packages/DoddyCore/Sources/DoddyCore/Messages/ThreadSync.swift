import Foundation

/// Messages on the web (owner, 28 Oct 2026: "sync always on"). After every change to the thread the iPhone sends its
/// newest messages to Doddy's server (`PUT /v1/web/messages`), which keeps them encrypted for Doddy Web to show;
/// "Delete conversation" deletes that copy too (`DELETE /v1/web/messages`) and says so only when the server confirms.
/// Text only: a photo is never sent here, only that a message had one; a file is its name and kind, never its link.
public enum ThreadSync {
    /// The same bound the server enforces.
    public static let maxMessages = 200
    public static let maxText = 10_000

    public struct Snapshot: Encodable, Equatable, Sendable {
        public let messages: [Item]
    }

    public struct Item: Encodable, Equatable, Sendable {
        public struct File: Encodable, Equatable, Sendable {
            public let name: String
            public let kind: String
        }

        public let id: String
        public let sender: String
        public let text: String
        public let createdAt: String
        public let delivery: String?
        public let hasPhoto: Bool?
        public let file: File?
    }

    /// The newest messages, oldest first, in the server's shape. A text longer than the server keeps is cut (the
    /// iPhone keeps it whole); a file kind the server doesn't know is sent as "text".
    public static func snapshot(of messages: [ThreadMessage]) -> Snapshot {
        let newest = messages.sorted { $0.createdAt < $1.createdAt }.suffix(maxMessages)
        return Snapshot(messages: newest.compactMap { message in
            let text = String(String.UnicodeScalarView(message.text.unicodeScalars.prefix(maxText)))
            guard !text.allSatisfy(\.isWhitespace) else { return nil }
            let file = message.document.map { document -> Item.File in
                let name = String(document.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
                let kind = ["deck", "doc", "spreadsheet", "pdf", "text"].contains(document.kind) ? document.kind : "text"
                return Item.File(name: name.isEmpty ? document.label : name, kind: kind)
            }
            return Item(
                id: message.id.uuidString.lowercased(), sender: message.sender.rawValue, text: text,
                createdAt: isoMilliseconds(message.createdAt),
                delivery: message.sender == .user ? message.delivery.rawValue : nil,
                hasPhoto: message.hasPhoto ? true : nil, file: file)
        })
    }

    static func isoMilliseconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

public protocol ThreadSyncClient: Sendable {
    /// Replaces the server's copy with this snapshot (an empty one deletes it).
    func send(_ snapshot: ThreadSync.Snapshot) async throws(WebLinkError)
    /// Deletes the server's copy. Returns only when the server said it is gone.
    func deleteAll() async throws(WebLinkError)
}

/// The same server and session as the Files list (`BackendMadeDocumentsClient`).
public struct BackendThreadSyncClient: ThreadSyncClient {
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

    public func send(_ snapshot: ThreadSync.Snapshot) async throws(WebLinkError) {
        let body: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            body = try encoder.encode(snapshot)
        } catch {
            throw .unreadable
        }
        let (status, data) = try await request("PUT", body: body)
        let reply: Stored = try BackendWebLinkClient.decode(status: status, data: data)
        guard reply.stored, reply.count == snapshot.messages.count else { throw .unreadable }
    }

    public func deleteAll() async throws(WebLinkError) {
        let (status, data) = try await request("DELETE", body: nil)
        let reply: Deleted = try BackendWebLinkClient.decode(status: status, data: data)
        guard reply.deleted else { throw .unreadable }
    }

    struct Stored: Decodable {
        let stored: Bool
        let count: Int
    }

    struct Deleted: Decodable {
        let deleted: Bool
    }

    private func request(_ method: String, body: Data?) async throws(WebLinkError) -> (Int, Data) {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        var headers = ["authorization": "Bearer \(token)", "accept": "application/json"]
        if body != nil { headers["content-type"] = "application/json" }
        let request = HTTPRequest(method: method, url: baseURL.appendingPathComponent("v1/web/messages"), headers: headers, body: body)
        do {
            let reply = try await transport.send(request)
            return (reply.status, reply.body)
        } catch {
            throw .transport
        }
    }
}
