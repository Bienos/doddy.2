import Foundation

// ASK-01 (ADR-483), the owner's rule of 2026-10-18: "Doddy can do everything, but it must always
// ask." Before every action of every tool, reads included, Doddy says exactly what it will do and
// waits for a yes for that one action. A task handed over (`hand_over_errand`) is that one action:
// its single yes covers every web search and page read Doddy's server makes for that task, with no
// limit, and nothing else (owner, 21 Oct 2026, ADR-570). That yes is a tap since ADR-716: the task's
// text goes to a server that opens whatever it names, so a spoken "yes" (to another question, or
// anything the microphone heard) must not start one. A Studio job (`make_something`, ADR-740) is the
// second such action, a tap too (ADR-742: it spends money): its tap covers that job's web look-ups
// (capped by the server's max_uses) and the making of its files in Anthropic's container, within the
// server's dollar limits, and nothing else. Anything that changes, sends, deletes, books or shares
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
// A second exception since 9 Nov 2026 (owner: "doddy should send sms from his numbers on his own", decision
// 2026-11-09-restaurant-calls-one-tap): `text_me` goes at once. It can only reach the user's own verified number,
// and only while they have turned on Texts from Doddy; the server still checks the approval hash of exactly that
// text and number. Texts to anyone else are impossible, not just asked about.
//
// A third change, 11 Nov 2026 (owner: "jak ja pytam się do niego coś, to on cały czas musi mieć zatwierdzenie …
// powinien być bardziej proaktywny, nie dopytywać się wszystkiego, tylko od razu pokazywać albo mówić informacje",
// decision 2026-11-11-asked-for-runs-at-once): what the user asks for is the yes. Looking at the user's own
// things to answer them (notes, lists, calendar, contacts, birthdays, photos, steps, the Health week, alarms,
// Doddy's timers, the parking spot, a task's result, this week's leaflets, the shared screen, and every read
// through an online account or Claude) runs at once, with no card and no spoken question. So do Doddy's own
// small things that are undone in one step: his stopwatch, focus timer and wind-down, adding to or ticking off
// one of his lists, following a topic, opening the training plan screen, and the capability-gap category.
// The standing consents stay where they were: each Connections switch (Calendar, Contacts, Photos, Health …)
// is asked once on its own sheet, an online account is connected once, and screen sharing is started by the
// person in iOS's own sheet. What still needs a tap on a card with the exact payload is everything that
// changes something outside Doddy's own lists and timers, sends, deletes, books, shares, calls, or starts
// paid background work (a handed-over task, a Studio job): DOD-07 is unchanged.
//
// A fourth change, 14 Nov 2026 (decision 2026-11-14-untrusted-content-needs-a-tap; DOD-07 and "tool content is
// data"): everything above is the baseline, and `voice-agent/tools.json` mirrors it. On top of it, `need(for:in:)`
// (OutsideContent.swift) holds six of the tools that run at once behind a tap when text from outside could be
// steering them: `text_me` and `ask_claude` with material once an email, a page, an account, Wikipedia or the screen
// has reached the conversation; `make_document` always; `look_at_screen` for the first look; `add_to_list` and
// `check_off` on a shared list unless the user just said the items. It can only add a card, never remove one.
//
// This file is the rule as code, so it is tested on Linux: which ask each tool needs (`AskFirst`),
// what counts as a spoken yes (`SpokenYes`), and the one check the app makes before running a
// tool (`AskLedger.mayRun`).

/// What the card says before a tool runs: exactly what Doddy will do.
public struct AskCard: Equatable, Sendable {
    public let title: String
    public let lines: [String]
    public let confirmLabel: String
    /// The other button; nil shows the app's own "No".
    public let declineLabel: String?

    public init(title: String, lines: [String], confirmLabel: String, declineLabel: String? = nil) {
        self.title = title
        self.lines = lines
        self.confirmLabel = confirmLabel
        self.declineLabel = declineLabel
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
        /// shows the exact change, and only a tap runs it. Also a task handed over to Doddy's
        /// server (ADR-716) and a trip's travel time, which reads where the iPhone is (ADR-718).
        case tapFirst(AskCard)
        /// The tool's own flow shows the exact payload on a card and changes something only on a
        /// tap (notes, calendar, reminders, alarms, timers, messages, shortcuts, Maps, plans).
        case ownPayloadCard
        /// Online accounts: Doddy's server makes the card and a single-use approval
        /// (backend/src/tools/askFirst.ts). A read runs on a tap or a spoken yes; a write on a tap only.
        case serverCard(isWrite: Bool)
        /// Runs at once, no card: a public lookup (`publicLookups`, ADR-575), a look at the user's own things
        /// they just asked about, or one of Doddy's own small reversible actions (`ownSmallActions`; decision
        /// 2026-11-11-asked-for-runs-at-once). For the server's tools the app still gets the server's
        /// single-use approval and uses it straight away.
        case runsNow
    }

    /// Tools that run without asking (ADR-575): they read nothing of the user's, change nothing,
    /// and send at most the words searched for. Web search, news and places cost Doddy a little
    /// per search (ADR-489); the weather and Wikipedia ones run on ElevenLabs (`ToolCatalog.webLookups`).
    public static let publicLookups: Set<String> = Set([
        VoiceToolName.calculate, VoiceToolName.convertUnits, VoiceToolName.convertCurrency,
        CloudToolName.webSearch, "news_search", "find_places",
    ]).union(ToolCatalog.webLookups)

    /// Looks at the user's own things on this iPhone, or at what Doddy's server holds for them, that run at once
    /// since 11 Nov 2026 (decision 2026-11-11-asked-for-runs-at-once). Each one's Connections switch, where it has
    /// one, is still asked once on its own sheet (`ToolGate`). `parking_spot` is not listed: only its "find" runs
    /// at once, saving and clearing keep their cards.
    public static let ownLooks: Set<String> = [
        VoiceToolName.searchMemories, VoiceToolName.readList, VoiceToolName.readCalendar, VoiceToolName.findFreeTime,
        VoiceToolName.lookupContact, VoiceToolName.upcomingBirthdays, VoiceToolName.findPhotos, VoiceToolName.lookAtScreen,
        VoiceToolName.readSteps, VoiceToolName.readHealthWeek, VoiceToolName.listAlarms, VoiceToolName.checkStopwatch,
        VoiceToolName.checkFocus, VoiceToolName.checkErrands, VoiceToolName.findDeals,
    ]

    /// Doddy's own small things that run at once since 11 Nov 2026: each is undone in one step (stop, untick,
    /// unfollow, close the screen) and none reaches another app, an account or another person.
    public static let ownSmallActions: Set<String> = [
        VoiceToolName.startStopwatch, VoiceToolName.stopStopwatch, VoiceToolName.startFocus, VoiceToolName.stopFocus,
        VoiceToolName.startWindDown, VoiceToolName.stopWindDown, VoiceToolName.addToList, VoiceToolName.checkOff,
        VoiceToolName.followNews, VoiceToolName.openTrainingPlan, VoiceToolName.noteCapabilityGap,
    ]

    /// True for a tool that never shows a card and never waits: the public lookups, the looks and the small actions
    /// above, every read through Doddy's server (an online account, Claude), translator start and stop, and a text
    /// to the user's own number. `voice-agent/tools.json` says `ask: runs_now` for exactly these. This is the baseline:
    /// `OutsideContentRule.guardedTools` among them can still ask in a conversation (`need(for:in:)`).
    public static func runsAtOnce(_ name: String) -> Bool {
        if publicLookups.contains(name) || ownLooks.contains(name) || ownSmallActions.contains(name) { return true }
        if [VoiceToolName.startTranslator, VoiceToolName.stopTranslator, VoiceToolName.textMe].contains(name) { return true }
        return CloudToolName.all.contains(name) && !CloudToolName.isWrite(name)
    }

    /// Every request has an answer here; the switch has no default, so a new tool doesn't compile
    /// until it says how it asks.
    /// `polish`: the app is shown in Polish, for the cards whose words are chosen here (ADR-666: leaflets).
    public static func need(for request: VoiceToolRequest, calendar: Calendar = .current, polish: Bool = false) -> Need {
        // The card is drawn as it is, so its words are chosen here: Polish when the app is shown in
        // Polish (owner, 9 Nov 2026: the app kept showing English words on these cards).
        func say(_ english: String, _ polishText: String) -> String { polish ? polishText : english }
        switch request {
        case .unsupported, .invalid, .needsClarification:
            return .nothingRuns
        // Decision 2026-11-11-asked-for-runs-at-once: the user asked, so Doddy looks and answers. No card, no question.
        case .searchMemories, .readList, .readCalendar, .findFreeTime, .lookupContact, .upcomingBirthdays, .findPhotos,
             .readSteps, .readHealthWeek, .listAlarms, .checkStopwatch, .checkFocus, .parkingSpot(.find), .checkErrands, .findDeals:
            return .runsNow
        case .lookAtScreen:
            // The person started screen sharing themselves in iOS's own sheet, and iOS shows that it is on the whole
            // time: that is the yes for Doddy to look while it stays on (decision 2026-11-11-asked-for-runs-at-once,
            // replacing "each look asks first" in 2026-11-09-doddy-looks-at-the-screen). With sharing off nothing is
            // looked at: the app opens iOS's sheet instead.
            return .runsNow
        case .calculate, .convertUnits, .convertCurrency:
            return .runsNow
        // Doddy's own timers, lists and follows: started, ticked or added at once; each is undone in one step.
        case .startStopwatch, .stopStopwatch, .startFocus, .stopFocus, .startWindDown, .stopWindDown,
             .addToList, .checkOff, .followNews, .openTrainingPlan, .noteCapabilityGap:
            return .runsNow
        // ADR-619 (owner, 24 Oct 2026: "nie pytaj, od razu działaj, przełącz się i pytaj, co
        // tłumaczyć"), replacing ADR-542: translator mode starts and stops the moment the user asks.
        // It reads nothing and sends nothing; the conversation turns private, and the other person
        // still hears the AI translator disclosure first.
        case .startTranslator, .stopTranslator:
            return .runsNow
        case .handOverErrand(let draft):
            // Reads the web and changes nothing on the iPhone (ADR-570), but the text goes to a server
            // that opens what it names, and a spoken "yes" could be anything the microphone heard, so
            // only a tap starts it (ADR-716). The card shows whose each text is, in full.
            return .tapFirst(ErrandAsk.handOverCard(draft, polish: polish))
        case .makeSomething(let job):
            // ADR-740: web research and files made in Anthropic's container, paid from Doddy's account.
            // Nothing outside Doddy changes, but it spends money and sends the user's words to Anthropic,
            // so only a tap starts it, like a handed-over task (ADR-716, ADR-742). The card shows the whole job.
            return .tapFirst(StudioAsk.card(job))
        // Opening a food app hands the person over to it (decision 2026-11-12-food-by-voice): a tap on the card
        // naming the app and the search, never on its own. Nothing is ordered here.
        case .openFoodApp(let handoff):
            return .tapFirst(handoff.card(polish: polish))
        // Taking something away keeps its card: a tap on exactly what goes.
        case .removeFromList(let request):
            return .tapFirst(AskCard(
                title: say("Remove from \(request.list)?", "Usunąć z listy „\(request.list)”?"),
                lines: request.items, confirmLabel: say("Remove", "Usuń")))
        case .parkingSpot(.clear):
            return .tapFirst(AskCard(
                title: say("Forget your parking spot?", "Zapomnieć miejsce parkowania?"),
                lines: [say("The one spot kept on this iPhone is removed.", "Jedyne miejsce zapisane na tym iPhonie zostanie usunięte.")],
                confirmLabel: say("Forget it", "Zapomnij")))
        case .leaveBy:
            // One card, not two (11 Nov 2026): the trip is worked out at once (where the iPhone is, and Apple Maps,
            // under iOS's own location permission), and the payload card with the place Maps found and the leave
            // time is the tap that sets the notification (ADR-718's first card is gone).
            return .ownPayloadCard
        case .saveMemory, .createCalendarEvent, .createReminder, .remindAboutNote, .undoLast, .setTimer, .setAlarm, .cancelAlarm,
             .openMap, .runShortcut, .draftMessage, .draftBlikTransfer, .makePresentation, .openCamera, .controlHome, .addIngredients, .createList, .changeCalendarEvent, .changeReminder,
             .deleteCalendarEvent, .deleteReminder, .deleteCalendarEvents, .moveReminders, .parkingSpot(.save),
             // The card shows the time and the exact reason; the tap approves exactly that (ADR-754).
             // call_places: the card shows every place, its number and where it came from, the exact
             // opening line and question; the one tap approves exactly that task's digest.
             .callMeLater, .callMeNow, .callPlaces:
            return .ownPayloadCard
        case .textMe:
            // A text to the user's own verified number goes at once while Texts from Doddy is on (owner, 9 Nov 2026,
            // decision 2026-11-09-restaurant-calls-one-tap). It can reach no one else (contact_policy.text_recipients).
            return .runsNow
        case .lostWallet:
            // ADR-692: the checklist is its own card. Showing it reads and changes nothing; each
            // step's page or number opens only on the person's tap on that step.
            return .ownPayloadCard
        case .draftInvoice:
            // ADR-677: the draft card shows the exact invoice and changes nothing anywhere; issuing in
            // inFakt is the card's own tap, bound to the digest of what it shows (ADR-640).
            return .ownPayloadCard
        case .cloudTool(let call):
            // A read through Doddy's server (an inbox, a calendar, a page, Claude writing something) runs at once
            // since 11 Nov 2026; the server's single-use approval is still made for exactly this call. A write
            // keeps the server's card and a tap.
            return call.isWrite ? .serverCard(isWrite: true) : .runsNow
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
        // German. "ja" is also Polish for "I", so a stray one could pass as a yes. It stays: it is the
        // German yes, a spoken yes answers reads only (a hand-over needs a tap since ADR-716), and a list
        // per language is the owner's call.
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
