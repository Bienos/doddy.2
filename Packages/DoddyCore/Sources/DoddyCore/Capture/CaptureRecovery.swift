import Foundation

// After Doddy was closed in the middle of a recording (a crash, a force-quit, a dead battery),
// the database still has the recording's row, because it is written before the audio starts. This
// decides what to keep. It never invents audio: a part is kept only if the file can be read now,
// and its length is the shorter of what the recorder said and what reading the file shows.

public struct UnfinishedPart: Equatable, Sendable {
    public let index: Int
    public let fileName: String
    /// What the recorder said when it closed this part. Nil if it never got to.
    public let recordedMilliseconds: Int?
    /// What reading the file shows now. Nil if the file is missing or cannot be read.
    public let probedMilliseconds: Int?
    public let modifiedAt: Date?

    public init(index: Int, fileName: String, recordedMilliseconds: Int?, probedMilliseconds: Int?, modifiedAt: Date? = nil) {
        self.index = index
        self.fileName = fileName
        self.recordedMilliseconds = recordedMilliseconds
        self.probedMilliseconds = probedMilliseconds
        self.modifiedAt = modifiedAt
    }
}

public struct UnfinishedRecording: Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let parts: [UnfinishedPart]
    public let gaps: [CaptureGap]

    public init(id: UUID, startedAt: Date, parts: [UnfinishedPart], gaps: [CaptureGap] = []) {
        self.id = id
        self.startedAt = startedAt
        self.parts = parts
        self.gaps = gaps
    }
}

public struct RecoveredRecording: Equatable, Sendable {
    public let id: UUID
    public let kept: [ClosedPart]
    /// Parts whose audio could not be read. Said to the user, never hidden.
    public let lostPartIndices: [Int]
    public let durationMilliseconds: Int
    public let endedAt: Date
    public let gaps: [CaptureGap]
}

public enum RecoveryDecision: Equatable, Sendable {
    case recover(RecoveredRecording)
    /// No readable audio at all: the row is kept as `lost`, so the user is told, not left wondering.
    case lost(id: UUID, lostPartIndices: [Int])
}

public enum CaptureRecovery {
    public static func plan(_ recording: UnfinishedRecording) -> RecoveryDecision {
        var kept: [ClosedPart] = []
        var lost: [Int] = []
        var lastModified: Date?
        for part in recording.parts.sorted(by: { $0.index < $1.index }) {
            guard let probed = part.probedMilliseconds, probed >= CaptureLimits.minRecoverablePartMilliseconds else {
                lost.append(part.index)
                continue
            }
            // Never more audio than the file shows, and never more than the recorder counted.
            let length = part.recordedMilliseconds.map { min($0, probed) } ?? probed
            kept.append(ClosedPart(index: part.index, durationMilliseconds: length))
            if let modified = part.modifiedAt { lastModified = max(lastModified ?? modified, modified) }
        }
        let total = kept.reduce(0) { $0 + $1.durationMilliseconds }
        guard total >= CaptureLimits.minMilliseconds else {
            return .lost(id: recording.id, lostPartIndices: lost + kept.map(\.index))
        }
        let gaps = recording.gaps.filter { $0.atMilliseconds <= total }
        let ended = lastModified ?? recording.startedAt.addingTimeInterval(TimeInterval(total) / 1000)
        return .recover(RecoveredRecording(
            id: recording.id, kept: kept, lostPartIndices: lost, durationMilliseconds: total,
            endedAt: max(ended, recording.startedAt), gaps: gaps))
    }

    /// One decision per unfinished recording, leaving out the one being recorded right now.
    public static func plan(_ recordings: [UnfinishedRecording], activeID: UUID?) -> [RecoveryDecision] {
        recordings.filter { $0.id != activeID }.map(plan)
    }

    /// Folders in the recordings directory that belong to no row (a delete that was cut short).
    /// Only names that are recording ids are ever named, so nothing else is touched.
    public static func orphanDirectories(onDisk names: [String], knownIDs: Set<UUID>) -> [String] {
        names.filter { name in
            guard let id = UUID(uuidString: name), name == id.uuidString.lowercased() else { return false }
            return !knownIDs.contains(id)
        }
    }

    /// What the user is told after recovery.
    public static func notice(_ recovered: RecoveredRecording, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        let length = RecordingClock.string(milliseconds: recovered.durationMilliseconds)
        var text = polish
            ? "Doddy został zamknięty w trakcie nagrywania. Odzyskano \(length)."
            : "Doddy was closed while recording. \(length) was recovered."
        if !recovered.lostPartIndices.isEmpty {
            text += polish ? " Nie dało się odczytać części nagrania (\(recovered.lostPartIndices.count))." : " \(recovered.lostPartIndices.count) part(s) could not be read."
        } else {
            text += polish ? " Koniec nagrania mógł zostać utracony." : " The end of the recording may be missing."
        }
        return text
    }
}
