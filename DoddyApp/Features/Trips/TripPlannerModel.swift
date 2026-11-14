import DoddyCore
import Foundation
import Observation

// The trip planner's conversation (decision 2026-11-11-travel-agent-plan, stage 2; TRAVEL_PLANNER.md).
// The person types, or dictates with the keyboard's microphone, what they want. The server understands the
// words and says what is missing; this model asks for one missing thing at a time and, once the brief is
// complete, searches. Nothing is stored: a plan is only on screen, and nothing is booked or paid.

/// The planner's server client, built like `TravelClientFactory`.
enum TripPlannerClientFactory {
    static func ready() async -> (any TripPlannerClient)? {
        guard let url = DeviceSession.serverURL() else { return nil }
        await DeviceSession.ensure(server: url)
        return make(url)
    }

    static func renewed() async -> (any TripPlannerClient)? {
        guard let url = DeviceSession.serverURL(), await DeviceSession.renew(server: url) else { return nil }
        return make(url)
    }

    private static func make(_ url: URL) -> (any TripPlannerClient)? {
        guard KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendTripPlannerClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }
}

@MainActor
@Observable
final class TripPlannerModel {
    struct Line: Identifiable, Equatable {
        enum Who { case person, doddy }
        let id = UUID()
        let who: Who
        let text: String
    }

    enum Phase: Equatable {
        case asking
        case thinking
        case searching
        case result(PlanResult)
        case problem(String)
    }

    private(set) var lines: [Line] = []
    private(set) var brief: TripBrief?
    private(set) var assumptions: [PlanAssumption] = []
    private(set) var phase: Phase = .asking
    private let polish = TripsModel.polish

    var adults: Int { brief?.adults ?? 1 }
    var children: Int { brief?.children ?? 0 }

    var isBusy: Bool { phase == .thinking || phase == .searching }

    /// The person's words: from the box, in the order they came. Each turn is one server call; once the
    /// brief is complete the search follows by itself.
    func send(_ words: String) async {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        lines.append(Line(who: .person, text: text))
        phase = .thinking
        guard var client = await TripPlannerClientFactory.ready() else { fail(.notSetUp); return }
        let understood: PlanUnderstood
        do {
            understood = try await client.understand(words: text, brief: brief, today: TripsModel.today)
        } catch OnlineAccountsError.unauthenticated {
            guard let renewed = await TripPlannerClientFactory.renewed() else { fail(.unavailable); return }
            client = renewed
            do { understood = try await client.understand(words: text, brief: brief, today: TripsModel.today) } catch { fail(TravelScanProblem(error)); return }
        } catch {
            fail(TravelScanProblem(error))
            return
        }
        brief = understood.brief
        assumptions = understood.assumptions
        if let next = understood.missing.first {
            lines.append(Line(who: .doddy, text: TripPlanText.question(next, polish: polish)))
            phase = .asking
            return
        }
        phase = .searching
        do {
            phase = .result(try await client.search(understood.brief, today: TripsModel.today))
        } catch {
            fail(TravelScanProblem(error))
        }
    }

    func startOver() {
        lines = []
        brief = nil
        assumptions = []
        phase = .asking
    }

    private func fail(_ problem: TravelScanProblem) {
        phase = .problem(problem.text(polish: polish))
    }
}
