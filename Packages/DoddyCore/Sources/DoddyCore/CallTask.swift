import Foundation

// Call tasks (decision docs/decisions/2026-11-09-restaurant-calls-one-tap.md): up to three places,
// one card, one tap. The server (server/messaging/src/taskCalls/tasks.ts) checks and compiles each
// place exactly like a single call case, returns one card with every place's preview and a task
// digest, and after the tap calls the places one after another until one gives a clear yes. The
// rules here are early hints on the iPhone; the server decides.

public enum CallTaskLimits {
    public static let maxPlaces = 3
    public static let nameLength = 80
    public static let goalLength = 160
    public static let questionLength = 200
    /// The booking name, as the server allows (letters, spaces, apostrophes, dots, hyphens).
    public static let bookingNameLength = 60
    public static let serviceLength = 80
    public static let maxPartySize = 20
    /// An order, as the server allows (server/messaging/src/taskCalls/order.ts).
    public static let maxOrderLines = 8
    public static let maxLineQuantity = 20
    public static let orderItemLength = 80
    public static let orderNoteLength = 60
    public static let addressLength = 80
    public static let cityLength = 60
    public static let apartmentLength = 20
    public static let minTotalPln = 10
    public static let maxTotalPln = 500
    public static let defaultTotalPln = 150
}

/// One place to call: its name as the user or the place search gave it, and its number.
public struct CallTaskPlace: Equatable, Sendable {
    public let name: String
    public let phone: String

    public init(name: String, phone: String) {
        self.name = name
        self.phone = phone
    }
}

/// A booking Doddy may make on the call (decision docs/decisions/2026-11-12-book-agent.md). The server
/// builds every sentence from it, including the one sentence that accepts it; the card shows them.
/// Same shape as the server's `bookingSchema` (server/messaging/src/taskCalls/booking.ts).
public struct CallTaskBooking: Codable, Equatable, Sendable {
    /// The name the booking is under, as the user said it ("Anna Kowalska").
    public let name: String
    /// The day, `YYYY-MM-DD`, Warsaw time.
    public let date: String
    /// The start time, `HH:MM`, 24-hour.
    public let time: String
    /// "strzyżenie męskie", "manicure"; nil for a table, which needs `partySize`.
    public let service: String?
    public let partySize: Int?

    public init(name: String, date: String, time: String, service: String? = nil, partySize: Int? = nil) {
        self.name = name
        self.date = date
        self.time = time
        self.service = service
        self.partySize = partySize
    }
}

/// A food order Doddy may place on the call (decision docs/decisions/2026-11-12-food-by-phone.md).
/// Payment is on delivery or at pickup only; no payment detail is ever part of it. The server builds
/// every sentence from it, including the one that accepts it. Same shape as the server's
/// `orderSchema` (server/messaging/src/taskCalls/order.ts).
public struct CallTaskOrder: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public let quantity: Int
        public let name: String
        /// "bez cebuli"; nil for none.
        public let note: String?

        public init(quantity: Int, name: String, note: String? = nil) {
            self.quantity = quantity
            self.name = name
            self.note = note
        }
    }

    /// Typed on the card for this one call, never saved as a home address.
    public struct Delivery: Codable, Equatable, Sendable {
        public let street: String
        public let apartment: String?
        /// `NN-NNN`.
        public let postcode: String
        public let city: String
        /// The courier's number, nine digits ("600 000 000"); the server normalises it.
        public let phone: String

        public init(street: String, apartment: String? = nil, postcode: String, city: String, phone: String) {
            self.street = street
            self.apartment = apartment
            self.postcode = postcode
            self.city = city
            self.phone = phone
        }
    }

    /// The name the order is under.
    public let name: String
    public let lines: [Line]
    /// Exactly one of `delivery` and `pickup`.
    public let delivery: Delivery?
    public let pickup: Bool?
    /// The most the person will pay, in whole zł; Doddy never accepts a higher total.
    public let maxTotalPln: Int

    public init(name: String, lines: [Line], delivery: Delivery? = nil, pickup: Bool = false,
                maxTotalPln: Int = CallTaskLimits.defaultTotalPln) {
        self.name = name
        self.lines = lines
        self.delivery = delivery
        self.pickup = pickup ? true : nil
        self.maxTotalPln = maxTotalPln
    }
}

/// What the voice tool `call_places` asked for. The user's first name is added by the app when it
/// builds the request (`body`), from the approved name in About you.
public struct CallTaskDraft: Equatable, Sendable {
    public let places: [CallTaskPlace]
    /// One question, asked word for word at every place ("Czy mają Państwo wolny stolik…"). Empty for
    /// a booking: the server builds that question from `booking`.
    public let question: String
    /// What the user wants, in one sentence; shown on the card, never said on the call.
    public let goal: String
    /// "Text me the result": a text to the user's own verified number when the task ends.
    public let textResult: Bool
    /// Set for a call that books (decision 2026-11-12-book-agent); nil for one that only asks.
    public let booking: CallTaskBooking?
    /// Set for a call that orders food (decision 2026-11-12-food-by-phone); one place only.
    public let order: CallTaskOrder?

    public init(places: [CallTaskPlace], question: String, goal: String, textResult: Bool,
                booking: CallTaskBooking? = nil, order: CallTaskOrder? = nil) {
        self.places = places
        self.question = question
        self.goal = goal
        self.textResult = textResult
        self.booking = booking
        self.order = order
    }

    /// The body of `POST /v1/call-tasks` (the server's strict schema). Every number is marked as
    /// found by Doddy's place search, which the card says.
    public func body(principalName: String, principalGenitive: String? = nil,
                     maxDurationSecs: Int = CallBriefDraft.defaultMaxDuration) -> CallTaskBody {
        CallTaskBody(
            kind: order != nil ? "order" : (booking == nil ? "ask" : "book"),
            places: places.map { .init(name: $0.name, phone: $0.phone, source: .places, sourceLabel: nil) },
            principal: .init(name: principalName, genitive: principalGenitive ?? PolishGenitive.suggest(principalName)),
            goal: goal, question: (booking == nil && order == nil) ? question : nil, booking: booking, order: order, facts: [],
            maxDurationSecs: maxDurationSecs, textResult: textResult)
    }
}

/// The body of `POST /v1/call-tasks`. An ask carries `question`; a booking carries `booking` and no
/// question (nil values are left out of the JSON).
public struct CallTaskBody: Encodable, Equatable, Sendable {
    public var kind = "ask"
    public let places: [CallBriefBody.Callee]
    public let principal: CallBriefBody.Principal
    public let goal: String
    public let question: String?
    public let booking: CallTaskBooking?
    public let order: CallTaskOrder?
    public let facts: [CallBriefBody.Fact]
    public let maxDurationSecs: Int
    public let textResult: Bool
}

/// What the card shows: every place's preview, built by the server from the exact payload it will
/// send, and the digest the one tap approves.
public struct CallTaskPreview: Decodable, Equatable, Sendable {
    public let taskId: UUID
    /// "book" for a call that may book (decision 2026-11-12-book-agent), "order" for one that may order food
    /// (2026-11-12-food-by-phone); "ask", or nil from older servers.
    public let kind: String?
    public let digest: String
    public let approvableUntil: String
    public let textResult: Bool
    public let places: [CallPreview]
    /// Whether the first call would fit inside the calling hours right now.
    public let callableNow: Bool?

    public var isBooking: Bool { kind == "book" }
    public var isOrder: Bool { kind == "order" }
}

extension VoiceToolRequest {
    /// `place_names` and `place_phones` (1 to 3 each, matched by position), `question`, `goal`,
    /// optional `text_result` (default true). Exactly as the agent wrote them: the card shows them
    /// and the server checks them again.
    static func parseCallPlaces(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard case .list(let names) = args.stringList("place_names"), !names.isEmpty else {
            return .invalid(name: name, reason: "missing place_names")
        }
        guard case .list(let phones) = args.stringList("place_phones"), phones.count == names.count else {
            return .invalid(name: name, reason: "place_phones needs one number for each name, in the same order; find a number first, never guess one")
        }
        guard names.count <= CallTaskLimits.maxPlaces else {
            return .invalid(name: name, reason: "at most \(CallTaskLimits.maxPlaces) places; pick the best \(CallTaskLimits.maxPlaces)")
        }
        var places: [CallTaskPlace] = []
        var numbers: Set<String> = []
        for (rawName, rawPhone) in zip(names, phones) {
            let placeName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = rawPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !placeName.isEmpty else { return .invalid(name: name, reason: "every place needs a name") }
            guard placeName.count <= CallTaskLimits.nameLength else {
                return .invalid(name: name, reason: "a place's name is longer than \(CallTaskLimits.nameLength) characters")
            }
            guard !phone.isEmpty else { return .invalid(name: name, reason: "\(placeName) has no phone number; find it first, never guess one") }
            switch PolishNumber.classify(phone) {
            case .refused(let reason):
                return .invalid(name: name, reason: "Doddy can't call \(placeName)'s number (\(reason.rawValue)); leave that place out")
            case .allowed(let e164, _):
                guard numbers.insert(e164).inserted else { return .invalid(name: name, reason: "the same number is listed twice") }
            }
            places.append(CallTaskPlace(name: placeName, phone: phone))
        }
        // A booking (decision 2026-11-12-book-agent): Doddy's server writes the question and the one
        // sentence that accepts the booking, so the agent passes the booking's details instead.
        let booking: CallTaskBooking?
        switch parseBooking(args) {
        case .none: booking = nil
        case .booking(let b): booking = b
        case .invalid(let reason): return .invalid(name: name, reason: reason)
        }
        let order: CallTaskOrder?
        switch parseOrder(args) {
        case .none: order = nil
        case .order(let o): order = o
        case .invalid(let reason): return .invalid(name: name, reason: reason)
        }
        if order != nil {
            guard booking == nil else {
                return .invalid(name: name, reason: "a call either books or orders, never both")
            }
            guard places.count == 1 else {
                return .invalid(name: name, reason: "an order goes to exactly one place; a second restaurant is a new order the user approves separately")
            }
        }
        let question: String
        if order != nil {
            guard args.text("question") == nil else {
                return .invalid(name: name, reason: "for an order, leave out question: Doddy's server asks for exactly the order")
            }
            question = ""
        } else if booking != nil {
            guard args.text("question") == nil else {
                return .invalid(name: name, reason: "for a booking, leave out question: Doddy's server asks for exactly the booking")
            }
            question = ""
        } else {
            guard let q = args.text("question"), q.count >= 5 else { return .invalid(name: name, reason: "missing question") }
            guard q.count <= CallTaskLimits.questionLength else {
                return .invalid(name: name, reason: "the question is longer than \(CallTaskLimits.questionLength) characters")
            }
            question = q
        }
        guard let goal = args.text("goal"), goal.count >= 3 else { return .invalid(name: name, reason: "missing goal") }
        guard goal.count <= CallTaskLimits.goalLength else {
            return .invalid(name: name, reason: "the goal is longer than \(CallTaskLimits.goalLength) characters")
        }
        let written = [question, goal] + places.map(\.name) + [booking?.name, booking?.service].compactMap { $0 }
            + orderTexts(order)
        if written.contains(where: { $0.contains("{") || $0.contains("}") }) {
            return .invalid(name: name, reason: "no curly braces in the question, goal, names, booking or order")
        }
        let textResult = args.has("text_result") ? args.flag("text_result") : true
        return .callPlaces(CallTaskDraft(places: places, question: question, goal: goal, textResult: textResult, booking: booking, order: order))
    }

    private enum ParsedBooking { case none, booking(CallTaskBooking), invalid(String) }

    /// `booking_name`, `booking_date` (YYYY-MM-DD), `booking_time` (HH:MM), and `booking_service` or
    /// `booking_party_size`. None of them: a call that only asks. Some but not all: refused.
    private static func parseBooking(_ args: Arguments) -> ParsedBooking {
        let keys = ["booking_name", "booking_date", "booking_time", "booking_service", "booking_party_size"]
        guard keys.contains(where: { args.has($0) }) else { return .none }
        guard let bookingName = args.text("booking_name"), !bookingName.isEmpty else {
            return .invalid("missing booking_name: ask the user whose name the booking is under; never guess it")
        }
        guard bookingName.count <= CallTaskLimits.bookingNameLength else {
            return .invalid("booking_name is longer than \(CallTaskLimits.bookingNameLength) characters")
        }
        guard let date = args.text("booking_date"), date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return .invalid("booking_date must be the day as YYYY-MM-DD, e.g. 2026-11-14")
        }
        guard let time = args.text("booking_time"), time.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else {
            return .invalid("booking_time must be HH:MM in 24-hour time, e.g. 19:00")
        }
        let service = args.text("booking_service")
        if let service, service.count > CallTaskLimits.serviceLength {
            return .invalid("booking_service is longer than \(CallTaskLimits.serviceLength) characters")
        }
        var partySize: Int?
        if args.has("booking_party_size") {
            guard let n = args.number("booking_party_size"), n == n.rounded(), n >= 1, n <= Double(CallTaskLimits.maxPartySize) else {
                return .invalid("booking_party_size must be a whole number from 1 to \(CallTaskLimits.maxPartySize)")
            }
            partySize = Int(n)
        }
        guard service != nil || partySize != nil else {
            return .invalid("a booking needs booking_service (e.g. 'strzyżenie męskie') or booking_party_size (for a table)")
        }
        return .booking(CallTaskBooking(name: bookingName, date: date, time: time, service: service, partySize: partySize))
    }

    private enum ParsedOrder { case none, order(CallTaskOrder), invalid(String) }

    private static func orderTexts(_ o: CallTaskOrder?) -> [String] {
        guard let o else { return [] }
        let d = o.delivery
        return [o.name] + o.lines.flatMap { [$0.name, $0.note].compactMap { $0 } }
            + [d?.street, d?.apartment, d?.city].compactMap { $0 }
    }

    /// `order_name`, `order_item_names` with `order_item_quantities` (same order; optional
    /// `order_item_notes`, "" for none), then `order_street`, `order_postcode`, `order_city`,
    /// `order_phone` (and `order_apartment`) for delivery, or `order_pickup: true`; optional
    /// `order_max_total_pln`. None of them: not an order. Some but not all: refused.
    private static func parseOrder(_ args: Arguments) -> ParsedOrder {
        let keys = ["order_name", "order_item_names", "order_item_quantities", "order_item_notes", "order_street",
                    "order_apartment", "order_postcode", "order_city", "order_phone", "order_pickup", "order_max_total_pln"]
        guard keys.contains(where: { args.has($0) }) else { return .none }
        guard let orderName = args.text("order_name") else {
            return .invalid("missing order_name: ask the user whose name the order is under; never guess it")
        }
        guard orderName.count <= CallTaskLimits.bookingNameLength else {
            return .invalid("order_name is longer than \(CallTaskLimits.bookingNameLength) characters")
        }
        guard case .list(let names) = args.stringList("order_item_names"), !names.isEmpty else {
            return .invalid("missing order_item_names: the dishes, one per entry")
        }
        guard names.count <= CallTaskLimits.maxOrderLines else {
            return .invalid("at most \(CallTaskLimits.maxOrderLines) lines in one order")
        }
        guard let quantities = args.numbers("order_item_quantities"), quantities.count == names.count else {
            return .invalid("order_item_quantities needs one whole number for each dish, in the same order")
        }
        var notes: [String] = []
        switch args.stringList("order_item_notes") {
        case .absent: notes = Array(repeating: "", count: names.count)
        case .list(let list) where list.count == names.count: notes = list
        default: return .invalid("order_item_notes needs one entry for each dish (\"\" for none), in the same order")
        }
        var lines: [CallTaskOrder.Line] = []
        for ((rawName, quantity), rawNote) in zip(zip(names, quantities), notes) {
            let dish = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dish.isEmpty, dish.count <= CallTaskLimits.orderItemLength else {
                return .invalid("every dish needs a name of at most \(CallTaskLimits.orderItemLength) characters")
            }
            guard note.count <= CallTaskLimits.orderNoteLength else {
                return .invalid("a note is longer than \(CallTaskLimits.orderNoteLength) characters")
            }
            guard quantity == quantity.rounded(), quantity >= 1, quantity <= Double(CallTaskLimits.maxLineQuantity) else {
                return .invalid("a quantity must be a whole number from 1 to \(CallTaskLimits.maxLineQuantity)")
            }
            lines.append(.init(quantity: Int(quantity), name: dish, note: note.isEmpty ? nil : note))
        }
        var maxTotal = CallTaskLimits.defaultTotalPln
        if args.has("order_max_total_pln") {
            guard let n = args.number("order_max_total_pln"), n == n.rounded(),
                  n >= Double(CallTaskLimits.minTotalPln), n <= Double(CallTaskLimits.maxTotalPln) else {
                return .invalid("order_max_total_pln must be a whole number of zł from \(CallTaskLimits.minTotalPln) to \(CallTaskLimits.maxTotalPln)")
            }
            maxTotal = Int(n)
        }
        let pickup = args.flag("order_pickup")
        let addressKeys = ["order_street", "order_apartment", "order_postcode", "order_city", "order_phone"]
        if pickup {
            guard !addressKeys.contains(where: { args.has($0) }) else {
                return .invalid("a pickup order has no address: leave out order_street, order_postcode, order_city and order_phone")
            }
            return .order(CallTaskOrder(name: orderName, lines: lines, pickup: true, maxTotalPln: maxTotal))
        }
        guard let street = args.text("order_street"), street.count <= CallTaskLimits.addressLength else {
            return .invalid("a delivery needs order_street (at most \(CallTaskLimits.addressLength) characters), or set order_pickup: true. Ask the user; never guess an address")
        }
        guard let postcode = args.text("order_postcode"), postcode.range(of: #"^\d{2}-\d{3}$"#, options: .regularExpression) != nil else {
            return .invalid("order_postcode must look like 00-001")
        }
        guard let city = args.text("order_city"), city.count <= CallTaskLimits.cityLength else {
            return .invalid("a delivery needs order_city")
        }
        let apartment = args.text("order_apartment")
        if let apartment, apartment.count > CallTaskLimits.apartmentLength {
            return .invalid("order_apartment is longer than \(CallTaskLimits.apartmentLength) characters")
        }
        guard let phone = args.text("order_phone"), normalisedCourierPhone(phone) != nil else {
            return .invalid("order_phone must be the courier's Polish number, nine digits; ask the user")
        }
        let delivery = CallTaskOrder.Delivery(street: street, apartment: apartment, postcode: postcode, city: city, phone: phone)
        return .order(CallTaskOrder(name: orderName, lines: lines, delivery: delivery, maxTotalPln: maxTotal))
    }

    /// Nine digits once spaces, hyphens and a leading +48 or 0048 are dropped (the server's rule).
    static func normalisedCourierPhone(_ raw: String) -> String? {
        var digits = raw.filter { !$0.isWhitespace && $0 != "-" }
        for prefix in ["+48", "0048"] where digits.hasPrefix(prefix) { digits.removeFirst(prefix.count); break }
        guard digits.count == 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return digits
    }
}

extension VoiceToolReply {
    // MARK: call_places (decision 2026-11-09-restaurant-calls-one-tap)
    //
    // "started" means the first call is being dialled, never that anyone answered: the result comes
    // later by notification (and a text, if chosen), and the agent never hears it.

    public static func callTaskStarted(first: String, count: Int, textResult: Bool, booking: Bool = false, order: Bool = false) -> String {
        let rest = count > 1
            ? (booking ? " If they can't book exactly that, Doddy calls the next place, one at a time, and stops at the first booking."
                       : " If they don't say yes, Doddy calls the next place, one at a time, and stops at the first yes.")
            : ""
        let back = textResult ? "a notification and a text to the user's own number" : "a notification"
        let unknown = order ? "so don't say anyone answered or that anything is ordered."
                            : "so don't say anyone answered or that anything is booked."
        return "started: Doddy is calling \(first) now.\(rest) The answer comes back as \(back) when Doddy is done; it isn't known yet, \(unknown)"
    }

    public static let callTaskUnknown = """
        unknown: Doddy couldn't confirm whether the calls started. Don't say they did, and don't call call_places again \
        on your own: the first call may be ringing. The user can check in Settings, Phone calls, Calls for you.
        """

    public static let callTaskBookingOff =
        "failed: booking by phone isn't switched on on Doddy's server yet. Nobody was called. Offer to call and only ask whether they have a free slot instead."

    public static let callTaskOrderOff =
        "failed: ordering by phone isn't switched on on Doddy's server yet. Nobody was called. Offer to open the restaurant's page in the delivery app instead."

    public static let callTaskDeclined = "declined: the user chose not to have Doddy call these places. Nobody was called."

    public static let callTaskNoServer =
        "failed: Doddy's server isn't set up in this version of the app, so Doddy can't make calls yet. Nobody was called."

    public static let callTaskNoPhone =
        "failed: the user hasn't verified their phone number in Settings, Notifications and texts, which Doddy needs before it calls for them. Nobody was called."

    public static let callTaskNoName =
        "failed: Doddy needs the user's first name to say who it's calling for. They can add it in Settings, About you. Nobody was called."

    /// Before the card: why calls can't be made now.
    public static func callTaskNotReady(_ availability: CallCaseAvailability) -> String {
        if !availability.configured || availability.killSwitch {
            return "failed: calls from Doddy are switched off on Doddy's server right now. Nobody was called."
        }
        if !availability.phoneVerified { return callTaskNoPhone }
        return "failed: calls from Doddy aren't available right now (the call agent's settings need a check). Nobody was called."
    }

    public static func callTaskRefused(_ error: Error) -> String {
        if case .offline? = error as? ServerError { return "failed: Doddy couldn't reach its server. Nobody was called." }
        switch error as? CallCaseError {
        case .destinationRefused(let reason)?:
            return "failed: one of the numbers isn't one Doddy may call (\(reason)). Leave that place out. Nobody was called."
        case .briefRefused(let field, let reason)?:
            return "failed: Doddy's server didn't accept the request (\(field): \(reason)). Nobody was called."
        case .notApprovable("outside_hours")?:
            return "failed: it's outside calling hours (8:00 to 23:00 Warsaw time), so nobody was called. Offer to try again in the morning."
        case .notApprovable("too_many_open_cases")?:
            return "failed: too many calls are already waiting in Calls for you. Nobody was called."
        case .gateRefused(let gate)?:
            return "failed: a limit stopped the first call (\(gate)). Nobody was called."
        case .callsDisabled?:
            return "failed: calls from Doddy are switched off on Doddy's server right now. Nobody was called."
        case .bookingNotConfigured?:
            return callTaskBookingOff
        case .orderNotConfigured?:
            return callTaskOrderOff
        case .server(.offline)?:
            return "failed: Doddy couldn't reach its server. Nobody was called."
        default:
            return "failed: something went wrong on Doddy's server. Nobody was called."
        }
    }
}
