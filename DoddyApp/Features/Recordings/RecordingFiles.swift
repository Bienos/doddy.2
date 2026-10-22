import AVFoundation
import DoddyCore
import Foundation

/// The folder of DODDY Capture audio, next to the database (ADR-588):
/// `Recordings/<recording id>/part-0001.caf`, `part-0002.caf`, and so on. Each part is closed on its
/// own, so Doddy being closed in the middle of a recording costs at most the part in progress.
///
/// The files are readable after the first unlock, not only while unlocked (`complete` would stop the
/// recording the moment the screen locked), and are kept out of the iPhone's backups: they are large
/// and private. Names are made by Doddy (`RecordingPart.fileName`); nothing from outside is a path.
struct RecordingFiles: Sendable {
    /// nil when the notes database couldn't be opened: nothing is written or read.
    let directory: URL?

    static let unavailable = RecordingFiles(directory: nil)

    static func beside(database url: URL) -> RecordingFiles {
        RecordingFiles(directory: url.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true))
    }

    /// A fresh folder for an in-memory database (UI tests), emptied with the temporary directory.
    static func temporary() -> RecordingFiles {
        RecordingFiles(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("DoddyRecordings-\(UUID().uuidString)", isDirectory: true))
    }

    func folder(for recordingID: UUID) -> URL? {
        directory?.appendingPathComponent(recordingID.uuidString.lowercased(), isDirectory: true)
    }

    func url(recordingID: UUID, fileName: String) -> URL? {
        guard RecordingPart.isValidFileName(fileName) else { return nil }
        return folder(for: recordingID)?.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Creates the recording's folder, and the root with it.
    @discardableResult
    func prepareFolder(for recordingID: UUID) throws -> URL {
        guard var root = directory, let folder = folder(for: recordingID) else {
            throw DoddyError.capabilityUnavailable(.memoryStorage)
        }
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        return folder
    }

    /// Deletes a recording's whole folder.
    func remove(recordingID: UUID) {
        if let folder = folder(for: recordingID) { try? FileManager.default.removeItem(at: folder) }
    }

    /// Deletes some of a recording's part files (rows already dropped).
    func remove(recordingID: UUID, fileNames: [String]) {
        for name in fileNames {
            if let url = url(recordingID: recordingID, fileName: name) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// "Delete everything": the whole folder of recordings.
    func removeAll() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// Names of the folders inside, for finding ones that belong to no recording.
    func folderNames() -> [String] {
        guard let directory else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    /// Removes a folder named by `CaptureRecovery.orphanDirectories`, which only ever names
    /// recording ids.
    func removeFolder(named name: String) {
        guard let directory, UUID(uuidString: name) != nil else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name, isDirectory: true))
    }

    /// Space iOS says is available for something the user asked for, or nil if it can't tell.
    func freeBytes() -> Int64? {
        var probe = directory ?? FileManager.default.temporaryDirectory
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    /// How much audio the file really holds, read from the file. Nil if it cannot be read.
    func probeDurationMilliseconds(_ url: URL) -> Int? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Int((Double(file.length) / file.processingFormat.sampleRate * 1000).rounded())
    }

    func modifiedAt(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func exists(recordingID: UUID, fileName: String) -> Bool {
        url(recordingID: recordingID, fileName: fileName).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
}
