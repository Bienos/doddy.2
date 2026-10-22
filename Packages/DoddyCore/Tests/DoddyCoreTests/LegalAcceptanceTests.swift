@testable import DoddyCore
import XCTest

/// ADR-581: the Terms are accepted once, by an explicit tap, and again only when they change.
final class LegalAcceptanceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_792_000_000)

    func testNobodyHasAcceptedUntilTheyTap() {
        XCTAssertTrue(LegalAcceptance.isNeeded(nil))
        XCTAssertTrue(LegalAcceptance.isNeeded(LegalAcceptance.decode(nil)))
        XCTAssertTrue(LegalAcceptance.isNeeded(LegalAcceptance.decode(Data("not json".utf8))), "a damaged record never counts")
    }

    func testAcceptingRecordsTheCurrentVersionsTimeAndSource() {
        let record = LegalAcceptance.accept(at: date, source: .onboarding)
        XCTAssertEqual(record.termsVersion, LegalDocuments.termsVersion)
        XCTAssertEqual(record.privacyVersion, LegalDocuments.privacyVersion)
        XCTAssertEqual(record.acceptedAt, date)
        XCTAssertEqual(record.source, .onboarding)
        XCTAssertFalse(LegalAcceptance.isNeeded(record))
    }

    func testTheRecordSurvivesStorage() throws {
        let record = LegalAcceptance.accept(at: date, source: .updatedTerms)
        let data = try XCTUnwrap(LegalAcceptance.encode(record))
        XCTAssertEqual(LegalAcceptance.decode(data), record)
    }

    func testATapAtAnyMomentReadsBackEqual() throws {
        // The app stores the record and compares the read-back before it says accepted.
        let record = LegalAcceptance.accept(at: date.addingTimeInterval(0.734), source: .onboarding)
        XCTAssertEqual(LegalAcceptance.decode(try XCTUnwrap(LegalAcceptance.encode(record))), record)
        XCTAssertEqual(record.acceptedAt, date, "kept to the whole second")
    }

    func testAMaterialChangeToTheTermsAsksAgain() {
        let old = LegalAcceptanceRecord(termsVersion: "2026-10-22", privacyVersion: "2026-10-22", acceptedAt: date, source: .onboarding)
        XCTAssertTrue(LegalAcceptance.isNeeded(old, minimumTerms: "2027-01-15", minimumPrivacy: "2026-10-22"))
        XCTAssertTrue(LegalAcceptance.isNeeded(old, minimumTerms: "2026-10-22", minimumPrivacy: "2027-01-15"))
        XCTAssertFalse(LegalAcceptance.isNeeded(old, minimumTerms: "2026-10-22", minimumPrivacy: "2026-10-22"),
                       "a newer wording that keeps the minimum doesn't ask again")
    }

    func testPeopleWhoUsedDoddyBeforeSeeTheUpdatedWording() {
        XCTAssertEqual(LegalAcceptance.source(hasUsedDoddyBefore: false, previous: nil), .onboarding)
        XCTAssertEqual(LegalAcceptance.source(hasUsedDoddyBefore: true, previous: nil), .updatedTerms)
        let old = LegalAcceptanceRecord(termsVersion: "2026-01-01", privacyVersion: "2026-01-01", acceptedAt: date, source: .onboarding)
        XCTAssertEqual(LegalAcceptance.source(hasUsedDoddyBefore: false, previous: old), .updatedTerms)
    }

    func testTheMinimumsNeverRunAheadOfTheDocuments() {
        XCTAssertLessThanOrEqual(LegalDocuments.minimumTermsVersion, LegalDocuments.termsVersion)
        XCTAssertLessThanOrEqual(LegalDocuments.minimumPrivacyVersion, LegalDocuments.privacyVersion)
    }

    func testPolishGetsThePolishPagesAndEveryoneElseTheEnglish() {
        XCTAssertEqual(LegalDocuments.url(.terms, languageCode: "pl").absoluteString, "https://www.doddy.lol/pl/terms/")
        XCTAssertEqual(LegalDocuments.url(.privacy, languageCode: "pl-PL").absoluteString, "https://www.doddy.lol/pl/privacy/")
        XCTAssertEqual(LegalDocuments.url(.terms, languageCode: "de").absoluteString, "https://www.doddy.lol/terms/")
        XCTAssertEqual(LegalDocuments.url(.privacy, languageCode: nil).absoluteString, "https://www.doddy.lol/privacy/")
    }
}
