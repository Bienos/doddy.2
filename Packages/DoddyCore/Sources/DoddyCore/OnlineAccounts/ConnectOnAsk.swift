import Foundation

/// What Doddy's server says the user can do, right in the conversation, so a refused tool can run
/// (ADR-511). It rides on the refusal; the error code stays what it always was, so builds that
/// don't know it behave as before.
public struct ConnectOffer: Codable, Equatable, Sendable {
    public enum Need: String, Sendable {
        case connect
        case switchOn = "switch_on"
        case morePermission = "more_permission"
        case reconnect
    }

    /// An online account id, or "websearch" (no account, a switch only).
    public let toolkit: String
    public let tool: String
    /// Kept as text so a value this build doesn't know never makes the whole refusal unreadable.
    public let need: String
    public let accountTitle: String
    public let toolTitle: String
    /// What the sign-in will ask the user to allow, in plain words. Empty for a switch.
    public let permissions: [String]

    public init(toolkit: String, tool: String, need: Need, accountTitle: String, toolTitle: String, permissions: [String]) {
        self.toolkit = toolkit
        self.tool = tool
        self.need = need.rawValue
        self.accountTitle = accountTitle
        self.toolTitle = toolTitle
        self.permissions = permissions
    }

    /// Nil for a need this build doesn't know: then no card is shown.
    public var kind: Need? { Need(rawValue: need) }
    public var needsSignIn: Bool { kind != nil && kind != .switchOn }
}

/// The card shown instead of "go to Settings". Text only; the app lays it out.
public struct ConnectCard: Equatable, Sendable {
    public let title: String
    public let lines: [String]
    /// What the sign-in will ask to allow; shown as a list.
    public let permissions: [String]
    public let confirmLabel: String
    public let cancelLabel: String
}

/// ADR-511, "connect when asked" (owner, 2026-10-19). Every account stays set up on Doddy's server,
/// but nothing is connected and every tool is off until the user asks for something that needs it.
/// Then the app offers to connect right there, instead of sending the user to Settings.
///
/// Rules this type enforces (UI-free, so they are tested on Linux):
/// - An offer exists only in answer to a tool call the agent made in this conversation, and only
///   when the server attached one to its refusal. Text from an email, the web or the agent can't
///   make one: there is no other way in.
/// - One offer at a time. It lasts ten minutes and belongs to the conversation it was made in;
///   End or a new conversation forgets it.
/// - It never runs the tool. After a connection, the agent is told and calls the tool again, which
///   goes through its own card and tap (ASK-01). Nothing here can approve anything.
/// - It keeps no arguments of the call: account, tool, conversation and time only.
public struct ConnectOnAsk: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// The card is up, waiting for the user.
        case offered
        /// The user tapped: signing in, or switching the tool on.
        case working
    }

    public struct Pending: Equatable, Sendable {
        public let offer: ConnectOffer
        public let toolCallID: String
        /// The voice controller's start number (ADR-458): a later conversation can't use it.
        public let conversation: Int
        public let offeredAt: Date
        public fileprivate(set) var phase: Phase
    }

    /// How a sign-in or switch ended, for the line the agent gets.
    public enum Ending: Equatable, Sendable {
        case connected
        case declined
        case canceled
        /// The user didn't allow what the tool needs on the provider's screen (ADR-511, D4).
        case notGranted
        case failed(String)
        case expired
    }

    public static let lifetime: TimeInterval = 600

    public private(set) var pending: Pending?

    public init() {}

    // MARK: Offering

    public enum Decision: Equatable, Sendable {
        /// Show this card; answer the tool call with `reply`.
        case offer(ConnectCard, reply: String)
        /// Another offer is still open: answer with `reply`, show nothing new.
        case busy(reply: String)
        /// Not something the user can fix here: answer as before (`VoiceToolReply.cloudFailed`).
        case none
    }

    /// A refused online-account call. `paused`: Pause all connections is on (ADR-134).
    public mutating func decide(
        _ error: OnlineAccountsError, tool: String, toolCallID: String, conversation: Int, paused: Bool, at now: Date
    ) -> Decision {
        guard !paused, case .server(_, _, _, _, let connect?) = error, let need = connect.kind, connect.tool == tool else { return .none }
        // A receipt that says the first try may have gone through outranks any offer (ADR-322).
        if error.receipt?.status == .outcomeUnknown { return .none }
        _ = expireIfNeeded(at: now)
        if let open = pending, open.conversation == conversation {
            return .busy(reply: Self.busy(open.offer))
        }
        pending = Pending(offer: connect, toolCallID: toolCallID, conversation: conversation, offeredAt: now, phase: .offered)
        return .offer(Self.card(for: connect, need: need), reply: Self.offered(connect))
    }

    /// The user tapped the card's button. True only once, for an open offer of this conversation.
    public mutating func tap(conversation: Int, at now: Date) -> Bool {
        guard expireIfNeeded(at: now) == nil, var open = pending, open.conversation == conversation, open.phase == .offered else { return false }
        open.phase = .working
        pending = open
        return true
    }

    /// "Not now". Ends the offer; the agent is told nothing was done.
    public mutating func decline(conversation: Int) -> String? {
        guard let open = pending, open.conversation == conversation, open.phase == .offered else { return nil }
        pending = nil
        return Self.ended(.declined, open.offer)
    }

    /// The server's answer to the sign-in (`complete`) or to the switch. "Connected" only when the
    /// server says the tool is now on; anything else is not.
    public mutating func finish(_ result: ToolkitResult, conversation: Int) -> (Ending, String)? {
        guard let open = pending, open.conversation == conversation, open.phase == .working else { return nil }
        pending = nil
        let ending = Self.ending(of: result, tool: open.offer.tool)
        return (ending, Self.ended(ending, open.offer))
    }

    /// The sign-in or switch couldn't be finished (no connection, the server refused).
    public mutating func fail(_ error: OnlineAccountsError, conversation: Int) -> String? {
        guard let open = pending, open.conversation == conversation, open.phase == .working else { return nil }
        pending = nil
        let ending: Ending = if case .server(_, let message, _, _, _) = error { .failed(message) } else { .failed(error.userMessage) }
        return Self.ended(ending, open.offer)
    }

    /// "Open in Mail instead" (ADR-511, D5): Mail opens with the email filled in, and the user sends
    /// it there. Ends the offer; nothing was connected and Doddy sent nothing.
    public mutating func openedMail(conversation: Int) -> String? {
        guard let open = pending, open.conversation == conversation, open.phase == .offered else { return nil }
        pending = nil
        return "opened: Mail opened with the email filled in, for the user to send there. Doddy didn't send it and \(open.offer.accountTitle) wasn't connected. "
            + "Don't say it was sent."
    }

    /// The Mail link for the card's "Open in Mail instead", only for a send to one plain address.
    /// Made when the card is shown and kept only while it is on screen.
    public static func mailInstead(for call: CloudToolCall) -> URL? {
        guard call.name == CloudToolName.sendEmail,
              case .string(let to)? = call.arguments["to"],
              case .string(let subject)? = call.arguments["subject"],
              case .string(let body)? = call.arguments["body"]
        else { return nil }
        return OpenLinks.email(address: to, subject: subject, body: body)
    }

    /// End, a new conversation, or the card was removed: forget the offer. Nothing is sent anywhere.
    public mutating func forget() {
        pending = nil
    }

    /// Drops an offer older than `lifetime` that the user never acted on. Returns the line for the
    /// agent when one expired.
    public mutating func expireIfNeeded(at now: Date) -> String? {
        guard let open = pending, open.phase == .offered, now.timeIntervalSince(open.offeredAt) >= Self.lifetime else { return nil }
        pending = nil
        return Self.ended(.expired, open.offer)
    }

    static func ending(of result: ToolkitResult, tool: String) -> Ending {
        switch result.receipt.status {
        case .succeeded:
            // The server's own view of the tool, not the receipt's words.
            return result.toolkit.tools.first(where: { $0.name == tool })?.enabled == true ? .connected : .failed(result.receipt.summary)
        case .canceled:
            return .canceled
        default:
            return result.receipt.errorCode == "permission_not_granted" ? .notGranted : .failed(result.receipt.summary)
        }
    }

    // MARK: What the user sees

    public static func card(for offer: ConnectOffer, need: ConnectOffer.Need) -> ConnectCard {
        let account = offer.accountTitle
        let asked = "You asked for: \(offer.toolTitle)."
        let onlyThis = "Only \"\(offer.toolTitle)\" is switched on. Everything else stays off until you ask for it."
        let nothingYet = "Nothing is done yet. Doddy still shows you exactly what it will do, and waits for you."
        let keeper = "Composio keeps the sign-in for Doddy's server. You can disconnect any time in Settings, Online accounts."
        switch need {
        case .switchOn:
            return ConnectCard(
                title: "Switch on \"\(offer.toolTitle)\"?",
                lines: [offer.toolkit == "websearch" ? "Web search is off." : "\(account) is connected, but this is off.", onlyThis, nothingYet],
                permissions: [], confirmLabel: "Switch on", cancelLabel: "Not now")
        case .connect:
            return ConnectCard(
                title: "Connect \(account)?",
                lines: [asked, "\(account) will ask you to sign in and allow:", onlyThis, nothingYet, keeper],
                permissions: offer.permissions, confirmLabel: "Connect \(account)", cancelLabel: "Not now")
        case .morePermission:
            return ConnectCard(
                title: "Give \(account) more access?",
                lines: [asked, "\(account) is connected, but not for this. It will ask you to sign in again and allow:", onlyThis, nothingYet, keeper],
                permissions: offer.permissions, confirmLabel: "Continue", cancelLabel: "Not now")
        case .reconnect:
            return ConnectCard(
                title: "Reconnect \(account)?",
                lines: [asked, "\(account)'s connection expired or can't be used. It will ask you to sign in and allow:", onlyThis, nothingYet, keeper],
                permissions: offer.permissions, confirmLabel: "Reconnect", cancelLabel: "Not now")
        }
    }

    // MARK: What the agent hears

    /// Tool-call answers that start with these did nothing (for What Doddy did, `ActivityEntry`).
    public static let toolReplyPrefixes = ["not connected:", "switched off:", "busy:"]

    /// The answer to the tool call when the card goes up. The call is answered at once, so it can't
    /// time out while the user signs in.
    public static func offered(_ offer: ConnectOffer) -> String {
        if offer.kind == .switchOn {
            return "switched off: \"\(offer.toolTitle)\" is switched off, so nothing was done. A card on screen lets the user switch it on. "
                + "Say in one short sentence that they can switch it on with the card, then wait. Don't call \(offer.tool) again until the app says it is on."
        }
        return "not connected: \(offer.accountTitle) isn't connected for \"\(offer.toolTitle)\", so nothing was done. A card on screen asks the user to connect \(offer.accountTitle). "
            + "Say in one short sentence that you need their OK to connect \(offer.accountTitle) first, and that nothing has been done yet. Then wait. "
            + "Don't call \(offer.tool) again until the app says \(offer.accountTitle) is connected."
    }

    static func busy(_ open: ConnectOffer) -> String {
        "busy: a card about \(open.accountTitle) is already on screen, so nothing was done. Ask the user to finish or close it first."
    }

    /// What the agent is told when the offer ends. Sent as information from the app, never as
    /// something the user said.
    public static func ended(_ ending: Ending, _ offer: ConnectOffer) -> String {
        let account = offer.accountTitle
        switch ending {
        case .connected:
            let what = offer.kind == .switchOn ? "\"\(offer.toolTitle)\" is switched on now" : "\(account) is connected now, and \"\(offer.toolTitle)\" is switched on"
            return "connected: \(what). Nothing has been done yet. If the user still wants it, call \(offer.tool) again with the details they gave; "
                + "its own card will show exactly what happens, and nothing is done before they answer it."
        case .declined:
            return "declined: the user chose not to \(offer.kind == .switchOn ? "switch on \"\(offer.toolTitle)\"" : "connect \(account)"). Nothing was done. Don't ask again unless they do."
        case .canceled:
            return "declined: connecting \(account) was canceled. Nothing was connected or done."
        case .notGranted:
            return "declined: \(account) wasn't connected, because the permission \"\(offer.toolTitle)\" needs wasn't given on the sign-in screen. Nothing was done."
        case .failed(let reason):
            return "failed: \(account) couldn't be \(offer.kind == .switchOn ? "switched on" : "connected"). Nothing was done. Reason: \(reason)"
        case .expired:
            return "declined: the card about \(account) timed out without an answer. Nothing was done."
        }
    }
}

/// The two things the connect card's button can do (ADR-511). Both only ask Doddy's server; the
/// server decides and records everything, and switches on the one tool after a verified sign-in.
public enum ConnectFlow {
    /// Sign in for one tool, through the provider's own page in the system sign-in sheet (the same
    /// path as Settings, RFC 8252). A closed or failed sheet completes as canceled, so the server
    /// removes anything the provider started. In demo mode (mock server) there is no sign-in page:
    /// the tap on the card, which is labelled Demo, stands in for it.
    public static func signIn(
        toolkit: String, forTool: String, client: any OnlineAccountsClient, authenticator: any WebAuthenticator
    ) async -> Result<ToolkitResult, OnlineAccountsError> {
        do {
            let attempt = try await client.connect(toolkit: toolkit, forTool: forTool)
            let result: CompletionResult
            if attempt.mode == .mock {
                result = .mock(approve: true)
            } else if let url = attempt.authorizationUrl {
                do {
                    let back = try await authenticator.authenticate(url: url, callbackScheme: attempt.callbackScheme)
                    result = ConnectionCallback.result(from: back, expectedScheme: attempt.callbackScheme, attemptId: attempt.attemptId) ?? .canceled
                } catch {
                    result = .canceled
                }
            } else {
                // A live server without a sign-in page can't be connected; say so and end the attempt.
                result = .canceled
            }
            return .success(try await client.complete(toolkit: toolkit, CompleteRequest(attemptId: attempt.attemptId, nonce: attempt.nonce, result: result)))
        } catch {
            return .failure(error)
        }
    }

    /// Switch on one tool of an account that is already connected (or web search).
    public static func switchOn(tool: String, client: any OnlineAccountsClient) async -> Result<ToolkitResult, OnlineAccountsError> {
        do {
            return .success(try await client.setSwitch(tool: tool, enabled: true))
        } catch {
            return .failure(error)
        }
    }
}
