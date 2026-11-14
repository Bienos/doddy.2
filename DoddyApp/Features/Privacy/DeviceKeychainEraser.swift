import DoddyCore
import Foundation
import Security

/// The Keychain side of "Erase everything on this iPhone" (`EraseThisIPhone`). The rules are `DeviceKeychain` in DoddyCore,
/// tested on Linux: which services are Doddy's, which are erased in which scope, and that one the table doesn't know is
/// erased. This file only asks the Keychain what it holds for Doddy and deletes by service name; every item Doddy keeps is a
/// generic password with a service name `com.bienos.doddy2.<name>` (`DeviceStoreInventoryTests` checks the sources for it).
///
/// Not compiled on Linux: the hosted `ios-build` job is its first compile. Not run on a device.
enum DeviceKeychainEraser {
    struct Failure: Error {
        let status: OSStatus
    }

    /// The service names the Keychain holds items under for this app now.
    static func services() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Failure(status: status) }
        let items = result as? [[String: Any]] ?? []
        return Array(Set(items.compactMap { $0[kSecAttrService as String] as? String })).sorted()
    }

    /// The services of `store` that should be gone in `scope` and are still in the Keychain.
    static func present(_ store: DeviceStoreID, scope: DeviceErasureScope) throws -> [String] {
        try services().filter { DeviceKeychain.store(for: $0) == store && DeviceKeychain.shouldErase(service: $0, scope: scope) }
    }

    /// Deletes every item under each of those services. An item that is already gone is fine.
    static func erase(_ store: DeviceStoreID, scope: DeviceErasureScope) throws {
        for service in try present(store, scope: scope) {
            let status = SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
        }
    }

    /// The read-back: asks the Keychain again, true only when none of them is left.
    static func isEmpty(_ store: DeviceStoreID, scope: DeviceErasureScope) throws -> Bool {
        try present(store, scope: scope).isEmpty
    }
}
