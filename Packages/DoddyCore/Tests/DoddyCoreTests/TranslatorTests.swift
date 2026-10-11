import DoddyCore
import XCTest

final class TranslatorTests: XCTestCase {
    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.startTranslator, parametersJSON: Data(json.utf8))
    }

    private func lang(_ code: String) -> TranslatorLanguage { TranslatorLanguages.named(code)! }

    private func faceToFace(_ owner: String = "pl", _ other: String? = "es") -> TranslatorSetup {
        TranslatorSetup(kind: .faceToFace, owner: lang(owner), other: other.map(lang))!
    }

    // MARK: Languages

    func testEveryAgentLanguageHasTheTranslatorLines() throws {
        // The same 37 codes the agent speaks (voice-agent/session.json), each with all four lines.
        let session = try JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/session.json"))) as? [String: Any]
        let codes = try XCTUnwrap(session?["languages"] as? [String])
        XCTAssertEqual(codes.count, 37)
        XCTAssertEqual(Set(TranslatorLanguages.all.map(\.code)), Set(codes))
        XCTAssertEqual(TranslatorLanguages.all.count, 37)
        for language in TranslatorLanguages.all {
            for line in [language.nativeName, language.englishName, language.aiLabel, language.hello, language.holdToTalk, language.careful] {
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, language.code)
            }
            // The disclosure names Doddy in every language.
            XCTAssertTrue(language.hello.contains("Doddy"), language.code)
        }
        // No two languages share a disclosure (a copy-paste slip would show the wrong language).
        XCTAssertEqual(Set(TranslatorLanguages.all.map(\.hello)).count, 37)
    }

    func testLanguageCodesAndOwnerDefault() {
        XCTAssertEqual(TranslatorLanguages.named(" ES ")?.code, "es")
        XCTAssertEqual(TranslatorLanguages.named("nb")?.code, "no")
        XCTAssertNil(TranslatorLanguages.named("eu"))
        XCTAssertEqual(TranslatorLanguages.ownerDefault(settingCode: "de", deviceCode: "pl").code, "de")
        XCTAssertEqual(TranslatorLanguages.ownerDefault(settingCode: nil, deviceCode: "pl").code, "pl")
        XCTAssertEqual(TranslatorLanguages.ownerDefault(settingCode: nil, deviceCode: "ja").code, "en")
    }

    // MARK: Tool parsing

    func testParsesThePairAndTheMode() {
        XCTAssertEqual(parse(#"{"their_language":"es","your_language":"pl"}"#),
                       .startTranslator(TranslatorProposal(kind: .faceToFace, yours: lang("pl"), theirs: lang("es"))))
        XCTAssertEqual(parse(#"{"their_language":"it","mode":"listen"}"#),
                       .startTranslator(TranslatorProposal(kind: .listen, yours: nil, theirs: lang("it"))))
        XCTAssertEqual(parse(#"{"their_language":"detect"}"#),
                       .startTranslator(TranslatorProposal(kind: .faceToFace, yours: nil, theirs: nil)))
        XCTAssertEqual(VoiceToolRequest.parse(name: VoiceToolName.stopTranslator, parametersJSON: Data("{}".utf8)), .stopTranslator)
    }

    func testRefusesUnknownOrSameLanguagesAndModes() {
        for json in [#"{}"#, #"{"their_language":"xx"}"#, #"{"their_language":"es","your_language":"es"}"#,
                     #"{"their_language":"es","mode":"both"}"#, #"{"their_language":"es","your_language":"klingon"}"#] {
            guard case .invalid = parse(json) else { return XCTFail("expected invalid for \(json)") }
        }
        // The owner's default can equal their language: no setup, so the app asks again.
        let proposal = TranslatorProposal(kind: .faceToFace, yours: nil, theirs: lang("pl"))
        XCTAssertNil(proposal.setup(ownerDefault: lang("pl")))
        XCTAssertEqual(proposal.setup(ownerDefault: lang("en"))?.pairText, "English ⇄ Polski")
    }

    func testOnlyStopIsAllowedWhileTranslating() {
        XCTAssertTrue(TranslatorPolicy.allows(.stopTranslator))
        let refused: [VoiceToolRequest] = [
            .searchMemories(query: "x"), .saveMemory(text: "x"), .lookupContact(name: "x"), .openMap(place: "x"),
            .startTranslator(TranslatorProposal(kind: .faceToFace, yours: nil, theirs: nil)), .unsupported(name: "x"),
        ]
        for request in refused { XCTAssertFalse(TranslatorPolicy.allows(request), "\(request)") }
        XCTAssertTrue(VoiceToolReply.translatorRefused("search_memories").hasPrefix("refused:"))
        // Nothing about translator mode is written to "What Doddy did".
        XCTAssertNil(ActivityRequest.describe(.stopTranslator, calendar: .current))
        XCTAssertFalse(ConnectionPause.applies(to: .stopTranslator))
    }

    func testStartedReplyCarriesTheDisclosureInTheirLanguage() {
        let reply = VoiceToolReply.translatorStarted(faceToFace())
        XCTAssertTrue(reply.hasPrefix("started:"))
        XCTAssertTrue(reply.contains(lang("es").hello))
        let detect = VoiceToolReply.translatorStarted(faceToFace("pl", nil))
        XCTAssertTrue(detect.contains("let them say something first"))
        let listen = VoiceToolReply.translatorStarted(TranslatorSetup(kind: .listen, owner: lang("pl"), other: lang("it"))!)
        XCTAssertTrue(listen.contains("Say nothing to anyone else"))
    }

    // MARK: Language guess and routing

    func testGuessesBetweenTheTwoLanguages() {
        let pair = [lang("pl"), lang("es")]
        XCTAssertEqual(LanguageGuess.guess("Zawiezie mnie pan na calle Mayor? Muszę być o 15:30.", among: pair)?.code, "pl")
        XCTAssertEqual(LanguageGuess.guess("¿Me lleva a la calle Mayor 12, cerca de la plaza?", among: pair)?.code, "es")
        XCTAssertEqual(LanguageGuess.guess("Здравствуйте, где вокзал?", among: [lang("en"), lang("ru")])?.code, "ru")
        XCTAssertEqual(LanguageGuess.guess("Де вокзал? Дякую.", among: [lang("ru"), lang("uk")])?.code, "uk")
        XCTAssertEqual(LanguageGuess.guess("Πού είναι ο σταθμός;", among: [lang("de"), lang("el")])?.code, "el")
        XCTAssertNil(LanguageGuess.guess("OK", among: pair))
    }

    func testRoutesByTheTranslationsLanguage() {
        var router = TranslatorRouter(setup: faceToFace())
        // The disclosure, in Spanish: to them.
        XCTAssertEqual(router.route(agentLine: lang("es").hello, after: nil), .translation(.toOther))
        XCTAssertEqual(router.route(agentLine: "¿Me lleva a la calle Mayor 12? Necesito estar a las 15:30.",
                                    after: "Zawiezie mnie pan na calle Mayor 12? Muszę być o 15:30."), .translation(.toOther))
        XCTAssertEqual(router.route(agentLine: "Tak, to dwadzieścia minut. Kosztuje 18 euro.",
                                    after: "Sí, son veinte minutos. Cuesta 18 euros."), .translation(.toOwner))
    }

    func testFallsBackToWhatWasSaidThenTheHeldSideThenTakingTurns() {
        var router = TranslatorRouter(setup: faceToFace())
        // The translation is unreadable ("OK"), what was said is Polish: it went to them.
        XCTAssertEqual(router.route(agentLine: "OK", after: "Proszę, gdzie jest dworzec?"), .translation(.toOther))
        // Nothing readable, the owner held "I'm speaking": it went to them.
        XCTAssertEqual(router.route(agentLine: "OK", after: "OK", held: .toOwner), .translation(.toOther))
        // Nothing at all: the opposite of the last line.
        XCTAssertEqual(router.route(agentLine: "OK", after: nil), .translation(.toOwner))
    }

    func testDoddyAtTheStartIsAQuietWord() {
        var router = TranslatorRouter(setup: faceToFace())
        XCTAssertEqual(router.route(agentLine: "Powiedz: „¿Podría ir más despacio?”", after: "Doddy, jak poprosić, żeby jechał wolniej?"), .aside)
        XCTAssertEqual(router.route(agentLine: "x", after: "Hej Doddy, co znaczy despacio?"), .aside)
        XCTAssertFalse(TranslatorRouter.isAside("Mój kolega Doddy mówi, że jest blisko"))
    }

    func testDoddyFromTheOtherPersonIsNotAQuietWord() {
        var router = TranslatorRouter(setup: faceToFace())
        // Said in their language: they are speaking to Doddy, so it is translated for the owner.
        XCTAssertEqual(router.route(agentLine: "Doddy, gdzie jest dworzec?", after: "Doddy, ¿dónde está la estación, por favor?"),
                       .translation(.toOwner))
        // Their hold-to-talk button was held.
        XCTAssertNotEqual(router.route(agentLine: "x", after: "Doddy, ok", held: .toOther), .aside)
        XCTAssertEqual(router.route(agentLine: "x", after: "Doddy, ok", held: .toOwner), .aside)
        // In listen mode, the guide naming Doddy in Italian still goes to the owner as a translation.
        var listen = TranslatorRouter(setup: TranslatorSetup(kind: .listen, owner: lang("pl"), other: lang("it"))!)
        XCTAssertEqual(listen.route(agentLine: "Doddy, to jest kaplica", after: "Doddy, questa è la cappella."), .translation(.toOwner))
        // Their language not known yet: it is still learned from their first line.
        var session = TranslatorSession(setup: faceToFace("pl", nil), startedAt: Date())
        session.heard("Doddy, ¿dónde está la estación, por favor?")
        XCTAssertEqual(session.setup.other, lang("es"))
    }

    func testListenOnlyGoesToTheOwner() {
        var router = TranslatorRouter(setup: TranslatorSetup(kind: .listen, owner: lang("pl"), other: lang("it"))!)
        XCTAssertEqual(router.route(agentLine: "Questa cappella", after: "Questa cappella fu dipinta tra il 1508 e il 1512."), .translation(.toOwner))
    }

    func testDetectLearnsTheirLanguage() {
        var session = TranslatorSession(setup: faceToFace("pl", nil), startedAt: Date())
        session.heard("Dzień dobry, proszę na dworzec.")
        XCTAssertNil(session.setup.other)
        session.heard("¿Perdón? ¿Dónde está usted, por favor?")
        XCTAssertEqual(session.setup.other?.code, "es")
    }

    // MARK: Facts, careful mode, session

    func testExactFacts() {
        XCTAssertEqual(ExactFacts.extract("¿Me lleva a la Calle Mayor 12, cerca de la plaza? Necesito estar a las 15:30."),
                       ["Calle Mayor 12", "15:30"])
        XCTAssertEqual(ExactFacts.extract("To kosztuje 18,50 zł albo €4.20, odjazd 9:05."), ["18,50 zł", "€4.20", "9:05"])
        XCTAssertEqual(ExactFacts.extract("Proszę brać 500 mg co 8 h."), ["500 mg", "8 h"])
        XCTAssertEqual(ExactFacts.extract("Call +48 600 100 200 now"), ["+48 600 100 200"])
        XCTAssertEqual(ExactFacts.extract("Nothing exact here."), [])
        XCTAssertEqual(ExactFacts.extract("1:00 2:00 3:00 4:00 5:00 6:00").count, ExactFacts.limit)
        XCTAssertEqual(ExactFacts.extract("15:30 i jeszcze raz 15:30"), ["15:30"])
    }

    func testCarefulTopics() {
        XCTAssertEqual(CarefulTopics.topic(in: "Tome una pastilla cada ocho horas."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "Muszę iść do lekarza."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "Die Polizei kommt gleich."), .law)
        XCTAssertEqual(CarefulTopics.topic(in: "Потрібен кредит у банку"), .money)
        XCTAssertNil(CarefulTopics.topic(in: "Is this fine?"))
        XCTAssertNil(CarefulTopics.topic(in: "¿Me lleva a la plaza?"))
    }

    func testCarefulTopicsSkipEverydayLookalikes() {
        XCTAssertNil(CarefulTopics.topic(in: "I speak Polish."))
        XCTAssertNil(CarefulTopics.topic(in: "What is your refund policy?"))
        XCTAssertNil(CarefulTopics.topic(in: "Another pillow, please."))
        XCTAssertEqual(CarefulTopics.topic(in: "Take two pills."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "Ring polisen nu."), .law)
        XCTAssertEqual(CarefulTopics.topic(in: "Zavolejte policie."), .law)
    }

    func testSessionKeepsTurnsCarefulModeAndTheFiveMinuteSummary() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var session = TranslatorSession(setup: faceToFace(), startedAt: start)
        session.said(lang("es").hello)
        session.heard("(app) say the disclosure now")
        session.heard("Muszę do lekarza na 15:30.")
        let turn = try XCTUnwrap(session.said("Tengo que ir al médico a las 15:30."))
        XCTAssertEqual(turn.original, "Muszę do lekarza na 15:30.")
        XCTAssertEqual(turn.route, .translation(.toOther))
        XCTAssertEqual(turn.facts, ["15:30"])
        XCTAssertEqual(session.careful, .health)
        // Careful mode stays on.
        session.heard("Dobrze.")
        session.said("Bien.")
        XCTAssertEqual(session.careful, .health)
        XCTAssertEqual(session.latest(.toOther)?.text, "Bien.")

        let summary = session.summary(endedAt: start.addingTimeInterval(6 * 60))
        XCTAssertEqual(summary.headline, "3 turns · Polski ⇄ Español · 6 min")
        XCTAssertTrue(summary.transcript.contains("Tengo que ir al médico a las 15:30."))
        XCTAssertFalse(summary.transcript.contains("(app)"))
        XCTAssertTrue(summary.isAvailable(at: summary.endedAt.addingTimeInterval(4 * 60 + 59)))
        XCTAssertFalse(summary.isAvailable(at: summary.endedAt.addingTimeInterval(5 * 60)))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(summary.factsNote(calendar: utc), "From a translated conversation (Polski ⇄ Español, 2027-01-15): 15:30")
        // A Buddhist phone calendar still gets the Gregorian date, not 2570.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc.timeZone
        XCTAssertEqual(summary.factsNote(calendar: buddhist), summary.factsNote(calendar: utc))
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}

extension TranslatorTests {
    func testTranslatorStartVariable() {
        XCTAssertEqual(TranslatorPrompt.render(nil), "none")
        let setup = TranslatorSetup(kind: .faceToFace, owner: TranslatorLanguages.named("pl")!, other: TranslatorLanguages.named("es"))!
        let text = TranslatorPrompt.render(setup)
        XCTAssertTrue(text.hasPrefix("Translator mode is on from the start: face to face."))
        XCTAssertTrue(text.contains(TranslatorLanguages.named("es")!.hello))
    }
}

extension TranslatorTests {
    func testWhatLeavesThisIPhoneListsTheTranslator() throws {
        let state = DataFlowState(
            rememberConversations: true, shareProfileWithVoice: false, tokenServerSet: false, connectionsOn: [],
            pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: false)
        let row = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "translator" })
        XCTAssertTrue(row.what.contains("other person's voice"))
        XCTAssertTrue(row.note?.contains("Listen only hears whoever is near you") == true)
    }

    /// The native-review sheet is made from the code; regenerate it with
    /// `DODDY_WRITE_REVIEW_SHEET=1 swift test --filter testReviewSheetMatchesTheCode`.
    func testReviewSheetMatchesTheCode() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/implementation/TRANSLATOR_LANGUAGE_REVIEW.md")
        let sheet = TranslatorReviewSheet.markdown()
        if ProcessInfo.processInfo.environment["DODDY_WRITE_REVIEW_SHEET"] == "1" {
            try sheet.write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), sheet)
        XCTAssertEqual(sheet.components(separatedBy: "\n").filter { $0.hasPrefix("| ") && !$0.hasPrefix("| Code") }.count,
                       TranslatorLanguages.all.count - 1)
    }
}
