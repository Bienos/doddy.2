/// One voice conversation at a time across the whole app (ADR-496).
///
/// The voice screen and "Hey Doddy" each make their own conversation, and each one's own guards
/// only stop it from starting twice. This gate is shared: a start goes ahead only if no *other*
/// conversation is still starting, connecting or talking.
///
/// It remembers who asked last and asks the caller whether that one is still busy, instead of
/// waiting to be told the conversation ended. A conversation that ends in any way (a failure, a
/// start that never got going, being freed) can therefore never leave the gate shut and voice
/// stuck until the app restarts.
public struct VoiceConversationGate<Owner: AnyObject> {
    public enum Decision: Equatable, Sendable {
        /// Start: no other conversation is busy. The asker is now the one the gate remembers.
        case go
        /// Don't start: another conversation is starting or live.
        case anotherIsRunning
    }

    private weak var holder: Owner?

    public init() {}

    /// `isBusy` says whether a conversation is starting, connecting or talking. The same owner
    /// asking again always goes ahead (its own guards decide whether it really starts again).
    public mutating func request(_ owner: Owner, isBusy: (Owner) -> Bool) -> Decision {
        if let holder, holder !== owner, isBusy(holder) { return .anotherIsRunning }
        holder = owner
        return .go
    }

    /// The conversation that is starting or live, if any, so a screen can show it instead of
    /// starting another.
    public func running(isBusy: (Owner) -> Bool) -> Owner? {
        guard let holder, isBusy(holder) else { return nil }
        return holder
    }
}
