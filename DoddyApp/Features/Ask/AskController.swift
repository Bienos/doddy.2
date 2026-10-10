import DoddyCore
import Foundation
import Observation

/// One in-memory chat. Nothing here is written to disk: closing the screen discards the conversation,
/// and nothing becomes a saved note unless the user saves it themselves.
@MainActor
@Observable
final class AskController {
    struct Message: Identifiable, Equatable {
        enum Kind: Equatable {
            case user
            case assistant(AssistantAnswer)
        }

        let id = UUID()
        let text: String
        let kind: Kind
    }

    private(set) var messages: [Message] = []
    private(set) var isSending = false
    /// Last failure, shown with a retry. The question itself is put back in `draft`.
    private(set) var error: AssistantError?
    var draft = ""

    private let sessionID = UUID()
    private var task: Task<Void, Never>?

    var canSend: Bool { !isSending && !draft.allSatisfy(\.isWhitespace) }

    func send(using service: AssistantService, policy: AssistantPolicy, locale: String) {
        guard canSend else { return }
        let question = draft
        let history = messages.map { message -> ConversationTurn in
            switch message.kind {
            case .user: ConversationTurn(role: .user, text: message.text)
            case .assistant: ConversationTurn(role: .assistant, text: message.text)
            }
        }
        draft = ""
        error = nil
        isSending = true
        messages.append(Message(text: question, kind: .user))
        let sessionID = self.sessionID

        task = Task { [weak self] in
            let result: Result<AssistantAnswer, AssistantError>
            do throws(AssistantError) {
                result = .success(try await service.ask(question, sessionID: sessionID, history: history, locale: locale, policy: policy))
            } catch {
                result = .failure(error)
            }
            self?.finish(question: question, result: result)
        }
    }

    func cancel() {
        task?.cancel()
    }

    func clearError() { error = nil }

    private func finish(question: String, result: Result<AssistantAnswer, AssistantError>) {
        isSending = false
        task = nil
        switch result {
        case .success(let answer):
            messages.append(Message(text: answer.answer.text, kind: .assistant(answer)))
        case .failure(let failure):
            // Keep the draft: remove the unanswered question from the chat and put it back in the editor.
            if let last = messages.last, last.kind == .user, last.text == question { messages.removeLast() }
            if draft.isEmpty { draft = question }
            if failure != .cancelled { error = failure }
        }
    }
}
