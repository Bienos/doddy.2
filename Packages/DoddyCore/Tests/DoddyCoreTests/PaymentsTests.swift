import Foundation
import XCTest
@testable import DoddyCore

/// Paying for things by voice (ADR-530): the shared contract, the client's requests, the checks
/// before anything is sent, and the results the agent and "What Doddy did" get.

private func purchaseFixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/purchases/\(name).json"))
}

private func decodePurchase<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(T.self, from: purchaseFixture(name))
}

private final class PaymentsTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    let status: Int
    let body: Data

    init(status: Int = 200, body: Data) {
        self.status = status
        self.body = body
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        return (status, body)
    }
}

final class PaymentsContractTests: XCTestCase {
    func testEveryFixtureDecodes() throws {
        let native = try decodePurchase(PurchasePrepareResult.self, "prepare-result-native")
        XCTAssertEqual(native.purchase.kind, .native)
        XCTAssertEqual(native.purchase.status, .awaitingTap)
        XCTAssertEqual(native.methods, [.applePay, .blik])
        XCTAssertEqual(native.payee, "Doddy (test)")
        XCTAssertTrue(native.purchase.testMode)
        XCTAssertNil(native.purchase.checkoutHost)
        XCTAssertNotNil(native.expiryDate)

        let checkout = try decodePurchase(PurchasePrepareResult.self, "prepare-result-checkout")
        XCTAssertEqual(checkout.purchase.kind, .checkout)
        XCTAssertEqual(checkout.methods, [])
        XCTAssertEqual(checkout.purchase.checkoutHost, "shop.example.pl")
        XCTAssertFalse(checkout.purchase.testMode)

        XCTAssertEqual(try decodePurchase(PurchaseResult.self, "purchase-result-paid-apple-pay").purchase.status, .paid)
        XCTAssertEqual(try decodePurchase(PurchaseResult.self, "purchase-result-waiting-blik").purchase.status, .waitingForBank)
        XCTAssertEqual(try decodePurchase(PurchaseResult.self, "purchase-result-unknown").purchase.status, .outcomeUnknown)
        let handoff = try decodePurchase(HandoffResult.self, "handoff-result")
        XCTAssertEqual(handoff.purchase.status, .handedOff)
        XCTAssertEqual(URL(string: handoff.checkoutUrl)?.host, "shop.example.pl")
        let list = try decodePurchase(PurchasesList.self, "purchases-list")
        XCTAssertEqual(list.purchases.map(\.status), [.userReportedPaid, .paid])
    }

    func testAnErrorBodyBecomesATypedErrorNeverAnEmptyResult() throws {
        XCTAssertThrowsError(try BackendPaymentsClient.decode(status: 403, data: try purchaseFixture("error-confirmation-expired")) as PurchaseResult) {
            XCTAssertEqual(($0 as? PaymentsError)?.code, "capability_disabled")
            XCTAssertEqual(($0 as? PaymentsError)?.userMessage, "This purchase needs a fresh confirmation. Nothing was paid.")
        }
        XCTAssertThrowsError(try BackendPaymentsClient.decode(status: 200, data: Data("{}".utf8)) as PurchaseResult) {
            XCTAssertEqual($0 as? PaymentsError, .unreadableResponse)
        }
        XCTAssertThrowsError(try BackendPaymentsClient.decode(status: 401, data: Data()) as PurchaseResult) {
            XCTAssertEqual($0 as? PaymentsError, .unauthenticated)
        }
    }

    func testStatusFlags() {
        XCTAssertEqual(PurchaseStatus.allCases.filter(\.needsStatusCheck), [.paying, .waitingForBank, .outcomeUnknown])
        XCTAssertEqual(Set(PurchaseStatus.allCases.filter(\.isFinal)), [.paid, .failed, .cancelled, .expired, .userReportedPaid])
    }
}

final class PaymentsClientTests: XCTestCase {
    private let purchaseID = UUID(uuidString: "6F1C2B9E-3A4D-4F5E-8A7B-1C2D3E4F5A6B")!
    private let approvalID = UUID(uuidString: "0B7D4A2E-5F6C-4D3B-9A8E-7F6E5D4C3B2A")!

    private func client(_ transport: PaymentsTransport, token: String? = "tok") -> BackendPaymentsClient {
        BackendPaymentsClient(baseURL: URL(string: "https://doddy.example.com")!, sessionToken: { token }, transport: transport)!
    }

    private func object(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testPrepareSendsExactlyTheDraftAndLeavesOutTheURLForNative() async throws {
        let transport = PaymentsTransport(body: try purchaseFixture("prepare-result-native"))
        let draft = PurchaseDraft(kind: .native, merchantName: "Kino Muranów", description: "2 tickets", amountMinor: 5_600, checkoutURL: nil)
        _ = try await client(transport).prepare(draft.request)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/purchases/prepare")
        XCTAssertEqual(request.headers["authorization"], "Bearer tok")
        let body = try object(request.body)
        XCTAssertEqual(body["kind"] as? String, "native")
        XCTAssertEqual(body["merchantName"] as? String, "Kino Muranów")
        XCTAssertEqual(body["amountMinor"] as? Int, 5_600)
        XCTAssertEqual(body["currency"] as? String, "PLN")
        XCTAssertNil(body["checkoutUrl"], "the server refuses unknown and native checkout URLs")
    }

    func testPayWithBlikSendsTheCodeAndNoApplePayData() async throws {
        let transport = PaymentsTransport(body: try purchaseFixture("purchase-result-waiting-blik"))
        let result = try await client(transport).pay(purchaseId: purchaseID, approvalId: approvalID, payment: .blik(code: "123456"))
        XCTAssertEqual(result.purchase.status, .waitingForBank)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/purchases/pay")
        let body = try object(request.body)
        XCTAssertEqual(body["purchaseId"] as? String, "6f1c2b9e-3a4d-4f5e-8a7b-1c2d3e4f5a6b")
        XCTAssertEqual(body["approvalId"] as? String, "0b7d4a2e-5f6c-4d3b-9a8e-7f6e5d4c3b2a")
        XCTAssertEqual(body["method"] as? String, "blik")
        XCTAssertEqual(body["blikCode"] as? String, "123456")
        XCTAssertNil(body["applePay"])
    }

    func testPayWithApplePayPassesTheTokenThrough() async throws {
        let transport = PaymentsTransport(body: try purchaseFixture("purchase-result-paid-apple-pay"))
        let token = ApplePayTokenData(paymentData: #"{"version":"EC_v1"}"#, network: "Visa", instrumentName: "Visa 1234", transactionId: "abc")
        _ = try await client(transport).pay(purchaseId: purchaseID, approvalId: approvalID, payment: .applePay(token))
        let body = try object(transport.requests.first?.body)
        XCTAssertEqual(body["method"] as? String, "apple_pay")
        XCTAssertNil(body["blikCode"])
        let applePay = try XCTUnwrap(body["applePay"] as? [String: Any])
        XCTAssertEqual(applePay["paymentData"] as? String, #"{"version":"EC_v1"}"#)
        XCTAssertEqual(applePay["network"] as? String, "Visa")
    }

    func testTheOtherRoutes() async throws {
        let result = try purchaseFixture("purchase-result-paid-apple-pay")
        let status = PaymentsTransport(body: result)
        _ = try await client(status).status(purchaseId: purchaseID)
        XCTAssertEqual(status.requests.first?.url.path, "/v1/purchases/status")
        XCTAssertEqual(try object(status.requests.first?.body)["purchaseId"] as? String, "6f1c2b9e-3a4d-4f5e-8a7b-1c2d3e4f5a6b")

        let cancel = PaymentsTransport(body: result)
        _ = try await client(cancel).cancel(purchaseId: purchaseID)
        XCTAssertEqual(cancel.requests.first?.url.path, "/v1/purchases/cancel")

        let handoff = PaymentsTransport(body: try purchaseFixture("handoff-result"))
        _ = try await client(handoff).handoff(purchaseId: purchaseID, approvalId: approvalID)
        XCTAssertEqual(handoff.requests.first?.url.path, "/v1/purchases/handoff")
        XCTAssertEqual(try object(handoff.requests.first?.body)["approvalId"] as? String, "0b7d4a2e-5f6c-4d3b-9a8e-7f6e5d4c3b2a")

        let report = PaymentsTransport(body: result)
        _ = try await client(report).report(purchaseId: purchaseID, paid: true)
        XCTAssertEqual(report.requests.first?.url.path, "/v1/purchases/report")
        XCTAssertEqual(try object(report.requests.first?.body)["paid"] as? Bool, true)

        let list = PaymentsTransport(body: try purchaseFixture("purchases-list"))
        let purchases = try await client(list).list()
        XCTAssertEqual(list.requests.first?.method, "GET")
        XCTAssertNil(list.requests.first?.body)
        XCTAssertEqual(purchases.count, 2)
    }

    func testNoTokenMeansNotConfiguredAndNothingIsSent() async throws {
        let transport = PaymentsTransport(body: Data())
        do {
            _ = try await client(transport, token: nil).status(purchaseId: purchaseID)
            XCTFail("expected notConfigured")
        } catch {
            XCTAssertEqual(error, .notConfigured)
        }
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertNil(BackendPaymentsClient(baseURL: URL(string: "http://doddy.example.com")!, sessionToken: { "t" }, transport: transport))
    }
}

final class PurchaseRulesTests: XCTestCase {
    func testPolishPrices() {
        XCTAssertEqual(PurchaseMoney.format(minor: 5_600), "56,00 zł")
        XCTAssertEqual(PurchaseMoney.format(minor: 7_450), "74,50 zł")
        XCTAssertEqual(PurchaseMoney.format(minor: 5), "0,05 zł")
        XCTAssertEqual(PurchaseMoney.format(minor: 123_450), "1 234,50 zł")
        XCTAssertEqual(PurchaseMoney.format(minor: 100_000_000), "1 000 000,00 zł")
        XCTAssertEqual(PurchaseMoney.format(minor: 1_999, currency: "eur"), "19,99 EUR")
        XCTAssertEqual(PurchaseMoney.decimal(minor: 5_650), Decimal(string: "56.5"))
    }

    func testAmountsTheAgentSaidAreNeverRoundedIntoSomethingElse() {
        XCTAssertEqual(PurchaseMoney.minor(fromMajor: 56), 5_600)
        XCTAssertEqual(PurchaseMoney.minor(fromMajor: 56.5), 5_650)
        XCTAssertEqual(PurchaseMoney.minor(fromMajor: 19.99), 1_999)
        XCTAssertEqual(PurchaseMoney.minor(fromMajor: 0.1), 10)
        XCTAssertNil(PurchaseMoney.minor(fromMajor: 19.999))
        XCTAssertNil(PurchaseMoney.minor(fromMajor: 0))
        XCTAssertNil(PurchaseMoney.minor(fromMajor: -5))
        XCTAssertNil(PurchaseMoney.minor(fromMajor: .infinity))
        XCTAssertNil(PurchaseMoney.minor(fromMajor: 1_000_000))
    }

    func testBlikCodes() {
        XCTAssertEqual(BlikCode.normalize("123456"), "123456")
        XCTAssertEqual(BlikCode.normalize("123 456"), "123456")
        XCTAssertEqual(BlikCode.normalize("123-456"), "123456")
        XCTAssertNil(BlikCode.normalize("12345"))
        XCTAssertNil(BlikCode.normalize("1234567"))
        XCTAssertNil(BlikCode.normalize("12a456"))
        XCTAssertNil(BlikCode.normalize("١٢٣٤٥٦"), "only ASCII digits")
    }

    func testCheckoutLinks() {
        XCTAssertEqual(CheckoutLink.validate("https://shop.example.pl/checkout?cart=1")?.host, "shop.example.pl")
        XCTAssertNotNil(CheckoutLink.validate("  https://www.example.com/pay  "))
        XCTAssertNil(CheckoutLink.validate("http://shop.example.pl/checkout"), "https only")
        XCTAssertNil(CheckoutLink.validate("https://user:pass@shop.example.pl/"), "no credentials")
        XCTAssertNil(CheckoutLink.validate("https://192.168.1.10/pay"), "no IP addresses")
        XCTAssertNil(CheckoutLink.validate("https://[::1]/pay"), "no IPv6 addresses")
        XCTAssertNil(CheckoutLink.validate("https://localhost/pay"))
        XCTAssertNil(CheckoutLink.validate("https://intranet/pay"), "a real public name has a dot")
        XCTAssertNil(CheckoutLink.validate("javascript:alert(1)"))
        XCTAssertNil(CheckoutLink.validate("https://example.com/" + String(repeating: "a", count: 2_100)))
    }

    func testTheApplePaySheetNamesWhoIsReallyPaid() throws {
        let prepared = try decodePurchase(PurchasePrepareResult.self, "prepare-result-native")
        let sheet = ApplePaySheet(prepared: prepared)
        XCTAssertEqual(sheet.lines.map(\.label), ["Kino Muranów (test, no real money)", "Doddy (test)"])
        XCTAssertEqual(sheet.lines.last?.amount, Decimal(56))
        XCTAssertEqual(sheet.currency, "PLN")
        XCTAssertEqual(sheet.countryCode, "PL")
    }

    func testBlikPollingCoversTheCodesLifetimeAndStartsQuickly() {
        let delays = PurchasePolling.delays()
        XCTAssertEqual(delays.reduce(0, +), PurchasePolling.blikWindowSeconds, accuracy: 0.001)
        XCTAssertEqual(delays.first, 2)
        XCTAssertTrue(delays.allSatisfy { $0 > 0 && $0 <= 8 })
        XCTAssertLessThan(delays.count, 40, "a status check every few seconds, not a flood")
    }
}

final class VoicePurchaseToolTests: XCTestCase {
    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.preparePurchase, parametersJSON: Data(json.utf8))
    }

    private func reason(_ request: VoiceToolRequest) -> String? {
        if case .invalid(_, let reason) = request { return reason }
        return nil
    }

    func testANativePurchase() {
        let request = parse(#"{"kind":"native","merchant":"Kino Muranów","description":"2 tickets, Friday 19:30","amount_pln":56}"#)
        XCTAssertEqual(request, .preparePurchase(PurchaseDraft(
            kind: .native, merchantName: "Kino Muranów", description: "2 tickets, Friday 19:30", amountMinor: 5_600, checkoutURL: nil)))
    }

    func testACheckoutPurchase() {
        let request = parse(#"{"kind":"checkout","merchant":"Bistro","description":"Pad thai","amount_pln":74.5,"checkout_url":"https://shop.example.pl/checkout"}"#)
        guard case .preparePurchase(let draft) = request else { return XCTFail("\(request)") }
        XCTAssertEqual(draft.kind, .checkout)
        XCTAssertEqual(draft.amountMinor, 7_450)
        XCTAssertEqual(draft.checkoutURL?.absoluteString, "https://shop.example.pl/checkout")
        XCTAssertEqual(draft.request.checkoutUrl, "https://shop.example.pl/checkout")
    }

    func testRefusalsTellTheAgentWhy() {
        XCTAssertEqual(reason(parse(#"{"kind":"later","merchant":"A","description":"B","amount_pln":5}"#)), "kind must be native or checkout")
        XCTAssertEqual(reason(parse(#"{"kind":"native","description":"B","amount_pln":5}"#)), "missing merchant")
        XCTAssertEqual(reason(parse(#"{"kind":"native","merchant":"A","amount_pln":5}"#)), "missing description")
        XCTAssertEqual(reason(parse(#"{"kind":"native","merchant":"A","description":"B"}"#)), "missing amount_pln")
        XCTAssertEqual(reason(parse(#"{"kind":"native","merchant":"A","description":"B","amount_pln":5,"currency":"EUR"}"#)), "only PLN is supported")
        XCTAssertNotNil(reason(parse(#"{"kind":"native","merchant":"A","description":"B","amount_pln":5.555}"#)))
        XCTAssertNotNil(reason(parse(#"{"kind":"native","merchant":"A","description":"B","amount_pln":1.5}"#)), "Stripe's PLN minimum is 2 zł")
        XCTAssertEqual(reason(parse(#"{"kind":"native","merchant":"A","description":"B","amount_pln":5,"checkout_url":"https://a.pl/x"}"#)), "checkout_url is only for kind checkout")
        XCTAssertEqual(reason(parse(#"{"kind":"checkout","merchant":"A","description":"B","amount_pln":5}"#)), "missing checkout_url")
        XCTAssertEqual(reason(parse(#"{"kind":"checkout","merchant":"A","description":"B","amount_pln":5,"checkout_url":"http://a.pl/x"}"#)), "checkout_url must be the shop's https page")
        let longMerchant = String(repeating: "m", count: 81)
        XCTAssertNotNil(reason(parse(#"{"kind":"native","merchant":"\#(longMerchant)","description":"B","amount_pln":5}"#)))
    }

    func testItNeedsThePaymentsSwitchAndStopsWhilePausedOrDriving() {
        let draft = PurchaseDraft(kind: .native, merchantName: "A", description: "B", amountMinor: 500, checkoutURL: nil)
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.preparePurchase, request: .preparePurchase(draft), translatorOn: false,
                                       pauseAll: false, isOn: { $0 != .payments }), .notConnected(.payments))
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.preparePurchase, request: .preparePurchase(draft), translatorOn: false,
                                       pauseAll: true, isOn: { _ in true }), .paused)
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.preparePurchase, request: .preparePurchase(draft), translatorOn: true,
                                       pauseAll: false, isOn: { _ in true }), .translatorRefused)
        if case .refuse = CarProfile.decision(for: .preparePurchase(draft)) {} else { XCTFail("paying must wait until the user isn't driving") }
    }

    func testTheActivityRowKeepsTheShopAndPriceButNoPaymentDetails() {
        let native = ActivityRequest.describe(.preparePurchase(PurchaseDraft(
            kind: .native, merchantName: "Kino", description: "2 tickets", amountMinor: 5_600, checkoutURL: nil)), calendar: .current)
        XCTAssertEqual(native?.app, .payments)
        XCTAssertEqual(native?.title, "Pay for something")
        XCTAssertEqual(native?.detail, "\u{201C}Kino\u{201D} · 56,00 zł")
        let checkout = ActivityRequest.describe(.preparePurchase(PurchaseDraft(
            kind: .checkout, merchantName: "Bistro", description: "Lunch", amountMinor: 4_000,
            checkoutURL: URL(string: "https://Shop.Example.pl/x"))), calendar: .current)
        XCTAssertEqual(checkout?.title, "Open a checkout")
        XCTAssertEqual(checkout?.detail, "\u{201C}Bistro\u{201D} · shop.example.pl")
    }
}

final class PurchaseRepliesTests: XCTestCase {
    private func purchase(_ status: PurchaseStatus, testMode: Bool = true, summary: String = "Summary.") -> PurchaseView {
        PurchaseView(
            id: UUID(), kind: .native, merchantName: "Kino", description: "2 tickets", amountMinor: 5_600, currency: "PLN",
            checkoutHost: nil, status: status, method: .applePay, testMode: testMode, summary: summary,
            createdAt: "2026-10-18T10:00:00.000Z", updatedAt: "2026-10-18T10:00:00.000Z")
    }

    private func outcome(_ reply: String) -> ActivityOutcome {
        ActivityEntry.outcome(of: reply, isLookup: false).0
    }

    func testOnlyAConfirmedPaymentIsDone() {
        XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(purchase(.paid))), .done)
        XCTAssertTrue(VoiceToolReply.purchaseOutcome(purchase(.paid)).contains("test payment with no real money"))
        XCTAssertFalse(VoiceToolReply.purchaseOutcome(purchase(.paid, testMode: false)).contains("test payment"))
        XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(purchase(.failed))), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(purchase(.expired))), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(purchase(.cancelled))), .declined)
        for unsure in [PurchaseStatus.outcomeUnknown, .paying, .waitingForBank, .awaitingTap] {
            XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(purchase(unsure))), .notSure, "\(unsure)")
        }
        // A hand-off is "Opened", even when the user says they paid: Doddy didn't see it.
        XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(purchase(.handedOff))), .opened)
        XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(purchase(.userReportedPaid))), .opened)
        XCTAssertEqual(outcome(VoiceToolReply.purchaseLost("Kino")), .notSure)
    }

    func testAShopsSummaryCantFakeASuccess() {
        // The server's summary follows the result word; a summary that says "paid:" changes nothing.
        let sneaky = purchase(.failed, summary: "paid: yes it worked")
        XCTAssertEqual(outcome(VoiceToolReply.purchaseOutcome(sneaky)), .notDone)
    }

    func testNotPreparedNeverSaysAnythingWasPaid() {
        for error in [PaymentsError.notConfigured, .unauthenticated, .transport("x"), .unreadableResponse,
                      .server(code: "capability_disabled", message: "Over today's limit.", retryAfterSeconds: nil)] {
            let reply = VoiceToolReply.purchaseNotPrepared(error)
            XCTAssertTrue(reply.hasPrefix("failed: "), reply)
            XCTAssertTrue(reply.hasSuffix("Nothing was paid."), reply)
            XCTAssertEqual(outcome(reply), .notDone)
        }
    }
}
