import Foundation

/// Client tools the voice agent may call. Names must match the tools configured on the
/// ElevenLabs agent (see docs/implementation/V1_VOICE_STATUS.md).
public enum VoiceToolName {
    public static let searchMemories = "search_memories"
    public static let saveMemory = "save_memory"
}

/// A parsed tool call. The model only proposes; the app decides what actually happens.
public enum VoiceToolRequest: Equatable, Sendable {
    case searchMemories(query: String)
    /// Never saved directly: the app shows it and waits for the user's confirmation.
    case saveMemory(text: String)
    case unsupported(name: String)
    case invalid(name: String, reason: String)

    public static func parse(name: String, parametersJSON: Data) -> VoiceToolRequest {
        let parameters = (try? JSONSerialization.jsonObject(with: parametersJSON)) as? [String: Any] ?? [:]
        func nonEmpty(_ key: String) -> String? {
            guard let value = parameters[key] as? String, !value.allSatisfy(\.isWhitespace) else { return nil }
            return value
        }
        switch name {
        case VoiceToolName.searchMemories:
            guard let query = nonEmpty("query") else { return .invalid(name: name, reason: "missing query") }
            return .searchMemories(query: query)
        case VoiceToolName.saveMemory:
            guard let text = nonEmpty("text") else { return .invalid(name: name, reason: "missing text") }
            return .saveMemory(text: text)
        default:
            return .unsupported(name: name)
        }
    }
}

/// Text returned to the agent. Written for the model: it states only what the app verified.
public enum VoiceToolReply {
    public static let declined = "declined: the user chose not to save this note. Nothing was saved."

    public static func search(_ outcome: RecallOutcome, limit: Int = 5) -> String {
        guard case .matches(let candidates) = outcome, !candidates.isEmpty else {
            return "No saved note matched. Tell the user you couldn't find it in their saved memories. Do not guess."
        }
        let shown = candidates.prefix(limit)
        var lines = ["Found \(candidates.count) saved note\(candidates.count == 1 ? "" : "s") (exact text, newest wording):"]
        for candidate in shown {
            lines.append("- \"\(candidate.record.currentText)\" (saved \(timestamp(candidate.record.capturedAt)))")
        }
        if candidates.count > shown.count {
            lines.append("…and \(candidates.count - shown.count) more. Ask the user to narrow it down if needed.")
        }
        return lines.joined(separator: "\n")
    }

    public static func saved(_ record: MemoryRecord) -> String {
        "saved: \"\(record.currentText)\" (saved \(timestamp(record.capturedAt)))."
    }

    public static func failed(_ reason: String) -> String {
        "failed: \(reason) Nothing was saved."
    }

    public static func unsupported(_ name: String) -> String {
        "The app does not support the tool \"\(name)\". Tell the user this isn't available yet."
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "date unavailable" }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
