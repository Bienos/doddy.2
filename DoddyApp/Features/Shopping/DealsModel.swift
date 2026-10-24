import DoddyCore
import Foundation
import Observation

// This week's leaflets (docs/implementation/SHOPPING.md 2): one request to Doddy's server, which reads
// the official leaflets of Biedronka, Lidl, Dino and Rossmann on this request and keeps nothing but
// counts. The voice tool (`find_deals`, after its ask card) and the "Cheapest this week" screen both
// come here, so they show the same answer. Nothing is retried by itself: each try counts against the
// day's leaflet checks. The last answer stays in memory only, for the screen; it is never saved.

@MainActor
@Observable
final class DealsModel {
    static let shared = DealsModel(client: { ServerConfig.client() })

    enum Phase: Equatable {
        case idle
        case checking
        case failed(String)
    }

    private let clientProvider: @MainActor () -> DoddyServerClient?
    private(set) var phase: Phase = .idle
    private(set) var lastRequest: DealsRequest?
    private(set) var lastResult: DealsResult?

    init(client: @escaping @MainActor () -> DoddyServerClient?) {
        self.clientProvider = client
    }

    var isServerConfigured: Bool { clientProvider() != nil }

    /// For the voice agent: the answer as the agent's data, or why nothing was looked up.
    func searchForAgent(_ request: DealsRequest) async -> String {
        switch await search(request) {
        case .success(let result):
            return DealsResultText.forAgent(result, language: request.language)
        case .failure(let error):
            return VoiceToolReply.dealsNotChecked(error)
        }
    }

    /// One request. On success the answer is kept for the screen; on failure the screen says why.
    @discardableResult
    func search(_ request: DealsRequest) async -> Result<DealsResult, any Error> {
        guard let client = clientProvider() else {
            phase = .failed(NSLocalizedString("Doddy's server isn't set up in this build, so leaflets can't be checked yet.", comment: ""))
            return .failure(DealsError.dealsDisabled)
        }
        phase = .checking
        lastRequest = request
        do {
            let result = try await client.searchDeals(request)
            lastResult = result
            phase = .idle
            return .success(result)
        } catch {
            phase = .failed(Self.message(for: error))
            return .failure(error)
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case DealsError.dealsDisabled:
            NSLocalizedString("Leaflet checks are switched off on Doddy's server.", comment: "")
        case DealsError.dailyLimit:
            NSLocalizedString("You've used today's leaflet checks. You can check again tomorrow.", comment: "")
        case DealsError.invalid:
            NSLocalizedString("Doddy's server didn't accept this list. Use up to 12 items of up to 60 characters.", comment: "")
        case DealsError.server(.offline), ServerError.offline:
            NSLocalizedString("Doddy's server couldn't be reached. Nothing was checked; try again when you're online.", comment: "")
        default:
            NSLocalizedString("Something went wrong on Doddy's server. Nothing was checked.", comment: "")
        }
    }
}
