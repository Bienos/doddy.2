@testable import DoddyCore
import XCTest

/// Plans (owner, 22 Oct 2026): paid versions are bought on the website, so the app shows what each
/// plan includes and opens a link that carries only the plan, "from the app" and the language.
final class PlansTests: XCTestCase {
    func testTheOwnersSketchIsPinned() {
        XCTAssertEqual(PlanCatalog.proposal.map(\.tier), [.free, .plus, .pro])
        XCTAssertEqual(PlanCatalog.proposal.map(\.studioReportsPerMonth), [2, 6, 8])
        XCTAssertEqual(PlanCatalog.proposal.map(\.researchDepth), [.simple, .balanced, .careful])
        XCTAssertEqual(PlanCatalog.offer(for: .plus).studioReportsPerMonth, 6)
        XCTAssertEqual(PlanTier.allCases.filter(\.isPaid), [.plus, .pro])
    }

    func testExportDeleteAndBackupAreNeverLimited() {
        XCTAssertEqual(PlanCatalog.neverLimited, ["export", "delete", "backup"])
    }

    func testTheLinkCarriesOnlyThePlanTheAppAndTheLanguage() throws {
        let plus = try XCTUnwrap(PlanLink.url(base: "https://example.org/plans", tier: .plus, language: "pl"))
        XCTAssertEqual(plus.absoluteString, "https://example.org/plans?plan=plus&from=app&lang=pl")
        let any = try XCTUnwrap(PlanLink.url(base: "https://example.org/plans", tier: nil, language: "en"))
        XCTAssertEqual(any.absoluteString, "https://example.org/plans?from=app&lang=en")
    }

    func testAnExistingPlanFromOrLangIsReplacedAndOtherItemsAreKept() throws {
        let url = try XCTUnwrap(PlanLink.url(base: "https://example.org/plans?utm=x&plan=pro&from=web", tier: .plus, language: "en"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.filter { $0.name == "plan" }.map(\.value), ["plus"])
        XCTAssertEqual(items.filter { $0.name == "from" }.map(\.value), ["app"])
        XCTAssertTrue(items.contains { $0.name == "utm" && $0.value == "x" })
    }

    func testNoAddressPlainHttpALoginInTheAddressOrNoHostGivesNoLink() {
        XCTAssertNil(PlanLink.url(base: nil, tier: .plus, language: "en"))
        XCTAssertNil(PlanLink.url(base: "", tier: .plus, language: "en"))
        XCTAssertNil(PlanLink.url(base: "  ", tier: .plus, language: "en"))
        XCTAssertNil(PlanLink.url(base: "http://example.org/plans", tier: .plus, language: "en"))
        XCTAssertNil(PlanLink.url(base: "https://user:pw@example.org/plans", tier: .plus, language: "en"))
        XCTAssertNil(PlanLink.url(base: "https:///plans", tier: .plus, language: "en"))
        XCTAssertNil(PlanLink.url(base: "javascript:alert(1)", tier: .plus, language: "en"))
    }

    func testAStrangeLanguageCodeIsDroppedNotSent() throws {
        let odd = try XCTUnwrap(PlanLink.url(base: "https://example.org/p", tier: nil, language: "p l!&x=1"))
        XCTAssertFalse((odd.query ?? "").contains("&x=1"))
        let none = try XCTUnwrap(PlanLink.url(base: "https://example.org/p", tier: nil, language: ""))
        XCTAssertEqual(none.absoluteString, "https://example.org/p?from=app")
    }
}
