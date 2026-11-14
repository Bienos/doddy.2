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
    /// Only a tap on the card: money, and bookings made by phone.
    case tapOnly

    /// When a card for it is up, the person's own spoken yes may run it: every tier but tap only. (A tool on the
    /// at-once tier that still shows its card takes a yes too; it needs none once it runs without the card.)
    public var acceptsSpokenYes: Bool { self != .tapOnly }
    /// A card with the exact payload is shown before it runs.
    public var showsCard: Bool { self != .atOnce }
}

public enum ConfirmationTiers {
    /// Money, and bookings: a spoken yes is never enough. `call_places` books a table or orders food by phone.
    public static let tapOnly: Set<String> = ["pay_for_page", "book_flight", "call_places"]

    /// Doddy's own things on this iPhone that move from a card to at once: each is undone in one step, or changes
    /// nothing anywhere (a draft the person sends themselves, a checklist, a map). Added to `AskFirst.runsAtOnce`.
    public static let ownUndoableAtOnce: Set<String> = [
        "set_timer", "set_alarm", "create_reminder", "save_memory", "remind_me_about_note", "remind_when_to_leave",
        "parking_spot", "create_list", "add_ingredients", "open_map", "open_camera", "open_food_app", "undo_last",
        "lost_wallet", "draft_message", "draft_blik_transfer", "draft_invoice", "make_presentation",
    ]

    /// Every tool Doddy has, by name (`ToolCatalog.all`).
    static let known: Set<String> = Set(ToolCatalog.all.map(\.name))

    /// The tier of a tool by its name. A name nobody classified (a new tool, a typo) is tap-only: it fails safe.
    public static func tier(for tool: String, outsideContentSeen: Bool = false) -> ConfirmationTier {
        let base: ConfirmationTier
        if tapOnly.contains(tool) || !known.contains(tool) {
            base = .tapOnly
        } else if AskFirst.runsAtOnce(tool) || ownUndoableAtOnce.contains(tool) {
            base = .atOnce
        } else {
            base = .spokenYes
        }
        return afterOutsideContent(base, outsideContentSeen)
    }

    /// `parking_spot` is three things: saving and finding run at once, forgetting the spot goes on a spoken yes
    /// (nothing brings it back).
    public static func tier(forParking action: ParkingAction, outsideContentSeen: Bool = false) -> ConfirmationTier {
        if case .clear = action { return afterOutsideContent(.spokenYes, outsideContentSeen) }
        return tier(for: "parking_spot", outsideContentSeen: outsideContentSeen)
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
    /// the conversation (`OutsideContentSession`), a spoken yes is not enough: words from there could have led to the
    /// ask, so only a tap runs it. Doddy's own undoable things stay at once.
    static func afterOutsideContent(_ tier: ConfirmationTier, _ outsideContentSeen: Bool) -> ConfirmationTier {
        outsideContentSeen && tier == .spokenYes ? .tapOnly : tier
    }
}

/// The person's own words while a card is up (step 2 of decision `2026-11-14-spoken-yes-and-fewer-cards`). They run
/// exactly what the card shows, as a tap would, only when all of this holds:
/// - the tool is not tap only (`ConfirmationTier.acceptsSpokenYes`: money, bookings, anything unclassified, and every
///   change once text from outside is in the conversation need a finger);
/// - the words are a short yes and nothing else (`SpokenYes`: "tak, ale…", "nie", "czekaj" are not);
/// - they came at least `earliest` after the card appeared, so Doddy had begun reading it out and they aren't words
///   left over from before it, and no later than `latest`, the time a card waits for a tap (`AskLedger.window`);
/// - the card doesn't wait for the person to choose something on it (several places Maps found, for example).
/// Anything else leaves the card up for a tap; nothing here runs anything.
public enum SpokenConfirmation {
    public static let earliest: TimeInterval = 1
    public static let latest: TimeInterval = 120

    public static func runs(_ words: String, tier: ConfirmationTier, cardShownAt: Date, now: Date, waitsForAChoice: Bool = false) -> Bool {
        guard tier.acceptsSpokenYes, !waitsForAChoice else { return false }
        let age = now.timeIntervalSince(cardShownAt)
        guard age.isFinite, age >= earliest, age <= latest else { return false }
        return SpokenYes.isYes(words)
    }
}

extension ConfirmationTiers {
    /// What `voice-agent/tools.json` says for a tool (`x_doddy.ask`), the agent's half of the same rule: `runs_now`
    /// for what the app runs at once without a card (`AskFirst.runsAtOnce`), `tap` for money and bookings, and
    /// `yes_or_tap` for every other tool, which shows a card the person's spoken yes or a tap answers.
    public static func specAsk(for tool: String) -> RealtimeToolSpec.Ask {
        if AskFirst.runsAtOnce(tool) { return .runsNow }
        return tier(for: tool) == .tapOnly ? .tap : .yesOrTap
    }
}
