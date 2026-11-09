import Foundation

/// A feature the release scope can hide (decision 2026-11-07-release-scope). Hiding is "no way in": the row in Settings, the
/// card or menu item on Home, the icon's quick action and the voice tool all go; the code and the
/// person's data stay. Nothing here deletes or changes what the person saved.
///
/// Only features that can be hidden are listed. What is never hidden, because it is the product
/// (notes, lists, the conversation, Apple Calendar, Reminders and Contacts by voice, timers, alarms
/// and the stopwatch, sums and conversions, the weather and Wikipedia, Face ID lock, backup and
/// export), has no case and no tool mapping: `ReleaseScope.coreTools` lists those tools.
///
/// Platforms: the iPhone app reads it. The Watch and Mac apps are paused (ADR-572).
public enum Feature: String, CaseIterable, Sendable, Codable {
    // The conversation
    /// Face-to-face and listen-only translation (ADR-215).
    case translator
    /// Several changes on one card, `propose_plan` (ADR-204).
    case planCard

    // Memory, beyond notes and lists
    /// "Close in meaning" results from on-device embeddings (ADR-227).
    case meaningSearch
    /// Google Keep and text files (ADR-231).
    case noteImport
    /// A recorded memo on a note, written out on the iPhone (ADR-230).
    case voiceMemos
    /// The weekly offer to remove duplicates and done lists (ADR-228).
    case tidyUp
    /// Notes in the iPhone's search (ADR-330).
    case spotlight
    /// Learned facts and routines, "What Doddy knows" (ADR-440).
    case learning
    /// DODDY Capture: long recordings with their words and a library (ADR-588).
    case recordings
    /// Lists shared through iCloud (ADR-263).
    case sharedLists
    /// The list on the Lock Screen with tick buttons (ADR-257).
    case shoppingModeLockScreen
    /// A note's reminder when arriving at or leaving a place (ADR-211). Time reminders stay.
    case placeReminders

    // The day
    /// "Time to leave" from Apple Maps (ADR-335).
    case leaveBy
    /// The parking spot (ADR-301).
    case parking
    /// Yearly notifications for picked contacts (ADR-288).
    case birthdays
    /// Moves today's open Reminders to tomorrow (ADR-261).
    case eveningWrapUp
    /// A week of notes and changes (ADR-306).
    case weeklyLookBack
    /// The week ahead (ADR-651).
    case weeklyPlan
    /// Steps, distance and floors from Motion & Fitness (ADR-568).
    case steps

    // Through Doddy's servers
    /// The typed conversation with Claude, "Messages" (ADR-585).
    case messages
    /// Files Doddy made on his server, opened in Quick Look (ADR-633).
    case files
    /// Sign in to Doddy in a browser (ADR-600).
    case doddyWeb
    /// Notes and conversations kept, encrypted, on Doddy's server (ADR-603).
    case cloudMemory
    /// Gmail, Outlook, Google Calendar, Drive, Notion and Todoist through the server (ADR-483 to 489).
    case onlineAccounts
    /// The web, the news and places, looked up through the server (ADR-575).
    case webSearch
    /// Claude on the server: summaries, rewrites, and files it makes (ADR-574).
    case claudeDocuments
    /// This week's leaflets, "Cheapest this week" (ADR-609).
    case deals
    /// Tasks handed to the background worker (ADR-570).
    case errands
    /// "Pilnuj ceny" (ADR-614).
    case priceWatch
    /// The feed of what the person follows (ADR-656).
    case following
    /// The daily digest by push or text (ADR-174).
    case dailyNews
    /// Push and text updates, and the phone number they need (ADR-139).
    case updates
    /// Calling Doddy's number, and "call me now" (S2).
    case phoneCalls
    /// Calls Doddy places for the person (ADR-500).
    case callCases
    /// Studio: research briefs and infographics made on the server (ADR-740 to 742).
    case studio
    /// USDC for a web page that asks for payment (ADR-734 to 737).
    case payments

    // Other apps and devices
    /// Apple Health, read only (ADR-620).
    case health
    /// The training plan and log (ADR-626, ADR-642).
    case trainingPlan
    /// Lights, outlets, fans and scenes (HomeCommand.swift).
    case homeKit
    /// A BLIK transfer on a card, sent by the person in their bank app (ADR-510; restored by #226).
    case blik
    /// A Keynote file made on the iPhone (ADR-567).
    case presentations
    /// inFakt invoices (ADR-640). Nothing is sent to inFakt in any build.
    case invoices
    /// InPost parcels by number (ADR-641).
    case parcels
    /// Photo counts and Doddy's camera by voice (ADR-569).
    case photosAndCamera
    /// The official steps after a lost or stolen wallet, ID or cards, shown as a checklist (`LostWallet.swift`).
    case lostWallet

    /// The voice tools that belong to the feature alone. A hidden feature's tools are refused by
    /// `ToolGate` before anything is looked up or logged, and they come off the live agent
    /// (`ReleaseScope.hiddenTools`). Empty for a feature with no tool of its own.
    public var tools: Set<String> {
        switch self {
        case .translator: [VoiceToolName.startTranslator, VoiceToolName.stopTranslator]
        case .planCard: [VoiceToolName.proposePlan]
        case .leaveBy: [VoiceToolName.remindWhenToLeave]
        case .parking: [VoiceToolName.parkingSpot]
        case .birthdays: [VoiceToolName.upcomingBirthdays]
        case .steps: [VoiceToolName.readSteps]
        case .onlineAccounts: CloudToolName.all.subtracting(Feature.webSearch.tools).subtracting(Feature.claudeDocuments.tools)
        case .webSearch: [CloudToolName.webSearch, "news_search", "find_places"]
        case .claudeDocuments: [CloudToolName.askClaude, CloudToolName.makeDocument]
        case .deals: [VoiceToolName.findDeals]
        case .errands: [VoiceToolName.handOverErrand, VoiceToolName.checkErrands]
        case .following: [VoiceToolName.followNews]
        case .health: [VoiceToolName.readHealthWeek]
        case .trainingPlan: [VoiceToolName.openTrainingPlan]
        case .homeKit: [VoiceToolName.controlHome]
        case .blik: [VoiceToolName.draftBlikTransfer]
        case .presentations: [VoiceToolName.makePresentation]
        case .photosAndCamera: [VoiceToolName.findPhotos, VoiceToolName.openCamera]
        // Doddy's own phone number (ADR-750 to 755): a text to the person's own number goes with the
        // texts, a call booked for later with the calls.
        case .updates: [VoiceToolName.textMe]
        case .phoneCalls: [VoiceToolName.callMeLater]
        case .invoices: [VoiceToolName.draftInvoice]
        case .studio: [VoiceToolName.makeSomething]
        case .payments: [PaymentToolName.payForPage]
        case .lostWallet: [VoiceToolName.lostWallet]
        case .meaningSearch, .noteImport, .voiceMemos, .tidyUp, .spotlight, .learning,
             .recordings, .sharedLists, .shoppingModeLockScreen, .placeReminders, .eveningWrapUp, .weeklyLookBack,
             .weeklyPlan, .files, .doddyWeb, .cloudMemory, .priceWatch, .dailyNews, .parcels:
            []
        // "What's on my screen?" asks the Messages route's Claude, with its key, switch and daily caps
        // (decision 2026-11-09-doddy-looks-at-the-screen), so it comes and goes with Messages.
        case .messages: [VoiceToolName.lookAtScreen]
        // Calls Doddy makes for the user, started from a conversation (decision 2026-11-09-restaurant-calls-one-tap).
        case .callCases: [VoiceToolName.callPlaces]
        }
    }

    /// The Settings › Connections switch that is the feature's only way in, if it has one. The
    /// switch's card goes with the feature; the other switches (Calendar, Reminders, Contacts,
    /// Timers, Maps, Shortcuts, Messages and email, Photos, Camera) stay.
    public var connection: VoiceConnection? {
        switch self {
        case .steps: .steps
        case .homeKit: .home
        case .blik: .blik
        case .presentations: .presentations
        default: nil
        }
    }

    /// The capability the "What I can do" sheet and Home read for the feature (`CapabilityCatalog`).
    /// Hiding the feature marks these as limited, so the sheet and Home's Messages button follow
    /// without a check of their own.
    public var capabilities: Set<Capability> {
        switch self {
        case .messages: [.textAssistant]
        case .onlineAccounts: [.connectedAccounts]
        case .updates: [.pushUpdates, .textUpdates]
        case .phoneCalls: [.phoneCalls]
        case .dailyNews: [.newsDigests]
        case .sharedLists: [.cloudSync]
        default: []
        }
    }
}

/// Which features a build shows (decision 2026-11-07-release-scope; `docs/implementation/RELEASE_SCOPE.md`). One list, read
/// by every way in: the voice tool gate, Home's menu and bottom bar, the Settings rows, the icon's
/// quick actions, the language picker and the capability catalog. There was no switch for "Hide"
/// before this (`GO_LIVE_CHECKLIST.md` B2): a feature could only be shipped or deleted.
///
/// The scope is decided by the build, never by a server or a remote flag: the app ships
/// `ReleaseScope.shipping`; a Debug build can show everything through Settings › About › Advanced
/// (`previewEverythingKey`), so the owner can try a hidden feature on their phone. A Release build
/// ignores that key.
public struct ReleaseScope: Equatable, Sendable {
    public let hidden: Set<Feature>

    public init(hidden: Set<Feature>) {
        self.hidden = hidden
    }

    /// Every feature, as the code was built until decision 2026-11-07-release-scope.
    public static let everything = ReleaseScope(hidden: [])

    /// The v1 beta (`docs/product/V1_SCOPE.md`, `PRZEGLAD_FUNKCJI_2026-11-07.md` §6): the
    /// conversation, memory, Apple Calendar, Reminders and Contacts, timers, alarms, the stopwatch,
    /// sums, the weather and Wikipedia, photo notes and camera, Face ID, backup and export, Messages
    /// behind its own consent, and the translator (owner, 8 Nov 2026: decision 2026-11-08-translator-in-beta).
    /// Everything that needs a server the beta doesn't keep, a vendor, a permission the beta doesn't
    /// ask for, or that has never run on a phone, is hidden. The list is the owner's to change: edit
    /// it here, and the tests say what the agent must lose.
    public static let shipping = ReleaseScope(hidden: [
        .planCard,
        .meaningSearch, .noteImport, .voiceMemos, .tidyUp, .spotlight, .learning, .recordings, .sharedLists,
        .shoppingModeLockScreen, .placeReminders,
        .leaveBy, .parking, .birthdays, .eveningWrapUp, .weeklyLookBack, .weeklyPlan, .steps,
        .files, .doddyWeb, .cloudMemory, .onlineAccounts, .webSearch, .claudeDocuments, .deals, .errands, .priceWatch,
        .following, .dailyNews, .updates, .phoneCalls, .callCases, .studio, .payments,
        .health, .trainingPlan, .homeKit, .blik, .presentations, .invoices, .parcels, .lostWallet,
    ])

    /// The Debug-only preference that shows everything on the owner's phone. A Release build never reads it.
    public static let previewEverythingKey = "releaseScope.previewEverything"

    /// A Debug build shows every feature until the switch is turned off (owner, 8 Nov 2026, decision
    /// 2026-11-08-debug-shows-every-feature). A Release or TestFlight build is always `shipping`.
    public static let debugShowsEverythingByDefault = true

    /// The scope of a Debug build, from the preference: nil (never set) or true shows everything,
    /// false shows what the beta ships.
    public static func debug(showEverything: Bool?) -> ReleaseScope {
        (showEverything ?? debugShowsEverythingByDefault) ? .everything : .shipping
    }

    public func shows(_ feature: Feature) -> Bool { !hidden.contains(feature) }

    /// A Connections switch is shown unless the one feature it serves is hidden.
    public func shows(_ connection: VoiceConnection) -> Bool {
        !hidden.contains { $0.connection == connection }
    }

    /// The hidden feature a voice tool belongs to, or nil when the tool runs in this build.
    public func hiddenFeature(forTool name: String) -> Feature? {
        hidden.first { $0.tools.contains(name) }
    }

    /// The tools to take off the live agent for this scope, sorted. The app refuses them anyway
    /// (`ToolGate.Decision.hidden`), so a live agent that still has one only makes Doddy say the
    /// feature isn't in the app.
    public var hiddenTools: [String] {
        hidden.flatMap(\.tools).sorted()
    }

    /// The languages the picker offers. The beta ships Polish and English, the two anyone has read
    /// (`l10n/REVIEW_NOTES.md`); the machine drafts come back one at a time after a native read
    /// (V1 decision 2). Voice answers in whatever language the person speaks regardless.
    public var languages: [AppLanguage] {
        self == .everything ? AppLanguage.allCases : AppLanguage.allCases.filter { Self.shippedLanguages.contains($0) }
    }

    private static let shippedLanguages: Set<AppLanguage> = [.english, .polish, .followPhone]

    /// The picker's rows: the shipped languages, plus the person's current choice if it is one of
    /// the hidden ones, so a choice made in an older build still shows as selected and can be
    /// changed. Order is `AppLanguage.allCases`'s.
    public func languageChoices(current: AppLanguage) -> [AppLanguage] {
        AppLanguage.allCases.filter { languages.contains($0) || $0 == current }
    }

    /// The tools no feature owns: the product itself, in every scope. Listed so a new tool has to be
    /// placed on purpose (`ReleaseScopeTests` fails on one that is in neither list).
    public static let coreTools: Set<String> = Set<String>([
        VoiceToolName.searchMemories, VoiceToolName.saveMemory, VoiceToolName.remindAboutNote,
        VoiceToolName.readList, VoiceToolName.addToList, VoiceToolName.checkOff, VoiceToolName.removeFromList,
        VoiceToolName.createList, VoiceToolName.addIngredients,
        VoiceToolName.readCalendar, VoiceToolName.findFreeTime, VoiceToolName.createCalendarEvent,
        VoiceToolName.changeCalendarEvent, VoiceToolName.deleteCalendarEvent, VoiceToolName.deleteCalendarEvents,
        VoiceToolName.createReminder, VoiceToolName.changeReminder, VoiceToolName.deleteReminder,
        VoiceToolName.moveReminders, VoiceToolName.undoLast,
        VoiceToolName.setTimer, VoiceToolName.setAlarm, VoiceToolName.listAlarms, VoiceToolName.cancelAlarm,
        VoiceToolName.startStopwatch, VoiceToolName.stopStopwatch, VoiceToolName.checkStopwatch,
        VoiceToolName.lookupContact, VoiceToolName.draftMessage,
        VoiceToolName.calculate, VoiceToolName.convertUnits, VoiceToolName.convertCurrency,
        VoiceToolName.openMap, VoiceToolName.runShortcut,
        VoiceToolName.noteCapabilityGap,
    ]).union(ToolCatalog.webLookups)
}

extension CapabilityCatalog {
    /// The catalog with the scope's hidden features marked as limited, so "What I can do" and the
    /// screens that read it say the same as the scope. An available capability of a shown feature is
    /// unchanged; a capability already not available stays as it was.
    public func hiding(_ scope: ReleaseScope) -> CapabilityCatalog {
        var statuses = self.statuses
        for feature in scope.hidden {
            for capability in feature.capabilities where statuses[capability] == .available {
                statuses[capability] = .limited(Self.notInThisVersion)
            }
        }
        return CapabilityCatalog(statuses: statuses)
    }

    /// The note a hidden feature's capability carries.
    public static let notInThisVersion = "Not in this version of Doddy"
}
