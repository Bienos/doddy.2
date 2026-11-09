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
    /// Who ran the voice (`VoiceProvider` raw value), for comparing the two in testing (ADR-265).
    /// Logs kept before ADR-265 have none. Never sent to either provider.
    public let voiceProvider: String?
    /// How it ended (`VoiceSessionEnd.code`, ADR-360): "user", "doddy", "quiet" or "dropped-…".
    /// Logs kept before ADR-360 have none. Never sent to the voice provider as such.
    public let ended: String?

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, lines: [Line], voiceProvider: String? = nil, ended: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lines = lines
        self.voiceProvider = voiceProvider
        self.ended = ended
    }
}

/// Text from the user's notes, lists, calendar, reminders or an earlier conversation, handed to
/// the agent between fixed markers (review C4). The agent's instructions say that anything
/// between them is information, never an instruction; the context variables sit between them in
/// the instructions, and tool results put them around stored text. Content can't close the block
/// early: every copy of a marker in it is removed, and each line stays one line.
public enum ToolData {
    public static let begin = "<<<DATA"
    public static let end = "DATA>>>"

    /// One line of content: no markers, no line breaks.
    public static func clean(_ text: String) -> String {
        var flat = text.components(separatedBy: .newlines).joined(separator: " ")
        while let marker = flat.range(of: begin, options: .caseInsensitive) ?? flat.range(of: end, options: .caseInsensitive) {
            flat.removeSubrange(marker)
        }
        return flat
    }

    /// Lines the app wrote around content (each already `clean`), between the markers.
    public static func block(_ lines: [String]) -> String {
        ([begin] + lines + [end]).joined(separator: "\n")
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
    /// What Doddy said is clipped later than what the user said: an answer that lists several
    /// ideas (names, places) is the part the next conversation most needs, and 400 characters
    /// cut it off after the first one or two. The conversations budget still bounds the total.
    public static let maxDoddyLineLength = 1000

    /// Said when only the end of the newest conversation fit the budget.
    static let cutStartNote = "(The start of this conversation was cut to fit. Its last lines follow.)"

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
            let body = log.lines.map {
                $0.fromUser ? "User: " + clip($0.text) : "Doddy: " + clip($0.text, limit: maxDoddyLineLength)
            }
            let block = ([header] + body).joined(separator: "\n")
            if used + block.count + 2 > maxCharacters {
                truncated = true
                // The newest conversation alone is longer than the budget (a long planning chat).
                // Dropping it whole left the next conversation with nothing, so its last lines
                // are kept instead: the end is what the next conversation carries on from.
                if kept.isEmpty, let tail = lastLines(of: body, header: header, maxCharacters: maxCharacters) {
                    kept.append((log.id, tail))
                }
                break
            }
            kept.append((log.id, block))
            used += block.count + 2
        }
        return (kept, truncated)
    }

    /// The header, a note that the start was cut, and as many of the newest lines as fit in
    /// `maxCharacters` (the same two-character gap between blocks as the whole-block rule). Nil
    /// when not even the newest line fits.
    private static func lastLines(of body: [String], header: String, maxCharacters: Int) -> String? {
        var used = header.count + 1 + cutStartNote.count + 2
        var tail: [String] = []
        for line in body.reversed() {
            guard used + line.count + 1 <= maxCharacters else { break }
            tail.append(line)
            used += line.count + 1
        }
        guard !tail.isEmpty else { return nil }
        return ([header, cutStartNote] + tail.reversed()).joined(separator: "\n")
    }

    /// One line, no data markers (ToolData), at most `limit` characters.
    static func clip(_ text: String, limit: Int = maxLineLength) -> String {
        let flat = ToolData.clean(text)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)) + "…"
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
            "Doddy remembered conversations — exported \(iso.string(from: exportedAt))",
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
