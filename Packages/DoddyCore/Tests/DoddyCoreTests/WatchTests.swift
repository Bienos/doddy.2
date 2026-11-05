@testable import DoddyCore
import XCTest

/// Price watch (docs/implementation/SHOPPING_WATCH.md, ADR-614): the digest is the fixture's (computed
/// with Python) and any change to the words is a different yes; the draft keeps the contract's request
/// rules; the client sends exactly the contract's requests, refuses a preview that isn't for what the user
/// was shown, never reports an approval the server didn't confirm and maps every refusal; summaries decode as
/// the server writes them, a state this app doesn't know is never active, and "dropped" is never said
/// without the confirmed price.
final class WatchTests: XCTestCase {
    private func fixtureObject() throws -> [String: Any] { try Fixtures.json("watch_create_v1.json") }

    private func part(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(fixtureObject()[name] as? [String: Any], name)
    }

    private func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    private func summaryJSON(_ name: String) throws -> Data {
        try data(try XCTUnwrap(part("summaries")[name]))
    }

    private func summary(_ name: String) throws -> WatchSummary {
        try JSONDecoder().decode(WatchSummary.self, from: summaryJSON(name))
    }

    private func previewData(_ edit: ([String: Any]) -> [String: Any] = { $0 }) throws -> Data {
        try data(edit(try part("preview")))
    }

    private func fixtureDraft() throws -> PriceWatchDraft {
        let r = try part("request")
        return PriceWatchDraft(title: r["title"] as! String, shop: r["shop"] as! String, url: r["url"] as! String,
                               thresholdMinor: r["thresholdMinor"] as! Int, currency: r["currency"] as! String,
                               language: r["language"] as! String)
    }

    private func draft(title: String = "Zmywarka", shop: String = "Media Expert", url: String = "https://www.mediaexpert.pl/p/1",
                       thresholdMinor: Int = 180_000, currency: String = "PLN", language: String = "pl") -> PriceWatchDraft {
        PriceWatchDraft(title: title, shop: shop, url: url, thresholdMinor: thresholdMinor, currency: currency, language: language)
    }

    private func client(_ transport: any ServerTransport) -> DoddyServerClient {
        DoddyServerClient(transport: transport, credentials: WatchCredentials(token: "t"))
    }

    private func date(_ text: String) throws -> Date { try XCTUnwrap(ServerDates.parse(text)) }

    private let dropPrice = Money(minor: 179_900)

    // MARK: The draft and its digest

    func testTheCanonicalTextAndTheDigestAreTheFixturesAndTheFixtureDraftIsValid() throws {
        let draft = try fixtureDraft()
        XCTAssertEqual(draft.canonicalJSON, try fixtureObject()["canonical"] as? String)
        XCTAssertEqual(draft.digest, try fixtureObject()["digest"] as? String, "SHA-256 over the same bytes, computed by Python")
        XCTAssertEqual(draft.digest, try part("preview")["digest"] as? String, "the server's preview carries the same digest")
        XCTAssertEqual(draft.validationIssues(), [])
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.digest.count, 64)
        XCTAssertEqual(draft.threshold, Money(minor: 180_000))
        // The promise is part of what is signed: days and checks a day are in the text.
        XCTAssertTrue(draft.canonicalJSON.contains("\"checksPerDay\":4"))
        XCTAssertTrue(draft.canonicalJSON.contains("\"days\":30"))
    }

    func testAnyChangeToTheWordsIsADifferentDigest() throws {
        let base = try fixtureDraft()
        let edits: [(String, PriceWatchDraft)] = [
            ("title", draft(title: "Zmywarka do zabudowy 45 cm", shop: base.shop, url: base.url, thresholdMinor: base.thresholdMinor)),
            ("shop", draft(title: base.title, shop: "x-kom", url: base.url, thresholdMinor: base.thresholdMinor)),
            ("url", draft(title: base.title, shop: base.shop, url: base.url + "?x=1", thresholdMinor: base.thresholdMinor)),
            ("price", draft(title: base.title, shop: base.shop, url: base.url, thresholdMinor: base.thresholdMinor - 1)),
            ("currency", draft(title: base.title, shop: base.shop, url: base.url, thresholdMinor: base.thresholdMinor, currency: "EUR")),
            ("language", draft(title: base.title, shop: base.shop, url: base.url, thresholdMinor: base.thresholdMinor, language: "en")),
        ]
        for (name, edited) in edits { XCTAssertNotEqual(edited.digest, base.digest, name) }
        // Only leading and trailing spaces of the texts are trimmed; the trimmed draft is the same yes.
        let spaced = draft(title: "  \(base.title)\n", shop: " \(base.shop) ", url: " \(base.url) ", thresholdMinor: base.thresholdMinor)
        XCTAssertEqual(spaced.digest, base.digest)
        XCTAssertEqual(spaced.title, base.title)
        // Inner spaces are the user's words and are kept.
        XCTAssertNotEqual(draft(title: "a  b").digest, draft(title: "a b").digest)
    }

    func testStringsAreEscapedAsJSONStringifyWritesThem() {
        // Vector computed with Python (json.dumps, ensure_ascii=False, sort_keys, compact separators), which
        // escapes exactly what JavaScript's JSON.stringify does: quotes, backslash, \b \t \n \f \r, other
        // control characters as lower-case \u00xx; DEL, U+2028 and U+2029 and everything else as it is.
        let tricky = PriceWatchDraft(
            title: "Say \"hi\" \\ back/slash\nnew\tline\r\u{08}\u{0C}\u{01}\u{1F}\u{7F}\u{2028}\u{2029} 🇮🇹 é",
            shop: "Sklep \"Żółw\" & Syn", url: "https://example.pl/a?b=c&d=é#frag", thresholdMinor: 99_999, currency: "EUR", language: "en")
        XCTAssertEqual(tricky.digest, "637bd356e3b19b8a7c3a21c69ef5d34ae2aea298e0a66d2480f266c6faddb6e9")
        XCTAssertTrue(tricky.canonicalJSON.contains(#"\"hi\" \\ back/slash\nnew\tline\r\b\f\u0001\u001f"#))
        XCTAssertTrue(tricky.canonicalJSON.contains("\u{7F}\u{2028}\u{2029} 🇮🇹 é"))
    }

    func testEveryRuleOfTheRequestIsKept() {
        func issues(_ d: PriceWatchDraft) -> [WatchDraftIssue] { d.validationIssues() }
        // title: 1 to 120, not blank (UTF-16 units, as the server counts)
        XCTAssertEqual(issues(draft(title: "")), [.missingTitle])
        XCTAssertEqual(issues(draft(title: "   \n ")), [.missingTitle])
        XCTAssertEqual(issues(draft(title: String(repeating: "a", count: 120))), [])
        XCTAssertEqual(issues(draft(title: String(repeating: "a", count: 121))), [.titleTooLong])
        XCTAssertEqual(issues(draft(title: String(repeating: "😀", count: 60))), [], "an emoji counts twice, 120 units")
        XCTAssertEqual(issues(draft(title: String(repeating: "😀", count: 61))), [.titleTooLong])
        // shop: 1 to 80
        XCTAssertEqual(issues(draft(shop: "")), [.missingShop])
        XCTAssertEqual(issues(draft(shop: " ")), [.missingShop])
        XCTAssertEqual(issues(draft(shop: String(repeating: "s", count: 80))), [])
        XCTAssertEqual(issues(draft(shop: String(repeating: "s", count: 81))), [.shopTooLong])
        // url: https with a host, at most 2048
        for good in ["https://x.pl", "https://x.pl/", "HTTPS://X.PL/p", "https://www.mediaexpert.pl/a/b?c=d#e", "https://x.pl:8443/p",
                     "https://user@x.pl/p", "https://[2001:db8::1]/p", "https://x.pl/zmywarka-do-zabudowy-ż"] {
            XCTAssertEqual(issues(draft(url: good)), [], good)
        }
        for bad in ["", "http://x.pl/p", "ftp://x.pl/p", "x.pl/p", "//x.pl/p", "https:/x.pl", "https://", "https:///p", "https://:443/p",
                    "https://?q=1", "https://x.pl/a b", "https://x.pl/a\u{00A0}b", "https://x.pl/a\nb", "https://[]/p", "https://[::1/p", "javascript:alert(1)"] {
            XCTAssertEqual(issues(draft(url: bad)), [.urlNotHTTPS], bad)
        }
        let atLimit = "https://x.pl/" + String(repeating: "a", count: 2_048 - "https://x.pl/".utf16.count)
        XCTAssertEqual(atLimit.utf16.count, 2_048)
        XCTAssertEqual(issues(draft(url: atLimit)), [])
        XCTAssertEqual(issues(draft(url: atLimit + "a")), [.urlTooLong])
        // thresholdMinor: an integer from 1 to 1,000,000,000
        XCTAssertEqual(issues(draft(thresholdMinor: 0)), [.priceOutOfRange])
        XCTAssertEqual(issues(draft(thresholdMinor: -5)), [.priceOutOfRange])
        XCTAssertEqual(issues(draft(thresholdMinor: 1)), [])
        XCTAssertEqual(issues(draft(thresholdMinor: 1_000_000_000)), [])
        XCTAssertEqual(issues(draft(thresholdMinor: 1_000_000_001)), [.priceOutOfRange])
        // currency [A-Z]{3}, language [a-z]{2}: never fixed up silently
        for bad in ["", "pln", "PL", "PLNN", "zł", "P1N", "ŻŁŻ"] { XCTAssertEqual(issues(draft(currency: bad)), [.currencyNotACode], bad) }
        XCTAssertEqual(issues(draft(currency: "EUR")), [])
        for bad in ["", "PL", "pol", "p", "p1", "pł"] { XCTAssertEqual(issues(draft(language: bad)), [.languageNotACode], bad) }
        XCTAssertEqual(issues(draft(language: "en")), [])
        // All at once, in a fixed order, each naming the request's field.
        let broken = issues(draft(title: "", shop: "", url: "http://x", thresholdMinor: 0, currency: "pln", language: "PL"))
        XCTAssertEqual(broken, [.missingTitle, .missingShop, .urlNotHTTPS, .priceOutOfRange, .currencyNotACode, .languageNotACode])
        XCTAssertEqual(broken.map(\.field), ["title", "shop", "url", "thresholdMinor", "currency", "language"])
        XCTAssertFalse(draft(title: "").isValid)
    }

    func testAPicksOfferIsWatchedOnTheShopsOwnPageAndOnlyWhenItWasReadThere() throws {
        func offer(_ evidence: ShoppingOffer.Evidence = .shopPage, url: String = "https://www.mediaexpert.pl/p/1",
                   title: String = "Zmywarka", shop: String = "Media Expert", currency: String = "PLN") -> ShoppingOffer {
            ShoppingOffer(id: "o1", title: title, shop: shop, price: Money(minor: 189_900, currency: currency), url: url,
                          buyUrl: "https://partner.example/r?u=abc", evidence: evidence, seenAt: Date(timeIntervalSince1970: 0))
        }
        XCTAssertTrue(offer().canWatchPrice)
        XCTAssertFalse(offer(.listing).canWatchPrice, "a Google Shopping list price isn't one the shop's page confirmed")
        XCTAssertFalse(offer(.unknown).canWatchPrice)
        XCTAssertFalse(offer(url: "http://www.mediaexpert.pl/p/1").canWatchPrice)
        XCTAssertFalse(offer(url: "https://").canWatchPrice)
        XCTAssertFalse(offer(currency: "zł").canWatchPrice)

        let made = PriceWatchDraft(watching: offer(), thresholdMinor: 180_000)
        XCTAssertEqual(made.url, "https://www.mediaexpert.pl/p/1", "the shop's own page, never the partner link")
        XCTAssertEqual(made.title, "Zmywarka")
        XCTAssertEqual(made.shop, "Media Expert")
        XCTAssertEqual(made.currency, "PLN")
        XCTAssertEqual(made.language, "pl")
        XCTAssertEqual(made.validationIssues(), [])
        XCTAssertEqual(PriceWatchDraft(watching: offer(currency: "EUR"), thresholdMinor: 5, language: "en").currency, "EUR")

        // A title longer than the server takes is cut with "…" before the card shows it, between characters.
        let long = PriceWatchDraft(watching: offer(title: String(repeating: "ż", count: 200), shop: String(repeating: "s", count: 100)), thresholdMinor: 1)
        XCTAssertEqual(long.title, String(repeating: "ż", count: 119) + "…")
        XCTAssertEqual(long.title.utf16.count, 120)
        XCTAssertEqual(long.shop, String(repeating: "s", count: 79) + "…")
        XCTAssertEqual(long.validationIssues(), [])
        let emoji = PriceWatchDraft(watching: offer(title: String(repeating: "😀", count: 100)), thresholdMinor: 1)
        XCTAssertLessThanOrEqual(emoji.title.utf16.count, 120)
        XCTAssertTrue(emoji.title.hasSuffix("…"))
        XCTAssertEqual(emoji.validationIssues(), [])
        let exact = String(repeating: "a", count: 120)
        XCTAssertEqual(PriceWatchDraft(watching: offer(title: exact), thresholdMinor: 1).title, exact, "at the limit nothing is cut")
    }

    // MARK: The user's price

    func testTheSuggestedPriceIsFivePercentBelowRoundedDownToWholeZloty() {
        XCTAssertEqual(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: 189_900), 180_400, "1 899 zł → 1 804 zł")
        XCTAssertEqual(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: 100_000), 95_000)
        XCTAssertEqual(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: 99_900), 94_900, "94 905 → 949 zł, down")
        XCTAssertEqual(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: 5_000), 4_700, "47,50 zł → 47 zł, down")
        XCTAssertEqual(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: 150), 100)
        // Under one whole złoty there is nothing to round to: the plain 5% below.
        XCTAssertEqual(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: 99), 94)
        XCTAssertEqual(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: 2), 1)
        for none in [1, 0, -100, 1_000_000_001] { XCTAssertNil(PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: none), "\(none)") }
        // Always a price the contract takes, below the price.
        for price in 2...20_000 {
            let suggestion = PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: price)
            XCTAssertNotNil(suggestion, "\(price)")
            guard let suggestion else { continue }
            XCTAssertGreaterThanOrEqual(suggestion, 1)
            XCTAssertLessThan(suggestion, price)
            XCTAssertLessThanOrEqual(suggestion, price * 95 / 100, "never more than 5% below: \(price)")
            if price >= 106 { XCTAssertEqual(suggestion % 100, 0, "whole złoty: \(price)") }
        }
    }

    func testTheUsersTypedPriceIsReadOnlyWhenItIsAPrice() {
        let good: [(String, Int)] = [
            ("1800", 180_000), ("1 800", 180_000), ("1\u{00A0}800", 180_000), ("  1800  ", 180_000), ("1799,90", 179_990),
            ("1799.90", 179_990), ("1799,9", 179_990), ("1799.5", 179_950), ("1800 zł", 180_000), ("1800zł", 180_000), ("1800 ZŁ", 180_000),
            ("1800 PLN", 180_000), ("1800 pln", 180_000), ("0,01", 1), ("0.5", 50), ("10000000", 1_000_000_000), ("10000000,00", 1_000_000_000),
        ]
        for (text, minor) in good { XCTAssertEqual(PriceWatchDraft.parseThresholdMinor(text), minor, text) }
        for bad in ["", " ", "abc", "zł", "0", "0,00", "-5", "+5", "1,800.50", "1.800,50", "12,345", "1800,", ",50", ".5", "1800,,5",
                    "10000000,01", "10000001", "1 000 000 000", "99999999999999", "1800 EUR", "1e3", "٣٠٠"] {
            XCTAssertNil(PriceWatchDraft.parseThresholdMinor(bad), bad)
        }
        XCTAssertEqual(PriceWatchDraft.parseThresholdMinor("1800 EUR", currency: "EUR"), 180_000)
        XCTAssertNil(PriceWatchDraft.parseThresholdMinor("1800 PLN", currency: "EUR"))
    }

    func testTheSuggestedPriceIsTypedBackToTheSameAmount() {
        XCTAssertEqual(PriceWatchDraft.typedText(forMinor: 180_400, .polish), "1804")
        XCTAssertEqual(PriceWatchDraft.typedText(forMinor: 179_990, .polish), "1799,90")
        XCTAssertEqual(PriceWatchDraft.typedText(forMinor: 179_990, .english), "1799.90")
        XCTAssertEqual(PriceWatchDraft.typedText(forMinor: 179_905, .polish), "1799,05")
        XCTAssertEqual(PriceWatchDraft.typedText(forMinor: 94, .polish), "0,94")
        XCTAssertEqual(PriceWatchDraft.typedText(forMinor: 1_000_000_000, .english), "10000000")
        for minor in Array(1...3_000) + [99_999, 179_990, 1_000_000_000] {
            for language in [NotificationLanguage.polish, .english] {
                XCTAssertEqual(PriceWatchDraft.parseThresholdMinor(PriceWatchDraft.typedText(forMinor: minor, language)), minor, "\(minor)")
            }
        }
    }

    // MARK: The server's answers

    func testThePreviewDecodesAsTheFixtureWritesItAndMustMatchTheDraft() throws {
        let preview = try JSONDecoder().decode(WatchPreview.self, from: previewData())
        XCTAssertEqual(preview.id, UUID(uuidString: "7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81"))
        XCTAssertEqual(preview.currentMinor, 189_900)
        XCTAssertEqual(preview.current, Money(minor: 189_900))
        XCTAssertEqual(preview.threshold, Money(minor: 180_000))
        XCTAssertEqual(preview.checkedAt, try date("2026-10-24T12:02:00.000Z"))
        XCTAssertEqual(preview.expiresAt, try date("2026-10-24T12:12:00.000Z"))
        XCTAssertEqual(preview.expiresAt.timeIntervalSince(preview.checkedAt), 600, "a draft lives 10 minutes")
        XCTAssertEqual(preview.days, 30)
        XCTAssertEqual(preview.checksPerDay, 4)
        let mine = try fixtureDraft()
        XCTAssertTrue(preview.matches(mine))

        func changed(_ key: String, _ value: Any) throws -> WatchPreview {
            try JSONDecoder().decode(WatchPreview.self, from: previewData { var p = $0; p[key] = value; return p })
        }
        let others: [(String, Any)] = [
            ("title", "Inna zmywarka"), ("shop", "x-kom"), ("url", "https://www.x-kom.pl/p/1"), ("thresholdMinor", 170_000),
            ("currency", "EUR"), ("language", "en"), ("days", 31), ("checksPerDay", 5), ("digest", String(repeating: "0", count: 64)),
        ]
        for (key, value) in others { XCTAssertFalse(try changed(key, value).matches(mine), key) }
        // A price read now isn't in the digest: it varies and doesn't make it another yes.
        XCTAssertTrue(try changed("currentMinor", 188_000).matches(mine))
    }

    func testSummariesDecodeAsTheFixtureWritesThem() throws {
        let active = try summary("active")
        XCTAssertEqual(active.id, UUID(uuidString: "7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81"))
        XCTAssertEqual(active.state, .active)
        XCTAssertTrue(active.state.isActive)
        XCTAssertEqual(active.title, "Zmywarka do zabudowy 45 cm, 42 dB, 10 kompletów")
        XCTAssertEqual(active.shop, "Media Expert")
        XCTAssertEqual(active.thresholdMinor, 180_000)
        XCTAssertEqual(active.currency, "PLN")
        XCTAssertEqual(active.language, "pl")
        XCTAssertEqual(active.createdAt, try date("2026-10-24T12:02:30.000Z"))
        XCTAssertEqual(active.endsAt, try date("2026-11-23T12:02:30.000Z"))
        XCTAssertEqual(active.lastCheckedAt, try date("2026-10-24T18:03:10.000Z"))
        XCTAssertEqual(active.lastPrice, Money(minor: 189_900))
        XCTAssertEqual(active.checksDone, 2)
        XCTAssertNil(active.triggeredAt)
        XCTAssertNil(active.triggeredPriceMinor)
        XCTAssertNil(active.failure)
        XCTAssertNil(active.confirmedDrop)
        XCTAssertTrue(active.canStop)

        let triggered = try summary("triggered")
        XCTAssertEqual(triggered.state, .triggered)
        XCTAssertFalse(triggered.state.isActive)
        XCTAssertTrue(triggered.state.isFinished)
        XCTAssertEqual(triggered.triggeredAt, try date("2026-10-26T06:02:41.000Z"))
        XCTAssertEqual(triggered.triggeredPriceMinor, 179_900)
        XCTAssertEqual(triggered.confirmedDrop, dropPrice)
        XCTAssertEqual(triggered.checksDone, 9)
        XCTAssertFalse(triggered.canStop)

        let failed = try summary("failed")
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.failure, .unreadable)
        XCTAssertNil(failed.lastPriceMinor, "a failed check is never a price")
        XCTAssertNil(failed.lastPrice)
        XCTAssertNil(failed.confirmedDrop)
        XCTAssertEqual(failed.lastCheckedAt, try date("2026-10-26T12:02:00.000Z"))
        XCTAssertEqual(failed.checksDone, 8)
        XCTAssertFalse(failed.canStop)
    }

    func testAStopTheServerAnsweredChangesOnlyAnActiveRow() throws {
        let active = try summary("active")
        let stopped = active.stopped()
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertFalse(stopped.canStop)
        XCTAssertEqual(stopped.id, active.id)
        XCTAssertEqual(stopped.title, active.title)
        XCTAssertEqual(stopped.lastPriceMinor, active.lastPriceMinor, "what the server last confirmed stays")
        XCTAssertEqual(stopped.checksDone, active.checksDone)
        XCTAssertEqual(stopped.endsAt, active.endsAt)
        XCTAssertEqual(WatchWords.state(stopped, .english), "Stopped")
        for name in ["triggered", "failed"] {
            let other = try summary(name)
            XCTAssertEqual(other.stopped(), other, "\(name) is not an active watch: it stays as the server said")
        }
    }

    func testAStateTheAppDoesntKnowIsNeverShownAsActive() throws {
        func summary(_ state: String, extra: String = "") throws -> WatchSummary {
            try JSONDecoder().decode(WatchSummary.self, from: Data("""
            {"id":"7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81","state":"\(state)","title":"T","shop":"S","url":"https://x.pl/p",
             "thresholdMinor":100,"currency":"PLN","language":"pl","createdAt":"2026-10-24T12:02:30Z"\(extra)}
            """.utf8))
        }
        for state in ["paused", "", "ACTIVE", "snoozed"] {
            let unknown = try summary(state)
            XCTAssertEqual(unknown.state, .unknown, state)
            XCTAssertFalse(unknown.state.isActive)
            XCTAssertFalse(unknown.state.isFinished)
            XCTAssertFalse(unknown.canStop, "an unknown state isn't stopped as if it were active")
            XCTAssertEqual(WatchWords.state(unknown, .english), "Status not known")
            XCTAssertEqual(WatchWords.state(unknown, .polish), "Nieznany stan")
            XCTAssertNotEqual(WatchWords.state(unknown, .english), WatchWords.state(try summary("active"), .english))
        }
        // Optional fields are optional; null reads as absent; an unknown failure code is `unknown`.
        let sparse = try summary("active", extra: #","endsAt":null,"lastPriceMinor":null,"failure":"newer_code","checksDone":3"#)
        XCTAssertNil(sparse.endsAt)
        XCTAssertNil(sparse.lastPriceMinor)
        XCTAssertEqual(sparse.failure, .unknown)
        XCTAssertEqual(sparse.checksDone, 3)
        XCTAssertEqual(try summary("active").checksDone, 0)
        // A draft read by id carries when it lapses and no end.
        let draft = try summary("draft", extra: #","expiresAt":"2026-10-24T12:12:00.000Z""#)
        XCTAssertEqual(draft.state, .draft)
        XCTAssertEqual(draft.expiresAt, try date("2026-10-24T12:12:00.000Z"))
        XCTAssertNil(draft.endsAt)
        XCTAssertFalse(draft.canStop)
        // A time that isn't a time is refused, not read as "now".
        XCTAssertThrowsError(try summary("active", extra: #","lastCheckedAt":"yesterday""#))
    }

    // MARK: The words

    func testTheCardsPromiseIsTheContractsSentence() {
        XCTAssertEqual(WatchWords.promise(.english),
                       "I check the page 4 times a day for 30 days, then I stop. I only tell you; I don't buy anything.")
        let polish = WatchWords.promise(.polish)
        XCTAssertTrue(polish.contains("4 razy dziennie przez 30 dni"), polish)
        XCTAssertTrue(polish.contains("potem przestaję"), polish)
        XCTAssertTrue(polish.contains("niczego nie kupuję"), polish)
        XCTAssertEqual(PriceWatchDraft.days, 30)
        XCTAssertEqual(PriceWatchDraft.checksPerDay, 4)
    }

    func testEveryStateHasItsWordsInBothLanguages() throws {
        let nbsp = "\u{00A0}"
        func watch(_ state: WatchState, triggered: Int? = nil) -> WatchSummary {
            WatchSummary(id: UUID(), state: state, title: "T", shop: "S", url: "https://x.pl/p", thresholdMinor: 180_000,
                         createdAt: Date(timeIntervalSince1970: 0), triggeredPriceMinor: triggered)
        }
        let expected: [(WatchState, Int?, String, String)] = [
            (.active, nil, "Pilnuję", "Watching"),
            (.triggered, 179_900, "Cena spadła do 1\(nbsp)799,00\(nbsp)zł", "Price dropped to PLN 1,799.00"),
            (.expired, nil, "Skończone po 30 dniach", "Finished after 30 days"),
            (.stopped, nil, "Zatrzymane", "Stopped"),
            (.failed, nil, "Nie mogę już odczytać ceny", "I can no longer read the price"),
            (.draft, nil, "Czeka na Twoje „tak”", "Waiting for your yes"),
            (.unknown, nil, "Nieznany stan", "Status not known"),
        ]
        for (state, triggered, polish, english) in expected {
            XCTAssertEqual(WatchWords.state(watch(state, triggered: triggered), .polish), polish, "\(state)")
            XCTAssertEqual(WatchWords.state(watch(state, triggered: triggered), .english), english, "\(state)")
        }
        XCTAssertEqual(Set(expected.map { $0.0 }), Set(WatchState.allCases), "a new state needs its words")
        // The fixture's triggered watch, in the user's words.
        XCTAssertEqual(WatchWords.state(try summary("triggered"), .polish), "Cena spadła do 1\(nbsp)799,00\(nbsp)zł")
        XCTAssertEqual(WatchWords.state(try summary("failed"), .polish), "Nie mogę już odczytać ceny")
    }

    func testDroppedIsNeverSaidWithoutTheConfirmedPrice() throws {
        func watch(_ state: WatchState, triggered: Int?) -> WatchSummary {
            WatchSummary(id: UUID(), state: state, title: "T", shop: "S", url: "https://x.pl/p", thresholdMinor: 180_000,
                         createdAt: Date(timeIntervalSince1970: 0), lastPriceMinor: 189_900, triggeredPriceMinor: triggered)
        }
        for state in WatchState.allCases {
            for triggered in [nil, 179_900, 180_000, 180_001, 250_000] as [Int?] {
                let w = watch(state, triggered: triggered)
                let says = [WatchWords.state(w, .english), WatchWords.state(w, .polish)].contains {
                    $0.contains("dropped to") || $0.contains("spadła do")
                }
                // Only a triggered watch with a confirmed price at or below the user's says it.
                let mayAsk = state == .triggered && triggered != nil && triggered! <= 180_000
                XCTAssertEqual(says, mayAsk, "\(state) \(String(describing: triggered))")
                XCTAssertEqual(w.confirmedDrop != nil, mayAsk, "\(state) \(String(describing: triggered))")
            }
        }
        // The words for a triggered watch with nothing confirmed say so.
        let none = watch(.triggered, triggered: nil)
        XCTAssertEqual(WatchWords.state(none, .english), "I can't confirm that the price dropped")
        XCTAssertEqual(WatchWords.state(none, .polish), "Nie mogę potwierdzić, że cena spadła")
    }

    func testOnlyAnActiveWatchSaysWatching() throws {
        for state in WatchState.allCases where state != .active {
            let w = WatchSummary(id: UUID(), state: state, title: "T", shop: "S", url: "https://x.pl/p", thresholdMinor: 100,
                                 createdAt: Date(timeIntervalSince1970: 0), triggeredPriceMinor: 50)
            XCTAssertFalse(WatchWords.state(w, .english).contains("Watching"), "\(state)")
            XCTAssertFalse(WatchWords.state(w, .polish).contains("Pilnuję"), "\(state)")
        }
    }

    func testThePriceLinesNameOnlyWhatTheServerConfirmed() throws {
        let active = try summary("active")
        XCTAssertEqual(WatchWords.yourPrice(active, .english), "Your price: PLN 1,800.00")
        XCTAssertEqual(WatchWords.yourPrice(active, .polish), "Twoja cena: 1\u{00A0}800,00\u{00A0}zł")
        XCTAssertEqual(WatchWords.lastPrice(active, .english), "Last confirmed price: PLN 1,899.00")
        XCTAssertEqual(WatchWords.lastPrice(active, .polish), "Ostatnia potwierdzona cena: 1\u{00A0}899,00\u{00A0}zł")
        XCTAssertNil(WatchWords.lastPrice(try summary("failed"), .english), "a watch that never read a price names none")
        XCTAssertNil(WatchWords.lastPrice(try summary("failed"), .polish))
        let euro = WatchSummary(id: UUID(), state: .active, title: "T", shop: "S", url: "https://x.eu/p", thresholdMinor: 5_000, currency: "EUR",
                                createdAt: Date(timeIntervalSince1970: 0), lastPriceMinor: 5_500)
        XCTAssertEqual(WatchWords.lastPrice(euro, .polish), "Ostatnia potwierdzona cena: 55,00\u{00A0}EUR")
    }

    func testStartedIsSaidOnlyWithTheThresholdAndNeverClaimsABuy() {
        let threshold = Money(minor: 180_000)
        let english = WatchWords.started(threshold: threshold, .english)
        XCTAssertEqual(english, "I'm watching. I'll tell you when the price is PLN 1,800.00 or lower. I don't buy anything.")
        let polish = WatchWords.started(threshold: threshold, .polish)
        XCTAssertTrue(polish.hasPrefix("Pilnuję."), polish)
        XCTAssertTrue(polish.contains("1\u{00A0}800,00\u{00A0}zł"), polish)
        XCTAssertTrue(polish.contains("Nic nie kupuję"), polish)
        for language in [NotificationLanguage.english, .polish] {
            let unsure = WatchWords.notSure(language)
            XCTAssertFalse(unsure.contains("I'm watching") || unsure.hasPrefix("Pilnuję."), unsure)
            XCTAssertFalse(WatchWords.notStartedYet(language).contains("I'm watching") || WatchWords.notStartedYet(language).hasPrefix("Pilnuję."))
        }
        XCTAssertTrue(WatchWords.notSure(.english).contains("may be running"))
        XCTAssertTrue(WatchWords.notSure(.english).contains("won't start it again by myself"))
        XCTAssertTrue(WatchWords.notStartedYet(.english).contains("Nothing is being watched"))
    }

    func testEveryRefusalIsSaidInWordsAndNeverClaimsAWatch() {
        let errors: [WatchError] = [
            .server(.offline), .server(.rateLimited), .server(.unexpected(status: 500)), .server(.accountMissing),
            .invalid(fields: ["url"]), .priceNotReadable(.blocked), .priceNotReadable(.notAllowed), .priceNotReadable(.noPrice),
            .priceNotReadable(.failed), .priceNotReadable(.unknown), .currencyMismatch, .alreadyBelow(currentMinor: 179_900),
            .alreadyBelow(currentMinor: nil), .notApprovable(state: .active), .notApprovable(state: nil), .digestMismatch,
            .tooManyOpenWatches, .notStoppable(state: .stopped), .notStoppable(state: .triggered), .notFound, .watchesDisabled,
            .rateLimited, .conflict("x"), .previewMismatch,
        ]
        var seen = Set<String>()
        for error in errors {
            for language in [NotificationLanguage.english, .polish] {
                let words = WatchWords.problem(error, language)
                XCTAssertFalse(words.isEmpty, "\(error)")
                XCTAssertFalse(words.contains("I'm watching") || words.hasPrefix("Pilnuję."), "\(error): \(words)")
                XCTAssertFalse(words.contains("dropped") || words.contains("spadła"), "\(error): \(words)")
                seen.insert(words)
            }
        }
        XCTAssertGreaterThan(seen.count, 20, "the refusals are told apart")
        let english: [(WatchError, String)] = [
            (.priceNotReadable(.blocked), "doesn't let automated readers in, and Doddy doesn't get around that"),
            (.priceNotReadable(.notAllowed), "doesn't allow automated reading"),
            (.priceNotReadable(.noPrice), "couldn't find a price I can read"),
            (.priceNotReadable(.failed), "couldn't read this page just now"),
            (.currencyMismatch, "different currency"),
            (.alreadyBelow(currentMinor: 179_900), "already at or below yours (now PLN 1,799.00)"),
            (.tooManyOpenWatches, "as many prices as Doddy's server allows"),
            (.watchesDisabled, "switched off or not set up on Doddy's server"),
            (.notApprovable(state: nil), "expired or was already used"),
            (.digestMismatch, "Nothing was started"),
            (.previewMismatch, "doesn't hold exactly what you were shown"),
            (.notStoppable(state: .stopped), "already stopped"),
            (.notStoppable(state: .expired), "already ended"),
            (.server(.offline), "Nothing was changed"),
        ]
        for (error, part) in english { XCTAssertTrue(WatchWords.problem(error, .english).contains(part), "\(error)") }
        XCTAssertTrue(WatchWords.problem(WatchError.alreadyBelow(currentMinor: 5_500), currency: "EUR", .polish).contains("teraz 55,00\u{00A0}EUR"))
        XCTAssertFalse(WatchWords.problem(WatchError.alreadyBelow(currentMinor: nil), .english).contains("now"))
        // A transport's own rate limit and offline read the same as the client's.
        XCTAssertEqual(WatchWords.problem(ServerError.offline, .english), WatchWords.problem(WatchError.server(.offline), .english))
        XCTAssertEqual(WatchWords.problem(ServerError.rateLimited, .english), WatchWords.problem(WatchError.rateLimited, .english))
        XCTAssertTrue(WatchWords.paused(.english).contains("Nothing was sent"))
        XCTAssertTrue(WatchWords.noServer(.english).contains("isn't set up"))
        XCTAssertTrue(WatchWords.notAPrice(.polish).contains("1799,90"))
    }

    // MARK: The client

    func testCreateSendsOnePostWithExactlyTheContractsFields() async throws {
        let transport = WatchScripted([ServerResponse(status: 201, body: try previewData())])
        let preview = try await client(transport).createWatch(try fixtureDraft())
        XCTAssertEqual(preview, try JSONDecoder().decode(WatchPreview.self, from: previewData()))
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].method, .post)
        XCTAssertEqual(sent[0].path, "/v1/watches")
        XCTAssertEqual(sent[0].bearerToken, "t")
        XCTAssertGreaterThan(sent[0].timeout, ServerRequest.defaultTimeout, "the server reads the shop's page while it makes the draft")
        XCTAssertEqual(sent[0].timeout, DoddyServerClient.watchCreateTimeout)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent[0].body ?? Data()) as? [String: Any])
        let request = try part("request")
        XCTAssertEqual(Set(body.keys), Set(request.keys), "strict: no more and no fewer fields")
        XCTAssertEqual(body["title"] as? String, request["title"] as? String)
        XCTAssertEqual(body["shop"] as? String, request["shop"] as? String)
        XCTAssertEqual(body["url"] as? String, request["url"] as? String)
        XCTAssertEqual(body["thresholdMinor"] as? Int, request["thresholdMinor"] as? Int)
        XCTAssertEqual(body["currency"] as? String, request["currency"] as? String)
        XCTAssertEqual(body["language"] as? String, request["language"] as? String)
    }

    func testAPreviewThatIsntForWhatTheUserWasShownIsNeverReturnedForApproval() async throws {
        let mine = try fixtureDraft()
        let others: [(String, Any)] = [
            ("title", "Inna zmywarka"), ("shop", "x-kom"), ("url", "https://www.x-kom.pl/p/1"), ("thresholdMinor", 170_000),
            ("currency", "EUR"), ("language", "en"), ("days", 60), ("checksPerDay", 24), ("digest", String(repeating: "0", count: 64)),
        ]
        for (key, value) in others {
            let reply = try previewData { var p = $0; p[key] = value; return p }
            do {
                _ = try await client(WatchScripted([ServerResponse(status: 201, body: reply)])).createWatch(mine)
                XCTFail("a preview with another \(key) must not come back")
            } catch {
                XCTAssertEqual(error as? WatchError, .previewMismatch, key)
            }
        }
    }

    func testAPriceAlreadyAtOrBelowTheUsersIsNeverADraft() async throws {
        for current in [180_000, 179_900, 1] {
            let reply = try previewData { var p = $0; p["currentMinor"] = current; return p }
            do {
                _ = try await client(WatchScripted([ServerResponse(status: 201, body: reply)])).createWatch(try fixtureDraft())
                XCTFail("\(current) is at or below 180000")
            } catch {
                XCTAssertEqual(error as? WatchError, .alreadyBelow(currentMinor: current))
            }
        }
        // One grosz above is a draft.
        let above = try previewData { var p = $0; p["currentMinor"] = 180_001; return p }
        let preview = try await client(WatchScripted([ServerResponse(status: 201, body: above)])).createWatch(try fixtureDraft())
        XCTAssertEqual(preview.currentMinor, 180_001)
    }

    func testADraftOutsideTheRulesIsNeverSent() async throws {
        let transport = WatchScripted([ServerResponse(status: 201, body: try previewData())])
        do {
            _ = try await client(transport).createWatch(draft(title: "", url: "http://x.pl", thresholdMinor: 0))
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? WatchError, .invalid(fields: ["title", "url", "thresholdMinor"]))
        }
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 0, "nothing leaves the phone for a draft the contract refuses")
    }

    func testCreateRefusalsAreTypedAndNothingIsRetried() async throws {
        func fails(_ expected: WatchError, _ responses: [ServerResponse], file: StaticString = #filePath, line: UInt = #line) async throws {
            let transport = WatchScripted(responses)
            do {
                _ = try await client(transport).createWatch(try fixtureDraft())
                XCTFail("expected \(expected)", file: file, line: line)
            } catch {
                XCTAssertEqual(error as? WatchError, expected, file: file, line: line)
            }
            let sent = await transport.sent
            XCTAssertEqual(sent.count, 1, "sent once, never again by itself", file: file, line: line)
        }
        func reply(_ status: Int, _ json: String = "{}") -> ServerResponse { ServerResponse(status: status, body: Data(json.utf8)) }
        try await fails(.priceNotReadable(.blocked), [reply(422, #"{"error":"price_not_readable","reason":"blocked"}"#)])
        try await fails(.currencyMismatch, [reply(422, #"{"error":"currency_mismatch"}"#)])
        try await fails(.alreadyBelow(currentMinor: 179_900), [reply(422, #"{"error":"already_below","currentMinor":179900}"#)])
        try await fails(.invalid(fields: ["url"]), [reply(400, #"{"error":"invalid_request","fields":["url"]}"#)])
        try await fails(.rateLimited, [reply(429, #"{"error":"rate_limited"}"#)])
        try await fails(.watchesDisabled, [reply(503, #"{"error":"watches_disabled"}"#)])
        try await fails(.server(.unexpected(status: 500)), [reply(500)])
        try await fails(.server(.unexpected(status: 201)), [reply(201, "<html>")])
        try await fails(.server(.accountMissing), [reply(401)])
        // No network: sent once, offline.
        try await fails(.server(.offline), [])
    }

    func testApproveSendsOnlyTheDigestToTheLowerCasedPath() async throws {
        let id = try XCTUnwrap(UUID(uuidString: "7D6C1F0E-2B8A-4C55-9A0E-3F4D5B6A7C81"))
        let body = Data(#"{"id":"7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81","state":"active","endsAt":"2026-11-23T12:02:30.000Z"}"#.utf8)
        let transport = WatchScripted([ServerResponse(status: 202, body: body)])
        let approval = try await client(transport).approveWatch(id, digest: "d1")
        XCTAssertEqual(approval, WatchApproval(id: id, state: .active, endsAt: try date("2026-11-23T12:02:30.000Z")))
        XCTAssertTrue(approval.isConfirmed)
        XCTAssertFalse(approval.isUnknown)
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].method, .post)
        XCTAssertEqual(sent[0].path, "/v1/watches/7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81/approve")
        XCTAssertEqual(sent[0].bearerToken, "t")
        let sentBody = try XCTUnwrap(JSONSerialization.jsonObject(with: sent[0].body ?? Data()) as? [String: String])
        XCTAssertEqual(sentBody, ["digest": "d1"])
    }

    func testAnApprovalWithoutATrustworthyAnswerIsUnknownNeverActive() async throws {
        let id = UUID()
        // The connection dropped after sending: it may have started.
        let dropped = try await client(WatchDropping()).approveWatch(id, digest: "d1")
        XCTAssertEqual(dropped, .unknown)
        XCTAssertTrue(dropped.isUnknown)
        XCTAssertFalse(dropped.isConfirmed)
        // A gateway error or a crash may have come after the server started it.
        for status in [500, 502, 504] {
            let answer = try await client(WatchScripted([ServerResponse(status: status)])).approveWatch(id, digest: "d1")
            XCTAssertTrue(answer.isUnknown, "\(status)")
        }
        // Accepted, but the reply can't be read, or is about another watch: not reported as active.
        let unreadable = try await client(WatchScripted([ServerResponse(status: 202, body: Data("<html>".utf8))])).approveWatch(id, digest: "d1")
        XCTAssertTrue(unreadable.isUnknown)
        let other = Data(#"{"id":"0b9e8d7c-6a5f-4e3d-8c2b-1a0f9e8d7c6b","state":"active"}"#.utf8)
        let elsewhere = try await client(WatchScripted([ServerResponse(status: 202, body: other)])).approveWatch(id, digest: "d1")
        XCTAssertTrue(elsewhere.isUnknown, "a yes for another watch isn't this watch's")
        // A state that isn't "active" isn't confirmation: one this app doesn't know is unknown, a known one is
        // what the server said (and the model asks the server before it says anything).
        let said = Data(#"{"id":"\#(id.uuidString.lowercased())","state":"paused"}"#.utf8)
        let notActive = try await client(WatchScripted([ServerResponse(status: 202, body: said)])).approveWatch(id, digest: "d1")
        XCTAssertFalse(notActive.isConfirmed)
        XCTAssertTrue(notActive.isUnknown)
        let triggeredAlready = Data(#"{"id":"\#(id.uuidString.lowercased())","state":"triggered"}"#.utf8)
        let early = try await client(WatchScripted([ServerResponse(status: 202, body: triggeredAlready)])).approveWatch(id, digest: "d1")
        XCTAssertFalse(early.isConfirmed, "only active is watching")
        XCTAssertFalse(early.isUnknown)
        XCTAssertEqual(early.state, .triggered)
        // Only the first request was sent: nothing is approved again by itself.
        let transport = WatchDropping()
        _ = try await client(transport).approveWatch(id, digest: "d1")
        let tries = await transport.tries
        XCTAssertEqual(tries, 1)
    }

    func testAnApprovalThatNeverLeftThePhoneIsOffline() async throws {
        do {
            _ = try await client(WatchScripted([])).approveWatch(UUID(), digest: "d1")
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? WatchError, .server(.offline))
        }
    }

    func testRefusedApprovalsSayNothingStarted() async throws {
        func refused(_ status: Int, _ json: String, _ expected: WatchError, file: StaticString = #filePath, line: UInt = #line) async {
            do {
                _ = try await client(WatchScripted([ServerResponse(status: status, body: Data(json.utf8))])).approveWatch(UUID(), digest: "d")
                XCTFail("expected \(expected)", file: file, line: line)
            } catch {
                XCTAssertEqual(error as? WatchError, expected, file: file, line: line)
            }
        }
        await refused(409, #"{"error":"digest_mismatch"}"#, .digestMismatch)
        await refused(409, #"{"error":"not_approvable","state":"active"}"#, .notApprovable(state: .active))
        await refused(409, #"{"error":"not_approvable","state":"draft"}"#, .notApprovable(state: .draft))
        await refused(409, #"{"error":"too_many_open_watches"}"#, .tooManyOpenWatches)
        await refused(404, #"{"error":"not_found"}"#, .notFound)
        await refused(503, #"{"error":"watches_disabled"}"#, .watchesDisabled)
        await refused(429, "{}", .rateLimited)
    }

    func testRefusalsMapToTheirCodes() {
        func reply(_ status: Int, _ json: String = "{}") -> ServerResponse { ServerResponse(status: status, body: Data(json.utf8)) }
        let cases: [(ServerResponse, WatchError)] = [
            (reply(400, #"{"error":"invalid_request","fields":["title","thresholdMinor"]}"#), .invalid(fields: ["title", "thresholdMinor"])),
            (reply(400), .invalid(fields: [])),
            (reply(404, #"{"error":"not_found"}"#), .notFound),
            (reply(409, #"{"error":"not_approvable","state":"active"}"#), .notApprovable(state: .active)),
            (reply(409, #"{"error":"not_approvable"}"#), .notApprovable(state: nil)),
            (reply(409, #"{"error":"not_approvable","state":"somethingnew"}"#), .notApprovable(state: .unknown)),
            (reply(409, #"{"error":"not_approvable","state":5}"#), .notApprovable(state: nil)),
            (reply(409, #"{"error":"digest_mismatch"}"#), .digestMismatch),
            (reply(409, #"{"error":"too_many_open_watches"}"#), .tooManyOpenWatches),
            (reply(409, #"{"error":"not_stoppable","state":"stopped"}"#), .notStoppable(state: .stopped)),
            (reply(409, #"{"error":"not_stoppable","state":"triggered"}"#), .notStoppable(state: .triggered)),
            (reply(409, #"{"error":"something_else"}"#), .conflict("something_else")),
            (reply(422, #"{"error":"price_not_readable","reason":"blocked"}"#), .priceNotReadable(.blocked)),
            (reply(422, #"{"error":"price_not_readable","reason":"not_allowed"}"#), .priceNotReadable(.notAllowed)),
            (reply(422, #"{"error":"price_not_readable","reason":"no_price"}"#), .priceNotReadable(.noPrice)),
            (reply(422, #"{"error":"price_not_readable","reason":"failed"}"#), .priceNotReadable(.failed)),
            (reply(422, #"{"error":"price_not_readable","reason":"a_new_reason"}"#), .priceNotReadable(.unknown)),
            (reply(422, #"{"error":"price_not_readable"}"#), .priceNotReadable(.unknown)),
            (reply(422, #"{"error":"currency_mismatch"}"#), .currencyMismatch),
            (reply(422, #"{"error":"already_below","currentMinor":179900}"#), .alreadyBelow(currentMinor: 179_900)),
            (reply(422, #"{"error":"already_below"}"#), .alreadyBelow(currentMinor: nil)),
            (reply(422, #"{"error":"something_else"}"#), .server(.unexpected(status: 422))),
            (reply(429), .rateLimited),
            (reply(429, #"{"error":"rate_limited"}"#), .rateLimited),
            (reply(503, #"{"error":"watches_disabled"}"#), .watchesDisabled),
            (reply(503, #"{"error":"maintenance"}"#), .server(.notConfigured("maintenance"))),
            (reply(500), .server(.unexpected(status: 500))),
            (reply(502), .server(.providerUnavailable)),
        ]
        for (response, expected) in cases {
            XCTAssertEqual(DoddyServerClient.watchError(from: response), expected, "\(response.status) \(String(decoding: response.body, as: UTF8.self))")
        }
    }

    func testListGetStopAndDeleteRoutes() async throws {
        let active = try summaryJSON("active")
        let triggered = try summaryJSON("triggered")
        let draftBody = Data(#"""
        {"id":"7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81","state":"draft","title":"T","shop":"S","url":"https://x.pl/p","thresholdMinor":100,
         "currency":"PLN","language":"pl","createdAt":"2026-10-24T12:02:30.000Z","expiresAt":"2026-10-24T12:12:30.000Z","checksDone":0}
        """#.utf8)
        let id = try XCTUnwrap(UUID(uuidString: "7D6C1F0E-2B8A-4C55-9A0E-3F4D5B6A7C81"))
        let lower = "7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81"
        let list = Data("{\"watches\":[".utf8) + triggered + Data(",".utf8) + active + Data("]}".utf8)
        let transport = WatchScripted([
            ServerResponse(status: 200, body: list),
            ServerResponse(status: 200, body: draftBody),
            ServerResponse(status: 204),
            ServerResponse(status: 204),
            ServerResponse(status: 404, body: Data(#"{"error":"not_found"}"#.utf8)),
        ])
        let server = client(transport)
        let watches = try await server.watches()
        XCTAssertEqual(watches.map(\.state), [.triggered, .active], "newest first, as the server sends them")
        let one = try await server.watch(id)
        XCTAssertEqual(one.state, .draft, "a draft reads as a draft")
        XCTAssertEqual(one.expiresAt, try date("2026-10-24T12:12:30.000Z"))
        try await server.stopWatch(id)
        try await server.deleteWatch(id)
        try await server.deleteWatch(id) // 404: the server holds no such watch, as asked

        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.method), [.get, .get, .post, .delete, .delete])
        XCTAssertEqual(sent.map(\.path), ["/v1/watches", "/v1/watches/\(lower)", "/v1/watches/\(lower)/stop", "/v1/watches/\(lower)", "/v1/watches/\(lower)"])
        XCTAssertTrue(sent.allSatisfy { $0.bearerToken == "t" })
        XCTAssertNil(sent[2].body, "stop has an empty body")
        XCTAssertNil(sent[3].body)
    }

    func testFailedCallsThrowWatchErrors() async throws {
        func reply(_ status: Int, _ json: String = "{}") -> ServerResponse { ServerResponse(status: status, body: Data(json.utf8)) }
        let id = UUID()
        func assertThrows(_ expected: WatchError, _ responses: [ServerResponse], file: StaticString = #filePath, line: UInt = #line,
                          _ body: (DoddyServerClient) async throws -> Void) async {
            do {
                try await body(client(WatchScripted(responses)))
                XCTFail("expected \(expected)", file: file, line: line)
            } catch {
                XCTAssertEqual(error as? WatchError, expected, file: file, line: line)
            }
        }
        await assertThrows(.notStoppable(state: .triggered), [reply(409, #"{"error":"not_stoppable","state":"triggered"}"#)]) { try await $0.stopWatch(id) }
        await assertThrows(.notFound, [reply(404, #"{"error":"not_found"}"#)]) { try await $0.stopWatch(id) }
        await assertThrows(.notFound, [reply(404, #"{"error":"not_found"}"#)]) { _ = try await $0.watch(id) }
        await assertThrows(.server(.unexpected(status: 500)), [reply(500)]) { try await $0.deleteWatch(id) }
        await assertThrows(.server(.unexpected(status: 200)), [reply(200, "not json")]) { _ = try await $0.watches() }
        await assertThrows(.server(.unexpected(status: 200)), [reply(200, #"{"watches":[{"id":"x"}]}"#)]) { _ = try await $0.watches() }
        await assertThrows(.watchesDisabled, [reply(503, #"{"error":"watches_disabled"}"#)]) { _ = try await $0.watches() }
        await assertThrows(.server(.offline), []) { try await $0.stopWatch(id) }
        await assertThrows(.server(.offline), []) { try await $0.deleteWatch(id) }
        await assertThrows(.server(.accountMissing), [reply(401)]) { _ = try await $0.watch(id) }
    }
}

private actor WatchScripted: ServerTransport {
    private var responses: [ServerResponse]
    private(set) var sent: [ServerRequest] = []
    init(_ responses: [ServerResponse]) { self.responses = responses }
    func send(_ request: ServerRequest) async throws -> ServerResponse {
        sent.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

/// The connection drops after sending, every time: the request may have reached the server.
private actor WatchDropping: ServerTransport {
    private(set) var tries = 0
    func send(_ request: ServerRequest) async throws -> ServerResponse {
        tries += 1
        throw URLError(.networkConnectionLost)
    }
}

private final class WatchCredentials: ServerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    init(token: String?) { self.token = token }
    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}
