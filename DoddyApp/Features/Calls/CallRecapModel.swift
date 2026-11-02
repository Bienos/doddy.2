import DoddyCore
import Foundation
import Observation

/// State for one call's recap (ADR-693), without the view. The recap is saved on this iPhone before the
/// server is told it can delete its copy (`CallRecapLoader`); nothing here says anything was saved as a
/// memory: the notes it lists wait in "Notes from your calls" until the user saves them there.
@MainActor
@Observable
final class CallRecapModel {
    enum Phase: Equatable {
        case loading
        case saved(StoredCallRecap)
        case waiting
        case none
        case gone(CallRecapState)
        case failed(String)
    }

    let callId: UUID
    private(set) var phase: Phase = .loading
    private(set) var isWorking = false
    private(set) var message: String?
    private let repository: any CallRecapRepository
    private let loader: CallRecapLoader?

    init(callId: UUID, client: DoddyServerClient?, repository: any CallRecapRepository) {
        self.callId = callId
        self.repository = repository
        self.loader = client.map { CallRecapLoader(backend: $0, repository: repository) }
    }

    func load() async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let loader else {
                // No messaging server in this build: only what is already on this iPhone.
                phase = try await repository.get(callId).map(Phase.saved) ?? .none
                return
            }
            switch try await loader.load(callId) {
            case .saved(let stored): phase = .saved(stored)
            case .waiting: phase = .waiting
            case .none: phase = .none
            case .gone(let state): phase = .gone(state)
            }
        } catch {
            // A recap already here is still shown when the server can't be reached.
            if let local = try? await repository.get(callId) {
                phase = .saved(local)
            } else {
                phase = .failed(Self.text(for: error))
            }
        }
    }

    /// Deletes the server's copy, then this iPhone's. Returns true when both are gone.
    func delete() async -> Bool {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            if let loader {
                try await loader.delete(callId)
            } else {
                try await repository.delete(callId)
            }
            phase = .gone(.deleted)
            return true
        } catch {
            message = String(format: NSLocalizedString("The recap couldn't be deleted. %@", comment: ""), Self.text(for: error))
            return false
        }
    }

    /// Why the recap has no summary, in the user's words.
    static func text(for reason: CallRecapSummaryNote) -> String {
        switch reason {
        case .noWriter: NSLocalizedString("No summary: Doddy's server has no summary writer set up. The notes and the transcript are below.", comment: "")
        case .writerFailed: NSLocalizedString("No summary: writing it failed twice. The notes and the transcript are below.", comment: "")
        case .dailyLimit: NSLocalizedString("No summary: today's limit for call summaries was reached. The notes and the transcript are below.", comment: "")
        case .saveClaim: NSLocalizedString("No summary: the one written said something was saved, but a note from a call is saved only when you confirm it, so it was left out. The notes and the transcript are below.", comment: "")
        case .emptyCall: NSLocalizedString("No summary: nobody spoke to Doddy on this call.", comment: "")
        case .transcriptUnreadable: NSLocalizedString("No summary: the call's transcript couldn't be read.", comment: "")
        case .unusableSummary, .unknown: NSLocalizedString("No summary for this call. The notes and the transcript are below.", comment: "")
        }
    }

    static func text(for error: any Error) -> String {
        switch error as? ServerError {
        case .notConfigured: NSLocalizedString("Call recaps aren't set up on Doddy's server yet.", comment: "")
        default: UpdatesModel.text(for: error)
        }
    }
}
