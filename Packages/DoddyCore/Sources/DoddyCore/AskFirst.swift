import Foundation

// ASK-01 (ADR-483), the owner's rule of 2026-10-18: "Doddy can do everything, but it must always
// ask." Before every action of every tool, reads included, Doddy says exactly what it will do and
// waits for a yes for that one action. A task handed over (`hand_over_errand`) is that one action:
// its single yes covers every web search and page read Doddy's server makes for that task, with no
// limit, and nothing else (owner, 21 Oct 2026, ADR-570). Anything that changes, sends, deletes, books or shares
// something needs a tap on a card with the exact payload: a spoken yes is not enough there,
// because the model hears it (model-only approval is forbidden, DOD-07). No yes, a no, an unclear
// answer or a timeout: nothing runs, and the agent is told so. Text from emails, the web or
// documents never counts as a yes: only the user's tap, or the user's own transcribed words for a
// read, reach `AskLedger`.
//
// One exception since 21 Oct 2026 (owner: "You don't say you don't have a weather app. You check on
// the internet. Just be on it.", ADR-575): public lookups that read nothing of the user's and change
// nothing (a sum, a unit or currency conversion, the web, the news, places) run at once. Only the
// words searched for leave the phone. Everything that reads the user's own data or changes anything
// still asks first.
//
// This file is the rule as code, so it is tested on Linux: which ask each tool needs (`AskFirst`),
// what counts as a spoken yes (`SpokenYes`), and the one check the app makes before running a
// tool (`AskLedger.mayRun`).

/// What the card says before a tool runs: exactly what Doddy will do.
public struct AskCard: Equatable, Sendable {
    public let title: String
    public let lines: [String]
    public let confirmLabel: String

    public init(title: String, lines: [String], confirmLabel: String) {
        self.title = title
        self.lines = lines
        self.confirmLabel = confirmLabel
    }
}

public enum AskFirst {
    public enum Need: Equatable, Sendable {
        /// Nothing runs and nothing is read (an unclear, unknown or incomplete call).
        case nothingRuns
        /// Reads and other actions that change nothing: the app shows this card and runs the tool
        /// only after a tap, or the user's own spoken yes said after the card appeared.
        case yesFirst(AskCard)
        /// A change with no card of its own (list items, clearing the parking spot): this card
        /// shows the exact change, and only a tap runs it.
        case tapFirst(AskCard)
        /// The tool's own flow shows the exact payload on a card and changes something only on a
        /// tap (notes, calendar, reminders, alarms, timers, messages, shortcuts, Maps, plans).
        case ownPayloadCard
        /// Online accounts: Doddy's server makes the card and a single-use approval
        /// (backend/src/tools/askFirst.ts). A read runs on a tap or a spoken yes; a write on a tap only.
        case serverCard(isWrite: Bool)
        /// A public lookup (`publicLookups`, ADR-575): runs at once, no card. For the web ones the
        /// app still gets the server's single-use approval and uses it straight away.
        case runsNow
    }

    /// Tools that run without asking (ADR-575): they read nothing of the user's, change nothing,
    /// and send at most the words searched for. Web search, news and places cost Doddy a little
    /// per search (ADR-489); the weather and Wikipedia ones run on ElevenLabs (`ToolCatalog.webLookups`).
    public static let publicLookups: Set<String> = Set([
        VoiceToolName.calculate, VoiceToolName.convertUnits, VoiceToolName.convertCurrency,
        CloudToolName.webSearch, "news_search", "find_places",
    ]).union(ToolCatalog.webLookups)

    /// Every request has an answer here; the switch has no default, so a new tool doesn't compile
    /// until it says how it asks.
    public static func need(for request: VoiceToolRequest, calendar: Calendar = .current) -> Need {
        switch request {
        case .unsupported, .invalid, .needsClarification:
            return .nothingRuns
        case .searchMemories(let query):
            return .yesFirst(AskCard(title: "Search your notes?", lines: ["For: \(query)"], confirmLabel: "Yes, search"))
        case .readCalendar(let range):
            return .yesFirst(AskCard(title: "Read your calendar?", lines: [span(range.start, range.end, calendar: calendar)], confirmLabel: "Yes, read it"))
        case .findFreeTime(let request):
            let last = calendar.date(byAdding: .day, value: max(request.days - 1, 0), to: request.firstDay) ?? request.firstDay
            return .yesFirst(AskCard(
                title: "Look for free time in your calendar?",
                lines: [day(request.firstDay, calendar: calendar) + (request.days > 1 ? " to " + day(last, calendar: calendar) : "")],
                confirmLabel: "Yes, look"))
        case .lookupContact(let name):
            return .yesFirst(AskCard(title: "Look up a contact?", lines: ["Name: \(name)"], confirmLabel: "Yes, look it up"))
        case .upcomingBirthdays(let days):
            return .yesFirst(AskCard(title: "Check birthdays in Contacts?", lines: ["The next \(days) days"], confirmLabel: "Yes, check"))
        case .calculate, .convertUnits, .convertCurrency:
            return .runsNow
        case .findPhotos(let request):
            return .yesFirst(AskCard(title: "Look through your photos?", lines: [request.text(calendar: calendar), "Only the counts and times go to Doddy's voice; the photos stay on your screen."], confirmLabel: "Yes, look"))
        case .readSteps(let day):
            return .yesFirst(AskCard(title: "Read your steps?", lines: ["\(day.text), from Motion & Fitness"], confirmLabel: "Yes, read them"))
        case .listAlarms:
            return .yesFirst(AskCard(title: "Check Doddy's alarms?", lines: ["The alarms Doddy set on this iPhone"], confirmLabel: "Yes, check"))
        case .readList(let name):
            return .yesFirst(AskCard(title: "Read a list?", lines: ["List: \(name)"], confirmLabel: "Yes, read it"))
        case .parkingSpot(.find):
            return .yesFirst(AskCard(title: "Find your parking spot?", lines: ["Uses where your iPhone is now"], confirmLabel: "Yes, find it"))
        // ADR-619 (owner, 24 Oct 2026: "nie pytaj, od razu działaj, przełącz się i pytaj, co
        // tłumaczyć"), replacing ADR-542: translator mode starts and stops the moment the user asks.
        // It reads nothing and sends nothing; the conversation turns private, and the other person
        // still hears the AI translator disclosure first.
        case .startTranslator, .stopTranslator:
            return .runsNow
        case .handOverErrand(let draft):
            // Reads the web and changes nothing (ADR-570); the card shows the user's exact words.
            return .yesFirst(ErrandAsk.handOverCard(draft))
        case .checkErrands:
            return .yesFirst(ErrandAsk.checkCard)
        case .addToList(let request):
            return .tapFirst(AskCard(title: "Add to \(request.list)?", lines: request.items, confirmLabel: "Add"))
        case .checkOff(let request):
            return .tapFirst(AskCard(title: "Tick off on \(request.list)?", lines: request.items, confirmLabel: "Tick off"))
        case .removeFromList(let request):
            return .tapFirst(AskCard(title: "Remove from \(request.list)?", lines: request.items, confirmLabel: "Remove"))
        case .parkingSpot(.clear):
            return .tapFirst(AskCard(title: "Forget your parking spot?", lines: ["The one spot kept on this iPhone is removed."], confirmLabel: "Forget it"))
        case .noteCapabilityGap(let category):
            return .tapFirst(AskCard(
                title: "Note that Doddy couldn't do this?",
                lines: ["Kept on this iPhone as a category only: \(category.rawValue.replacingOccurrences(of: "_", with: " "))"],
                confirmLabel: "Note it"))
        case .saveMemory, .createCalendarEvent, .createReminder, .remindAboutNote, .undoLast, .setTimer, .setAlarm, .cancelAlarm,
             .openMap, .runShortcut, .draftMessage, .draftBlikTransfer, .makePresentation, .openCamera, .addIngredients, .createList, .changeCalendarEvent, .changeReminder,
             .deleteCalendarEvent, .deleteReminder, .deleteCalendarEvents, .moveReminders, .leaveBy, .parkingSpot(.save):
            return .ownPayloadCard
        case .cloudTool(let call):
            return !call.isWrite && publicLookups.contains(call.name) ? .runsNow : .serverCard(isWrite: call.isWrite)
        }
    }

    /// True when only a tap may say yes (anything that changes something).
    public static func needsTap(_ need: Need) -> Bool {
        switch need {
        case .tapFirst, .ownPayloadCard, .serverCard(isWrite: true): true
        case .nothingRuns, .yesFirst, .serverCard(isWrite: false), .runsNow: false
        }
    }

    /// What the agent hears when the user said no, didn't answer, or the card went away.
    public static func notAsked(_ toolName: String) -> String {
        "declined: the user didn't say yes to \(toolName), so Doddy did nothing and read nothing. Say so in one short sentence; don't try again unless the user asks."
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func span(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        let time = { (d: Date) -> String in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        return "From \(day(start, calendar: calendar)) \(time(start)) to \(day(end, calendar: calendar)) \(time(end))"
    }
}

/// A spoken yes for a read: the user's own transcribed words, nothing else. Strict on purpose: a
/// short answer that is only a yes. "Yes, but…", "no", "not now", a question, or anything longer
/// is not a yes, and the card waits for a tap.
public enum SpokenYes {
    /// In the app's languages. Matched against the whole answer, lower-cased, without punctuation.
    static let phrases: Set<String> = [
        // English
        "yes", "yeah", "yep", "yup", "sure", "ok", "okay", "go ahead", "do it", "yes please", "please do", "go on",
        "yes go ahead", "yes do it", "ok go ahead", "okay go ahead", "sure go ahead",
        // Polish
        "tak", "tak proszę", "tak prosze", "dobrze", "jasne", "śmiało", "smialo", "zrób to", "zrob to", "tak zrób to", "tak zrob to", "okej", "pewnie",
        // German
        "ja", "ja bitte", "klar", "mach das", "ja mach das", "in ordnung",
        // French
        "oui", "oui vas-y", "oui vas y", "vas-y", "vas y", "d'accord", "oui s'il te plaît", "oui s'il te plait",
        // Spanish
        "sí", "si", "sí por favor", "si por favor", "vale", "claro", "adelante",
        // Italian
        "sì", "sì grazie", "si grazie", "va bene", "certo", "vai",
        // Dutch
        "ja graag", "prima", "graag",
        // Portuguese
        "sim", "sim por favor", "pode", "pode ser", "claro que sim",
    ]

    /// Words that undo a yes anywhere in the answer.
    static let vetoes: Set<String> = ["no", "not", "don't", "dont", "nie", "nein", "non", "nee", "não", "nao", "wait", "stop", "czekaj", "but", "ale", "aber", "mais", "pero", "ma", "maar", "mas"]

    public static func isYes(_ said: String) -> Bool {
        let words = said.lowercased()
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 5 else { return false }
        if words.contains(where: vetoes.contains) { return false }
        return phrases.contains(words.joined(separator: " "))
    }
}

/// The app's half of ASK-01: one ask per tool call, answered once, used once.
///
/// The controller calls `asked` when it shows the card, `answer` with the user's tap or the user's
/// own transcribed words, and `mayRun` right before the tool runs. `mayRun` is true once, only for
/// a yes to exactly this request, given while the card was up and within `window`.
public struct AskLedger: Sendable {
    /// Where an answer came from. There is deliberately no case for the agent's words, a tool's
    /// result, an email, a web page or a document: those can never answer an ask.
    public enum Answer: Equatable, Sendable {
        case tapped
        /// The user's own words, from the speech-to-text of their side of the conversation.
        case userSaid(String)
        case declined
    }

    public enum Outcome: Equatable, Sendable {
        /// The yes counts: run it now.
        case granted
        /// A no, or the card is gone: nothing runs.
        case declined
        /// Not an answer that counts (a spoken yes for a change, or words that aren't a clear
        /// yes): the card stays up.
        case stillWaiting
        /// No such ask, or it was already answered or expired.
        case unknown
    }

    private struct Entry: Sendable {
        let request: VoiceToolRequest
        let needsTap: Bool
        let askedAt: Date
        var granted = false
    }

    private var entries: [String: Entry] = [:]
    /// How long a card waits for its answer, and how long a yes may wait for its run.
    public let window: TimeInterval

    public init(window: TimeInterval = 120) {
        self.window = window
    }

    /// The card for this call is on screen now.
    public mutating func asked(_ toolCallID: String, request: VoiceToolRequest, needsTap: Bool, at now: Date) {
        entries[toolCallID] = Entry(request: request, needsTap: needsTap, askedAt: now)
    }

    public mutating func answer(_ answer: Answer, for toolCallID: String, at now: Date) -> Outcome {
        guard var entry = entries[toolCallID], !entry.granted else { return .unknown }
        guard now.timeIntervalSince(entry.askedAt) <= window, now >= entry.askedAt else {
            entries[toolCallID] = nil
            return .declined
        }
        switch answer {
        case .declined:
            entries[toolCallID] = nil
            return .declined
        case .tapped:
            entry.granted = true
        case .userSaid(let words):
            // A change needs a tap (DOD-07); a read takes the user's own clear yes.
            guard !entry.needsTap, SpokenYes.isYes(words) else { return .stillWaiting }
            entry.granted = true
        }
        entries[toolCallID] = entry
        return .granted
    }

    /// The one check before a tool runs. True once, for a granted ask for exactly this request.
    public mutating func mayRun(_ toolCallID: String, request: VoiceToolRequest, at now: Date) -> Bool {
        guard let entry = entries[toolCallID] else { return false }
        entries[toolCallID] = nil
        return entry.granted && entry.request == request && now.timeIntervalSince(entry.askedAt) <= window * 2
    }

    /// The asks still waiting for a spoken answer (reads only), oldest first.
    public func waitingForSpokenYes() -> [String] {
        entries.filter { !$0.value.granted && !$0.value.needsTap }.sorted { $0.value.askedAt < $1.value.askedAt }.map(\.key)
    }

    /// End of a conversation: every open ask goes; nothing asked in it can run later.
    public mutating func clear() {
        entries = [:]
    }
}
