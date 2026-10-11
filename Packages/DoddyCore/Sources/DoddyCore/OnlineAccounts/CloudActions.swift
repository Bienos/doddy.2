import Foundation

// Online-account writes in the action status model (ADR-303, extends ADR-300 to ADR-302). A Gmail
// draft or a Todoist task is made by Doddy's server, which now keeps what happened to each
// single-use confirmation: asked again with the same confirmation, it answers with the first
// answer and never runs it twice. So when the answer is lost on the way back (no connection, an
// answer the app couldn't read), the app asks once more with the same confirmation: that can't
// make a second draft or task. The server also tells the card when the same write ran in the
// last day, and after an unsure try looks for a Todoist task before a second is made.

public enum CloudIdempotency {
    /// Same tool, same arguments (key order doesn't matter): the same write. Nil for reads.
    public static func key(_ call: CloudToolCall) -> String? {
        guard call.isWrite else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let arguments = (try? encoder.encode(call.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return "c1-" + ReminderIdempotency.fnv(call.name + "\u{1F}" + arguments)
    }
}

public enum CloudRun {
    /// Runs a confirmed write. If the answer is lost on the way back, asks once more with the same
    /// confirmation: the server runs a confirmation at most once and answers a repeat with what
    /// happened the first time (ADR-303), so this never does the write twice.
    public static func confirmed(
        _ call: CloudToolCall, approvalId: UUID, timeZone: String, client: some OnlineAccountsClient,
        pause: @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(1)) }
    ) async -> Result<RunResult, OnlineAccountsError> {
        do {
            return .success(try await client.run(call, timeZone: timeZone, approvalId: approvalId))
        } catch {
            guard call.isWrite, lostOnTheWay(error) else { return .failure(error) }
            await pause()
            do {
                return .success(try await client.run(call, timeZone: timeZone, approvalId: approvalId))
            } catch let second {
                // Still lost: Doddy can't tell, so it stays the first answer (unknown).
                return .failure(lostOnTheWay(second) ? error : second)
            }
        }
    }

    /// The request or its answer was lost; the server may have run it.
    static func lostOnTheWay(_ error: OnlineAccountsError) -> Bool {
        switch error {
        case .transport, .unreadableResponse: true
        default: false
        }
    }
}

/// The reply for the agent, and what "What Doddy did" keeps, for one online-account write.
public struct CloudWriteRecord: Equatable, Sendable {
    public let reply: String
    /// True when the server was (or may have been) asked to run it.
    public let attempted: Bool
    public let receipt: ActivityReceipt?
}

extension CloudWriteRecord {
    public init(_ outcome: Result<RunResult, OnlineAccountsError>, tool: String, app: ActivityApp, readAt: Date) {
        switch outcome {
        case .success(let result):
            let lines = [result.receipt.summary]
            self.init(
                reply: VoiceToolReply.cloudResult(result), attempted: true,
                receipt: ActivityReceipt(app: app, externalID: result.externalId, lines: lines, readAt: readAt))
        case .failure(let error):
            let reply = VoiceToolReply.cloudFailed(error, tool: tool)
            // "unknown" may have run; "failed" provably didn't (the server says which).
            self.init(reply: reply, attempted: reply.hasPrefix("unknown:"), receipt: nil)
        }
    }
}

extension VoiceToolReply {
    /// Before a card: an earlier unsure try is already there (the server looked). Nothing is done.
    public static func cloudAlreadyThere(_ tool: String) -> String {
        let account = CloudToolName.account(tool)
        return "added: \"\(CloudToolName.title(tool))\" was already in \(account) from the earlier try, so Doddy did not do it a second time. Tell the user it is already there."
    }
}
