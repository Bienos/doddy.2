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
        // The same 89 codes the agent speaks (voice-agent/session.json), each with all four lines:
        // 37 European (ADR-212) and, since 12 Nov 2026, every other language ElevenLabs accepts as a preset.
        let session = try JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/session.json"))) as? [String: Any]
        let codes = try XCTUnwrap(session?["languages"] as? [String])
        XCTAssertEqual(codes.count, 89)
        XCTAssertEqual(Set(TranslatorLanguages.all.map(\.code)), Set(codes))
        XCTAssertEqual(TranslatorLanguages.all.count, 89)
        XCTAssertEqual(TranslatorLanguages.count, 89)
        // Each agent language greets with the app's opening line or its own first message.
        let firstMessages = try XCTUnwrap(session?["first_message"] as? [String: String])
        XCTAssertEqual(Set(firstMessages.keys), Set(codes))
        for language in TranslatorLanguages.all {
            for line in [language.nativeName, language.englishName, language.aiLabel, language.hello, language.holdToTalk, language.careful] {
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, language.code)
            }
            // The disclosure names Doddy in every language.
            XCTAssertTrue(language.hello.contains("Doddy"), language.code)
        }
        // No two languages share a disclosure (a copy-paste slip would show the wrong language).
        XCTAssertEqual(Set(TranslatorLanguages.all.map(\.hello)).count, 89)
        // The 52 added on 12 Nov 2026 share no line with any other language (a copy-paste slip would
        // show Indonesian to a Malay speaker). Croatian, Bosnian and Serbian rightly share a few.
        let added = Set(Self.addedOn12Nov)
        for language in TranslatorLanguages.all where added.contains(language.code) {
            for other in TranslatorLanguages.all where other != language {
                for keyPath in [\TranslatorLanguage.aiLabel, \.holdToTalk, \.careful, \.nativeName] {
                    XCTAssertNotEqual(language[keyPath: keyPath], other[keyPath: keyPath], "\(language.code) and \(other.code)")
                }
            }
        }
    }

    /// The languages added on 12 Nov 2026: 16 first, then every other one ElevenLabs accepts as a preset.
    static let addedOn12Nov = [
        "ar", "zh", "ja", "ko", "hi", "bn", "ur", "fa", "he", "vi", "th", "id", "ms", "fil", "sw", "ka",
        "af", "hy", "as", "ast", "az", "my", "yue", "gu", "ha", "jv", "kn", "kk", "ky",
        "ml", "mi", "mr", "mn", "ne", "oc", "or", "ps", "pa", "sd", "so", "tg", "ta", "te", "uz", "yo",
        "am", "lo", "lg", "sn", "ckb", "wo", "zu",
    ]

    func testEachNewLanguageIsToldFromEnglishAndPolishByItsOwnLines() {
        // Their disclosure is recognised as their language next to the two the owner usually speaks,
        // so their half gets their lines and the owner's half gets the owner's.
        for code in Self.addedOn12Nov {
            let language = lang(code)
            XCTAssertEqual(LanguageGuess.guess(language.hello, among: [language, lang("en")]), language, code)
            XCTAssertEqual(LanguageGuess.guess(language.hello, among: [lang("pl"), language]), language, code)
        }
        // Right to left: their half is laid out from the right.
        XCTAssertEqual(Set(TranslatorLanguages.all.filter(\.isRightToLeft).map(\.code)), ["ar", "ckb", "fa", "he", "ps", "sd", "ur"])
        // ElevenLabs refused these as presets on 12 Nov 2026, so the translator doesn't offer them.
        for refused in ["ln", "ceb", "ny", "eu", "sq"] { XCTAssertNil(TranslatorLanguages.named(refused), refused) }
        XCTAssertFalse(lang("pl").isRightToLeft)
    }

    func testLanguageCodesAndOwnerDefault() {
        XCTAssertEqual(TranslatorLanguages.named(" ES ")?.code, "es")
        XCTAssertEqual(TranslatorLanguages.named("nb")?.code, "no")
        XCTAssertNil(TranslatorLanguages.named("eu"))
        XCTAssertNil(TranslatorLanguages.named("sq"))
        XCTAssertEqual(TranslatorLanguages.ownerDefault(settingCode: "de", deviceCode: "pl").code, "de")
        XCTAssertEqual(TranslatorLanguages.ownerDefault(settingCode: nil, deviceCode: "pl").code, "pl")
        // An iPhone in Japanese now starts the translator in Japanese; one in Basque still in English.
        XCTAssertEqual(TranslatorLanguages.ownerDefault(settingCode: nil, deviceCode: "ja").code, "ja")
        XCTAssertEqual(TranslatorLanguages.ownerDefault(settingCode: nil, deviceCode: "eu").code, "en")
        // Older or other codes for the same language.
        XCTAssertEqual(TranslatorLanguages.named("iw")?.code, "he")
        XCTAssertEqual(TranslatorLanguages.named("in")?.code, "id")
        XCTAssertEqual(TranslatorLanguages.named("TL")?.code, "fil")
        XCTAssertEqual(TranslatorLanguages.named("cmn")?.code, "zh")
        XCTAssertEqual(TranslatorLanguages.named("fil")?.label, "Filipino")
        XCTAssertEqual(TranslatorLanguages.named("ja")?.label, "日本語 (Japanese)")
        XCTAssertEqual(TranslatorLanguages.named("YUE")?.code, "yue")
        XCTAssertEqual(TranslatorLanguages.named("ast")?.label, "Asturianu (Asturian)")
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

    func testOnlyStopAndStartAreAllowedWhileTranslating() {
        XCTAssertTrue(TranslatorPolicy.allows(.stopTranslator))
        // A second start_translator is answered "already on" (9 Nov 2026: a refusal made Doddy talk about
        // it in English instead of translating).
        XCTAssertTrue(TranslatorPolicy.allows(.startTranslator(TranslatorProposal(kind: .faceToFace, yours: nil, theirs: nil))))
        let refused: [VoiceToolRequest] = [
            .searchMemories(query: "x"), .saveMemory(text: "x"), .lookupContact(name: "x"), .openMap(place: "x"),
            .unsupported(name: "x"),
        ]
        for request in refused { XCTAssertFalse(TranslatorPolicy.allows(request), "\(request)") }
        XCTAssertTrue(VoiceToolReply.translatorRefused("search_memories").hasPrefix("refused:"))
        // After a refusal the line is translated, not answered or asked about (12 Nov 2026 live checks).
        XCTAssertTrue(VoiceToolReply.translatorRefused("find_places").contains("translate it now into the other language and say nothing else"))
        // Nothing about translator mode is written to "What Doddy did".
        XCTAssertNil(ActivityRequest.describe(.stopTranslator, calendar: .current))
        XCTAssertFalse(ConnectionPause.applies(to: .stopTranslator))
    }

    func testStartedReplyCarriesTheDisclosureInTheirLanguage() {
        let reply = VoiceToolReply.translatorStarted(faceToFace())
        XCTAssertTrue(reply.hasPrefix("started:"))
        // Owner, 9 Nov 2026: nothing spoken of his own, no disclosure and no "what should I translate?".
        XCTAssertFalse(reply.contains(lang("es").hello))
        XCTAssertTrue(reply.contains("Say nothing of your own: no greeting, no AI translator disclosure"))
        XCTAssertTrue(reply.contains("Polish into Spanish, Spanish into Polish"))
        let detect = VoiceToolReply.translatorStarted(faceToFace("pl", nil))
        XCTAssertTrue(detect.contains("Wait in silence until someone speaks"))
        XCTAssertTrue(detect.contains("translate what they said into Polish"))
        XCTAssertTrue(detect.contains("until you have heard it, into English"))
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

    func testDoddyAtTheStartIsTranslatedLikeEverythingElse() {
        // ADR-574: the owner opened with "Yo, Doddy, …" and got answers instead of translations.
        var router = TranslatorRouter(setup: faceToFace())
        XCTAssertFalse(TranslatorRouter.isAside("Yo, Doddy. I want to tell you something."))
        XCTAssertFalse(TranslatorRouter.isAside("Doddy, jak poprosić, żeby jechał wolniej?"))
        XCTAssertEqual(router.route(agentLine: "¿Cómo le pido que vaya más despacio?", after: "Doddy, jak poprosić, żeby jechał wolniej?"),
                       .translation(.toOther))
        XCTAssertNotEqual(router.route(agentLine: "x", after: "Hej Doddy, co znaczy despacio?"), .aside)
    }

    func testDoddyFromTheOtherPersonIsNotAQuietWord() {
        var router = TranslatorRouter(setup: faceToFace())
        // Said in their language: they are speaking to Doddy, so it is translated for the owner.
        XCTAssertEqual(router.route(agentLine: "Doddy, gdzie jest dworzec?", after: "Doddy, ¿dónde está la estación, por favor?"),
                       .translation(.toOwner))
        // Their hold-to-talk button was held.
        XCTAssertNotEqual(router.route(agentLine: "x", after: "Doddy, ok", held: .toOther), .aside)
        XCTAssertNotEqual(router.route(agentLine: "x", after: "Doddy, ok", held: .toOwner), .aside)
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

    func testGuessesTheNewScripts() {
        let arabicScript = [lang("ar"), lang("fa"), lang("ur")]
        XCTAssertEqual(LanguageGuess.guess("أين محطة القطار؟ شكراً.", among: arabicScript)?.code, "ar")
        XCTAssertEqual(LanguageGuess.guess("ایستگاه قطار کجاست؟ خیلی ممنون.", among: arabicScript)?.code, "fa")
        XCTAssertEqual(LanguageGuess.guess("ریلوے اسٹیشن کہاں ہے؟ بہت شکریہ۔", among: arabicScript)?.code, "ur")
        // Kana means Japanese; kanji alone, with Chinese-only characters, means Chinese.
        XCTAssertEqual(LanguageGuess.guess("駅はどこですか？", among: [lang("zh"), lang("ja")])?.code, "ja")
        XCTAssertEqual(LanguageGuess.guess("请问火车站在哪里？谢谢你。", among: [lang("zh"), lang("ja")])?.code, "zh")
        XCTAssertEqual(LanguageGuess.guess("기차역이 어디예요?", among: [lang("pl"), lang("ko")])?.code, "ko")
        XCTAssertEqual(LanguageGuess.guess("איפה תחנת הרכבת?", among: [lang("en"), lang("he")])?.code, "he")
        XCTAssertEqual(LanguageGuess.guess("रेलवे स्टेशन कहाँ है?", among: [lang("en"), lang("hi"), lang("bn")])?.code, "hi")
        XCTAssertEqual(LanguageGuess.guess("สถานีรถไฟอยู่ที่ไหน", among: [lang("pl"), lang("th")])?.code, "th")
        XCTAssertEqual(LanguageGuess.guess("სად არის სადგური?", among: [lang("ru"), lang("ka")])?.code, "ka")
        XCTAssertEqual(LanguageGuess.guess("Ga tàu ở đâu? Cảm ơn bạn.", among: [lang("pl"), lang("vi"), lang("ro")])?.code, "vi")
        XCTAssertEqual(LanguageGuess.guess("Stasiun kereta di mana? Bisa tolong saya?", among: [lang("id"), lang("ms")])?.code, "id")
        XCTAssertEqual(LanguageGuess.guess("Stesen kereta api di mana? Boleh tolong saya?", among: [lang("id"), lang("ms")])?.code, "ms")
        XCTAssertEqual(LanguageGuess.guess("Saan ang istasyon ng tren? Salamat po.", among: [lang("en"), lang("fil")])?.code, "fil")
        XCTAssertEqual(LanguageGuess.guess("Kituo cha treni kiko wapi? Asante sana.", among: [lang("en"), lang("sw")])?.code, "sw")
        // The second group: a script of its own, or letters and words within a shared one.
        XCTAssertEqual(LanguageGuess.guess("Որտե՞ղ է կայարանը", among: [lang("ru"), lang("hy")])?.code, "hy")
        XCTAssertEqual(LanguageGuess.guess("ரயில் நிலையம் எங்கே?", among: [lang("hi"), lang("ta"), lang("te")])?.code, "ta")
        XCTAssertEqual(LanguageGuess.guess("Вокзал қайда? Рахмет.", among: [lang("ru"), lang("kk"), lang("ky")])?.code, "kk")
        XCTAssertEqual(LanguageGuess.guess("Вокзал куҷо аст? Ташаккур.", among: [lang("ru"), lang("kk"), lang("tg")])?.code, "tg")
        XCTAssertEqual(LanguageGuess.guess("火車站喺邊度？唔該。", among: [lang("zh"), lang("yue"), lang("ja")])?.code, "yue")
        XCTAssertEqual(LanguageGuess.guess("请问火车站在哪里？谢谢。", among: [lang("zh"), lang("yue")])?.code, "zh")
        XCTAssertEqual(LanguageGuess.guess("سټېشن چېرته دی؟ مننه.", among: [lang("fa"), lang("ur"), lang("ps")])?.code, "ps")
        XCTAssertEqual(LanguageGuess.guess("ৰেল ষ্টেচন ক'ত আছে?", among: [lang("bn"), lang("as")])?.code, "as")
        XCTAssertEqual(LanguageGuess.guess("রেল স্টেশন কোথায়?", among: [lang("bn"), lang("as")])?.code, "bn")
        XCTAssertEqual(LanguageGuess.guess("स्टेशन कुठे आहे?", among: [lang("hi"), lang("mr"), lang("ne")])?.code, "mr")
        XCTAssertEqual(LanguageGuess.guess("Stansiya haradadır? Təşəkkür edirəm.", among: [lang("tr"), lang("az")])?.code, "az")
        XCTAssertEqual(LanguageGuess.guess("Istasyon nerede? Teşekkür ederim.", among: [lang("tr"), lang("az")])?.code, "tr")
        XCTAssertEqual(LanguageGuess.guess("Waar is die stasie? Ek soek dit, baie dankie.", among: [lang("nl"), lang("af")])?.code, "af")
        // European lines are still read as before with all 85 in play.
        XCTAssertEqual(LanguageGuess.guess("Здравствуйте, где вокзал?", among: TranslatorLanguages.all)?.code, "ru")
        XCTAssertEqual(LanguageGuess.guess("Πού είναι ο σταθμός;", among: TranslatorLanguages.all)?.code, "el")
    }

    func testDetectLearnsANewLanguageAndRoutesBothWays() {
        // A Polish owner and a Japanese stranger, their language left to detect.
        var session = TranslatorSession(setup: faceToFace("pl", nil), startedAt: Date())
        // The owner's Polish ("po", a Filipino word too) is never taken for theirs.
        session.heard("Idę po zakupy, potem na dworzec.")
        XCTAssertNil(session.setup.other)
        session.heard("すみません、駅はどこですか？")
        XCTAssertEqual(session.setup.other?.code, "ja")
        XCTAssertEqual(session.said("Przepraszam, gdzie jest dworzec?")?.route, .translation(.toOwner))
        session.heard("Prosto, potem w lewo.")
        XCTAssertEqual(session.said("まっすぐ行って、それから左です。")?.route, .translation(.toOther))
        // Arabic, set from the start.
        var router = TranslatorRouter(setup: faceToFace("en", "ar"))
        XCTAssertEqual(router.route(agentLine: "من فضلك، أين محطة القطار؟", after: "Excuse me, where is the train station?"),
                       .translation(.toOther))
        XCTAssertEqual(router.route(agentLine: "Go straight, then turn left.", after: "امشِ مباشرة ثم انعطف يساراً."),
                       .translation(.toOwner))
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

    func testASentencesFirstWordAndANumberIsNotAnAddress() {
        XCTAssertEqual(ExactFacts.extract("At 15 we leave."), [])
        XCTAssertEqual(ExactFacts.extract("Okay. Wait 10 seconds."), [])
        XCTAssertEqual(ExactFacts.extract("Jedziemy na Piotrkowska 120, dobrze?"), ["Piotrkowska 120"])
        XCTAssertEqual(ExactFacts.extract("Rue de Rivoli 99, s'il vous plaît."), ["Rue de Rivoli 99"])
        XCTAssertEqual(ExactFacts.extract("Proszę na ul. Długa 5a."), ["ul. Długa 5a"])
        XCTAssertEqual(ExactFacts.extract("Św. Marcin 12, proszę."), ["Św. Marcin 12"])
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

    func testCarefulTopicsInTheNewLanguages() {
        // Words joined to the next with no space, or with "the" in front, are still heard.
        XCTAssertEqual(CarefulTopics.topic(in: "我需要去医院。"), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "警察を呼んでください。"), .law)
        XCTAssertEqual(CarefulTopics.topic(in: "ต้องไปธนาคารก่อน"), .money)
        XCTAssertEqual(CarefulTopics.topic(in: "أين المستشفى؟"), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "צריך עורך דין"), .law)
        XCTAssertEqual(CarefulTopics.topic(in: "Tôi cần gặp bác sĩ."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "Saya perlu ke rumah sakit."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "경찰을 불러 주세요."), .law)
        XCTAssertEqual(CarefulTopics.topic(in: "मुझे डॉक्टर चाहिए।"), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "Nahitaji mkopo wa benki."), .money)
        XCTAssertEqual(CarefulTopics.topic(in: "Kailangan ko ng gamot."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "ექიმი მჭირდება."), .health)
        // Everyday lines in them stay plain: a street in Hebrew, a shrine in Thai, "dawać" in Polish.
        XCTAssertNil(CarefulTopics.topic(in: "איפה הרחוב הזה?"))
        XCTAssertNil(CarefulTopics.topic(in: "ศาลเจ้าอยู่ที่ไหน"))
        XCTAssertNil(CarefulTopics.topic(in: "Proszę mi dawać znać."))
        XCTAssertNil(CarefulTopics.topic(in: "Un albergo molto ospitale."))
        XCTAssertNil(CarefulTopics.topic(in: "駅はどこですか？"))
        // The second group.
        XCTAssertEqual(CarefulTopics.topic(in: "எனக்கு மருத்துவர் வேண்டும்."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "Polisə zəng edin, vəkil lazımdır."), .law)
        XCTAssertEqual(CarefulTopics.topic(in: "Банктен несие алғым келеді."), .money)
        XCTAssertEqual(CarefulTopics.topic(in: "Ek moet hospitaal toe gaan."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "Waxaan u baahanahay dhakhtar."), .health)
        XCTAssertEqual(CarefulTopics.topic(in: "ဆေးရုံ ဘယ်မှာလဲ"), .health)
        XCTAssertNil(CarefulTopics.topic(in: "Thank you for your loyalty."))
        XCTAssertNil(CarefulTopics.topic(in: "Дайте, пожалуйста, банку воды."))
    }

    func testACorrectedLineKeepsTheFactsOfWhatWasSaid() throws {
        var session = TranslatorSession(setup: faceToFace(), startedAt: Date())
        session.heard("Pociąg jest o 15:30, peron 4, bilet 18,50 zł.")
        let turn = try XCTUnwrap(session.said("El tren sale a las 15:30."))
        XCTAssertEqual(turn.facts, ["15:30", "18,50 zł"])
        session.correct("El tren sale a las 15:30.", to: "El tren sale a las 15:30, andén 4.")
        XCTAssertEqual(session.turns.last?.text, "El tren sale a las 15:30, andén 4.")
        XCTAssertEqual(session.turns.last?.facts, ["15:30", "18,50 zł"])
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
        // 12 Nov 2026 live checks: the interpreter rule comes first, with the question the agent used to answer.
        XCTAssertTrue(text.hasPrefix("YOU ARE ONLY AN INTERPRETER NOW."))
        XCTAssertTrue(text.contains("you say that same question in Spanish and nothing else"))
        XCTAssertTrue(text.contains("Translator mode is on from the start: face to face."))
        XCTAssertTrue(text.contains("you call no tool"))
        XCTAssertTrue(text.contains("Spanish always becomes Polish, Polish always becomes Spanish"))
        XCTAssertTrue(text.contains("If you called a tool anyway and the app refused it"))
        // Owner, 9 Nov 2026: silent start. No spoken disclosure; their half of the screen shows the AI label.
        XCTAssertFalse(text.contains(TranslatorLanguages.named("es")!.hello))
        XCTAssertTrue(text.contains("no AI translator disclosure, no question about what to translate"))
        XCTAssertTrue(text.contains("Wait in silence until someone speaks"))
        // The mode is already on: no second start, both directions named.
        XCTAssertTrue(text.contains("never call start_translator"))
        XCTAssertTrue(text.contains("Polish into Spanish, Spanish into Polish"))
        XCTAssertFalse(text.contains("When the app says so"))
    }

    func testTranslatorOpensInSilence() {
        // Owner, 9 Nov 2026 ("niech nic nie mówi"): no first message at all, never "Jestem. Co słychać?".
        let pl = TranslatorLanguages.named("pl")!, es = TranslatorLanguages.named("es")!
        for setup in [TranslatorSetup(kind: .faceToFace, owner: pl, other: es)!, TranslatorSetup(kind: .faceToFace, owner: pl, other: nil)!,
                      TranslatorSetup(kind: .listen, owner: pl, other: es)!] {
            XCTAssertEqual(TranslatorPrompt.openingLine(setup), "")
        }
    }

    func testUnknownLanguageStillTranslatesBothWays() {
        let pl = TranslatorLanguages.named("pl")!
        let text = TranslatorPrompt.render(TranslatorSetup(kind: .faceToFace, owner: pl, other: nil)!)
        XCTAssertTrue(text.contains("the first language you hear that isn't Polish is theirs"))
        XCTAssertTrue(text.contains("translate what they said into Polish"))
        XCTAssertTrue(text.contains("until you have heard it, into English."))
        XCTAssertTrue(text.contains("that same question in the other person's language"))
        XCTAssertFalse(text.contains("say the AI translator disclosure once"))
        // An English speaker's fallback is Polish, never English into English.
        let en = TranslatorPrompt.render(TranslatorSetup(kind: .faceToFace, owner: TranslatorLanguages.english, other: nil)!)
        XCTAssertTrue(en.contains("until you have heard it, into Polish"))
    }

    func testASecondStartIsAnsweredAlreadyOn() {
        let setup = TranslatorSetup(kind: .listen, owner: TranslatorLanguages.named("pl")!, other: TranslatorLanguages.named("de"))!
        let reply = VoiceToolReply.translatorAlreadyOn(setup)
        XCTAssertTrue(reply.hasPrefix("started: translator mode is already on"))
        XCTAssertTrue(reply.contains("don't call start_translator again"))
        XCTAssertTrue(reply.contains("into Polish for the user"))
        // Not a refusal. (Since 12 Nov the rules in it say what to do "if the app refused" a tool.)
        XCTAssertFalse(reply.hasPrefix("refused"))
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
