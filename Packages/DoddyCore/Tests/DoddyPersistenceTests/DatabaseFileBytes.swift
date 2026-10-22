import Foundation
import GRDB

/// What is physically in a SQLite file, not what a query returns. `secure_delete` overwrites a
/// deleted row's pages but not the words the FTS5 index keeps of it, so a deleted or corrected
/// word is only known to be gone by reading the bytes (ADR-584).
enum DatabaseFileBytes {
    /// The database file and its `-wal` and `-journal` files, as they are on disk right now.
    static func contents(at path: String) -> Data {
        var bytes = Data()
        for suffix in ["", "-wal", "-journal"] {
            if let data = FileManager.default.contents(atPath: path + suffix) { bytes.append(data) }
        }
        return bytes
    }

    /// How many times `marker` is in those bytes.
    static func occurrences(of marker: String, at path: String) -> Int {
        let bytes = contents(at: path), needle = Data(marker.utf8)
        var count = 0, from = bytes.startIndex
        while let hit = bytes.range(of: needle, in: from..<bytes.endIndex) {
            count += 1
            from = hit.upperBound
        }
        return count
    }

    /// Whether the full-text index itself finds `word`. A repository query can also find a note by
    /// scanning the table, which would not show that the word was ever indexed.
    static func indexFinds(_ word: String, in table: String, at path: String) throws -> Bool {
        let found = try DatabaseQueue(path: path).read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table) WHERE \(table) MATCH ?", arguments: [word])
        }
        return (found ?? 0) > 0
    }

    static func remove(_ path: String) {
        for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }
}
