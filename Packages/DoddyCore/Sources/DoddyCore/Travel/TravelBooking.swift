import Foundation

// Travel, stage 1 (decision 2026-11-11-travel-agent-plan; docs/implementation/TRAVEL_EMAILS.md).
// One booking as Doddy's server sends it after reading the person's booking emails on their request
// (schemas/fixtures/travel_bookings_v1.json). Every value in it was found in an email; the server drops
// what it couldn't find there. Dates are the email's own local dates ("YYYY-MM-DD"), times "HH:MM".

public struct TravelBooking: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case flight, stay, package, train, bus, carRental = "car_rental" }
    /// booked and changed are bookings to plan around; waiting is paid but not confirmed by the seller;
    /// failed and cancelled are shown as such and never planned around.
    public enum State: String, Codable, Sendable { case booked, changed, cancelled, waiting, failed }

    public struct Place: Codable, Equatable, Sendable {
        public let code: String?
        public let name: String?
    }

    public struct Segment: Codable, Equatable, Sendable {
        public let carrier: String?
        public let number: String?
        public let from: Place
        public let to: Place
        public let departDate: String?
        public let departTime: String?
        public let arriveDate: String?
        public let arriveTime: String?
    }

    public struct Stay: Codable, Equatable, Sendable {
        public let name: String?
        public let address: String?
        public let city: String?
        public let checkInDate: String?
        public let checkInTime: String?
        public let checkOutDate: String?
        public let checkOutTime: String?
        public let guests: String?
    }

    public struct Money: Codable, Equatable, Sendable {
        public let amount: String
        public let currency: String
    }

    public struct Charge: Codable, Equatable, Sendable {
        public let what: String
        public let amount: String
        public let currency: String
    }

    public struct Deposit: Codable, Equatable, Sendable {
        public let amount: String
        public let currency: String
        public let when: String?
    }

    public struct Deadline: Codable, Equatable, Sendable {
        public let date: String
        public let time: String?
    }

    public struct Destination: Codable, Equatable, Sendable {
        public let city: String?
        public let country: String?
    }

    public struct Facts: Codable, Equatable, Sendable {
        public let segments: [Segment]
        public let stay: Stay?
        public let destination: Destination?
        public let bags: [String]
        public let total: Money?
        public let freeCancellationUntil: Deadline?
        public let nonRefundable: Bool?
        public let payOnSite: [Charge]
        public let deposit: Deposit?
        /// Sentences copied word for word from the email ("3rd floor without elevator").
        public let notes: [String]
    }

    public struct Source: Codable, Equatable, Sendable {
        public let messageId: String
        public let receivedAt: String
        /// Shown as "z maila od ryanair.com".
        public let senderDomain: String
        public let status: String
    }

    public let id: String
    public let kind: Kind
    public let state: State
    public let provider: String?
    public let reference: String?
    public let facts: Facts
    public let sources: [Source]

    /// A booking Doddy plans around: made, or changed by the seller.
    public var isActive: Bool { state == .booked || state == .changed }
}

public struct TravelBookingsResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let bookings: [TravelBooking]
}

/// A calendar day from an email ("2026-12-08"), compared and counted without time zones.
public struct TripDay: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int

    public init?(_ iso: String?) {
        guard let iso, iso.count == 10 else { return nil }
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        (year, month, day) = (parts[0], parts[1], parts[2])
    }

    public init(year: Int, month: Int, day: Int) { (self.year, self.month, self.day) = (year, month, day) }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: TripDay, b: TripDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    /// Days from `self` to `other` (positive when `other` is later), counted on the Gregorian calendar.
    public func days(to other: TripDay) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let a = utc.date(from: DateComponents(year: year, month: month, day: day))!
        let b = utc.date(from: DateComponents(year: other.year, month: other.month, day: other.day))!
        return utc.dateComponents([.day], from: a, to: b).day!
    }

    public func adding(days n: Int) -> TripDay {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let d = utc.date(byAdding: .day, value: n, to: utc.date(from: DateComponents(year: year, month: month, day: day))!)!
        let c = utc.dateComponents([.year, .month, .day], from: d)
        return TripDay(year: c.year!, month: c.month!, day: c.day!)
    }

    /// This day at a local "HH:MM" in a time zone, as an instant.
    public func at(_ time: String?, in zone: TimeZone) -> Date? {
        guard let time else { return nil }
        let p = time.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0...23).contains(p[0]), (0...59).contains(p[1]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: p[0], minute: p[1]))
    }
}

extension TravelBooking {
    /// The first and last day the booking covers.
    public var span: (start: TripDay, end: TripDay)? {
        let days = facts.segments.flatMap { [TripDay($0.departDate), TripDay($0.arriveDate)] }
            + [TripDay(facts.stay?.checkInDate), TripDay(facts.stay?.checkOutDate)]
        let known = days.compactMap { $0 }.sorted()
        guard let first = known.first, let last = known.last else { return nil }
        return (first, last)
    }
}
