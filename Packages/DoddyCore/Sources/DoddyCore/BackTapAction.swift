import Foundation

/// What "Talk to Doddy" does when Back Tap, the Action Button, Siri or the Control Center
/// control runs it (Settings → Back Tap and Siri).
///
/// - `conversation`: starts a conversation, and the Dynamic Island opens up with Doddy's
///   greeting. This is the default.
/// - `smallIsland`: starts a conversation, but the island stays the small strip at the top.
/// - `openApp`: only brings the app forward. No microphone, no island.
///
/// The app asks iOS to open the island once (an alert update); iOS decides the final size, so
/// this is a request, not a guarantee.
public enum BackTapAction: String, CaseIterable, Sendable {
    case conversation
    case smallIsland
    case openApp

    /// The stored choice, or the default when none is (or an unknown one is) stored.
    public static func stored(_ raw: String?) -> BackTapAction {
        raw.flatMap(BackTapAction.init(rawValue:)) ?? .conversation
    }

    /// Whether this action starts a voice conversation.
    public var startsConversation: Bool { self != .openApp }

    /// Whether the island is asked to open up with the greeting.
    public var opensIsland: Bool { self == .conversation }
}
