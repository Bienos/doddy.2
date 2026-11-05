import Foundation

// A typed note from a small capture surface, first the Mac menu bar (ADR-435). The words are
// checked with the same rules as a note from the watch (`WatchNote.problem`), saved as a typed
// note, and "Saved" is said only from the repository's read-back. A save that threw may or may
// not have been written, so it is never reported as saved or as nothing saved, and the person is
// asked to look before trying again (unknown is never success and never blindly retried).

public enum QuickCaptureOutcome: Equatable, Sendable {
    /// Written and read back.
    case saved(MemoryRecord)
    /// Not sent to the repository: the words need changing first. Nothing was saved.
    case needsChange(String)
    /// The repository didn't confirm. It may or may not be saved.
    case unconfirmed
}

public enum QuickCapture {
    public static let unconfirmedMessage =
        "Doddy couldn't confirm the note was saved. Look at Recent before trying again."

    public static func save(_ text: String, to repository: MemoryRepository, at date: Date = Date()) async -> QuickCaptureOutcome {
        if let problem = WatchNote.problem(text) { return .needsChange(problem) }
        let draft: NewMemory
        do {
            draft = try NewMemory(text: text, category: .other, source: .explicitText, capturedAt: date)
        } catch {
            return .needsChange("Say or type a few words first.")
        }
        do {
            return .saved(try await repository.save(draft))
        } catch {
            return .unconfirmed
        }
    }
}
