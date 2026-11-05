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

    /// Whether this is a development build. Compile-time, like `ServerConfig` (ADR-175): nothing typed
    /// in Settings can change it, and a shipped build has no code path that reads the typed address.
    private static var isDevelopmentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The server address, and the ONE place the app decides it (ADR-720): every client, the sign-in,
    /// the account erasure and the warm-up ask here. The device ID is sent to this address and it is
    /// the credential that mints session tokens, so a shipped build uses only the address built into
    /// the app. A development build also takes the address typed in Settings › Advanced, but only
    /// https, or http to this computer (`ServerAddressPolicy`, tested in DoddyCore).
    static func serverURL() -> URL? {
        ServerAddressPolicy.resolve(
            typed: typedServerAddress, builtIn: Bundle.main.object(forInfoDictionaryKey: "DoddyServerURL") as? String,
            debug: isDevelopmentBuild)
    }

    /// What was typed in Settings › Advanced, as typed. The only place that reads it (ADR-720), and only a
    /// development build does: in a shipped build this is always nil.
    private static var typedServerAddress: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: PreferenceKey.connectedAppsServerURL)
        #else
        nil
        #endif
    }

    /// The typed development address alone, when the policy lets it through; nil in a shipped build.
    /// `KeychainSessionStore` binds a token saved before tokens were bound to it.
    static func typedServerURL() -> URL? {
        guard let typed = typedServerAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty,
              let url = URL(string: typed), ServerAddressPolicy.accepts(url, debug: isDevelopmentBuild)
        else { return nil }
        return url
    }

    /// Called at launch (ADR-720). A shipped build no longer reads the address typed in Settings, so
    /// one saved by an earlier build is removed: a phone that was talked into pasting a stranger's
    /// address recovers by updating. The session token that server issued is bound to its host
    /// (`BoundSessionToken`), so it isn't used with the real one; the next sign-in replaces it. The
    /// device ID is not changed (see the ADR).
    static func removeSavedServerOverride(defaults: UserDefaults = .standard) {
        #if !DEBUG
        defaults.removeObject(forKey: PreferenceKey.connectedAppsServerURL)
        #endif
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
        // The device ID goes only to an address the policy lets through, whoever asks (ADR-720).
        guard ServerAddressPolicy.accepts(server, debug: isDevelopmentBuild) else { return false }
        guard let deviceID = deviceID() else { return false }
        let code = Bundle.main.object(forInfoDictionaryKey: "DoddyInviteCode") as? String
        guard let issued = await DeviceSessionClient.signIn(
            server: server, deviceID: deviceID, inviteCode: code, transport: URLSessionTransport.shared)
        else { return false }
        guard KeychainSessionStore.save(issued.token, issuedBy: server) else { return false }
        if let expiry = issued.expiresAt { UserDefaults.standard.set(expiry, forKey: expiryKey) }
        return true
    }

    private static var idQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The device ID if one was made already. Reads only; it never makes one.
    private static func storedDeviceID() -> String? {
        var read = idQuery
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let id = String(data: data, encoding: .utf8), UUID(uuidString: id) != nil {
            return id
        }
        return nil
    }

    /// True when this iPhone already has a device ID, so it has signed in to Doddy's server or is about
    /// to. Reads only, so the privacy screen can ask without making one (ADR-721).
    static var hasDeviceID: Bool { storedDeviceID() != nil }

    /// What the privacy screen means by "Doddy's server is in use" (ADR-721): there is an address the app
    /// would use, and the phone has a session with it or has made the device ID that signs in. Before that
    /// nothing has been sent there.
    static func isServerInUse() -> Bool {
        guard let server = serverURL() else { return false }
        return KeychainSessionStore.read()?.token(for: server) != nil || hasDeviceID
    }

    /// This iPhone's device ID, made once. Nil only if the Keychain refuses to keep it.
    static func deviceID() -> String? {
        if let id = storedDeviceID() { return id }
        let base = idQuery
        let id = UUID().uuidString.lowercased()
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(id.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? id : nil
    }
}
