import DoddyCore
import Foundation
import Security

/// ADR-563: the phone signs itself in to Doddy's server, so web search, Claude and online accounts
/// work without a token pasted into Settings.
///
/// One random device ID lives in this iPhone's Keychain (this device only, not in backups). The
/// server turns it into a session token (`POST /v1/session/device`, `DeviceSessionClient`); for the
/// beta the server belongs to the first iPhone that signs in. The token goes into
/// `KeychainSessionStore`, bound to the server that issued it, exactly like a hand-made token did,
/// so every existing client keeps working unchanged.
enum DeviceSession {
    private static let service = "com.bienos.doddy2.device"
    private static let account = "device-id"
    private static let expiryKey = "deviceSession.expiresAt"
    /// Ask for a new token when the old one has less than this left (tokens last 30 days).
    private static let renewBefore: TimeInterval = 2 * 24 * 60 * 60

    /// The server address: Settings' development field when set, else the one built into the app.
    static func serverURL() -> URL? {
        let typed = UserDefaults.standard.string(forKey: PreferenceKey.connectedAppsServerURL)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let address = typed.isEmpty ? (Bundle.main.object(forInfoDictionaryKey: "DoddyServerURL") as? String ?? "") : typed
        guard let url = URL(string: address), url.host != nil, url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    /// True when a usable token for `server` is in the Keychain, getting one first if needed.
    /// A token typed in Settings (no recorded expiry) is used as it is.
    @discardableResult
    static func ensure(server: URL, now: Date = Date()) async -> Bool {
        if KeychainSessionStore.read()?.token(for: server) != nil {
            guard let expiry = UserDefaults.standard.object(forKey: expiryKey) as? Date else { return true }
            if expiry.timeIntervalSince(now) > renewBefore { return true }
        }
        return await signIn(server: server)
    }

    /// The server refused the token (expired, or its key changed): forget it and sign in again.
    static func renew(server: URL) async -> Bool {
        KeychainSessionStore.delete()
        UserDefaults.standard.removeObject(forKey: expiryKey)
        return await signIn(server: server)
    }

    private static func signIn(server: URL) async -> Bool {
        guard let deviceID = deviceID() else { return false }
        let code = Bundle.main.object(forInfoDictionaryKey: "DoddyInviteCode") as? String
        guard let issued = await DeviceSessionClient.signIn(
            server: server, deviceID: deviceID, inviteCode: code, transport: URLSessionTransport.shared)
        else { return false }
        guard KeychainSessionStore.save(issued.token, issuedBy: server) else { return false }
        if let expiry = issued.expiresAt { UserDefaults.standard.set(expiry, forKey: expiryKey) }
        return true
    }

    /// This iPhone's device ID, made once. Nil only if the Keychain refuses to keep it.
    static func deviceID() -> String? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var read = base
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let id = String(data: data, encoding: .utf8), UUID(uuidString: id) != nil {
            return id
        }
        let id = UUID().uuidString.lowercased()
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(id.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? id : nil
    }
}
