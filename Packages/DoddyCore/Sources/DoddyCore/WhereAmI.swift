import Foundation

// "Czy ty wiesz, gdzie ja teraz jestem?" (owner, 14 Nov 2026; decision 2026-11-14-approximate-location-by-voice). In a
// conversation Doddy kept asking which city. The owner said yes to: "With your consent (approximate position, never
// stored) Doddy would search 'near me' without asking for the city." So the voice agent can ask the app for the person's
// rough area, once per call of `where_am_i`, and put it in find_places, web_search or get_weather.
//
// The consent is iOS's own location question (While Using the App), asked the first time, like Calendar's for
// read_calendar; Doddy never asks for Always and never tracks. The app reads one position about a kilometre sure, only
// then. The agent hears the district and town Apple's geocoder gives for that position rounded to two decimals (Apple
// sees only the rounded position), the rounded position itself for the weather, how sure and how old the reading is.
// Nothing is kept: no note, no file, no log line with a place or a coordinate. The area goes back to the voice agent as
// the tool's result and nowhere else; the agent may put it in a search, as it would a town the person named.
//
// This file is the rule, tested on Linux: what iOS's answer means, the rounding, which reading counts as "now", and the
// words the agent hears. Reading the position and asking Apple's geocoder live in the app (`PlaceLocation`).

extension VoiceToolName {
    /// The person's approximate area, read once when the agent asks (decision 2026-11-14-approximate-location-by-voice).
    public static let whereAmI = "where_am_i"
}

/// One position iOS gave, as plain numbers (no CoreLocation in DoddyCore).
public struct LocationFix: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    /// How sure iOS was, in metres. Negative: iOS said the position isn't valid.
    public let accuracyMeters: Double
    /// When iOS took it (its own timestamp, which is older than now for a position iOS kept).
    public let takenAt: Date

    public init(latitude: Double, longitude: Double, accuracyMeters: Double, takenAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.takenAt = takenAt
    }
}

/// What Apple's geocoder called the place at the rounded position. Any of them can be missing. Each is one line, cut to
/// `WhereAmI.maxNameLength`, because it is text from outside the app that goes to the agent.
public struct AreaNames: Equatable, Sendable {
    /// The district or neighbourhood (`subLocality`).
    public let district: String?
    /// The city, town or village (`locality`).
    public let town: String?
    /// The province or state (`administrativeArea`).
    public let region: String?
    public let country: String?

    public init(district: String?, town: String?, region: String?, country: String?) {
        self.district = Self.clean(district)
        self.town = Self.clean(town)
        self.region = Self.clean(region)
        self.country = Self.clean(country)
    }

    /// No name at all: the agent gets only the rounded position.
    public var isEmpty: Bool { district == nil && town == nil && region == nil && country == nil }

    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(WhereAmI.maxNameLength))
    }
}

/// The area the agent hears: the position rounded to `WhereAmI.decimals`, and how sure and how old the reading was.
public struct ApproximateArea: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let accuracyMeters: Double
    public let takenAt: Date

    public init(latitude: Double, longitude: Double, accuracyMeters: Double, takenAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.takenAt = takenAt
    }
}

public enum WhereAmI {
    /// Two decimals: about 1.1 km north to south, and less east to west away from the equator (about 0.7 km in Warsaw).
    public static let decimals = 2
    /// A reading older than this is never passed off as where the person is now (10 minutes).
    public static let maxFixAge: TimeInterval = 10 * 60
    /// A reading stamped up to this far after `now` still counts (the clock may have been set while it was taken).
    public static let futureSkew: TimeInterval = 60
    /// Less sure than this, a reading can't name a town. Approximate Location (Precise off) is usually a few kilometres.
    public static let worstAccuracyMeters: Double = 10_000
    /// Less sure than this, the district is left out: the reading could as well be in the next one.
    public static let districtAccuracyMeters: Double = 2_000
    /// How long the app waits for iOS's reading, and then for Apple's geocoder.
    public static let fixTimeout: TimeInterval = 8
    public static let geocodeTimeout: TimeInterval = 5
    /// The longest place name passed on.
    public static let maxNameLength = 80

    /// What the app does after reading iOS's location state.
    public enum Step: Equatable, Sendable {
        /// Allowed (While Using the App, precise or approximate): read one position.
        case read
        /// iOS hasn't asked the person yet: the app shows iOS's own question, only while Doddy is on screen.
        case askIOS
        /// The person chose Never, or location is restricted on this iPhone: nothing is read and nothing is asked again.
        case notAllowed
        /// Location Services are off for the whole iPhone.
        case servicesOff
    }

    public static func step(for readiness: LocationReadiness) -> Step {
        switch readiness {
        case .ready, .approximateOnly: .read
        case .notDetermined: .askIOS
        case .denied: .notAllowed
        case .unavailable: .servicesOff
        }
    }

    /// Rounded to `decimals` places; never "-0.00".
    public static func round(_ degrees: Double) -> Double {
        let rounded = (degrees * 100).rounded() / 100
        return rounded == 0 ? 0 : rounded
    }

    /// A reading counts as where the person is now only when iOS said it is valid, it is sure to `worstAccuracyMeters`,
    /// its coordinates are real ones, and it is at most `maxFixAge` old.
    public static func isCurrent(_ fix: LocationFix, now: Date) -> Bool {
        guard fix.accuracyMeters.isFinite, fix.accuracyMeters >= 0, fix.accuracyMeters <= worstAccuracyMeters else { return false }
        guard fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90, abs(fix.longitude) <= 180 else { return false }
        let age = now.timeIntervalSince(fix.takenAt)
        return age.isFinite && age <= maxFixAge && age >= -futureSkew
    }

    /// The reading iOS just gave if it counts; otherwise the last one iOS gave Doddy, if that still counts; otherwise
    /// nothing, and the agent hears "unknown".
    public static func best(fresh: LocationFix?, lastKnown: LocationFix?, now: Date) -> LocationFix? {
        if let fresh, isCurrent(fresh, now: now) { return fresh }
        if let lastKnown, isCurrent(lastKnown, now: now) { return lastKnown }
        return nil
    }

    /// What leaves the app: the rounded position, never the reading itself.
    public static func area(of fix: LocationFix) -> ApproximateArea {
        ApproximateArea(latitude: Self.round(fix.latitude), longitude: Self.round(fix.longitude), accuracyMeters: fix.accuracyMeters, takenAt: fix.takenAt)
    }

    /// "just now", "about 4 minutes ago".
    static func ageText(_ takenAt: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(takenAt))
        guard seconds >= 90 else { return "just now" }
        let minutes = Int((seconds / 60).rounded())
        return "about \(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }

    /// "about 1 km", "about 3 km".
    static func accuracyText(_ meters: Double) -> String {
        meters < 1_500 ? "about 1 km" : "about \(Int((meters / 1_000).rounded())) km"
    }

    static func degreesText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

extension VoiceToolReply {
    /// The area as the agent hears it. The names are Apple's and the position is rounded; both follow as data (ToolData).
    public static func whereAmI(_ area: ApproximateArea, names: AreaNames?, now: Date) -> String {
        let position = "Rounded position: \(WhereAmI.degreesText(area.latitude)), \(WhereAmI.degreesText(area.longitude))"
        var first = "found: roughly where the user is now, from the iPhone's location (\(WhereAmI.accuracyText(area.accuracyMeters)), read \(WhereAmI.ageText(area.takenAt, now: now))). Nothing was saved."
        if WhereAmI.ageText(area.takenAt, now: now) != "just now" {
            first += " It is a few minutes old, so if they may have moved since, say it's where they were a little while ago."
        }
        let district = area.accuracyMeters <= WhereAmI.districtAccuracyMeters ? names?.district : nil
        guard let names, !names.isEmpty, district != nil || names.town != nil else {
            return first + " Apple's maps gave no town or district for it just now, so only the position rounded to about 1 km follows:\n"
                + ToolData.block([position])
                + "\nget_weather can use it as latitude and longitude. For find_places or web_search you need a town: ask the user which one, in a few words. Never read out the numbers."
        }
        var lines: [String] = []
        if let district { lines.append(quoted("District", district)) }
        if let town = names.town { lines.append(quoted("Town", town)) }
        if let region = names.region { lines.append(quoted("Region", region)) }
        if let country = names.country { lines.append(quoted("Country", country)) }
        lines.append(position)
        let near = district != nil && names.town != nil ? "the district and town" : (names.town != nil ? "the town" : "the district")
        return first + " The area as Apple's maps name it, and the position rounded to about 1 km:\n"
            + ToolData.block(lines)
            + "\nUse it for what the user asked instead of asking which city: find_places with near set to \(near), web_search with the town in the search words, get_weather with the rounded position as latitude and longitude. Say the area in a few words as roughly where they are; never read out the numbers and never say you know their address."
    }

    /// iOS says no for Doddy: the person chose Never, or location is restricted on this iPhone. Nothing was read.
    public static let whereAmINotAllowed = "not allowed: location is off for Doddy on this iPhone, so nothing was read. Tell the user in one short sentence that you can't see where they are, and that they can allow it in iPhone Settings, Doddy, Location, While Using the App. Then ask which town or area they mean. Don't call where_am_i again in this conversation unless they say they turned it on."

    /// The person was asked by iOS and didn't allow it.
    public static let whereAmINotAnswered = "not allowed: the user didn't allow location when iPhone asked, so nothing was read. Ask which town or area they mean, and don't call where_am_i again in this conversation."

    /// Location Services are off for the whole iPhone.
    public static let whereAmIServicesOff = "unavailable: Location Services are off on this iPhone, so nothing was read. Tell the user in one short sentence; they can turn them on in iPhone Settings, Privacy & Security, Location Services. Then ask which town or area they mean. Don't call where_am_i again in this conversation unless they say they turned them on."

    /// iOS hasn't asked yet, and it shows its question only while Doddy is open on the screen.
    public static let whereAmINotAskedOffScreen = "not asked: Doddy hasn't been allowed to use location yet, and iPhone can ask only while Doddy is open on the screen. Nothing was read. Tell the user in one short sentence to open Doddy and ask again, or to say which town or area they mean."

    /// No reading came in time, or only one too old or too unsure to count. Never an older position passed off as now.
    public static func whereAmIUnknown(onScreen: Bool) -> String {
        let minutes = Int(WhereAmI.maxFixAge / 60)
        let why = onScreen
            ? "the iPhone gave no position recent and sure enough in time (indoors it can take longer)"
            : "the iPhone gave no position in time; while Doddy isn't open on the screen it may give none"
        let ask = onScreen
            ? "Tell the user in one short sentence that you couldn't tell where they are right now, and ask which town or area they mean."
            : "Tell the user in one short sentence that you couldn't tell where they are; they can open Doddy and ask again, or say which town or area they mean."
        return "unknown: \(why), so Doddy doesn't know where the user is right now. It never uses a position older than \(minutes) minutes. Nothing was read or kept. \(ask) Don't call where_am_i again unless they ask."
    }
}
