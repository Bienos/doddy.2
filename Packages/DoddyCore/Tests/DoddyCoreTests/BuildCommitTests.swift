import XCTest
@testable import DoddyCore

/// The commit in Settings › About (7 Nov 2026 audit): only a real commit is shown, in its short form.
final class BuildCommitTests: XCTestCase {
    func testAFullCommitShowsItsFirstSevenCharacters() {
        XCTAssertEqual(BuildCommit.short("8f3c2a1d9b7e6f5a4c3b2a1908f7e6d5c4b3a291"), "8f3c2a1")
        XCTAssertEqual(BuildCommit.short("8f3c2a1"), "8f3c2a1")
        XCTAssertEqual(BuildCommit.short(" 8f3c2a1d\n"), "8f3c2a1", "whitespace around it is ignored")
    }

    func testABuildMadeElsewhereShowsNoCommit() {
        XCTAssertNil(BuildCommit.short("local"))
        XCTAssertNil(BuildCommit.short("$(DODDY_GIT_COMMIT)"), "the setting wasn't expanded")
        XCTAssertNil(BuildCommit.short(""))
        XCTAssertNil(BuildCommit.short(nil))
    }

    func testAnythingThatIsNotACommitShowsNothing() {
        XCTAssertNil(BuildCommit.short("8f3c2a"), "too short")
        XCTAssertNil(BuildCommit.short(String(repeating: "a", count: 41)), "too long")
        XCTAssertNil(BuildCommit.short("8F3C2A1D"), "git writes lowercase")
        XCTAssertNil(BuildCommit.short("8f3c2a1g"), "not hex")
        XCTAssertNil(BuildCommit.short("８f3c2a1d"), "a fullwidth digit isn't ASCII")
    }

    func testTheVersionLine() {
        XCTAssertEqual(BuildCommit.versionText(version: "0.1.0", build: "12", commit: "8f3c2a1d9b7e"), "0.1.0 (12, 8f3c2a1)")
        XCTAssertEqual(BuildCommit.versionText(version: "0.1.0", build: "12", commit: "local"), "0.1.0 (12)", "as before")
        XCTAssertEqual(BuildCommit.versionText(version: nil, build: nil, commit: nil), "? (?)")
    }
}
