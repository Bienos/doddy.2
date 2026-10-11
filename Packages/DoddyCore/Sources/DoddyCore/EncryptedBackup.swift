import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Encrypted backup file (ADR-222; owner: "A file you keep"). One file the user saves to Files or
// iCloud Drive themselves and restores on a new iPhone. It holds the notes and lists (the same
// JSON as the export), the photos of photo notes, time reminders and the "About you" answers,
// encrypted with a key made from the user's passphrase. No server, no account, no key escrow:
// without the passphrase nobody, Doddy included, can open it. Restore adds; it never overwrites.

public enum BackupLimits {
    /// PBKDF2-HMAC-SHA256 rounds for new files (OWASP's 2023 figure for this KDF).
    public static let iterations = 600_000
    /// Files asking for fewer rounds are refused (protects against a tampered header).
    public static let minimumIterations = 100_000
    public static let minimumPassphraseLength = 10
    /// Whole file, photos included. Larger backups are refused; make one without photos.
    public static let maxFileBytes = 200 * 1024 * 1024
    public static let fileExtension = "doddybackup"
}

/// What is inside, after decryption.
public struct BackupContents: Codable, Equatable, Sendable {
    public struct Reminder: Codable, Equatable, Sendable {
        public let memoryID: UUID
        /// The next time it fires as the backup was made; repeating ones keep their cadence from it.
        public let fireAtMs: Int64
        public let timeZoneID: String
        public let repeats: String?

        public init(memoryID: UUID, fireAt: Date, timeZoneID: String, repeats: ReminderRepeat?) {
            self.memoryID = memoryID
            self.fireAtMs = Int64((fireAt.timeIntervalSince1970 * 1000).rounded())
            self.timeZoneID = timeZoneID
            self.repeats = repeats?.rawValue
        }

        public var fireAt: Date { Date(timeIntervalSince1970: Double(fireAtMs) / 1000) }
        public var repeatRule: ReminderRepeat? { repeats.flatMap(ReminderRepeat.init(rawValue:)) }

        /// When to set it on restore: its own time if still ahead; for a repeating one whose time
        /// has passed, its next occurrence on the same cadence; nil for a one-off that has passed.
        public func nextFire(after now: Date) -> Date? {
            if fireAt > now { return fireAt }
            guard let rule = repeatRule else { return nil }
            return ReminderSchedule.next(after: now, rule, anchor: fireAt, timeZoneID: timeZoneID)
        }
    }

    public struct Photo: Codable, Equatable, Sendable {
        public let memoryID: UUID
        public let width: Int
        public let height: Int
        public let addedAtMs: Int64
        public let jpeg: Data

        public init(memoryID: UUID, width: Int, height: Int, addedAt: Date, jpeg: Data) {
            self.memoryID = memoryID
            self.width = width
            self.height = height
            self.addedAtMs = Int64((addedAt.timeIntervalSince1970 * 1000).rounded())
            self.jpeg = jpeg
        }
    }

    public static let currentVersion = 1

    public let formatVersion: Int
    public let createdAtMs: Int64
    /// Exactly `MemoryExport.json`: notes, lists and list items, read back with `MemoryRestore`.
    public let memoriesExport: Data
    public let reminders: [Reminder]
    /// "About you" answers by `ProfileKey` raw value.
    public let profile: [String: String]
    public let photos: [Photo]

    public init(createdAt: Date, memoriesExport: Data, reminders: [Reminder], profile: [String: String], photos: [Photo]) {
        self.formatVersion = Self.currentVersion
        self.createdAtMs = Int64((createdAt.timeIntervalSince1970 * 1000).rounded())
        self.memoriesExport = memoriesExport
        self.reminders = reminders
        self.profile = profile
        self.photos = photos
    }

    /// Time reminders worth keeping: the next occurrence of each, after `now`. Place reminders
    /// stay on the iPhone they were made on (a place needs that iPhone's location permission).
    public static func reminders(_ reminders: [MemoryReminder], now: Date) -> [Reminder] {
        reminders.compactMap { reminder in
            guard case .time(_, let zone) = reminder.trigger, let next = reminder.nextFire(after: now) else { return nil }
            return Reminder(memoryID: reminder.memoryID, fireAt: next, timeZoneID: zone, repeats: reminder.repeats)
        }
    }

    public var profileDraft: ProfileDraft {
        ProfileDraft(values: Dictionary(uniqueKeysWithValues: profile.compactMap { key, value in
            ProfileKey(rawValue: key).map { ($0, value) }
        }))
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case passphraseTooShort(minimum: Int)
    case tooLarge(bytes: Int, maximum: Int)
    /// Not a Doddy backup file at all.
    case notABackup
    case newerFormat(Int)
    /// Wrong passphrase, or the file was changed or damaged; AES-GCM can't tell which.
    case wrongPassphraseOrDamaged
    /// The header asks for fewer key rounds than Doddy accepts.
    case weakFile
}

public enum EncryptedBackup {
    public static let format = "doddy-backup"
    public static let fileVersion = 1
    private static let kdfName = "pbkdf2-sha256"
    private static let cipherName = "aes-256-gcm"

    /// The file on disk. Only `sealed` is secret; the rest says how to open it.
    private struct File: Codable {
        let format: String
        let version: Int
        let kdf: String
        let iterations: Int
        let salt: Data
        let cipher: String
        let sealed: Data
    }

    public static func checkPassphrase(_ passphrase: String) throws(BackupError) {
        guard passphrase.count >= BackupLimits.minimumPassphraseLength else {
            throw .passphraseTooShort(minimum: BackupLimits.minimumPassphraseLength)
        }
    }

    public static func encrypt(
        _ contents: BackupContents, passphrase: String, iterations: Int = BackupLimits.iterations
    ) throws -> Data {
        try checkPassphrase(passphrase)
        var salt = Data(count: 16)
        var generator = SystemRandomNumberGenerator()
        for index in salt.indices { salt[index] = UInt8.random(in: .min ... .max, using: &generator) }
        let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let plaintext = try JSONEncoder().encode(contents)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header(iterations: iterations, salt: salt))
        guard let combined = sealed.combined else { throw BackupError.notABackup }
        let file = File(format: format, version: fileVersion, kdf: kdfName, iterations: iterations,
                        salt: salt, cipher: cipherName, sealed: combined)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)
        guard data.count <= BackupLimits.maxFileBytes else {
            throw BackupError.tooLarge(bytes: data.count, maximum: BackupLimits.maxFileBytes)
        }
        return data
    }

    public static func decrypt(
        _ data: Data, passphrase: String, minimumIterations: Int = BackupLimits.minimumIterations
    ) throws(BackupError) -> BackupContents {
        guard data.count <= BackupLimits.maxFileBytes else {
            throw .tooLarge(bytes: data.count, maximum: BackupLimits.maxFileBytes)
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.format == format else { throw .notABackup }
        guard file.version <= fileVersion else { throw .newerFormat(file.version) }
        guard file.kdf == kdfName, file.cipher == cipherName, file.salt.count >= 16 else { throw .notABackup }
        guard file.iterations >= minimumIterations else { throw .weakFile }
        let key = deriveKey(passphrase: passphrase, salt: file.salt, iterations: file.iterations)
        guard let box = try? AES.GCM.SealedBox(combined: file.sealed),
              let plaintext = try? AES.GCM.open(box, using: key, authenticating: header(iterations: file.iterations, salt: file.salt))
        else { throw .wrongPassphraseOrDamaged }
        guard let contents = try? JSONDecoder().decode(BackupContents.self, from: plaintext) else { throw .notABackup }
        guard contents.formatVersion <= BackupContents.currentVersion else { throw .newerFormat(contents.formatVersion) }
        return contents
    }

    /// The header fields are authenticated with the data, so a changed round count or salt fails.
    private static func header(iterations: Int, salt: Data) -> Data {
        Data("\(format)|\(fileVersion)|\(kdfName)|\(iterations)|\(salt.base64EncodedString())|\(cipherName)".utf8)
    }

    /// The passphrase in Unicode NFC, so the same words typed on another keyboard give the same key.
    static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        SymmetricKey(data: pbkdf2SHA256(password: Data(passphrase.precomposedStringWithCanonicalMapping.utf8),
                                        salt: salt, iterations: iterations, length: 32))
    }

    /// PBKDF2-HMAC-SHA256 (RFC 8018) on the platform's HMAC; checked against published vectors.
    public static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, length: Int) -> Data {
        let keyed = HMAC<SHA256>(key: SymmetricKey(data: password))
        var output = Data()
        var block: UInt32 = 1
        while output.count < length {
            var first = keyed
            first.update(data: salt)
            first.update(data: withUnsafeBytes(of: block.bigEndian) { Data($0) })
            var u = Array(first.finalize())
            var t = u
            if iterations > 1 {
                for _ in 1..<iterations {
                    var next = keyed
                    next.update(data: u)
                    u = Array(next.finalize())
                    for index in t.indices { t[index] ^= u[index] }
                }
            }
            output.append(contentsOf: t)
            block += 1
        }
        return output.prefix(length)
    }
}

/// What restoring a backup would do, worked out before anything is written. It only adds.
public struct BackupRestorePlan: Equatable, Sendable {
    public let notes: MemoryRestorePlan
    public let listItems: [ListItem]
    /// Photos for notes this restore adds (a note already here keeps its own photo or none).
    public let photos: [BackupContents.Photo]
    /// Reminders for notes this restore adds, still ahead (or repeating).
    public let reminders: [BackupContents.Reminder]
    /// The "About you" answers, only when this iPhone has none.
    public let profile: ProfileDraft?

    public static func make(
        _ contents: BackupContents, existing: [MemoryRecord], profileIsEmpty: Bool, now: Date
    ) throws(MemoryRestoreError) -> BackupRestorePlan {
        let read = try MemoryRestore.read(contents.memoriesExport)
        // Every earlier wording of the added notes comes back too (ADR-236).
        let notes = MemoryRestore.plan(read.records, corrections: read.corrections, existing: existing, exportedAt: read.exportedAt)
        let added = Set(notes.toAdd.map(\.id))
        let items = try MemoryRestore.listItems(contents.memoriesExport).filter { added.contains($0.listID) }
        let reminders = contents.reminders.filter { added.contains($0.memoryID) && $0.nextFire(after: now) != nil }
        let photos = contents.photos.filter { added.contains($0.memoryID) }
        let draft = contents.profileDraft
        return BackupRestorePlan(
            notes: notes, listItems: items, photos: photos, reminders: reminders,
            profile: profileIsEmpty && !draft.values.isEmpty ? draft : nil)
    }

    public var isEmpty: Bool { notes.isEmpty && profile == nil }
}
