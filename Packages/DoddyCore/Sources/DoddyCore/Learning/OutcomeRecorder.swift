import Foundation

/// Turns what "What Doddy did" recorded into outcome events (ADR-440, design §4.3). The log
/// entry is the source of truth about what happened; this only reads its outcome, never the
/// detail text, and writes identifiers.
public enum OutcomeRecorder {
    /// Asked again within this long after a change counts as "redone".
    public static let redoWindow: TimeInterval = 10 * 60

    /// Events for an entry that was just added (`previous == nil`) or replaced. `recent` are the
    /// other entries, newest first, for spotting a redo. `sessionID` is the conversation's id.
    public static func events(
        for entry: ActivityEntry, previous: ActivityEntry?, recent: [ActivityEntry], sessionID: String?, now: Date
    ) -> [OutcomeEvent] {
        var events: [OutcomeEvent] = []
        let tool = toolName(entry)
        func detail(_ correction: CorrectionKind? = nil) -> OutcomeDetail? {
            try? OutcomeDetail(toolName: tool, correction: correction, sessionID: sessionID)
        }
        func event(_ kind: OutcomeKind, _ detail: OutcomeDetail?) -> OutcomeEvent? {
            guard let detail else { return nil }
            return try? OutcomeEvent(requestID: entry.id.uuidString, kind: kind, detail: detail, createdAt: now)
        }

        // Undo is a correction of a change that was done, once.
        if case .undone = entry.undoState, !isUndone(previous) {
            if let undo = event(.corrected, detail(.undo)) { events.append(undo) }
            return events
        }
        guard entry.outcome != previous?.outcome else { return events }
        switch entry.outcome {
        case .done, .alreadyThere, .lookedUp:
            if let done = event(.completed, detail()) { events.append(done) }
            if !entry.outcome.isLookup, isRedo(entry, among: recent, now: now), let redo = event(.redone, detail()) {
                events.append(redo)
            }
        case .declined:
            if let declined = event(.declined, detail()) { events.append(declined) }
        case .notDone where entry.note == ActivityLog.unansweredNote:
            if let cancelled = event(.cancelled, detail()) { events.append(cancelled) }
        case .inProgress, .notSure, .notDone, .opened, .shown:
            break
        }
        return events
    }

    /// The tool as an identifier: the entry's own tool name, or, for entries from before
    /// ADR-440, the fixed title turned into one ("Add reminder" → "add_reminder").
    public static func toolName(_ entry: ActivityEntry) -> String {
        if let tool = entry.tool { return tool }
        let folded = entry.title.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII ? Character(scalar) : "_"
        }
        let collapsed = String(folded).split(separator: "_", omittingEmptySubsequences: true).joined(separator: "_")
        return collapsed.isEmpty ? "unknown" : collapsed
    }

    private static func isUndone(_ entry: ActivityEntry?) -> Bool {
        if case .undone = entry?.undoState { return true }
        return false
    }

    /// The same tool, done or declined within the window, with a different request.
    private static func isRedo(_ entry: ActivityEntry, among recent: [ActivityEntry], now: Date) -> Bool {
        let tool = toolName(entry)
        return recent.contains { earlier in
            earlier.id != entry.id && toolName(earlier) == tool
                && (earlier.outcome == .done || earlier.outcome == .declined)
                && earlier.at <= entry.at && entry.at.timeIntervalSince(earlier.at) <= redoWindow
                && (earlier.detail ?? "") != (entry.detail ?? "")
        }
    }
}

extension ActivityOutcome {
    var isLookup: Bool { self == .lookedUp }
}
