import DoddyCore
import Foundation
import Security

/// Device id, invite code and gateway token in the Keychain. Items are readable after first unlock,
/// never synced to iCloud and never restored to another device. Deleting the app removes them
/// (iOS may keep Keychain items across reinstalls; "Remove" in Settings clears them explicitly).
actor KeychainCredentialStore: DeviceCredentialStore {
    enum KeychainError: Error, Equatable { case status(OSStatus) }

    private enum Account: String { case deviceID, inviteCode, token }
    private let service: String

    init(service: String = "com.bienos.doddy2.gateway") {
        self.service = service
    }

    func deviceID() throws -> UUID {
        if let data = try read(.deviceID), let text = String(data: data, encoding: .utf8), let id = UUID(uuidString: text) {
            return id
        }
        let created = UUID()
        try write(Data(created.uuidString.lowercased().utf8), for: .deviceID)
        return created
    }

    func inviteCode() throws -> String? {
        try read(.inviteCode).flatMap { String(data: $0, encoding: .utf8) }
    }

    func setInviteCode(_ code: String?) throws {
        try write(code.map { Data($0.utf8) }, for: .inviteCode)
    }

    private struct StoredToken: Codable {
        let value: String
        let expiresAtMs: Int64
        let gatewayHost: String?
    }

    /// An unreadable entry counts as "no token": the client simply registers again.
    func token() throws -> DeviceToken? {
        guard let data = try read(.token), let stored = try? JSONDecoder().decode(StoredToken.self, from: data) else { return nil }
        return DeviceToken(
            value: stored.value,
            expiresAt: Date(timeIntervalSince1970: Double(stored.expiresAtMs) / 1000),
            gatewayHost: stored.gatewayHost)
    }

    func setToken(_ token: DeviceToken?) throws {
        let data = try token.map {
            try JSONEncoder().encode(StoredToken(
                value: $0.value, expiresAtMs: Int64($0.expiresAt.timeIntervalSince1970 * 1000), gatewayHost: $0.gatewayHost))
        }
        try write(data, for: .token)
    }

    // MARK: - Keychain

    private func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private func read(_ account: Account) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.status(status)
        }
    }

    /// `nil` deletes the item.
    private func write(_ data: Data?, for account: Account) throws {
        let query = baseQuery(account)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound { throw KeychainError.status(status) }
            return
        }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError.status(update) }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { throw KeychainError.status(status) }
    }
}
