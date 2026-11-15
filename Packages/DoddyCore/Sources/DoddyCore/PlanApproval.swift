import Foundation

// What a tap on the plan card is worth (DOD-07: the approval is bound to the exact payload shown; ASK-01: one tap,
// one run). The plan card (`propose_plan`, ADR-204) holds several changes, and the steps that go through Doddy's server
// (a Gmail draft, a Todoist task; ADR-209) come with a preview and a single-use approval that the server made for
// exactly those arguments when the card was put up. That approval lasts two minutes.
//
// A card nobody tapped for a while is old news: the server may now find another mail or page for the same words, a
// switch may have been turned off, the person may have moved on. A tap on such a card must never run the old plan.
// This file decides, from the clock and the payload only, whether a tap (or a spoken yes) on the card is for a fresh
// card with the payload it showed (run it, once), or for a card that ran out or no longer matches (run nothing; the
// app checks the steps again and shows the card again with what is true now). The voice controller does the
// checking and the showing; it never decides what a tap is worth.
//
// The clock is passed in at every call, as in `AskLedger`, so the window's edges are tested exactly.

/// What a plan card shows and what its approval is bound to: which tool each step is, and, for the steps Doddy's
/// server prepared, the preview text and the approval id that will be spent. The person's own ticks and Changes on
/// the card are theirs, seen on the card, and don't void it; a step's local arguments are checked again when it runs.
public struct PlanCardPayload: Equatable, Sendable {
    /// What the server prepared for one online-account step.
    public struct Prepared: Equatable, Sendable {
        public let preview: ToolPreview
        public let approvalID: UUID

        public init(preview: ToolPreview, approvalID: UUID) {
            self.preview = preview
            self.approvalID = approvalID
        }
    }

    /// Step number to tool name.
    public let tools: [Int: String]
    /// Step number to what the server prepared for it.
    public let prepared: [Int: Prepared]

    public init(tools: [Int: String], prepared: [Int: Prepared]) {
        self.tools = tools
        self.prepared = prepared
    }

    public init(steps: [PlanStep], prepared: [Int: Prepared]) {
        self.init(tools: Dictionary(uniqueKeysWithValues: steps.map { ($0.number, $0.toolName) }), prepared: prepared)
    }

    /// The steps whose card is not what `old` showed: another tool, a step that is new or gone, or a server preview
    /// with other words. A new approval id alone is not a change: every time the card is made again it gets new ones.
    public func changedSteps(since old: PlanCardPayload) -> Set<Int> {
        var changed: Set<Int> = []
        for number in Set(tools.keys).union(old.tools.keys) {
            if tools[number] != old.tools[number] || prepared[number]?.preview != old.prepared[number]?.preview {
                changed.insert(number)
            }
        }
        return changed
    }
}

public struct PlanApprovalGate: Sendable {
    /// How long a card, and the server approvals made for it, stay good for a tap: counted from when the steps were
    /// prepared. It stays inside `approvalLife` so that every step's approval is still alive when its turn comes in
    /// the run that follows the tap. A tap at exactly this age still counts.
    public static let window: TimeInterval = 90
    /// How long Doddy's server's single-use approval works (backend `AskGate`: two minutes).
    public static let approvalLife: TimeInterval = 120
    /// A card that was just shown again takes no tap for this long, so the press that asked for the new card, or a
    /// double tap that lands as it appears, is never taken for the person's look at it. The same second a spoken yes
    /// waits for (`SpokenConfirmation.earliest`).
    public static let settle: TimeInterval = 1

    /// Where an answer came from. Nothing here for the agent's words, a tool's result, an email or a web page: those
    /// can never answer a card.
    public enum Answer: Equatable, Sendable {
        case tapped
        /// The user's own short yes, already checked by `SpokenYes` and `SpokenConfirmation` for this card's tier.
        case userSaid
    }

    public enum Decision: Equatable, Sendable {
        /// The card is fresh and the payload is the one it showed: run the plan now. Said once per card.
        case run
        /// The card ran out, or the payload is not the one that was shown: nothing runs. Check the steps again, then
        /// `show` the card again; only a new tap on that card can run it.
        case refresh
        /// Nothing happens: no such card, it was already used or is waiting to be shown again, a spoken yes that may
        /// not run this card, or a press that is the same one that showed the card again.
        case ignore
    }

    private enum State { case open, waitingForRefresh, used }

    private struct Card {
        var payload: PlanCardPayload
        let preparedAt: Date
        let shownAt: Date
        let shownAgain: Bool
        var state: State
    }

    private var cards: [String: Card] = [:]

    public init() {}

    /// The card for this call is on screen now with `payload`; its steps were prepared at `preparedAt` (the earliest
    /// server approval's time, or `now` when the plan has no online-account step). Calling it again for the same
    /// call is the card being shown again: it counts as shown again, with a new window.
    public mutating func show(_ toolCallID: String, payload: PlanCardPayload, preparedAt: Date, at now: Date) {
        cards[toolCallID] = Card(
            payload: payload, preparedAt: preparedAt, shownAt: now, shownAgain: cards[toolCallID] != nil, state: .open)
    }

    /// The answer to the card with the payload the answer would run (what the app holds now, not what it showed).
    public mutating func answer(_ answer: Answer, for toolCallID: String, payload: PlanCardPayload, at now: Date) -> Decision {
        guard var card = cards[toolCallID], card.state == .open else { return .ignore }
        let age = now.timeIntervalSince(card.preparedAt)
        let ranOut = !(age >= 0 && age <= Self.window)
        let sameCard = card.payload == payload
        switch answer {
        case .userSaid:
            // A yes runs only a first card that is still fresh. After that it does nothing, and the card stays.
            guard !card.shownAgain, !ranOut, sameCard else { return .ignore }
        case .tapped:
            if ranOut || !sameCard {
                card.state = .waitingForRefresh
                cards[toolCallID] = card
                return .refresh
            }
            if card.shownAgain, now.timeIntervalSince(card.shownAt) < Self.settle { return .ignore }
        }
        card.state = .used
        cards[toolCallID] = card
        return .run
    }

    /// True while a spoken yes may answer this card: a first card, fresh, not used. For the card's header.
    public func acceptsSpokenYes(for toolCallID: String, at now: Date) -> Bool {
        guard let card = cards[toolCallID], card.state == .open, !card.shownAgain else { return false }
        let age = now.timeIntervalSince(card.preparedAt)
        return age >= 0 && age <= Self.window
    }

    /// True when the card on screen is one that ran out and was shown again, for its explanation line.
    public func wasShownAgain(_ toolCallID: String) -> Bool {
        cards[toolCallID]?.shownAgain ?? false
    }

    /// The card went away unanswered (declined, replaced by a newer one): nothing about it can run later.
    public mutating func forget(_ toolCallID: String) {
        cards[toolCallID] = nil
    }

    /// End of a conversation: every card goes.
    public mutating func clear() {
        cards = [:]
    }

    /// Which steps stay ticked when a card is shown again. A tick was the person's yes to what the card showed then:
    /// it stays for a step whose card is unchanged and that can still run, and goes for a step whose preview changed
    /// or that is blocked now. A step the person had left unticked stays unticked.
    public static func tickedAfterRefresh(
        _ ticked: Set<Int>, old: PlanCardPayload, new: PlanCardPayload, blocked: Set<Int>
    ) -> Set<Int> {
        ticked.subtracting(blocked).subtracting(new.changedSteps(since: old))
    }
}
