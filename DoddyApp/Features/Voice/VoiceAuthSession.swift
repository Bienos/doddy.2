import AuthenticationServices
import CryptoKit
import DoddyCore
import Foundation
import Observation
import Security

/// A persistent DODDY voice session. Apple sign-in is exchanged once for a rotating,
/// revocable DODDY refresh token; provider credentials are never stored here.
@MainActor
@Observable
final class VoiceAuthSession {
    static let shared = VoiceAuthSession()

    private(set) var isSignedIn = false
    private(set) var isLoading = false
    private(set) var userID: String?
    var hasSavedSession: Bool { VoiceSessionKeychain.refreshToken() != nil && VoiceSessionKeychain.userID() != nil }
    var message: String?
    private var accessToken: String?
    private var accessTokenExpiresAt = Date.distantPast
    private var refreshTask: Task<VoiceSessionReply, Error>?
    private var restoreTask: Task<Void, Never>?
    private var lastFailure: VoiceAuthFailure?
    private var revocationObserver: NSObjectProtocol?

    private init() {
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.appleAccessWasRevoked() }
        }
    }

    /// Seconds of life left in this older voice session's access token; nil when it isn't signed in.
    /// For `TalkStartAccount`, which decides whether a start restores it.
    var voiceSessionSecondsLeft: TimeInterval? { isSignedIn ? accessTokenExpiresAt.timeIntervalSinceNow : nil }

    func restore() async {
        if isSignedIn, accessTokenExpiresAt.timeIntervalSinceNow > 30 { return }
        // One restore at a time (ADR-672): a second caller waits for the one in flight. Returning at
        // once made `bearerToken()` throw "session expired" while the first restore was still working.
        if let restoreTask {
            await restoreTask.value
            return
        }
        guard !isLoading, let refreshToken = VoiceSessionKeychain.refreshToken(), let userID = VoiceSessionKeychain.userID() else {
            if !hasSavedSession { lastFailure = .sessionExpired }
            return
        }
        // Its own task, so a caller that is cancelled (a sheet closed) doesn't cancel the refresh.
        let task = Task { @MainActor in
            await self.runRestore(refreshToken, userID: userID)
            self.restoreTask = nil
        }
        restoreTask = task
        await task.value
    }

    private func runRestore(_ refreshToken: String, userID: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let appleID = ASAuthorizationAppleIDProvider()
            let state = try await appleCredentialState(appleID, userID: userID)
            guard state == .authorized else {
                clearLocalSession()
                lastFailure = .sessionExpired
                message = "Your Apple access has changed. Sign in with Apple again to use voice."
                return
            }
            let reply = try await refreshSession(refreshToken)
            save(reply, userID: userID)
        } catch {
            if let error = error as? VoiceAuthFailure, error == .sessionExpired {
                clearLocalSession()
                lastFailure = .sessionExpired
                message = error.message
            } else if let error = error as? VoiceAuthFailure, error == .serverNotConfigured {
                lastFailure = .serverNotConfigured
                message = error.message
            } else if let error = error as? VoiceAuthFailure, error == .offline {
                lastFailure = .offline
                message = "You’re offline. Connect to the internet and retry to use voice. Your local notes are still available."
            } else {
                lastFailure = .offline
                message = "Couldn’t restore your voice session. Retry, or sign in again if the session has expired."
            }
        }
    }

    func finishAppleSignIn(identityToken: String, rawNonce: String, authorizationCode: String? = nil,
                           userID: String) async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let reply = try await VoiceAuthAPI.shared.signIn(identityToken, rawNonce: rawNonce,
                                                             authorizationCode: authorizationCode, provider: "elevenlabs")
            save(reply, userID: userID)
        } catch {
            lastFailure = (error as? VoiceAuthFailure) ?? .rejected
            message = (error as? VoiceAuthFailure)?.message ?? "Sign-in didn’t finish. Try again."
        }
    }

    func bearerToken() async throws -> String {
        if let accessToken, accessTokenExpiresAt.timeIntervalSinceNow > 30 { return accessToken }
        await restore()
        if let accessToken, accessTokenExpiresAt.timeIntervalSinceNow > 30 { return accessToken }
        throw lastFailure ?? .sessionExpired
    }

    func signOut() async {
        if let token = try? await bearerToken() { try? await VoiceAuthAPI.shared.signOut(token) }
        clearLocalSession()
        message = nil
    }

    func deleteAccount() async {
        // ADR-674: Doddy's server first (online accounts and what it keeps). If that didn't go through,
        // stop here: this button goes with the voice account, so it must stay to try again.
        let server = await ServerAccountErasure.run()
        let serverLine = ServerAccountErasure.message(for: server)
        guard server.mayDeleteVoiceAccount else {
            message = serverLine
            return
        }
        if let voiceLine = await deleteVoiceAccountOnly() {
            message = [serverLine, voiceLine].compactMap { $0 }.joined(separator: " ")
        } else {
            message = serverLine
        }
    }

    /// The voice account alone, once Doddy's server has already deleted what it keeps: here, and when
    /// the Doddy account is deleted (`DoddyAccountServers.deleteAccount`, decision
    /// 2026-11-08-required-account). Nil when it was deleted; otherwise why it wasn't.
    func deleteVoiceAccountOnly() async -> String? {
        do {
            let token = try await bearerToken()
            try await VoiceAuthAPI.shared.deleteAccount(token)
            clearLocalSession()
            return nil
        } catch {
            return (error as? VoiceAuthFailure)?.message ?? "Couldn’t delete the Doddy voice account. Check your connection and retry."
        }
    }

    /// The voice token server refused the access token (401). That alone doesn't mean the sign-in is
    /// gone: the access token can be revoked or expire early on the server. So the saved refresh token is
    /// tried once first (engineering audit, 7 Nov 2026: before, any 401 deleted it and forced a new
    /// Sign in with Apple). restore() itself clears the session when the server refuses the refresh
    /// token too; offline, the refresh token is kept and restore() says why.
    func serverRejectedSession() async {
        accessToken = nil
        accessTokenExpiresAt = .distantPast
        await restore()
        if accessToken != nil { return }
        guard VoiceSessionKeychain.refreshToken() == nil else { return }
        clearLocalSession()
        lastFailure = .sessionExpired
        message = "Your voice session expired. Sign in with Apple again to reconnect."
    }

    private func appleAccessWasRevoked() async {
        if let accessToken { try? await VoiceAuthAPI.shared.signOut(accessToken) }
        clearLocalSession()
        lastFailure = .sessionExpired
        message = "Your Apple access was revoked. Sign in with Apple again to use voice."
    }

    private func save(_ reply: VoiceSessionReply, userID: String) {
        guard VoiceSessionKeychain.save(refreshToken: reply.refreshToken, userID: userID) else {
            clearLocalSession()
            message = "This iPhone couldn’t securely save your voice session. Try again."
            return
        }
        self.userID = userID
        accessToken = reply.accessToken
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(reply.expiresIn))
        isSignedIn = true
        lastFailure = nil
        message = nil
    }

    private func refreshSession(_ refreshToken: String) async throws -> VoiceSessionReply {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await VoiceAuthAPI.shared.refresh(refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func appleCredentialState(_ provider: ASAuthorizationAppleIDProvider, userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: state) }
            }
        }
    }

    private func clearLocalSession() {
        VoiceSessionKeychain.delete()
        userID = nil
        accessToken = nil
        accessTokenExpiresAt = .distantPast
        isSignedIn = false
        // A token fetched ahead for this login never outlives it (decision 2026-11-10-action-button-start).
        VoiceTokenWarmer.shared.clear()
    }
}

enum VoiceAuthFailure: Error, Equatable {
    case offline, sessionExpired, serverNotConfigured, rejected, badResponse
    /// The server limits sign-ins per caller address (ADR-712). `retryAfterSeconds` is the reply's Retry-After.
    case tooManySignIns(retryAfterSeconds: Int?)

    var message: String {
        switch self {
        case .offline: "Couldn’t reach Doddy. Check your connection and retry."
        case .sessionExpired: "Your voice session expired. Sign in with Apple again."
        case .serverNotConfigured: "Voice isn’t set up yet. Try again later; you don’t need a code or provider key."
        case .rejected: "Apple sign-in couldn’t be verified. Try again."
        case .badResponse: "Doddy’s voice service sent an unexpected reply. Try again."
        case .tooManySignIns(let seconds): VoiceTokenServer.signInThrottledMessage(retryAfterSeconds: seconds)
        }
    }
}

struct VoiceSessionReply: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

/// A single Keychain item stores only the DODDY refresh token and Apple's opaque subject.
/// The short-lived access token stays in memory.
enum VoiceSessionKeychain {
    private static let service = "com.bienos.doddy2.voice-session"
    private static let account = "default"

    static func refreshToken() -> String? { read()?.refreshToken }
    static func userID() -> String? { read()?.userID }

    static func save(refreshToken: String, userID: String) -> Bool {
        delete()
        guard let data = try? JSONEncoder().encode(KeychainValue(refreshToken: refreshToken, userID: userID)) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                    kSecValueData as String: data]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }

    /// Remove the old tester secret and developer-editable endpoint/provider configuration once.
    static func removeLegacySetup() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: "com.bienos.doddy2.voice-access-code",
                       kSecAttrAccount as String: "default"] as CFDictionary)
        UserDefaults.standard.removeObject(forKey: PreferenceKey.voiceTokenServer)
        UserDefaults.standard.removeObject(forKey: PreferenceKey.voiceAgentID)
    }

    private static func read() -> KeychainValue? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(KeychainValue.self, from: data)
    }

    private struct KeychainValue: Codable { let refreshToken: String; let userID: String }
}

enum AppleSignInNonce {
    static func make() -> (raw: String, hashed: String)? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let raw = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return (raw, digest.map { String(format: "%02x", $0) }.joined())
    }
}

/// The person's yes to sending voice data to ElevenLabs. ElevenLabs is the only voice (9 Nov 2026), so
/// there is one consent. Its key is the one that was kept for ElevenLabs before, so a yes already given
/// still counts. The old OpenAI consent has no use any more; `reset` removes it too.
enum VoiceProviderConsent {
    static let key = "voice.providerConsent.elevenlabs.v1"
    private static let retiredOpenAIKey = "voice.providerConsent.openai.v1"
    static func isGranted() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
    static func grant() {
        UserDefaults.standard.set(true, forKey: key)
    }
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: retiredOpenAIKey)
        // Consent withdrawn: a token fetched ahead goes too (decision 2026-11-10-action-button-start).
        Task { @MainActor in VoiceTokenWarmer.shared.clear() }
    }
}
