import Foundation

// Client for the Doddy server (server/, ADR-036). Platform-agnostic: the app supplies the
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
    /// Sends one request. Throws `ServerError.offline` when no HTTP response arrived.
    func send(_ request: ServerRequest) async throws -> ServerResponse
}

/// Holds the device's bearer token for the anonymous Doddy account.
public protocol DeviceCredentialStore: Sendable {
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

    public init(id: UUID, channel: UpdateChannel, state: String, deliveryStatus: String? = nil, errorCode: String? = nil) {
        self.id = id
        self.channel = channel
        self.state = state
        self.deliveryStatus = deliveryStatus
        self.errorCode = errorCode
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
    private let credentials: any DeviceCredentialStore

    public init(transport: any ServerTransport, credentials: any DeviceCredentialStore) {
        self.transport = transport
        self.credentials = credentials
    }

    public func hasAccount() -> Bool { (try? credentials.load()) != nil }

    /// Creates the anonymous account on first use (no email, no name) and keeps its token.
    @discardableResult
    public func ensureAccount() async throws -> String {
        if let token = try credentials.load() { return token }
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
        let response = try await authorized(.get, "/v1/phone", body: nil)
        guard response.status == 200, let status = try? JSONDecoder().decode(PhoneStatus.self, from: response.body)
        else { throw Self.error(from: response) }
        return status
    }

    /// Records consent to `SMSConsent.text` (with its version), or withdraws it.
    public func setSMSConsent(_ consent: Bool) async throws {
        try await expect(204, .put, "/v1/phone/sms-consent",
                         ConsentBody(consent: consent, textVersion: consent ? SMSConsent.textVersion : nil))
    }

    public func removePhone() async throws {
        try await expect(204, .delete, "/v1/phone")
    }

    public func sendUpdate(_ text: String, channels: [UpdateChannel], idempotencyKey: String) async throws -> [QueuedUpdate] {
        let body = try Self.json(UpdateBody(text: text, channels: channels, idempotencyKey: idempotencyKey))
        let response = try await authorized(.post, "/v1/updates", body: body)
        guard response.status == 202, let queued = try? JSONDecoder().decode(QueuedList.self, from: response.body)
        else { throw Self.error(from: response) }
        return queued.messages
    }

    public func updateStatus(_ id: UUID) async throws -> UpdateStatus {
        let response = try await authorized(.get, "/v1/updates/\(id.uuidString.lowercased())", body: nil)
        guard response.status == 200, let status = try? JSONDecoder().decode(UpdateStatus.self, from: response.body)
        else { throw Self.error(from: response) }
        return status
    }

    /// Erases the account and everything the server holds for it, then forgets the token.
    /// Memories are not affected: they were never on the server.
    public func deleteAccount() async throws {
        guard let token = try credentials.load() else { return }
        let response = try await send(.delete, "/v1/account", body: nil, token: token)
        guard response.status == 204 || response.status == 401 else { throw Self.error(from: response) }
        try credentials.delete()
    }

    public func voiceConversationToken() async throws -> String {
        let response = try await authorized(.get, "/v1/voice/token", body: nil)
        guard response.status == 200, let token = try? JSONDecoder().decode(VoiceToken.self, from: response.body)
        else { throw Self.error(from: response) }
        return token.token
    }

    // MARK: Plumbing

    private func expect(_ status: Int, _ method: HTTPMethod, _ path: String) async throws {
        let response = try await authorized(method, path, body: nil)
        guard response.status == status else { throw Self.error(from: response) }
    }

    private func expect(_ status: Int, _ method: HTTPMethod, _ path: String, _ body: some Encodable) async throws {
        let response = try await authorized(method, path, body: try Self.json(body))
        guard response.status == status else { throw Self.error(from: response) }
    }

    private func authorized(_ method: HTTPMethod, _ path: String, body: Data?) async throws -> ServerResponse {
        let token = try await ensureAccount()
        let response = try await send(method, path, body: body, token: token)
        if response.status == 401 {
            // The account was deleted or the token revoked; a new one is created on next use.
            try? credentials.delete()
            throw ServerError.accountMissing
        }
        return response
    }

    private func send(_ method: HTTPMethod, _ path: String, body: Data?, token: String?) async throws -> ServerResponse {
        do {
            return try await transport.send(ServerRequest(method: method, path: path, body: body, bearerToken: token))
        } catch let error as ServerError {
            throw error
        } catch {
            throw ServerError.offline
        }
    }

    static func error(from response: ServerResponse) -> ServerError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: response.body)
        let code = body?.error ?? ""
        switch (response.status, code) {
        case (400, "wrong_code"): return .wrongCode
        case (400, "code_expired"): return .codeExpired
        case (400, "phone_rejected"): return .phoneRejected
        case (400, _): return .invalidRequest(fields: body?.fields ?? [])
        case (401, _): return .accountMissing
        case (404, "no_verified_phone"), (409, _): return .notEnabled(code)
        case (429, _): return .rateLimited
        case (502, _): return .providerUnavailable
        case (503, _): return .notConfigured(code)
        default: return .unexpected(status: response.status)
        }
    }

    private static func json(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

private struct CreatedAccount: Decodable { let deviceToken: String }
private struct PushTokenBody: Encodable { let token: String; let environment: PushEnvironment }
private struct PhoneBody: Encodable { let phone: String }
private struct CodeBody: Encodable { let phone: String; let code: String }
private struct ConsentBody: Encodable { let consent: Bool; let textVersion: String? }
private struct UpdateBody: Encodable { let text: String; let channels: [UpdateChannel]; let idempotencyKey: String }
private struct QueuedList: Decodable { let messages: [QueuedUpdate] }
private struct VoiceToken: Decodable { let token: String }
private struct ErrorBody: Decodable { let error: String?; let fields: [String]? }

/// How a voice conversation authenticates with ElevenLabs (ADR-034, ADR-048).
public enum VoiceAuthChoice: Equatable, Sendable {
    /// Fetch a short-lived conversation token from the Doddy server. The API key stays there.
    case serverToken
    /// Development only: connect to a public agent by ID. Anyone with the ID can use it.
    case publicAgent(id: String)
    case unavailable(String)
}

public enum VoiceAuthPolicy {
    /// A connected server always wins; the public agent is allowed only where the caller says
    /// so (debug builds), and never silently replaces a failing server.
    public static func choose(serverConfigured: Bool, publicAgentID: String, allowPublicAgent: Bool) -> VoiceAuthChoice {
        if serverConfigured { return .serverToken }
        guard allowPublicAgent else {
            return .unavailable("Voice needs the Doddy server, which isn't connected in this build.")
        }
        let id = publicAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return .unavailable("Voice isn't set up. Add an ElevenLabs agent ID in Settings → Voice.")
        }
        return .publicAgent(id: id)
    }
}
