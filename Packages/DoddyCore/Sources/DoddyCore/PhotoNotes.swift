import Foundation

// Photo notes (ADR-225). A note can carry one photo: a receipt, a parking spot, a label. The
// photo's text is read on this iPhone (Apple's Vision framework, no network) and offered in the
// editor, where the user checks it before saving; the saved note's words are what they accepted,
// so search, Doddy and export work on them like any note. The photo file stays on this iPhone,
// is never sent to ElevenLabs or a server, and is deleted with its note.

public enum PhotoLimits {
    /// Longest side after downscaling, in pixels. Enough to read a receipt, small on disk.
    public static let maxPixels = 2048
    /// A picked image larger than this is refused before it is decoded.
    public static let maxSourceBytes = 40 * 1024 * 1024
    /// Read text longer than this is cut at a line boundary and the user is told.
    public static let maxRecognizedCharacters = 3_000
}

/// The one photo a note carries. The file lives in the app's own folder under `fileName`.
public struct MemoryPhoto: Equatable, Sendable {
    public let memoryID: UUID
    public let fileName: String
    public let width: Int
    public let height: Int
    public let addedAt: Date

    public init(memoryID: UUID, fileName: String, width: Int, height: Int, addedAt: Date) {
        self.memoryID = memoryID
        self.fileName = fileName
        self.width = width
        self.height = height
        self.addedAt = addedAt
    }

    /// File names are made by Doddy: the note's id and `.jpg`, nothing from outside.
    public static func fileName(for memoryID: UUID) -> String { "\(memoryID.uuidString.lowercased()).jpg" }

    public static func isValidFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }
}

public enum PhotoError: Error, Equatable, Sendable {
    case noteNotFound
    case badFileName
    case badSize
    /// The note has a photo already. Replacing one isn't offered: remove it first.
    case alreadyAttached
}

public protocol PhotoRepository: Sendable {
    /// Links the photo file to its note, replacing an earlier photo; read back before success.
    func attach(_ photo: MemoryPhoto) async throws -> MemoryPhoto
    func photo(forMemory memoryID: UUID) async throws -> MemoryPhoto?
    func allPhotos() async throws -> [MemoryPhoto]
    /// Returns the removed link, so the file can be deleted (or put back on Undo).
    @discardableResult
    func detach(memoryID: UUID) async throws -> MemoryPhoto?
}

public struct UnavailablePhotoRepository: PhotoRepository {
    public init() {}
    public func attach(_ photo: MemoryPhoto) async throws -> MemoryPhoto { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func photo(forMemory memoryID: UUID) async throws -> MemoryPhoto? { nil }
    public func allPhotos() async throws -> [MemoryPhoto] { [] }
    public func detach(memoryID: UUID) async throws -> MemoryPhoto? { nil }
}

/// What Vision read, turned into text for the editor.
public enum RecognizedText {
    public struct Result: Equatable, Sendable {
        public let text: String
        /// True when the read text was longer than `PhotoLimits.maxRecognizedCharacters`.
        public let wasCut: Bool
    }

    /// Lines in reading order, trimmed, empty ones dropped, joined with newlines; cut at the last
    /// whole line that fits. Nothing is reworded or corrected.
    public static func join(_ lines: [String]) -> Result {
        var kept: [String] = []
        var count = 0
        var wasCut = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let added = trimmed.count + (kept.isEmpty ? 0 : 1)
            if count + added > PhotoLimits.maxRecognizedCharacters {
                wasCut = true
                break
            }
            kept.append(trimmed)
            count += added
        }
        return Result(text: kept.joined(separator: "\n"), wasCut: wasCut)
    }

    /// The editor text after adding what the photo says: the user's words first, then a blank
    /// line, then the read text. Adding the same read text twice changes nothing.
    public static func adding(_ recognized: String, to typed: String) -> String {
        let read = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !read.isEmpty, !typed.contains(read) else { return typed }
        let mine = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return mine.isEmpty ? read : typed.trimmingCharacters(in: .newlines) + "\n\n" + read
    }

    /// The pixel size after downscaling so the longer side is at most `PhotoLimits.maxPixels`.
    public static func scaledSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > PhotoLimits.maxPixels, longest > 0 else { return (width, height) }
        let scale = Double(PhotoLimits.maxPixels) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}
