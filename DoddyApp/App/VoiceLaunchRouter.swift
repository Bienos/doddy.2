import Observation

/// Carries "open the voice screen" from the shortcut intent to the UI. A flag rather than a
/// callback because on a cold launch the intent can run before any view exists.
@MainActor
@Observable
final class VoiceLaunchRouter {
    static let shared = VoiceLaunchRouter()

    private(set) var isRequested = false

    func requestConversation() { isRequested = true }
    func clear() { isRequested = false }
}
