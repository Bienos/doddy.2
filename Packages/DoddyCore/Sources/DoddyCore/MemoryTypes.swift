import Foundation

/// Where a memory came from. Raw values match `schemas/memory.schema.json`.
public enum MemorySource: String, Codable, CaseIterable, Sendable {
    case explicitText = "explicit_text"
    case explicitVoice = "explicit_voice"
    case sharedContent = "shared_content"
    case importedLegacyUnknown = "imported_legacy_unknown"
    /// Brought in from a Google Keep export or a text file the user picked and reviewed
    /// (ADR-231). Dated when the file says when the note was made, otherwise "date unknown".
    case importedFile = "imported_file"
    /// A note Doddy wrote, on a phone call or while answering a text, that the user then saved
    /// with a tap (ADR-494, owner decision 2026-10-18). Doddy's words, the user's confirmation.
    case notedByDoddy = "noted_by_doddy"
    case sampleFixture = "sample_fixture"

    /// Sources a user can create through an explicit capture action.
    public var isExplicitCapture: Bool {
        switch self {
        // A note Doddy wrote counts: it becomes a memory only through the user's Save tap.
        case .explicitText, .explicitVoice, .sharedContent, .notedByDoddy: true
        case .importedLegacyUnknown, .importedFile, .sampleFixture: false
        }
    }

    /// Fixtures are never returned for personal recall (docs/architecture/MEMORY_AND_DATA.md).
    public var isEligibleForPersonalRecall: Bool { self != .sampleFixture }
}

/// Raw values match `schemas/memory.schema.json`.
public enum MemoryCategory: String, Codable, CaseIterable, Sendable {
    case fact, preference, commitment, recommendation, decision, item, place, intention, other
    /// A list (ADR-216): the text is its name; the items are in `list_items`. Never offered as a
    /// note type, and never returned by recall.
    case list

    /// The types a note can be filed under (everything but `list`).
    public static var noteCategories: [MemoryCategory] { allCases.filter { $0 != .list } }
}

public enum MemoryLimits {
    /// Maximum length of accepted text, counted in Unicode scalars to match the
    /// JSON Schema `maxLength` (which counts code points).
    public static let maxTextLength = 5_000
}

public enum MemoryValidationError: Error, Equatable, Sendable {
    case empty
    case tooLong(length: Int, maximum: Int)
    case sourceNotCapturable(MemorySource)
    case missingCaptureDate(MemorySource)
    case unexpectedCaptureDate(MemorySource)
    /// A stored correction must be numbered from 1 (ADR-252).
    case invalidCorrectionNumber(Int)
}

public enum MemoryTextValidator {
    /// Validates without altering the text: nothing is trimmed, truncated or normalised.
    /// Whitespace-only text counts as empty. Oversized text is rejected, never cut down.
    public static func validate(_ text: String) throws(MemoryValidationError) {
        if text.allSatisfy(\.isWhitespace) { throw .empty }
        let length = text.unicodeScalars.count
        if length > MemoryLimits.maxTextLength {
            throw .tooLong(length: length, maximum: MemoryLimits.maxTextLength)
        }
    }
}

/// A validated request to save a new memory. The accepted text is kept byte-for-byte.
public struct NewMemory: Equatable, Sendable {
    public let text: String
    public let category: MemoryCategory
    public let source: MemorySource
    public let capturedAt: Date

    public init(
        text: String,
        category: MemoryCategory = .other,
        source: MemorySource = .explicitText,
        capturedAt: Date
    ) throws(MemoryValidationError) {
        try MemoryTextValidator.validate(text)
        guard source.isExplicitCapture else { throw .sourceNotCapturable(source) }
        self.text = text
        self.category = category
        self.source = source
        self.capturedAt = capturedAt
    }
}

/// A stored memory. `rawText` is the exact accepted text and never changes;
/// `currentText` is the user's correction. Field names and JSON keys follow
/// `schemas/memory.schema.json` (tombstones are not modelled; deletion is a purge).
public struct MemoryRecord: Hashable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public let id: UUID
    public let rawText: String
    public let currentText: String
    public let source: MemorySource
    public let category: MemoryCategory
    /// `nil` only for `imported_legacy_unknown`: an unknown date is shown as unavailable,
    /// never replaced by the import time.
    public let capturedAt: Date?
    public let updatedAt: Date?
    public let userEdited: Bool

    public init(
        id: UUID,
        rawText: String,
        currentText: String? = nil,
        source: MemorySource,
        category: MemoryCategory = .other,
        capturedAt: Date?,
        updatedAt: Date? = nil,
        userEdited: Bool = false
    ) throws(MemoryValidationError) {
        try MemoryTextValidator.validate(rawText)
        let current = currentText ?? rawText
        try MemoryTextValidator.validate(current)
        switch (source, capturedAt) {
        case (.importedLegacyUnknown, .some): throw .unexpectedCaptureDate(source)
        case (.importedLegacyUnknown, .none), (.importedFile, _): break
        case (_, .none): throw .missingCaptureDate(source)
        case (_, .some): break
        }
        self.id = id
        self.rawText = rawText
        self.currentText = current
        self.source = source
        self.category = category
        self.capturedAt = capturedAt
        self.updatedAt = updatedAt
        self.userEdited = userEdited
    }

    /// Builds the record for a validated capture. The caller supplies the identifier so
    /// persistence adapters (and tests) control it.
    public init(id: UUID, capturing new: NewMemory) throws(MemoryValidationError) {
        try self.init(
            id: id, rawText: new.text, source: new.source,
            category: new.category, capturedAt: new.capturedAt)
    }

    /// Returns a copy of another type. The words, dates, source and "edited" state are untouched:
    /// choosing a type is filing the note, not correcting it (ADR-192).
    public func recategorized(to category: MemoryCategory) throws(MemoryValidationError) -> MemoryRecord {
        try MemoryRecord(
            id: id, rawText: rawText, currentText: currentText, source: source,
            category: category, capturedAt: capturedAt, updatedAt: updatedAt, userEdited: userEdited)
    }

    /// Returns a corrected copy. `rawText` and `capturedAt` are untouched.
    public func correcting(to newText: String, at date: Date) throws(MemoryValidationError) -> MemoryRecord {
        try MemoryRecord(
            id: id, rawText: rawText, currentText: newText, source: source,
            category: category, capturedAt: capturedAt, updatedAt: date, userEdited: true)
    }
}

extension MemoryRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, rawText, currentText, source, category
        case capturedAtMs, updatedAtMs, userEdited
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: c, debugDescription: "Unsupported schemaVersion \(version)")
        }
        func date(_ key: CodingKeys) throws -> Date? {
            try c.decodeIfPresent(Int64.self, forKey: key).map(EpochMilliseconds.date)
        }
        do {
            try self.init(
                id: try c.decode(UUID.self, forKey: .id),
                rawText: try c.decode(String.self, forKey: .rawText),
                currentText: try c.decode(String.self, forKey: .currentText),
                source: try c.decode(MemorySource.self, forKey: .source),
                category: try c.decode(MemoryCategory.self, forKey: .category),
                capturedAt: try date(.capturedAtMs),
                updatedAt: try date(.updatedAtMs),
                userEdited: try c.decode(Bool.self, forKey: .userEdited))
        } catch let error as MemoryValidationError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid memory record: \(error)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(rawText, forKey: .rawText)
        try c.encode(currentText, forKey: .currentText)
        try c.encode(source, forKey: .source)
        try c.encode(category, forKey: .category)
        try c.encode(capturedAt.map(EpochMilliseconds.rounded), forKey: .capturedAtMs)
        try c.encode(updatedAt.map(EpochMilliseconds.rounded), forKey: .updatedAtMs)
        try c.encode(userEdited, forKey: .userEdited)
    }
}

/// Dates as whole milliseconds since 1970: the one conversion files and the database share.
public enum EpochMilliseconds {
    /// To the nearest millisecond, for files. Exact inverse of `date(_:)`, so a date read from a
    /// file or the database is written back unchanged.
    public static func rounded(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Rounded down, as the database keeps a new time (it never moves later).
    public static func truncated(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    public static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
