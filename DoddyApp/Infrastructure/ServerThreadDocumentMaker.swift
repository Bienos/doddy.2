import DoddyCore
import Foundation

/// Makes the file a Messages card offered (ADR-606) with the server tool the voice already uses, `make_document`:
/// the server issues a single-use approval for exactly these words (`prepare`), and the file is made only by
/// running that approval (`run`). The person's tap on the card is what calls this; nothing here runs on its own.
///
/// "Made" means the server returned a link on https and did not report a failure. The file itself may still be
/// working, and its page says so; no status is kept in the thread. A network failure after `run` was sent
/// leaves it unknown whether the file exists: the card says it could not confirm, and the next tap asks for a new
/// approval rather than replaying the old one.
///
/// NOT COMPILED here (needs the app target); the rules it relies on are tested in DoddyCore.
struct ServerThreadDocumentMaker: ThreadDocumentMaker {
    func make(_ proposal: AssistantProposal) async throws -> ThreadDocument {
        guard let client = await OnlineAccountsClientFactory.ready() else { throw ThreadDocumentError.notConfigured }
        do {
            return try await run(proposal, with: client)
        } catch OnlineAccountsError.unauthenticated {
            // A refused session is renewed once; a second refusal is a failure, not another loop.
            guard let renewed = await OnlineAccountsClientFactory.renewed() else { throw ThreadDocumentError.failed }
            return try await run(proposal, with: renewed)
        } catch let error as OnlineAccountsError {
            throw Self.map(error)
        }
    }

    private func run(_ proposal: AssistantProposal, with client: any OnlineAccountsClient) async throws(OnlineAccountsError) -> ThreadDocument {
        let call = proposal.toolCall
        let prepared = try await client.prepare(call)
        let result = try await client.run(call, timeZone: TimeZone.current.identifier, approvalId: prepared.approvalId)
        guard let document = result.document.flatMap(ThreadDocument.init) else { throw .unreadableResponse }
        return document
    }

    private static func map(_ error: OnlineAccountsError) -> ThreadDocumentError {
        switch error {
        case .notConfigured: .notConfigured
        case .transport: .offline
        case .unauthenticated, .server, .unreadableResponse: .failed
        }
    }
}
