import Foundation

/// A finished voice conversation as the app keeps it on the phone, so Doddy can pick up where
/// it left off next time. It is sent to the agent at the start of the next conversation only
/// while the user keeps "Remember recent conversations" on; it never becomes a memory record.
public struct ConversationLog: Equatable, Sendable, Codable, Identifiable {
    public struct Line: Equatable, Sendable, Codable {
        public let fromUser: Bool
        public let text: String

        public init(fromUser: Bool, text: String) {
            self.fromUser = fromUser
            self.text = text
        }
    }

    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let lines: [Line]
    /// Who ran the voice (`VoiceProvider` raw value), for comparing the two in testing (ADR-264).
    /// Logs kept before ADR-264 have none. Never sent to either provider.
    public let voiceProvider: String?

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, lines: [Line], voiceProvider: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lines = lines
        self.voiceProvider = voiceProvider
    }
}

/// Builds the text the app hands to the voice agent as dynamic variables when a conversation
/// starts. Deterministic and bounded, so the prompt cannot grow without limit, and honest about
/// cuts: the agent is told when a list is incomplete.
public enum VoiceContext {
    public struct Rendered: Equatable, Sendable {
        public let text: String
        public let includedCount: Int
        public let truncated: Bool

        // Explicit so the app target (another module) can build one, e.g. when the user has
        // switched remembering conversations off; the memberwise init is internal.
        public init(text: String, includedCount: Int, truncated: Bool) {
            self.text = text
            self.includedCount = includedCount
            self.truncated = truncated
        }
    }

    public static let defaultNotesBudget = 6000
    public static let defaultConversationsBudget = 4000
    public static let maxLineLength = 400

    /// Newest first, one line per note: "- [2026-10-09 02:05] text". Stops at the character
    /// budget and reports the cut, so the agent knows to use search_memories for the rest.
    public static func savedNotes(_ records: [MemoryRecord], maxCharacters: Int = defaultNotesBudget, timeZone: TimeZone = .current) -> Rendered {
        let sorted = records.sorted { lhs, rhs in
            switch (lhs.capturedAt, rhs.capturedAt) {
            case let (l?, r?): l > r
            case (nil, _?): false
            case (_?, nil): true
            case (nil, nil): lhs.currentText < rhs.currentText
            }
        }
        var lines: [String] = []
        var used = 0
        var truncated = false
        for record in sorted {
            let stamp = record.capturedAt.map { format($0, timeZone: timeZone) } ?? "date unknown"
            let line = "- [\(stamp)] \(clip(record.currentText))"
            if used + line.count + 1 > maxCharacters {
                truncated = true
                break
            }
            lines.append(line)
            used += line.count + 1
        }
        let text = lines.isEmpty ? "(no saved notes)" : lines.joined(separator: "\n")
        return Rendered(text: text, includedCount: lines.count, truncated: truncated)
    }

    /// The most recent conversations that fit the budget, rendered oldest to newest so the
    /// agent reads them in order. Whole conversations are dropped from the old end first.
    public static func recentConversations(_ logs: [ConversationLog], maxCharacters: Int = defaultConversationsBudget, timeZone: TimeZone = .current) -> Rendered {
        let selection = selectConversations(logs, maxCharacters: maxCharacters, timeZone: timeZone)
        let kept = selection.blocks.map(\.text)
        let text = kept.isEmpty ? "(no earlier conversations)" : kept.reversed().joined(separator: "\n\n")
        return Rendered(text: text, includedCount: kept.count, truncated: selection.truncated)
    }

    /// Which kept conversations the next voice conversation would be handed, by the same rule
    /// as `recentConversations`. Shown in Settings → Remembered conversations (ADR-177).
    public static func conversationsSentNextTime(_ logs: [ConversationLog], maxCharacters: Int = defaultConversationsBudget, timeZone: TimeZone = .current) -> Set<UUID> {
        Set(selectConversations(logs, maxCharacters: maxCharacters, timeZone: timeZone).blocks.map(\.id))
    }

    /// Newest first; stops at the first conversation that doesn't fit.
    private static func selectConversations(_ logs: [ConversationLog], maxCharacters: Int, timeZone: TimeZone) -> (blocks: [(id: UUID, text: String)], truncated: Bool) {
        let newestFirst = logs.sorted { $0.endedAt > $1.endedAt }
        var kept: [(id: UUID, text: String)] = []
        var used = 0
        var truncated = false
        for log in newestFirst where !log.lines.isEmpty {
            let header = "Conversation on \(format(log.startedAt, timeZone: timeZone)):"
            let body = log.lines.map { ($0.fromUser ? "User: " : "Doddy: ") + clip($0.text) }
            let block = ([header] + body).joined(separator: "\n")
            if used + block.count + 2 > maxCharacters {
                truncated = true
                break
            }
            kept.append((log.id, block))
            used += block.count + 2
        }
        return (kept, truncated)
    }

    static func clip(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > maxLineLength else { return flat }
        return String(flat.prefix(maxLineLength - 1)) + "…"
    }

    static func format(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// Whether a finished voice conversation is kept on the phone (PRD item 6, ADR-170). A private
/// conversation is never kept, whatever the "Remember recent conversations" setting says, so it
/// can't come back as context in a later conversation. Empty conversations are never kept.
public enum ConversationRetention {
    public static func shouldKeep(rememberRecent: Bool, isPrivate: Bool, lineCount: Int) -> Bool {
        rememberRecent && !isPrivate && lineCount > 0
    }
}

/// Plain-text export of the kept conversations (Settings → Remembered conversations, ADR-177).
/// Oldest first, every line in full (no clipping), in the user's time zone.
public enum ConversationLogExport {
    public static func plainText(_ logs: [ConversationLog], exportedAt: Date, timeZone: TimeZone = .current) -> String {
        let iso = ISO8601DateFormatter()
        var lines = [
            "DODDY remembered conversations — exported \(iso.string(from: exportedAt))",
            "\(logs.count) \(logs.count == 1 ? "conversation" : "conversations"). Written down from the conversation's text; no audio is kept.",
            "",
        ]
        for log in logs.sorted(by: { $0.startedAt < $1.startedAt }) {
            lines.append("## \(VoiceContext.format(log.startedAt, timeZone: timeZone)) – \(VoiceContext.format(log.endedAt, timeZone: timeZone))")
            for line in log.lines {
                lines.append((line.fromUser ? "You: " : "Doddy: ") + line.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
