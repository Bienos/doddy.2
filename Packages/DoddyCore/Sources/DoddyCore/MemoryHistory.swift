import Foundation

/// One correction of a saved note, kept forever with the note (ADR-252). The original wording
/// stays in the note itself (`MemoryRecord.rawText`); each correction adds one of these, so every
/// wording the note ever had can be shown. Deleted with the note.
public struct MemoryCorrection: Equatable, Sendable {
    public let memoryID: UUID
    /// 1 for the first correction, then 2, 3…
    public let number: Int
    /// The wording the note had from this correction on.
    public let text: String
    public let correctedAt: Date

    public init(memoryID: UUID, number: Int, text: String, correctedAt: Date) throws(MemoryValidationError) {
        try MemoryTextValidator.validate(text)
        guard number >= 1 else { throw .invalidCorrectionNumber(number) }
        self.memoryID = memoryID
        self.number = number
        self.text = text
        self.correctedAt = correctedAt
    }
}

extension MemoryCorrection: Codable {
    private enum CodingKeys: String, CodingKey {
        case memoryId, number, text, correctedAtMs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                memoryID: try c.decode(UUID.self, forKey: .memoryId),
                number: try c.decode(Int.self, forKey: .number),
                text: try c.decode(String.self, forKey: .text),
                correctedAt: Date(timeIntervalSince1970: Double(try c.decode(Int64.self, forKey: .correctedAtMs)) / 1000))
        } catch let error as MemoryValidationError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid correction: \(error)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(memoryID, forKey: .memoryId)
        try c.encode(number, forKey: .number)
        try c.encode(text, forKey: .text)
        try c.encode(EpochMilliseconds.rounded(correctedAt), forKey: .correctedAtMs)
    }
}

/// One wording a note has had, oldest first.
public struct MemoryVersion: Equatable, Sendable {
    /// 1 is the original.
    public let number: Int
    public let text: String
    /// When it was saved or corrected; `nil` only for an original without a known date.
    public let savedAt: Date?
    public let isOriginal: Bool
    public let isCurrent: Bool
}

/// Every wording of a note, from what was stored (ADR-252).
public struct MemoryHistory: Equatable, Sendable {
    public let versions: [MemoryVersion]
    /// False when corrections were made but not every in-between wording is known: the note was
    /// corrected before Doddy kept history, or came from an export without it. Then only the
    /// original and the current wording are shown, and the screen says so.
    public let isComplete: Bool

    public init(record: MemoryRecord, corrections: [MemoryCorrection]) {
        let original = MemoryVersion(
            number: 1, text: record.rawText, savedAt: record.capturedAt, isOriginal: true, isCurrent: !record.userEdited)
        guard record.userEdited else {
            versions = [original]
            isComplete = corrections.isEmpty
            return
        }
        if Self.consistent(record, corrections) {
            let sorted = corrections.sorted { $0.number < $1.number }
            versions = [original] + sorted.map {
                MemoryVersion(number: $0.number + 1, text: $0.text, savedAt: $0.correctedAt, isOriginal: false,
                              isCurrent: $0.number == sorted.count)
            }
            isComplete = true
        } else {
            versions = [original, MemoryVersion(number: 2, text: record.currentText, savedAt: record.updatedAt,
                                                isOriginal: false, isCurrent: true)]
            isComplete = false
        }
    }

    /// The corrections belong to this note, are numbered 1…n without gaps, and the last one is
    /// the note's current wording. Anything else is not trusted as its history.
    public static func consistent(_ record: MemoryRecord, _ corrections: [MemoryCorrection]) -> Bool {
        let sorted = corrections.sorted { $0.number < $1.number }
        return !sorted.isEmpty
            && sorted.allSatisfy { $0.memoryID == record.id }
            && sorted.map(\.number) == Array(1...sorted.count)
            && sorted.last?.text == record.currentText
    }

    /// Earlier wordings, newest first, for "Earlier versions" on the note.
    public var earlier: [MemoryVersion] { versions.filter { !$0.isCurrent }.reversed() }
}
