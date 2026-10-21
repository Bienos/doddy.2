import Foundation

/// When a voice conversation asks iOS to open its Dynamic Island up into the big, expanded island
/// for a few seconds (ADR-570). The app does that with an alert update of the Live Activity; iOS
/// shows it only while Doddy is not the app on screen, plays its alert sound with it and decides
/// the final size, so every "yes" here is a request, not a promise.
///
/// The island opens up when Doddy starts speaking: his first words (the greeting, "Hey Pat,
/// what's up?") and the start of each answer to something the user said. Never twice for one
/// answer (the provider can flip between speaking and listening inside one), never while the
/// app is on screen (iOS wouldn't show it, and the greeting's turn would be spent), and not
/// within `minimumGap` of the last one, because each one also plays a sound.
public struct IslandExpansion: Equatable, Sendable {
    /// The shortest time between two requests.
    public static let minimumGap: TimeInterval = 20

    /// Off when Settings › Back Tap and Siri says "Small island".
    public let isOn: Bool
    /// True until Doddy's first words have opened the island, and again after the user speaks.
    private var due = true
    private var lastOpened: Date?

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    /// The choice in Settings › Back Tap and Siri: everything but "Small island" opens it up.
    public init(_ action: BackTapAction) {
        self.init(isOn: action != .smallIsland)
    }

    /// Doddy just started speaking. True when the island should open up now; the next one is
    /// due only after the user has said something.
    public mutating func doddyStartedSpeaking(at now: Date, appOnScreen: Bool) -> Bool {
        guard isOn, due, !appOnScreen else { return false }
        if let lastOpened, now.timeIntervalSince(lastOpened) < Self.minimumGap { return false }
        lastOpened = now
        due = false
        return true
    }

    /// The user said something (their words arrived from the provider).
    public mutating func userSpoke() {
        due = true
    }
}
