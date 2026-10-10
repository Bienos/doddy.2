import DoddyCore
import Foundation
import Security

/// Keeps the Doddy messaging server token in the Keychain, on this device only (not in backups, not
/// synced). Restoring to a new iPhone starts a fresh anonymous account.
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
