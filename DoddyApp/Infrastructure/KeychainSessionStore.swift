import DoddyCore
import Foundation
import Security

/// The Doddy server session token lives only in the iOS Keychain (this device only, never in
/// UserDefaults, backups or the app bundle). Provider tokens never reach the app at all.
/// It is stored with the server that issued it (`BoundSessionToken`), and the clients send it
/// only to that server, so changing the address in Settings can't hand it to another host (DOD-11).
enum KeychainSessionStore {
    private static let service = "com.bienos.doddy2.connected-apps"
    private static let account = "session-token"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The saved token with the server it belongs to, or nil.
    ///
    /// Tokens saved before tokens were bound are plain text. Such a token is bound to the server
    /// address set in Settings now, which is the one it has been sent to so far, and saved again
    /// in the new form. Without a usable address it isn't used until one is set; the old form
    /// had no record of its server, so there is nothing better to bind it to.
    static func read() -> BoundSessionToken? {
        guard let data = readData() else { return nil }
        if let bound = try? JSONDecoder().decode(BoundSessionToken.self, from: data) { return bound }
        guard let legacy = String(data: data, encoding: .utf8),
              let server = configuredServer(),
              let bound = BoundSessionToken(token: legacy, issuedBy: server)
        else { return nil }
        write(bound)
        return bound
    }

    /// True when any token is saved, bound or not, so Settings can offer to remove it.
    static var hasToken: Bool { readData() != nil }

    /// Saves `token` for `server` only. Returns false if the token or address can't be used or
    /// the Keychain refused the write; the caller says so instead of pretending.
    @discardableResult
    static func save(_ token: String, issuedBy server: URL) -> Bool {
        guard let bound = BoundSessionToken(token: token, issuedBy: server) else { return false }
        return write(bound)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static func readData() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    @discardableResult
    private static func write(_ bound: BoundSessionToken) -> Bool {
        guard let data = try? JSONEncoder().encode(bound) else { return false }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// The Connected Apps server address from Settings, if it is a URL with a scheme and host.
    private static func configuredServer() -> URL? {
        let address = UserDefaults.standard.string(forKey: PreferenceKey.connectedAppsServerURL)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let url = URL(string: address), url.scheme != nil, url.host != nil else { return nil }
        return url
    }
}
