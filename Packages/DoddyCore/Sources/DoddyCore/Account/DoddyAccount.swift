import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account, a Supabase
// Auth user (ADR-526) made with Sign in with Apple, Google, or a code sent by email. Nobody uses
// Doddy without one. This file is everything about that account that isn't UI or Keychain: the
// requests to Supabase Auth, the rules for codes and sessions, and the calls that bring an iPhone's
// earlier data on Doddy's servers into the account. It is tested on Linux; the app supplies the
// HTTP transport, Apple's sign-in sheet, the browser sheet for Google and the Keychain.
//
// The app talks to Supabase Auth itself, with the project's publishable key (meant for clients, not a
// secret): Supabase limits sign-ins per address, and going through one of Doddy's servers would put
// every person behind that server's single address.

/// How a Doddy account signs in. These three only: no passwords, no phone, no anonymous accounts.
public enum DoddyAccountMethod: String, Codable, Sendable, CaseIterable {
    case apple, google, email
}

/// Where the Doddy accounts live. From Info.plist; nil in a build without accounts set up.
public struct DoddyAccountConfig: Equatable, Sendable {
    /// `https://<ref>.supabase.co`.
    public let projectURL: URL
    /// The project's publishable key: public, sent as `apikey`.
    public let publishableKey: String
    /// Where Google's browser sign-in comes back to the app, e.g. `doddy://auth-callback`.
    public let redirectURL: URL

    public init?(projectURL: URL?, publishableKey: String?, redirectURL: URL?) {
        guard let projectURL, projectURL.scheme == "https", let host = projectURL.host, !host.isEmpty,
              let key = publishableKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty, key.count <= 512,
              let redirectURL, let scheme = redirectURL.scheme, scheme != "http", scheme != "https", redirectURL.host != nil
        else { return nil }
        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        origin.port = projectURL.port
        guard let clean = origin.url else { return nil }
        self.projectURL = clean
        self.publishableKey = key
        self.redirectURL = redirectURL
    }
}

/// A signed-in Doddy account. Kept in the Keychain (this device only); the access token is what every
/// Doddy server checks, and the refresh token gets a new one when it runs out (about an hour).
public struct DoddyAccountSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    /// The Supabase user's UUID: the account's id on every Doddy server.
    public let userID: String
    /// What Settings shows. For Apple it may be a private relay address.
    public let email: String?
    public let method: DoddyAccountMethod

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String, email: String?, method: DoddyAccountMethod) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
        self.method = method
    }

    /// True while the access token has more than `margin` left; otherwise refresh before using it.
    public func isFresh(at now: Date, margin: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) > margin
    }

    /// `Authorization` for Doddy's servers.
    public var authorization: String { "Bearer \(accessToken)" }
}

public enum DoddyAccountError: Error, Equatable, Sendable {
    /// This build has no Doddy accounts set up (no project in Info.plist).
    case notConfigured
    case invalidEmail
    /// The code is wrong or has expired.
    case invalidCode
    case rateLimited
    /// Supabase refused this sign-in (Apple or Google said no, or the account isn't allowed).
    case refused
    /// The saved sign-in no longer works: the person signs in again.
    case signedOut
    case offline
    /// Supabase answered with an error or something unreadable. Try again later.
    case unavailable

    public var userMessage: String {
        switch self {
        case .notConfigured: "Sign-in isn't set up in this build of Doddy yet."
        case .invalidEmail: "That doesn't look like an email address. Check it and try again."
        case .invalidCode: "That code is wrong or has expired. Check it, or ask for a new one."
        case .rateLimited: "Too many tries for now. Wait a minute, then try again."
        case .refused: "That sign-in didn't work. Try again, or use another way to sign in."
        case .signedOut: "You were signed out. Sign in again to keep using Doddy."
        case .offline: "Doddy couldn't reach the sign-in service. Check your connection and try again."
        case .unavailable: "The sign-in service had a problem. Try again in a moment."
        }
    }
}

/// An email address as typed: trimmed and lowercased, or nil unless it plausibly is one. Supabase
/// checks the rest by sending the code.
public enum EmailAddress {
    public static func normalized(_ text: String) -> String? {
        let email = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.count <= 254, !email.contains(where: { $0.isWhitespace }) else { return nil }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let local = parts.first, let domain = parts.last,
              !local.isEmpty, local.count <= 64,
              domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains("..")
        else { return nil }
        return email
    }
}

/// The code from the email: digits only (spaces and dashes the person typed are dropped), 6 to 10 of them.
public enum EmailCode {
    public static func normalized(_ text: String) -> String? {
        let kept = text.filter { !$0.isWhitespace && $0 != "-" }
        guard (6...10).contains(kept.count), kept.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return kept
    }
}

/// PKCE (RFC 7636) for Google's browser sign-in: the verifier stays on the iPhone, only its hash travels.
public struct PKCEPair: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    /// From 32 random bytes: a 43-character verifier and its S256 challenge.
    public static func make(randomBytes: [UInt8]) -> PKCEPair {
        let verifier = base64URL(Data(randomBytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        return PKCEPair(verifier: verifier, challenge: challenge)
    }

    public static func random() -> PKCEPair {
        var generator = SystemRandomNumberGenerator()
        return make(randomBytes: (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The requests to Supabase Auth. Every call either returns a checked session or throws a
/// `DoddyAccountError`; a session is never assumed.
public struct DoddyAccountClient: Sendable {
    public let config: DoddyAccountConfig
    private let transport: any HTTPTransport

    public init(config: DoddyAccountConfig, transport: any HTTPTransport) {
        self.config = config
        self.transport = transport
    }

    // MARK: Email

    /// Sends a code to `email`. A new address gets a new account when the code is used.
    public func sendEmailCode(to email: String) async throws(DoddyAccountError) {
        guard let address = EmailAddress.normalized(email) else { throw .invalidEmail }
        let response = try await post("otp", body: ["email": address, "create_user": true])
        switch response.status {
        case 200..<300: return
        case 429: throw .rateLimited
        case 400, 422: throw .invalidEmail
        default: throw .unavailable
        }
    }

    public func verifyEmailCode(email: String, code: String, now: Date) async throws(DoddyAccountError) -> DoddyAccountSession {
        guard let address = EmailAddress.normalized(email) else { throw .invalidEmail }
        guard let token = EmailCode.normalized(code) else { throw .invalidCode }
        let response = try await post("verify", body: ["type": "email", "email": address, "token": token])
        return try session(from: response, now: now, method: .email, refusedAs: .invalidCode)
    }

    // MARK: Apple

    /// Exchanges Sign in with Apple's identity token. `rawNonce` is the one whose SHA-256 went to Apple.
    public func signInWithApple(identityToken: String, rawNonce: String, now: Date) async throws(DoddyAccountError) -> DoddyAccountSession {
        guard !identityToken.isEmpty, identityToken.count <= 16_384, !rawNonce.isEmpty else { throw .refused }
        let response = try await post(
            "token", query: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: ["provider": "apple", "id_token": identityToken, "nonce": rawNonce])
        return try session(from: response, now: now, method: .apple, refusedAs: .refused)
    }

    // MARK: Google

    /// Where the browser sheet opens for Google. It comes back to `config.redirectURL` with `?code=`.
    public func googleAuthorizeURL(pkce: PKCEPair) -> URL {
        var components = URLComponents(url: config.projectURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: config.redirectURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return components.url!
    }

    /// The code from the browser sheet's return, or nil when it isn't our return or Google said no.
    public func googleCode(from callback: URL) -> String? {
        guard callback.scheme == config.redirectURL.scheme, callback.host == config.redirectURL.host,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              !items.contains(where: { $0.name == "error" }),
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.count <= 512
        else { return nil }
        return code
    }

    public func exchangeGoogleCode(_ code: String, pkce: PKCEPair, now: Date) async throws(DoddyAccountError) -> DoddyAccountSession {
        guard !code.isEmpty else { throw .refused }
        let response = try await post(
            "token", query: [URLQueryItem(name: "grant_type", value: "pkce")],
            body: ["auth_code": code, "code_verifier": pkce.verifier])
        return try session(from: response, now: now, method: .google, refusedAs: .refused)
    }

    // MARK: Keeping it signed in

    /// A new access token for `session`. `.signedOut` when the refresh token no longer works.
    public func refresh(_ session: DoddyAccountSession, now: Date) async throws(DoddyAccountError) -> DoddyAccountSession {
        let response = try await post(
            "token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": session.refreshToken])
        return try self.session(from: response, now: now, method: session.method, refusedAs: .signedOut)
    }

    /// Ends this iPhone's session at Supabase. Best effort: the app forgets the session either way.
    public func signOut(_ session: DoddyAccountSession) async {
        var request = request("logout", query: [URLQueryItem(name: "scope", value: "local")], body: nil)
        request = HTTPRequest(method: request.method, url: request.url,
                              headers: request.headers.merging(["authorization": session.authorization]) { $1 }, body: nil)
        _ = try? await transport.send(request)
    }

    // MARK: Plumbing

    private func request(_ path: String, query: [URLQueryItem] = [], body: Data?) -> HTTPRequest {
        var components = URLComponents(url: config.projectURL.appendingPathComponent("auth/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return HTTPRequest(
            method: "POST", url: components.url!,
            headers: ["apikey": config.publishableKey, "content-type": "application/json", "accept": "application/json"],
            body: body)
    }

    private func post(_ path: String, query: [URLQueryItem] = [], body: [String: Any]) async throws(DoddyAccountError) -> (status: Int, body: Data) {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { throw .unavailable }
        do {
            return try await transport.send(request(path, query: query, body: data))
        } catch {
            throw .offline
        }
    }

    private struct SessionReply: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double?
        let expires_at: Double?
        let user: User
        struct User: Decodable {
            let id: String
            let email: String?
            let app_metadata: AppMetadata?
            struct AppMetadata: Decodable { let provider: String? }
        }
    }

    private func session(from response: (status: Int, body: Data), now: Date, method: DoddyAccountMethod, refusedAs: DoddyAccountError) throws(DoddyAccountError) -> DoddyAccountSession {
        switch response.status {
        case 200..<300: break
        case 429: throw .rateLimited
        case 400..<500: throw refusedAs
        default: throw .unavailable
        }
        guard let reply = try? JSONDecoder().decode(SessionReply.self, from: response.body),
              !reply.access_token.isEmpty, reply.access_token.count <= 8_192,
              !reply.refresh_token.isEmpty, reply.refresh_token.count <= 2_048,
              UUID(uuidString: reply.user.id) != nil
        else { throw .unavailable }
        let expiresAt: Date
        if let at = reply.expires_at, at > now.timeIntervalSince1970 {
            expiresAt = Date(timeIntervalSince1970: at)
        } else if let seconds = reply.expires_in, seconds > 0 {
            expiresAt = now.addingTimeInterval(seconds)
        } else {
            throw .unavailable
        }
        // The method Supabase recorded wins (a refresh keeps it); one Doddy doesn't offer is refused.
        let recorded = reply.user.app_metadata?.provider.map { DoddyAccountMethod(rawValue: $0) }
        if let recorded, recorded == nil { throw .refused }
        return DoddyAccountSession(
            accessToken: reply.access_token, refreshToken: reply.refresh_token, expiresAt: expiresAt,
            userID: reply.user.id.lowercased(), email: reply.user.email, method: (recorded ?? nil) ?? method)
    }
}

/// Bringing an iPhone's earlier data on Doddy's servers into its account, once, on the first sign-in.
/// Never merged: a server that already has the account's own data says so, and the earlier data
/// stays where it was (decision 2026-11-08-required-account, ADR-600).
public enum DoddyAccountLink {
    public enum Outcome: Equatable, Sendable {
        /// Linked now, or already linked (a repeat).
        case linked
        /// The server refused to merge; the message says why, in plain words.
        case conflict(message: String)
        /// The earlier device sign-in isn't valid any more: there is nothing to bring.
        case nothingToLink
        /// This server has no Doddy accounts set up yet.
        case notSetUp
        /// Offline, busy or broken: try again later. Nothing changed.
        case retryLater
    }

    private struct ServerError: Decodable {
        let error: Detail
        struct Detail: Decodable { let code: String; let message: String? }
    }

    /// Doddy's backend (`POST /v1/account/link-device`): the account takes over the data of the iPhone
    /// whose device token (`ds1.…`) is sent as proof.
    public static func linkBackend(server: URL, account: DoddyAccountSession, deviceToken: String, transport: any HTTPTransport) async -> Outcome {
        guard deviceToken.hasPrefix("ds1."), deviceToken.count <= 2_048,
              let body = try? JSONSerialization.data(withJSONObject: ["deviceToken": deviceToken])
        else { return .nothingToLink }
        let request = HTTPRequest(
            method: "POST", url: server.appendingPathComponent("v1/account/link-device"),
            headers: ["authorization": account.authorization, "content-type": "application/json", "accept": "application/json"],
            body: body)
        guard let response = try? await transport.send(request) else { return .retryLater }
        let error = try? JSONDecoder().decode(ServerError.self, from: response.body)
        switch (response.status, error?.error.code) {
        case (200, _): return .linked
        case (409, "account_conflict"): return .conflict(message: error?.error.message ?? "This iPhone's earlier data belongs to another Doddy account, so it wasn't added.")
        case (401, _): return .nothingToLink
        case (503, "live_not_configured"): return .notSetUp
        default: return .retryLater
        }
    }

    public enum MessagingSignIn: Equatable, Sendable {
        /// This iPhone's own token on the messaging server, for the account.
        case signedIn(accountID: String, deviceToken: String)
        case conflict(reason: String)
        /// The account's access token was refused: refresh it and try once more.
        case accountRefused
        case notSetUp
        case retryLater
    }

    /// Doddy's messaging server (`POST /v1/accounts/sign-in`). `earlierDeviceToken`: this iPhone's
    /// anonymous token there, if it has one, so that account is linked (or, when empty, moved in).
    public static func signInMessaging(server: URL, account: DoddyAccountSession, earlierDeviceToken: String?, transport: any HTTPTransport) async -> MessagingSignIn {
        var fields: [String: Any] = [:]
        if let token = earlierDeviceToken, token.count == 43, token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) {
            fields["deviceToken"] = token
        }
        guard let body = try? JSONSerialization.data(withJSONObject: fields) else { return .retryLater }
        let request = HTTPRequest(
            method: "POST", url: server.appendingPathComponent("v1/accounts/sign-in"),
            headers: ["authorization": account.authorization, "content-type": "application/json", "accept": "application/json"],
            body: body)
        guard let response = try? await transport.send(request) else { return .retryLater }
        struct Reply: Decodable { let accountId: String; let deviceToken: String }
        struct Refusal: Decodable { let error: String; let reason: String? }
        switch response.status {
        case 200:
            guard let reply = try? JSONDecoder().decode(Reply.self, from: response.body),
                  UUID(uuidString: reply.accountId) != nil, reply.deviceToken.count == 43
            else { return .retryLater }
            return .signedIn(accountID: reply.accountId.lowercased(), deviceToken: reply.deviceToken)
        case 409:
            let refusal = try? JSONDecoder().decode(Refusal.self, from: response.body)
            return .conflict(reason: refusal?.reason ?? "account_conflict")
        case 401:
            return .accountRefused
        case 503:
            let refusal = try? JSONDecoder().decode(Refusal.self, from: response.body)
            return refusal?.error == "not_configured" ? .notSetUp : .retryLater
        default:
            return .retryLater
        }
    }
}
