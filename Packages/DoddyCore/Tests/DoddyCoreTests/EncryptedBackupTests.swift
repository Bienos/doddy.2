import DoddyCore
import XCTest

/// Encrypted backup file (ADR-222): key derivation, sealing, refusal, and an add-only restore plan.
final class EncryptedBackupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let passphrase = "blue tin kettle on the shelf"

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    /// Published PBKDF2-HMAC-SHA256 test vectors ("password" / "salt").
    func testPBKDF2MatchesPublishedVectors() {
        let password = Data("password".utf8), salt = Data("salt".utf8)
        XCTAssertEqual(hex(EncryptedBackup.pbkdf2SHA256(password: password, salt: salt, iterations: 1, length: 32)),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        XCTAssertEqual(hex(EncryptedBackup.pbkdf2SHA256(password: password, salt: salt, iterations: 2, length: 32)),
                       "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        XCTAssertEqual(hex(EncryptedBackup.pbkdf2SHA256(password: password, salt: salt, iterations: 4096, length: 32)),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    private func contents() throws -> (BackupContents, MemoryRecord, MemoryRecord) {
        let note = try MemoryRecord(id: UUID(), rawText: "Locker code 4512", source: .explicitText, category: .fact, capturedAt: now)
        let list = try MemoryRecord(id: UUID(), rawText: "Shopping", source: .explicitVoice, category: .list, capturedAt: now)
        let item = ListItem(id: UUID(), listID: list.id, text: "oat milk", source: .voice, addedAt: now, doneAt: nil, position: 0)
        let export = try MemoryExport.json([note, list], listItems: [item], exportedAt: now)
        let contents = BackupContents(
            createdAt: now, memoriesExport: export,
            reminders: [
                .init(memoryID: note.id, fireAt: now.addingTimeInterval(3600), timeZoneID: "Europe/Warsaw", repeats: nil),
                .init(memoryID: note.id, fireAt: now.addingTimeInterval(-3600), timeZoneID: "Europe/Warsaw", repeats: .weekly),
                .init(memoryID: list.id, fireAt: now.addingTimeInterval(-60), timeZoneID: "UTC", repeats: nil),
            ],
            profile: ["name": "Ola", "unknownKey": "x"],
            photos: [.init(memoryID: note.id, width: 10, height: 8, addedAt: now, jpeg: Data([0xFF, 0xD8, 1, 2, 0xFF, 0xD9]))],
            recordings: [.init(memoryID: note.id, durationMilliseconds: 4_200, addedAt: now, m4a: Data([0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70]))])
        return (contents, note, list)
    }

    func testRoundTripAndWrongPassphrase() throws {
        let (contents, _, _) = try contents()
        let file = try EncryptedBackup.encrypt(contents, passphrase: passphrase, iterations: 1_000)
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("4512"), "nothing readable without the passphrase")
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("Locker"))
        XCTAssertEqual(try EncryptedBackup.decrypt(file, passphrase: passphrase, minimumIterations: 1_000), contents)
        // Same words, decomposed accents: same key.
        let accented = "zażółć gęślą jaźń 2026"
        let other = try EncryptedBackup.encrypt(contents, passphrase: accented, iterations: 1_000)
        XCTAssertEqual(try EncryptedBackup.decrypt(other, passphrase: accented.decomposedStringWithCanonicalMapping, minimumIterations: 1_000), contents)

        XCTAssertThrowsError(try EncryptedBackup.decrypt(file, passphrase: "blue tin kettle on the shelF", minimumIterations: 1_000)) {
            XCTAssertEqual($0 as? BackupError, .wrongPassphraseOrDamaged)
        }
        XCTAssertThrowsError(try EncryptedBackup.encrypt(contents, passphrase: "short", iterations: 1_000)) {
            XCTAssertEqual($0 as? BackupError, .passphraseTooShort(minimum: BackupLimits.minimumPassphraseLength))
        }
    }

    func testTamperedOrForeignFilesAreRefused() throws {
        let (contents, _, _) = try contents()
        let file = try EncryptedBackup.encrypt(contents, passphrase: passphrase, iterations: 1_000)
        XCTAssertThrowsError(try EncryptedBackup.decrypt(file, passphrase: passphrase)) {
            XCTAssertEqual($0 as? BackupError, .weakFile, "the default floor refuses a low round count")
        }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
        json["iterations"] = 1_001
        let changedHeader = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try EncryptedBackup.decrypt(changedHeader, passphrase: passphrase, minimumIterations: 1_000)) {
            XCTAssertEqual($0 as? BackupError, .wrongPassphraseOrDamaged, "the header is authenticated")
        }
        json["iterations"] = 1_000
        var sealed = try XCTUnwrap(Data(base64Encoded: json["sealed"] as! String))
        sealed[sealed.count / 2] ^= 0x01
        json["sealed"] = sealed.base64EncodedString()
        XCTAssertThrowsError(try EncryptedBackup.decrypt(try JSONSerialization.data(withJSONObject: json), passphrase: passphrase, minimumIterations: 1_000)) {
            XCTAssertEqual($0 as? BackupError, .wrongPassphraseOrDamaged)
        }
        json["version"] = 9
        XCTAssertThrowsError(try EncryptedBackup.decrypt(try JSONSerialization.data(withJSONObject: json), passphrase: passphrase, minimumIterations: 1_000)) {
            XCTAssertEqual($0 as? BackupError, .newerFormat(9))
        }
        XCTAssertThrowsError(try EncryptedBackup.decrypt(contents.memoriesExport, passphrase: passphrase)) {
            XCTAssertEqual($0 as? BackupError, .notABackup, "a plain export isn't a backup")
        }
    }

    /// Review B3: the export inside a backup may be larger than a plain export file may be; a
    /// backup Doddy could make and verify can also be restored.
    func testLargeExportInsideABackupCanBeRestored() throws {
        let (small, note, list) = try contents()
        var export = small.memoriesExport
        export.append(Data(repeating: UInt8(ascii: " "), count: MemoryRestore.maxFileBytes))
        XCTAssertThrowsError(try MemoryRestore.read(export)) {
            XCTAssertEqual($0 as? MemoryRestoreError, .tooLarge(bytes: export.count, maximum: MemoryRestore.maxFileBytes))
        }
        let large = BackupContents(createdAt: now, memoriesExport: export, reminders: [], profile: [:], photos: [])
        let plan = try BackupRestorePlan.make(large, existing: [], profileIsEmpty: true, now: now)
        XCTAssertEqual(Set(plan.notes.toAdd.map(\.id)), [note.id, list.id])
        XCTAssertEqual(plan.listItems.map(\.text), ["oat milk"])
    }

    /// Review B2: a header asking for a huge round count is refused before any key is made, and
    /// making the key stops when the restore is cancelled.
    func testHugeRoundCountIsRefusedAndKeyMakingCanBeCancelled() async throws {
        let (contents, _, _) = try contents()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try EncryptedBackup.encrypt(contents, passphrase: passphrase, iterations: 1_000)) as? [String: Any])
        json["iterations"] = Int(Int32.max)
        let huge = try JSONSerialization.data(withJSONObject: json)
        let started = Date()
        XCTAssertThrowsError(try EncryptedBackup.decrypt(huge, passphrase: passphrase)) {
            XCTAssertEqual($0 as? BackupError, .weakFile)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)

        json["iterations"] = BackupLimits.maximumIterations
        let slow = try JSONSerialization.data(withJSONObject: json)
        let words = passphrase
        let task = Task.detached { try EncryptedBackup.decrypt(slow, passphrase: words) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    func testRestoreOnlyAdds() throws {
        let (contents, note, list) = try contents()
        // A fresh iPhone: everything comes back, reminders that can still ring, profile known keys only.
        let fresh = try BackupRestorePlan.make(contents, existing: [], profileIsEmpty: true, now: now)
        XCTAssertEqual(Set(fresh.notes.toAdd.map(\.id)), [note.id, list.id])
        XCTAssertEqual(fresh.listItems.map(\.text), ["oat milk"])
        XCTAssertEqual(fresh.photos.count, 1)
        XCTAssertEqual(fresh.recordings.map(\.durationMilliseconds), [4_200])
        XCTAssertEqual(fresh.reminders.count, 2, "the passed one-off is left out; the weekly one comes back")
        let weekly = try XCTUnwrap(fresh.reminders.first { $0.repeatRule == .weekly })
        XCTAssertEqual(weekly.nextFire(after: now), now.addingTimeInterval(7 * 24 * 3600 - 3600))
        XCTAssertEqual(fresh.profile?.values, [.name: "Ola"])

        // The note is already here: it, its photo and its reminder are left alone; the profile too.
        let here = try BackupRestorePlan.make(contents, existing: [note], profileIsEmpty: false, now: now)
        XCTAssertEqual(here.notes.toAdd.map(\.id), [list.id])
        XCTAssertEqual(here.notes.alreadyHere, 1)
        XCTAssertTrue(here.photos.isEmpty)
        XCTAssertTrue(here.recordings.isEmpty)
        XCTAssertTrue(here.reminders.isEmpty)
        XCTAssertNil(here.profile)
    }

    /// ADR-252: a corrected note's earlier wordings travel in the backup and come back with it.
    func testCorrectionsComeBackWithTheirNote() throws {
        let note = try MemoryRecord(
            id: UUID(), rawText: "Size 43", currentText: "Size 42.5", source: .explicitText, capturedAt: now,
            updatedAt: now.addingTimeInterval(120), userEdited: true)
        let history = [
            try MemoryCorrection(memoryID: note.id, number: 1, text: "Size 42", correctedAt: now.addingTimeInterval(60)),
            try MemoryCorrection(memoryID: note.id, number: 2, text: "Size 42.5", correctedAt: now.addingTimeInterval(120)),
        ]
        let export = try MemoryExport.json([note], corrections: history, exportedAt: now)
        let contents = BackupContents(createdAt: now, memoriesExport: export, reminders: [], profile: [:], photos: [])
        let opened = try EncryptedBackup.decrypt(try EncryptedBackup.encrypt(contents, passphrase: passphrase), passphrase: passphrase)
        let plan = try BackupRestorePlan.make(opened, existing: [], profileIsEmpty: false, now: now)
        XCTAssertEqual(plan.notes.toAdd, [note])
        XCTAssertEqual(plan.notes.corrections, history)
        // Already on this iPhone: its own history stays, nothing from the file is added.
        let here = try BackupRestorePlan.make(opened, existing: [note], profileIsEmpty: false, now: now)
        XCTAssertEqual(here.notes.corrections, [])
    }

    func testBackupsMadeBeforeVoiceMemosStillOpen() throws {
        let (contents, _, _) = try contents()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(contents)) as? [String: Any])
        XCTAssertNotNil(json["recordings"])
        json["recordings"] = nil
        let older = try JSONDecoder().decode(BackupContents.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(older.recordings, [])
        XCTAssertEqual(older.photos, contents.photos)
    }

    func testOnlyTimeRemindersAreBackedUp() throws {
        let id = UUID()
        let time = MemoryReminder(id: UUID(), memoryID: id, fireAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now)
        let gone = MemoryReminder(id: UUID(), memoryID: id, fireAt: now.addingTimeInterval(-60), timeZoneID: "UTC", createdAt: now)
        let place = MemoryReminder(
            id: UUID(), memoryID: id,
            trigger: .place(try ReminderPlace(name: "Home", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true)),
            createdAt: now)
        XCTAssertEqual(BackupContents.reminders([time, gone, place], now: now).count, 1)
    }
}
