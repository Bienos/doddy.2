import XCTest
@testable import DoddyCore

/// What leaves this iPhone follows the settings, never a fixed list.
final class DataFlowTests: XCTestCase {
    private let base = DataFlowState(
        rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
        connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)

    private func row(_ id: String, _ state: DataFlowState) -> DataFlowRow {
        DataFlow.rows(state).first { $0.id == id }!
    }

    func testOffSwitchesShowAsNotSent() throws {
        XCTAssertFalse(row("tokenServer", base).isActive)
        XCTAssertFalse(row("doddyServer", base).isActive)
        XCTAssertFalse(row("askDoddy", base).isActive)
        XCTAssertTrue(row("elevenlabs", base).isActive)
        // Place search (ADR-196) is user-started, so always listed; places themselves stay here.
        XCTAssertEqual(row("placeSearch", base).destination, "Apple Maps (place search and travel time)")
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("Places you set for reminders") })
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains("Earlier wordings of notes you corrected, except in files you export."))
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("Notes suggested after a conversation:") }, "save suggestions are on-device")
        let siriOff = try XCTUnwrap(DataFlow.rows(base).first { $0.id == "siri" })
        XCTAssertFalse(siriOff.isActive, "off unless the app says the switch is on")
        var siriState = base
        siriState.siriReadsNotes = true
        let siriOn = try XCTUnwrap(DataFlow.rows(siriState).first { $0.id == "siri" })
        XCTAssertTrue(siriOn.isActive)
        XCTAssertTrue(siriOn.what.contains("the note Siri reads back"))
        XCTAssertEqual(row("elevenlabs", base).what, "Your voice, the conversation, your saved notes, your list names (items only when Doddy reads or changes a list) and your personality settings.")
    }

    func testVoiceRowGrowsWithWhatIsSwitchedOn() {
        var state = base
        state.rememberConversations = true
        state.shareProfileWithVoice = true
        state.connectionsOn = [.reminders, .calendar]
        state.doddyServerSet = true
        let what = row("elevenlabs", state).what
        XCTAssertTrue(what.contains("your last few conversations"))
        XCTAssertTrue(what.contains("your introduction answers"))
        XCTAssertTrue(what.contains("(Calendar, Reminders)"))
        XCTAssertTrue(what.contains("results from your online accounts"))
    }

    func testPauseAllRemovesAppsFromTheVoiceRow() {
        var state = base
        state.connectionsOn = [.calendar]
        state.doddyServerSet = true
        state.pauseAll = true
        XCTAssertFalse(row("elevenlabs", state).what.contains("Calendar"))
        XCTAssertFalse(row("elevenlabs", state).what.contains("online accounts"))
        XCTAssertTrue(row("doddyServer", state).note?.contains("paused") ?? false)
    }

    /// ADR-586: typed questions go through the messaging server to Anthropic, so they can only leave with a server set.
    func testAskDoddyNamesAnthropicAndNeedsTheMessagingServer() {
        var state = base
        XCTAssertEqual(row("askDoddy", state).note, "Ask Doddy is off, so nothing goes there.")
        state.askDoddyOn = true
        XCTAssertFalse(row("askDoddy", state).isActive, "on, but no server: nothing can be sent")
        XCTAssertEqual(row("askDoddy", state).note, "No messaging server is set, so typed questions can't be sent.")
        state.messagingServerSet = true
        let ask = row("askDoddy", state)
        XCTAssertTrue(ask.isActive)
        XCTAssertTrue(ask.destination.contains("Anthropic"))
        XCTAssertFalse(ask.destination.contains("OpenAI"))
        XCTAssertTrue(DataFlow.cloudAISummary(state).contains("Anthropic (Ask Doddy)"))
        XCTAssertFalse(DataFlow.cloudAISummary(state).contains("OpenAI (Ask Doddy)"))
    }

    func testAskDoddyMentionsNotesOnlyWhenAllowed() {
        var state = base
        state.askDoddyOn = true
        XCTAssertTrue(row("askDoddy", state).what.contains("saved notes"))
        state.askDoddyUsesNotes = false
        XCTAssertEqual(row("askDoddy", state).what, "Typed questions, with a photo or file you attach to one (not kept).")
    }

    /// ADR-570: handed-over tasks go to the messaging server and Anthropic, only with a server set.
    func testErrandsRowNamesAnthropicAndNeverTheNotes() {
        XCTAssertFalse(row("errands", base).isActive)
        XCTAssertTrue(row("errands", base).note?.contains("can't be handed over") ?? false)
        var state = base
        state.messagingServerSet = true
        let errands = row("errands", state)
        XCTAssertTrue(errands.isActive)
        XCTAssertTrue(errands.destination.contains("Anthropic"))
        XCTAssertTrue(errands.what.contains("Never your saved notes"))
        XCTAssertTrue(errands.note?.contains("no words from the task") ?? false)
    }

    /// SHOPPING.md: leaflets go through the messaging server; nothing that identifies the user goes to the
    /// shops, and the row says Rossmann gets the item names as a search.
    func testLeafletsRowSaysNothingIdentifyingGoesToTheShops() {
        XCTAssertFalse(row("deals", base).isActive)
        XCTAssertTrue(row("deals", base).note?.contains("can't be checked") ?? false)
        var state = base
        state.messagingServerSet = true
        let deals = row("deals", state)
        XCTAssertTrue(deals.isActive)
        XCTAssertTrue(deals.destination.contains("Anthropic"))
        XCTAssertTrue(deals.what.contains("Nothing that identifies you goes to any shop."))
        XCTAssertTrue(deals.what.contains("rossmann.pl as a search"), "the one shop that gets the item names is named")
        XCTAssertTrue(deals.what.contains("Never your saved notes"))
        XCTAssertTrue(deals.note?.contains("only daily counts") ?? false)
        state.pauseAll = true
        XCTAssertFalse(row("deals", state).isActive, "paused: the server isn't asked")
        XCTAssertTrue(row("errands", state).what.contains("Serper"), "shopping tasks name the offer source")
    }

    /// SHOPPING_WATCH.md (ADR-614): a watched price goes to the messaging server, which reads the shop's page;
    /// the notification has no product words, nothing is bought, no AI service is involved, and nothing is sent
    /// without a server or while Connections are paused.
    func testPriceWatchRowSaysWhatGoesWhereAndThatNothingIsBought() {
        XCTAssertFalse(row("watches", base).isActive)
        XCTAssertEqual(row("watches", base).note, "No messaging server is set, so prices can't be watched.")
        XCTAssertFalse(DataFlow.networkSummary(base).contains("prices you watch"))
        var state = base
        state.messagingServerSet = true
        let watches = row("watches", state)
        XCTAssertTrue(watches.isActive)
        XCTAssertTrue(watches.destination.contains("messaging server"))
        XCTAssertTrue(watches.destination.contains("shops' pages"))
        for part in ["shop's name and page address", "the product's title", "the price you want", "a few times a day for 30 days",
                     "The notification has no product words", "Nothing is bought, ordered or signed in", "Never your saved notes"] {
            XCTAssertTrue(watches.what.contains(part), part)
        }
        XCTAssertTrue(watches.when.contains("when you tap Yes on the card"), "a watch starts from the card's Yes, watch button, never by a spoken yes")
        XCTAssertFalse(watches.when.contains("say yes"))
        XCTAssertTrue(watches.note?.contains("keeps no page content") ?? false)
        XCTAssertTrue(DataFlow.networkSummary(state).contains("the shops' pages, read by your messaging server (prices you watch)"))
        // No model reads a watch: it is in no AI summary.
        XCTAssertFalse(watches.destination.contains("Anthropic"))
        XCTAssertFalse(DataFlow.cloudAISummary(state).localizedCaseInsensitiveContains("watch"))
        // Paused: nothing new goes, and the row says the server still checks what is already running.
        state.pauseAll = true
        let paused = row("watches", state)
        XCTAssertFalse(paused.isActive)
        XCTAssertTrue(paused.note?.contains("already watch") ?? false)
        XCTAssertTrue(paused.note?.contains("until you stop or delete them") ?? false)
        XCTAssertFalse(DataFlow.networkSummary(state).contains("prices you watch"))
    }

    func testMessagingServerRowListsNotesOnlyWhenTheCopyIsOn() {
        XCTAssertFalse(row("messagingServer", base).isActive)
        var state = base
        state.messagingServerSet = true
        XCTAssertTrue(row("messagingServer", state).isActive)
        XCTAssertFalse(row("messagingServer", state).what.contains("saved notes"))
        XCTAssertFalse(row("messagingServer", state).what.contains("notification token"))
        state.pushOn = true
        state.memoryCopyOn = true
        XCTAssertTrue(row("messagingServer", state).what.contains("this iPhone's notification token"))
        XCTAssertTrue(row("messagingServer", state).what.contains("a copy of your saved notes"))
    }

    func testTextsToDoddyAreListedAsNotesWithNoAI() {
        // ADR-753: texts kept as notes on the messaging server; no model reads them (ADR-755).
        var state = base
        state.messagingServerSet = true
        state.newsWriterProvider = "openai"
        XCTAssertFalse(row("messagingServer", state).what.contains("texts you send"))
        state.textsToDoddyOn = true
        XCTAssertTrue(row("messagingServer", state).what.contains("the texts you send Doddy's number"))
        XCTAssertFalse(row("messagingServer", state).destination.contains("Anthropic"), "notes alone go to no AI")
        XCTAssertFalse(DataFlow.cloudAISummary(state).contains("replies to your texts"))
        XCTAssertFalse(row("messagingServer", state).note?.contains("written by Anthropic") == true)
        state.textsToDoddyOn = false
        XCTAssertFalse(row("messagingServer", state).what.contains("the texts you send Doddy's number"))
    }

    func testNewsWriterIsNamedOnlyAsTheServerReportsIt() {
        var state = base
        state.messagingServerSet = true
        let unknown = row("messagingServer", state)
        XCTAssertTrue(unknown.destination.contains("Anthropic or OpenAI"))
        XCTAssertTrue(unknown.note?.contains("headlines to Anthropic or OpenAI") == true)
        state.newsWriterProvider = "openai"
        let openAI = row("messagingServer", state)
        XCTAssertTrue(openAI.destination.contains("OpenAI"))
        XCTAssertFalse(openAI.destination.contains("Anthropic"))
        XCTAssertFalse(openAI.note?.contains("Anthropic") == true)
        state.newsWriterProvider = "anthropic"
        XCTAssertFalse(row("messagingServer", state).destination.contains("OpenAI"))
    }

    func testRememberedConversationsLineFollowsTheSwitch() {
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains("Conversations: none are remembered."))
        var state = base
        state.rememberConversations = true
        XCTAssertFalse(DataFlow.staysOnPhone(state).contains("Conversations: none are remembered."))
    }

    // ADR-440: what Doddy learned reaches a conversation only when the user switched that on.
    func testLearnedFactsAreListedOnlyWhenSharedWithVoice() {
        XCTAssertFalse(row("elevenlabs", base).what.contains("What I've learned"))
        var shared = base
        shared.learnedSharedWithVoice = true
        XCTAssertTrue(row("elevenlabs", shared).what.contains("the facts and routines you confirmed under What I've learned"))
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("What Doddy learned") }, "proposals and counts are always on the phone")
    }
}

/// Settings → Privacy's Network and Cloud AI rows come from the same rows as What leaves this
/// iPhone (audit 2026-10-12 §5 #6, ADR-447), so they can't list less than that screen.
final class DataFlowSummaryTests: XCTestCase {
    private let base = DataFlowState(
        rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
        connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)

    private var everything: DataFlowState {
        var state = base
        state.tokenServerSet = true
        state.doddyServerSet = true
        state.askDoddyOn = true
        state.messagingServerSet = true
        state.siriReadsNotes = true
        state.sharedLists = 1
        state.voiceProvider = .openAIRealtime
        return state
    }

    func testEveryRowIsNamedInTheNetworkSummaryOrDeliberatelyLeftOut() {
        for row in DataFlow.rows(everything) {
            XCTAssertTrue(
                DataFlow.networkNames[row.id] != nil || DataFlow.notInNetworkSummary.contains(row.id),
                "\(row.id) is in What leaves this iPhone but not in Settings' Network row")
        }
        XCTAssertTrue(DataFlow.notInNetworkSummary.isDisjoint(with: DataFlow.networkNames.keys))
    }

    func testNetworkNamesExactlyTheActiveRows() {
        let summary = DataFlow.networkSummary(everything)
        for row in DataFlow.rows(everything) where row.isActive {
            if let name = DataFlow.networkNames[row.id] {
                XCTAssertTrue(summary.contains(name), "\(row.id) is on but missing: \(summary)")
            }
        }
        // The audit's missing ones are there when they're on.
        for name in ["your Doddy messaging server", "Apple Maps", "European Central Bank", "iCloud", "Siri", "Anthropic (Ask Doddy, through your messaging server)"] {
            XCTAssertTrue(summary.contains(name), name)
        }
    }

    func testSwitchedOffServicesAreNotNamed() {
        var state = base
        state.siriReadsNotes = false
        state.pauseAll = true
        let summary = DataFlow.networkSummary(state)
        for name in ["voice token server", "Doddy server", "messaging server", "Ask Doddy", "Siri", "iCloud", "European Central Bank", "OpenAI"] {
            XCTAssertFalse(summary.contains(name), "\(name) is off but named: \(summary)")
        }
        XCTAssertTrue(summary.hasPrefix("ElevenLabs (while talking)"), "voice is always possible")
        XCTAssertTrue(summary.hasSuffix("What leaves this iPhone says what goes."))
    }

    func testCloudAINamesEveryAIServiceThatIsOn() {
        XCTAssertEqual(DataFlow.cloudAISummary(base), "ElevenLabs (voice)")
        // OpenAI runs the voice where the token server is set (ADR-442): ElevenLabs gets no voice then.
        XCTAssertEqual(
            DataFlow.cloudAISummary(everything),
            "OpenAI (voice); Anthropic (Ask Doddy); ElevenLabs (phone calls) and Anthropic or OpenAI (daily news) on your messaging server; Anthropic (tasks you hand over); Anthropic (the answer card of calls Doddy places for you); Anthropic (leaflets you check)")
        XCTAssertFalse(DataFlow.networkSummary(everything).contains("ElevenLabs (while talking)"))
        var elevenLabs = everything
        elevenLabs.voiceProvider = .elevenLabs
        XCTAssertTrue(DataFlow.cloudAISummary(elevenLabs).hasPrefix("ElevenLabs (voice); Anthropic (Ask Doddy)"))
        var state = everything
        state.newsWriterProvider = "anthropic"
        XCTAssertTrue(DataFlow.cloudAISummary(state).contains("Anthropic (daily news)"))
    }

    func testWebSignInSaysWhatTheBrowserSeesAndThatNotesStayHere() throws {
        // ADR-600.
        var state = base
        state.doddyServerSet = true
        let row = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webSignIn" })
        XCTAssertTrue(row.isActive)
        XCTAssertTrue(row.what.contains("Never your saved notes"))
        XCTAssertTrue(row.what.contains("files Doddy made"))
        state.doddyServerSet = false
        let off = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webSignIn" })
        XCTAssertFalse(off.isActive)
        XCTAssertNotNil(off.note)
    }

    func testKeptNotesAndConversationsHaveTheirOwnRowAndNameAnthropic() throws {
        // ADR-603.
        var state = base
        state.doddyServerSet = true
        let off = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertFalse(off.isActive)
        XCTAssertEqual(off.what, "Nothing: both switches are off.")
        XCTAssertTrue(DataFlow.rows(state).first { $0.id == "webSignIn" }?.what.contains("Never your saved notes, lists, profile or conversations.") ?? false)
        XCTAssertFalse(DataFlow.cloudAISummary(state).contains("web"))

        state.webNotesKept = true
        let notes = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertTrue(notes.isActive)
        XCTAssertTrue(notes.what.contains("saved notes (not private ones)"))
        XCTAssertFalse(notes.what.contains("conversations"))
        XCTAssertTrue(notes.destination.contains("Anthropic"))
        XCTAssertTrue(notes.note?.contains("the server can read it") ?? false, "it says plainly that this is not end-to-end")

        state.webConversationsKept = true
        let both = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertTrue(both.what.contains("conversations (not private ones), never audio"))
        XCTAssertTrue(both.note?.contains("1 year") ?? false)
        XCTAssertTrue(DataFlow.cloudAISummary(state).contains("Anthropic (questions you ask on the web"))
        XCTAssertTrue(DataFlow.networkSummary(state).contains("notes and conversations you keep there"))
        // The browser's row no longer claims the browser never sees notes.
        let browser = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webSignIn" })
        XCTAssertFalse(browser.what.contains("Never your saved notes"))
        XCTAssertTrue(browser.what.contains("notes and conversations you keep on Doddy's server"))
    }

    /// ADR-721: before this iPhone has signed in to Doddy's server nothing has been sent, and the row says that.
    /// It used to say "No Doddy server is set", which was false for everybody since ADR-563 built the address in.
    func testNothingIsSaidToGoToTheServerBeforeTheFirstSignIn() throws {
        var state = base
        state.webNotesKept = true
        state.doddyServerSet = false
        let row = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertFalse(row.isActive)
        XCTAssertEqual(row.note, "Keep on Doddy's server is on, but this iPhone hasn't signed in there yet, so nothing has been sent. It is sent once it has.")
        // With the switches off the row says so, whether or not the iPhone has signed in.
        state.webNotesKept = false
        XCTAssertEqual(try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" }).note,
                       "Keep on Doddy's server is off in Settings › Doddy on the web, so nothing goes there.")
        state.doddyServerSet = true
        XCTAssertEqual(try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" }).note,
                       "Keep on Doddy's server is off in Settings › Doddy on the web, so nothing goes there.")
    }

    /// ADR-721: the Doddy server row is true both before the first sign-in and after it.
    func testTheDoddyServerRowIsTrueBeforeAndAfterTheFirstSignIn() throws {
        // Before: not sent, and it says what will happen instead of claiming there is no server.
        let before = try XCTUnwrap(DataFlow.rows(base).first { $0.id == "doddyServer" })
        XCTAssertFalse(before.isActive)
        let note = try XCTUnwrap(before.note)
        XCTAssertTrue(note.hasPrefix("Nothing has been sent to Doddy's server yet."))
        XCTAssertTrue(note.contains("random device ID"), "it says what the first online feature sends")
        XCTAssertFalse(note.localizedCaseInsensitiveContains("no doddy server is set"))

        // After: the device ID, the searches that go at once and what waits for a yes are all named.
        var state = base
        state.doddyServerSet = true
        let after = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "doddyServer" })
        XCTAssertTrue(after.isActive)
        XCTAssertNil(after.note)
        for part in ["random device ID", "Keychain", "web, news or places search", "go at once without asking", "Monid",
                     "after you say yes or tap", "only after you tap its card to confirm",
                     "Never your saved notes, except the copy you choose to keep on Doddy's server"] {
            XCTAssertTrue(after.what.contains(part), part)
        }
        XCTAssertFalse(after.what.contains("a search word, or the text"), "the old wording said every search word waits for a yes")
        XCTAssertTrue(after.when.contains("signs in or renews its session"))
        // Paused connections keep the note they had.
        state.pauseAll = true
        XCTAssertTrue(try XCTUnwrap(DataFlow.rows(state).first { $0.id == "doddyServer" }).note?.contains("paused") ?? false)
    }

    func testNoRowClaimsThereIsNoDoddyServerInEitherState() {
        for signedIn in [false, true] {
            for kept in [false, true] {
                var state = base
                state.doddyServerSet = signedIn
                state.webNotesKept = kept
                state.webConversationsKept = kept
                for row in DataFlow.rows(state) {
                    for text in [row.what, row.when, row.note ?? ""] {
                        XCTAssertFalse(text.localizedCaseInsensitiveContains("no doddy server is set"), "\(row.id): \(text)")
                    }
                }
            }
        }
        // The browser's row, before the first sign-in, says nothing has been sent and when something would be.
        let browser = DataFlow.rows(base).first { $0.id == "webSignIn" }
        XCTAssertEqual(browser?.isActive, false)
        XCTAssertTrue(browser?.note?.hasPrefix("Nothing has been sent to Doddy's server yet.") ?? false)
    }

    /// ADR-721: the Network summary in Settings › Privacy names Doddy's server once it is in use, by what it is for.
    func testTheNetworkSummaryNamesTheServerOnceItIsInUse() {
        XCTAssertFalse(DataFlow.networkSummary(base).contains("your Doddy server"))
        var state = base
        state.doddyServerSet = true
        XCTAssertTrue(DataFlow.networkSummary(state).contains("your Doddy server (web search, online accounts and the web)"))
        XCTAssertFalse(DataFlow.networkSummary(state).contains("(Connected Apps)"), "it is not only Connected Apps any more")
    }

    /// The voice token server row no longer talks about a wake word, which was removed in ADR-549.
    func testTheTokenServerRowHasNoWakeWordSetup() throws {
        let token = try XCTUnwrap(DataFlow.rows(base).first { $0.id == "tokenServer" })
        XCTAssertFalse(token.when.localizedCaseInsensitiveContains("wake"))
        XCTAssertTrue(token.when.contains("a conversation requests a provider connection credential"))
        XCTAssertTrue(token.what.contains("No voice, transcript, notes or profile details are sent"))
    }

    /// ADR-722: the promise that Private notes are never sent holds for the morning check-in too, and the rows say so.
    func testThePrivateNotePromiseIsNamedWhereTheCheckInIsListed() throws {
        var state = base
        state.morningCheckInOn = true
        let what = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "elevenlabs" }).what
        XCTAssertTrue(what.contains("today's Doddy reminders (not those of notes you mark Private)"))
        XCTAssertTrue(try XCTUnwrap(DataFlow.rows(state).first { $0.id == "elevenlabs" }).note?.contains("Notes you mark Private are never sent.") ?? false)
        let siri = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "siri" })
        XCTAssertTrue(siri.when.contains("Doddy unlocked, if you use the Face ID lock"))
        XCTAssertTrue(siri.when.contains("Notes you mark Private are never read out."))
    }
}

/// Invoices and parcels (ADR-640, ADR-641): what the screen says matches what the build can do.
final class DataFlowInvoiceAndParcelTests: XCTestCase {
    private let base = DataFlowState(
        rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
        connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)

    private func row(_ id: String, _ state: DataFlowState) throws -> DataFlowRow {
        try XCTUnwrap(DataFlow.rows(state).first { $0.id == id })
    }

    func testInFaktIsNotSentWhileSendingIsNotVerified() throws {
        XCTAssertFalse(InFaktAPI.createVerified, "this test describes the build before a sandbox call has settled the wire format")
        var state = base
        state.inFaktKeySaved = true
        let saved = try row("inFakt", state)
        XCTAssertFalse(saved.isActive, "a saved key alone sends nothing")
        XCTAssertTrue(saved.note?.contains("isn't switched on in this build") ?? false)
        XCTAssertTrue(saved.note?.contains("Keychain") ?? false)
        XCTAssertFalse(DataFlow.networkSummary(state).contains("inFakt"))
        XCTAssertFalse(try row("inFakt", base).isActive)
    }

    func testInFaktRowSaysOnlyAConfirmedInvoiceAndNeverDoddysServer() throws {
        let inFakt = try row("inFakt", base)
        XCTAssertTrue(inFakt.what.hasPrefix("Only an invoice you confirmed"))
        XCTAssertTrue(inFakt.what.contains("Doddy's server sees neither"))
        XCTAssertEqual(inFakt.when, "Only when you tap Confirm on an invoice card.")
    }

    func testInPostIsOnWhenConnectionsAreNotPausedAndNamesWhatGoes() throws {
        let on = try row("inPost", base)
        XCTAssertTrue(on.isActive)
        XCTAssertTrue(on.what.contains("parcel number"))
        XCTAssertTrue(on.what.contains("No account, no key"))
        XCTAssertTrue(on.note?.contains("internet address") ?? false, "it does not claim InPost sees nothing")
        XCTAssertTrue(DataFlow.networkSummary(base).contains("InPost"))

        var paused = base
        paused.pauseAll = true
        let off = try row("inPost", paused)
        XCTAssertFalse(off.isActive)
        XCTAssertEqual(off.note, "Connections are paused, so parcels aren't looked up.")
        XCTAssertFalse(DataFlow.networkSummary(paused).contains("InPost"))
    }

    func testTheKeyAndTheParcelListStayOnThePhone() {
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("Your inFakt key") && $0.contains("never on Doddy's server") })
    }

    func testNeitherRowIsAnAIService() {
        var state = base
        state.inFaktKeySaved = true
        XCTAssertFalse(DataFlow.cloudAISummary(state).contains("InPost"))
        XCTAssertFalse(DataFlow.cloudAISummary(state).contains("inFakt"))
    }
}

/// Calls Doddy places for the user (ADR-500..507) and the messages Doddy sends back (POST /v1/updates), and the words
/// for the actions that are a tap and no longer a spoken yes (ADR-716). Each statement was read from the app's and the
/// server's code in the review of 4 Nov 2026 (see the comments in `DataFlow.rows`).
final class DataFlowCallsAndUpdatesTests: XCTestCase {
    private let base = DataFlowState(
        rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
        connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)

    private var withServer: DataFlowState {
        var state = base
        state.messagingServerSet = true
        return state
    }

    private func row(_ id: String, _ state: DataFlowState) throws -> DataFlowRow {
        try XCTUnwrap(DataFlow.rows(state).first { $0.id == id }, id)
    }

    func testPlacedCallsHaveARowThatSaysWhatIsSentWhenAndWhere() throws {
        let calls = try row("callCases", withServer)
        XCTAssertTrue(calls.isActive)
        for place in ["messaging server", "Twilio", "ElevenLabs", "Anthropic"] {
            XCTAssertTrue(calls.destination.contains(place), place)
        }
        // What is sent: the brief, ticked facts only, and nothing dialled before the card is approved.
        for part in ["Polish phone number", "who the call is for", "only the facts you ticked", "Unticked facts never leave",
                     "Nothing is dialled until you approve the card", "ElevenLabs also hears the other person",
                     "Twilio transcribes both sides", "Google engine", "told not to record it",
                     "Anthropic's Claude reads the call's transcript", "If you tap Take over", "never words"] {
            XCTAssertTrue(calls.what.contains(part), part)
        }
        XCTAssertTrue(calls.when.contains("When you prepare a call's card (nothing is dialled)"))
        XCTAssertTrue(calls.when.contains("between 8:00 and 23:00 Warsaw time"))
        XCTAssertTrue(calls.when.contains("at most 5 minutes"))
        // What the server keeps and deletes, and what the notification says.
        let note = try XCTUnwrap(calls.note)
        for part in ["encrypted", "each with a receipt", "7 days", "asks ElevenLabs to delete its copy", "only that an answer is waiting",
                     "once your number is verified"] {
            XCTAssertTrue(note.contains(part), part)
        }
        // It starts from Settings, not from a conversation, so pausing connections doesn't change it.
        var paused = withServer
        paused.pauseAll = true
        XCTAssertTrue(try row("callCases", paused).isActive)
    }

    func testTheUpdatesRowSaysTheAppSendsOnlyTheTestsAndWhatTextingDoddyDoes() throws {
        let updates = try row("updates", withServer)
        XCTAssertTrue(updates.isActive)
        XCTAssertTrue(updates.destination.contains("Apple (notifications)") && updates.destination.contains("Twilio (texts)"))
        XCTAssertTrue(updates.what.contains("Test from Doddy: notifications are working."))
        XCTAssertTrue(updates.what.contains("Test from Doddy: texts are working."))
        XCTAssertTrue(updates.what.contains("in their own rows"), "what other features send is described where it belongs")
        // Text with Doddy sends the person's words to Anthropic; the row says so, says it is off by default and that notes stay out.
        XCTAssertTrue(updates.what.contains("If you also turn on Text with Doddy"))
        XCTAssertTrue(updates.what.contains("Anthropic, whose Claude writes one reply by text"))
        XCTAssertTrue(updates.what.contains("can't read your notes or change anything"))
        XCTAssertTrue(updates.when.contains("Only when you tap Send a test notification or Send a test text"))
        XCTAssertTrue(updates.when.contains("only if you turned on Text with Doddy"))
        let note = try XCTUnwrap(updates.note)
        XCTAssertTrue(note.contains("only until it is sent"))
        XCTAssertTrue(note.contains("Text with Doddy is off until you turn it on"))
    }

    func testWithoutAMessagingServerNeitherRowClaimsAnythingGoes() throws {
        let calls = try row("callCases", base)
        let updates = try row("updates", base)
        XCTAssertFalse(calls.isActive)
        XCTAssertFalse(updates.isActive)
        XCTAssertEqual(calls.note, "No messaging server is set, so calls can't be placed.")
        XCTAssertEqual(updates.note, "No messaging server is set, so nothing goes there.")
        XCTAssertFalse(DataFlow.networkSummary(base).contains("Twilio, ElevenLabs and Anthropic (calls"))
        XCTAssertFalse(DataFlow.cloudAISummary(base).contains("calls Doddy places"))
    }

    func testTheNewRowsAreInTheSummariesOnlyWhenTheServerIsSet() {
        let network = DataFlow.networkSummary(withServer)
        XCTAssertTrue(network.contains("Twilio, ElevenLabs and Anthropic (calls Doddy places for you, through your messaging server)"))
        XCTAssertTrue(network.contains("Apple and Twilio (notifications and texts from Doddy, through your messaging server)"))
        // The answer card is written by Claude, so Settings' Cloud AI line names it like the other Anthropic features.
        XCTAssertTrue(DataFlow.cloudAISummary(withServer).contains("Anthropic (the answer card of calls Doddy places for you)"))
    }

    /// ADR-716: handing a task over is a tap on its card. A watch is started only from the card's Yes, watch button. Neither
    /// is described as something you say.
    func testActionsThatAreATapAreNotDescribedAsSpokenYes() throws {
        let errands = try row("errands", withServer)
        XCTAssertEqual(errands.when, "Only when you tap Yes on the card to hand a task over, until its result is saved on this iPhone.")
        XCTAssertFalse(errands.when.contains("say yes"))
        let watches = try row("watches", withServer)
        XCTAssertTrue(watches.when.hasPrefix("Only when you tap Yes on the card to watch a price"))
        XCTAssertFalse(watches.when.contains("say yes"))
    }

    /// Reads that still accept a spoken yes keep their wording; a write never says "say yes" without a tap. The rows that may
    /// mention a spoken yes are the leaflets (a read) and the Doddy server row (reads: "say yes or tap").
    func testOnlyReadsStillMentionASpokenYes() {
        var all = withServer
        all.doddyServerSet = true
        all.webNotesKept = true
        all.webConversationsKept = true
        all.morningCheckInOn = true
        all.askDoddyOn = true
        all.siriReadsNotes = true
        all.sharedLists = 1
        all.pushOn = true
        all.memoryCopyOn = true
        all.shareProfileWithVoice = true
        all.rememberConversations = true
        let mentioning = DataFlow.rows(all)
            .filter { [$0.what, $0.when, $0.note ?? ""].contains { $0.localizedCaseInsensitiveContains("say yes") } }
            .map(\.id)
        XCTAssertEqual(Set(mentioning), ["deals", "doddyServer"])
        let deals = DataFlow.rows(all).first { $0.id == "deals" }
        XCTAssertEqual(deals?.when, "Only when you say yes to checking this week's leaflets.", "find_deals is a read and still accepts a spoken yes")
        let server = DataFlow.rows(all).first { $0.id == "doddyServer" }
        XCTAssertTrue(server?.what.contains("after you say yes or tap") ?? false)
        XCTAssertTrue(server?.what.contains("only after you tap its card to confirm") ?? false, "drafts, emails and tasks are tap-only")
    }
}
