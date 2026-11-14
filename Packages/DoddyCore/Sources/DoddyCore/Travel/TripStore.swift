import Foundation

// The bookings found in the person's email, kept on this iPhone only (owner: Gmail read on request; the
// server keeps nothing). One JSON file, replaced whole after each search, written atomically and
// protected until the first unlock. "Forget my trips" deletes it, and the screen says so only after the
// file is really gone (no claim without a verified storage operation, DOD-08).

public struct SavedTrips: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    /// When the search that found these ran.
    public let checkedAt: Date
    public let bookings: [TravelBooking]
    public let emailsFound: Int
    public let emailsUnreadable: Int

    public init(checkedAt: Date, bookings: [TravelBooking], emailsFound: Int, emailsUnreadable: Int) {
        self.version = Self.currentVersion
        self.checkedAt = checkedAt
        self.bookings = bookings
        self.emailsFound = emailsFound
        self.emailsUnreadable = emailsUnreadable
    }
}

public struct TripStore: Sendable {
    public enum Failure: Error, Equatable { case unreadable, writeFailed, deleteFailed }

    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// The app's file, in Application Support.
    public static func standard() -> TripStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return TripStore(fileURL: base.appendingPathComponent("Trips", isDirectory: true).appendingPathComponent("trips-v1.json"))
    }

    /// nil when nothing was saved yet. A file this version can't read is an error, never "no trips".
    public func load() throws(Failure) -> SavedTrips? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let saved = try Self.decoder.decode(SavedTrips.self, from: Data(contentsOf: fileURL))
            guard saved.version == SavedTrips.currentVersion else { throw Failure.unreadable }
            return saved
        } catch {
            throw .unreadable
        }
    }

    /// Writes, then reads the file back: true only when what is on disk is what was saved.
    @discardableResult
    public func save(_ trips: SavedTrips) throws(Failure) -> SavedTrips {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Bookings found in email are Doddy's own work, not something the person saved to keep: the folder is kept
            // out of iPhone backups (backup rule, docs/architecture/DEVICE_DATA_STORES.md).
            var folder = fileURL.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try Self.encoder.encode(trips).write(to: fileURL, options: options)
        } catch {
            throw .writeFailed
        }
        guard let back = try? load(), back == trips else { throw .writeFailed }
        return back
    }

    public func forget() throws(Failure) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { try FileManager.default.removeItem(at: fileURL) } catch { throw .deleteFailed }
        }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw .deleteFailed }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// What Home's card says about the next trip, if one is close (owner: "Karta na Home, gdy jest wyjazd").
public enum TripHomeCard {
    /// Shown while a trip is under way, or starts within this many days.
    public static let daysAhead = 60

    public static func nextTrip(_ trips: [Trip], today: TripDay) -> Trip? {
        trips.first { trip in
            switch trip.when(today: today) {
            case .ongoing: true
            case let .upcoming(days): days <= daysAhead
            case .past: false
            }
        }
    }

    public static func title(_ trip: Trip, today: TripDay, polish: Bool) -> String {
        switch trip.when(today: today) {
        case .ongoing: polish ? "\(trip.title): jesteś w podróży" : "\(trip.title): you're travelling"
        case .upcoming(0): polish ? "\(trip.title) dziś" : "\(trip.title) today"
        case .upcoming(1): polish ? "\(trip.title) jutro" : "\(trip.title) tomorrow"
        case let .upcoming(days): polish ? "\(trip.title) za \(days) dni" : "\(trip.title) in \(days) days"
        case .past: trip.title
        }
    }

    /// "3 rzeczy do sprawdzenia" / "3 things to check"; the count of checks other than sentences from emails.
    public static func subtitle(_ trip: Trip, polish: Bool) -> String {
        let n = TripChecks.checks(for: trip).filter { if case .fromTheEmail = $0.kind { false } else { true } }.count
        if polish {
            return "\(n) \(n == 1 ? "rzecz" : "rzeczy") do sprawdzenia"
        }
        return n == 1 ? "1 thing to check" : "\(n) things to check"
    }
}
