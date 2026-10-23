import Foundation

// Where recordings live (ADR-588). The recording's row is written BEFORE the audio starts, so a
// kill leaves something to recover from; nothing is inferred from files alone. Every write is read
// back before it is reported as done, like the notes.

public enum RecordingStoreError: Error, Equatable, Sendable {
    case notFound
    case alreadyExists
    /// The recording is still being made (or was never finished), so this isn't allowed yet.
    case notFinished
    case badFileName
    /// A part must start where the parts before it end, and follow the one before it.
    case badPart
    case badDuration
    case badTranscript
    /// The write was done but reading it back did not show it, so it was rolled back.
    case verificationFailed
}

public struct RecordingListItem: Equatable, Sendable {
    public let recording: Recording
    /// The first words of the transcript, if there is one. Not a summary and not called one.
    public let preview: String?

    public init(recording: Recording, preview: String?) {
        self.recording = recording
        self.preview = preview
    }
}

public struct RecordingSearchHit: Equatable, Sendable {
    public let recordingID: UUID
    public let segmentIndex: Int
    public let startMilliseconds: Int
    public let text: String

    public init(recordingID: UUID, segmentIndex: Int, startMilliseconds: Int, text: String) {
        self.recordingID = recordingID
        self.segmentIndex = segmentIndex
        self.startMilliseconds = startMilliseconds
        self.text = text
    }
}

/// A recording the app has to look at after a kill: the row, and the parts it had written.
public struct UnfinishedRecordingRecord: Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let parts: [RecordingPart]
    public let gaps: [CaptureGap]

    public init(id: UUID, startedAt: Date, parts: [RecordingPart], gaps: [CaptureGap]) {
        self.id = id
        self.startedAt = startedAt
        self.parts = parts
        self.gaps = gaps
    }
}

public struct FinishedRecording: Equatable, Sendable {
    public let recording: Recording
    /// Part files whose rows were dropped because they could not be read; the app deletes them.
    public let removedFileNames: [String]

    public init(recording: Recording, removedFileNames: [String]) {
        self.recording = recording
        self.removedFileNames = removedFileNames
    }
}

/// A note the user chose to remember from a recording.
public struct RecordingMemoryLink: Equatable, Sendable {
    public let memoryID: UUID
    /// Nil once the recording is deleted. The note stays; it says where it came from.
    public let recordingID: UUID?
    public let atMilliseconds: Int
    public let recordingTitle: String
    public let linkedAt: Date

    public init(memoryID: UUID, recordingID: UUID?, atMilliseconds: Int, recordingTitle: String, linkedAt: Date) {
        self.memoryID = memoryID
        self.recordingID = recordingID
        self.atMilliseconds = atMilliseconds
        self.recordingTitle = recordingTitle
        self.linkedAt = linkedAt
    }
}

public protocol RecordingRepository: Sendable {
    // The recording being made.
    func begin(id: UUID, origin: CaptureOrigin, languageCode: String, startedAt: Date) async throws -> Recording
    /// Opening the part that is already open, at the same place, returns it: a start that failed
    /// leaves its row behind, and the next try must not be refused for it.
    func openPart(recordingID: UUID, index: Int, startOffsetMilliseconds: Int) async throws -> RecordingPart
    func closePart(recordingID: UUID, index: Int, durationMilliseconds: Int) async throws
    /// Saves the quiet stretches so far, so a kill does not lose where they were.
    func checkpoint(recordingID: UUID, gaps: [CaptureGap]) async throws
    /// Ends the recording. The parts listed are the ones that count; any other part row is removed.
    func finish(recordingID: UUID, phase: RecordingPhase, endedAt: Date, endReason: CaptureEndReason,
                parts: [ClosedPart], gaps: [CaptureGap]) async throws -> FinishedRecording
    /// A recording with nothing usable: the row stays, as `lost`, so the user is told.
    func markLost(recordingID: UUID, endedAt: Date) async throws
    /// Removes a recording that never held anything worth keeping. Returns its part file names.
    func discard(recordingID: UUID) async throws -> [String]
    func unfinished() async throws -> [UnfinishedRecordingRecord]
    /// Every recording's id, so folders that belong to none can be told apart.
    func allIDs() async throws -> Set<UUID>

    // The library.
    func recording(id: UUID) async throws -> Recording?
    func recordings(category: RecordingCategory, limit: Int, offset: Int) async throws -> [RecordingListItem]
    func parts(recordingID: UUID) async throws -> [RecordingPart]
    func rename(id: UUID, title: String) async throws -> Recording
    func setKind(id: UUID, kind: RecordingKind) async throws -> Recording
    /// The language the words are written out in (BCP-47). One per recording: to read a mixed-language
    /// recording in both, it is written out once per language.
    func setLanguage(id: UUID, languageCode: String) async throws -> Recording
    /// Deletes the recording, its words and their search index. Returns the part file names to delete.
    func delete(id: UUID) async throws -> [String]
    /// "Delete everything": every recording, its parts, words and search index, read back to be empty.
    /// The audio folder is the app's to remove.
    func deleteAll() async throws

    // Words.
    func setTranscriptionStatus(id: UUID, _ status: TranscriptionStatus) async throws
    /// Replaces all of a recording's lines in one step and reads them back. Lines must be numbered 0...n-1.
    func saveTranscript(recordingID: UUID, segments: [TranscriptSegment], status: TranscriptionStatus) async throws
    func segments(recordingID: UUID, offset: Int, limit: Int) async throws -> [TranscriptSegment]
    func segmentCount(recordingID: UUID) async throws -> Int
    /// The line being said at a time on the recording's own time.
    func segmentIndex(recordingID: UUID, atMilliseconds: Int) async throws -> Int?
    func editSegment(recordingID: UUID, index: Int, text: String) async throws -> TranscriptSegment
    /// Best match first. `recordingID` nil searches every recording.
    func search(_ query: String, in recordingID: UUID?, limit: Int) async throws -> [RecordingSearchHit]

    // Memory the user chose.
    func linkMemory(memoryID: UUID, recordingID: UUID, atMilliseconds: Int, recordingTitle: String, linkedAt: Date) async throws
    func memoryLinks(forRecording recordingID: UUID) async throws -> [RecordingMemoryLink]
    func provenance(forMemory memoryID: UUID) async throws -> RecordingMemoryLink?
}
