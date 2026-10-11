import Foundation

// Voice memos (ADR-230). A note can carry one short recording, made in Doddy while writing the
// note. Its words are written out on this iPhone (Apple's Speech framework with on-device
// recognition required; if this iPhone can't do that for the language, nothing is written out
// and nothing is sent) and offered in the editor, where the user checks them before saving. The
// saved note's words are what they accepted, so search, Doddy and export work on them like any
// note. The recording stays on this iPhone, is never sent to ElevenLabs or a server, is not in
// exports, goes in the encrypted backup file only if the user includes it (ADR-234), and is
// deleted with its note.

public enum VoiceMemoLimits {
    /// Longest recording, in seconds. Recording stops by itself here.
    public static let maxSeconds = 300
    /// Shorter recordings are dropped as a mis-tap.
    public static let minMilliseconds = 500
    /// Written-out text longer than this is cut at a whole word and the user is told.
    public static let maxTranscriptCharacters = 3_000
}

/// The one recording a note carries. The file lives in the app's own folder under `fileName`.
public struct MemoryAudio: Equatable, Sendable {
    public let memoryID: UUID
    public let fileName: String
    public let durationMilliseconds: Int
    public let addedAt: Date

    public init(memoryID: UUID, fileName: String, durationMilliseconds: Int, addedAt: Date) {
        self.memoryID = memoryID
        self.fileName = fileName
        self.durationMilliseconds = durationMilliseconds
        self.addedAt = addedAt
    }

    /// File names are made by Doddy: the note's id and `.m4a`, nothing from outside.
    public static func fileName(for memoryID: UUID) -> String { "\(memoryID.uuidString.lowercased()).m4a" }

    public static func isValidFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".m4a") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    public static func isValidDuration(_ milliseconds: Int) -> Bool {
        milliseconds >= VoiceMemoLimits.minMilliseconds && milliseconds <= VoiceMemoLimits.maxSeconds * 1000 + 999
    }
}

public enum AudioError: Error, Equatable, Sendable {
    case noteNotFound
    case badFileName
    case badDuration
    /// The note has a recording already. Replacing one isn't offered: remove it first.
    case alreadyAttached
}

public protocol AudioRepository: Sendable {
    /// Links the recording to its note, replacing an earlier link; read back before success.
    func attach(_ audio: MemoryAudio) async throws -> MemoryAudio
    func audio(forMemory memoryID: UUID) async throws -> MemoryAudio?
    func allAudio() async throws -> [MemoryAudio]
    /// Returns the removed link, so the file can be deleted (or put back on Undo).
    @discardableResult
    func detach(memoryID: UUID) async throws -> MemoryAudio?
}

public struct UnavailableAudioRepository: AudioRepository {
    public init() {}
    public func attach(_ audio: MemoryAudio) async throws -> MemoryAudio { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func audio(forMemory memoryID: UUID) async throws -> MemoryAudio? { nil }
    public func allAudio() async throws -> [MemoryAudio] { [] }
    public func detach(memoryID: UUID) async throws -> MemoryAudio? { nil }
}

public enum VoiceMemoText {
    /// What the recognizer wrote out, trimmed and cut at the last whole word that fits. Nothing
    /// is reworded or corrected.
    public static func transcript(_ raw: String) -> RecognizedText.Result {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > VoiceMemoLimits.maxTranscriptCharacters else { return RecognizedText.Result(text: text, wasCut: false) }
        let head = text.prefix(VoiceMemoLimits.maxTranscriptCharacters)
        let cut = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        return RecognizedText.Result(text: cut.trimmingCharacters(in: .whitespacesAndNewlines), wasCut: true)
    }

    /// The editor text after writing out the recording again (in another language): the earlier
    /// written-out text is swapped for the new one where it still stands unchanged; otherwise the
    /// new text is added after the user's words.
    public static func replacing(_ earlier: String?, with new: String, in typed: String) -> String {
        if let earlier, !earlier.isEmpty, let range = typed.range(of: earlier) {
            var result = typed
            result.replaceSubrange(range, with: new)
            return result
        }
        return RecognizedText.adding(new, to: typed)
    }

    /// "0:42", "4:05".
    public static func duration(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds) / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
