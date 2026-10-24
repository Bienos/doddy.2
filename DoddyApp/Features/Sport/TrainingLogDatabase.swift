import DoddyCore
import DoddyPersistence
import Foundation

/// Where the training log is kept (sport plan stage 3, ADR-632): its own SQLite file,
/// `Application Support/Sport/training-log.sqlite`, not the notes' file. The notes' folder is in
/// device backups; training notes are health data, so this folder is left out of iCloud and computer
/// backups like the training plan's (ADR-625; App Review 5.1.3). The folder is created and the file
/// opened only when the person turns the log on, so nothing exists on a phone that never did.
///
/// `DoddyDatabase` runs every migration, so this file also holds the notes' tables, empty. They are
/// never written from here.
enum TrainingLogDatabase {
    static func fileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return support.appendingPathComponent("Sport", isDirectory: true).appendingPathComponent("training-log.sqlite")
    }

    static var exists: Bool {
        guard !isUITest, let url = fileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func open() throws -> any TrainingLogRepository {
        if isUITest { return SQLiteTrainingLogRepository(database: try DoddyDatabase.inMemory()) }
        guard let url = fileURL() else { throw CocoaError(.fileNoSuchFile) }
        var folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return SQLiteTrainingLogRepository(database: try DoddyDatabase(path: url.path))
    }

    /// UI-test launches keep the log in memory and write nothing to disk.
    private static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-inMemoryStore") }
}

extension TrainingLogModel {
    /// The one model of the screen and its Connections card.
    static let shared = TrainingLogModel(
        open: { try TrainingLogDatabase.open() }, storeExists: { TrainingLogDatabase.exists },
        plan: { TrainingPlanStore.shared.saved?.plan })
}
