import Foundation

/// Why an export file can't be restored. Nothing is added in any of these cases.
public enum MemoryRestoreError: Error, Equatable, Sendable {
    case tooLarge(bytes: Int, maximum: Int)
    /// Not JSON, or JSON without Doddy's export envelope.
    case notADoddyExport
    /// Made by a newer Doddy whose format this build doesn't know.
    case newerFormat(Int)
    /// One note (1-based position in the file) is damaged or breaks the memory rules.
    case unreadableNote(position: Int)
    /// Two notes in the file share an id but differ, so the file can't be trusted as an export.
    case conflictingDuplicate(position: Int)
    /// One correction (1-based position in the file's corrections) is damaged (ADR-252).
    case unreadableCorrection(position: Int)
}

/// What a restore would do, worked out before anything is written (ADR-178).
public struct MemoryRestorePlan: Equatable, Sendable {
    /// Notes not on this iPhone yet, newest first. Added exactly as exported.
    public let toAdd: [MemoryRecord]
    /// Same id and same content as a note already here.
    public let alreadyHere: Int
    /// Same id but different content (for example corrected since the export): the note on
    /// this iPhone is kept and the file's version is not added.
    public let keptOnPhone: Int
    /// Sample notes are never restored.
    public let skippedSamples: Int
    public let exportedAt: Date?
    /// The history of the notes in `toAdd`, from the file (ADR-252). A note whose corrections
    /// don't form its whole history is added without them.
    public let corrections: [MemoryCorrection]

    public var isEmpty: Bool { toAdd.isEmpty }
}

/// Reads a `MemoryExport.json` file back. Strict: a file with any damaged note is refused as a
/// whole, so a restore never adds part of a file or a note that differs from what was exported.
public enum MemoryRestore {
    public static let maxFileBytes = 20 * 1024 * 1024

    private struct Envelope: Decodable {
        let formatVersion: Int
        let exportedAtMs: Int64?
        let memories: [Slot]
        /// Absent in exports made before ADR-252.
        let corrections: [CorrectionSlot]?
    }

    private struct CorrectionSlot: Decodable {
        let correction: MemoryCorrection?
        init(from decoder: any Decoder) throws {
            correction = try? MemoryCorrection(from: decoder)
        }
    }

    /// Keeps going past a bad note so its position can be reported.
    private struct Slot: Decodable {
        let record: MemoryRecord?
        init(from decoder: any Decoder) throws {
            record = try? MemoryRecord(from: decoder)
        }
    }

    private struct VersionOnly: Decodable {
        let formatVersion: Int
    }

    /// `maxBytes` is larger only for the export inside an encrypted backup, which is already
    /// limited (and authenticated) as a whole, so every backup Doddy makes can be restored.
    public static func read(_ data: Data, maxBytes: Int = maxFileBytes) throws(MemoryRestoreError)
        -> (records: [MemoryRecord], corrections: [MemoryCorrection], exportedAt: Date?) {
        guard data.count <= maxBytes else { throw .tooLarge(bytes: data.count, maximum: maxBytes) }
        let decoder = JSONDecoder()
        guard let version = try? decoder.decode(VersionOnly.self, from: data).formatVersion else {
            throw .notADoddyExport
        }
        guard version <= MemoryExport.formatVersion else { throw .newerFormat(version) }
        guard version >= 1, let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw .notADoddyExport
        }
        var records: [MemoryRecord] = []
        var byID: [UUID: MemoryRecord] = [:]
        for (index, slot) in envelope.memories.enumerated() {
            guard let record = slot.record else { throw .unreadableNote(position: index + 1) }
            if let earlier = byID[record.id] {
                guard earlier == record else { throw .conflictingDuplicate(position: index + 1) }
                continue
            }
            byID[record.id] = record
            records.append(record)
        }
        var corrections: [MemoryCorrection] = []
        for (index, slot) in (envelope.corrections ?? []).enumerated() {
            guard let correction = slot.correction else { throw .unreadableCorrection(position: index + 1) }
            corrections.append(correction)
        }
        return (records, corrections, envelope.exportedAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) })
    }

    /// The list items in the file (ADR-216); empty for files without lists. A damaged item list
    /// is refused, so no list comes back half-filled.
    public static func listItems(_ data: Data, maxBytes: Int = maxFileBytes) throws(MemoryRestoreError) -> [ListItem] {
        struct Items: Decodable { let listItems: [ListItem]? }
        guard data.count <= maxBytes else { throw .tooLarge(bytes: data.count, maximum: maxBytes) }
        guard let items = try? JSONDecoder().decode(Items.self, from: data) else { throw .notADoddyExport }
        return (items.listItems ?? []).filter { ListText.cleaned($0.text) != nil && $0.text.count <= ListLimits.itemLength }
    }

    public static func plan(
        _ incoming: [MemoryRecord], corrections: [MemoryCorrection] = [], existing: [MemoryRecord], exportedAt: Date?
    ) -> MemoryRestorePlan {
        let here = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var toAdd: [MemoryRecord] = []
        var alreadyHere = 0, keptOnPhone = 0, samples = 0
        for record in incoming {
            if record.source == .sampleFixture {
                samples += 1
            } else if let current = here[record.id] {
                if current == record { alreadyHere += 1 } else { keptOnPhone += 1 }
            } else {
                toAdd.append(record)
            }
        }
        toAdd.sort { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
        let adding = Set(toAdd.map(\.id))
        return MemoryRestorePlan(
            toAdd: toAdd, alreadyHere: alreadyHere, keptOnPhone: keptOnPhone,
            skippedSamples: samples, exportedAt: exportedAt,
            corrections: corrections.filter { adding.contains($0.memoryID) })
    }
}
