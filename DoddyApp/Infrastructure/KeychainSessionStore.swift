import Foundation
import Security

/// The Doddy server session token lives only in the iOS Keychain (this device only, never in
/// UserDefaults, backups or the app bundle). Provider tokens never reach the app at all.
enum KeychainSessionStore {
    private static let service = "com.bienos.doddy2.connected-apps"
    private static let account = "session-token"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns false if the Keychain refused the write; the caller says so instead of pretending.
    @discardableResult
    static func save(_ token: String) -> Bool {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
