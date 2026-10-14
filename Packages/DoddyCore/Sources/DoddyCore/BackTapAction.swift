import Foundation

/// What "Talk to Doddy" does when Back Tap, the Action Button, Siri or the Control Center
/// control runs it (Settings → Back Tap and Siri). The default starts a conversation, as it
/// always did. "Open Doddy" only brings the app forward, with no microphone and no island.
///
/// The app can't choose the Dynamic Island's size: iOS decides it. So there is no size setting.
public enum BackTapAction: String, CaseIterable, Sendable {
    case conversation
    case openApp

    /// The stored choice, or the default when none is (or an unknown one is) stored.
    public static func stored(_ raw: String?) -> BackTapAction {
        raw.flatMap(BackTapAction.init(rawValue:)) ?? .conversation
    }

    /// Whether this action starts a voice conversation.
    public var startsConversation: Bool { self == .conversation }
}
