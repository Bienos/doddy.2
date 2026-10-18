import Foundation

/// What the voice screen offers when an online-account tool couldn't run because the account isn't
/// connected or the tool's switch is off (ADR-483): a card in the conversation instead of "go to
/// Settings, Online accounts".
///
/// Decided from the server's catalog, never from the error code alone. The server checks the switch
/// before the connection, so a new user's first "check my email" comes back as "switched off" even
/// though Gmail was never connected; only the catalog says which step is missing.
public struct CloudAccessOffer: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Sign in at the provider, then switch this one tool on.
        case connect
        /// Connected once, but the access expired or isn't what Doddy expects: sign in again, then switch on.
        case reconnect
        /// The account is connected; only this tool's switch is off.
        case turnOn
    }

    public let kind: Kind
    /// Server id of the account, e.g. "gmail".
    public let toolkit: String
    /// The server's name for the account, e.g. "Gmail".
    public let accountTitle: String
    /// The tool the agent asked for, e.g. "check_email".
    public let tool: String
    /// The server's name for that tool's switch, e.g. "Check my email".
    public let toolTitle: String
    /// The server runs its mock adapter: the card says so, and no sign-in page opens.
    public let isDemo: Bool

    public init(kind: Kind, toolkit: String, accountTitle: String, tool: String, toolTitle: String, isDemo: Bool) {
        self.kind = kind
        self.toolkit = toolkit
        self.accountTitle = accountTitle
        self.tool = tool
        self.toolTitle = toolTitle
        self.isDemo = isDemo
    }

    /// Codes after which missing access may be the reason. Anything else (limits, provider failures,
    /// an expired confirmation, a write that may have gone through) never gets a sign-in offer.
    static let accessCodes: Set<String> = ["capability_disabled", "not_connected", "connection_expired", "permission_insufficient"]
    /// Receipt codes that arrive with `capability_disabled` but are about a confirmation, not access.
    static let confirmationCodes: Set<String> = ["confirmation_required", "earlier_outcome_unknown"]

    /// Cheap check before asking the server for its catalog: false means answer as before.
    public static func mayNeedAccess(_ error: OnlineAccountsError) -> Bool {
        guard case .server(let code, _, _, let receipt) = error, accessCodes.contains(code) else { return false }
        if receipt?.status == .outcomeUnknown { return false }
        if let receiptCode = receipt?.errorCode, confirmationCodes.contains(receiptCode) { return false }
        return true
    }

    /// Nil when the failure isn't about access, the tool isn't in the catalog, the server can't
    /// connect this account at all, or the tool is already on (the catalog is newer than the error).
    public static func decide(after error: OnlineAccountsError, tool: String, catalog: ToolsCatalog) -> CloudAccessOffer? {
        guard mayNeedAccess(error) else { return nil }
        guard let toolkit = catalog.toolkits.first(where: { $0.tools.contains { $0.name == tool } }),
              let view = toolkit.tools.first(where: { $0.name == tool })
        else { return nil }

        func offer(_ kind: Kind) -> CloudAccessOffer {
            CloudAccessOffer(kind: kind, toolkit: toolkit.id, accountTitle: toolkit.title, tool: view.name,
                             toolTitle: view.title, isDemo: catalog.mode == .mock)
        }
        // Web search: no account, only the switch.
        guard toolkit.hasAccount else { return view.enabled ? nil : offer(.turnOn) }
        switch toolkit.status {
        case .unavailable:
            // This server has no settings for the account; signing in can't work.
            return nil
        case .disconnected, .connecting:
            // A pending attempt is replaced by a new Connect on the server.
            return offer(.connect)
        case .expired, .permissionInsufficient:
            return offer(.reconnect)
        case .connected, .error:
            // `.error` rows still run on the server; only the switch can be missing.
            return view.enabled ? nil : offer(.turnOn)
        }
    }
}

/// How a tap on the card ended. Only `.ready` lets the app tell the agent to try again.
public enum CloudAccessOutcome: Equatable, Sendable {
    /// The server confirmed the account is connected and this tool is on.
    case ready
    /// The user closed the sign-in page. Nothing was connected or switched on.
    case canceled
    /// Shown on the card, in the server's or the app's words.
    case failed(String)
}

public enum CloudAccess {
    /// The tap on the card: sign in if needed, then switch on exactly the tool that was asked for,
    /// nothing else. Every step is the server's answer; a failure never looks like success.
    ///
    /// The switch goes on only because the card names it ("Connect Gmail and turn on Check my
    /// email"): the tap is the user's choice for that one tool. Other Gmail tools stay off, and a
    /// write still waits for its own confirmation card.
    public static func open(
        _ offer: CloudAccessOffer, client: any OnlineAccountsClient, authenticator: any WebAuthenticator
    ) async -> CloudAccessOutcome {
        do {
            if offer.kind != .turnOn {
                let attempt = try await client.connect(toolkit: offer.toolkit)
                let result: CompletionResult
                if attempt.mode == .mock || attempt.authorizationUrl == nil {
                    // Demo server: the tap on the card is the approval; no fake sign-in page is shown.
                    result = .mock(approve: true)
                } else {
                    do {
                        let url = try await authenticator.authenticate(url: attempt.authorizationUrl!, callbackScheme: attempt.callbackScheme)
                        result = ConnectionCallback.result(from: url, expectedScheme: attempt.callbackScheme, attemptId: attempt.attemptId) ?? .canceled
                    } catch {
                        result = .canceled
                    }
                }
                // Always completed, even when canceled, so the server closes the attempt.
                let done = try await client.complete(
                    toolkit: offer.toolkit, CompleteRequest(attemptId: attempt.attemptId, nonce: attempt.nonce, result: result))
                if done.receipt.status == .canceled { return .canceled }
                guard done.receipt.status == .succeeded, done.toolkit.status == .connected else {
                    return .failed(done.receipt.summary)
                }
            }
            let switched = try await client.setSwitch(tool: offer.tool, enabled: true)
            guard switched.toolkit.tools.first(where: { $0.name == offer.tool })?.enabled == true else {
                return .failed(switched.receipt.summary)
            }
            return .ready
        } catch {
            return .failed(error.userMessage)
        }
    }

    /// The tool's reply while the card is on screen, instead of "connect it in Settings, Online accounts".
    public static func agentReply(_ offer: CloudAccessOffer) -> String {
        let missing: String
        switch offer.kind {
        case .connect: missing = "\(offer.accountTitle) isn't connected"
        case .reconnect: missing = "\(offer.accountTitle) needs to be connected again"
        case .turnOn: missing = "\"\(offer.toolTitle)\" is switched off"
        }
        return "failed: \(missing). A card on screen lets the user fix it with one tap. Tell them in one short sentence to tap it; "
            + "don't mention Settings. If they do, the app will tell you to try again. Nothing was done."
    }

    /// The "(app)" message after `.ready`, so the agent does what the user asked without being asked twice.
    public static func agentMessage(_ offer: CloudAccessOffer) -> String {
        let done = offer.kind == .turnOn
            ? "switched on \"\(offer.toolTitle)\""
            : "connected \(offer.accountTitle) and switched on \"\(offer.toolTitle)\""
        return "The user tapped the card on screen and \(done); the server confirmed it. Do what they asked again now with \(offer.tool), once. Don't mention the card."
    }
}
