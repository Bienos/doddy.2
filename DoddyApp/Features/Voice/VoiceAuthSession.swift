import CryptoKit
import DoddyCore
import Foundation
import Observation
import Security

/// A persistent DODDY voice session. Apple sign-in is exchanged once for a rotating,
/// revocable DODDY refresh token; provider credentials are never stored here. Apple's side of
/// the sign-in is in AppleSignIn.swift, the calls to DODDY's server in VoiceTokenClient.swift (ADR-483).
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
    private var lastFailure: VoiceAuthFailure?
    private var revocationObserver: NSObjectProtocol?

    private init() {
        revocationObserver = AppleSignIn.observeRevocation { [weak self] in
            await self?.appleAccessWasRevoked()
        }
    }

    func restore() async {
        if isSignedIn, accessTokenExpiresAt.timeIntervalSinceNow > 30 { return }
        guard !isLoading, let refreshToken = VoiceSessionKeychain.refreshToken(), let userID = VoiceSessionKeychain.userID() else {
            if !hasSavedSession { lastFailure = .sessionExpired }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            guard try await AppleSignIn.isStillAuthorized(userID: userID) else {
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

    func finishAppleSignIn(identityToken: String, rawNonce: String, userID: String, provider: VoiceProvider) async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let reply = try await VoiceAuthAPI.shared.signIn(identityToken, rawNonce: rawNonce, provider: provider.rawValue)
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
        do {
            let token = try await bearerToken()
            try await VoiceAuthAPI.shared.deleteAccount(token)
            clearLocalSession()
            message = nil
        } catch {
            message = (error as? VoiceAuthFailure)?.message ?? "Couldn’t delete the DODDY voice account. Check your connection and retry."
        }
    }

    func serverRejectedSession() {
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

    private func clearLocalSession() {
        VoiceSessionKeychain.delete()
        userID = nil
        accessToken = nil
        accessTokenExpiresAt = .distantPast
        isSignedIn = false
    }
}

enum VoiceAuthFailure: Error, Equatable {
    case offline, sessionExpired, serverNotConfigured, rejected, badResponse

    var message: String {
        switch self {
        case .offline: "Couldn’t reach DODDY. Check your connection and retry."
        case .sessionExpired: "Your voice session expired. Sign in with Apple again."
        case .serverNotConfigured: "Voice isn’t set up yet. Try again later; you don’t need a code or provider key."
        case .rejected: "Apple sign-in couldn’t be verified. Try again."
        case .badResponse: "DODDY’s voice service sent an unexpected reply. Try again."
        }
    }
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

enum VoiceProviderConsent {
    static func key(for provider: VoiceProvider) -> String { "voice.providerConsent.\(provider.rawValue).v1" }
    static func isGranted(for provider: VoiceProvider) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: provider))
    }
    static func grant(for provider: VoiceProvider) {
        UserDefaults.standard.set(true, forKey: key(for: provider))
    }
    static func reset() {
        for provider in VoiceProvider.allCases { UserDefaults.standard.removeObject(forKey: key(for: provider)) }
    }
}
