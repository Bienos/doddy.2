import Foundation

// One look-up of a parcel at InPost (ADR-634), with the network left out. The app supplies a
// `ParcelFetching` (the URLSession client in DoddyApp); everything that decides is here, so it is
// tested on Linux: a look-up starts only from the person's own act (`ParcelLookupPolicy`), the
// answer is read by HTTP code, and anything that can't be read or reached is "unavailable", never
// a status the parcel doesn't have.
//
// Platforms: iPhone and iPad.

/// What the client got back, before anything is understood.
public enum ParcelFetch: Equatable, Sendable {
    case reply(Data, statusCode: Int)
    /// The app's own per-minute limit was reached; nothing was sent.
    case tooMany
    /// No connection, a timeout, a refused redirect or an answer over the size cap.
    case failed
}

public protocol ParcelFetching: Sendable {
    func fetch(_ number: ParcelNumber) async -> ParcelFetch
}

public enum ParcelLookupResult: Equatable, Sendable {
    case tracking(ParcelTracking)
    /// InPost has no record of the number (yet).
    case notFound
    case notATrackingNumber
    /// The trigger was not the person's own act; nothing was sent.
    case notAllowed
    case tooMany
    /// Not reached, not understood, or InPost asked to slow down. The parcel's last known status stands.
    case unavailable

    /// A sentence for the person; nil when there is a parcel to show instead.
    public func message(polish: Bool) -> String? {
        switch self {
        case .tracking: nil
        case .notFound:
            polish
                ? "InPost nie ma informacji o tej przesyłce. Numer może być błędny albo nadawca jeszcze jej nie nadał."
                : "InPost has no record of this parcel. The number may be wrong, or the sender may not have posted it yet."
        case .notATrackingNumber:
            polish ? "InPost nie rozpoznaje tego jako numeru przesyłki." : "InPost doesn't recognise this as a parcel number."
        case .notAllowed:
            polish
                ? "Doddy sprawdza przesyłkę tylko wtedy, gdy ją dodasz albo stukniesz Odśwież."
                : "Doddy checks a parcel only when you add it or tap Refresh."
        case .tooMany:
            polish ? "Zbyt wiele sprawdzeń w ciągu minuty. Poczekaj chwilę." : "Too many checks in a minute. Wait a moment."
        case .unavailable:
            polish
                ? "Nie udało się sprawdzić przesyłki: brak połączenia albo InPost nie odpowiedział. Zostaje ostatni znany stan."
                : "The parcel couldn't be checked: no connection, or InPost didn't answer. The last known status stays."
        }
    }
}

public struct ParcelTracker: Sendable {
    private let fetcher: any ParcelFetching

    public init(fetcher: any ParcelFetching) { self.fetcher = fetcher }

    public func lookup(_ number: ParcelNumber, trigger: ParcelLookupTrigger) async -> ParcelLookupResult {
        guard ParcelLookupPolicy.allows(trigger) else { return .notAllowed }
        switch await fetcher.fetch(number) {
        case .tooMany:
            return .tooMany
        case .failed:
            return .unavailable
        case .reply(let data, let statusCode):
            guard data.count <= InPostTracking.maxBytes else { return .unavailable }
            switch InPostTracking.parse(data, statusCode: statusCode, number: number) {
            case .found(let tracking): return .tracking(tracking)
            case .notFound: return .notFound
            case .notATrackingNumber: return .notATrackingNumber
            case .rateLimited, .unreadable: return .unavailable
            }
        }
    }
}

public extension ParcelBook {
    /// Keeps what a look-up found. Only a parcel InPost answered for changes the list: "not found",
    /// "too many" and "unavailable" leave the last known status as it was, and a parcel removed while
    /// the look-up was in flight is not brought back. This is deliberately synchronous: the screen adds
    /// the parcel, saves the list, awaits the tracker, and only then applies the answer to the list as it
    /// is by then, so no `mutating` call is ever held open across a suspension.
    mutating func apply(_ result: ParcelLookupResult, now: Date) {
        if case .tracking(let tracking) = result { record(tracking, now: now) }
    }

    /// A parcel may be looked up when the list is on and the parcel is in it.
    func mayLookUp(_ number: ParcelNumber) -> Bool {
        isOn && entries.contains { $0.number == number.digits }
    }
}
