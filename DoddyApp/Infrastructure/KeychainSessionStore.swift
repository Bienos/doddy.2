import DoddyCore
import Foundation
import Security

/// The Doddy server session token lives only in the iOS Keychain (this device only, never in
/// UserDefaults, backups or the app bundle). Provider tokens never reach the app at all.
/// It is stored with the server that issued it (`BoundSessionToken`), and the clients send it
/// only to that server, so changing the address can't hand the TOKEN to another host (DOD-11).
/// That binding does not protect the DEVICE ID, the credential that mints tokens: `DeviceSession`
/// sends it to whatever address `DeviceSession.serverURL()` returns, which in a shipped build is only
/// the one built into the app and never one typed in Settings (ADR-720).
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
    /// had no record of its server, so there is nothing better to bind it to. A shipped build has
    /// no such address (ADR-720), so it never uses one; the next sign-in replaces it.
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

    /// The Connected Apps server address from Settings, if the address policy lets it through. Only a
    /// development build has one (ADR-720); a shipped build ignores what was typed. Asked of
    /// `DeviceSession`, the one place that reads the typed address.
    private static func configuredServer() -> URL? {
        DeviceSession.typedServerURL()
    }
}

/// Decision 2026-11-08-required-account: the signed-in Doddy account (its access and refresh tokens and
/// who it is), in the Keychain on this device only, never in backups or UserDefaults. Only
/// `DoddyAccountModel` reads and writes it, and only a kept session counts as signed in.
struct DoddyAccountKeychain: DoddyAccountSessionStore {
    private static let service = "com.bienos.doddy2.doddy-account"
    private static let account = "session"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: Self.account]
    }

    func load() -> DoddyAccountSession? {
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(DoddyAccountSession.self, from: data)
    }

    func save(_ session: DoddyAccountSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
