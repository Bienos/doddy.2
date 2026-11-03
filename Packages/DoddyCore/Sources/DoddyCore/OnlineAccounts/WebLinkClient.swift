import Foundation

/// ADR-600: Doddy on the web. The browser has no sign-in of its own yet, so the iPhone vouches for
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
    /// ADR-700: which of Apple and Google the server offers for the web. Empty: the code only.
    func signInProviders() async throws(WebLinkError) -> [WebSignInProvider]
    /// Apple and Google sign-ins linked to this account.
    func linkedSignIns() async throws(WebLinkError) -> [WebLinkedSignIn]
    /// A one-time address to open in the system sign-in sheet, which links `provider` to this account.
    func linkTicket(for provider: WebSignInProvider) async throws(WebLinkError) -> WebLinkTicket
    /// Links what the sheet signed in with. Only this iPhone's session can, with the code its sheet ended with.
    func completeLink(code: String) async throws(WebLinkError) -> WebLinkOutcome
    func unlink(signIn id: UUID) async throws(WebLinkError)
}

/// ADR-700: before a server knew Apple and Google, it offered neither.
public extension WebLinkClient {
    func signInProviders() async throws(WebLinkError) -> [WebSignInProvider] { [] }
    func linkedSignIns() async throws(WebLinkError) -> [WebLinkedSignIn] { [] }
    func linkTicket(for provider: WebSignInProvider) async throws(WebLinkError) -> WebLinkTicket { throw .notConfigured }
    func completeLink(code: String) async throws(WebLinkError) -> WebLinkOutcome { throw .notConfigured }
    func unlink(signIn id: UUID) async throws(WebLinkError) { throw .notConfigured }
}

/// ADR-700: Apple or Google, as a second way into this same account on the web.
public enum WebSignInProvider: String, Sendable, CaseIterable, Equatable {
    case google, apple
}

public struct WebLinkedSignIn: Equatable, Sendable, Identifiable {
    /// The Supabase Auth user behind it (what the server unlinks by).
    public let id: UUID
    public let provider: WebSignInProvider
    public let linkedAt: Date

    public init(id: UUID, provider: WebSignInProvider, linkedAt: Date) {
        self.id = id
        self.provider = provider
        self.linkedAt = linkedAt
    }
}

/// Where the iPhone's sign-in sheet starts, and the scheme it ends at.
public struct WebLinkTicket: Equatable, Sendable {
    public let url: URL
    public let callbackScheme: String

    public init(url: URL, callbackScheme: String) {
        self.url = url
        self.callbackScheme = callbackScheme
    }

    /// How the sheet ended, read from the address it ended at (`<scheme>://web-sign-in/return?result=…`).
    /// `confirm` carries the code this iPhone redeems with its own session; nothing is linked before
    /// that. Anything else, including an address of another scheme or path, reads as `failed`.
    public func end(of callback: URL) -> WebSheetEnd {
        guard callback.scheme == callbackScheme, callback.host == "web-sign-in", callback.path == "/return",
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        else { return .done(.failed) }
        switch items.first(where: { $0.name == "result" })?.value {
        case "confirm":
            guard let code = items.first(where: { $0.name == "code" })?.value,
                  code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
            else { return .done(.failed) }
            return .confirm(code: code)
        case "canceled": return .done(.canceled)
        case "busy": return .done(.busy)
        default: return .done(.failed)
        }
    }
}

/// Where the sign-in sheet left things (ADR-700).
public enum WebSheetEnd: Equatable, Sendable {
    /// Signed in at Apple or Google; this iPhone confirms with this code to link it.
    case confirm(code: String)
    /// Nothing to confirm: how it ended.
    case done(WebLinkOutcome)
}

/// What linking Apple or Google did, as the server said it. Only `linked` and `already` mean linked.
public enum WebLinkOutcome: Equatable, Sendable {
    case linked(WebSignInProvider)
    case already(WebSignInProvider)
    /// That Apple or Google account belongs to another Doddy account; nothing was changed or merged.
    case taken(WebSignInProvider)
    case canceled
    case busy
    case failed
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

    public func signInProviders() async throws(WebLinkError) -> [WebSignInProvider] {
        do throws(WebLinkError) {
            let reply: ProvidersReply = try await call("GET", "v1/web/sign-in-options", body: nil)
            return reply.providers.compactMap(WebSignInProvider.init(rawValue:))
        } catch {
            // A server from before ADR-700, or without the web on: neither is offered.
            if error == .notFound { return [] }
            throw error
        }
    }

    public func linkedSignIns() async throws(WebLinkError) -> [WebLinkedSignIn] {
        let reply: IdentitiesReply = try await call("GET", "v1/web/identities", body: nil)
        var list: [WebLinkedSignIn] = []
        for item in reply.identities {
            guard let id = UUID(uuidString: item.id), let linkedAt = DeviceSessionClient.parseDate(item.linkedAt) else { throw .unreadable }
            // A provider this app doesn't know is left out rather than shown wrongly.
            guard let provider = WebSignInProvider(rawValue: item.provider) else { continue }
            list.append(WebLinkedSignIn(id: id, provider: provider, linkedAt: linkedAt))
        }
        return list
    }

    public func linkTicket(for provider: WebSignInProvider) async throws(WebLinkError) -> WebLinkTicket {
        let body = Data(#"{"provider":"\#(provider.rawValue)"}"#.utf8)
        let reply: TicketReply = try await call("POST", "v1/web/oauth/tickets", body: body)
        guard let url = URL(string: reply.url), Self.isTicketURL(url), Self.isAppScheme(reply.callbackScheme) else { throw .unreadable }
        return WebLinkTicket(url: url, callbackScheme: reply.callbackScheme)
    }

    public func completeLink(code: String) async throws(WebLinkError) -> WebLinkOutcome {
        guard code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw .unreadable }
        let reply: CompleteReply = try await call("POST", "v1/web/oauth/complete", body: Data(#"{"code":"\#(code)"}"#.utf8))
        guard let provider = WebSignInProvider(rawValue: reply.provider) else { throw .unreadable }
        switch reply.result {
        case "linked": return .linked(provider)
        case "already": return .already(provider)
        case "taken": return .taken(provider)
        default: throw .unreadable
        }
    }

    public func unlink(signIn id: UUID) async throws(WebLinkError) {
        let _: UnlinkedReply = try await call("DELETE", "v1/web/identities/\(id.uuidString.lowercased())", body: nil)
    }

    // MARK: - contract

    struct ProvidersReply: Decodable {
        let providers: [String]
    }

    struct IdentitiesReply: Decodable {
        struct Item: Decodable {
            let id: String
            let provider: String
            let linkedAt: String
        }
        let identities: [Item]
    }

    struct TicketReply: Decodable {
        let url: String
        let callbackScheme: String
    }

    struct CompleteReply: Decodable {
        let result: String
        let provider: String
    }

    struct UnlinkedReply: Decodable {
        let unlinked: Bool
    }

    /// The sheet opens only Doddy's own start address, on an https origin (http only on this device).
    static func isTicketURL(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil,
              url.path == "/v1/web/oauth/start",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 1, items[0].name == "ticket", items[0].value?.isEmpty == false
        else { return false }
        return url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host))
    }

    /// The sheet may only end at Doddy's own scheme.
    static func isAppScheme(_ scheme: String) -> Bool {
        scheme.range(of: "^doddy(-[a-z]+)?$", options: .regularExpression) != nil
    }

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
