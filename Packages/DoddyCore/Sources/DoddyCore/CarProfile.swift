import Foundation

// Doddy in the car (ADR-338, groundwork for CarPlay, ADR-317). The owner decided on 2026-10-11:
// in the car Doddy may look things up, and may save a note or add list items after a spoken
// "yes" to an exact read-back, because both stay on the iPhone and can be undone there. Nothing
// else that changes something, and nothing that leaves the iPhone, happens while driving. The
// car screen itself waits for Apple's CarPlay entitlement; these rules are written and tested
// first so that screen can only use them.

public enum CarDecision: Equatable, Sendable {
    /// Read-only: answered out loud as usual.
    case run
    /// A local, undoable write: Doddy reads back exactly this and waits for a spoken yes.
    case askAloud(readBack: String)
    /// Not while driving; the reply tells the agent why.
    case refuse(reason: String)
}

public enum CarProfile {
    public static func decision(for request: VoiceToolRequest) -> CarDecision {
        switch request {
        case .searchMemories, .readCalendar, .findFreeTime, .upcomingBirthdays, .calculate, .convertUnits,
             .convertCurrency, .readList, .listAlarms, .needsClarification, .unsupported, .invalid:
            return .run
        case .noteCapabilityGap:
            // Bookkeeping on the iPhone (ADR-440): one category, none of the user's data, nothing to undo.
            return .run
        case .parkingSpot(let action):
            // Finding the car is a look-up; saving or clearing the spot waits until parked.
            if case .find = action { return .run }
            return .refuse(reason: "Saving or clearing the parking spot is done on the iPhone, not while driving.")
        case .cloudTool(let call):
            return CloudToolName.isWrite(call.name)
                ? .refuse(reason: "Drafts and tasks in online accounts need a tap on the iPhone, so not while driving.")
                : .run
        case .draftBlikTransfer:
            // Money (ADR-510): a card to check and a bank app to send from, so never while driving.
            return .refuse(reason: "A BLIK transfer is shown on the iPhone for the user to check and send in their bank app, so it waits until they aren't driving.")
        case .preparePurchase:
            // Paying needs Face ID or a BLIK code on the iPhone (ADR-490).
            return .refuse(reason: "Paying needs a tap and Face ID on the iPhone, so it waits until the user isn't driving.")
        case .saveMemory(let text):
            return .askAloud(readBack: CarConfirmation.readBack(saving: text))
        case .addToList(let request):
            return .askAloud(readBack: CarConfirmation.readBack(adding: request.items, to: request.list))
        case .leaveBy, .createCalendarEvent, .createReminder, .remindAboutNote, .lookupContact, .addIngredients, .undoLast,
             .setTimer, .setAlarm, .cancelAlarm, .openMap, .runShortcut, .draftMessage, .startTranslator,
             .stopTranslator, .checkOff, .removeFromList, .createList, .changeCalendarEvent, .changeReminder,
             .deleteCalendarEvent, .deleteReminder, .deleteCalendarEvents, .moveReminders:
            return .refuse(reason: "This needs a tap on a card on the iPhone, so it waits until the user isn't driving.")
        }
    }
}

public enum CarConfirmation {
    /// Whole answers that count as yes, after trimming and lowercasing. Anything else is a no.
    static let yesWords: Set<String> = [
        "yes", "yes please", "yeah", "yep", "save it", "add it", "do it",
        "tak", "tak proszę", "tak prosze", "zapisz", "dodaj", "zrób to", "zrob to",
    ]

    public static func readBack(saving text: String) -> String {
        "I'll save this note: \u{201C}\(text)\u{201D}. Say yes to save it, or no."
    }

    public static func readBack(adding items: [String], to list: String) -> String {
        "I'll add \(items.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")) to your list \u{201C}\(list)\u{201D}. Say yes to add, or no."
    }

    /// True only for a short, plain yes. "Yes, but change it…", "no", silence or anything unclear
    /// is not a yes: nothing is saved and the user can say it again.
    public static func isYes(_ utterance: String) -> Bool {
        let cleaned = utterance.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: ",", with: "")
        return yesWords.contains(cleaned)
    }
}

extension VoiceToolReply {
    public static func notInTheCar(_ reason: String) -> String {
        "not in the car: \(reason) Nothing was done. Tell the user in one short sentence and offer to remind them later if it helps."
    }
}
