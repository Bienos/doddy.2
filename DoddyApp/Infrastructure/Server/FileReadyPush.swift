import DoddyCore
import Foundation
import os

/// "Tell me when the file is done" (owner, 9 Nov 2026). When Doddy starts making a file (`make_document`, ADR-564), the
/// file's private link goes to the messaging server, which asks Doddy's own server whether the file is done and sends one
/// notification with fixed words. Best effort and silent: it only decides whether a notification comes, so a failure
/// changes nothing on screen and nothing is claimed. The file itself shows up in Messages and Files as before.
/// "What leaves this iPhone" has a row for it (`fileReady`).
@MainActor
enum FileReadyPush {
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "file-ready-push")

    /// Registers a file that is still being made. A ready or failed file, or a link that isn't https, is left alone.
    static func watch(_ document: RunDocument) {
        guard document.status == .working, document.url.scheme?.lowercased() == "https" else { return }
        let link = document.url
        let language = ConversationLanguage.stored() == .polish ? "pl" : "en"
        Task {
            guard let client = ServerConfig.client() else { return }
            do {
                let outcome = try await client.watchFile(link: link, language: language)
                // The outcome only, never the link.
                log.notice("file watch: \(String(describing: outcome), privacy: .public)")
            } catch {
                log.notice("file watch failed: \(LogSafeError.kind(of: error), privacy: .public)")
            }
        }
    }
}
