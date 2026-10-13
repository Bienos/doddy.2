import DoddyCore
import Foundation
import Security

/// The Picovoice AccessKey for "Hey Doddy" (ADR-254), in this iPhone's Keychain only. Either the
/// user's own key from the Picovoice Console, or (ADR-328) the owner's key that Doddy's token
/// server hands to a tester, kept under its own account so removing one never removes the other.
/// Nothing of either is in the repository or the app. Picovoice receives it when listening starts.
enum WakeAccessKeyStore {
    private static func keychainQuery(account: String = "default") -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bienos.doddy2.picovoice-access-key",
            kSecAttrAccount as String: account,
        ]
    }

    private static var query: [String: Any] { keychainQuery() }

    /// The key listening uses: the user's own if they saved one, else the token server's.
    static var activeKey: String? { read() ?? readManaged() }

    /// The token server's key (ADR-328).
    static func readManaged() -> String? { read(keychainQuery(account: "managed")) }

    @discardableResult
    static func saveManaged(_ key: String) -> Bool { save(key, to: keychainQuery(account: "managed")) }

    static func deleteManaged() { SecItemDelete(keychainQuery(account: "managed") as CFDictionary) }

    static func read() -> String? { read(query) }

    private static func read(_ base: [String: Any]) -> String? {
        var request = base
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var isSaved: Bool { read() != nil }

    /// Returns false if the Keychain refused the write; Settings then says it wasn't saved.
    /// After first unlock, so listening can restart after a conversation with the iPhone locked.
    static func save(_ key: String) -> Bool { save(key, to: query) }

    private static func save(_ key: String, to base: [String: Any]) -> Bool {
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// The "Hey Doddy" keyword file the user made in the Picovoice Console, copied into Application
/// Support/WakeWord when they choose it in Settings. Not backed up; removing it in Settings
/// deletes the copy. The original in Files is left alone.
enum WakeKeywordStore {
    enum ImportError: Error, Equatable {
        case problem(WakeKeywordFile.Problem)
        case unreadable
        case notSaved

        var message: String {
            switch self {
            case .problem(let problem): problem.message
            case .unreadable: "Doddy couldn't read that file. Download it to this iPhone (Files, On My iPhone) and choose it again."
            case .notSaved: "Doddy couldn't keep a copy of that file on this iPhone. Try again."
            }
        }
    }

    private static let nameKey = "heyDoddy.keywordFileName"

    /// The keyword file that ships in the app (ADR-328): `DoddyApp/Resources/WakeWord/hey-doddy.ppn`,
    /// the owner's, made in the Picovoice Console for iOS and English. Nil until the owner adds it.
    static var bundledURL: URL? { Bundle.main.url(forResource: "hey-doddy", withExtension: "ppn") }

    /// The file listening uses: one the user chose, else the one in the app.
    static var activeURL: URL? {
        if let url, FileManager.default.fileExists(atPath: url.path) { return url }
        return bundledURL
    }

    /// The user's imported copy in Application Support.
    static var url: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("WakeWord", isDirectory: true)
            .appendingPathComponent("hey-doddy.ppn")
    }

    /// The user chose their own file in Settings.
    static var exists: Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// There is a file to listen with, the user's or the app's.
    static var isAvailable: Bool { activeURL != nil }

    /// The name of the file the user chose, for Settings.
    static var importedName: String? {
        exists ? UserDefaults.standard.string(forKey: nameKey) : nil
    }

    /// Copies the chosen file (a security-scoped URL from the file picker) after checking it.
    static func importFile(from source: URL) throws(ImportError) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source) else { throw .unreadable }
        if let problem = WakeKeywordFile.check(fileName: source.lastPathComponent, byteCount: data.count) {
            throw .problem(problem)
        }
        guard var target = url else { throw .notSaved }
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? target.setResourceValues(values)
        } catch {
            throw .notSaved
        }
        UserDefaults.standard.set(source.lastPathComponent, forKey: nameKey)
    }

    static func delete() {
        if let url { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: nameKey)
    }
}

/// "Hey Doddy" with one tap (ADR-328): the owner's Picovoice key comes from Doddy's token server,
/// with the same access code as a conversation, and the keyword file is in the app. A user who
/// saved their own key and file keeps using those.
enum WakeOneTapSetup {
    /// One tap is enough: a keyword file is here, and a key is here or can come from the server.
    static var isReady: Bool {
        WakeKeywordStore.isAvailable && (WakeAccessKeyStore.activeKey != nil || client != nil)
    }

    /// Fetches and keeps the server's key when no key is on this iPhone yet. Nil when there was
    /// nothing to do or it worked; otherwise what to show. The key is never logged.
    static func fetchKeyIfNeeded() async -> String? {
        guard WakeAccessKeyStore.activeKey == nil, let client else { return nil }
        let result: Result<String, VoiceTokenError>
        do throws(VoiceTokenError) {
            result = .success(try await client.fetchWakeWordKey())
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let key):
            return WakeAccessKeyStore.saveManaged(key) ? nil : "Doddy couldn't keep the key on this iPhone. Try again."
        case .failure(let error):
            return VoiceTokenServer.message(for: error)
        }
    }

    /// The token server and access code from Settings → Voice, when both are set.
    private static var client: VoiceTokenClient? {
        let mode = VoiceConnectionMode.resolve(
            serverAddress: UserDefaults.standard.string(forKey: PreferenceKey.voiceTokenServer) ?? "",
            accessCode: VoiceAccessCodeStore.read(), publicAgentID: "")
        guard case .tokenServer(let endpoint, let accessCode) = mode else { return nil }
        return VoiceTokenClient(endpoint: endpoint, accessCode: accessCode)
    }
}

