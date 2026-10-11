import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Encrypted backup file (ADR-222; owner: "A file you keep"). One file the user saves to Files or
// iCloud Drive themselves and restores on a new iPhone. It holds the notes and lists (the same
// JSON as the export), the photos of photo notes, voice memo recordings (ADR-234, optional, like
// photos), time reminders and the "About you" answers,
// encrypted with a key made from the user's passphrase. No server, no account, no key escrow:
// without the passphrase nobody, Doddy included, can open it. Restore adds; it never overwrites.

public enum BackupLimits {
    /// PBKDF2-HMAC-SHA256 rounds for new files (OWASP's 2023 figure for this KDF).
    public static let iterations = 600_000
    /// Files asking for fewer rounds are refused (protects against a tampered header).
    public static let minimumIterations = 100_000
    /// Files asking for more are refused too, so a crafted or damaged header can't keep the
    /// restore screen busy for hours (ten times what Doddy writes).
    public static let maximumIterations = 6_000_000
    public static let minimumPassphraseLength = 10
    /// Whole file, photos included. Larger backups are refused; make one without photos or voice memos.
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

    /// A note's voice memo (ADR-234). Files made before it have none; they still open.
    public struct Recording: Codable, Equatable, Sendable {
        public let memoryID: UUID
        public let durationMilliseconds: Int
        public let addedAtMs: Int64
        public let m4a: Data

        public init(memoryID: UUID, durationMilliseconds: Int, addedAt: Date, m4a: Data) {
            self.memoryID = memoryID
            self.durationMilliseconds = durationMilliseconds
            self.addedAtMs = Int64((addedAt.timeIntervalSince1970 * 1000).rounded())
            self.m4a = m4a
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
    public let recordings: [Recording]

    public init(
        createdAt: Date, memoriesExport: Data, reminders: [Reminder], profile: [String: String], photos: [Photo],
        recordings: [Recording] = []
    ) {
        self.formatVersion = Self.currentVersion
        self.createdAtMs = Int64((createdAt.timeIntervalSince1970 * 1000).rounded())
        self.memoriesExport = memoriesExport
        self.reminders = reminders
        self.profile = profile
        self.photos = photos
        self.recordings = recordings
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, createdAtMs, memoriesExport, reminders, profile, photos, recordings
    }

    /// Recordings are optional in the file, so backups made before ADR-234 still open.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        createdAtMs = try container.decode(Int64.self, forKey: .createdAtMs)
        memoriesExport = try container.decode(Data.self, forKey: .memoriesExport)
        reminders = try container.decode([Reminder].self, forKey: .reminders)
        profile = try container.decode([String: String].self, forKey: .profile)
        photos = try container.decode([Photo].self, forKey: .photos)
        recordings = try container.decodeIfPresent([Recording].self, forKey: .recordings) ?? []
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
    /// The header asks for fewer (or far more) key rounds than Doddy accepts.
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
        guard let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations) else { throw CancellationError() }
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

    /// Throws `BackupError`, or `CancellationError` when the calling task is cancelled while the
    /// key is being made.
    public static func decrypt(
        _ data: Data, passphrase: String, minimumIterations: Int = BackupLimits.minimumIterations
    ) throws -> BackupContents {
        guard data.count <= BackupLimits.maxFileBytes else {
            throw BackupError.tooLarge(bytes: data.count, maximum: BackupLimits.maxFileBytes)
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.format == format else { throw BackupError.notABackup }
        guard file.version <= fileVersion else { throw BackupError.newerFormat(file.version) }
        guard file.kdf == kdfName, file.cipher == cipherName, file.salt.count >= 16 else { throw BackupError.notABackup }
        guard file.iterations >= minimumIterations, file.iterations <= BackupLimits.maximumIterations else {
            throw BackupError.weakFile
        }
        guard let key = deriveKey(
            passphrase: passphrase, salt: file.salt, iterations: file.iterations, isCancelled: { Task.isCancelled })
        else { throw CancellationError() }
        guard let box = try? AES.GCM.SealedBox(combined: file.sealed),
              let plaintext = try? AES.GCM.open(box, using: key, authenticating: header(iterations: file.iterations, salt: file.salt))
        else { throw BackupError.wrongPassphraseOrDamaged }
        guard let contents = try? JSONDecoder().decode(BackupContents.self, from: plaintext) else { throw BackupError.notABackup }
        guard contents.formatVersion <= BackupContents.currentVersion else {
            throw BackupError.newerFormat(contents.formatVersion)
        }
        return contents
    }

    /// The header fields are authenticated with the data, so a changed round count or salt fails.
    private static func header(iterations: Int, salt: Data) -> Data {
        Data("\(format)|\(fileVersion)|\(kdfName)|\(iterations)|\(salt.base64EncodedString())|\(cipherName)".utf8)
    }

    /// The passphrase in Unicode NFC, so the same words typed on another keyboard give the same key.
    /// Nil once `isCancelled` says so.
    static func deriveKey(
        passphrase: String, salt: Data, iterations: Int, isCancelled: () -> Bool = { false }
    ) -> SymmetricKey? {
        pbkdf2SHA256(password: Data(passphrase.precomposedStringWithCanonicalMapping.utf8),
                     salt: salt, iterations: iterations, length: 32, isCancelled: isCancelled)
            .map { SymmetricKey(data: $0) }
    }

    /// PBKDF2-HMAC-SHA256 (RFC 8018) on the platform's HMAC; checked against published vectors.
    public static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, length: Int) -> Data {
        pbkdf2SHA256(password: password, salt: salt, iterations: iterations, length: length, isCancelled: { false })!
    }

    /// The same; asks `isCancelled` every 10,000 rounds and returns nil once it says so.
    static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, length: Int, isCancelled: () -> Bool) -> Data? {
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
                for round in 1..<iterations {
                    if round % 10_000 == 0, isCancelled() { return nil }
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
    /// Voice memos for notes this restore adds, with a valid length.
    public let recordings: [BackupContents.Recording]
    /// Reminders for notes this restore adds, still ahead (or repeating).
    public let reminders: [BackupContents.Reminder]
    /// The "About you" answers, only when this iPhone has none.
    public let profile: ProfileDraft?

    public static func make(
        _ contents: BackupContents, existing: [MemoryRecord], profileIsEmpty: Bool, now: Date
    ) throws(MemoryRestoreError) -> BackupRestorePlan {
        // The backup's own size limit applies, not the export file's (review B3).
        let read = try MemoryRestore.read(contents.memoriesExport, maxBytes: BackupLimits.maxFileBytes)
        // Every earlier wording of the added notes comes back too (ADR-252).
        let notes = MemoryRestore.plan(read.records, corrections: read.corrections, existing: existing, exportedAt: read.exportedAt)
        let added = Set(notes.toAdd.map(\.id))
        let items = try MemoryRestore.listItems(contents.memoriesExport, maxBytes: BackupLimits.maxFileBytes).filter { added.contains($0.listID) }
        let reminders = contents.reminders.filter { added.contains($0.memoryID) && $0.nextFire(after: now) != nil }
        let photos = contents.photos.filter { added.contains($0.memoryID) }
        let recordings = contents.recordings.filter { added.contains($0.memoryID) && MemoryAudio.isValidDuration($0.durationMilliseconds) }
        let draft = contents.profileDraft
        return BackupRestorePlan(
            notes: notes, listItems: items, photos: photos, recordings: recordings, reminders: reminders,
            profile: profileIsEmpty && !draft.values.isEmpty ? draft : nil)
    }

    public var isEmpty: Bool { notes.isEmpty && profile == nil }
}
