import Foundation

/// What one voice tool does and what it needs before it runs (DODDY Brain Phase 3b, ADR-444).
///
/// Only `effect` and `approval` are declared here, for the phone and web tools. Everything else is
/// read from the constants that already decide it, so this is not a second list to keep in step:
/// the switch from `VoiceConnection.serving`, plan use from `PlanTool.allowed`, and the online
/// account tools (with read or write) from `CloudToolName`. `ToolCatalogTests` checks all of it
/// against `voice-agent/tools.json` and the server's `CLOUD_TOOLS`, so a drift fails a test before
/// it reaches the live agent.
public struct ToolDescriptor: Equatable, Sendable {
    public enum Effect: String, Sendable, CaseIterable {
        /// Reads and answers; nothing changes anywhere.
        case lookup
        /// Changes something on this iPhone: a note, a list, Calendar, Reminders, a timer.
        case localChange
        /// Changes something in an online account, through Doddy's server.
        case accountWrite
        /// Opens another app with something filled in; the user finishes there. Also a task
        /// handed to Doddy's server, which works on it and keeps the result in the app (ADR-716).
        case handoff
        /// A text from Doddy's own number to the user's verified number (ADR-750 U2), through
        /// Doddy's messaging server. Never to anyone else.
        case sendText
        /// A call placed by Doddy's messaging server from Doddy's own number: to the user's verified
        /// number at a time they approved (ADR-754), or to up to three places the user approved on one
        /// card (decision 2026-11-09-restaurant-calls-one-tap).
        case placeCall
        /// Changes the conversation itself (translator mode, the plan card).
        case session
    }

    /// ASK-01 (ADR-483): every tool asks first, except the public lookups that run at once (ADR-575).
    public enum Approval: String, Sendable, CaseIterable {
        /// A public lookup that reads nothing of the user's and changes nothing (`AskFirst.publicLookups`):
        /// runs when the agent calls it (owner, 21 Oct 2026, ADR-575). Also translator mode's start
        /// and stop, which read and send nothing (owner, 24 Oct 2026, ADR-619), and a text to the
        /// user's own verified number while Texts from Doddy is on (owner, 9 Nov 2026, decision
        /// 2026-11-09-restaurant-calls-one-tap).
        case runsNow
        /// Changes nothing: the app shows what it will do and runs it on a tap or the user's own
        /// spoken yes (`AskFirst.Need.yesFirst`).
        case askFirst
        /// Shows a card with the exact change first; nothing happens until the user taps.
        case card
        /// A read through Doddy's server: the server's single-use approval for exactly these
        /// arguments, sent once the user said yes or tapped.
        case serverAsk
        /// A card, and the server's single-use approval for exactly the arguments shown.
        case serverApproval
    }

    public let name: String
    public let runsOn: RealtimeToolSpec.RunsOn
    public let effect: Effect
    public let approval: Approval

    public init(_ name: String, _ effect: Effect, _ approval: Approval, runsOn: RealtimeToolSpec.RunsOn = .phone) {
        self.name = name
        self.effect = effect
        self.approval = approval
        self.runsOn = runsOn
    }

    /// The Settings → Connections switch it needs; nil for tools that are always on.
    public var connection: VoiceConnection? { VoiceConnection.serving(name) }
    /// May be a step of a plan card (ADR-204). The plan card is then the approval for the step.
    public var planEligible: Bool { PlanTool.allowed.contains(name) }
    /// An online-account tool, run by Doddy's server.
    public var isCloud: Bool { CloudToolName.all.contains(name) }
}

public enum ToolCatalog {
    /// Every tool in `voice-agent/tools.json`, by name. The `runs_on: web` tools are public
    /// lookups ElevenLabs runs itself (weather, Wikipedia). ASK-01 took them out because the app
    /// can't ask before them; since ADR-575 public lookups run at once, so they are back.
    public static let all: [ToolDescriptor] = phone + cloud + web

    /// Public lookups ElevenLabs runs on its own servers (ADR-575).
    public static let webLookups: Set<String> = ["geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary"]

    private static let web: [ToolDescriptor] = webLookups.sorted().map {
        ToolDescriptor($0, .lookup, .runsNow, runsOn: .web)
    }

    public static func descriptor(_ name: String) -> ToolDescriptor? {
        byName[name]
    }

    private static let byName: [String: ToolDescriptor] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    private static let phone: [ToolDescriptor] = [
        // Notes and lists (ADR-216). Since 11 Nov 2026 (decision 2026-11-11-asked-for-runs-at-once) looking, adding and
        // ticking off run at once; saving a note, a new list and removing items keep their cards.
        .init(VoiceToolName.searchMemories, .lookup, .runsNow),
        .init(VoiceToolName.saveMemory, .localChange, .runsNow),
        .init(VoiceToolName.remindAboutNote, .localChange, .card),
        .init(VoiceToolName.readList, .lookup, .runsNow),
        .init(VoiceToolName.addToList, .localChange, .runsNow),
        .init(VoiceToolName.checkOff, .localChange, .runsNow),
        .init(VoiceToolName.removeFromList, .localChange, .card),
        .init(VoiceToolName.createList, .localChange, .card),
        .init(VoiceToolName.addIngredients, .localChange, .runsNow),
        // One row on this iPhone, a category only (ADR-440).
        .init(VoiceToolName.noteCapabilityGap, .localChange, .runsNow),
        // Calendar and Reminders.
        .init(VoiceToolName.readCalendar, .lookup, .runsNow),
        .init(VoiceToolName.findFreeTime, .lookup, .runsNow),
        .init(VoiceToolName.createCalendarEvent, .localChange, .card),
        .init(VoiceToolName.createReminder, .localChange, .runsNow),
        .init(VoiceToolName.changeCalendarEvent, .localChange, .card),
        .init(VoiceToolName.changeReminder, .localChange, .card),
        .init(VoiceToolName.deleteCalendarEvent, .localChange, .card),
        .init(VoiceToolName.deleteReminder, .localChange, .card),
        .init(VoiceToolName.deleteCalendarEvents, .localChange, .card),
        .init(VoiceToolName.moveReminders, .localChange, .card),
        .init(VoiceToolName.undoLast, .localChange, .card),
        // Contacts, timers and alarms, places.
        .init(VoiceToolName.lookupContact, .lookup, .runsNow),
        .init(VoiceToolName.upcomingBirthdays, .lookup, .runsNow),
        // Motion & Fitness, read only (ADR-568).
        .init(VoiceToolName.readSteps, .lookup, .runsNow),
        // Apple Health, the week as a summary, after its own consent (ADR-623).
        .init(VoiceToolName.readHealthWeek, .lookup, .runsNow),
        // Opens the plan screen on a tap; the safety questions are asked there, never by the agent (ADR-626).
        .init(VoiceToolName.openTrainingPlan, .handoff, .runsNow),
        // Counts and times from the photo library; the pictures stay on screen (ADR-569).
        .init(VoiceToolName.findPhotos, .lookup, .runsNow),
        .init(VoiceToolName.lookAtScreen, .lookup, .runsNow),
        // Run when asked since step 2c (decision 2026-11-14-spoken-yes-and-fewer-cards): Undo in What Doddy did
        // stops the timer while it counts down and turns the alarm off while the iPhone has it.
        .init(VoiceToolName.setTimer, .localChange, .runsNow),
        .init(VoiceToolName.setAlarm, .localChange, .runsNow),
        .init(VoiceToolName.listAlarms, .lookup, .runsNow),
        .init(VoiceToolName.cancelAlarm, .localChange, .card),
        // Follow something in Following (ADR-657): Doddy's own feature on this iPhone.
        .init(VoiceToolName.followNews, .localChange, .runsNow),
        .init(VoiceToolName.unfollowNews, .localChange, .runsNow),
        // Doddy's own things by voice (decision 2026-11-27-voice-first-doddy): at once, with Undo where there is one
        // (`OwnThingsVoice.atOnceTools`); a note's reminder keeps a card with the note and the reminder it turns off.
        .init(VoiceToolName.changeNote, .localChange, .runsNow),
        .init(VoiceToolName.deleteNote, .localChange, .runsNow),
        .init(VoiceToolName.cancelNoteReminder, .localChange, .card),
        .init(VoiceToolName.renameList, .localChange, .runsNow),
        .init(VoiceToolName.deleteList, .localChange, .runsNow),
        .init(VoiceToolName.clearTicked, .localChange, .runsNow),
        // Stopping a task or a Studio job on Doddy's server (ADR-570, ADR-740), as asked.
        .init(VoiceToolName.cancelTask, .handoff, .runsNow),
        // A stopwatch that counts up (ADR-652): Doddy's own tool, no other app.
        .init(VoiceToolName.startStopwatch, .localChange, .runsNow),
        .init(VoiceToolName.stopStopwatch, .localChange, .runsNow),
        .init(VoiceToolName.checkStopwatch, .lookup, .runsNow),
        // The focus timer and the wind-down (decision 2026-11-10-timers-by-voice): Doddy's own timers, like the stopwatch.
        .init(VoiceToolName.startFocus, .localChange, .runsNow),
        .init(VoiceToolName.stopFocus, .localChange, .runsNow),
        .init(VoiceToolName.checkFocus, .lookup, .runsNow),
        .init(VoiceToolName.startWindDown, .localChange, .runsNow),
        .init(VoiceToolName.stopWindDown, .localChange, .runsNow),
        // Saving or clearing a spot shows a card; "find" asks first (ADR-301, ASK-01). The card is
        // the strictest of its three actions.
        .init(VoiceToolName.parkingSpot, .localChange, .card),
        .init(VoiceToolName.remindWhenToLeave, .localChange, .card),
        // The person's rough area for a look-up near them, read once and never kept (decision 2026-11-14-approximate-location-by-voice).
        .init(VoiceToolName.whereAmI, .lookup, .runsNow),
        // Worked out on the iPhone, or the ECB's public rates file (ADR-270, ADR-300). Run at once (ADR-575).
        .init(VoiceToolName.calculate, .lookup, .runsNow),
        .init(VoiceToolName.convertUnits, .lookup, .runsNow),
        .init(VoiceToolName.convertCurrency, .lookup, .runsNow),
        // Another app opens with it filled in; nothing is sent by Doddy.
        .init(VoiceToolName.openMap, .handoff, .runsNow),
        // A food delivery app opens when asked while Doddy is on screen, otherwise its card waits for a yes or a tap
        // (step 2b of decision 2026-11-14-spoken-yes-and-fewer-cards); the person orders there (decision 2026-11-12-food-by-voice).
        .init(VoiceToolName.openFoodApp, .handoff, .runsNow),
        .init(VoiceToolName.runShortcut, .handoff, .card),
        .init(VoiceToolName.draftMessage, .handoff, .runsNow),
        // The iPhone's call screen for one contact; the person taps Call (25 Nov 2026).
        .init(VoiceToolName.callContact, .handoff, .runsNow),
        // A BLIK transfer on a card; the user sends it in their bank app, never Doddy (ADR-510).
        .init(VoiceToolName.draftBlikTransfer, .handoff, .runsNow),
        // Sent by Doddy, so the card shows the exact text and the tap approves exactly that
        // text; the server checks the same approval hash (ADR-750 U2).
        // Decision 2026-11-09-restaurant-calls-one-tap (owner, 9 Nov 2026): to the user's own verified number only,
        // at once while Texts from Doddy is on, no card; never the same text twice in a row (`TextRepeat`).
        .init(VoiceToolName.textMe, .sendText, .runsNow),
        // The card shows the time and the exact reason Doddy will say; the server checks the same
        // approval hash when it books the call and again when it places it (ADR-754).
        // Rings only the user's own verified number, as asked (owner, 25 Nov 2026, `AskFirst.ownPhoneCallsAtOnce`).
        .init(VoiceToolName.callMeLater, .placeCall, .runsNow),
        // The same call as Settings, Phone calls, Call me now; the card shows the number's last digits.
        // Rings only the user's own verified number, as asked (owner, 25 Nov 2026, `AskFirst.ownPhoneCallsAtOnce`).
        .init(VoiceToolName.callMeNow, .placeCall, .runsNow),
        // A standing permission: the card shows the exact schedule, the number and the switch; the server checks the
        // same approval hash when it sets it up and again before each day's call (decision 2026-11-14-morning-call).
        .init(VoiceToolName.callMeEveryMorning, .placeCall, .card),
        // Stops them at once: it only takes the permission away.
        .init(VoiceToolName.stopMorningCalls, .placeCall, .runsNow),
        .init(VoiceToolName.callPlaces, .placeCall, .card),
        // A file made on the iPhone when asked (step 2b of decision 2026-11-14-spoken-yes-and-fewer-cards), then the share sheet to Keynote or Files (ADR-567).
        .init(VoiceToolName.makePresentation, .handoff, .runsNow),
        // Doddy's camera opens when asked while Doddy is on screen, otherwise its card waits (step 2b of decision 2026-11-14-spoken-yes-and-fewer-cards);
        // a yes said in the background opens nothing and is told so. A kept photo becomes a note the user saves (ADR-569).
        .init(VoiceToolName.openCamera, .handoff, .runsNow),
        // "I lost my wallet" (ADR-692): the official steps on a card; each page or number opens only on a tap.
        .init(VoiceToolName.lostWallet, .handoff, .runsNow),
        // A light, outlet, fan or scene in HomeKit, after a card naming the exact accessory.
        .init(VoiceToolName.controlHome, .localChange, .card),
        // A task handed over (ADR-570): web research on Doddy's server that changes nothing on the
        // iPhone; one yes covers every look-up of that task. A spoken yes or a tap since step 2a of decision
        // 2026-11-14-spoken-yes-and-fewer-cards (was a tap only, ADR-716), and a tap only once outside text is in the
        // conversation: its text goes to a server that opens what it names. Checking what it found is a read.
        .init(VoiceToolName.handOverErrand, .handoff, .card),
        .init(VoiceToolName.checkErrands, .lookup, .runsNow),
        // A Studio job (ADR-740): web research and files made on Doddy's server, paid from Doddy's account.
        // A spoken yes or a tap since step 2a (was a tap only, ADR-742), like a handed-over task; a tap only after
        // outside text. It spends money from Doddy's account, not the person's.
        .init(VoiceToolName.makeSomething, .handoff, .card),
        // This week's leaflets, read on Doddy's server (SHOPPING.md): public data, nothing changes. At once since 11 Nov 2026.
        .init(VoiceToolName.findDeals, .lookup, .runsNow),
        // Paying for one web page (ADR-734 to 736; off by default, not on the live agent). The agent only
        // names the page; Doddy's server's own terms are on the payment card, and only a tap (plus the typed
        // amount from the threshold) and a fresh Face ID start it. Counted as a handoff because it hands one
        // request to Doddy's server behind its own card; it is not a `CloudToolName` and never a plan step.
        .init(PaymentToolName.payForPage, .handoff, .card),
        // The conversation itself.
        // ADR-619: translator mode starts and stops at once, without asking (owner, 24 Oct 2026).
        .init(VoiceToolName.startTranslator, .session, .runsNow),
        .init(VoiceToolName.stopTranslator, .session, .runsNow),
        .init(VoiceToolName.proposePlan, .session, .card),
        // An invoice draft on the card (ADR-677): nothing leaves the iPhone; issuing is the card's tap.
        .init(VoiceToolName.draftInvoice, .session, .runsNow),
    ]

    /// From `CloudToolName`: a write is an account write behind the server's approval, the rest are reads.
    private static let cloud: [ToolDescriptor] = CloudToolName.all.sorted().map { name in
        CloudToolName.isWrite(name)
            ? ToolDescriptor(name, .accountWrite, .serverApproval)
            // Every read through Doddy's server runs at once since 11 Nov 2026 (decision 2026-11-11-asked-for-runs-at-once).
            : ToolDescriptor(name, .lookup, .runsNow)
    }
}
