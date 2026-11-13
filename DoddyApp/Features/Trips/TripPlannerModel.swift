import DoddyCore
import Foundation
import Observation

// The trip planner (decision 2026-11-11-travel-agent-plan, stage 2; TRAVEL_PLANNER.md), planner-first since the
// owner's review of 13 Nov 2026. The Trips screen is a form (`TripPlanForm` in DoddyCore): a complete form goes
// straight to the flight search (Kiwi.com through Doddy's server, no model). Words the person types or dictates
// go through the server's "understand" step, which fills the form; if something is still missing, Doddy asks
// for one thing at a time, on the page. Nothing is stored: a plan is only on screen, and nothing is booked or paid.

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
    enum Phase: Equatable {
        case idle
        /// Doddy's server is reading the person's words.
        case thinking
        case searching
        case result(PlanResult)
        case problem(String)
    }

    /// What the screen shows and what a search sends.
    var form = TripPlanForm()
    private(set) var phase: Phase = .idle
    /// Doddy's one question, when a search was asked for with something missing.
    private(set) var question: PlanNeed?
    private let polish = TripsModel.polish

    var isBusy: Bool { phase == .thinking || phase == .searching }

    /// The search button: a complete form is searched at once; otherwise Doddy asks for the first missing thing.
    func search() async {
        guard !isBusy else { return }
        if case .problem = phase { phase = .idle }
        if let first = form.missing.first {
            question = first
            return
        }
        question = nil
        await runSearch(form.brief)
    }

    /// The person's own words, typed or dictated: the server fills the form from them, then the search follows
    /// by itself once nothing is missing (as the conversational planner did).
    func tell(_ words: String) async {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        phase = .thinking
        guard var client = await TripPlannerClientFactory.ready() else { fail(.notSetUp); return }
        let brief = form.brief
        let understood: PlanUnderstood
        do {
            understood = try await client.understand(words: text, brief: brief, today: TripsModel.today)
        } catch OnlineAccountsError.unauthenticated {
            guard let renewed = await TripPlannerClientFactory.renewed() else { fail(.wordsUnavailable); return }
            client = renewed
            do {
                understood = try await client.understand(words: text, brief: brief, today: TripsModel.today)
            } catch {
                fail(TripPlanProblem(error, searching: false))
                return
            }
        } catch {
            fail(TripPlanProblem(error, searching: false))
            return
        }
        form.apply(understood.brief)
        if let first = form.missing.first {
            question = first
            phase = .idle
            return
        }
        question = nil
        await runSearch(form.brief, client: client)
    }

    func startOver() {
        form = TripPlanForm()
        question = nil
        phase = .idle
    }

    /// Clears the question once the person has filled in what it asked for; the next search asks the next one.
    func formChanged() {
        if let asked = question, !form.missing.contains(asked) { question = nil }
    }

    private func runSearch(_ brief: TripBrief, client existing: (any TripPlannerClient)? = nil) async {
        phase = .searching
        var client: any TripPlannerClient
        if let existing {
            client = existing
        } else {
            guard let ready = await TripPlannerClientFactory.ready() else { fail(.notSetUp); return }
            client = ready
        }
        do {
            phase = .result(try await client.search(brief, today: TripsModel.today))
        } catch OnlineAccountsError.unauthenticated {
            guard let renewed = await TripPlannerClientFactory.renewed() else { fail(.flightsUnavailable); return }
            client = renewed
            do {
                phase = .result(try await client.search(brief, today: TripsModel.today))
            } catch {
                fail(TripPlanProblem(error, searching: true))
            }
        } catch {
            fail(TripPlanProblem(error, searching: true))
        }
    }

    private func fail(_ problem: TripPlanProblem) {
        phase = .problem(problem.text(polish: polish))
    }
}
