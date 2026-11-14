import Foundation

/// How a voice tool is confirmed (decision `2026-11-14-spoken-yes-and-fewer-cards`; the owner's choice of
/// 14 Nov 2026: "„Tak” głosem na wszystko", only money and bookings keep a tap).
///
/// This is the table the app is to follow; `AskFirst.need(for:)` is still what runs today, until the voice
/// controller is moved onto this table (step 2 of the decision).
public enum ConfirmationTier: String, Sendable, Equatable, CaseIterable {
    /// Runs as soon as it's asked and Doddy says what it did. Doddy's own things on this iPhone, each undone
    /// in one step (Undo, `undo_last`) where it changed something, plus every look and read that runs at once today.
    case atOnce
    /// The card shows the exact payload and Doddy reads it out; a tap, or the person's own short spoken yes
    /// said after the card appeared (`SpokenYes`: strict, any "no", "wait" or "but" undoes it), runs exactly that.
    case spokenYes
    /// Only a tap on the card: money, and bookings made by phone.
    case tapOnly

    /// The person's own spoken yes may run it.
    public var acceptsSpokenYes: Bool { self == .spokenYes }
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

    /// Once text from outside (an email, a web page, a document, an online account, the shared screen) has come into
    /// the conversation (`OutsideContentSession`), a spoken yes is not enough: words from there could have led to the
    /// ask, so only a tap runs it. Doddy's own undoable things stay at once.
    static func afterOutsideContent(_ tier: ConfirmationTier, _ outsideContentSeen: Bool) -> ConfirmationTier {
        outsideContentSeen && tier == .spokenYes ? .tapOnly : tier
    }
}
