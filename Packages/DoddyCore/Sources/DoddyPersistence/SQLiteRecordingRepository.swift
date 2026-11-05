import DoddyCore
import Foundation
import GRDB

/// DODDY Capture's recordings, their parts and words, and the notes the user kept from them
/// (ADR-588, `v16_recordings`). The row is written before the audio exists. Every write is read
/// back inside the same transaction and fails, rolling back, unless it shows; the app deletes a
/// part file or tells the user "saved" only after this returned.
public final class SQLiteRecordingRepository: RecordingRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    // MARK: - The recording being made

    public func begin(id: UUID, origin: CaptureOrigin, languageCode: String, startedAt: Date) async throws -> Recording {
        let started = DoddyDatabase.truncatedToMilliseconds(startedAt)
        return try await dbQueue.write { db in
            guard try Self.fetch(id, db) == nil else { throw RecordingStoreError.alreadyExists }
            try db.execute(
                sql: """
                    INSERT INTO recordings (id, title, kind, origin, phase, language, started_at_ms, duration_ms, transcription, gaps_json)
                    VALUES (?, '', ?, ?, ?, ?, ?, 0, ?, '[]')
                    """,
                arguments: [id.uuidString, RecordingKind.other.rawValue, origin.rawValue, RecordingPhase.recording.rawValue,
                            languageCode, DoddyDatabase.milliseconds(started), TranscriptionStatus.notStarted.rawValue])
            let expected = Recording(id: id, origin: origin, phase: .recording, languageCode: languageCode, startedAt: started)
            guard try Self.fetch(id, db) == expected else { throw RecordingStoreError.verificationFailed }
            return expected
        }
    }

    public func openPart(recordingID: UUID, index: Int, startOffsetMilliseconds: Int) async throws -> RecordingPart {
        try await dbQueue.write { db in
            guard let recording = try Self.fetch(recordingID, db) else { throw RecordingStoreError.notFound }
            guard recording.phase == .recording else { throw RecordingStoreError.badPart }
            let existing = try Self.parts(recordingID, db)
            if let last = existing.last, last.index == index, last.durationMilliseconds == nil, last.startOffsetMilliseconds == startOffsetMilliseconds {
                return last
            }
            // The next part, after a closed one, starting where the closed ones end.
            guard index == (existing.last?.index ?? 0) + 1, existing.allSatisfy({ $0.durationMilliseconds != nil }) else {
                throw RecordingStoreError.badPart
            }
            let closed = existing.reduce(0) { $0 + ($1.durationMilliseconds ?? 0) }
            guard startOffsetMilliseconds == closed else { throw RecordingStoreError.badPart }
            let part = RecordingPart(recordingID: recordingID, index: index, fileName: RecordingPart.fileName(index: index),
                                     startOffsetMilliseconds: startOffsetMilliseconds)
            try db.execute(
                sql: "INSERT INTO recording_parts (recording_id, idx, file_name, start_offset_ms) VALUES (?, ?, ?, ?)",
                arguments: [recordingID.uuidString, index, part.fileName, startOffsetMilliseconds])
            guard try Self.parts(recordingID, db).last == part else { throw RecordingStoreError.verificationFailed }
            return part
        }
    }

    public func closePart(recordingID: UUID, index: Int, durationMilliseconds: Int) async throws {
        guard durationMilliseconds >= 0 else { throw RecordingStoreError.badDuration }
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recording_parts SET duration_ms = ? WHERE recording_id = ? AND idx = ? AND duration_ms IS NULL",
                arguments: [durationMilliseconds, recordingID.uuidString, index])
            guard db.changesCount == 1 else { throw RecordingStoreError.badPart }
            guard try Self.parts(recordingID, db).first(where: { $0.index == index })?.durationMilliseconds == durationMilliseconds else {
                throw RecordingStoreError.verificationFailed
            }
        }
    }

    public func checkpoint(recordingID: UUID, gaps: [CaptureGap]) async throws {
        let json = try Self.encode(gaps)
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE recordings SET gaps_json = ? WHERE id = ? AND phase = ?",
                           arguments: [json, recordingID.uuidString, RecordingPhase.recording.rawValue])
            guard db.changesCount == 1 else { throw RecordingStoreError.notFound }
        }
    }

    public func finish(recordingID: UUID, phase: RecordingPhase, endedAt: Date, endReason: CaptureEndReason,
                       parts counted: [ClosedPart], gaps: [CaptureGap]) async throws -> FinishedRecording {
        guard phase == .saved || phase == .recovered else { throw RecordingStoreError.badPart }
        guard counted.allSatisfy({ $0.durationMilliseconds >= 0 }) else { throw RecordingStoreError.badDuration }
        let ordered = counted.sorted { $0.index < $1.index }
        let json = try Self.encode(gaps)
        return try await dbQueue.write { db in
            guard let recording = try Self.fetch(recordingID, db) else { throw RecordingStoreError.notFound }
            guard recording.phase == .recording else { throw RecordingStoreError.notFinished }
            let stored = try Self.parts(recordingID, db)
            guard Set(ordered.map(\.index)).isSubset(of: Set(stored.map(\.index))), Set(ordered.map(\.index)).count == ordered.count else {
                throw RecordingStoreError.badPart
            }
            let keep = Set(ordered.map(\.index))
            let removed = stored.filter { !keep.contains($0.index) }
            for part in removed {
                try db.execute(sql: "DELETE FROM recording_parts WHERE recording_id = ? AND idx = ?", arguments: [recordingID.uuidString, part.index])
            }
            // Parts are laid end to end again, so a dropped one leaves no hole on the timeline.
            var offset = 0
            for part in ordered {
                try db.execute(sql: "UPDATE recording_parts SET duration_ms = ?, start_offset_ms = ? WHERE recording_id = ? AND idx = ?",
                               arguments: [part.durationMilliseconds, offset, recordingID.uuidString, part.index])
                offset += part.durationMilliseconds
            }
            let ended = max(DoddyDatabase.truncatedToMilliseconds(endedAt), recording.startedAt)
            try db.execute(
                sql: """
                    UPDATE recordings SET phase = ?, ended_at_ms = ?, duration_ms = ?, end_reason = ?, gaps_json = ?
                    WHERE id = ? AND phase = ?
                    """,
                arguments: [phase.rawValue, DoddyDatabase.milliseconds(ended), offset, endReason.rawValue, json,
                            recordingID.uuidString, RecordingPhase.recording.rawValue])
            guard db.changesCount == 1, let after = try Self.fetch(recordingID, db),
                  after.phase == phase, after.durationMilliseconds == offset, after.endReason == endReason, after.gaps == gaps,
                  try Self.parts(recordingID, db).map({ $0.durationMilliseconds }) == ordered.map({ Optional($0.durationMilliseconds) })
            else { throw RecordingStoreError.verificationFailed }
            return FinishedRecording(recording: after, removedFileNames: removed.map(\.fileName))
        }
    }

    public func markLost(recordingID: UUID, endedAt: Date) async throws {
        try await dbQueue.write { db in
            guard let recording = try Self.fetch(recordingID, db) else { throw RecordingStoreError.notFound }
            guard recording.phase == .recording else { throw RecordingStoreError.notFinished }
            let ended = max(DoddyDatabase.truncatedToMilliseconds(endedAt), recording.startedAt)
            try db.execute(sql: "UPDATE recordings SET phase = ?, ended_at_ms = ?, duration_ms = 0 WHERE id = ?",
                           arguments: [RecordingPhase.lost.rawValue, DoddyDatabase.milliseconds(ended), recordingID.uuidString])
            guard try Self.fetch(recordingID, db)?.phase == .lost else { throw RecordingStoreError.verificationFailed }
        }
    }

    public func discard(recordingID: UUID) async throws -> [String] {
        try await Self.remove(recordingID, in: dbQueue)
    }

    public func unfinished() async throws -> [UnfinishedRecordingRecord] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recordings WHERE phase = ? ORDER BY started_at_ms", arguments: [RecordingPhase.recording.rawValue])
                .compactMap(Self.recording(from:))
                .map { UnfinishedRecordingRecord(id: $0.id, startedAt: $0.startedAt, parts: try Self.parts($0.id, db), gaps: $0.gaps) }
        }
    }

    public func allIDs() async throws -> Set<UUID> {
        try await dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT id FROM recordings").compactMap(UUID.init(uuidString:)))
        }
    }

    // MARK: - The library

    public func recording(id: UUID) async throws -> Recording? {
        try await dbQueue.read { db in try Self.fetch(id, db) }
    }

    public func recordings(category: RecordingCategory, limit: Int, offset: Int) async throws -> [RecordingListItem] {
        guard limit > 0 else { return [] }
        return try await dbQueue.read { db in
            var sql = """
                SELECT r.*, (SELECT s.text FROM recording_segments s WHERE s.recording_id = r.id ORDER BY s.idx LIMIT 1) AS preview
                FROM recordings r
                """
            var arguments: [any DatabaseValueConvertible] = []
            if let kinds = category.kinds {
                sql += " WHERE r.kind IN (\(kinds.map { _ in "?" }.joined(separator: ", ")))"
                arguments += kinds.map(\.rawValue)
            }
            sql += " ORDER BY r.started_at_ms DESC, r.rowid DESC LIMIT ? OFFSET ?"
            arguments += [limit, max(0, offset)]
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).compactMap { row in
                Self.recording(from: row).map { RecordingListItem(recording: $0, preview: Self.preview(row["preview"])) }
            }
        }
    }

    public func parts(recordingID: UUID) async throws -> [RecordingPart] {
        try await dbQueue.read { db in try Self.parts(recordingID, db) }
    }

    public func rename(id: UUID, title: String) async throws -> Recording {
        let cleaned = RecordingTitle.clean(title)
        return try await dbQueue.write { db in
            try db.execute(sql: "UPDATE recordings SET title = ? WHERE id = ?", arguments: [cleaned, id.uuidString])
            guard db.changesCount == 1 else { throw RecordingStoreError.notFound }
            guard let after = try Self.fetch(id, db), after.title == cleaned else { throw RecordingStoreError.verificationFailed }
            return after
        }
    }

    public func setKind(id: UUID, kind: RecordingKind) async throws -> Recording {
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE recordings SET kind = ? WHERE id = ?", arguments: [kind.rawValue, id.uuidString])
            guard db.changesCount == 1 else { throw RecordingStoreError.notFound }
            guard let after = try Self.fetch(id, db), after.kind == kind else { throw RecordingStoreError.verificationFailed }
            return after
        }
    }

    public func setLanguage(id: UUID, languageCode: String) async throws -> Recording {
        let code = languageCode.trimmingCharacters(in: .whitespaces)
        guard (2...35).contains(code.count), code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { throw RecordingStoreError.badTranscript }
        return try await dbQueue.write { db in
            try db.execute(sql: "UPDATE recordings SET language = ? WHERE id = ?", arguments: [code, id.uuidString])
            guard db.changesCount == 1 else { throw RecordingStoreError.notFound }
            guard let after = try Self.fetch(id, db), after.languageCode == code else { throw RecordingStoreError.verificationFailed }
            return after
        }
    }

    public func delete(id: UUID) async throws -> [String] {
        try await Self.remove(id, in: dbQueue)
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM recordings")
            try Self.compactSearchIndex(db)
            for table in ["recordings", "recording_parts", "recording_segments"] {
                guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") == 0 else { throw RecordingStoreError.verificationFailed }
            }
        }
    }

    // MARK: - Words

    public func setTranscriptionStatus(id: UUID, _ status: TranscriptionStatus) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE recordings SET transcription = ? WHERE id = ?", arguments: [status.rawValue, id.uuidString])
            guard db.changesCount == 1 else { throw RecordingStoreError.notFound }
            guard try Self.fetch(id, db)?.transcription == status else { throw RecordingStoreError.verificationFailed }
        }
    }

    public func saveTranscript(recordingID: UUID, segments: [TranscriptSegment], status: TranscriptionStatus) async throws {
        guard segments.map(\.index) == Array(0..<segments.count) else { throw RecordingStoreError.badTranscript }
        guard segments.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.endMilliseconds >= $0.startMilliseconds && $0.startMilliseconds >= 0 })
        else { throw RecordingStoreError.badTranscript }
        // "Done" with no words is not done: that is "no speech".
        guard status != .done || !segments.isEmpty else { throw RecordingStoreError.badTranscript }
        try await dbQueue.write { db in
            guard let recording = try Self.fetch(recordingID, db) else { throw RecordingStoreError.notFound }
            guard recording.phase == .saved || recording.phase == .recovered else { throw RecordingStoreError.notFinished }
            try db.execute(sql: "DELETE FROM recording_segments WHERE recording_id = ?", arguments: [recordingID.uuidString])
            for segment in segments {
                try db.execute(
                    sql: """
                        INSERT INTO recording_segments (recording_id, idx, start_ms, end_ms, text, original_text, confidence, search_text)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [recordingID.uuidString, segment.index, segment.startMilliseconds, segment.endMilliseconds,
                                segment.text, segment.originalText, segment.confidence, SearchFolding.fold(segment.text)])
            }
            try db.execute(sql: "UPDATE recordings SET transcription = ? WHERE id = ?", arguments: [status.rawValue, recordingID.uuidString])
            try Self.compactSearchIndex(db)
            let back = try Self.segments(recordingID, offset: 0, limit: Int.max, db)
            guard back.count == segments.count, TranscriptFormat.fingerprint(back) == TranscriptFormat.fingerprint(segments),
                  try Self.fetch(recordingID, db)?.transcription == status else { throw RecordingStoreError.verificationFailed }
        }
    }

    public func segments(recordingID: UUID, offset: Int, limit: Int) async throws -> [TranscriptSegment] {
        guard limit > 0 else { return [] }
        return try await dbQueue.read { db in try Self.segments(recordingID, offset: max(0, offset), limit: limit, db) }
    }

    public func segmentCount(recordingID: UUID) async throws -> Int {
        try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recording_segments WHERE recording_id = ?", arguments: [recordingID.uuidString]) ?? 0
        }
    }

    public func segmentIndex(recordingID: UUID, atMilliseconds: Int) async throws -> Int? {
        try await dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT idx FROM recording_segments WHERE recording_id = ? AND start_ms <= ?
                    ORDER BY start_ms DESC, idx DESC LIMIT 1
                    """,
                arguments: [recordingID.uuidString, max(0, atMilliseconds)])
        }
    }

    public func editSegment(recordingID: UUID, index: Int, text: String) async throws -> TranscriptSegment {
        guard let cleaned = TranscriptEdit.cleaned(text) else { throw RecordingStoreError.badTranscript }
        return try await dbQueue.write { db in
            try db.execute(sql: "UPDATE recording_segments SET text = ?, search_text = ? WHERE recording_id = ? AND idx = ?",
                           arguments: [cleaned, SearchFolding.fold(cleaned), recordingID.uuidString, index])
            guard db.changesCount == 1 else { throw RecordingStoreError.notFound }
            try Self.compactSearchIndex(db)
            guard let after = try Self.segments(recordingID, offset: index, limit: 1, db).first, after.index == index, after.text == cleaned else {
                throw RecordingStoreError.verificationFailed
            }
            return after
        }
    }

    public func search(_ query: String, in recordingID: UUID?, limit: Int) async throws -> [RecordingSearchHit] {
        guard limit > 0, let pattern = RecordingSearch.pattern(for: query) else { return [] }
        return try await dbQueue.read { db in
            var sql = """
                SELECT recording_segments.recording_id, recording_segments.idx, recording_segments.start_ms, recording_segments.text
                FROM recording_segments_fts
                JOIN recording_segments ON recording_segments.rowid = recording_segments_fts.rowid
                WHERE recording_segments_fts MATCH ?
                """
            var arguments: [any DatabaseValueConvertible] = [pattern]
            if let recordingID {
                sql += " AND recording_segments.recording_id = ?"
                arguments.append(recordingID.uuidString)
            }
            sql += " ORDER BY bm25(recording_segments_fts) LIMIT ?"
            arguments.append(limit)
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).compactMap { row in
                guard let id = UUID(uuidString: row["recording_id"]) else { return nil }
                return RecordingSearchHit(recordingID: id, segmentIndex: row["idx"], startMilliseconds: row["start_ms"], text: row["text"])
            }
        }
    }

    // MARK: - Notes the user kept

    public func linkMemory(memoryID: UUID, recordingID: UUID, atMilliseconds: Int, recordingTitle: String, linkedAt: Date) async throws {
        let title = RecordingTitle.clean(recordingTitle)
        let linked = DoddyDatabase.truncatedToMilliseconds(linkedAt)
        try await dbQueue.write { db in
            guard try Self.fetch(recordingID, db) != nil else { throw RecordingStoreError.notFound }
            try db.execute(
                sql: """
                    INSERT INTO recording_memories (memory_id, recording_id, at_ms, recording_title, linked_at_ms) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(memory_id) DO UPDATE SET recording_id = excluded.recording_id, at_ms = excluded.at_ms,
                        recording_title = excluded.recording_title, linked_at_ms = excluded.linked_at_ms
                    """,
                arguments: [memoryID.uuidString, recordingID.uuidString, max(0, atMilliseconds), title, DoddyDatabase.milliseconds(linked)])
            guard try Self.link(memoryID, db) == RecordingMemoryLink(memoryID: memoryID, recordingID: recordingID, atMilliseconds: max(0, atMilliseconds),
                                                                     recordingTitle: title, linkedAt: linked) else {
                throw RecordingStoreError.verificationFailed
            }
        }
    }

    public func memoryLinks(forRecording recordingID: UUID) async throws -> [RecordingMemoryLink] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recording_memories WHERE recording_id = ? ORDER BY at_ms, linked_at_ms", arguments: [recordingID.uuidString])
                .compactMap(Self.link(from:))
        }
    }

    public func provenance(forMemory memoryID: UUID) async throws -> RecordingMemoryLink? {
        try await dbQueue.read { db in try Self.link(memoryID, db) }
    }

    // MARK: - Rows

    private static func remove(_ id: UUID, in queue: DatabaseQueue) async throws -> [String] {
        try await queue.write { db in
            guard try fetch(id, db) != nil else { return [] }
            let files = try parts(id, db).map(\.fileName)
            try db.execute(sql: "DELETE FROM recordings WHERE id = ?", arguments: [id.uuidString])
            try compactSearchIndex(db)
            guard try fetch(id, db) == nil,
                  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recording_segments WHERE recording_id = ?", arguments: [id.uuidString]) == 0,
                  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recording_parts WHERE recording_id = ?", arguments: [id.uuidString]) == 0
            else { throw RecordingStoreError.verificationFailed }
            return files
        }
    }

    /// `secure_delete` overwrites a deleted row but not the words the full-text index keeps of it:
    /// FTS5 records a delete as new index entries and leaves the old ones until segments merge
    /// (measured: the text was still in the file after the delete). Merging them now, in the same
    /// transaction, is what makes a deleted or corrected word actually leave the file.
    private static func compactSearchIndex(_ db: Database) throws {
        try db.execute(sql: "INSERT INTO recording_segments_fts(recording_segments_fts) VALUES('optimize')")
    }

    private static func fetch(_ id: UUID, _ db: Database) throws -> Recording? {
        try Row.fetchOne(db, sql: "SELECT * FROM recordings WHERE id = ?", arguments: [id.uuidString]).flatMap(recording(from:))
    }

    private static func recording(from row: Row) -> Recording? {
        guard let id = UUID(uuidString: row["id"]),
              let kind = RecordingKind(rawValue: row["kind"]), let origin = CaptureOrigin(rawValue: row["origin"]),
              let phase = RecordingPhase(rawValue: row["phase"]), let transcription = TranscriptionStatus(rawValue: row["transcription"])
        else { return nil }
        let ended: Int64? = row["ended_at_ms"]
        let reason: String? = row["end_reason"]
        let gapsJSON: String = row["gaps_json"]
        return Recording(
            id: id, title: row["title"], kind: kind, origin: origin, phase: phase, languageCode: row["language"],
            startedAt: DoddyDatabase.date(milliseconds: row["started_at_ms"]), endedAt: ended.map(DoddyDatabase.date(milliseconds:)),
            durationMilliseconds: row["duration_ms"], endReason: reason.flatMap(CaptureEndReason.init(rawValue:)),
            transcription: transcription, gaps: (try? JSONDecoder().decode([CaptureGap].self, from: Data(gapsJSON.utf8))) ?? [])
    }

    private static func parts(_ recordingID: UUID, _ db: Database) throws -> [RecordingPart] {
        try Row.fetchAll(db, sql: "SELECT * FROM recording_parts WHERE recording_id = ? ORDER BY idx", arguments: [recordingID.uuidString]).map { row in
            RecordingPart(recordingID: recordingID, index: row["idx"], fileName: row["file_name"],
                          startOffsetMilliseconds: row["start_offset_ms"], durationMilliseconds: row["duration_ms"])
        }
    }

    private static func segments(_ recordingID: UUID, offset: Int, limit: Int, _ db: Database) throws -> [TranscriptSegment] {
        try Row.fetchAll(
            db, sql: "SELECT * FROM recording_segments WHERE recording_id = ? AND idx >= ? ORDER BY idx LIMIT ?",
            arguments: [recordingID.uuidString, offset, limit]
        ).map { row in
            TranscriptSegment(index: row["idx"], startMilliseconds: row["start_ms"], endMilliseconds: row["end_ms"], text: row["text"],
                              originalText: row["original_text"], confidence: row["confidence"])
        }
    }

    private static func link(_ memoryID: UUID, _ db: Database) throws -> RecordingMemoryLink? {
        try Row.fetchOne(db, sql: "SELECT * FROM recording_memories WHERE memory_id = ?", arguments: [memoryID.uuidString]).flatMap(link(from:))
    }

    private static func link(from row: Row) -> RecordingMemoryLink? {
        guard let memory = UUID(uuidString: row["memory_id"]) else { return nil }
        let recording: String? = row["recording_id"]
        return RecordingMemoryLink(
            memoryID: memory, recordingID: recording.flatMap(UUID.init(uuidString:)), atMilliseconds: row["at_ms"],
            recordingTitle: row["recording_title"], linkedAt: DoddyDatabase.date(milliseconds: row["linked_at_ms"]))
    }

    /// The first words of a transcript, cut at a word, for a list row.
    private static func preview(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard text.count > 140 else { return text }
        let cut = String(text.prefix(140))
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut) + "…"
    }

    private static func encode(_ gaps: [CaptureGap]) throws -> String {
        String(decoding: try JSONEncoder().encode(gaps), as: UTF8.self)
    }
}
