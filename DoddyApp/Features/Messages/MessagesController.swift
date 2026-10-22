import DoddyCore
import Foundation
import Observation

/// Doddy's Messages thread (owner, 22 Oct 2026, ADR-582): typed chat with Doddy, kept on this
/// iPhone. It replaces the one-off Ask screen, whose conversation was thrown away on Close. The
/// replies come from the same gateway and the same rules as Ask (consent, saved notes, the AI
/// disclosure), but every message is written to `ChatLogFile` and a message only counts as kept
/// when the file was read back. Files and infographics Doddy sends later arrive through
/// `receive(_:)`.
@MainActor
@Observable
final class MessagesController {
    static let shared = MessagesController()

    private(set) var messages: [ChatMessage] = []
    private(set) var isSending = false
    /// Last failure from Doddy's AI, shown with a retry. The question is put back in `draft`.
    private(set) var error: AssistantError?
    /// The thread couldn't be read or written. Nothing is claimed kept while this is set.
    private(set) var storageProblem: String?
    var draft = ""

    private let log: ChatLogFile?
    private var task: Task<Void, Never>?
    private let sessionID = UUID()
    private static let lastOpenedKey = "messages.lastOpened"

    init(log: ChatLogFile? = MessagesController.defaultLog()) {
        self.log = log
        load()
    }

    var canSend: Bool { !isSending && !draft.allSatisfy(\.isWhitespace) }

    /// Doddy's messages the user hasn't looked at since the thread was last open.
    var unread: Int {
        messages.unreadCount(since: UserDefaults.standard.object(forKey: Self.lastOpenedKey) as? Date)
    }

    func markOpened() {
        UserDefaults.standard.set(Date(), forKey: Self.lastOpenedKey)
    }

    private func load() {
        guard let log else {
            storageProblem = NSLocalizedString("Messages can't be kept on this iPhone right now.", comment: "")
            return
        }
        do { messages = try log.load() } catch {
            storageProblem = NSLocalizedString("The saved messages couldn't be read. They were left as they are.", comment: "")
        }
    }

    /// Adds a message to the thread and keeps it. False when it couldn't be kept (the thread on
    /// screen is unchanged, so what is shown is always what is stored).
    @discardableResult
    func receive(_ message: ChatMessage) -> Bool {
        guard let log else { return false }
        do {
            messages = try log.append(message)
            storageProblem = nil
            return true
        } catch {
            storageProblem = NSLocalizedString("This message couldn't be kept on this iPhone.", comment: "")
            return false
        }
    }

    func send(using service: AssistantService, policy: AssistantPolicy, locale: String) {
        guard canSend else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = messages.suffix(12).compactMap { message -> ConversationTurn? in
            guard let text = message.text else { return nil }
            return ConversationTurn(role: message.sender == .user ? .user : .assistant, text: text)
        }
        guard receive(ChatMessage(sender: .user, content: .text(question))) else { return }
        draft = ""
        error = nil
        isSending = true
        let sessionID = self.sessionID
        task = Task { [weak self] in
            let result: Result<AssistantAnswer, AssistantError>
            do throws(AssistantError) {
                result = .success(try await service.ask(question, sessionID: sessionID, history: Array(history), locale: locale, policy: policy))
            } catch {
                result = .failure(error)
            }
            self?.finish(question: question, result: result)
        }
    }

    func cancel() { task?.cancel() }

    /// Removes the whole thread and the files kept beside it. Checked; says so if it couldn't.
    func deleteAll() {
        guard let log else { return }
        do {
            try log.deleteAll()
            try fileStore?.deleteAll()
            messages = []
            storageProblem = nil
        } catch {
            storageProblem = NSLocalizedString("The messages couldn't be deleted. Try again.", comment: "")
        }
    }

    // MARK: Files and links (ADR-594)

    func reportStorageProblem(_ text: String) { storageProblem = text }

    /// The folder that holds kept files, next to the thread.
    var fileStore: ChatFileStore? { Self.directory.map { ChatFileStore(directory: $0) } }

    /// Copies a file into the thread and adds its message. The message appears only when the copy
    /// was read back (right size, inside the thread's folder); otherwise the thread says so and
    /// nothing is added. False when it couldn't be kept.
    @discardableResult
    func keep(fileAt source: URL, named name: String? = nil, from sender: ChatMessage.Sender) -> Bool {
        guard let fileStore else {
            storageProblem = NSLocalizedString("This file couldn't be kept on this iPhone.", comment: "")
            return false
        }
        do {
            let file = try fileStore.keep(copyOf: source, named: name)
            return finishKeeping(file, from: sender, store: fileStore)
        } catch {
            storageProblem = Self.problem(for: error)
            return false
        }
    }

    /// The same for bytes that arrived in memory (a photo from the camera).
    @discardableResult
    func keep(data: Data, named name: String, from sender: ChatMessage.Sender) -> Bool {
        guard let fileStore else {
            storageProblem = NSLocalizedString("This file couldn't be kept on this iPhone.", comment: "")
            return false
        }
        do {
            let file = try fileStore.keep(data: data, named: name)
            return finishKeeping(file, from: sender, store: fileStore)
        } catch {
            storageProblem = Self.problem(for: error)
            return false
        }
    }

    private static func problem(for error: Error) -> String {
        if (error as? ChatFileStore.Failure) == .tooBig {
            return NSLocalizedString("That file is bigger than 25 MB, so it wasn't added.", comment: "")
        }
        return NSLocalizedString("This file couldn't be kept on this iPhone.", comment: "")
    }

    private func finishKeeping(_ file: ChatFile, from sender: ChatMessage.Sender, store: ChatFileStore) -> Bool {
        if receive(ChatMessage(sender: sender, content: .file(file))) { return true }
        // The thread couldn't take the message: don't leave an orphan file behind.
        try? FileManager.default.removeItem(at: store.url(for: file).deletingLastPathComponent())
        return false
    }

    private func finish(question: String, result: Result<AssistantAnswer, AssistantError>) {
        isSending = false
        task = nil
        switch result {
        case .success(let answer):
            receive(ChatMessage(sender: .doddy, content: .text(answer.answer.text)))
        case .failure(let failure):
            if failure != .cancelled { error = failure }
        }
    }

    // MARK: Where it lives

    /// Application Support/Messages/. UI-test launches get a new folder each time.
    static let directory: URL? = {
        let fileManager = FileManager.default
        if ProcessInfo.processInfo.arguments.contains("-inMemoryStore") {
            return fileManager.temporaryDirectory.appendingPathComponent("messages-\(UUID().uuidString)", isDirectory: true)
        }
        return try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Messages", isDirectory: true)
    }()


    static func defaultLog() -> ChatLogFile? {
        directory.map { ChatLogFile(url: $0.appendingPathComponent("messages.json")) }
    }
}
