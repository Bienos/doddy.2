import Foundation

// Swift mirror of the online-account tools API v1 (backend/src/tools/contracts.ts): Gmail, Google
// Drive, Notion and Todoist through Composio, and web search through Monid (no account). Both sides decode the shared fixtures in
// contracts/online-accounts/, written by the backend (`npm run fixtures`).

public enum ToolkitStatus: String, Codable, Sendable {
    /// This server has no settings for the account, so it cannot be connected here.
    case unavailable
    case disconnected, connecting, connected
    case permissionInsufficient = "permission_insufficient"
    case expired, error
}

public enum ToolRisk: String, Codable, Sendable { case read, write }

/// One switch in Settings. `enabled` is true only if the user switched it on and the account is
/// connected with an acceptable grant, as judged by the server.
public struct ToolView: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let title: String
    public let blurb: String
    public let risk: ToolRisk
    public let enabled: Bool

    public var id: String { name }
}

public struct ToolkitView: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Plain words about what Doddy can and cannot do with the account.
    public let access: String
    /// False for web search: nothing to connect, only the switch. Older servers don't send it.
    public let needsAccount: Bool?
    public let status: ToolkitStatus
    public let reason: ConnectionReason?
    public let connectedAt: String?
    public let remoteCleanup: RemoteCleanup
    public let tools: [ToolView]
}

public struct ToolsCatalog: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let toolkits: [ToolkitView]
}

extension ToolkitView {
    /// True for accounts (Gmail, …); false for sections like web search that have only a switch.
    public var hasAccount: Bool { needsAccount ?? true }
}

/// Sanitized record of one connect, switch, read or write. Never contains message, task or file content.
public struct OnlineToolReceipt: Codable, Equatable, Sendable, Identifiable {
    public enum Operation: String, Codable, Sendable {
        case connect, disconnect, read, write
        case switchTool = "switch"
    }

    public let operationId: UUID
    public let operation: Operation
    public let toolkit: String
    public let tool: String?
    public let timestamp: String
    public let mode: ConnectedAppsMode
    public let status: ReceiptStatus
    public let summary: String
    public let errorCode: String?
    public let providerReference: String?

    public var id: UUID { operationId }
}

public struct ToolkitResult: Codable, Equatable, Sendable {
    public let toolkit: ToolkitView
    public let receipt: OnlineToolReceipt
}

public struct ToolPreview: Codable, Equatable, Sendable {
    public let title: String
    public let lines: [String]
    public let confirmLabel: String
}

public struct PrepareResult: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let tool: String
    public let preview: ToolPreview
    public let approvalId: UUID
    public let expiresAt: String
    /// The same write ran in the last day (ADR-322); nil otherwise and from older servers.
    public let earlier: EarlierWrite?
}

/// What the server knows about an earlier run of the same write (ADR-322).
public struct EarlierWrite: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case succeeded
        case outcomeUnknown = "outcome_unknown"
        /// It may have gone through, and the server's look found it there.
        case found
    }

    public let status: Status
    /// ISO time it finished.
    public let at: String
}

public struct RunResult: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let tool: String
    /// Written for the voice agent: states only what the provider returned.
    public let text: String
    public let count: Int
    public let truncated: Bool
    /// Writes: the provider's id for the draft or task (ADR-322). Stays on the phone.
    public let externalId: String?
    /// True when the server answered a repeated run of an approval that already succeeded:
    /// nothing ran again.
    public let replayed: Bool?
    public let receipt: OnlineToolReceipt
}

public struct OnlineReceiptsResponse: Codable, Equatable, Sendable {
    public let receipts: [OnlineToolReceipt]
}

public struct OnlineErrorBody: Codable, Equatable, Sendable {
    public struct Detail: Codable, Equatable, Sendable {
        public let code: String
        public let message: String
        public let correlationId: String
        public let retryAfterSeconds: Int?
        public let receipt: OnlineToolReceipt?
    }
    public let error: Detail
}

// MARK: Tools the voice agent may call

/// The online-account tools, by the name the voice agent uses. The server owns the real list;
/// this one only lets the app route a call and say whether it needs an on-screen confirmation.
public enum CloudToolName {
    public static let checkEmail = "check_email"
    public static let draftEmail = "draft_email"
    public static let findDriveFile = "find_drive_file"
    public static let searchNotion = "search_notion"
    public static let listTodoistTasks = "list_todoist_tasks"
    public static let addTodoistTask = "add_todoist_task"
    /// Todoist complete and move (ADR-303): the card shows the task as Todoist has it.
    public static let completeTodoistTask = "complete_todoist_task"
    public static let moveTodoistTask = "move_todoist_task"
    /// One whole email, the newest that matches, when the user asks (ADR-304). Off until switched on.
    public static let readEmail = "read_email"
    /// A reply draft in the newest matching email's conversation (round 5). Never sent.
    public static let draftEmailReply = "draft_email_reply"
    /// One Notion page's text, the best match among pages shared with Doddy (round 5). Off until switched on.
    public static let readNotionPage = "read_notion_page"
    /// Microsoft Outlook (ADR-340): the same reads and draft as Gmail, plus reading its calendar.
    public static let checkOutlookEmail = "check_outlook_email"
    public static let readOutlookEmail = "read_outlook_email"
    public static let draftOutlookEmail = "draft_outlook_email"
    public static let readOutlookCalendar = "read_outlook_calendar"
    /// Gmail writes that send or change something (ADR-485). Each runs only on a tap on the card
    /// that shows exactly what will happen (ASK-01); nothing deletes for good.
    public static let sendEmail = "send_email"
    public static let replyToEmail = "reply_to_email"
    public static let forwardEmail = "forward_email"
    public static let changeEmail = "change_email"
    public static let trashEmail = "trash_email"
    /// Google Calendar (ADR-486) and Outlook calendar and mail writes (ADR-486, ADR-487): name →
    /// spoken title, account, write. Every write waits for a tap on its card (ASK-01).
    static let more: [String: (title: String, account: String, write: Bool)] = [
        "read_google_calendar": ("Read the Google Calendar", "Google Calendar", false),
        "create_google_event": ("Add a Google Calendar event", "Google Calendar", true),
        "change_google_event": ("Change a Google Calendar event", "Google Calendar", true),
        "delete_google_event": ("Delete a Google Calendar event", "Google Calendar", true),
        "answer_google_invite": ("Answer a Google Calendar invitation", "Google Calendar", true),
        "create_outlook_event": ("Add an Outlook event", "Outlook", true),
        "change_outlook_event": ("Change an Outlook event", "Outlook", true),
        "delete_outlook_event": ("Delete an Outlook event", "Outlook", true),
        "accept_outlook_invite": ("Accept an Outlook invitation", "Outlook", true),
        "decline_outlook_invite": ("Decline an Outlook invitation", "Outlook", true),
        "send_outlook_email": ("Send an Outlook email", "Outlook", true),
        "reply_outlook_email": ("Send an Outlook reply", "Outlook", true),
        "forward_outlook_email": ("Forward an Outlook email", "Outlook", true),
        "move_outlook_email": ("Archive or bin an Outlook email", "Outlook", true),
        "mark_outlook_email": ("Mark an Outlook email", "Outlook", true),
        // ADR-488.
        "rename_todoist_task": ("Rename a task", "Todoist", true),
        "create_notion_page": ("Create a Notion page", "Notion", true),
        "append_notion_page": ("Add to a Notion page", "Notion", true),
        "trash_notion_page": ("Move a Notion page to the trash", "Notion", true),
        "create_drive_doc": ("Create a Google Doc", "Google Drive", true),
    ]
    /// Web search through Monid on Doddy's server. No account; only a switch in Settings.
    public static let webSearch = "web_search"

    public static let all: Set<String> = Set<String>([checkEmail, draftEmail, readEmail, draftEmailReply, findDriveFile, searchNotion,
                                          readNotionPage, listTodoistTasks, addTodoistTask, completeTodoistTask,
                                          moveTodoistTask, webSearch, checkOutlookEmail, readOutlookEmail,
                                          draftOutlookEmail, readOutlookCalendar, sendEmail, replyToEmail, forwardEmail,
                                          changeEmail, trashEmail]).union(more.keys)
    /// These change something in the user's account and wait for a tap on the card.
    public static let writes: Set<String> = Set<String>([draftEmail, draftEmailReply, draftOutlookEmail, addTodoistTask, completeTodoistTask, moveTodoistTask,
                                             sendEmail, replyToEmail, forwardEmail, changeEmail, trashEmail])
        .union(more.filter { $0.value.write }.keys)

    public static func isWrite(_ name: String) -> Bool { writes.contains(name) }

    /// Spoken-friendly name, used in replies to the agent.
    public static func title(_ name: String) -> String {
        switch name {
        case checkEmail: "Check my email"
        case draftEmail: "Draft an email"
        case findDriveFile: "Find a Drive file"
        case searchNotion: "Search Notion"
        case listTodoistTasks: "List my tasks"
        case addTodoistTask: "Add a task"
        case completeTodoistTask: "Complete a task"
        case moveTodoistTask: "Move a task"
        case readEmail: "Read an email"
        case draftEmailReply: "Draft a reply"
        case readNotionPage: "Read a Notion page"
        case checkOutlookEmail: "Check Outlook email"
        case readOutlookEmail: "Read an Outlook email"
        case draftOutlookEmail: "Draft an Outlook email"
        case readOutlookCalendar: "Read the Outlook calendar"
        case webSearch: "Search the web"
        case sendEmail: "Send an email"
        case replyToEmail: "Send a reply"
        case forwardEmail: "Forward an email"
        case changeEmail: "Archive or mark an email"
        case trashEmail: "Move an email to Trash"
        default: more[name]?.title ?? name
        }
    }

    public static func account(_ name: String) -> String {
        switch name {
        case checkEmail, draftEmail, readEmail, draftEmailReply, sendEmail, replyToEmail, forwardEmail, changeEmail, trashEmail: "Gmail"
        case findDriveFile: "Google Drive"
        case searchNotion, readNotionPage: "Notion"
        case checkOutlookEmail, readOutlookEmail, draftOutlookEmail, readOutlookCalendar: "Outlook"
        case webSearch: "Web search"
        default: more[name]?.account ?? "Todoist"
        }
    }

    /// Tools that work without connecting an account.
    public static func needsAccount(_ name: String) -> Bool { name != webSearch }
}

/// A tool call from the voice agent. Arguments are passed on exactly as received.
public struct CloudToolCall: Equatable, Sendable {
    public let name: String
    public let arguments: [String: JSONValue]

    public init(name: String, arguments: [String: JSONValue]) {
        self.name = name
        self.arguments = arguments
    }

    public var isWrite: Bool { CloudToolName.isWrite(name) }
}
