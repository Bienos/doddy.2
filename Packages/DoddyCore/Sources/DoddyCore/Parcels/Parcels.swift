import Foundation

// InPost parcels (ADR-634): read a parcel's status by its tracking number, and keep a short list of
// the parcels the person is waiting for. What is known about InPost's tracking is in
// docs/implementation/INPOST_STATUS.md: the endpoint needs no token (InPost's own documentation and a
// live request agree), its real error answers differ from the documented ones, so the answer is read
// by the HTTP code, and nothing in an answer is trusted beyond what is checked here.
//
// Nothing in this file reads mail or messages. A parcel number found in a message is DATA: it can be
// offered to the person as a suggestion, and it is looked up only when the person adds it or taps
// Refresh (`ParcelLookupPolicy`).
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux. The one request lives in the app.

/// An InPost tracking number: 24 digits, as in every example in InPost's documentation. InPost does
/// not state the format as a rule, so this is stricter than it may need to be: a number that is
/// refused is never sent anywhere.
public struct ParcelNumber: Equatable, Hashable, Sendable, Codable {
    public static let length = 24
    public let digits: String

    public init?(_ raw: String) {
        let digits = raw.filter { $0 != " " && $0 != "-" }
        guard digits.count == Self.length, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self.digits = digits
    }

    /// Numbers in a piece of text, for a SUGGESTION to the person ("add this one?"). A run of exactly
    /// 24 digits, not part of a longer number. Never starts a look-up by itself.
    public static func candidates(in text: String) -> [ParcelNumber] {
        var found: [ParcelNumber] = []
        var run = ""
        func flush() {
            if run.count == length, let number = ParcelNumber(run), !found.contains(number) { found.append(number) }
            run = ""
        }
        for character in text {
            if character.isASCII, character.isNumber { run.append(character) } else { flush() }
        }
        flush()
        return found
    }
}

/// What may start a status look-up. Only the person's own act does.
public enum ParcelLookupTrigger: Equatable, Sendable {
    case personAddedIt
    case personTappedRefresh
    /// A number seen in an email, a message, a web page or a scan.
    case foundInContent
    /// The model asked for it.
    case requestedByModel
}

public enum ParcelLookupPolicy {
    public static func allows(_ trigger: ParcelLookupTrigger) -> Bool {
        switch trigger {
        case .personAddedIt, .personTappedRefresh: true
        case .foundInContent, .requestedByModel: false
        }
    }
}

public enum ParcelStatusKind: String, Sendable, Codable {
    case preparing, inTransit, readyForPickup, delivered, problem, returned, unknown
}

/// InPost's status names (from `GET /v1/statuses`, 32 names for the locker service on 24 Oct 2026),
/// each with a short sentence in Polish and English. The wording is InPost's own published titles;
/// InPost's documentation says they may be used in user interfaces. A name that is not in the table is
/// shown as unknown with InPost's own word, never turned into a sentence.
public enum ParcelStatuses {
    public struct Text: Equatable, Sendable {
        public let polish: String
        public let english: String
        public let kind: ParcelStatusKind
    }

    public static func text(for name: String) -> Text {
        if let known = table[name] { return known }
        let shown = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(60))
        return Text(polish: "Status nieznany (\(shown))", english: "Unknown status (\(shown))", kind: .unknown)
    }

    private static func t(_ pl: String, _ en: String, _ kind: ParcelStatusKind) -> Text { Text(polish: pl, english: en, kind: kind) }

    static let table: [String: Text] = [
        "created": t("Przesyłka utworzona", "Shipment created", .preparing),
        "confirmed": t("Przygotowana przez Nadawcę", "Prepared by the sender", .preparing),
        "oversized": t("Przesyłka ponadgabarytowa", "Oversize parcel", .problem),
        "dispatched_by_sender_to_pok": t("Nadana w PaczkoPunkcie", "Shipped at the customer service point", .inTransit),
        "dispatched_by_sender": t("Paczka nadana w automacie Paczkomat", "Parcel shipped at the parcel machine", .inTransit),
        "collected_from_sender": t("Odebrana od klienta", "Picked up from the client", .inTransit),
        "taken_by_courier": t("Odebrana od Nadawcy", "Picked up from the sender", .inTransit),
        "adopted_at_source_branch": t("Przyjęta w oddziale InPost", "Received at an InPost branch", .inTransit),
        "adopted_at_sorting_center": t("Przyjęta w Sortowni", "Received at the sorting center", .inTransit),
        "sent_from_source_branch": t("W trasie", "On the road", .inTransit),
        "taken_by_courier_from_pok": t("W drodze do oddziału nadawczego InPost", "On the way to the InPost shipping branch", .inTransit),
        "out_for_delivery": t("Przekazano do doręczenia", "Handed over for delivery", .inTransit),
        "readdressed": t("Przekierowano na inny adres", "Rerouted to another address", .inTransit),
        "ready_to_pickup": t("Czeka w Paczkomacie na odbiór", "Waiting in the parcel machine for pickup", .readyForPickup),
        "pickup_reminder_sent": t("Przypomnienie o czekającej paczce", "Reminder of a waiting parcel", .readyForPickup),
        "courier_avizo_in_customer_service_point": t("Oczekuje na odbiór", "Awaiting collection", .readyForPickup),
        "ready_to_pickup_from_branch": t("Paczka nieodebrana, czeka w oddziale", "Parcel not collected, waiting at the branch", .readyForPickup),
        "stack_in_customer_service_point": t("Paczka magazynowana w PaczkoPunkcie", "Parcel stored at a parcel service point", .readyForPickup),
        "stack_in_box_machine": t("Paczka magazynowana w tymczasowym Paczkomacie", "Parcel stored in a temporary parcel machine", .readyForPickup),
        "unstack_from_customer_service_point": t("W drodze do wybranego Paczkomatu", "On the way to the parcel machine of your choice", .inTransit),
        "unstack_from_box_machine": t("W drodze do pierwotnie wybranego Paczkomatu", "On the way to the parcel machine first chosen", .inTransit),
        "delivered": t("Dostarczona", "Delivered", .delivered),
        "pickup_time_expired": t("Upłynął termin odbioru", "The deadline for collecting has passed", .problem),
        "stack_parcel_pickup_time_expired": t("Upłynął termin odbioru paczki magazynowanej", "The deadline for collecting the stored parcel has passed", .problem),
        "stack_parcel_in_box_machine_pickup_time_expired": t("Upłynął termin odbioru paczki magazynowanej", "The deadline for collecting the stored parcel has passed", .problem),
        "avizo": t("Powrót do oddziału", "Back to the branch", .problem),
        "rejected_by_receiver": t("Odmowa przyjęcia", "Parcel rejected", .problem),
        "undelivered": t("Przekazanie do magazynu przesyłek niedoręczalnych", "Transferred to the undeliverable-parcels warehouse", .problem),
        "delay_in_delivery": t("Możliwe opóźnienie doręczenia", "Possible delay in delivery", .problem),
        "claimed": t("Zareklamowana w Paczkomacie", "Complaint made at the parcel machine", .problem),
        "returned_to_sender": t("Zwrot do nadawcy", "Returned to the sender", .returned),
        "taken_by_courier_from_customer_service_point": t("Zwrócona do nadawcy", "Returned to the sender", .returned),
        "canceled": t("Anulowano etykietę", "The label was cancelled", .problem),
    ]
}

public struct ParcelEvent: Equatable, Sendable, Codable {
    public let status: String
    /// As InPost wrote it (ISO 8601 with offset); only shown, never computed with.
    public let datetime: String?
}

public struct ParcelTracking: Equatable, Sendable, Codable {
    public let number: String
    public let status: String
    public let service: String?
    /// The parcel machine's name ("KAT07A"), when InPost gives it.
    public let pickupPoint: String?
    public let pickupAddress: String?
    public let openingHours: String?
    /// Newest first, at most `InPostTracking.maxEvents`.
    public let events: [ParcelEvent]
    public let updatedAt: String?

    public var statusText: ParcelStatuses.Text { ParcelStatuses.text(for: status) }

    /// "Czeka w Paczkomacie na odbiór · KAT07A, Bankowa 14, 40-007 Katowice".
    public func headline(polish: Bool) -> String {
        let text = statusText
        var line = polish ? text.polish : text.english
        if text.kind == .readyForPickup || text.kind == .inTransit, let point = pickupPoint {
            line += " · " + [point, pickupAddress].compactMap { $0 }.joined(separator: ", ")
        }
        return line
    }
}

public enum ParcelAnswer: Equatable, Sendable {
    case found(ParcelTracking)
    /// InPost has no such parcel (or it is older than 45 days).
    case notFound
    /// InPost says it is not a tracking number it knows.
    case notATrackingNumber
    case rateLimited
    case unreadable
}

public enum InPostTracking {
    public static let host = "api-shipx-pl.easypack24.net"
    public static let maxBytes = 256 * 1024
    public static let timeout: TimeInterval = 10
    public static let maxEvents = 20
    /// InPost documents no limit for this endpoint; the app keeps itself to this many a minute.
    public static let lookupsPerMinute = 20
    public static let attribution = "InPost"

    /// The one address the app asks, built from a checked number: no key, no query.
    public static func url(for number: ParcelNumber) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1/tracking/\(number.digits)"
        // The parts are fixed or digits, so this always makes a URL.
        return components.url!
    }

    public static func userAgent(appVersion: String) -> String {
        let version = appVersion.filter { $0.isASCII && ($0.isNumber || $0 == ".") }
        return "Doddy/\(version.isEmpty ? "1" : version) (https://doddy.lol)"
    }

    /// Reads the answer by its HTTP code first (InPost's live error bodies differ from its
    /// documentation), and a 200 only if it names the parcel that was asked for.
    public static func parse(_ data: Data, statusCode: Int, number: ParcelNumber) -> ParcelAnswer {
        switch statusCode {
        case 404: return .notFound
        case 400: return .notATrackingNumber
        case 429: return .rateLimited
        case 200: break
        default: return .unreadable
        }
        guard data.count <= maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let answered = root["tracking_number"] as? String, answered == number.digits,
              let status = line(root["status"], max: 80) else { return .unreadable }
        let custom = root["custom_attributes"] as? [String: Any]
        let detail = custom?["target_machine_detail"] as? [String: Any]
        let address = detail?["address"] as? [String: Any]
        let events = ((root["tracking_details"] as? [[String: Any]]) ?? []).prefix(maxEvents).compactMap { item -> ParcelEvent? in
            guard let name = line(item["status"], max: 80) else { return nil }
            return ParcelEvent(status: name, datetime: line(item["datetime"], max: 40))
        }
        return .found(ParcelTracking(
            number: number.digits, status: status, service: line(root["service"], max: 60),
            pickupPoint: line(custom?["target_machine_id"], max: 30),
            pickupAddress: [line(address?["line1"], max: 80), line(address?["line2"], max: 80)].compactMap { $0 }.joined(separator: ", ").nilIfEmpty,
            openingHours: line(detail?["opening_hours"], max: 40), events: Array(events),
            updatedAt: line(root["updated_at"], max: 40)))
    }

    /// One line, no control characters, cut to `max`; nil when empty or not text.
    private static func line(_ value: Any?, max: Int) -> String? {
        guard let text = value as? String else { return nil }
        let plain = String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(max))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: The person's list

public struct ParcelEntry: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let number: String
    /// The person's own name for it ("buty z Allegro"), at most `ParcelBook.maxLabel` characters.
    public var label: String?
    public let addedAt: Date
    public var lastStatus: String?
    public var lastChecked: Date?
}

/// The "Przesyłki" list, kept on this iPhone. It starts empty and off: nothing is added, and nothing
/// is looked up, until the person turns it on.
public struct ParcelBook: Equatable, Sendable, Codable {
    public static let maxParcels = 30
    public static let maxLabel = 40

    public enum AddResult: Equatable, Sendable {
        case added(ParcelEntry)
        case alreadyThere
        case full
        case notTurnedOn
    }

    public var isOn: Bool
    public private(set) var entries: [ParcelEntry]

    public init(isOn: Bool = false, entries: [ParcelEntry] = []) {
        self.isOn = isOn
        self.entries = entries
    }

    public mutating func add(_ number: ParcelNumber, label: String?, now: Date, id: UUID = UUID()) -> AddResult {
        guard isOn else { return .notTurnedOn }
        guard !entries.contains(where: { $0.number == number.digits }) else { return .alreadyThere }
        guard entries.count < Self.maxParcels else { return .full }
        let clean = label.map {
            String(String.UnicodeScalarView($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let entry = ParcelEntry(id: id, number: number.digits, label: clean.flatMap { $0.isEmpty ? nil : String($0.prefix(Self.maxLabel)) },
                                addedAt: now, lastStatus: nil, lastChecked: nil)
        entries.append(entry)
        return .added(entry)
    }

    public mutating func remove(id: UUID) { entries.removeAll { $0.id == id } }

    /// Remembers the latest answer for a parcel.
    public mutating func record(_ tracking: ParcelTracking, now: Date) {
        guard let index = entries.firstIndex(where: { $0.number == tracking.number }) else { return }
        entries[index].lastStatus = tracking.status
        entries[index].lastChecked = now
    }

    /// Turning it off, or "delete all": the numbers go with it.
    public mutating func turnOff() {
        isOn = false
        entries = []
    }
}
