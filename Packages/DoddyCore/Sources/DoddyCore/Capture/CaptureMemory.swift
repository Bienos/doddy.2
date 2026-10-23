import Foundation

// A recording is not memory (ADR-579). Its audio, words and summary are source material that stays
// in Recordings. What Doddy remembers across conversations is only what the user picks, one thing
// at a time, with a tap on "Remember this". That makes an ordinary note (the same store, the same
// edit and delete) whose last line says where it came from, and a link row that keeps the exact
// recording and time for as long as the recording exists.
//
// Nothing here saves anything. The app shows `draft`, the user may change it, and only a tap on
// Save calls `MemoryRepository.save`.

public enum CaptureMemory {
    public enum Kind: Equatable, Sendable {
        case decision, actionItem, fact, keyPoint, excerpt
    }

    /// The note as it will be saved, for the user to read and change first: the thing, then where
    /// it came from. "Alex is responsible for the website launch" becomes
    /// "Alex is responsible for the website launch\n\nFrom the recording “Budget call”, 14:32."
    public static func draft(item text: String, recordingTitle: String, atMilliseconds: Int, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        let thing = TranscriptEdit.cleaned(text) ?? ""
        let title = RecordingTitle.clean(recordingTitle)
        let when = RecordingClock.string(milliseconds: atMilliseconds)
        let source = polish ? "Z nagrania „\(title)”, \(when)." : "From the recording “\(title)”, \(when)."
        return "\(thing)\n\n\(source)"
    }

    /// The note type that fits what was picked. The user can change it like any note's.
    public static func category(for kind: Kind) -> MemoryCategory {
        switch kind {
        case .decision: .decision
        case .actionItem: .commitment
        case .fact: .fact
        case .keyPoint, .excerpt: .other
        }
    }

    /// A request to save the note. `source` is an explicit capture: the user tapped Save.
    public static func newMemory(text: String, kind: Kind, savedAt: Date) throws(MemoryValidationError) -> NewMemory {
        try NewMemory(text: text, category: category(for: kind), source: .explicitText, capturedAt: savedAt)
    }

    /// A note's footer, when asked where it came from. Nil for an ordinary note.
    public static func provenance(recordingTitle: String?, atMilliseconds: Int, recordingStillExists: Bool, _ language: NotificationLanguage) -> String? {
        guard let title = recordingTitle.map(RecordingTitle.clean), !title.isEmpty else { return nil }
        let polish = language == .polish
        let when = RecordingClock.string(milliseconds: atMilliseconds)
        if recordingStillExists {
            return polish ? "Z nagrania „\(title)”, \(when)" : "From the recording “\(title)”, \(when)"
        }
        return polish ? "Z nagrania „\(title)”, \(when) (nagranie zostało usunięte)" : "From the recording “\(title)”, \(when) (the recording was deleted)"
    }
}
