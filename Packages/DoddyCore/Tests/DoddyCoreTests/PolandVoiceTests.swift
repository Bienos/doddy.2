import Foundation
import XCTest
@testable import DoddyCore

final class PolandVoiceTests: XCTestCase {
    private let tool = VoiceToolName.getPolandInfo

    func testPolishAliasesResolveOnlySupportedCities() {
        XCTAssertEqual(PolishContext.city("Wawa"), .warszawa)
        XCTAssertEqual(PolishContext.city("w Warszawie"), .warszawa)
        XCTAssertEqual(PolishContext.city("w Krakowie"), .krakow)
        XCTAssertEqual(PolishContext.city("we Wrocławiu"), .wroclaw)
        XCTAssertEqual(PolishContext.city("w Gdańsku"), .gdansk)
        XCTAssertEqual(PolishContext.city("w Poznaniu"), .poznan)
        XCTAssertEqual(PolishContext.city("Kraków"), .krakow)
        XCTAssertEqual(PolishContext.city("Gdansk"), .gdansk)
        XCTAssertEqual(PolishContext.city("Wrocław"), .wroclaw)
        XCTAssertEqual(PolishContext.city("Poznań"), .poznan)
        XCTAssertNil(PolishContext.city("Berlin"))
        XCTAssertNil(PolishContext.city("Warszawa.cz"))
        XCTAssertEqual(PolishContext.topic("jakość powietrza"), .air)
        XCTAssertEqual(PolishContext.topic("smog"), .air)
        XCTAssertEqual(PolishContext.topic("burze"), .warnings)
        XCTAssertEqual(PolishContext.topic("Kursy"), .rates)
        XCTAssertNil(PolishContext.topic("kup mi bilet"))
    }

    func testVoiceRequestIsStrictAndDoesNotGuessCity() {
        XCTAssertEqual(VoiceToolRequest.parse(
            name: tool, parametersJSON: Data(#"{"topic":"air","city":"Wawa"}"#.utf8)),
            .polandInfo(PolandVoiceRequest(topic: "air", city: "Warszawa")!))
        XCTAssertEqual(VoiceToolRequest.parse(
            name: tool, parametersJSON: Data(#"{"topic":"rates"}"#.utf8)),
            .polandInfo(PolandVoiceRequest(topic: "rates", city: nil)!))
        for bad in [
            #"{}"#,
            #"{"topic":"weather"}"#,
            #"{"topic":"warnings","city":"Praga"}"#,
            #"{"topic":"air","city":"Berlin"}"#,
            #"{"topic":"prices","city":"Warszawa"}"#
        ] {
            guard case .invalid = VoiceToolRequest.parse(name: tool, parametersJSON: Data(bad.utf8)) else {
                return XCTFail("Invalid official-data request accepted: \(bad)")
            }
        }
    }

    func testOfficialLookupRequiresApprovalAndHonorsPause() {
        let request = VoiceToolRequest.polandInfo(PolandVoiceRequest(topic: "weather", city: "Warszawa")!)
        guard case .yesFirst(let card) = AskFirst.need(for: request, polish: true) else {
            return XCTFail("Official public-data lookup must ask first")
        }
        XCTAssertTrue(card.title.contains("polskie"))
        XCTAssertTrue(ConnectionPause.applies(to: request))
        XCTAssertEqual(CarProfile.decision(for: request), .run)
        XCTAssertEqual(ToolCatalog.descriptor(tool)?.effect, .lookup)
        XCTAssertEqual(ToolCatalog.descriptor(tool)?.approval, .askFirst)
        XCTAssertEqual(ToolGate.decide(toolName: tool, request: request, translatorOn: false,
                                       pauseAll: true, isOn: { _ in true }), .paused)
        XCTAssertEqual(ToolGate.decide(toolName: tool, request: request, translatorOn: false,
                                       pauseAll: false, isOn: { _ in true }), .run)
        let activity = ActivityRequest.describe(request, calendar: .current)
        XCTAssertEqual(activity?.title, "Checked Polish public data")
        XCTAssertTrue(activity?.detail?.contains("Warszawa") == true)
    }

    func testVoiceRatesDoNotRequireLocation() {
        let request = PolandVoiceRequest(topic: "rates", city: nil)
        XCTAssertEqual(request?.topic, .rates)
        XCTAssertNil(request?.city)
        XCTAssertNil(PolandVoiceRequest(topic: "warnings", city: nil))
        XCTAssertNil(PolandVoiceRequest(topic: "weather", city: ""))
        XCTAssertNil(PolandVoiceRequest(topic: "air", city: "somewhere nearby"))
        XCTAssertNil(PolandVoiceRequest(topic: "rates", city: "New York"))
    }

    func testNoNewGatedUserDataOrPaymentCapability() {
        XCTAssertFalse(AskFirst.publicLookups.contains(tool))
        XCTAssertFalse(CloudToolName.all.contains(tool))
        XCTAssertNil(VoiceConnection.serving(tool))
        XCTAssertFalse(PlanTool.allowed.contains(tool))
        XCTAssertEqual(PolandOpenData.weatherURL(city: .warszawa).host, "danepubliczne.imgw.pl")
        XCTAssertEqual(PolandOpenData.exchangeRateURL("EUR")?.host, "api.nbp.pl")
    }
}
