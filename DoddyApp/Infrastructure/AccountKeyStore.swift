import DoddyCore
import Foundation
import Security

/// The keys a person pastes in for their own accounts (ADR-640). Today only the inFakt API key,
/// so invoices can go from this iPhone straight to inFakt without Doddy's server ever holding it.
///
/// The key lives only in the Keychain, readable while the iPhone is unlocked
/// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`): not synced to iCloud Keychain, not moved to
/// another device, and never in UserDefaults, logs, the activity list or any message to a server.
/// Settings shows it masked (`AccountKey.masked`) and never reads it back out to the screen.
/// "Remove key" in Settings and "Delete all" both remove it and confirm it is gone. iOS keeps Keychain
/// items after the app is deleted, so a fresh install clears this service first, as
/// `KeychainCredentialStore` does for its own.
///
/// Nothing here makes a network call. A Keychain error is reported as `.unavailable`, never as "no key".
/// Not run on a device in this build: BLOCKED / NOT RUN (see docs/implementation/INFAKT_STATUS.md).
enum AccountKeyStore {
    enum Account: String, CaseIterable, Sendable {
        case inFakt = "infakt.api-key"
    }

    enum StoreError: Error, Equatable { case status(OSStatus) }

    static let service = "com.bienos.doddy2.account-keys"
    /// UserDefaults go with the app when it is deleted; Keychain items do not.
    static let installMarkerKey = "accountKeysInstalled"

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.rawValue]
    }

    /// Clears keys a previous install left behind. Marks the install only once they are really gone,
    /// so a failure is tried again at the next launch. Call once at launch, before any `state`.
    static func clearLeftoversOnFreshInstall(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: installMarkerKey) else { return }
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { defaults.set(true, forKey: installMarkerKey) }
    }

    /// What a screen gets: what is saved (masked), save and remove, each confirmed by asking the
    /// Keychain again (`AccountKeyManager`), and no way to read the key back out.
    static func manager(for account: Account) -> AccountKeyManager {
        AccountKeyManager(store: KeychainAccountKey(account: account))
    }

    /// The key, for the one place that puts it in a request header (the inFakt client, once one
    /// exists; scripts/check_forbidden_capabilities.sh allows no other caller). A value that no longer
    /// passes `AccountKey` (damaged, or from an older build) counts as no key rather than being sent.
    static func read(_ account: Account) throws -> AccountKey? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
            return AccountKey(text)
        case errSecItemNotFound:
            return nil
        default:
            throw StoreError.status(status)
        }
    }

    /// Saves `key`, replacing any earlier one. Throws when the Keychain refuses, so the screen can say so
    /// instead of showing a key as saved.
    static func save(_ key: AccountKey, for account: Account) throws {
        let query = baseQuery(account)
        let data = Data(key.value.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw StoreError.status(update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { throw StoreError.status(status) }
    }

    /// Removing a key that isn't there is fine.
    static func remove(_ account: Account) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw StoreError.status(status) }
    }

    /// Delete all (DOD-06): every key this store holds. Each is confirmed gone by asking again.
    static func removeAll() -> Bool {
        Account.allCases.allSatisfy { manager(for: $0).remove() == .removed }
    }
}

/// The Keychain behind one account, for `AccountKeyManager`. Private to this file, so a screen can't
/// build one and read the key out; it gets `AccountKeyStore.manager(for:)` instead.
private struct KeychainAccountKey: AccountKeyStoring {
    let account: AccountKeyStore.Account

    func read() throws -> AccountKey? { try AccountKeyStore.read(account) }
    func save(_ key: AccountKey) throws { try AccountKeyStore.save(key, for: account) }
    func remove() throws { try AccountKeyStore.remove(account) }
}
