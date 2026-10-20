import Foundation

/// Allowing an on-phone function from the conversation (ADR-562). When a tool is blocked only
/// because its switch in Settings › Connections is off, or because iOS hasn't been asked yet, the
/// conversation screen shows "Allow Doddy to use Calendar?" and one tap turns the switch on, with
/// iOS's own prompt first when iOS has never asked. The agent hears that a card is up, says one
/// line, and is told once the user has allowed it, so it tries once more. Only when iOS has
/// already said no does the card open Doddy's page in iPhone Settings: the one place iOS lets a
/// refused permission change.
///
/// Pure: the controller reads the switch and iOS's answer and passes them in, so the rules are
/// tested here, on any OS. Nothing here turns a switch on; only the user's tap on the card does,
/// and the action itself still asks for its own yes (ASK-01) when the agent tries again.
public enum ConnectionApproval {
    /// What iOS says about the permission a connection needs. Maps, Shortcuts, Messages and BLIK
    /// need none of their own and are always `.granted`.
    public enum SystemPermission: Equatable, Sendable {
        case granted
        /// iOS has never asked; its own prompt shows on the tap.
        case notAsked
        /// iOS said no before (or the iPhone restricts it). Only iPhone Settings can change it.
        case denied
    }

    /// Which button the card offers.
    public enum Card: Equatable, Sendable {
        /// "Allow": one tap turns the switch on, after iOS's own prompt when it hasn't asked.
        case allow
        /// "Open iPhone Settings": iOS said no before, so neither Doddy nor iOS can ask again.
        case openSystemSettings
    }

    public static func card(for permission: SystemPermission) -> Card {
        permission == .denied ? .openSystemSettings : .allow
    }

    /// What the Allow tap came to. `before` is iOS's answer before the tap; `switchIsOn` is the
    /// switch as read after it (it is stored on only when iOS allowed it).
    public enum Outcome: Equatable, Sendable {
        /// On, and iOS allows it: the card goes and the agent is told to try once more.
        case allowed
        /// The user said no in iOS's own prompt: nothing changed, and the card goes.
        case declined
        /// iOS had already said no, so no prompt could show: the card offers iPhone Settings.
        case blockedBySystem
    }

    public static func outcome(before: SystemPermission, switchIsOn: Bool) -> Outcome {
        if switchIsOn { return .allowed }
        return before == .denied ? .blockedBySystem : .declined
    }

    /// Sent to the agent as an "(app)" message once the switch is on and iOS allows it.
    public static func allowedMessage(_ connection: VoiceConnection) -> String {
        "The user just allowed \(connection.title) on screen. Carry on with what they asked: try it once more now. Don't thank them or mention the card."
    }

    /// Background context (Doddy doesn't answer it) after the user tapped Not now, or said no in
    /// iOS's prompt. Nothing changed.
    public static func declinedContext(_ connection: VoiceConnection) -> String {
        "The user chose not to allow \(connection.title), so nothing was looked up or changed. Don't try it again or ask about it unless they do."
    }
}

/// The access card on the conversation screen: one at a time, for one connection. Its steps:
/// Allow (working while iOS's prompt is up), then gone; or, when iOS had already said no, Open
/// iPhone Settings, then gone once Doddy is back in front and iOS allows it.
public struct ConnectionApprovalCard: Equatable, Sendable {
    public let connection: VoiceConnection
    public private(set) var card: ConnectionApproval.Card
    /// The Allow tap is being handled (iOS's own prompt may be up): a second tap does nothing.
    public private(set) var isWorking = false
    /// The user tapped Open iPhone Settings on this card. When Doddy is in front again the switch
    /// turns on if iOS now allows it: that tap and the user's own change there are the yes.
    public private(set) var sentToSettings = false

    public init(connection: VoiceConnection, permission: ConnectionApproval.SystemPermission) {
        self.connection = connection
        card = ConnectionApproval.card(for: permission)
    }

    /// The Allow tap. False (nothing to do) while one is running, or when the card offers iPhone
    /// Settings instead.
    public mutating func beginAllow() -> Bool {
        guard card == .allow, !isWorking else { return false }
        isWorking = true
        return true
    }

    /// The Allow tap's result. True when the card stays (now offering iPhone Settings); false when
    /// it goes.
    public mutating func finish(_ outcome: ConnectionApproval.Outcome) -> Bool {
        isWorking = false
        guard outcome == .blockedBySystem else { return false }
        card = .openSystemSettings
        return true
    }

    /// The Open iPhone Settings tap. False when the card offers Allow instead, or a tap is running.
    public mutating func sendToSettings() -> Bool {
        guard card == .openSystemSettings, !isWorking else { return false }
        sentToSettings = true
        return true
    }

    /// Back in Doddy after iPhone Settings: true only if this card sent the user there and iOS
    /// now allows it. Anything else leaves the card as it is.
    public func allowsOnReturn(_ now: ConnectionApproval.SystemPermission) -> Bool {
        sentToSettings && !isWorking && now == .granted
    }

    /// "Not now": the card may go unless a tap is running (iOS's own prompt answers that one).
    public var canDecline: Bool { !isWorking }
}
