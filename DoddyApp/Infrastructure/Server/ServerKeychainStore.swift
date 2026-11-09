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

/// Messaging-server tokens whose revocation is still owed (security audit 2026-11-09, finding 1): this
/// iPhone signed out, the server hasn't yet said it forgot the token. Kept apart from the token the app
/// uses (`ServerKeychainStore`): nothing reads these but the one request that ends them. Keychain, this
/// device only (not in backups, not synced), readable after the first unlock so a launch can retry.
///
/// `clearLeftoversOnFreshInstall` (below) leaves this slot alone on purpose: a reinstall after an
/// offline sign-out still owes the server its revocation, and the first launch pays it.
struct ServerPendingRevocationStore: PendingRevocationStore {
    private let service = "com.bienos.doddy2.server.pending-revocation"
    private let account = "deviceTokens"

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
    /// reads them: on a fresh install the messaging-server token and the Connected Apps session
    /// token left by an earlier install are removed, as `KeychainCredentialStore` does for the
    /// gateway items, so a reinstall really starts anew (DOD-11).
    ///
    /// The marker lives in UserDefaults, which go with the app. An install updating to this
    /// version already has the gateway's marker and keeps its tokens: dropping the messaging token
    /// would orphan its server account, and any memory copy on it, with no way to delete it.
    static func clearLeftoversOnFreshInstall(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: installMarkerKey) else { return }
        if !defaults.bool(forKey: KeychainCredentialStore.installMarkerKey) {
            // Not marked if the delete failed, so it is tried again next launch.
            guard (try? ServerKeychainStore().delete()) != nil else { return }
            KeychainSessionStore.delete()
        }
        defaults.set(true, forKey: installMarkerKey)
    }
}
