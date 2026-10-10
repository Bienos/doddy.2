import DoddyCore
import Foundation
import GRDB

/// Meaning-search vectors (ADR-228) in the same SQLite file as the notes. A vector row references
/// its note, so deleting a note (or every note) deletes its vector; `secure_delete` overwrites it.
public final class SQLiteMemoryVectorStore: MemoryVectorStore {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func vectors(modelID: String) async throws -> [MeaningVector] {
        try await dbQueue.read { db in
            try Row.fetchAll(
                db, sql: "SELECT memory_id, text_hash, dimension, vector FROM memory_vectors WHERE model_id = ?",
                arguments: [modelID]
            ).compactMap { row -> MeaningVector? in
                guard let id = UUID(uuidString: row["memory_id"]),
                      let values = Self.floats(row["vector"], dimension: row["dimension"])
                else { return nil }
                return MeaningVector(memoryID: id, textHash: row["text_hash"], values: values)
            }
        }
    }

    /// Notes deleted since the vector was made are skipped (the reference would fail).
    public func store(_ vectors: [MeaningVector], modelID: String) async throws {
        try await dbQueue.write { db in
            for vector in vectors where !vector.values.isEmpty {
                guard try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM memories WHERE id = ?)", arguments: [vector.memoryID.uuidString]) == true
                else { continue }
                try db.execute(
                    sql: """
                        INSERT INTO memory_vectors (memory_id, model_id, text_hash, dimension, vector)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(memory_id) DO UPDATE SET
                            model_id = excluded.model_id, text_hash = excluded.text_hash,
                            dimension = excluded.dimension, vector = excluded.vector
                        """,
                    arguments: [vector.memoryID.uuidString, modelID, vector.textHash, vector.values.count, Self.blob(vector.values)])
            }
        }
    }

    public func removeAll() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM memory_vectors")
        }
    }

    /// Rows stored, all models (tests and Settings).
    public func count() async throws -> Int {
        try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory_vectors") ?? 0 }
    }

    static func blob(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func floats(_ data: Data, dimension: Int) -> [Float]? {
        guard dimension > 0, data.count == dimension * 4 else { return nil }
        let bytes = [UInt8](data)
        return (0..<dimension).map { index in
            var bits: UInt32 = 0
            for offset in 0..<4 { bits |= UInt32(bytes[index * 4 + offset]) << (8 * offset) }
            return Float(bitPattern: bits)
        }
    }
}
