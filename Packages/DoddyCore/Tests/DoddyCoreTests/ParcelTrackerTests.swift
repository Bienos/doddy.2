import XCTest
@testable import DoddyCore

/// A scripted InPost. It counts how often it was asked.
private actor FakeFetcher: ParcelFetching {
    private let result: ParcelFetch
    private(set) var asked: [String] = []
    init(_ result: ParcelFetch) { self.result = result }
    func fetch(_ number: ParcelNumber) async -> ParcelFetch {
        asked.append(number.digits)
        return result
    }
}

/// Looking a parcel up (ADR-641): only the person's own act starts one, the answer is read by HTTP code,
/// and whatever can't be read leaves the last known status alone.
final class ParcelTrackerTests: XCTestCase {
    private let number = ParcelNumber("632085946340007012341234")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reply(_ json: String, code: Int = 200) -> ParcelFetch { .reply(Data(json.utf8), statusCode: code) }

    private let delivered = #"{"tracking_number":"632085946340007012341234","status":"delivered","tracking_details":[]}"#
    private let inTransit = #"{"tracking_number":"632085946340007012341234","status":"sent_from_source_branch","tracking_details":[]}"#

    func testWhatThePersonDidStartsALookUpAndAParcelIsShown() async {
        let fetcher = FakeFetcher(reply(delivered))
        let result = await ParcelTracker(fetcher: fetcher).lookup(number, trigger: .personAddedIt)
        guard case .tracking(let tracking) = result else { return XCTFail("expected a parcel, got \(result)") }
        XCTAssertEqual(tracking.status, "delivered")
        let asked = await fetcher.asked
        XCTAssertEqual(asked, [number.digits])
    }

    func testANumberFoundInContentOrNamedByTheModelIsNeverLookedUp() async {
        let fetcher = FakeFetcher(reply(delivered))
        let tracker = ParcelTracker(fetcher: fetcher)
        let fromContent = await tracker.lookup(number, trigger: .foundInContent)
        let fromModel = await tracker.lookup(number, trigger: .requestedByModel)
        XCTAssertEqual(fromContent, .notAllowed)
        XCTAssertEqual(fromModel, .notAllowed)
        let asked = await fetcher.asked
        XCTAssertEqual(asked, [], "nothing was sent to InPost")
        XCTAssertTrue(fromContent.message(polish: true)?.contains("tylko wtedy, gdy ją dodasz albo stukniesz Odśwież") ?? false)
    }

    func testTheCodeDecidesWhatTheAnswerMeans() async {
        let notFoundBody = #"{"trackingNumber":"632085946340007012341234","message":"Tracking information about 632085946340007012341234 shipment has not been found."}"#
        let cases: [(ParcelFetch, ParcelLookupResult)] = [
            (reply(notFoundBody, code: 404), .notFound),
            (reply(#"{"error":"uknown_tracking_number"}"#, code: 400), .notATrackingNumber),
            (reply("{}", code: 429), .unavailable),
            (reply("{}", code: 500), .unavailable),
            (reply("not json", code: 200), .unavailable),
            (.failed, .unavailable),
            (.tooMany, .tooMany),
        ]
        for (fetch, expected) in cases {
            let result = await ParcelTracker(fetcher: FakeFetcher(fetch)).lookup(number, trigger: .personTappedRefresh)
            XCTAssertEqual(result, expected, "\(fetch)")
        }
    }

    func testAnAnswerForAnotherParcelOrOverTheSizeCapIsUnavailable() async {
        let other = #"{"tracking_number":"111111111111111111111111","status":"delivered"}"#
        let wrongParcel = await ParcelTracker(fetcher: FakeFetcher(reply(other))).lookup(number, trigger: .personAddedIt)
        XCTAssertEqual(wrongParcel, .unavailable)
        let huge = reply(delivered + String(repeating: " ", count: InPostTracking.maxBytes))
        let tooBig = await ParcelTracker(fetcher: FakeFetcher(huge)).lookup(number, trigger: .personAddedIt)
        XCTAssertEqual(tooBig, .unavailable)
    }

    func testEveryResultWithoutAParcelHasASentenceInBothLanguages() {
        let results: [ParcelLookupResult] = [.notFound, .notATrackingNumber, .notAllowed, .tooMany, .unavailable]
        for result in results {
            XCTAssertNotNil(result.message(polish: true), "\(result)")
            XCTAssertNotNil(result.message(polish: false), "\(result)")
            XCTAssertNotEqual(result.message(polish: true), result.message(polish: false))
        }
        XCTAssertNil(ParcelLookupResult.tracking(ParcelTracking(number: number.digits, status: "delivered", service: nil, pickupPoint: nil,
                                                                pickupAddress: nil, openingHours: nil, events: [], updatedAt: nil)).message(polish: true))
    }

    // MARK: Applying an answer to the list

    private func book(on: Bool = true) -> ParcelBook {
        var book = ParcelBook(isOn: on)
        _ = book.add(number, label: "buty", now: now)
        return book
    }

    func testOnlyAParcelInPostAnsweredForChangesTheList() async {
        var list = book()
        let transit = await ParcelTracker(fetcher: FakeFetcher(reply(inTransit))).lookup(number, trigger: .personAddedIt)
        list.apply(transit, now: now)
        XCTAssertEqual(list.entries.first?.lastStatus, "sent_from_source_branch")
        XCTAssertEqual(list.entries.first?.lastChecked, now)

        let later = now.addingTimeInterval(600)
        for failure: ParcelLookupResult in [.unavailable, .tooMany, .notFound, .notATrackingNumber, .notAllowed] {
            list.apply(failure, now: later)
        }
        XCTAssertEqual(list.entries.first?.lastStatus, "sent_from_source_branch", "a failed check leaves the last known status")
        XCTAssertEqual(list.entries.first?.lastChecked, now, "and the time it was last known")
    }

    func testAParcelRemovedWhileTheLookUpWasInFlightIsNotBroughtBack() async throws {
        var list = book()
        let id = try XCTUnwrap(list.entries.first?.id)
        let pending = await ParcelTracker(fetcher: FakeFetcher(reply(delivered))).lookup(number, trigger: .personAddedIt)
        list.remove(id: id)
        list.apply(pending, now: now)
        XCTAssertEqual(list.entries, [])
    }

    func testOnlyAParcelInAListThatIsOnMayBeLookedUp() {
        XCTAssertTrue(book().mayLookUp(number))
        XCTAssertFalse(book(on: false).mayLookUp(number))
        XCTAssertFalse(ParcelBook(isOn: true).mayLookUp(number), "a number that isn't in the list")
        var off = book()
        off.turnOff()
        XCTAssertFalse(off.mayLookUp(number))
    }
}
