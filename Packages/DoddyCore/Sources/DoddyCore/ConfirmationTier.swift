import Foundation

/// How a voice tool is confirmed (decision `2026-11-14-spoken-yes-and-fewer-cards`; the owner's choice of
/// 14 Nov 2026: "„Tak” głosem na wszystko", only money and bookings keep a tap).
///
/// The app follows the table in two parts (step 2 of the decision). First, every card takes the person's spoken
/// yes unless its tool is tap only (`SpokenConfirmation`, the voice controller, `AskFirst`'s own cards). Then the
/// tools on the at-once tier lose their card; until then each still shows it, and a yes or a tap runs it.
public enum ConfirmationTier: String, Sendable, Equatable, CaseIterable {
    /// Runs as soon as it's asked and Doddy says what it did. Doddy's own things on this iPhone, each undone
    /// in one step (Undo, `undo_last`) where it changed something, plus every look and read that runs at once today.
    case atOnce
    /// The card shows the exact payload and Doddy reads it out; a tap, or the person's own short spoken yes
    /// said after the card appeared (`SpokenYes`: strict, any "no", "wait" or "but" undoes it), runs exactly that.
    case spokenYes
    /// Money and bookings (decision 2026-11-27-voice-first-doddy, step 3; owner, 27 Nov 2026: "Strong spoken yes"): the
    /// card shows the exact amount, who gets it or what is booked, and Doddy reads it out. A tap runs it, or the person's
    /// own words naming the action (`StrongSpokenYes`: "tak, zapłać", "yes, book it"); a plain "tak" does not. Once text
    /// from outside is in the conversation it is a tap only again (`afterOutsideContent`).
    case strongSpokenYes
    /// Only a tap on the card: a tool nobody classified (it fails safe), and money and bookings once text from outside
    /// (an email, a page, the screen) is in the conversation.
    case tapOnly

    /// When a card for it is up, the person's own spoken yes may run it: every tier but tap only. (A tool on the
    /// at-once tier that still shows its card takes a yes too; it needs none once it runs without the card.)
    public var acceptsSpokenYes: Bool { self != .tapOnly }
    /// A card with the exact payload is shown before it runs.
    public var showsCard: Bool { self != .atOnce }
}

public enum ConfirmationTiers {
    /// Bookings and orders (decision 2026-11-27-voice-first-doddy, step 3): a tap, or the person's own words naming the
    /// action (`StrongSpokenYes`); never a plain yes. `call_places` books a table, orders food (paid on delivery) or asks
    /// one question by phone (`strongAction(for:)` says which); `book_flight` books and pays for a flight.
    public static let strongYes: Set<String> = ["book_flight", "call_places", "tell_by_phone"]
    /// A tap only. Paying for a page (ADR-736) asks for Face ID after the tap, so the person is looking at the iPhone
    /// anyway, and the page it pays for is text from outside: a spoken phrase would save nothing and open a way in.
    public static let tapOnly: Set<String> = ["pay_for_page"]

    /// Doddy's own things on this iPhone that move from a card to at once: each is undone in one step, or changes
    /// nothing anywhere (a draft the person sends themselves, a checklist, a map). Added to `AskFirst.runsAtOnce`.
    public static let ownUndoableAtOnce: Set<String> = [
        "set_timer", "set_alarm", "create_reminder", "save_memory", "remind_me_about_note", "remind_when_to_leave",
        "parking_spot", "create_list", "add_ingredients", "open_map", "open_camera", "open_food_app",
        "lost_wallet", "draft_message", "draft_blik_transfer", "draft_invoice", "make_presentation",
        // `undo_last` is not here (step 2b): nothing undoes an undo, so it keeps its card and a spoken yes.
    ]

    /// Every tool Doddy has, by name (`ToolCatalog.all`).
    static let known: Set<String> = Set(ToolCatalog.all.map(\.name))

    /// The tier of a tool by its name. A name nobody classified (a new tool, a typo) is tap-only: it fails safe.
    public static func tier(for tool: String, outsideContentSeen: Bool = false) -> ConfirmationTier {
        let base: ConfirmationTier
        if tapOnly.contains(tool) || !known.contains(tool) {
            base = .tapOnly
        } else if strongYes.contains(tool) {
            base = .strongSpokenYes
        } else if AskFirst.runsAtOnce(tool) || ownUndoableAtOnce.contains(tool) {
            base = .atOnce
        } else {
            base = .spokenYes
        }
        return afterOutsideContent(base, outsideContentSeen, asksOnce: ownUndoableAtOnce.contains(tool))
    }

    /// `parking_spot` is three things: saving and finding run at once, forgetting the spot goes on a spoken yes
    /// (nothing brings it back). After outside text, saving asks once like Doddy's other own things; finding the car
    /// is a look and still runs at once.
    public static func tier(forParking action: ParkingAction, outsideContentSeen: Bool = false) -> ConfirmationTier {
        switch action {
        case .clear: return afterOutsideContent(.spokenYes, outsideContentSeen, asksOnce: false)
        case .find: return .atOnce
        case .save: return tier(for: "parking_spot", outsideContentSeen: outsideContentSeen)
        }
    }

    /// The tier of a call as the app received it: `parking_spot` by what it does with the spot, every other tool by
    /// its name (`toolName`, exactly as the call named it, so an unknown name stays tap only).
    public static func tier(for request: VoiceToolRequest, toolName: String, outsideContentSeen: Bool = false) -> ConfirmationTier {
        if case .parkingSpot(let action) = request, toolName == VoiceToolName.parkingSpot {
            return tier(forParking: action, outsideContentSeen: outsideContentSeen)
        }
        return tier(for: toolName, outsideContentSeen: outsideContentSeen)
    }

    /// Once text from outside (an email, a web page, a document, an online account, the shared screen) has come into
    /// the conversation (`OutsideContentSession`), Doddy asks one spoken question before any change, and the person's
    /// own short yes is enough (owner, 15 Nov 2026, option 2; decision `2026-11-15-after-outside-text-one-question`):
    /// - Doddy's own things that otherwise run at once (`asksOnce`: a note, a reminder, a timer, a list, a draft…) stop
    ///   running at once and wait for that yes, so words from an email can never change anything silently;
    /// - a change that already asks keeps taking a spoken yes (until 15 Nov it needed a tap here);
    /// - money and bookings stay tap only, and looks and reads still run at once;
    /// - Doddy's session things that touch nothing outside it and stop in one step (the stopwatch, focus, wind-down,
    ///   the translator, following a news topic, the training plan screen, noting a missing capability) also still
    ///   start at once; items for a list ask through the session rule (`AskFirst.need(for:in:listIsShared:)`).
    /// Since 25 Nov 2026 (owner: "he should not be really asking anything", decision 2026-11-25-doddy-acts-without-asking)
    /// outside text no longer changes a tier: Doddy's own things keep running at once. The text stays data, never an
    /// instruction, and every change that already asked keeps its card. Kept as the one place a future rule would go.
    /// Money and bookings are the exception (decision 2026-11-27-voice-first-doddy, step 3): after an email, a page or
    /// the screen they take a tap only, since that is where words from outside could try to make Doddy pay or book.
    static func afterOutsideContent(_ tier: ConfirmationTier, _ outsideContentSeen: Bool, asksOnce: Bool) -> ConfirmationTier {
        if tier == .strongSpokenYes, outsideContentSeen { return .tapOnly }
        return tier
    }

    /// What a money or booking card's words must name (`StrongSpokenYes`): paying, booking, ordering, or (a plain
    /// question by phone) calling. Nil for every other call.
    public static func strongAction(for request: VoiceToolRequest, toolName: String) -> StrongSpokenYes.Action? {
        switch toolName {
        case "pay_for_page": return .pay
        case VoiceToolName.tellByPhone: return .call
        case "book_flight": return .book
        case VoiceToolName.callPlaces:
            guard case .callPlaces(let draft) = request else { return .call }
            if draft.order != nil { return .order }
            if draft.booking != nil { return .book }
            return .call
        default: return nil
        }
    }
}

/// The person's own words while a card is up (step 2 of decision `2026-11-14-spoken-yes-and-fewer-cards`). They run
/// exactly what the card shows, as a tap would, only when all of this holds:
/// - the tool is not tap only (`ConfirmationTier.acceptsSpokenYes`: money, bookings and anything unclassified need a
///   finger; since 15 Nov 2026 text from outside in the conversation no longer does);
/// - the words are a short yes and nothing else (`SpokenYes`: "tak, ale…", "nie", "czekaj" are not);
/// - they came at least `earliest` after the card appeared, so Doddy had begun reading it out and they aren't words
///   left over from before it, and no later than `latest`, the time a card waits for a tap (`AskLedger.window`);
/// - the card doesn't wait for the person to choose something on it (several places Maps found, for example).
/// Anything else leaves the card up for a tap; nothing here runs anything.
public enum SpokenConfirmation {
    public static let earliest: TimeInterval = 1
    public static let latest: TimeInterval = 120

    /// `action`: for money and bookings (`ConfirmationTier.strongSpokenYes`), what the words must name; without it such
    /// a card never runs on words.
    public static func runs(_ words: String, tier: ConfirmationTier, cardShownAt: Date, now: Date, waitsForAChoice: Bool = false,
                            action: StrongSpokenYes.Action? = nil) -> Bool {
        guard tier.acceptsSpokenYes, !waitsForAChoice else { return false }
        let age = now.timeIntervalSince(cardShownAt)
        guard age.isFinite, age >= earliest, age <= latest else { return false }
        if tier == .strongSpokenYes {
            guard let action else { return false }
            return StrongSpokenYes.isYes(words, for: action)
        }
        return SpokenYes.isYes(words)
    }
}

extension ConfirmationTiers {
    /// What `voice-agent/tools.json` says for a tool (`x_doddy.ask`), the agent's half of the same rule: `runs_now`
    /// for what the app runs at once without a card (`AskFirst.runsAtOnce`), `tap` for money and bookings, and
    /// `yes_or_tap` for every other tool, which shows a card the person's spoken yes or a tap answers.
    public static func specAsk(for tool: String) -> RealtimeToolSpec.Ask {
        if AskFirst.runsAtOnce(tool) { return .runsNow }
        switch tier(for: tool) {
        case .strongSpokenYes: return .strongYesOrTap
        case .tapOnly: return .tap
        default: return .yesOrTap
        }
    }
}

/// The person's own words for money and bookings (decision 2026-11-27-voice-first-doddy, step 3): a short answer that
/// names the action ("tak, zapłać", "zarezerwuj", "yes, pay it", "tak, zamów"), with nothing else in it but a yes or a
/// please. A plain "tak", an action the card isn't about ("tak, zamów" on a payment), any other word (an amount, a
/// change, "ale…") or any veto from `SpokenYes` runs nothing, and the card waits for a tap.
public enum StrongSpokenYes {
    public enum Action: String, Sendable, CaseIterable {
        case pay, book, order, call

        /// The words that name it, in the app's languages, lower-cased.
        var verbs: Set<String> {
            switch self {
            case .pay: ["zapłać", "zaplac", "płać", "plac", "zapłacę", "zaplace", "pay", "bezahlen", "bezahle", "payer", "paie", "paga", "pagar"]
            case .book: ["zarezerwuj", "rezerwuj", "zarezerwuję", "zarezerwuje", "book", "buchen", "buche", "réserve", "reserve", "réserver", "reserver", "reserva", "reservar"]
            case .order: ["zamów", "zamow", "zamawiaj", "zamówię", "zamowie", "order", "bestellen", "bestelle", "commande", "commander", "pide", "pedir"]
            case .call: ["dzwoń", "dzwon", "zadzwoń", "zadzwon", "call", "anrufen", "appelle", "appeler", "llama", "llamar"]
            }
        }

        /// What Doddy asks the person to say, for the card's header.
        public func phrase(polish: Bool) -> String {
            switch self {
            case .pay: polish ? "tak, zapłać" : "yes, pay"
            case .book: polish ? "tak, zarezerwuj" : "yes, book it"
            case .order: polish ? "tak, zamów" : "yes, order it"
            case .call: polish ? "tak, dzwoń" : "yes, call"
            }
        }
    }

    /// Words that may stand with the action and change nothing.
    static let fillers: Set<String> = [
        "tak", "yes", "yeah", "ok", "okay", "okej", "proszę", "prosze", "please", "it", "to", "now", "teraz", "go", "ahead",
        "jasne", "dobrze", "sure", "ja", "oui", "sí", "si", "bitte", "por", "favor", "s'il", "te", "plaît", "plait",
    ]

    public static func isYes(_ said: String, for action: Action) -> Bool {
        let words = said.lowercased()
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 5 else { return false }
        if words.contains(where: SpokenYes.vetoes.contains) { return false }
        // Only digits gone: "zapłać 50" has a number the card already shows; it is not a yes to something else, but it
        // isn't a clean answer either, so it runs nothing (the split above drops digits, so check the raw text).
        if said.rangeOfCharacter(from: .decimalDigits) != nil { return false }
        guard words.contains(where: action.verbs.contains) else { return false }
        return words.allSatisfy { action.verbs.contains($0) || fillers.contains($0) }
    }
}
