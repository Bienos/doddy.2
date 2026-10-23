import XCTest
@testable import DoddyCore

final class SignInOptionTests: XCTestCase {
    func testThreeOptionsInTheOrderTheSheetShowsThem() {
        XCTAssertEqual(SignInOption.allCases, [.faceID, .google, .email])
    }

    func testTheUnconnectedProviderNeverReportsASignIn() async {
        // The sign-in screens exist but nothing is connected (ADR-595). No option may look like a
        // success until the sign-in milestone builds a real one.
        let provider: SignInProviding = UnconnectedSignIn()
        for option in SignInOption.allCases {
            let outcome = await provider.signIn(with: option)
            XCTAssertEqual(outcome, .notConnectedYet, "\(option) must not claim to sign anyone in")
            XCTAssertNotEqual(outcome, .signedIn)
        }
    }
}
