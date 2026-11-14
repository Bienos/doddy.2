import Foundation
import XCTest
@testable import DoddyCore

final class FoodAppsTests: XCTestCase {
    func testTheAppsAreListedInOrderWithTheirOwnHosts() {
        let hosts = Dictionary(uniqueKeysWithValues: FoodApps.all.map { ($0.id, $0.url.host ?? "") })
        XCTAssertEqual(FoodApps.all.map(\.id), ["ubereats", "wolt", "glovo", "bolt", "pyszne"])
        XCTAssertEqual(hosts["ubereats"], "www.ubereats.com")
        XCTAssertEqual(hosts["wolt"], "wolt.com")
        XCTAssertEqual(hosts["glovo"], "glovoapp.com")
        XCTAssertEqual(hosts["bolt"], "food.bolt.eu")
        XCTAssertEqual(hosts["pyszne"], "www.pyszne.pl")
    }

    func testEveryRowOpensAnHTTPSPageAndNothingElse() {
        for app in FoodApps.all {
            XCTAssertTrue(app.isOpenable, app.name)
            XCTAssertEqual(app.url.scheme, "https", app.name)
            XCTAssertNil(app.url.query, "\(app.name): no search or tracking is passed in")
            XCTAssertFalse(app.name.isEmpty)
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(FoodApps.all.map(\.id)).count, FoodApps.all.count)
    }

    func testAnAddressThatIsNotHTTPSIsNotOpenable() {
        XCTAssertFalse(FoodApp(id: "x", name: "X", url: URL(string: "http://example.com")!).isOpenable)
        XCTAssertFalse(FoodApp(id: "x", name: "X", url: URL(string: "ubereats://")!).isOpenable)
        XCTAssertFalse(FoodApp(id: "x", name: "X", url: URL(string: "https://")!).isOpenable)
        XCTAssertFalse(FoodApp(id: "x", name: "X", url: URL(fileURLWithPath: "/")).isOpenable)
    }
}
