import Foundation

/// ADR-579: Doddy on the web. The browser has no sign-in of its own yet, so the iPhone vouches for
/// it: the phone asks Doddy's server for a short code, the person types it at the web address the
/// phone shows, and that browser is signed in to the same account. The phone also lists the signed-in
/// browsers and signs any of them out. This is the HTTP side, kept here so it is tested on Linux;
/// the screen is `DoddyApp/Features/Web/WebSignInView.swift`.
public struct WebLinkCode: Equatable, Sendable {
    /// Eight letters and digits as two groups of four ("K7QM-4XPA").
    public let code: String
    public let expiresAt: Date
    /// Where to type it. Shown on the phone so a look-alike site stands out.
    public let webOrigin: URL

    /// What the phone shows as the address: the host (and port), without the scheme for https.
    public var displayAddress: String {
        guard let host = webOrigin.host else { return webOrigin.absoluteString }
        let port = webOrigin.port.map { ":\($0)" } ?? ""
        return webOrigin.scheme == "https" ? "\(host)\(port)" : "\(webOrigin.scheme ?? "http")://\(host)\(port)"
    }

    /// Whole seconds left, never negative.
    public func secondsLeft(at now: Date) -> Int {
        max(0, Int(expiresAt.timeIntervalSince(now).rounded(.down)))
    }
}

/// A browser signed in to Doddy on the web.
public struct WebBrowserSession: Equatable, Sendable, Identifiable {
    public enum Browser: String, Sendable, CaseIterable {
        case chrome, edge, firefox, safari, opera, other
    }

    public enum System: String, Sendable, CaseIterable {
        case macos, windows, ios, ipados, android, linux, chromeos, other
    }

    public let id: UUID
    public let browser: Browser
    public let system: System
    public let createdAt: Date
    public let lastSeenAt: Date
    /// When it is signed out at the latest (30 days, or 14 unused).
    public let expiresAt: Date
}

public enum WebLinkError: Error, Equatable, Sendable {
    /// No server or no session in this build.
    case notConfigured
    case unauthenticated
    case rateLimited(retryAfterSeconds: Int?)
    /// That browser is already signed out.
    case notFound
    case transport
    /// The reply didn't match the contract; nothing is shown instead.
    case unreadable
    case server(message: String)
}

public protocol WebLinkClient: Sendable {
    func newCode() async throws(WebLinkError) -> WebLinkCode
    func browsers() async throws(WebLinkError) -> [WebBrowserSession]
    func signOut(browser id: UUID) async throws(WebLinkError)
}

public struct BackendWebLinkClient: WebLinkClient {
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

    public func newCode() async throws(WebLinkError) -> WebLinkCode {
        let reply: CodeReply = try await call("POST", "v1/web/link-codes", body: Data("{}".utf8))
        guard Self.isCode(reply.code),
              let expiresAt = DeviceSessionClient.parseDate(reply.expiresAt),
              let origin = URL(string: reply.webOrigin), Self.isWebOrigin(origin)
        else { throw .unreadable }
        return WebLinkCode(code: reply.code, expiresAt: expiresAt, webOrigin: origin)
    }

    public func browsers() async throws(WebLinkError) -> [WebBrowserSession] {
        let reply: SessionsReply = try await call("GET", "v1/web/sessions", body: nil)
        var sessions: [WebBrowserSession] = []
        for item in reply.sessions {
            guard let id = UUID(uuidString: item.id),
                  let created = DeviceSessionClient.parseDate(item.createdAt),
                  let seen = DeviceSessionClient.parseDate(item.lastSeenAt),
                  let expires = DeviceSessionClient.parseDate(item.expiresAt)
            else { throw .unreadable }
            sessions.append(WebBrowserSession(
                id: id,
                browser: WebBrowserSession.Browser(rawValue: item.browser) ?? .other,
                system: WebBrowserSession.System(rawValue: item.os) ?? .other,
                createdAt: created, lastSeenAt: seen, expiresAt: expires))
        }
        return sessions
    }

    public func signOut(browser id: UUID) async throws(WebLinkError) {
        let _: SignedOutReply = try await call("DELETE", "v1/web/sessions/\(id.uuidString.lowercased())", body: nil)
    }

    // MARK: - contract

    struct CodeReply: Decodable {
        let code: String
        let expiresAt: String
        let webOrigin: String
    }

    struct SessionsReply: Decodable {
        struct Item: Decodable {
            let id: String
            let browser: String
            let os: String
            let createdAt: String
            let lastSeenAt: String
            let expiresAt: String
        }
        let sessions: [Item]
    }

    struct SignedOutReply: Decodable {
        let signedOut: Bool
    }

    /// Eight characters from the server's alphabet (no I, L, O, U, 0 or 1), as two groups of four.
    static func isCode(_ text: String) -> Bool {
        text.range(of: "^[A-HJKMNP-TV-Z2-9]{4}-[A-HJKMNP-TV-Z2-9]{4}$", options: .regularExpression) != nil
    }

    /// The address to type the code at: an https origin (http only on this device, for development).
    static func isWebOrigin(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/"
        else { return false }
        return url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host))
    }

    private func call<Response: Decodable>(_ method: String, _ path: String, body: Data?) async throws(WebLinkError) -> Response {
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

    static func decode<Response: Decodable>(status: Int, data: Data) throws(WebLinkError) -> Response {
        if (200..<300).contains(status) {
            do { return try JSONDecoder().decode(Response.self, from: data) } catch { throw .unreadable }
        }
        switch status {
        case 401: throw .unauthenticated
        case 404: throw .notFound
        default: break
        }
        guard let body = try? JSONDecoder().decode(OnlineErrorBody.self, from: data) else { throw .unreadable }
        if status == 429 || body.error.code == "rate_limited" { throw .rateLimited(retryAfterSeconds: body.error.retryAfterSeconds) }
        throw .server(message: body.error.message)
    }
}
