import Foundation

/// How the voice agent's online-account tool calls are read and answered. The agent only proposes:
/// the Doddy server checks the switch, the connection and the grant, and writes wait for a tap.
extension VoiceToolRequest {
    /// Nil unless `name` is one of the online-account tools. The arguments are passed on untouched
    /// (the server validates them strictly); only "is it a JSON object" is checked here.
    static func parseCloud(name: String, parametersJSON: Data) -> VoiceToolRequest? {
        // `pay_for_page` rides the same route (one card, then the server) but is not an online-account tool.
        guard CloudToolName.all.contains(name) || name == PaymentToolName.payForPage else { return nil }
        guard let arguments = try? JSONDecoder().decode([String: JSONValue].self, from: parametersJSON) else {
            return .invalid(name: name, reason: "arguments must be a JSON object")
        }
        return .cloudTool(CloudToolCall(name: name, arguments: arguments))
    }
}

extension VoiceToolReply {
    /// A successful read or write. Demo servers say so, so demo data is never presented as the user's.
    public static func cloudResult(_ result: RunResult) -> String {
        // A file still being made: the phone's own words, with no card or tap in them (owner, 13 Nov 2026).
        if let started = MadeFileStart.voiceReply(result) { return started }
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

    /// The code the server answers with when it can't find the one thing a write is about
    /// (backend/src/tools/service.ts, `lookup`). If the server ever names that failure another way,
    /// the new code goes here (ADR-718).
    static let lookupFailureCode = "not_found"

    /// ONE reply for every failed look-up of a write's target (ADR-718). It is true before the card
    /// and after the tap, and it says nothing of which of the cases it was.
    public static let cloudTargetNotFound =
        "not changed: Doddy couldn't pin down exactly one thing to change for that request (nothing matched it, or more than one thing did, or it can't be acted on). "
        + "Nothing was changed. Ask the user for the exact details, then try again."

    /// The result words the server starts a line with (backend/src/tools/catalog.ts).
    static let cloudResultPrefixes = ["drafted:", "added:", "completed:", "moved:", "email:", "page:", "sent:", "changed:", "trashed:", "deleted:", "answered:", "started:",
                                         // book_flight (decision 2026-11-11-flights-kiwi-search-duffel-booking): "booked:" only with
                                         // Duffel's order id and booking reference; "failed:" when Duffel said nothing was booked; else "unknown:".
                                         "booked:", "failed:", "unknown:",
                                         // plan_trip (backend/src/flights/planTrip.ts): the trip planner's one question for what is
                                         // still missing, in code's words; nothing was searched.
                                         "ask:"]

    /// What the agent hears when `make_document` was asked with too little to go on. Starts with the fixed word
    /// `need_details`, then the server's one-line list of what is missing, then what to do.
    public static func needDetails(message: String) -> String {
        let list = ToolData.clean(message).trimmingCharacters(in: .whitespacesAndNewlines)
        return "need_details: \(list) Nothing was made and nothing was used up. Ask the user at most two short questions about exactly what is missing (skip any they already answered), then call make_document again with their answers in the request. If they say to just do it, call it again with sensible defaults and say which you assumed."
    }

    /// research_now ran out of time on the server (40 s), or the app's 45 s wait ended or the server couldn't be reached.
    /// Nothing half-done is passed on, so the agent never has a partial answer to make up the rest of.
    static func researchNotFound(inTimeOrReached: Bool) -> String {
        let what = inTimeOrReached
            ? "Doddy's research didn't come back in time, or Doddy's server couldn't be reached"
            : "Doddy's research didn't finish in time"
        return "failed: \(what), so nothing was found. Don't make up an answer. Offer a quick web_search instead, "
            + "or hand_over_errand to research it properly in the background (the result arrives in Messages)."
    }

    /// plan_trip didn't come back: the app's 40 s wait ended or the server couldn't be reached. Nothing half-done is passed
    /// on, so the agent never has half a plan to fill in.
    static let planTripNotReached =
        "failed: Doddy's trip planning didn't come back in time, or Doddy's server couldn't be reached, so no flights were found. "
        + "Don't make up flights, prices or times. Offer to try once more, or find_flights for one route and date."

    /// The server's codes for a plan_trip step that failed or hit a daily limit (backend `planTripFailed`, `runPlanTrip`).
    static let planTripFailureCodes: Set<String> = ["provider_timeout", "provider_unavailable", "malformed_provider_result", "rate_limited", "quota_exceeded"]

    /// plan_trip failed on the server: its own words (code-written: the planner or Kiwi.com, out of time, unreachable or
    /// at today's limit), flattened to one line, and what the agent may offer. Nothing was booked.
    static func planTripFailed(_ serverMessage: String, dailyLimit: Bool) -> String {
        let said = ToolData.clean(serverMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        let what = said.isEmpty ? (dailyLimit ? "Today's trip planning limit was reached." : "Doddy's trip planning didn't work just now.") : said
        let offer = dailyLimit
            ? "Tell the user it works again tomorrow."
            : "Offer to try again in a moment, or find_flights for one route and date."
        return "failed: \(what) Nothing was booked. Don't make up flights, prices or times. \(offer)"
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
            // ADR-563: the app signs in again by itself after this.
            return "failed: Doddy had to sign in to his server again. Nothing was done. Try once more."
        case .transport:
            // research_now waits up to 45 s; a request that runs out of time ends here too, so the reply covers both.
            if tool == CloudToolName.researchNow { return researchNotFound(inTimeOrReached: true) }
            // plan_trip waits up to 40 s, so the same: out of time or not reached, and nothing to fill in.
            if tool == CloudToolName.planTrip { return planTripNotReached }
            return isWrite ? maybeDone : "failed: Doddy's server couldn't be reached. Nothing was changed."
        case .unreadableResponse:
            return isWrite ? maybeDone : "failed: Doddy's server sent an answer the app couldn't read, so nothing is shown."
        case .server(let code, _, _, let receipt):
            // The server's own receipt outranks the code: it recorded that the provider may have done it.
            if receipt?.status == .outcomeUnknown { return maybeDone }
            // book_flight (decision 2026-11-11-flights-kiwi-search-duffel-booking): a blocked or failed receipt
            // means the server proved nothing went to Duffel's booking (or Duffel said nothing was booked).
            if tool == CloudToolName.bookFlight, let status = receipt?.status, status == .blocked || status == .failed {
                return "failed: \(ToolData.clean(error.userMessage)) Nothing was booked."
            }
            // plan_trip: the server's own words say which step failed (the planner or Kiwi.com) and why; never "no flights".
            if tool == CloudToolName.planTrip, Self.planTripFailureCodes.contains(code) {
                return planTripFailed(error.userMessage, dailyLimit: code == "quota_exceeded")
            }
            switch code {
            case "capability_disabled":
                // ASK-01: the server had no yes for this exact call (or it was used or expired).
                if receipt?.errorCode == "ask_first_required" {
                    return "declined: Doddy didn't have the user's yes for \"\(CloudToolName.title(tool))\", so nothing was looked at or done. Ask again only if the user wants."
                }
                if CloudRun.isFirstTryFailure(error) {
                    // The server's record of the first try with this confirmation: it never ran (ADR-322).
                    return "failed: the first try didn't go through, so nothing was done. Offer to try again."
                }
                if receipt?.errorCode == "confirmation_required" {
                    return "failed: the confirmation expired before it was used. Nothing was done. Offer to try again."
                }
                // A repeat of a confirmation whose first run may have gone through (ADR-322).
                if receipt?.errorCode == "earlier_outcome_unknown" || receipt?.status == .outcomeUnknown { return maybeDone }
                // research_now follows the person's own "Search the web" switch (backend `researchSwitchedOff`).
                if tool == CloudToolName.researchNow {
                    return "failed: Search the web is switched off in Settings, so Doddy didn't research it. Tell the user they can switch it on in Settings, Online accounts, Web search. Nothing was looked up."
                }
                // plan_evening has no switch of its own: it follows Find places (backend `switchOf`), so the reply names that one.
                if tool == CloudToolName.planEvening {
                    return "failed: \"Find places\" is switched off, so Doddy didn't look for places. Tell the user they can switch it on in Settings, Online accounts, Web search. Nothing was looked up."
                }
                return "failed: \"\(CloudToolName.title(tool))\" is switched off. Tell the user they can switch it on in Settings, Online accounts. Nothing was done."
            case OnlineAccountsError.needDetailsCode:
                // Decision 2026-11-10-files-ask-for-details: the server turned a too-thin file request away before any
                // card, approval or Claude call. It is not a failure and not "done": the agent asks and sends it again.
                return needDetails(message: error.userMessage)
            case "not_connected", "connection_expired", "permission_insufficient":
                // ADR-563: the app puts a Connect button on screen for this account.
                return "not_connected: \(account) isn't connected yet, or needs reconnecting. A \"Connect \(account)\" button is on the user's screen now. Ask in one short sentence whether they'd like to connect it; it takes a few seconds. When it's connected the app tells you, and then you do what they asked. Nothing was done yet."
            case "live_not_configured":
                return "failed: \(account) isn't set up on Doddy's server. Nothing was done."
            case "quota_exceeded" where tool == CloudToolName.researchNow:
                // Its own daily count on the server, apart from Claude's writing (and the server's own Claude cap).
                return "failed: today's research limit was reached. Tell the user it works again tomorrow; a quick web_search still works, and you can still help in your own words. Nothing was sent to Claude."
            case "provider_timeout" where tool == CloudToolName.researchNow:
                return researchNotFound(inTimeOrReached: false)
            case "refused" where account == CloudToolName.claudeAccount:
                // Claude declined (its `refusal` stop reason, backend `claudeFailure`).
                return "failed: Claude declined that request. Say so in one short sentence and don't guess an answer. Nothing was done."
            case "quota_exceeded" where account == CloudToolName.claudeAccount:
                return "failed: today's Claude limit was reached. Tell the user it works again tomorrow; you can still help in your own words. Nothing was sent to Claude."
            case "quota_exceeded" where !CloudToolName.needsAccount(tool):
                return "failed: today's web search limit was reached. Tell the user it works again tomorrow and answer from what you know if you can, saying it may be out of date. Nothing was looked up."
            case "rate_limited", "quota_exceeded", "busy":
                return "failed: \(account) or Doddy's usage limit says to wait. Tell the user to try again later. Nothing was done."
            case "provider_timeout", "provider_unavailable":
                return isWrite ? maybeDone : "failed: \(account) couldn't be reached. Nothing was changed."
            case Self.lookupFailureCode where isWrite:
                // ADR-718: the server looks for the thing to change before the card is made. Nothing matched,
                // several did, or it can't be acted on all read the same, so a failed look-up tells the agent
                // nothing about what is in the mailbox, the calendar or the task list.
                return cloudTargetNotFound
            case "malformed_provider_result":
                return isWrite ? maybeDone : "failed: \(account) sent an answer Doddy couldn't read, so there is nothing to report."
            default:
                // A code this app doesn't know can't prove a write didn't happen.
                return isWrite ? maybeDone : "failed: that didn't work. Nothing was done."
            }
        }
    }
}
