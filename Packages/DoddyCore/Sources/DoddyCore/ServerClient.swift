import Foundation

// Client for the Doddy messaging server (server/messaging/, ADR-139). Platform-agnostic: the app supplies the
// HTTP transport and the credential store (Keychain), so this file has no
// networking or Keychain code of its own and runs in Linux tests.

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
}

public struct ServerRequest: Equatable, Sendable {
    public let method: HTTPMethod
    /// Absolute path on the server, e.g. `/v1/phone`.
    public let path: String
    public let body: Data?
    public let bearerToken: String?
    /// How long the transport should wait for an answer. Starting a call or building the news
    /// waits on the server's own provider calls, so those get longer than the default: giving up
    /// sooner would report a failure while the call or the news is already on its way.
    public let timeout: TimeInterval

    public static let defaultTimeout: TimeInterval = 15

    init(method: HTTPMethod, path: String, body: Data?, bearerToken: String?, timeout: TimeInterval = defaultTimeout) {
        self.method = method
        self.path = path
        self.body = body
        self.bearerToken = bearerToken
        self.timeout = timeout
    }
}

public struct ServerResponse: Equatable, Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

public protocol ServerTransport: Sendable {
    /// Sends one request. When no HTTP response arrived, throws the underlying error (e.g. the
    /// `URLError`) so the client can tell "never left the phone" from "may have reached the
    /// server" (`ServerTransportFailure`). A transport that throws `ServerError.offline` instead
    /// is read as "may have reached the server" for requests that start something.
    func send(_ request: ServerRequest) async throws -> ServerResponse
}

/// What a transport error says about whether the request reached the server (DOD-08).
public enum ServerTransportFailure {
    /// True only for errors raised before the request could have reached the server: no network,
    /// no such host, connection refused, or a failed TLS handshake. A timeout or a dropped
    /// connection may come after the server got the request, so they are not on this list.
    public static func certainlyNotSent(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .callIsActive, .dataNotAllowed, .badURL, .unsupportedURL,
             .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed,
             .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return true
        default:
            return false
        }
    }
}

/// Holds the device's bearer token for the anonymous Doddy account.
public protocol ServerCredentialStore: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

public enum ServerError: Error, Equatable, Sendable {
    /// The server has no credentials for this provider yet (HTTP 503).
    case notConfigured(String)
    /// The channel isn't switched on for this account (HTTP 409/404), e.g. `sms_not_enabled`.
    case notEnabled(String)
    case wrongCode
    case codeExpired
    case phoneRejected
    /// The PIN was too easy to guess (all one digit or a straight run like 1234).
    case weakPIN
    /// A feed address that points at a private network, a non-web scheme or similar.
    case unsafeURL
    /// The address answered, but not with an RSS or Atom feed.
    case notAFeed
    case invalidRequest(fields: [String])
    case rateLimited
    case providerUnavailable
    /// The server no longer knows this device; the stored token was removed.
    case accountMissing
    case offline
    case unexpected(status: Int)
}

public enum PushEnvironment: String, Sendable, Encodable {
    case sandbox, production
}

public enum UpdateChannel: String, Sendable, Codable, CaseIterable {
    case push, sms
}

public struct PhoneStatus: Equatable, Sendable, Decodable {
    public let phone: String?
    public let smsEnabled: Bool
    /// The user replied STOP; only texting START re-opens SMS (carrier rule).
    public let optedOut: Bool

    public static let none = PhoneStatus(phone: nil, smsEnabled: false, optedOut: false)

    public init(phone: String?, smsEnabled: Bool, optedOut: Bool) {
        self.phone = phone
        self.smsEnabled = smsEnabled
        self.optedOut = optedOut
    }
}

public struct QueuedUpdate: Equatable, Sendable, Decodable {
    public let id: UUID
    public let channel: UpdateChannel
    public let state: String
}

public struct UpdateStatus: Equatable, Sendable, Decodable {
    public let id: UUID
    public let channel: UpdateChannel
    public let state: String
    public let deliveryStatus: String?
    public let errorCode: String?
    /// For a text whose outcome was unknown: what Twilio's own records showed (ADR-490 U2).
    /// "found" (the row is then sent), "not_found", "failed" (couldn't check), or nil.
    public let lookup: String?

    public init(
        id: UUID, channel: UpdateChannel, state: String, deliveryStatus: String? = nil, errorCode: String? = nil,
        lookup: String? = nil
    ) {
        self.id = id
        self.channel = channel
        self.state = state
        self.deliveryStatus = deliveryStatus
        self.errorCode = errorCode
        self.lookup = lookup
    }

    /// Still moving through the server's outbox.
    public var isPending: Bool { state == "queued" || state == "sending" }

    /// Says only what is known: "sent" means a provider accepted it, not that it was read.
    public var userFacingText: String {
        switch state {
        case "queued": return "Waiting to send"
        case "sending": return "Sending…"
        case "sent" where channel == .sms && deliveryStatus == "delivered": return "Delivered"
        case "sent" where channel == .sms && (deliveryStatus == "undelivered" || deliveryStatus == "failed"):
            return "Twilio accepted it, but the carrier didn't deliver it"
        case "sent" where channel == .sms: return "Handed to Twilio for delivery"
        case "sent": return "Handed to Apple. Check your notifications"
        case "failed": return "Not sent" + (errorCode.map { " (\($0))" } ?? "")
        case "unknown" where channel == .sms && lookup == "not_found":
            return "Twilio has no record of it, so it most likely wasn't sent. Doddy won't resend it automatically"
        case "unknown" where channel == .sms && lookup == "failed":
            return "Unclear whether it was sent, and Doddy couldn't check with Twilio. It won't resend it automatically"
        case "unknown" where channel == .sms:
            return "Unclear whether it was sent. Doddy is checking Twilio's records and won't resend it"
        case "unknown": return "Unclear whether it was sent. Doddy won't resend it automatically"
        case "cancelled": return "Cancelled"
        default: return "Status: \(state)"
        }
    }
}

/// The exact SMS opt-in wording. The server stores `textVersion` with the consent, so any
/// change to `text` must come with a new version.
public enum SMSConsent {
    public static let textVersion = "sms-v1"
    public static let text = "Doddy may text this number with the updates you turn on. Message frequency varies. Message and data rates may apply. Reply STOP to stop or HELP for help."
}

public enum PhoneNumberInput {
    /// Turns typed input into E.164 (`+48500100200`). Numbers without `+` or `00` get the
    /// default calling code. Returns nil when the result can't be a valid E.164 number.
    public static func normalize(_ raw: String, defaultCallingCode: String = "48") -> String? {
        var digits = raw.filter { !" -().\u{00A0}".contains($0) }
        if digits.hasPrefix("00") { digits = "+" + digits.dropFirst(2) }
        if !digits.hasPrefix("+") { digits = "+" + defaultCallingCode + digits }
        let body = digits.dropFirst()
        guard (7...15).contains(body.count), body.allSatisfy(\.isASCIIDigit), body.first != "0" else { return nil }
        return digits
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

public actor DoddyServerClient {
    private let transport: any ServerTransport
    private let credentials: any ServerCredentialStore
    /// Idempotency keys of updates not yet accepted by the server, by text and channels.
    private var pendingUpdateKeys: [UpdateBody: String] = [:]
    /// The same for approved texts, by approval hash (ADR-490 U2).
    private var pendingTextKeys: [String: String] = [:]
    /// The same for calls booked for later, by approval hash (ADR-495, `scheduleCall`).
    var pendingCallKeys: [String: String] = [:]
    /// The account being created right now, if any (see `ensureAccount`).
    private var accountCreation: Task<String, any Error>?

    public init(transport: any ServerTransport, credentials: any ServerCredentialStore) {
        self.transport = transport
        self.credentials = credentials
    }

    public func hasAccount() -> Bool { (try? credentials.load()) != nil }

    /// Creates the anonymous account on first use (no email, no name) and keeps its token.
    /// Callers that arrive while it is being created wait for that one account: the actor is
    /// reentrant across the request, and a second POST would leave an orphaned account.
    @discardableResult
    public func ensureAccount() async throws -> String {
        if let token = try credentials.load() { return token }
        if let accountCreation { return try await accountCreation.value }
        let creation = Task { try await self.createAccount() }
        accountCreation = creation
        defer { accountCreation = nil }
        return try await creation.value
    }

    private func createAccount() async throws -> String {
        let response = try await send(.post, "/v1/accounts", body: nil, token: nil)
        guard response.status == 201,
              let created = try? JSONDecoder().decode(CreatedAccount.self, from: response.body)
        else { throw Self.error(from: response) }
        try credentials.save(created.deviceToken)
        return created.deviceToken
    }

    public func registerPushToken(_ token: Data, environment: PushEnvironment) async throws {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        try await expect(204, .put, "/v1/device/push-token", PushTokenBody(token: hex, environment: environment))
    }

    public func removePushToken() async throws {
        try await expect(204, .delete, "/v1/device/push-token")
    }

    public func startPhoneVerification(_ e164: String) async throws {
        try await expect(202, .post, "/v1/phone/verification", PhoneBody(phone: e164))
    }

    public func confirmPhone(_ e164: String, code: String) async throws {
        try await expect(200, .post, "/v1/phone/verification/check", CodeBody(phone: e164, code: code))
    }

    public func phoneStatus() async throws -> PhoneStatus {
        try await getJSON("/v1/phone")
    }

    /// Records consent to `SMSConsent.text` (with its version), or withdraws it.
    public func setSMSConsent(_ consent: Bool) async throws {
        try await expect(204, .put, "/v1/phone/sms-consent",
                         ConsentBody(consent: consent, textVersion: consent ? SMSConsent.textVersion : nil))
    }

    public func removePhone() async throws {
        try await expect(204, .delete, "/v1/phone")
    }

    /// Sends with one idempotency key per intent: sending the same text to the same channels
    /// again after a failure reuses the key, so if the first try did reach the server it still
    /// goes out once (DOD-08). The key is dropped once the server has accepted the update, so a
    /// later send of the same text is a new update.
    public func sendUpdate(_ text: String, channels: [UpdateChannel]) async throws -> [QueuedUpdate] {
        let intent = UpdateBody(text: text, channels: channels, idempotencyKey: "")
        let key = pendingUpdateKeys[intent] ?? UUID().uuidString
        pendingUpdateKeys[intent] = key
        let queued = try await sendUpdate(text, channels: channels, idempotencyKey: key)
        pendingUpdateKeys[intent] = nil
        return queued
    }

    public func sendUpdate(_ text: String, channels: [UpdateChannel], idempotencyKey: String) async throws -> [QueuedUpdate] {
        let body = try Self.json(UpdateBody(text: text, channels: channels, idempotencyKey: idempotencyKey))
        let response = try await authorized(.post, "/v1/updates", body: body)
        guard response.status == 202, let queued = try? JSONDecoder().decode(QueuedList.self, from: response.body)
        else { throw Self.error(from: response) }
        return queued.messages
    }

    /// A text the user approved on a card, from Doddy's number to their own verified number
    /// (ADR-490 U2). `approvalHash` is `ApprovalHash.text` of the number and text the card showed;
    /// the server recomputes it with the number it holds and refuses on any difference.
    ///
    /// One idempotency key per approval: trying the same approved text again after an unknown
    /// outcome reuses the key, so the server sends it at most once (DOD-09). The key is dropped
    /// only once the server has queued the text, so the same words approved again later are a
    /// new text. A refusal keeps it: the server refuses some requests (its hourly limit, texts
    /// switched off) before it looks for a repeat of the key, so a refusal says nothing about
    /// an earlier try that went unanswered.
    /// Throws `ServerError` when it certainly wasn't sent (offline, account gone, unexpected).
    public func sendApprovedText(_ body: String, approvalHash: String) async throws -> ApprovedTextOutcome {
        let key = pendingTextKeys[approvalHash] ?? UUID().uuidString
        pendingTextKeys[approvalHash] = key
        let request = try Self.json(TextBody(body: body, approvalHash: approvalHash, idempotencyKey: key))
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/texts", body: request, startsSomething: true)
        } catch is OutcomeUnknown {
            return .unknown
        }
        if response.status == 202, let queued = try? JSONDecoder().decode(QueuedList.self, from: response.body),
           let text = queued.messages.first {
            pendingTextKeys[approvalHash] = nil
            return .queued(text)
        }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: response.body))?.error
        switch (response.status, code) {
        // Each of these is answered before anything is queued.
        case (400, _): return .refused("invalid")
        case (409, _): return .refused(code ?? "status_409")
        case (503, "sms_not_configured"): return .refused("sms_not_configured")
        // The route's hourly limit answers without a code; the daily limits name themselves.
        case (429, _): return .refused(code ?? "rate_limited")
        // Any other server error, the hosting proxy's 502 or 504 included, may come after the
        // server queued the text: unknown, never "not sent" (DOD-08). The key is kept, so a
        // try-again of the same approval is answered with the text already queued.
        case (500..., _):
            return .unknown
        default: throw Self.error(from: response)
        }
    }

    public func updateStatus(_ id: UUID, timeout: TimeInterval = ServerRequest.defaultTimeout) async throws -> UpdateStatus {
        try await getJSON("/v1/updates/\(id.uuidString.lowercased())", timeout: timeout)
    }

    /// Erases the account and everything the server holds for it, then forgets the token.
    /// Memories are not affected: they were never on the server.
    public func deleteAccount() async throws {
        guard let token = try credentials.load() else { return }
        let response = try await send(.delete, "/v1/account", body: nil, token: token)
        guard response.status == 204 || response.status == 401 else { throw Self.error(from: response) }
        try credentials.delete()
    }

    // MARK: Plumbing

    /// GETs `path` and decodes a 200 reply; anything else, an unreadable body included, is an error.
    func getJSON<T: Decodable>(_ path: String, timeout: TimeInterval = ServerRequest.defaultTimeout) async throws -> T {
        let response = try await authorized(.get, path, body: nil, timeout: timeout)
        guard response.status == 200, let value = try? JSONDecoder().decode(T.self, from: response.body)
        else { throw Self.error(from: response) }
        return value
    }

    func expect(_ status: Int, _ method: HTTPMethod, _ path: String) async throws {
        let response = try await authorized(method, path, body: nil)
        guard response.status == status else { throw Self.error(from: response) }
    }

    func expect(_ status: Int, _ method: HTTPMethod, _ path: String, _ body: some Encodable) async throws {
        let response = try await authorized(method, path, body: try Self.json(body))
        guard response.status == status else { throw Self.error(from: response) }
    }

    /// `startsSomething`: the request starts something the user would notice twice (a call, a
    /// news message). If it may have reached the server but no answer came back, `OutcomeUnknown`
    /// is thrown instead of `ServerError.offline`, so the caller says "unknown" rather than
    /// "offline, try again" (DOD-08).
    func authorized(
        _ method: HTTPMethod, _ path: String, body: Data?,
        startsSomething: Bool = false, timeout: TimeInterval = ServerRequest.defaultTimeout
    ) async throws -> ServerResponse {
        let token = try await ensureAccount()
        let response = try await send(method, path, body: body, token: token, startsSomething: startsSomething, timeout: timeout)
        if response.status == 401 {
            // The account was deleted or the token revoked; a new one is created on next use.
            try? credentials.delete()
            throw ServerError.accountMissing
        }
        return response
    }

    private func send(
        _ method: HTTPMethod, _ path: String, body: Data?, token: String?,
        startsSomething: Bool = false, timeout: TimeInterval = ServerRequest.defaultTimeout
    ) async throws -> ServerResponse {
        do {
            return try await transport.send(
                ServerRequest(method: method, path: path, body: body, bearerToken: token, timeout: timeout))
        } catch let error as ServerError where !(startsSomething && error == .offline) {
            throw error
        } catch {
            if startsSomething && !ServerTransportFailure.certainlyNotSent(error) { throw OutcomeUnknown() }
            throw ServerError.offline
        }
    }

    /// The request may have reached the server, but no answer came back. Internal: each request
    /// that starts something turns it into its own "unknown" result.
    struct OutcomeUnknown: Error {}

    static func error(from response: ServerResponse) -> ServerError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: response.body)
        let code = body?.error ?? ""
        switch (response.status, code) {
        case (400, "wrong_code"): return .wrongCode
        case (400, "code_expired"): return .codeExpired
        case (400, "phone_rejected"): return .phoneRejected
        case (400, "weak_pin"): return .weakPIN
        case (400, "unsafe_url"): return .unsafeURL
        // Live: PUT /v1/news/settings answers it when news is switched on with nothing picked.
        case (400, "no_topics"): return .notEnabled("no_topics")
        case (422, "not_a_feed"): return .notAFeed
        // The key was used before for a different update; the server sent nothing new.
        case (409, "idempotency_mismatch"): return .invalidRequest(fields: ["idempotencyKey"])
        case (400, _): return .invalidRequest(fields: body?.fields ?? [])
        case (401, _): return .accountMissing
        case (404, "no_verified_phone"), (409, _): return .notEnabled(code)
        case (429, _): return .rateLimited
        case (502, _): return .providerUnavailable
        case (503, _): return .notConfigured(code)
        default: return .unexpected(status: response.status)
        }
    }

    static func json(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

private struct CreatedAccount: Decodable { let deviceToken: String }
private struct PushTokenBody: Encodable { let token: String; let environment: PushEnvironment }
private struct PhoneBody: Encodable { let phone: String }
private struct CodeBody: Encodable { let phone: String; let code: String }
private struct ConsentBody: Encodable { let consent: Bool; let textVersion: String? }
private struct UpdateBody: Encodable, Hashable { let text: String; let channels: [UpdateChannel]; let idempotencyKey: String }
private struct QueuedList: Decodable { let messages: [QueuedUpdate] }
private struct TextBody: Encodable { let body: String; let approvalHash: String; let idempotencyKey: String }

/// What happened to an approved text (ADR-490 U2).
public enum ApprovedTextOutcome: Equatable, Sendable {
    /// The server queued it, or had queued it on an earlier try of the same approval.
    case queued(QueuedUpdate)
    /// Refused before anything was queued; the server's error code (see `VoiceToolReply.textRefused`).
    case refused(String)
    /// The request may have reached the server but no answer came back (DOD-08).
    case unknown
}
private struct ErrorBody: Decodable { let error: String?; let fields: [String]? }

/// ISO 8601 timestamps as the messaging server writes them (with or without fractional seconds).
public enum ServerDates {
    public static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    public static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
