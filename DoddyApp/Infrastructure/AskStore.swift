import DoddyAssistant
import DoddyCore
import Foundation
import Observation

/// One-question-at-a-time view state for the cloud assistant preview. Nothing is persisted:
/// the question, the reply and the notes sent are forgotten when the screen is left.
@MainActor
@Observable
final class AskStore {
    struct Answer: Equatable {
        let text: String
        /// Saved notes the reply cited, verified against the notes actually sent.
        let sources: [MemoryRecord]
    }

    enum Phase: Equatable {
        case idle
        case sending
        case answered(Answer)
        case failed(String)
    }

    /// At most this many matching notes accompany a question.
    static let maxNotes = 3

    private(set) var phase: Phase = .idle
    private(set) var notesSent = 0
    private let environment: AppEnvironment
    private let sessionID = UUID()
    private var task: Task<Void, Never>?

    init(environment: AppEnvironment) { self.environment = environment }

    var isSending: Bool { phase == .sending }

    func ask(_ question: String) {
        guard !isSending else { return }
        phase = .sending
        notesSent = 0
        task = Task { await run(question) }
    }

    func cancel() { task?.cancel() }

    private func run(_ question: String) async {
        var grounding: [MemoryCandidate] = []
        if let outcome = try? await environment.recallService.recall(question, limit: 20),
           case .matches(let candidates) = outcome {
            grounding = Array(candidates.prefix(Self.maxNotes))
        }
        notesSent = grounding.count
        do {
            let reply = try await environment.assistantClient.respond(
                AssistantRequest(sessionID: sessionID, userText: question, groundingMemories: grounding))
            let sent = Dictionary(grounding.map { ($0.memoryID, $0.record) }, uniquingKeysWith: { first, _ in first })
            phase = .answered(Answer(text: reply.text, sources: reply.citedMemoryIDs.compactMap { sent[$0] }))
        } catch AssistantError.cancelled {
            phase = .idle
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? AssistantError {
        case .offline: "You seem to be offline. Nothing was sent."
        case .timeout: "That took too long, so I stopped waiting. Nothing was saved."
        case .rateLimited: "You've hit the preview's limit for now. Try again later."
        case .providerUnavailable, .malformedResponse: "Doddy's AI service isn't answering right now. Try again in a bit."
        case .notAuthorized: "This iPhone couldn't be authorised with Doddy's server. Try again later."
        case .invalidCitations: "I couldn't verify which of your notes that answer used, so I'm not showing it."
        case .invalidRequest: "That question can't be sent as it is (empty or too long)."
        case .cancelled, nil:
            if error is DoddyError { "AI answers aren't available in this build." } else { "Something went wrong. Nothing was changed." }
        }
    }
}
