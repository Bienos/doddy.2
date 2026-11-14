import Foundation
import XCTest
@testable import DoddyCore

final class PolandPackTests: XCTestCase {
    func testCitySelectionUsesFixedPolishStationsAndTERYT() {
        XCTAssertEqual(PolandCity.allCases.count, 5)
        XCTAssertEqual(PolandCity.warszawa.name, "Warszawa")
        XCTAssertEqual(PolandCity.warszawa.synopStation, "warszawa")
        XCTAssertEqual(PolandCity.warszawa.countyTERYT, "1465")
        XCTAssertEqual(PolandCity.wroclaw.countyTERYT, "0264")
        XCTAssertEqual(PolandOpenData.weatherURL(city: .gdansk).host, "danepubliczne.imgw.pl")
    }

    func testOfficialIMGWMeasurementPreservesMissingValues() throws {
        let json = #"{"stacja":"Warszawa","data_pomiaru":"2026-11-11","godzina_pomiaru":"16","temperatura":"2.1","predkosc_wiatru":"2","wilgotnosc_wzgledna":"91.7","suma_opadu":null}"#
        let weather = try JSONDecoder().decode(PolandWeather.self, from: Data(json.utf8))
        XCTAssertEqual(weather.station, "Warszawa")
        XCTAssertEqual(weather.temperatureCelsius, 2.1)
        XCTAssertEqual(weather.wind, 2)
        XCTAssertEqual(weather.observedAt, "2026-11-11 16:00")
        XCTAssertNil(weather.precipitation)
    }

    func testIMGWWarningsNoWarningsAndCountyFilter() throws {
        let noWarnings = Data(#"{"message":"Brak ostrzeżeń meteorologicznych"}"#.utf8)
        XCTAssertEqual(try PolandWarnings.parse(noWarnings, city: .warszawa), .noWarningsInPoland)

        let alerts = Data(#"""
        [
          {"nazwa_zdarzenia":"Burze","stopien":"2","tresc":"Burze","teryt":["146501"],"obowiazuje_do":"2026-11-12"},
          {"nazwa_zdarzenia":"Mróz","stopien":"1","teryt":["026401"]}
        ]
        """#.utf8)
        switch try PolandWarnings.parse(alerts, city: .warszawa) {
        case .matching(let items):
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items[0].event, "Burze")
        default:
            XCTFail("Must match the selected city's county code")
        }
        switch try PolandWarnings.parse(alerts, city: .poznan) {
        case .locationNotVerified: break
        default: XCTFail("Do not claim no warning if only other counties were returned")
        }
        let unspecified = Data(#"[{"nazwa_zdarzenia":"Silny wiatr"}]"#.utf8)
        XCTAssertEqual(try PolandWarnings.parse(unspecified, city: .warszawa), .locationNotVerified)
    }

    func testGIOSUsesVersionedEndpointAndPolishResponseKeys() throws {
        XCTAssertTrue(PolandOpenData.airStationsURL.absoluteString.contains("/pjp-api/v1/"))
        let stationJSON = Data(#"""
        {"Lista stacji pomiarowych":[
          {"Identyfikator stacji":552,"Nazwa miasta":"Warszawa","Nazwa stacji":"Warszawa, Kondratowicza"},
          {"Identyfikator stacji":129,"Nazwa miasta":"Wrocław","Nazwa stacji":"Wrocław, Wiśniowa"}
        ],"totalPages":1}
        """#.utf8)
        let station = try XCTUnwrap(PolandAirStation.find(in: stationJSON, city: .warszawa))
        XCTAssertEqual(station.id, 552)
        XCTAssertEqual(station.city, "Warszawa")
        XCTAssertEqual(try PolandAirStation.find(in: stationJSON, city: .gdansk), nil)
        XCTAssertNil(PolandOpenData.airIndexURL(stationID: -1))
        XCTAssertTrue(try XCTUnwrap(PolandOpenData.airIndexURL(stationID: 552)).absoluteString.hasSuffix("/552"))
    }

    func testGIOSUnavailableIndexIsNotPresentedAsGood() throws {
        let good = Data(#"{"AqIndex":{"Wartość indeksu":1,"Nazwa kategorii indeksu":"Dobry"}}"#.utf8)
        XCTAssertEqual(try PolandAirIndex.parse(good, station: "Warszawa")?.category, "Dobry")
        let unknown = Data(#"{"AqIndex":{"Wartość indeksu":-1,"Nazwa kategorii indeksu":"Brak indeksu"}}"#.utf8)
        XCTAssertNil(try PolandAirIndex.parse(unknown, station: "Warszawa"))
    }

    func testNBPRatesAreOfficialAndNotFabricated() throws {
        let json = Data(#"{"code":"EUR","rates":[{"effectiveDate":"2026-11-10","mid":4.1234}]}"#.utf8)
        let rate = try JSONDecoder().decode(PolandExchangeRate.self, from: json)
        XCTAssertEqual(rate.latest?.effectiveDate, "2026-11-10")
        XCTAssertEqual(rate.pln(for: 100), 412.34)
        XCTAssertNil(rate.pln(for: -50))
        XCTAssertNil(rate.pln(for: 1000001))
        XCTAssertEqual(PolandOpenData.exchangeRateURL("EUR")?.host, "api.nbp.pl")
        XCTAssertNil(PolandOpenData.exchangeRateURL("../../secret"))
    }

    func testInPostTracksOnlyExplicitValidNumbers() throws {
        let number = "873234987612340872938732"
        let url = try XCTUnwrap(PolandParcel.trackingURL(number: number))
        XCTAssertEqual(url.host, "inpost.pl")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, number)
        XCTAssertNil(PolandParcel.trackingURL(number: "123"))
        XCTAssertNil(PolandParcel.trackingURL(number: "87323498761234087293873a"))
        XCTAssertNil(PolandParcel.trackingURL(number: "873234987612340872938732&evil=1"))
        XCTAssertEqual(PolandParcel.lockerFinder.host, "inpost.pl")
    }
}
