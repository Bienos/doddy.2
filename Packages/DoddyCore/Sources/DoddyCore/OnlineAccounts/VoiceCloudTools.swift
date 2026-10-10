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
        guard result.mode == .mock else { return result.text }
        return "DEMO DATA from a test server, not the user's real account. Tell the user it is demo data. \(result.text)"
    }

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
            switch code {
            case "capability_disabled":
                if receipt?.errorCode == "confirmation_required" {
                    return "failed: the confirmation expired before it was used. Nothing was done. Offer to try again."
                }
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
                return isWrite || receipt?.status == .outcomeUnknown ? maybeDone : "failed: \(account) couldn't be reached. Nothing was changed."
            case "malformed_provider_result":
                return isWrite ? maybeDone : "failed: \(account) sent an answer Doddy couldn't read, so there is nothing to report."
            default:
                return "failed: that didn't work. Nothing was done."
            }
        }
    }
}
