import Foundation

// The proposers (ADR-324, design §4): rules on the iPhone. Each returns typed proposals; the
// policy and the card decide what happens next. No model is involved in Phase C.

/// One learned-fact proposal at most per conversation, from the same sentences the "Worth
/// keeping?" card offers (ADR-247): a preference or a personal fact in the user's own words.
/// The evidence is the sentence itself (folded, hashed), not the conversation, so "Never this"
/// keeps holding when the user says it again another day.
public enum FactProposer {
    public static func sentenceEvidenceID(_ text: String) -> String {
        "fact-" + String(EvidenceDigest.compute([SearchFolding.fold(text)]).prefix(24))
    }

    public static func propose(
        from suggestions: [SaveSuggestion], savedTexts: [String], date: Date
    ) -> LearningProposal? {
        let saved = Set(savedTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let candidates = suggestions.filter { !saved.contains($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let pick = candidates.first(where: { $0.reason == .preference }) ?? candidates.first(where: { $0.reason == .personalFact })
        guard let pick else { return nil }
        let kind: LearnedFactKind = pick.reason == .preference ? .preference : .person
        guard let provenance = try? LearningProvenance(proposer: .rule, reason: pick.reason.rawValue, episodeDates: [date]),
              let fact = try? FactProposal(
                kind: kind, value: pick.text, scope: .general, confidence: kind == .preference ? 70 : 60,
                provenance: provenance, sourceEpisodeIDs: [sentenceEvidenceID(pick.text)])
        else { return nil }
        return .fact(fact)
    }
}

/// What a procedure step asks for each run, per tool, from `voice-agent/tools.json`. The
/// detector has no parameter values (outcome events carry none), so every parameter is asked.
public enum ProcedureStepTemplates {
    public static func asked(for tool: String) -> [String] {
        switch tool {
        case VoiceToolName.saveMemory: ["text"]
        case VoiceToolName.createCalendarEvent: ["title", "start"]
        case VoiceToolName.createReminder: ["title", "due"]
        case VoiceToolName.setTimer: ["minutes"]
        case VoiceToolName.addToList: ["list", "items"]
        case CloudToolName.draftEmail: ["to", "subject", "body"]
        case CloudToolName.addTodoistTask: ["content"]
        default: []
        }
    }

    /// The step in plain words, in English or Polish, for the suggested name and the screens.
    public static func title(for tool: String, polish: Bool = false) -> String {
        switch tool {
        case VoiceToolName.saveMemory: polish ? "zapisz notatkę" : "save a note"
        case VoiceToolName.createCalendarEvent: polish ? "dodaj wydarzenie" : "add an event"
        case VoiceToolName.createReminder: polish ? "dodaj przypomnienie" : "add a reminder"
        case VoiceToolName.setTimer: polish ? "uruchom minutnik" : "start a timer"
        case VoiceToolName.addToList: polish ? "dodaj do listy" : "add to a list"
        case CloudToolName.draftEmail: polish ? "napisz szkic e-maila" : "draft an email"
        case CloudToolName.addTodoistTask: polish ? "dodaj zadanie w Todoist" : "add a Todoist task"
        default: tool
        }
    }
}

/// Proposes a procedure when the same ordered sequence of allowed tools was completed in one
/// conversation on three or more separate days within 30 days (design §4.2).
public enum ProcedureDetector {
    public static let minDays = 3
    public static let windowDays = 30

    /// `existingSequences` are the tool sequences of every procedure row, whatever its status:
    /// a sequence the user said no to, or retired, is not proposed again when a later day
    /// would give it new evidence.
    public static func detect(
        events: [OutcomeEvent], knownDigests: Set<String>, existingSequences: Set<[String]> = [], now: Date,
        calendar: Calendar = .current, polish: Bool = false
    ) -> [LearningProposal] {
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let usable = events.filter {
            $0.kind == .completed && $0.createdAt >= since && $0.createdAt <= now
                && $0.detail.sessionID != nil && $0.detail.toolName.map(PlanTool.allowed.contains) == true
        }
        // One sequence per conversation, in the order the tools completed.
        var bySession: [String: [OutcomeEvent]] = [:]
        for event in usable { bySession[event.detail.sessionID!, default: []].append(event) }
        struct Episode { let day: Date; let ids: [String]; let at: Date }
        var sequences: [[String]: [Episode]] = [:]
        for (_, ordered) in bySession {
            let sorted = ordered.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            let tools = sorted.compactMap(\.detail.toolName)
            guard tools.count >= 2, tools.count <= Procedure.maxSteps else { continue }
            let day = calendar.startOfDay(for: sorted[0].createdAt)
            sequences[tools, default: []].append(Episode(day: day, ids: sorted.map(\.id.uuidString), at: sorted[0].createdAt))
        }
        var proposals: [LearningProposal] = []
        for (tools, episodes) in sequences.sorted(by: { $0.key.joined(separator: ">") < $1.key.joined(separator: ">") }) {
            // One episode per day, the newest days first.
            var byDay: [Date: Episode] = [:]
            for episode in episodes where byDay[episode.day].map({ episode.at > $0.at }) ?? true { byDay[episode.day] = episode }
            let days = byDay.values.sorted { $0.at > $1.at }
            guard days.count >= minDays, !existingSequences.contains(tools) else { continue }
            let evidence = Array(days.prefix(minDays))
            let ids = evidence.flatMap(\.ids)
            guard !knownDigests.contains(EvidenceDigest.compute(ids)) else { continue }
            guard let provenance = try? LearningProvenance(proposer: .rule, reason: "repeated_sequence", episodeDates: evidence.map(\.at)),
                  let steps = try? tools.enumerated().map({ index, tool in
                      try ProcedureStep(number: index + 1, toolName: tool, fixed: [:], asked: ProcedureStepTemplates.asked(for: tool))
                  }),
                  let proposal = try? ProcedureProposal(
                    triggerText: trigger(for: tools, polish: polish), steps: steps, scope: .general, provenance: provenance, sourceEpisodeIDs: ids)
            else { continue }
            proposals.append(.procedure(proposal))
        }
        return proposals
    }

    /// "Add a reminder, then start a timer" / "Dodaj przypomnienie, potem uruchom minutnik". The user
    /// can rename it in Settings, What I've learned.
    public static func trigger(for tools: [String], polish: Bool = false) -> String {
        let titles = tools.map { ProcedureStepTemplates.title(for: $0, polish: polish) }
        let joined = titles.joined(separator: polish ? ", potem " : ", then ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}
