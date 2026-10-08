import DoddyAssistant
import Foundation
import Security

/// Stores the anonymous gateway token in the Keychain (bearer credential: never UserDefaults).
/// Available after first unlock, not migrated to other devices or backups.
struct KeychainDeviceTokenStore: DeviceTokenStore {
    private let service = "com.bienos.doddy2.gateway"
    private let account = "deviceToken"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func token() async -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) async throws {
        await clear()
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func clear() async {
        SecItemDelete(baseQuery as CFDictionary)
    }

    enum KeychainError: Error { case status(OSStatus) }
}
