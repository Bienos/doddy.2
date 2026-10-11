import Foundation

/// The note the user just deleted, kept in memory only for a short undo window (ADR-183). The
/// store has already purged it; undo adds it back exactly as it was through
/// `MemoryRepository.restore`. "Delete all" never offers this.
public struct DeletedNote: Equatable, Sendable {
    public static let undoWindow: TimeInterval = 10

    public let record: MemoryRecord
    /// Its history (ADR-252), so undo brings every earlier wording back too.
    public let corrections: [MemoryCorrection]
    public let deletedAt: Date

    public init(record: MemoryRecord, corrections: [MemoryCorrection] = [], deletedAt: Date) {
        self.record = record
        self.corrections = corrections
        self.deletedAt = deletedAt
    }

    public func canUndo(at now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(deletedAt)
        return elapsed >= 0 && elapsed < Self.undoWindow
    }
}
