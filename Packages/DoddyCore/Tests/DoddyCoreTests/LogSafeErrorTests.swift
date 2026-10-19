import XCTest
@testable import DoddyCore

final class LogSafeErrorTests: XCTestCase {
    private enum Sample: Error {
        case plain
        case withText(String)
        case withLabel(address: String)
    }

    private struct Described: Error, CustomStringConvertible {
        var description: String { "wss://example.invalid/rtc?access_token=SECRET" }
    }

    private enum DescribedEnum: Error, CustomStringConvertible {
        case only
        var description: String { "token SECRET" }
    }

    func testEnumCasesGiveTheirNameButNeverTheirValues() {
        XCTAssertEqual(LogSafeError.kind(of: Sample.plain), "Sample.plain")
        XCTAssertEqual(LogSafeError.kind(of: Sample.withText("wss://x/?access_token=SECRET")), "Sample.withText")
        XCTAssertEqual(LogSafeError.kind(of: Sample.withLabel(address: "SECRET")), "Sample.withLabel")
    }

    func testNonEnumErrorsAndSelfDescribingErrorsGiveTheTypeOnly() {
        XCTAssertEqual(LogSafeError.kind(of: Described()), "Described")
        XCTAssertEqual(LogSafeError.kind(of: DescribedEnum.only), "DescribedEnum")
        XCTAssertEqual(LogSafeError.kind(of: URLError(.timedOut)), "URLError")
    }

    func testVoiceTokenErrorsLogTheirCase() {
        XCTAssertEqual(LogSafeError.kind(of: VoiceTokenError.busy), "VoiceTokenError.busy")
        XCTAssertEqual(LogSafeError.kind(of: VoiceTokenError.serverProblem(status: 418)), "VoiceTokenError.serverProblem")
    }

    func testNothingSecretEverAppears() {
        let errors: [any Error] = [Sample.withText("SECRET"), Sample.withLabel(address: "SECRET"), Described(), DescribedEnum.only]
        for error in errors { XCTAssertFalse(LogSafeError.kind(of: error).contains("SECRET"), "\(type(of: error))") }
    }
}
