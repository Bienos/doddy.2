import Foundation
import XCTest
@testable import DoddyCore

/// ADR-716: a task handed over is read by Doddy's server, whose researcher opens any link in the
/// text. The phone refuses a link before the card, tells the agent to send the task again without
/// one, and shows the user whose each text is, in full. A spoken yes can no longer start a task.
final class ErrandLinkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func draft(words: String = "znajdź tani hotel w Rzymie", brief: String = "Hotel w Rzymie, tanio.", title: String = "Rzym",
                       kind: ErrandKind? = nil, priorities: [String] = []) -> ErrandDraft {
        ErrandDraft(words: words, brief: brief, title: title, kind: kind, priorities: priorities)
    }

    // MARK: What is a link

    /// Spellings that must be refused, in any field.
    private let links = [
        // A scheme, in any case.
        "https://example.com/oferta", "http://example.com", "HTTPS://EXAMPLE.COM/X", "HtTp://example.com", "ftp://example.com/file",
        "file:///etc/passwd", "ws://example.com", "hxxps://example.com/x", "Zobacz https://example.com/x i powiedz",
        // www.
        "www.example.com", "WWW.EXAMPLE.COM", "www2.example.com", "sprawdź www.sklep.pl",
        // A site with a path, a query or a fragment and no scheme.
        "example.com/oferta", "Example.COM/Oferta", "shop.pl/produkt/123", "sub.example.co.uk/a", "example.com:8080/x",
        "user@example.com/x", "example.com?x=1", "example.com#top", "example.com/", "zażółć.pl/x", "sprawdź na example.com/oferta czy taniej",
        "allegro.pl/o", "xn--p1ai.xn--80asehdb/x",
        // An IP address, with or without a path.
        "192.168.0.1/admin", "10.0.0.1:8080/x", "169.254.169.254", "127.0.0.1", "0x7f.0.0.1/x", "[::1]/x", "[2001:db8::1]:8080/x", "[::1]",
        // Script and data addresses.
        "javascript:alert(1)", "JavaScript:void(0)", "vbscript:x", "data:text/html,<b>x</b>", "data:text/plain;base64,AAAA", "DATA:image/png,x",
        // A markdown link.
        "[kliknij tutaj](https://example.com)", "[x](example.com)", "[x](/sciezka)", "![obraz](http://x/y.png)", "[x](mailto:a@b.c)",
        // Escaped, once or twice, and with HTML entities.
        "https%3A%2F%2Fexample.com%2Fx", "example.com%2Fpath", "example.com%2fpath", "example.com%252Fpath", "example.com%25252Fpath",
        "https:%2F%2Fexample.com", "example.com&sol;path", "example.com&#47;path", "example.com&#x2f;path", "h&#116;tp://example.com",
        "example.com%5Cpath",
        // Full-width letters, invisible characters, other dots and slashes, a backslash.
        "ｈｔｔｐｓ：／／ｅｘａｍｐｌｅ．ｃｏｍ／ｘ", "ht\u{200B}tps://example.com", "exam\u{200B}ple.com/x", "ex\u{00AD}ample.com/x",
        "example。com/x", "example\u{FF61}com/x", "example.com\u{2044}x", "https:\\\\example.com\\x",
        // Written out so a person can still read it.
        "example[.]com/x", "example(.)com/x", "example[dot]com/x", "hxxps[:]//example[.]com", "example.com[/]x",
    ]

    /// Text that must stay allowed: a bare site name, numbers, fractions, dates, abbreviations.
    private let notLinks = [
        "allegro.pl", "Allegro.pl i OLX.pl", "wizzair.com", "Sprawdź ceny na allegro.pl, olx.pl oraz ceneo.pl.", "Czy to jest wizzair.com? Albo ryanair.com?",
        "pl.wikipedia.org", "jan@example.com", "e-mail: jan@example.com", "example.com.", "example.com:8080",
        "3.5/5", "10/12", "12.11/19.11", "389 zł / os.", "zł/szt", "km/h", "24/7", "and/or", "tanio/blisko", "TCP/IP", "Wi-Fi/Bluetooth",
        "5.1/7.1", "iOS 17.2/18", "cena 1.299,00 zł/szt.", "12.11.2026", "1.2.3.4.5", "iOS 17.4.1", "10.12.2026.14",
        "data: 12 listopada", "Data: 12.11, godzina: 8", "metadata: nic", "JavaScript developer", "javascript: the good parts",
        "[12:30] lot", "[1] przypis", "[x] (nie)", "zobacz [1] (str. 5)", "Hotele do 2000 zł, 7 dni, wylot z Warszawy",
        "sprawdź loty i hotele do 2000 zł", "Zażółć gęślą jaźń", "",
        // What people say when they hand a task over, in Polish and English.
        "chcę jechać do Rzymu w przyszłym miesiącu na 7 dni, sprawdź loty i hotele do 2000 zł",
        "Znajdź cichą zmywarkę 45 cm do 2500 zł, np. Bosch/Siemens/Electrolux", "godz. 8.30/9.00", "Kup bilet Warszawa–Kraków, 12.11, ok. 9:00, 1. klasa",
        "tel. 600-100-200", "ul. Marszałkowska 12/14 m. 5", "5.5/10 w skali", "wersja 2.1.3", "wizzair.com, ryanair.com, lot.com", "jan.kowalski@gmail.com",
        "bez www", "zużycie 1.5l/100km", "S.A./sp. z o.o.", "12.11.2026/13.11.2026", "Hotel…tanio/blisko", "perfumy, biżuteria/szal?",
        "Flights from Warsaw, 1 person, any 7 days next month; hotels under 2000 zł in total", "e.g. flights/hotels or trains", "Dishwasher 45 cm, 44 dB, A/B energy class",
    ]

    func testEverySpellingOfALinkIsRefused() {
        for text in links { XCTAssertTrue(LinkShape.isIn(text), "should be a link: \(text)") }
    }

    func testPlainTextAndBareSiteNamesAreNotLinks() {
        for text in notLinks { XCTAssertFalse(LinkShape.isIn(text), "should not be a link: \(text)") }
    }

    func testEveryPatternCompiled() {
        // A pattern that failed to compile would silently check nothing.
        XCTAssertEqual(LinkShape.patterns.count, LinkShape.sources.count)
        XCTAssertGreaterThanOrEqual(LinkShape.patterns.count, 9)
    }

    // MARK: The draft

    func testALinkInAnyTextTheServerGetsIsAnIssue() {
        XCTAssertEqual(draft().validationIssues(), [])
        XCTAssertEqual(draft(words: "sprawdź https://example.com/x").validationIssues(), [.containsLink])
        XCTAssertEqual(draft(brief: "Zobacz www.example.com").validationIssues(), [.containsLink])
        XCTAssertEqual(draft(title: "example.com/x").validationIssues(), [.containsLink])
        XCTAssertEqual(draft(kind: .shopping, priorities: ["Cisza", "example.com/x"]).validationIssues(), [.containsLink])
        // Reported once, however many texts carry one.
        XCTAssertEqual(draft(words: "https://a.pl/x", brief: "https://b.pl/x", title: "https://c.pl/x").validationIssues(), [.containsLink])
        // Bare site names stay.
        XCTAssertEqual(draft(words: "porównaj ceny na allegro.pl i olx.pl", brief: "Ceny na allegro.pl i olx.pl.").validationIssues(), [])
        XCTAssertFalse(draft(words: "ceneo.pl").containsLink)
        XCTAssertTrue(draft(words: "ceneo.pl/produkt").containsLink)
        XCTAssertTrue(draft().isValid)
        XCTAssertFalse(draft(words: "https://example.com").isValid)
    }

    func testTheAgentIsToldToSendItAgainWithoutLinks() {
        let name = VoiceToolName.handOverErrand
        func parse(_ words: String) -> VoiceToolRequest {
            let json = try! JSONSerialization.data(withJSONObject: ["words": words, "brief": "Hotel.", "title": "Rzym"])
            return VoiceToolRequest.parse(name: name, parametersJSON: json)
        }
        guard case .invalid(_, let reason) = parse("zobacz HTTPS://EXAMPLE.COM/x") else { return XCTFail("a link must not parse") }
        XCTAssertEqual(reason, ErrandDraftIssue.containsLink.reason)
        XCTAssertTrue(reason.contains("send the task again with no link"), reason)
        XCTAssertTrue(reason.contains("allegro.pl"), "a bare site name is fine, and the agent hears so")
        XCTAssertEqual(AskFirst.need(for: parse("https://example.com/x")), .nothingRuns, "nothing is shown or asked")
        // The same task without the link goes through.
        if case .invalid = parse("zobacz allegro.pl") { XCTFail("a bare site name is allowed") }
        // The server's own refusal of a link names the fields; the agent is told what to change.
        let refused = VoiceToolReply.errandNotStarted(ErrandError.invalid(fields: ["words"]))
        XCTAssertTrue(refused.hasPrefix("failed:"), refused)
        XCTAssertTrue(refused.contains("link or web address"), refused)
        XCTAssertTrue(refused.contains("Nothing was done"), refused)
    }

    // MARK: The card says whose each text is, in full

    func testTheCardSaysWhoseEachTextIs() {
        let said = "chcę jechać do Rzymu na 7 dni"
        let card = ErrandAsk.handOverCard(draft(words: said, brief: "Loty i hotel, zakładam wylot z Warszawy.", title: "Rzym, 7 dni"))
        XCTAssertEqual(card.title, "Hand this to Doddy?")
        XCTAssertEqual(card.lines[0], "Your words, as Doddy will pass them on: \u{201C}\(said)\u{201D}")
        XCTAssertEqual(card.lines[1], "Doddy's own note, written by Doddy and not by you: \u{201C}Loty i hotel, zakładam wylot z Warszawy.\u{201D}")
        XCTAssertEqual(card.lines[2], "Title in Tasks, also Doddy's: \u{201C}Rzym, 7 dni\u{201D}")
        XCTAssertTrue(card.lines.contains("Check that the words are what you said. If they aren't, tap No."))
        XCTAssertEqual(card.lines.last, "Nothing is booked, bought or sent.")
        XCTAssertEqual(card.confirmLabel, "Yes, go")
    }

    func testTheCardNeverCutsAText() {
        let long = String(repeating: "ż", count: ErrandDraft.maxWords - 1) + "!"
        let note = String(repeating: "b", count: ErrandDraft.maxBrief - 1) + "?"
        let priorities = ["Cisza", "Cena", "Gwarancja", "Rozmiar", "Kolor"]
        for kind in [nil, ErrandKind.shopping] {
            let card = ErrandAsk.handOverCard(draft(words: long, brief: note, kind: kind, priorities: kind == nil ? [] : priorities))
            XCTAssertTrue(card.lines.contains("Your words, as Doddy will pass them on: \u{201C}\(long)\u{201D}"), "the words are shown whole")
            XCTAssertTrue(card.lines.contains("Doddy's own note, written by Doddy and not by you: \u{201C}\(note)\u{201D}"), "the note is shown whole")
            XCTAssertFalse(card.lines.contains { $0.contains("…") }, "nothing is cut with an ellipsis")
            if kind != nil {
                XCTAssertTrue(card.lines.contains("What matters most, as Doddy heard it, in this order: Cisza, Cena, Gwarancja, Rozmiar, Kolor"))
            }
        }
    }

    // MARK: A spoken yes starts a task again (decision 2026-11-14-spoken-yes-and-fewer-cards), except after outside text

    func testASpokenYesStartsAnErrandUnlessTextFromOutsideIsInTheConversationAndOneTapAlwaysDoes() {
        let request = VoiceToolRequest.handOverErrand(draft())
        let need = AskFirst.need(for: request)
        guard case .yesFirst = need else { return XCTFail("the card takes a yes or a tap, got \(need)") }
        XCTAssertFalse(AskFirst.needsTap(need))

        // The shopping kind of task is the same.
        let shopping = VoiceToolRequest.handOverErrand(draft(kind: .shopping, priorities: ["Cisza"]))
        guard case .yesFirst = AskFirst.need(for: shopping) else { return XCTFail("a shopping task takes a yes too") }

        // ADR-716's worry was a yes to something else. The yes must be only a yes, and the voice controller also
        // wants it a second after the card appeared (`SpokenConfirmation`); a page or an email in the conversation
        // makes it a tap again, because words from there could have asked for the task.
        var afterAPage = OutsideContentSession()
        afterAPage.noteRun(of: "web_search")
        let tapAfterAPage = AskFirst.need(for: request, in: afterAPage)
        guard case .tapFirst = tapAfterAPage else { return XCTFail("after a page only a tap starts a task, got \(tapAfterAPage)") }
        var ledger = AskLedger()
        ledger.asked("c1", request: request, needsTap: AskFirst.needsTap(tapAfterAPage), at: now)
        XCTAssertTrue(ledger.waitingForSpokenYes().isEmpty, "no spoken yes is waited for after outside text")
        for said in ["tak", "Tak, proszę.", "yes", "Yes please", "ok", "okay", "sure", "go ahead", "jasne", "zrób to", "ja", "oui", "sí", "sim", "vale"] {
            XCTAssertEqual(ledger.answer(.userSaid(said), for: "c1", at: now.addingTimeInterval(2)), .stillWaiting, said)
        }
        XCTAssertFalse(ledger.mayRun("c1", request: request, at: now.addingTimeInterval(3)), "no tap: nothing is handed over")

        // Without outside text, the person's own short yes starts exactly this task, once.
        ledger.asked("c0", request: request, needsTap: AskFirst.needsTap(need), at: now)
        XCTAssertEqual(ledger.answer(.userSaid("tak, ale do Paryża"), for: "c0", at: now.addingTimeInterval(2)), .stillWaiting)
        XCTAssertEqual(ledger.answer(.userSaid("tak"), for: "c0", at: now.addingTimeInterval(2)), .granted)
        XCTAssertTrue(ledger.mayRun("c0", request: request, at: now.addingTimeInterval(3)))
        XCTAssertFalse(ledger.mayRun("c0", request: request, at: now.addingTimeInterval(4)), "once")

        // One tap runs it once, for exactly these words.
        ledger.asked("c2", request: request, needsTap: true, at: now)
        XCTAssertEqual(ledger.answer(.tapped, for: "c2", at: now.addingTimeInterval(2)), .granted)
        let other = VoiceToolRequest.handOverErrand(draft(words: "znajdź tani hotel w Rzymie i samochód"))
        XCTAssertFalse(ledger.mayRun("c2", request: other, at: now.addingTimeInterval(3)), "another text needs its own tap")
        ledger.asked("c3", request: request, needsTap: true, at: now)
        XCTAssertEqual(ledger.answer(.tapped, for: "c3", at: now.addingTimeInterval(2)), .granted)
        XCTAssertTrue(ledger.mayRun("c3", request: request, at: now.addingTimeInterval(3)))
        XCTAssertFalse(ledger.mayRun("c3", request: request, at: now.addingTimeInterval(4)), "once")
    }

    func testTheSpecAndTheCatalogSayACardForHandingOverAndAtOnceForChecking() throws {
        let descriptor = try XCTUnwrap(ToolCatalog.descriptor(VoiceToolName.handOverErrand))
        XCTAssertEqual(descriptor.approval, .card)
        XCTAssertEqual(descriptor.effect, .handoff)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let spec = try RealtimeToolCatalog.decode(Data(contentsOf: root.appendingPathComponent("voice-agent/tools.json")))
        let tool = try XCTUnwrap(spec.first { $0.name == VoiceToolName.handOverErrand })
        XCTAssertEqual(tool.ask, .yesOrTap, "a card that a spoken yes or a tap answers (decision 2026-11-14-spoken-yes-and-fewer-cards)")
        XCTAssertTrue(tool.confirmOnScreen)
        // Checking what a task found, and this week's leaflets, run at once since 11 Nov 2026
        // (decision 2026-11-11-asked-for-runs-at-once): no card, no spoken question.
        let check = try XCTUnwrap(spec.first { $0.name == VoiceToolName.checkErrands })
        XCTAssertEqual(check.ask, .runsNow)
        XCTAssertFalse(check.confirmOnScreen)
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.checkErrands)?.approval, .runsNow)
        let deals = try XCTUnwrap(spec.first { $0.name == VoiceToolName.findDeals })
        XCTAssertEqual(deals.ask, .runsNow)
        XCTAssertFalse(deals.confirmOnScreen)
    }

    func testInTheCarAnErrandWaitsForATapToo() {
        guard case .refuse = CarProfile.decision(for: .handOverErrand(draft())) else { return XCTFail("a tap is not possible while driving") }
        XCTAssertEqual(CarProfile.decision(for: .checkErrands(about: nil)), .run)
    }
}
