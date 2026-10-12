import Foundation
import XCTest
@testable import DoddyCore

// NOT RUN when written (2026-10-12): the authoring environment had no Swift toolchain. These are
// the checks for Packages/DoddyCore/Sources/DoddyCore/Payments; run them with scripts/ci.sh.

/// Shared fixtures written by the backend (`npm run fixtures`); the TypeScript tests validate the same files.
private func paymentFixtureData(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/payments/\(name).json"))
}

private func paymentFixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(T.self, from: paymentFixtureData(name))
}

/// A server error as the app would see it, built from a real server answer.
private func serverError(_ name: String) throws -> PaymentsError {
    let body = try paymentFixture(PaymentErrorBody.self, name)
    return .server(code: body.error.code, message: body.error.message, retryAfterSeconds: body.error.retryAfterSeconds, receipt: body.error.receipt)
}

private final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ iso: String) { date = PaymentTime.parse(iso)! }
}

/// 30 seconds into the fixture approval's two minutes.
private let startOfDay = "2026-10-12T10:00:30.000Z"
private let afterExpiry = "2026-10-12T10:03:00.000Z"
private let page = "https://demo-shop.example/articles/42"

// MARK: Fakes

@MainActor
private final class PaymentsFakeAuthenticator: PaymentAuthenticator {
    var result: PaymentAuthResult = .confirmed
    private(set) var reasons: [String] = []
    var onConfirm: (() -> Void)?

    func confirm(reason: String) async -> PaymentAuthResult {
        reasons.append(reason)
        onConfirm?()
        return result
    }
}

private final class PaymentsFakeClient: PaymentsClient, @unchecked Sendable {
    var prepareResult: Result<PaymentPrepared, PaymentsError>
    var payResult: Result<PaymentResult, PaymentsError>
    var receiptsResult: Result<[PaymentReceipt], PaymentsError> = .success([])
    var statusResult: Result<PaymentStatus, PaymentsError>
    var switchResult: Result<PaymentSwitchResult, PaymentsError>
    var duringPay: (@Sendable () async -> Void)?
    private(set) var prepareCalls: [String] = []
    private(set) var payCalls: [(url: String, approvalId: UUID)] = []
    private(set) var switchCalls: [Bool] = []

    init() throws {
        prepareResult = .success(try paymentFixture(PaymentPrepared.self, "prepared"))
        payResult = .success(try paymentFixture(PaymentResult.self, "paid"))
        statusResult = .success(try paymentFixture(PaymentStatus.self, "status-off"))
        switchResult = .success(try paymentFixture(PaymentSwitchResult.self, "switch-result-on"))
    }

    func status() async throws(PaymentsError) -> PaymentStatus { try statusResult.get() }
    func setSwitch(enabled: Bool) async throws(PaymentsError) -> PaymentSwitchResult {
        switchCalls.append(enabled)
        return try switchResult.get()
    }
    func prepare(url: String) async throws(PaymentsError) -> PaymentPrepared {
        prepareCalls.append(url)
        return try prepareResult.get()
    }
    func pay(url: String, approvalId: UUID) async throws(PaymentsError) -> PaymentResult {
        payCalls.append((url, approvalId))
        await duringPay?()
        return try payResult.get()
    }
    func receipts() async throws(PaymentsError) -> [PaymentReceipt] { try receiptsResult.get() }
}

private final class Observed: @unchecked Sendable {
    var phase: PaymentApprovalModel.Phase?
    var busy: Bool?
    var canDismiss: Bool?
}

// MARK: Contract

final class PaymentsContractTests: XCTestCase {
    func testEveryPaymentFixtureDecodes() throws {
        let off = try paymentFixture(PaymentStatus.self, "status-off")
        XCTAssertEqual(off.mode, .mock)
        XCTAssertFalse(off.enabled, "payments start off")
        XCTAssertEqual(off.wallet.kind, .mock)
        XCTAssertTrue(off.wallet.testNetwork)
        XCTAssertEqual(off.limits.usedToday, "0.00")
        XCTAssertEqual(off.unresolved, 0)

        let none = try paymentFixture(PaymentStatus.self, "status-no-wallet")
        XCTAssertEqual(none.wallet.kind, PaymentWalletKind.none)
        XCTAssertFalse(none.wallet.configured)
        XCTAssertNil(none.wallet.account)

        XCTAssertEqual(try paymentFixture(PaymentStatus.self, "status-used").limits.usedToday, "0.05")
        XCTAssertEqual(try paymentFixture(PaymentStatus.self, "status-unresolved").unresolved, 1)

        let switched = try paymentFixture(PaymentSwitchResult.self, "switch-result-on")
        XCTAssertTrue(switched.status.enabled)
        XCTAssertEqual(switched.receipt.operation, .switchPayments)

        let prepared = try paymentFixture(PaymentPrepared.self, "prepared")
        XCTAssertEqual(prepared.preview.confirmLabel, "Pay 0.05 USDC")
        XCTAssertEqual(prepared.preview.lines.count, 5)
        XCTAssertEqual(prepared.preview.lines.first, "Amount: 0.05 USDC")

        let paid = try paymentFixture(PaymentResult.self, "paid")
        XCTAssertEqual(paid.receipt.status, .succeeded)
        XCTAssertEqual(paid.receipt.host, "demo-shop.example")
        XCTAssertNotNil(paid.receipt.transaction)

        let receipts = try paymentFixture(PaymentReceiptsResponse.self, "receipts")
        XCTAssertEqual(receipts.receipts.first?.operation, .pay)
        XCTAssertTrue(receipts.receipts.contains { $0.operation == .switchPayments })

        for name in ["error-fresh-confirmation", "error-no-wallet", "error-over-limit", "error-unconfirmed"] {
            let body = try paymentFixture(PaymentErrorBody.self, name)
            XCTAssertNotNil(body.error.receipt, name)
            XCTAssertFalse(body.error.message.isEmpty, name)
        }
    }

    func testTheApprovalExpiryIsReadWithMilliseconds() throws {
        let prepared = try paymentFixture(PaymentPrepared.self, "prepared")
        XCTAssertEqual(prepared.expiryDate, PaymentTime.parse("2026-10-12T10:02:00Z"))
        XCTAssertNil(PaymentTime.parse("not a date"))
    }

    func testErrorsSayWhetherAPaymentMayHaveHappened() throws {
        // Only a server that says it did nothing is a "failed"; every doubt is "might have been paid".
        XCTAssertTrue(try serverError("error-unconfirmed").mightHaveBeenPaid)
        XCTAssertFalse(try serverError("error-over-limit").mightHaveBeenPaid)
        XCTAssertFalse(try serverError("error-fresh-confirmation").mightHaveBeenPaid)
        XCTAssertFalse(try serverError("error-no-wallet").mightHaveBeenPaid)
        XCTAssertTrue(PaymentsError.transport("URLError").mightHaveBeenPaid)
        XCTAssertTrue(PaymentsError.unreadableResponse.mightHaveBeenPaid)
        XCTAssertFalse(PaymentsError.unauthenticated.mightHaveBeenPaid)
        XCTAssertFalse(PaymentsError.notConfigured.mightHaveBeenPaid)
        XCTAssertTrue(PaymentsError.server(code: "internal", message: "x", retryAfterSeconds: nil, receipt: nil).mightHaveBeenPaid)
        XCTAssertTrue(PaymentsError.server(code: "provider_unavailable", message: "x", retryAfterSeconds: nil, receipt: nil).mightHaveBeenPaid)
        XCTAssertTrue(PaymentsError.server(code: "provider_timeout", message: "x", retryAfterSeconds: nil, receipt: nil).mightHaveBeenPaid)
        XCTAssertFalse(PaymentsError.server(code: "busy", message: "x", retryAfterSeconds: 2, receipt: nil).mightHaveBeenPaid)
        XCTAssertFalse(PaymentsError.server(code: "capability_disabled", message: "x", retryAfterSeconds: nil, receipt: nil).mightHaveBeenPaid)
    }

    func testServerAnswersBecomeTypedErrors() throws {
        let data = try paymentFixtureData("error-unconfirmed")
        do {
            let _: PaymentResult = try BackendPaymentsClient.decode(status: 502, data: data)
            XCTFail("an error body is not a result")
        } catch {
            XCTAssertEqual(error.code, "provider_unavailable")
            XCTAssertEqual(error.receipt?.status, .outcomeUnknown)
            XCTAssertTrue(error.mightHaveBeenPaid)
        }
        do {
            let _: PaymentResult = try BackendPaymentsClient.decode(status: 401, data: Data())
            XCTFail("401 is a refusal")
        } catch {
            XCTAssertEqual(error, .unauthenticated)
        }
        do {
            let _: PaymentResult = try BackendPaymentsClient.decode(status: 200, data: Data("{}".utf8))
            XCTFail("an unreadable success is an error, never an empty result")
        } catch {
            XCTAssertEqual(error, .unreadableResponse)
        }
        do {
            let _: PaymentResult = try BackendPaymentsClient.decode(status: 502, data: Data("<html>bad gateway</html>".utf8))
            XCTFail("an unreadable error body is an error")
        } catch {
            XCTAssertEqual(error, .unreadableResponse)
        }
    }
}

// MARK: Client

private final class Capture: @unchecked Sendable {
    var requests: [HTTPRequest] = []
    var reply: (status: Int, body: Data) = (200, Data())
}

private struct CapturingTransport: HTTPTransport {
    let capture: Capture
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        capture.requests.append(request)
        return capture.reply
    }
}

final class PaymentsClientTests: XCTestCase {
    private func client(_ capture: Capture, token: String? = "t0ken") -> BackendPaymentsClient {
        BackendPaymentsClient(baseURL: URL(string: "https://api.doddy.test")!, sessionToken: { token }, transport: CapturingTransport(capture: capture))!
    }

    func testPayingSendsOnlyThePageAndTheApproval() async throws {
        let capture = Capture()
        capture.reply = (200, try paymentFixtureData("paid"))
        let approval = UUID()
        _ = try await client(capture).pay(url: page, approvalId: approval)

        let request = try XCTUnwrap(capture.requests.first)
        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://api.doddy.test/v1/payments/pay")
        XCTAssertEqual(request.headers["authorization"], "Bearer t0ken")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(body, ["url": page, "approvalId": approval.uuidString.lowercased()], "no amount, recipient or wallet can be sent")
    }

    func testPreparingSendsOnlyThePage() async throws {
        let capture = Capture()
        capture.reply = (200, try paymentFixtureData("prepared"))
        _ = try await client(capture).prepare(url: page)
        let request = try XCTUnwrap(capture.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.doddy.test/v1/payments/prepare")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String], ["url": page])
    }

    func testStatusAndSwitchAndReceipts() async throws {
        let capture = Capture()
        capture.reply = (200, try paymentFixtureData("status-off"))
        let status = try await client(capture).status()
        XCTAssertFalse(status.enabled)
        XCTAssertEqual(capture.requests.last?.method, "GET")
        XCTAssertNil(capture.requests.last?.body)

        capture.reply = (200, try paymentFixtureData("switch-result-on"))
        _ = try await client(capture).setSwitch(enabled: true)
        XCTAssertEqual(capture.requests.last?.method, "PUT")
        XCTAssertEqual(capture.requests.last?.url.path, "/v1/payments/switch")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(capture.requests.last?.body)) as? [String: Bool], ["enabled": true])

        capture.reply = (200, try paymentFixtureData("receipts"))
        XCTAssertFalse(try await client(capture).receipts().isEmpty)
    }

    func testNoTokenMeansNothingIsSent() async {
        let capture = Capture()
        for token in [nil, ""] as [String?] {
            do {
                _ = try await client(capture, token: token).status()
                XCTFail("no session, no request")
            } catch {
                XCTAssertEqual(error, .notConfigured)
            }
        }
        XCTAssertTrue(capture.requests.isEmpty)
    }

    func testOnlyHTTPSServersAreAccepted() {
        let transport = CapturingTransport(capture: Capture())
        XCTAssertNil(BackendPaymentsClient(baseURL: URL(string: "http://api.doddy.test")!, sessionToken: { "t" }, transport: transport))
        XCTAssertNil(BackendPaymentsClient(baseURL: URL(string: "https://api.doddy.test?x=1")!, sessionToken: { "t" }, transport: transport))
    }
}

// MARK: The approval card's state machine

@MainActor
final class PaymentApprovalModelTests: XCTestCase {
    private func make(_ client: PaymentsFakeClient, _ auth: PaymentsFakeAuthenticator, _ clock: TestClock = TestClock(startOfDay)) -> PaymentApprovalModel {
        PaymentApprovalModel(client: client, authenticator: auth, now: { clock.date })
    }

    private func ready(_ client: PaymentsFakeClient, _ auth: PaymentsFakeAuthenticator, _ clock: TestClock = TestClock(startOfDay)) async -> PaymentApprovalModel {
        let model = make(client, auth, clock)
        await model.start(url: page)
        return model
    }

    func testNothingIsAskedOrPaidBeforeThePersonApproves() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let model = await ready(client, auth)
        guard case .awaitingApproval(let prepared) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(prepared.preview.confirmLabel, "Pay 0.05 USDC")
        XCTAssertEqual(client.prepareCalls, [page])
        XCTAssertTrue(client.payCalls.isEmpty)
        XCTAssertTrue(auth.reasons.isEmpty)
        XCTAssertEqual(model.secondsLeft(), 90)
        XCTAssertTrue(model.canDismiss, "the card can still be dismissed before paying")
    }

    func testFaceIDThenOnePaymentWithTheApprovalTheServerGave() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let model = await ready(client, auth)
        let approval = try XCTUnwrap(model.prepared?.approvalId)
        await model.approve()

        XCTAssertEqual(auth.reasons, ["Pay 0.05 USDC"], "Face ID is asked with the amount in its prompt")
        XCTAssertEqual(client.payCalls.count, 1)
        XCTAssertEqual(client.payCalls.first?.url, page)
        XCTAssertEqual(client.payCalls.first?.approvalId, approval)
        guard case .paid(let result) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(result.receipt.status, .succeeded)
    }

    func testFaceIDIsAskedEveryTime() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let model = await ready(client, auth)
        await model.approve()
        model.finish()
        await model.start(url: page)
        await model.approve()
        XCTAssertEqual(auth.reasons.count, 2, "no remembered yes")
        XCTAssertEqual(client.payCalls.count, 2)
    }

    func testFaceIDNotConfirmedPaysNothingAndCanBeTriedAgain() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        auth.result = .cancelled
        let model = await ready(client, auth)
        await model.approve()
        XCTAssertTrue(client.payCalls.isEmpty)
        guard case .awaitingApproval = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(model.notice, "Face ID wasn't confirmed. Nothing was paid.")

        auth.result = .confirmed
        await model.approve()
        XCTAssertEqual(client.payCalls.count, 1)
        guard case .paid = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertNil(model.notice)
    }

    func testWithoutFaceIDOrAPasscodeTheAnswerIsNo() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        auth.result = .unavailable
        let model = await ready(client, auth)
        await model.approve()
        XCTAssertTrue(client.payCalls.isEmpty, "a payment is never allowed without a check")
        guard case .failed(let message, _) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(message.contains("Nothing was paid"))
    }

    func testAnExpiredApprovalIsNotEvenOffered() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let clock = TestClock(startOfDay)
        let model = await ready(client, auth, clock)
        clock.date = PaymentTime.parse(afterExpiry)!
        XCTAssertEqual(model.secondsLeft(), 0)
        await model.approve()
        XCTAssertTrue(auth.reasons.isEmpty, "no Face ID prompt for a dead approval")
        XCTAssertTrue(client.payCalls.isEmpty)
        guard case .failed(let message, _) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(message.contains("Nothing was paid"))
    }

    func testAnApprovalThatRunsOutWhileConfirmingIsNotSent() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let clock = TestClock(startOfDay)
        auth.onConfirm = { clock.date = PaymentTime.parse(afterExpiry)! }
        let model = await ready(client, auth, clock)
        await model.approve()
        XCTAssertEqual(auth.reasons.count, 1)
        XCTAssertTrue(client.payCalls.isEmpty)
        guard case .failed = model.phase else { return XCTFail("\(model.phase)") }
    }

    func testTwoQuickTapsPayOnce() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let model = await ready(client, auth)
        async let first: Void = model.approve()
        async let second: Void = model.approve()
        _ = await (first, second)
        XCTAssertEqual(client.payCalls.count, 1)
        XCTAssertEqual(auth.reasons.count, 1)
        guard case .paid = model.phase else { return XCTFail("\(model.phase)") }
        // And once it is paid, the same approval cannot be sent again.
        await model.approve()
        XCTAssertEqual(client.payCalls.count, 1)
    }

    // MARK: After the server was asked to pay

    func testLosingContactWhilePayingIsUnconfirmedNeverFailed() async throws {
        let client = try PaymentsFakeClient()
        client.payResult = .failure(.transport("URLError"))
        let model = await ready(client, PaymentsFakeAuthenticator())
        await model.approve()
        XCTAssertEqual(client.payCalls.count, 1, "never retried")
        guard case .unconfirmed(let message, _) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(message.contains("may or may not"))
        XCTAssertTrue(message.contains("Don't pay again yet"))
    }

    func testTheServersOwnDoubtIsShownAsItWrote() async throws {
        let client = try PaymentsFakeClient()
        client.payResult = .failure(try serverError("error-unconfirmed"))
        let model = await ready(client, PaymentsFakeAuthenticator())
        await model.approve()
        guard case .unconfirmed(let message, let receipt) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(message.contains("may or may not have gone through"))
        XCTAssertEqual(receipt?.status, .outcomeUnknown)
        XCTAssertEqual(client.payCalls.count, 1)
    }

    func testAnUnreadableOrUnexplainedServerFailureIsAlsoUnconfirmed() async throws {
        for failure in [PaymentsError.unreadableResponse, .server(code: "internal", message: "Something went wrong on Doddy's server.", retryAfterSeconds: nil, receipt: nil)] {
            let client = try PaymentsFakeClient()
            client.payResult = .failure(failure)
            let model = await ready(client, PaymentsFakeAuthenticator())
            await model.approve()
            guard case .unconfirmed = model.phase else { return XCTFail("\(failure): \(model.phase)") }
        }
    }

    func testARefusalThatDidNothingIsAFailureWithTheServersWords() async throws {
        for name in ["error-fresh-confirmation", "error-over-limit"] {
            let client = try PaymentsFakeClient()
            client.payResult = .failure(try serverError(name))
            let model = await ready(client, PaymentsFakeAuthenticator())
            await model.approve()
            guard case .failed(let message, let receipt) = model.phase else { return XCTFail("\(name): \(model.phase)") }
            XCTAssertTrue(message.contains("Nothing was paid"), name)
            XCTAssertEqual(receipt?.status, .blocked, name)
        }
        let busy = try PaymentsFakeClient()
        busy.payResult = .failure(.server(code: "busy", message: "Another request is still running.", retryAfterSeconds: 2, receipt: nil))
        let model = await ready(busy, PaymentsFakeAuthenticator())
        await model.approve()
        guard case .failed = model.phase else { return XCTFail("\(model.phase)") }
    }

    func testOnlyASucceededReceiptCountsAsPaid() async throws {
        let client = try PaymentsFakeClient()
        let paid = try paymentFixture(PaymentResult.self, "paid")
        let unknown = try paymentFixture(PaymentErrorBody.self, "error-unconfirmed").error.receipt!
        client.payResult = .success(PaymentResult(mode: paid.mode, text: paid.text, receipt: unknown))
        let model = await ready(client, PaymentsFakeAuthenticator())
        await model.approve()
        guard case .unconfirmed = model.phase else { return XCTFail("a 200 with a doubtful receipt is not 'paid': \(model.phase)") }
    }

    func testTheCardCannotBeCancelledOrDismissedWhileThePaymentIsBeingSent() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let model = await ready(client, auth)
        let seen = Observed()
        client.duringPay = {
            await MainActor.run {
                model.cancel()
                model.finish()
                model.dismiss()
                seen.phase = model.phase
                seen.busy = model.isBusy
                seen.canDismiss = model.canDismiss
            }
        }
        await model.approve()
        guard case .paying? = seen.phase else { return XCTFail("\(String(describing: seen.phase))") }
        XCTAssertEqual(seen.busy, true)
        XCTAssertEqual(seen.canDismiss, false)
        guard case .paid = model.phase else { return XCTFail("\(model.phase)") }
    }

    // MARK: Starting and cancelling

    func testCancelBeforePayingSendsNothing() async throws {
        let client = try PaymentsFakeClient()
        let auth = PaymentsFakeAuthenticator()
        let model = await ready(client, auth)
        model.cancel()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(client.payCalls.isEmpty)
        XCTAssertTrue(auth.reasons.isEmpty)
        await model.approve() // nothing to approve any more
        XCTAssertTrue(client.payCalls.isEmpty)
    }

    func testClosingTheSheetBeforePayingCancelsAndAfterAnOutcomeClears() async throws {
        let client = try PaymentsFakeClient()
        let model = await ready(client, PaymentsFakeAuthenticator())
        model.dismiss()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(client.payCalls.isEmpty)

        await model.start(url: page)
        await model.approve()
        guard case .paid = model.phase else { return XCTFail("\(model.phase)") }
        model.dismiss()
        XCTAssertEqual(model.phase, .idle, "the outcome was read, so closing clears it")
    }

    func testTheServersRefusalToPrepareEndsInFailureBeforeAnyFaceID() async throws {
        let client = try PaymentsFakeClient()
        client.prepareResult = .failure(try serverError("error-over-limit"))
        let auth = PaymentsFakeAuthenticator()
        let model = await ready(client, auth)
        guard case .failed(let message, _) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(message.contains("more than Doddy's limit"))
        await model.approve()
        XCTAssertTrue(auth.reasons.isEmpty)
        XCTAssertTrue(client.payCalls.isEmpty)
    }

    func testAnEmptyAddressIsNotSentAndStartingTwiceIsIgnored() async throws {
        let client = try PaymentsFakeClient()
        let model = make(client, PaymentsFakeAuthenticator())
        await model.start(url: "   ")
        guard case .failed = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(client.prepareCalls.isEmpty)
        model.finish()

        await model.start(url: "  \(page)  ")
        XCTAssertEqual(client.prepareCalls, [page], "the address is trimmed")
        await model.start(url: "https://other.example/x")
        XCTAssertEqual(client.prepareCalls.count, 1, "a second start while a card is up is ignored")
    }

    func testWithoutAServerThePaymentSaysSo() async {
        let model = PaymentApprovalModel(client: nil, authenticator: PaymentsFakeAuthenticator())
        await model.start(url: page)
        guard case .failed(let message, _) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(message.contains("isn't set up"))
    }

    // MARK: Checking again after an unconfirmed payment

    private func unconfirmedModel(_ client: PaymentsFakeClient) async throws -> PaymentApprovalModel {
        client.payResult = .failure(.transport("URLError"))
        let model = await ready(client, PaymentsFakeAuthenticator())
        await model.approve()
        guard case .unconfirmed = model.phase else {
            XCTFail("\(model.phase)")
            return model
        }
        return model
    }

    /// The fixture's pay receipt with another time and status, as the server would list it.
    private func receipt(status: String, at iso: String, host: String = "demo-shop.example") throws -> PaymentReceipt {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: paymentFixtureData("paid")) as? [String: Any])
        var receipt = try XCTUnwrap(json["receipt"] as? [String: Any])
        receipt["timestamp"] = iso
        receipt["status"] = status
        receipt["host"] = host
        json["receipt"] = receipt
        return try JSONDecoder().decode(PaymentResult.self, from: JSONSerialization.data(withJSONObject: json)).receipt
    }

    func testCheckingAgainFindsWhatTheServerRecorded() async throws {
        let client = try PaymentsFakeClient()
        let model = try await unconfirmedModel(client)
        client.receiptsResult = .success([try receipt(status: "succeeded", at: "2026-10-12T10:00:31.000Z")])
        await model.checkAgain()
        guard case .paid(let result) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(result.receipt.status, .succeeded)
    }

    func testCheckingAgainIgnoresOtherSitesAndOlderReceipts() async throws {
        let client = try PaymentsFakeClient()
        let model = try await unconfirmedModel(client)
        client.receiptsResult = .success([
            try receipt(status: "succeeded", at: "2026-10-12T10:00:31.000Z", host: "other.example"),
            try receipt(status: "succeeded", at: "2026-10-12T09:00:00.000Z"),
        ])
        await model.checkAgain()
        guard case .unconfirmed = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(model.notice, "Doddy's server has no record yet. Check your wallet's history.")
    }

    func testCheckingAgainCanLearnItFailedOrIsStillUnknown() async throws {
        let failed = try PaymentsFakeClient()
        let failedModel = try await unconfirmedModel(failed)
        failed.receiptsResult = .success([try receipt(status: "failed", at: "2026-10-12T10:00:31.000Z")])
        await failedModel.checkAgain()
        guard case .failed = failedModel.phase else { return XCTFail("\(failedModel.phase)") }

        let unknown = try PaymentsFakeClient()
        let unknownModel = try await unconfirmedModel(unknown)
        unknown.receiptsResult = .success([try receipt(status: "outcome_unknown", at: "2026-10-12T10:00:31.000Z")])
        await unknownModel.checkAgain()
        guard case .unconfirmed = unknownModel.phase else { return XCTFail("\(unknownModel.phase)") }
    }

    func testCheckingAgainOffline() async throws {
        let client = try PaymentsFakeClient()
        let model = try await unconfirmedModel(client)
        client.receiptsResult = .failure(.transport("URLError"))
        await model.checkAgain()
        guard case .unconfirmed = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertNotNil(model.notice)
    }
}

// MARK: Settings

@MainActor
final class PaymentsSettingsModelTests: XCTestCase {
    func testStatusLoadsAndPayingIsOffUntilTheServerAcceptsTheSwitch() async throws {
        let client = try PaymentsFakeClient()
        let model = PaymentsSettingsModel(client: client)
        XCTAssertEqual(model.load, .loading)
        await model.refresh()
        XCTAssertEqual(model.load, .ready)
        XCTAssertTrue(model.isDemo)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.canPay)

        await model.setEnabled(true)
        XCTAssertEqual(client.switchCalls, [true])
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.canPay)
        XCTAssertEqual(model.receipts.first?.operation, .switchPayments)
    }

    func testARefusedSwitchStaysWhereItWasWithTheServersReason() async throws {
        let client = try PaymentsFakeClient()
        client.statusResult = .success(try paymentFixture(PaymentStatus.self, "status-no-wallet"))
        client.switchResult = .failure(try serverError("error-no-wallet"))
        let model = PaymentsSettingsModel(client: client)
        await model.refresh()
        await model.setEnabled(true)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.canPay)
        XCTAssertEqual(model.message, "No payment wallet is set up on this server.")
        XCTAssertEqual(model.receipts.first?.status, .blocked)
    }

    func testUnconfirmedPaymentsAreSurfaced() async throws {
        let client = try PaymentsFakeClient()
        client.statusResult = .success(try paymentFixture(PaymentStatus.self, "status-unresolved"))
        let model = PaymentsSettingsModel(client: client)
        await model.refresh()
        XCTAssertEqual(model.unresolved, 1)
    }

    func testWithoutAServerNothingIsShownOrSent() async throws {
        let model = PaymentsSettingsModel(client: nil)
        XCTAssertEqual(model.load, .notConfigured)
        await model.refresh()
        await model.setEnabled(true)
        XCTAssertEqual(model.load, .notConfigured)
        XCTAssertNil(model.status)
    }

    func testAFailedRefreshKeepsWhatWasShown() async throws {
        let client = try PaymentsFakeClient()
        let model = PaymentsSettingsModel(client: client)
        await model.refresh()
        client.statusResult = .failure(.transport("URLError"))
        await model.refresh()
        XCTAssertEqual(model.load, .ready)
        XCTAssertNotNil(model.status)
        XCTAssertNotNil(model.message)
    }
}
