import DoddyCore
import Foundation
import Security

/// The Picovoice AccessKey for "Hey Doddy" (ADR-234), in this iPhone's Keychain only. It is the
/// user's own key from the Picovoice Console; nothing of it is in the repository or the app.
/// Picovoice receives it when listening starts, to check it.
enum WakeAccessKeyStore {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bienos.doddy2.picovoice-access-key",
            kSecAttrAccount as String: "default",
        ]
    }

    static func read() -> String? {
        var request = query
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
    static func save(_ key: String) -> Bool {
        delete()
        var item = query
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

    static var url: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("WakeWord", isDirectory: true)
            .appendingPathComponent("hey-doddy.ppn")
    }

    static var exists: Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

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
