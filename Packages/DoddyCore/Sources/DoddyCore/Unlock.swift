import Foundation

// MARK: Unlock as you go (ADR-324)

/// Something a request needs that the user hasn't allowed yet. Nothing is asked up front: the
/// card appears while the request is being handled, for exactly this one thing, and the request
/// runs again once the user has allowed it. Declining changes nothing.
public enum UnlockNeed: Equatable, Sendable {
    /// An iPhone connection switch in Settings, Connections, and its iOS permission.
    case connection(VoiceConnection)
    /// An online-account tool: its account may need connecting and its own switch is off.
    case onlineTool(String)

    /// What the card asks for, by the name the user knows.
    public var title: String {
        switch self {
        case .connection(let connection): connection.title
        case .onlineTool(let tool): CloudToolName.account(tool)
        }
    }
}

/// One tap on the card. A request needs one or two of these, in this order.
public enum UnlockStep: Equatable, Sendable, Identifiable {
    /// Turn the Settings, Connections switch on; iOS asks for its permission if it never did.
    case allowConnection(VoiceConnection)
    /// Connect the account in the system browser (same flow as Settings, Online accounts).
    case connectAccount(toolkit: String, title: String)
    /// Switch on the one tool the request needs. Connecting never does this by itself (ADR-097).
    case switchOnTool(tool: String, title: String)

    public var id: String {
        switch self {
        case .allowConnection(let connection): "connection:\(connection.rawValue)"
        case .connectAccount(let toolkit, _): "connect:\(toolkit)"
        case .switchOnTool(let tool, _): "switch:\(tool)"
        }
    }

    /// The button's label.
    public var action: String {
        switch self {
        case .allowConnection(let connection): "Allow \(connection.title)"
        case .connectAccount(_, let title): "Connect \(title)"
        case .switchOnTool(_, let title): "Switch on \"\(title)\""
        }
    }
}

/// The card's steps and how far the user got. `advance()` after each step the code verified.
public struct UnlockPlan: Equatable, Sendable {
    public let need: UnlockNeed
    public let steps: [UnlockStep]
    public private(set) var completed: Int

    public init(need: UnlockNeed, steps: [UnlockStep]) {
        self.need = need
        self.steps = steps
        completed = 0
    }

    public var current: UnlockStep? { completed < steps.count ? steps[completed] : nil }
    public var isComplete: Bool { completed >= steps.count }

    public func isDone(_ step: UnlockStep) -> Bool {
        guard let index = steps.firstIndex(of: step) else { return false }
        return index < completed
    }

    public mutating func advance() {
        guard !isComplete else { return }
        completed += 1
    }
}

extension UnlockNeed {
    /// The server refusals the user can resolve on the card. Anything else is a plain failure.
    /// A confirmation that expired is not one: the switch was on, the card simply waited too long.
    public static func from(_ error: OnlineAccountsError, tool: String) -> UnlockNeed? {
        guard case .server(let code, _, _, let receipt) = error else { return nil }
        switch code {
        case "capability_disabled":
            return receipt?.errorCode == "confirmation_required" ? nil : .onlineTool(tool)
        case "not_connected", "connection_expired", "permission_insufficient":
            return CloudToolName.needsAccount(tool) ? .onlineTool(tool) : nil
        default:
            return nil
        }
    }

    /// Whether the code alone says the account isn't usable (used when the catalog can't be read).
    public static func saysNotConnected(_ error: OnlineAccountsError) -> Bool {
        guard case .server(let code, _, _, _) = error else { return false }
        return ["not_connected", "connection_expired", "permission_insufficient"].contains(code)
    }
}

extension UnlockPlan {
    /// Steps for an online tool from what the server's catalog says right now: connect the account
    /// if it isn't connected, then switch the tool on if it is off. Web search has no account.
    /// Empty when the catalog says everything is already allowed (the refusal was something else).
    /// Without a catalog, `accountNotConnected` (from the error code) decides the first step.
    public static func onlineSteps(for tool: String, catalog: ToolsCatalog?, accountNotConnected: Bool) -> [UnlockStep] {
        let account = CloudToolName.account(tool)
        guard let catalog else {
            var steps: [UnlockStep] = []
            if accountNotConnected, CloudToolName.needsAccount(tool) {
                steps.append(.connectAccount(toolkit: Self.guessedToolkit(for: tool), title: account))
            }
            steps.append(.switchOnTool(tool: tool, title: CloudToolName.title(tool)))
            return steps
        }
        guard let toolkit = catalog.toolkits.first(where: { $0.tools.contains { $0.name == tool } }) else {
            return []
        }
        let view = toolkit.tools.first { $0.name == tool }
        var steps: [UnlockStep] = []
        if toolkit.hasAccount, toolkit.status != .connected {
            steps.append(.connectAccount(toolkit: toolkit.id, title: toolkit.title))
        }
        // `enabled` is false while the account is disconnected even if the switch row is on, so
        // after a connect the switch is checked again before this step runs.
        if view?.enabled != true {
            steps.append(.switchOnTool(tool: tool, title: view?.title ?? CloudToolName.title(tool)))
        }
        return steps
    }

    /// The server's toolkit ids, for the no-catalog case only.
    static func guessedToolkit(for tool: String) -> String {
        switch CloudToolName.account(tool) {
        case "Gmail": "gmail"
        case "Google Drive": "googledrive"
        case "Notion": "notion"
        case "Todoist": "todoist"
        case "Outlook": "outlook"
        default: "websearch"
        }
    }
}

extension VoiceToolReply {
    /// The user tapped Not now. The request stays undone and nothing was switched on.
    public static func unlockDeclined(_ need: UnlockNeed) -> String {
        "declined: the user chose not to let Doddy use \(need.title) right now. Nothing was switched on and nothing was done. Accept it in one short sentence; they can ask again whenever they want."
    }

    /// iOS refused, or refused earlier: the app can't ask again and the card says how to allow it.
    public static func unlockBlocked(_ connection: VoiceConnection) -> String {
        "failed: iPhone doesn't allow Doddy to use \(connection.title). The card on screen explains how to allow it in iPhone Settings. Nothing was done."
    }

    /// A step didn't go through (connect canceled, server said no). Nothing ran.
    public static func unlockFailed(_ step: UnlockStep, reason: String?) -> String {
        let what: String
        switch step {
        case .allowConnection(let connection): what = "\(connection.title) wasn't turned on"
        case .connectAccount(_, let title): what = "\(title) wasn't connected"
        case .switchOnTool(_, let title): what = "\"\(title)\" wasn't switched on"
        }
        let why = reason.map { " (\($0))" } ?? ""
        return "failed: \(what)\(why). Nothing was done. Tell the user in one sentence; they can try again."
    }
}
