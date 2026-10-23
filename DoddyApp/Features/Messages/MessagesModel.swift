import DoddyCore
import Foundation
import Observation

/// The thread with Doddy (ADR-585): what the Messages screen shows and does, without the views, so it is
/// type-checked on Linux. Every message is saved on this iPhone and read back before it counts as saved
/// (`MessageThreadRepository`); the rules for what goes to the server as earlier turns, and what the
/// delivery line may say, are `ThreadRules`. Nothing becomes a saved note unless the user saves it.
@MainActor
@Observable
final class MessagesModel {
    enum Storage: Equatable {
        /// Reading what was saved. Sending waits so the thread keeps its order.
        case loading
        /// Messages are kept on this iPhone.
        case saving
        /// Reading or saving failed: what is on screen may not be kept. The screen says so.
        case notSaved
    }

    private(set) var messages: [ThreadMessage] = []
    private(set) var isSending = false
    /// The last failure, shown with what to do about it. The message itself stays in the thread.
    private(set) var error: AssistantError?
    private(set) var storage: Storage = .loading
    /// Deleting the conversation did not read back as done, so nothing is claimed gone.
    private(set) var deleteFailed = false
    var draft = ""

    private let repository: any MessageThreadRepository
    private let now: @Sendable () -> Date
    private let sessionID = UUID()
    private var task: Task<Void, Never>?
    private var didLoad = false

    init(repository: any MessageThreadRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    var canSend: Bool { storage != .loading && ThreadRules.canSend(draft: draft, isSending: isSending) }

    // MARK: Loading

    /// Reads the saved thread. A message left "sending" because the app was closed is not delivered.
    func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            _ = try await repository.failUnfinished()
            messages = try await repository.recent(limit: ThreadRules.displayLimit)
            storage = .saving
        } catch {
            storage = .notSaved
        }
    }

    // MARK: Sending

    /// - Parameter service: nil when Ask Doddy isn't set up.
    func send(using service: AssistantService?, policy: AssistantPolicy, locale: String) {
        guard canSend else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preflight(question, service: service, policy: policy) else { return }
        draft = ""
        deliver(ThreadMessage.user(question, now: now()), replacing: nil, using: service, policy: policy, locale: locale)
    }

    /// Sends a message that got no answer once more, as a new message at the end of the thread.
    func retry(_ id: UUID, using service: AssistantService?, policy: AssistantPolicy, locale: String) {
        guard !isSending, storage != .loading,
              let index = messages.firstIndex(where: { $0.id == id }), ThreadRules.canRetry(messages[index])
        else { return }
        let text = messages[index].text
        guard preflight(text, service: service, policy: policy) else { return }
        messages.remove(at: index)
        deliver(ThreadMessage.user(text, now: now()), replacing: id, using: service, policy: policy, locale: locale)
    }

    func cancel() {
        task?.cancel()
    }

    func clearError() { error = nil }

    /// Nothing is saved or sent while Ask Doddy is off, not set up, or the text can't be sent as written:
    /// the words stay where they are and the screen says what to do.
    private func preflight(_ text: String, service: AssistantService?, policy: AssistantPolicy) -> Bool {
        guard policy.consentGranted else { error = .consentRequired; return false }
        guard service != nil else { error = .notConfigured; return false }
        guard text.unicodeScalars.count <= AssistantLimits.maxQuestionLength else { error = .invalidRequest; return false }
        return true
    }

    private func deliver(_ message: ThreadMessage, replacing old: UUID?, using service: AssistantService?, policy: AssistantPolicy, locale: String) {
        guard let service else { return }
        let history = ThreadRules.history(from: messages, before: message.createdAt)
        messages.append(message)
        error = nil
        isSending = true
        let sessionID = self.sessionID
        task = Task {
            if let old { await self.persist { try await $0.delete(id: old) } }
            await self.persist { try await $0.append(message) }
            let result: Result<AssistantAnswer, AssistantError>
            do throws(AssistantError) {
                result = .success(try await service.ask(message.text, sessionID: sessionID, history: history, locale: locale, policy: policy))
            } catch {
                result = .failure(error)
            }
            await self.finish(message, result)
        }
    }

    private func finish(_ message: ThreadMessage, _ result: Result<AssistantAnswer, AssistantError>) async {
        switch result {
        case .success(let answer):
            let reply = ThreadMessage.doddy(answer, now: now())
            setDelivery(of: message.id, .sent)
            messages.append(reply)
            await persist {
                try await $0.setDelivery(id: message.id, .sent)
                try await $0.append(reply)
            }
        case .failure(let failure):
            setDelivery(of: message.id, .failed)
            if failure != .cancelled { error = failure }
            await persist { try await $0.setDelivery(id: message.id, .failed) }
        }
        isSending = false
        task = nil
    }

    private func setDelivery(of id: UUID, _ delivery: ThreadMessage.Delivery) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].delivery = delivery
    }

    /// Runs a save to its end even when the screen closes and cancels the request, and says so when it
    /// did not work. Cancelling stops the question, not the bookkeeping.
    private func persist(_ work: @escaping @Sendable (any MessageThreadRepository) async throws -> Void) async {
        let repository = self.repository
        let saved = await Task.detached { (try? await work(repository)) != nil }.value
        if !saved { storage = .notSaved }
    }

    // MARK: Deleting

    /// Removes the whole conversation from this iPhone. The screen is emptied only after the store read
    /// back as empty.
    func deleteConversation() async {
        guard !isSending, storage != .loading else { return }
        deleteFailed = false
        do {
            try await repository.deleteAll()
            messages = []
            error = nil
            storage = .saving
        } catch {
            deleteFailed = true
        }
    }

    func clearDeleteFailure() { deleteFailed = false }
}
