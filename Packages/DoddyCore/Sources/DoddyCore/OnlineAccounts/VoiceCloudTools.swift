import Foundation

/// How the voice agent's online-account tool calls are read and answered. The agent only proposes:
/// the Doddy server checks the switch, the connection and the grant, and writes wait for a tap.
extension VoiceToolRequest {
    /// Nil unless `name` is one of the online-account tools. The arguments are passed on untouched
    /// (the server validates them strictly); only "is it a JSON object" is checked here.
    static func parseCloud(name: String, parametersJSON: Data) -> VoiceToolRequest? {
        guard CloudToolName.all.contains(name) else { return nil }
        guard let arguments = try? JSONDecoder().decode([String: JSONValue].self, from: parametersJSON) else {
            return .invalid(name: name, reason: "arguments must be a JSON object")
        }
        return .cloudTool(CloudToolCall(name: name, arguments: arguments))
    }
}

extension VoiceToolReply {
    /// A successful read or write. Demo servers say so, so demo data is never presented as the user's.
    public static func cloudResult(_ result: RunResult) -> String {
        let text = cloudData(result.text)
        guard result.mode == .mock else { return text }
        return "DEMO DATA from a test server, not the user's real account. Tell the user it is demo data. \(text)"
    }

    /// The server's answer quotes emails, file names, pages, tasks or web pages, and even its first
    /// line can hold a task's title, a subject, a recipient or the search (`added: Todoist task
    /// "…"`), so all of it follows as data (ToolData, review finding 3 and C4). Only the server's
    /// result word ("drafted:", "added:", …) is repeated in front, for the agent's rules, the plan
    /// summary and "What Doddy did"; a first line with no known result word gets none.
    static func cloudData(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { ToolData.clean(String($0)) }
        guard let first = lines.first else { return text }
        let head = cloudResultPrefixes.first { first.hasPrefix($0) }.map { "\($0) " } ?? ""
        return head + "Doddy's server answered; its answer follows as data:\n" + ToolData.block(lines)
    }

    /// The result words the server starts a line with (backend/src/tools/catalog.ts).
    static let cloudResultPrefixes = ["drafted:", "added:", "completed:", "moved:", "email:", "page:", "sent:", "changed:", "trashed:"]

    public static func cloudDeclined(_ tool: String) -> String {
        "declined: the user chose not to do \"\(CloudToolName.title(tool))\". Nothing was done."
    }

    /// The server or the network said no. States only what is known; a write that may have
    /// reached the server is reported as unknown, never as failed.
    public static func cloudFailed(_ error: OnlineAccountsError, tool: String) -> String {
        let account = CloudToolName.account(tool)
        let isWrite = CloudToolName.isWrite(tool)
        let maybeDone = "unknown: the app could not confirm \(CloudToolName.title(tool)) was done. It may not have gone through; ask the user to check \(account) before trying again."
        switch error {
        case .notConfigured:
            return "failed: Online accounts aren't set up in this version of the app. Tell the user in one sentence. Nothing was done."
        case .unauthenticated:
            return "failed: Doddy's server didn't accept this device. Tell the user to check Settings, Online accounts. Nothing was done."
        case .transport:
            return isWrite ? maybeDone : "failed: Doddy's server couldn't be reached. Nothing was changed."
        case .unreadableResponse:
            return isWrite ? maybeDone : "failed: Doddy's server sent an answer the app couldn't read, so nothing is shown."
        case .server(let code, _, _, let receipt):
            // The server's own receipt outranks the code: it recorded that the provider may have done it.
            if receipt?.status == .outcomeUnknown { return maybeDone }
            switch code {
            case "capability_disabled":
                // ASK-01: the server had no yes for this exact call (or it was used or expired).
                if receipt?.errorCode == "ask_first_required" {
                    return "declined: Doddy didn't have the user's yes for \"\(CloudToolName.title(tool))\", so nothing was looked at or done. Ask again only if the user wants."
                }
                if receipt?.errorCode == "confirmation_required" {
                    return "failed: the confirmation expired before it was used. Nothing was done. Offer to try again."
                }
                // A repeat of a confirmation whose first run may have gone through (ADR-322).
                if receipt?.errorCode == "earlier_outcome_unknown" || receipt?.status == .outcomeUnknown { return maybeDone }
                return "failed: \"\(CloudToolName.title(tool))\" is switched off. Tell the user they can switch it on in Settings, Online accounts. Nothing was done."
            case "not_connected", "connection_expired", "permission_insufficient":
                return "failed: \(account) isn't connected or needs reconnecting. Tell the user they can connect it in Settings, Online accounts. Nothing was done."
            case "live_not_configured":
                return "failed: \(account) isn't set up on Doddy's server. Nothing was done."
            case "quota_exceeded" where !CloudToolName.needsAccount(tool):
                return "failed: today's web search limit was reached. Tell the user it works again tomorrow and answer from what you know if you can, saying it may be out of date. Nothing was looked up."
            case "rate_limited", "quota_exceeded", "busy":
                return "failed: \(account) or Doddy's usage limit says to wait. Tell the user to try again later. Nothing was done."
            case "provider_timeout", "provider_unavailable":
                return isWrite ? maybeDone : "failed: \(account) couldn't be reached. Nothing was changed."
            case "not_found" where tool == CloudToolName.completeTodoistTask || tool == CloudToolName.moveTodoistTask:
                // Refused before any card (ADR-303): Todoist doesn't have that open task.
                return "not found: that Todoist task wasn't found, or it's already done. Nothing was changed. Read the tasks again with list_todoist_tasks and use the id it gives."
            case "not_found" where [CloudToolName.replyToEmail, CloudToolName.forwardEmail, CloudToolName.changeEmail, CloudToolName.trashEmail].contains(tool):
                return "not found: no email matched that search, or Doddy can't tell who to reply to. Nothing was sent or changed. Ask the user which email they meant."
            case "not_found" where tool == CloudToolName.draftEmailReply:
                // Refused before any card: no email matched, or its sender has no usable address.
                return "not found: no email matched that search, or the newest match has no sender address Doddy can reply to. No draft was created. Ask the user which email they meant."
            case "malformed_provider_result":
                return isWrite ? maybeDone : "failed: \(account) sent an answer Doddy couldn't read, so there is nothing to report."
            default:
                // A code this app doesn't know can't prove a write didn't happen.
                return isWrite ? maybeDone : "failed: that didn't work. Nothing was done."
            }
        }
    }
}
