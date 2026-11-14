import DoddyCore
import Foundation
import Security

/// Keeps the Doddy messaging server token in the Keychain, on this device only (not in backups, not
/// synced). Restoring to a new iPhone, or installing Doddy again, starts a fresh anonymous account.
struct ServerKeychainStore: ServerCredentialStore {
    private let service = "com.bienos.doddy2.server"
    private let account = "deviceToken"

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw ServerKeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ServerKeychainError(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ServerKeychainError(status: status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

struct ServerKeychainError: Error {
    let status: OSStatus
}

/// Keeps the voice server's own session for the signed-in Doddy account (decision 2026-11-12-one-token-per-server):
/// its access and refresh tokens and which account they belong to, in one Keychain item. This device only (not in
/// backups, not synced), readable after the first unlock so a launch can renew it. It is apart from the older Apple voice
/// session (`VoiceSessionKeychain`): each has its own item, and signing out of the Doddy account removes only this one.
/// The rules (what is kept, renewed, refused and owed) are `VoiceAccountSessions` in DoddyCore, tested on Linux; this
/// only reads, writes and deletes the item. Erased with the account (`DeviceKeychain`). A fresh install removes it
/// (`clearLeftoversOnFreshInstall`, below).
struct VoiceAccountSessionKeychain: VoiceSessionPairStore {
    private let service = "com.bienos.doddy2.voice-account-session"
    private let account = "default"

    func load() -> VoiceSessionPair? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(VoiceSessionPair.self, from: data)
    }

    func save(_ pair: VoiceSessionPair) -> Bool {
        guard let data = try? JSONEncoder().encode(pair) else { return false }
        // Updated in place: a failed write never leaves the item half-written.
        let updated = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

/// Messaging-server tokens whose revocation is still owed (security audit 2026-11-09, finding 1): this
/// iPhone signed out, the server hasn't yet said it forgot the token. Kept apart from the token the app
/// uses (`ServerKeychainStore`): nothing reads these but the one request that ends them. Keychain, this
/// device only (not in backups, not synced), readable after the first unlock so a launch can retry.
///
/// `clearLeftoversOnFreshInstall` (below) leaves this slot alone on purpose: a reinstall after an
/// offline sign-out still owes the server its revocation, and the first launch pays it.
struct ServerPendingRevocationStore: PendingRevocationStore {
    private let service: String
    private let account: String

    /// The messaging server's slot by default. `voiceSessions` is the same kind of list for the voice server.
    init(service: String = "com.bienos.doddy2.server.pending-revocation", account: String = "deviceTokens") {
        self.service = service
        self.account = account
    }

    /// Voice-server sessions this iPhone signed out of, whose sign-out the voice server hasn't yet confirmed (decision
    /// 2026-11-12-one-token-per-server, `VoiceAccountSessions`): refresh tokens, owed until the server answers. A slot
    /// of its own, used for nothing but that one request. Like the messaging slot, `clearLeftoversOnFreshInstall` leaves it
    /// alone, so a reinstall after an offline sign-out still pays it at the first launch.
    static let voiceSessions = ServerPendingRevocationStore(service: "com.bienos.doddy2.voice-account-session-owed", account: "refreshTokens")

    func load() -> [String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let tokens = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return tokens
    }

    func save(_ tokens: [String]) -> Bool {
        if tokens.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        // Updated in place: a failed write must never lose what was already owed.
        let updated = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

extension ServerKeychainStore {
    static let installMarkerKey = "serverKeychainInstalled"

    /// iOS keeps Keychain items after the app is deleted. Called once at launch, before anything
    /// reads them: on a fresh install the messaging-server token, the Connected Apps session
    /// token, the Doddy account's session and the voice account's session left by an earlier
    /// install are removed, as `KeychainCredentialStore` does for the gateway items, so a reinstall
    /// really starts anew (DOD-11): the welcome asks to sign in again instead of saying "Continue"
    /// with the old account (owner, 12 Nov 2026; decision 2026-11-12-deleted-files-stay-gone).
    /// The device id (`DeviceSession`) stays: it is what the server knows this iPhone by.
    ///
    /// The marker lives in UserDefaults, which go with the app. An install updating to this
    /// version already has the gateway's marker and keeps its tokens: dropping the messaging token
    /// would orphan its server account, and any memory copy on it, with no way to delete it, and
    /// an update must not sign anyone out.
    static func clearLeftoversOnFreshInstall(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: installMarkerKey) else { return }
        if !defaults.bool(forKey: KeychainCredentialStore.installMarkerKey) {
            // Not marked if the delete failed, so it is tried again next launch.
            guard (try? ServerKeychainStore().delete()) != nil else { return }
            KeychainSessionStore.delete()
            DoddyAccountKeychain().delete()
            VoiceSessionKeychain.delete()
            // The voice server's session for the Doddy account (decision 2026-11-12-one-token-per-server).
            VoiceAccountSessionKeychain().delete()
        }
        defaults.set(true, forKey: installMarkerKey)
    }
}
