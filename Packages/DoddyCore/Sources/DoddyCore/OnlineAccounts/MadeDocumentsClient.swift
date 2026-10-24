import Foundation

/// Files Doddy made on his server (ADR-564), as the iPhone's Files sheet lists them (ADR-633). It reads
/// the same `GET /v1/web/documents` the web app uses (ADR-600), with the iPhone's own session, so no new
/// server route is needed. A file's bytes are fetched only when the person taps it, from
/// `GET /v1/web/documents/:id/file`. The server keeps each file a week and says so (`keptDays`); the
/// list never claims a file is ready before the server says `ready`.
public struct MadeDocument: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case deck, doc, spreadsheet, pdf, text, file
    }

    public enum Status: String, Sendable, CaseIterable {
        /// Claude is still making it.
        case working
        case ready
        case failed
        /// It stayed `working` too long: the job stopped without finishing (the server decides).
        case interrupted
    }

    /// 24 characters from the server (`[A-Za-z0-9_-]`), never anything else (it goes in a path).
    public let id: String
    public let name: String
    public let kind: Kind
    public let status: Status
    public let createdAt: Date
    /// When the server deletes it.
    public let deleteAfter: Date
    /// Only for a ready file.
    public let sizeBytes: Int?

    public init(id: String, name: String, kind: Kind, status: Status, createdAt: Date, deleteAfter: Date, sizeBytes: Int?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.deleteAfter = deleteAfter
        self.sizeBytes = sizeBytes
    }

    /// Only a ready file can be opened; the others say what happened instead.
    public var canOpen: Bool { status == .ready }

    /// A name that is safe as one file in a folder: no folders, no control characters, not hidden,
    /// not empty, at most 120 characters (the extension kept).
    public var safeFileName: String { Self.safeFileName(name) }

    public static func safeFileName(_ name: String) -> String {
        let cleaned = String(name.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || "/\\:".unicodeScalars.contains(scalar) { return "_" }
            return Character(scalar)
        })
        var trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix(".") { trimmed.removeFirst() }
        if trimmed.isEmpty { return "Document" }
        guard trimmed.count > 120 else { return trimmed }
        let ext = (trimmed as NSString).pathExtension
        let keep = ext.isEmpty || ext.count > 10 ? 120 : 120 - ext.count - 1
        let base = String(trimmed.prefix(keep))
        return ext.isEmpty || ext.count > 10 ? base : "\(base).\(ext)"
    }

    static func isID(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9_-]{24}$", options: .regularExpression) != nil
    }
}

public struct MadeDocumentList: Equatable, Sendable {
    public let documents: [MadeDocument]
    /// How many days the server keeps a file (seven, ADR-564).
    public let keptDays: Int

    public init(documents: [MadeDocument], keptDays: Int) {
        self.documents = documents
        self.keptDays = keptDays
    }
}

public protocol MadeDocumentsClient: Sendable {
    func documents() async throws(WebLinkError) -> MadeDocumentList
    /// The file's bytes. `notFound` once the server no longer keeps it or it has no file yet.
    func file(of document: MadeDocument) async throws(WebLinkError) -> Data
}

public struct BackendMadeDocumentsClient: MadeDocumentsClient {
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

    public func documents() async throws(WebLinkError) -> MadeDocumentList {
        let (status, data) = try await send("v1/web/documents", accept: "application/json")
        let reply: ListReply = try BackendWebLinkClient.decode(status: status, data: data)
        guard reply.keptDays > 0 else { throw .unreadable }
        var documents: [MadeDocument] = []
        for item in reply.documents {
            guard MadeDocument.isID(item.id),
                  let kind = MadeDocument.Kind(rawValue: item.kind),
                  let state = MadeDocument.Status(rawValue: item.status),
                  let created = DeviceSessionClient.parseDate(item.createdAt),
                  let deleteAfter = DeviceSessionClient.parseDate(item.deleteAfter)
            else { throw .unreadable }
            documents.append(MadeDocument(
                id: item.id, name: item.name, kind: kind, status: state,
                createdAt: created, deleteAfter: deleteAfter,
                sizeBytes: state == .ready ? item.sizeBytes : nil))
        }
        return MadeDocumentList(documents: documents, keptDays: reply.keptDays)
    }

    public func file(of document: MadeDocument) async throws(WebLinkError) -> Data {
        guard MadeDocument.isID(document.id) else { throw .notFound }
        let (status, data) = try await send("v1/web/documents/\(document.id)/file", accept: "*/*")
        guard (200..<300).contains(status) else {
            // The error replies are JSON; `decode` maps them (404 is "no longer kept").
            let _: ListReply = try BackendWebLinkClient.decode(status: status, data: data)
            throw .unreadable
        }
        return data
    }

    // MARK: - contract

    struct ListReply: Decodable {
        struct Item: Decodable {
            let id: String
            let name: String
            let kind: String
            let status: String
            let createdAt: String
            let deleteAfter: String
            let sizeBytes: Int?
        }
        let documents: [Item]
        let keptDays: Int
    }

    private func send(_ path: String, accept: String) async throws(WebLinkError) -> (Int, Data) {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        let request = HTTPRequest(
            method: "GET", url: baseURL.appendingPathComponent(path),
            headers: ["authorization": "Bearer \(token)", "accept": accept], body: nil)
        do {
            let reply = try await transport.send(request)
            return (reply.status, reply.body)
        } catch {
            throw .transport
        }
    }
}
