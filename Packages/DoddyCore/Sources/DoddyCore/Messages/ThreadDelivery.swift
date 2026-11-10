import Foundation

/// What Doddy finished in the background arrives in Messages as his own message (owner, 10 Nov 2026: "on potem to
/// wysyła w wiadomościach swoich na apce z opisem"): a task he researched, or a file he made. The person reads it
/// there, taps through to everything, and shares the file from it. Plain Swift for the Linux tests.
///
/// Only what Doddy's server reported is said: "done" only for a task the server marked done, with the server's own
/// short answer; a file is "being made" until the server lists it ready. Nothing here sends anything anywhere.
public enum ThreadDelivery {
    /// The bubble keeps the start of the task's answer; the whole result opens from it.
    public static let answerLimit = 600

    /// The message for a task that has just finished, or nil when it hasn't (still running, cancelled, unknown).
    /// Its id is the task's own, so it is saved once however often the app looks, and the screen can open the
    /// task's result from it.
    public static func errand(_ errand: StoredErrand, now: Date) -> ThreadMessage? {
        let polish = errand.draft.language.lowercased().hasPrefix("pl")
        let title = errand.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        switch errand.state {
        case .done:
            guard let result = errand.result else { return nil }
            let answer = clipped(result.answer.trimmingCharacters(in: .whitespacesAndNewlines))
            let head = polish ? "Gotowe: „\(title)”." : "Done: “\(title)”."
            let tail = polish ? "Całość, ze źródłami, otworzysz poniżej." : "Everything, with the sources, opens below."
            text = [head, answer, tail].filter { !$0.isEmpty }.joined(separator: "\n\n")
        case .failed:
            let reason = errand.failure ?? .unknown
            text = polish
                ? "Nie udało mi się dokończyć: „\(title)”. \(polishReason(reason)) Poproś mnie jeszcze raz, jeśli nadal tego chcesz."
                : "I couldn't finish “\(title)”: \(reason.shortReason). Ask me again if you still want it."
        case .draft, .queued, .running, .cancelled, .unknown:
            return nil
        }
        return ThreadMessage(id: errand.id, sender: .doddy, text: text, createdAt: now, delivery: .sent, basis: .general)
    }

    /// The message for a file Doddy started making in a voice conversation. The file opens from it and is shared
    /// from it once ready; until then its page says it is still being made. Nil when nothing can be shown.
    public static func document(_ document: RunDocument, polish: Bool, now: Date, id: UUID = UUID()) -> ThreadMessage? {
        guard let file = ThreadDocument(document) else { return nil }
        let name = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = name.isEmpty ? file.label : name
        let text: String
        switch document.status {
        case .ready:
            text = polish ? "Proszę, gotowe: „\(shown)”." : "Here it is: “\(shown)”."
        case .working:
            text = polish
                ? "Robię to dla ciebie: „\(shown)”. Zajmie minutę lub dwie; otworzysz to tutaj."
                : "I'm making “\(shown)” for you. It takes a minute or two; it opens from here."
        case .failed:
            return nil
        }
        return ThreadMessage(id: id, sender: .doddy, text: text, createdAt: now, delivery: .sent, basis: .general, document: file)
    }

    /// Whether the thread already has a bubble for this file, so a second look adds nothing.
    public static func hasDocument(_ document: RunDocument, in thread: [ThreadMessage]) -> Bool {
        let id = ThreadAttachments.documentID(of: document.url)
        return thread.contains { message in
            guard let url = message.document?.url else { return false }
            if let id { return ThreadAttachments.documentID(of: url) == id }
            return url == document.url
        }
    }

    /// The words above a file card, when there are any besides the file's own name.
    public static func caption(of message: ThreadMessage) -> String? {
        guard let document = message.document else { return nil }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == document.name.trimmingCharacters(in: .whitespacesAndNewlines) || text == document.label
            ? nil : text
    }

    static func clipped(_ text: String) -> String {
        guard text.count > answerLimit else { return text }
        let cut = text.prefix(answerLimit)
        let end = cut.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? cut.endIndex
        return String(cut[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func polishReason(_ reason: ErrandFailureCode) -> String {
        switch reason {
        case .interrupted: "Serwer przerwał pracę w połowie."
        case .timeLimit: "Trwało to dłużej niż limit czasu."
        case .refused: "Model AI odmówił tego zadania."
        case .providerError: "Usługa AI miała problem."
        case .unreadableResult: "Nie dało się sprawdzić wyniku, więc go nie pokazuję."
        case .unknown: "Powód jest nieznany."
        }
    }
}
