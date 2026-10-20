import XCTest
@testable import DoddyCore

final class OpenDoddyWaysTests: XCTestCase {
    private func ways(isPhone: Bool = true, controls: Bool = true, actionButton: ActionButtonSupport = .yes) -> [OpenDoddyWay] {
        OpenDoddyWays.available(on: OpenDoddyDevice(isPhone: isPhone, supportsControls: controls, actionButton: actionButton))
    }

    func testAnIPhoneWithEverythingShowsAllFourInOrderWithSiriLast() {
        XCTAssertEqual(ways(), [.backTap, .actionButton, .control, .siri])
    }

    func testAnIPhoneWithoutAnActionButtonIsNotOfferedOne() {
        XCTAssertEqual(ways(actionButton: .no), [.backTap, .control, .siri])
    }

    func testAnUnknownModelStillShowsTheActionButtonWayBecauseItMayExist() {
        XCTAssertEqual(ways(actionButton: .unknown), [.backTap, .actionButton, .control, .siri])
    }

    func testControlsNeedIOS18() {
        XCTAssertEqual(ways(controls: false), [.backTap, .actionButton, .siri])
    }

    func testAnIPadHasNeitherBackTapNorAnActionButtonEvenIfTheModelSaysYes() {
        XCTAssertEqual(ways(isPhone: false, actionButton: .yes), [.control, .siri])
        XCTAssertEqual(ways(isPhone: false, controls: false, actionButton: .no), [.siri])
    }

    func testSiriIsAlwaysThereAndIsTheOnlyWayWithNothingToSetUp() {
        XCTAssertEqual(OpenDoddyWay.allCases.filter { !$0.needsSetup }, [.siri])
        XCTAssertTrue(ways(isPhone: false, controls: false, actionButton: .no).contains(.siri))
    }

    func testTheActionButtonStartsWithTheIPhone15Pro() {
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone16,1"), .yes, "iPhone 15 Pro")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone16,2"), .yes, "iPhone 15 Pro Max")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone17,3"), .yes, "iPhone 16")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone17,5"), .yes, "iPhone 16e")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone18,1"), .yes, "a later model keeps it")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone100,1"), .yes, "three-digit numbers are read whole")
    }

    func testEarlierIPhonesAndTheIPhone15HaveNone() {
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone15,4"), .no, "iPhone 15")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone15,5"), .no, "iPhone 15 Plus")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone14,7"), .no, "iPhone 14")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone9,1"), .no, "iPhone 7")
    }

    func testAnUnreadableModelIsUnknownNotNo() {
        XCTAssertEqual(ActionButtonSupport.forModel(nil), .unknown)
        XCTAssertEqual(ActionButtonSupport.forModel(""), .unknown)
        XCTAssertEqual(ActionButtonSupport.forModel("arm64"), .unknown, "a simulator's own architecture")
        XCTAssertEqual(ActionButtonSupport.forModel("iPhone"), .unknown)
        XCTAssertEqual(ActionButtonSupport.forModel("iPad16,3"), .unknown, "not an iPhone: the iPhone rule doesn't apply")
    }
}
