import Foundation

/// The Mute and Unmute buttons on the Dynamic Island and the Lock Screen (ADR-131). Muting stays open:
/// anyone may silence Doddy, even on a locked iPhone. Unmuting starts him listening again, so it needs
/// the iPhone unlocked: its intent asks iOS for Face ID or the passcode first (`needsUnlockedIPhone`),
/// and the app checks again when it runs (`decide`). The rules are here, tested on Linux; the intents are
/// `MuteDoddyIntent` and `UnmuteDoddyIntent` in `Shared/VoiceActivity`.
public enum IslandMute {
    public enum Button: Sendable {
        case mute, unmute
    }

    public enum Decision: Equatable, Sendable {
        /// The conversation's mute switch is flipped.
        case toggle
        /// The conversation is already as the button asks (the island was a step behind); nothing changes.
        case nothing
        /// Unmute refused: the iPhone is locked, so the microphone stays off.
        case refusedLocked
    }

    /// True for the button whose intent needs the iPhone unlocked before iOS runs it
    /// (`authenticationPolicy = .requiresAuthentication`).
    public static func needsUnlockedIPhone(_ button: Button) -> Bool {
        switch button {
        case .mute: false
        case .unmute: true
        }
    }

    /// What a button does now. The conversation only has a toggle, so each button flips it only when the
    /// island shows the state that button changes: Mute can never unmute, and Unmute can never mute.
    /// `shownMuted` is what the island shows (nil when this process has no island to read).
    public static func decide(_ button: Button, shownMuted: Bool?, iPhoneUnlocked: Bool) -> Decision {
        switch button {
        case .mute:
            return shownMuted == false ? .toggle : .nothing
        case .unmute:
            guard iPhoneUnlocked else { return .refusedLocked }
            return shownMuted == true ? .toggle : .nothing
        }
    }
}
