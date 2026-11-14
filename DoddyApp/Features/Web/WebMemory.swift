import DoddyCore
import Foundation

/// The one model behind keeping notes and conversations on Doddy's server (ADR-603). Settings, the note
/// screens, the launch tasks and the voice controller all talk to it; the rules are `WebMemoryModel` in
/// DoddyCore, tested on Linux. Off until the person turns each kind on in Settings › Doddy on the web.
enum WebMemory {
    @MainActor static let shared = WebMemoryModel(
        makeClient: { await WebMemoryClientFactory.ready() },
        renewClient: { await WebMemoryClientFactory.renewed() },
        // Only the account that owns this iPhone's data gets it (decision 2026-11-12-local-data-owner).
        uploadGate: { DoddyAccountServers.localDataUpload() })

    /// The language of a conversation as the server wants it: the app's own choice, else the phone's.
    @MainActor static func language() -> String? {
        AppLanguageStore.chosen().code ?? Locale.current.language.languageCode?.identifier
    }
}
