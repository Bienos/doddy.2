import XCTest
@testable import DoddyCore

final class CurrencyTests: XCTestCase {
    static let ecb = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
    \t<gesmes:subject>Reference rates</gesmes:subject>
    \t<Cube>
    \t\t<Cube time='2026-10-09'>
    \t\t\t<Cube currency='USD' rate='1.0800'/>
    \t\t\t<Cube currency='JPY' rate='160.50'/>
    \t\t\t<Cube currency='GBP' rate='0.8400'/>
    \t\t\t<Cube currency='PLN' rate='4.2860'/>
    \t\t\t<Cube currency='CHF' rate='0.9400'/>
    \t\t\t<Cube currency='HUF' rate='395.10'/>
    \t\t</Cube>
    \t</Cube>
    </gesmes:Envelope>
    """

    func testReadsTheECBFile() throws {
        let rates = try XCTUnwrap(ExchangeRateSource.parse(Self.ecb))
        XCTAssertEqual(rates.date, "2026-10-09")
        XCTAssertEqual(rates.perEuro["PLN"], 4.286)
        XCTAssertEqual(rates.perEuro["EUR"], 1)
        XCTAssertEqual(rates.codes.first, "CHF")
    }

    func testAnythingElseIsNotRates() {
        XCTAssertNil(ExchangeRateSource.parse("<html>Service unavailable</html>"))
        XCTAssertNil(ExchangeRateSource.parse("<Cube currency='USD' rate='1.08'/>"), "no date")
        XCTAssertNil(ExchangeRateSource.parse(Self.ecb.replacingOccurrences(of: "rate='1.0800'", with: "rate='0'")), "a zero rate")
        XCTAssertNil(ExchangeRateSource.parse("<Cube time='2026-10-09'><Cube currency='USD' rate='1.08'/></Cube>"), "too few rates")
    }

    func testConvertsThroughTheEuro() throws {
        let rates = try XCTUnwrap(ExchangeRateSource.parse(Self.ecb))
        let toZloty = try CurrencyConversion.convert(CurrencyConversionRequest(amount: 50, from: "eur", to: "PLN"), rates: rates).get()
        XCTAssertEqual(toZloty.converted, 214.3, accuracy: 0.0001)
        let dollarsToPounds = try CurrencyConversion.convert(CurrencyConversionRequest(amount: 108, from: "USD", to: "pounds"), rates: rates).get()
        XCTAssertEqual(dollarsToPounds.converted, 84, accuracy: 0.0001)
        XCTAssertEqual(dollarsToPounds.to, "GBP")
        XCTAssertEqual(CurrencyConversion.money(1234.5, "JPY"), "1235 JPY")
        XCTAssertEqual(CurrencyConversion.money(9.999, "PLN"), "10.00 PLN")
    }

    func testNeverGuesses() throws {
        let rates = try XCTUnwrap(ExchangeRateSource.parse(Self.ecb))
        XCTAssertEqual(CurrencyConversion.convert(CurrencyConversionRequest(amount: 5, from: "dollar", to: "PLN"), rates: rates), .failure(.unknownCurrency("DOLLAR")))
        XCTAssertEqual(CurrencyConversion.convert(CurrencyConversionRequest(amount: -5, from: "EUR", to: "PLN"), rates: rates), .failure(.negative))
        let none = VoiceToolReply.currency(CurrencyConversionRequest(amount: 5, from: "EUR", to: "PLN"), rates: nil, isLastKnown: false)
        XCTAssertTrue(none.hasPrefix("failed:"))
        XCTAssertTrue(none.contains("Don't guess"))
    }

    func testTheAnswerGivesTheDateAndSaysWhenRatesAreOld() throws {
        let rates = try XCTUnwrap(ExchangeRateSource.parse(Self.ecb))
        let request = CurrencyConversionRequest(amount: 50, from: "EUR", to: "PLN")
        let fresh = VoiceToolReply.currency(request, rates: rates, isLastKnown: false)
        XCTAssertTrue(fresh.hasPrefix("converted: 50.00 EUR = 214.30 PLN"), fresh)
        XCTAssertTrue(fresh.contains("2026-10-09"))
        XCTAssertTrue(fresh.contains("1 EUR = 4.2860 PLN"))
        XCTAssertFalse(fresh.contains("last rates"))
        XCTAssertTrue(VoiceToolReply.currency(request, rates: rates, isLastKnown: true).contains("last rates the app has"))
    }

    func testRefreshEverySixHoursAndAfterAClockChange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ExchangeRateSource.needsRefresh(fetchedAt: nil, now: now))
        XCTAssertFalse(ExchangeRateSource.needsRefresh(fetchedAt: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(ExchangeRateSource.needsRefresh(fetchedAt: now.addingTimeInterval(-7 * 3600), now: now))
        XCTAssertTrue(ExchangeRateSource.needsRefresh(fetchedAt: now.addingTimeInterval(3600), now: now))
    }

    func testToolCall() {
        let json = Data(#"{"amount": 49.99, "from": "EUR", "to": "PLN"}"#.utf8)
        XCTAssertEqual(VoiceToolRequest.parse(name: "convert_currency", parametersJSON: json),
                       .convertCurrency(CurrencyConversionRequest(amount: 49.99, from: "EUR", to: "PLN")))
        if case .invalid = VoiceToolRequest.parse(name: "convert_currency", parametersJSON: Data(#"{"amount": 5}"#.utf8)) {} else {
            XCTFail("from and to are required")
        }
        XCTAssertTrue(ConnectionPause.applies(to: .convertCurrency(CurrencyConversionRequest(amount: 1, from: "EUR", to: "PLN"))))
    }
}
