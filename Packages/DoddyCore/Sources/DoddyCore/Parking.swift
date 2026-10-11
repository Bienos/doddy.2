import Foundation

// "Where did I park?" (ADR-301). "Remember where I parked" reads one position, only then, with
// "While Using" location (place reminders' reader, ADR-196), and shows it on a card; the spot is
// kept only after Save, on this iPhone. "Where's my car?" answers with when it was saved, the
// user's note, and roughly how far it is; the card opens it in Apple Maps on a tap. The voice
// agent never hears coordinates, only the time, the note and a rounded distance. One spot at a
// time: a new one replaces the old; "I've got the car" clears it. Nothing tracks the user.

extension VoiceToolName {
    public static let parkingSpot = "parking_spot"
}

public struct ParkingSpot: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    /// How sure iOS was of the position, in metres.
    public let accuracyMeters: Double
    public let savedAt: Date
    /// The user's own words, e.g. "level 2, row C".
    public let note: String?

    public init(latitude: Double, longitude: Double, accuracyMeters: Double, savedAt: Date, note: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.savedAt = savedAt
        self.note = note.flatMap { Parking.cleanNote($0) }
    }
}

public enum ParkingAction: Equatable, Sendable {
    case save(note: String?)
    case find
    case clear
}

public enum Parking {
    public static let storageKey = "parking.spot"
    public static let maxNoteLength = 120
    /// A position less sure than this isn't worth keeping for finding a car.
    public static let worstAccuracyMeters: Double = 100

    static func cleanNote(_ text: String) -> String? {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return String(clean.prefix(maxNoteLength))
    }

    /// Great-circle distance in metres.
    public static func distance(from a: (latitude: Double, longitude: Double), to b: (latitude: Double, longitude: Double)) -> Double {
        let radius = 6_371_000.0
        let toRadians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * toRadians
        let dLon = (b.longitude - a.longitude) * toRadians
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * toRadians) * cos(b.latitude * toRadians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    /// Rounded, as people say it: "about 50 m", "about 350 m", "about 1.2 km", "about 15 km".
    public static func distanceText(_ meters: Double) -> String {
        if meters < 30 { return "very close (within about 30 m)" }
        if meters < 1000 { return "about \(Int((meters / 50).rounded()) * 50) m" }
        if meters < 10_000 { return String(format: "about %.1f km", meters / 1000) }
        return "about \(Int((meters / 1000).rounded())) km"
    }

    /// "today at 14:05", "yesterday at 09:30", "on 3 Oct at 18:00", in the user's zone.
    public static func savedText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "en_GB")
        time.dateFormat = "HH:mm"
        let clock = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(clock)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday at \(clock)"
        }
        time.dateFormat = "d MMM"
        return "on \(time.string(from: date)) at \(clock)"
    }

    /// Apple Maps at the spot, labelled "Parked car". Coordinates only go to Maps, on a tap.
    public static func mapsURL(_ spot: ParkingSpot) -> URL? {
        URL(string: String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=Parked%%20car", spot.latitude, spot.longitude))
    }

    public static func encode(_ spot: ParkingSpot) -> Data? { try? JSONEncoder().encode(spot) }
    public static func decode(_ data: Data?) -> ParkingSpot? { data.flatMap { try? JSONDecoder().decode(ParkingSpot.self, from: $0) } }
}

extension VoiceToolRequest {
    /// action: save (with an optional note), find or clear.
    static func parseParking(_ args: Arguments, name: String) -> VoiceToolRequest {
        switch args.text("action")?.lowercased() {
        case "save": return .parkingSpot(.save(note: args.text("note")))
        case "find": return .parkingSpot(.find)
        case "clear": return .parkingSpot(.clear)
        default: return .invalid(name: name, reason: "action must be save, find or clear")
        }
    }
}

extension VoiceToolReply {
    /// The spot's note is the user's words, so it follows as data (ToolData).
    public static func parkingSaved(_ spot: ParkingSpot, now: Date, calendar: Calendar) -> String {
        var text = "saved: the parking spot is kept on this iPhone (\(Parking.savedText(spot.savedAt, now: now, calendar: calendar))"
        if spot.note != nil { text += ", with the note below" }
        return text + "). Checked. It replaces any spot saved before." + noteData(spot)
    }

    public static func parkingFound(_ spot: ParkingSpot, now: Date, calendar: Calendar, distanceMeters: Double?) -> String {
        var text = "found: the user saved their parking spot \(Parking.savedText(spot.savedAt, now: now, calendar: calendar))"
        if spot.note != nil { text += " with the note below" }
        if let distanceMeters { text += "; it is \(Parking.distanceText(distanceMeters)) from here in a straight line" }
        return text + ". It is on the screen with Open in Maps; don't describe directions yourself." + noteData(spot)
    }

    private static func noteData(_ spot: ParkingSpot) -> String {
        spot.note.map { "\n" + ToolData.block([quoted("Note", $0)]) } ?? ""
    }

    public static let parkingNone = "not found: no parking spot is saved. Tell the user; offer to save one next time."
    public static let parkingCleared = "cleared: the saved parking spot was removed from this iPhone. Checked."
    public static let parkingNothingToClear = "not changed: no parking spot was saved, so there was nothing to clear."
    public static let parkingNotSaved = "failed: the parking spot couldn't be kept on this iPhone. Nothing was saved."
    public static let parkingDeclined = "declined: the user chose not to save the parking spot. Nothing was saved."

    /// Location isn't usable, or no position came within 15 seconds.
    public static func parkingNoLocation(_ readiness: LocationReadiness?) -> String {
        switch readiness {
        case .denied: return "failed: Doddy isn't allowed to use location. Tell the user they can allow it (While Using) in iOS Settings, Doddy, Location. Nothing was saved."
        case .approximateOnly: return "failed: Precise Location is off for Doddy, and an approximate position isn't good enough to find a car. Tell the user they can turn on Precise Location in iOS Settings, Doddy, Location. Nothing was saved."
        case .unavailable: return "failed: Location Services are off on this iPhone. Nothing was saved."
        default: return "failed: the iPhone couldn't get a precise enough position just now (it may be indoors or underground). Nothing was saved; suggest saving a note instead, e.g. the level and row."
        }
    }
}
