import DoddyCore
import Foundation
import Observation

// Trips from booking emails (decision 2026-11-11-travel-agent-plan; docs/implementation/TRAVEL_EMAILS.md).
// Owner, 11 Nov 2026: Gmail is read only when the person asks ("Tylko na żądanie"); the server keeps
// nothing, so the bookings are saved on this iPhone (`TripStore`) and read back before the screen says so.
// The rules (trips, checks, the words) are in DoddyCore and tested on Linux; this file only moves data.

/// The Doddy server client for the trip search, built like `OnlineAccountsClientFactory`.
enum TravelClientFactory {
    static func make() -> (any TravelClient)? {
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendTravelClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }

    static func ready() async -> (any TravelClient)? {
        guard let url = DeviceSession.serverURL() else { return nil }
        await DeviceSession.ensure(server: url)
        return make()
    }

    static func renewed() async -> (any TravelClient)? {
        guard let url = DeviceSession.serverURL(), await DeviceSession.renew(server: url) else { return nil }
        return make()
    }
}

@MainActor
@Observable
final class TripsModel {
    static let shared = TripsModel(store: .standard())

    enum Phase: Equatable {
        case idle
        /// Asking the server for its card.
        case preparing
        /// The card is up; nothing has been read yet.
        case waitingForYes(PrepareResult)
        case searching
        /// The last search, as the server and the store said.
        case done(emails: Int, bookings: Int, unreadable: Int)
        case problem(TravelScanProblem)
        /// Found, but this iPhone couldn't save it: nothing is shown as saved.
        case notSaved
    }

    private let store: TripStore
    private(set) var saved: SavedTrips?
    /// The saved file couldn't be read. Never shown as "no trips".
    private(set) var storeUnreadable = false
    var phase: Phase = .idle

    init(store: TripStore) {
        self.store = store
        reload()
    }

    nonisolated static var polish: Bool { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) == .polish }

    static var today: TripDay {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return TripDay(year: c.year!, month: c.month!, day: c.day!)
    }

    var trips: [Trip] { TripAssembly.trips(from: saved?.bookings ?? []) }
    var notGoingAhead: [TravelBooking] { TripAssembly.notGoingAhead(saved?.bookings ?? []) }
    var homeTrip: Trip? { TripHomeCard.nextTrip(trips, today: Self.today) }

    func reload() {
        do {
            saved = try store.load()
            storeUnreadable = false
        } catch {
            storeUnreadable = true
        }
    }

    /// Step one: the server's card. Nothing is read from Gmail here.
    func ask() async {
        phase = .preparing
        guard var client = await TravelClientFactory.ready() else { phase = .problem(.notSetUp); return }
        do {
            phase = .waitingForYes(try await client.prepareScan())
        } catch OnlineAccountsError.unauthenticated {
            guard let renewed = await TravelClientFactory.renewed() else { phase = .problem(.unavailable); return }
            client = renewed
            do { phase = .waitingForYes(try await client.prepareScan()) } catch { phase = .problem(TravelScanProblem(error)) }
        } catch {
            phase = .problem(TravelScanProblem(error))
        }
    }

    /// Step two, only from the card's own button: one search, then saved here and read back.
    func search(_ card: PrepareResult) async {
        guard case .waitingForYes(let shown) = phase, shown == card else { return }
        phase = .searching
        guard let client = TravelClientFactory.make() else { phase = .problem(.notSetUp); return }
        let result: TravelScanResponse
        do {
            result = try await client.scan(approvalId: card.approvalId)
        } catch {
            phase = .problem(TravelScanProblem(error))
            return
        }
        do {
            saved = try store.save(SavedTrips(checkedAt: Date(), bookings: result.bookings, emailsFound: result.emailsFound,
                                              emailsUnreadable: result.emailsUnreadable))
            storeUnreadable = false
            phase = .done(emails: result.emailsFound, bookings: result.bookings.count, unreadable: result.emailsUnreadable)
        } catch {
            phase = .notSaved
        }
    }

    func cancelCard() { phase = .idle }

    /// Deletes the file; true only when it is gone.
    func forget() -> Bool {
        do {
            try store.forget()
            saved = nil
            storeUnreadable = false
            phase = .idle
            return true
        } catch {
            return false
        }
    }
}
