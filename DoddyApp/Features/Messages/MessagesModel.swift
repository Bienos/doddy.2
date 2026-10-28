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
    /// A file Doddy offered with an answer (ADR-606), by the id of that answer. Kept for this session only: the card
    /// is an offer, not a record, so after the app closes the offer is gone and nothing was made.
    private(set) var proposals: [UUID: AssistantProposal] = [:]
    /// A training plan Doddy offered with an answer (ADR-626), by the id of that answer. An offer, not a record: kept for this
    /// session only. It holds a goal and maybe days and minutes; the safety questions are asked on the plan screen.
    private(set) var planAsks: [UUID: PlanAsk] = [:]
    /// The answer whose file is being made now. One at a time, so a double tap makes one file.
    private(set) var making: UUID?
    /// Why the last file was not made. The offer stays so the person can try again or decline.
    private(set) var makeFailure: ThreadDocumentError?
    var draft = ""
    /// A photo to send with the next message, already made smaller on this iPhone. Sent once, then dropped; never saved.
    var photo: AssistantImage?

    /// The copy on Doddy's server for Doddy Web could not be confirmed deleted. This iPhone's copy is gone; the screen says
    /// what is left and offers to try again.
    private(set) var webDeleteFailed = false

    private let repository: any MessageThreadRepository
    /// Sends the thread to Doddy's server for the web after every change; nil in tests and builds without a server.
    private let sync: (any ThreadSyncClient)?
    private var syncTask: Task<Void, Never>?
    private let now: @Sendable () -> Date
    private let sessionID = UUID()
    private var task: Task<Void, Never>?
    private var makeTask: Task<Void, Never>?
    private var didLoad = false

    init(repository: any MessageThreadRepository, sync: (any ThreadSyncClient)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.sync = sync
        self.now = now
    }

    var canSend: Bool { storage != .loading && ThreadRules.canSend(draft: draft, isSending: isSending, hasPhoto: photo != nil) }

    // MARK: Loading

    /// Reads the saved thread. A message left "sending" because the app was closed is not delivered.
    func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            _ = try await repository.failUnfinished()
            messages = try await repository.recent(limit: ThreadRules.displayLimit)
            storage = .saving
            // Catches the web copy up with anything that changed while it couldn't be sent.
            syncToWeb()
        } catch {
            storage = .notSaved
        }
    }

    // MARK: Sending

    /// - Parameter service: nil when Ask Doddy isn't set up.
    func send(using service: AssistantService?, policy: AssistantPolicy, locale: String) {
        guard canSend else { return }
        let image = photo
        let question = image == nil
            ? draft.trimmingCharacters(in: .whitespacesAndNewlines)
            : ThreadRules.photoQuestion(draft: draft, fallback: NSLocalizedString("What's in this photo?", comment: "Messages: the question sent with a photo when nothing was typed"))
        guard preflight(question, service: service, policy: policy) else { return }
        draft = ""
        photo = nil
        deliver(ThreadMessage.user(question, now: now(), hasPhoto: image != nil), image: image, replacing: nil, using: service, policy: policy, locale: locale)
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

    private func deliver(_ message: ThreadMessage, image: AssistantImage? = nil, replacing old: UUID?, using service: AssistantService?, policy: AssistantPolicy, locale: String) {
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
                result = .success(try await service.ask(message.text, sessionID: sessionID, history: history, locale: locale, image: image, policy: policy))
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
            if let proposal = answer.answer.proposal { proposals[reply.id] = proposal }
            if let planAsk = answer.answer.planAsk { planAsks[reply.id] = planAsk }
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
        syncToWeb()
    }

    /// Sends what is saved on this iPhone to the web copy. Only the latest send matters, so an earlier one still on its way
    /// is cancelled; a failure is left for the next change or the next time Messages opens. Nothing is shown for it: the
    /// conversation itself is on this iPhone either way.
    private func syncToWeb() {
        guard let sync, storage == .saving else { return }
        let snapshot = ThreadSync.snapshot(of: messages)
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await sync.send(snapshot)
        }
    }

    // MARK: Files

    /// The person tapped Make on a card. Only the words on the card are made; the model is not asked again. The file
    /// bubble is added once the server returned a link and it was saved and read back; a failure leaves the offer.
    func makeDocument(for id: UUID, using maker: (any ThreadDocumentMaker)?) {
        guard making == nil, storage != .loading, let proposal = proposals[id] else { return }
        makeFailure = nil
        guard let maker else { makeFailure = .notConfigured; return }
        making = id
        makeTask = Task {
            let result: Result<ThreadDocument, ThreadDocumentError>
            do {
                result = .success(try await maker.make(proposal))
            } catch let failure as ThreadDocumentError {
                result = .failure(failure)
            } catch {
                result = .failure(.failed)
            }
            await self.finishMaking(id, result)
        }
    }

    private func finishMaking(_ id: UUID, _ result: Result<ThreadDocument, ThreadDocumentError>) async {
        switch result {
        case .success(let document):
            let file = ThreadMessage.file(document, now: now())
            proposals[id] = nil
            messages.append(file)
            await persist { try await $0.append(file) }
        case .failure(let failure):
            makeFailure = failure
        }
        making = nil
        makeTask = nil
    }

    /// "Not now": the offer goes. Nothing was made, so nothing is deleted.
    func dismissProposal(_ id: UUID) {
        guard making != id else { return }
        proposals[id] = nil
        makeFailure = nil
    }

    func clearMakeFailure() { makeFailure = nil }

    /// "Not now" on a plan offer: it goes. Nothing was made and nothing was asked.
    func dismissPlanAsk(_ id: UUID) {
        planAsks[id] = nil
    }

    // MARK: Deleting

    /// Removes the whole conversation from this iPhone, then the copy on Doddy's server for the web. The screen is emptied
    /// only after the store read back as empty; the web copy is called deleted only when the server said so.
    func deleteConversation() async {
        guard !isSending, storage != .loading else { return }
        deleteFailed = false
        do {
            try await repository.deleteAll()
            messages = []
            proposals = [:]
            planAsks = [:]
            error = nil
            makeFailure = nil
            storage = .saving
        } catch {
            deleteFailed = true
            return
        }
        await deleteWebCopy()
    }

    /// Deletes the web copy. No session for the server means there is no copy to delete.
    func deleteWebCopy() async {
        guard let sync else { return }
        syncTask?.cancel()
        webDeleteFailed = false
        do {
            try await sync.deleteAll()
        } catch .notConfigured {
            return
        } catch {
            webDeleteFailed = true
        }
    }

    func clearDeleteFailure() { deleteFailed = false }

    func clearWebDeleteFailure() { webDeleteFailed = false }
}
