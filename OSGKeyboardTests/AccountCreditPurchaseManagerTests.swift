// AccountCreditPurchaseManagerTests.swift
// OSGKeyboardTests

@testable import OSGKeyboard
import XCTest

@MainActor
final class AccountCreditPurchaseManagerTests: XCTestCase {
    func testVerifiedPurchaseFinishesOnlyAfterServerAcknowledgement() async {
        let accountID = UUID()
        let service = CreditServiceStub(
            purchase: AccountCreditPurchase(
                transactionID: "2000000000001",
                productID: productID,
                creditsGranted: 3_000,
                balanceAfter: 4_000,
                replayed: false
            )
        )
        let finishRecorder = FinishRecorder()
        let transaction = AccountStoreTransaction(
            id: 2_000_000_000_001,
            productID: productID,
            appAccountToken: accountID,
            signedTransaction: signedTransaction,
            finishOperation: { await finishRecorder.record() }
        )
        let store = CreditStoreStub(outcome: .success(.verified(transaction)))
        let manager = AccountCreditPurchaseManager(service: service, store: store)

        await manager.prepare(accountID: accountID)
        XCTAssertEqual(
            manager.options,
            [
                AccountCreditPurchaseOption(
                    productID: "500tks",
                    credits: 500,
                    displayPrice: "$0.99"
                ),
                AccountCreditPurchaseOption(
                    productID: "1500tks",
                    credits: 1_500,
                    displayPrice: "$1.99"
                ),
                AccountCreditPurchaseOption(
                    productID: "3000tks",
                    credits: 3_000,
                    displayPrice: "$2.99"
                )
            ]
        )
        let purchased = await manager.purchase(productID: productID, accountID: accountID)

        XCTAssertTrue(purchased)
        XCTAssertEqual(manager.state, .succeeded(credits: 3_000))
        XCTAssertEqual(manager.lastGrantedBalance, 4_000)
        let submissions = await service.submittedTransactions()
        let finishedCount = await finishRecorder.count()
        XCTAssertEqual(submissions, [signedTransaction])
        XCTAssertEqual(finishedCount, 1)

        manager.dismissSuccessMessage()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.lastGrantedBalance, 4_000)
    }

    func testMismatchedAccountTransactionIsRejectedWithoutServerSubmissionOrFinish() async {
        let accountID = UUID()
        let service = CreditServiceStub(
            purchase: AccountCreditPurchase(
                transactionID: "2000000000001",
                productID: productID,
                creditsGranted: 3_000,
                balanceAfter: 4_000,
                replayed: false
            )
        )
        let finishRecorder = FinishRecorder()
        let transaction = AccountStoreTransaction(
            id: 2_000_000_000_001,
            productID: productID,
            appAccountToken: UUID(),
            signedTransaction: signedTransaction,
            finishOperation: { await finishRecorder.record() }
        )
        let store = CreditStoreStub(outcome: .success(.verified(transaction)))
        let manager = AccountCreditPurchaseManager(service: service, store: store)

        await manager.prepare(accountID: accountID)
        let purchased = await manager.purchase(productID: productID, accountID: accountID)

        XCTAssertFalse(purchased)
        XCTAssertEqual(manager.state, .failed(messageKey: "account.storekit.error.verification"))
        let submissions = await service.submittedTransactions()
        let finishedCount = await finishRecorder.count()
        XCTAssertEqual(submissions, [])
        XCTAssertEqual(finishedCount, 0)
    }

    func testPendingPurchaseRemainsUnfinishedAndCanReturnToIdle() async {
        let accountID = UUID()
        let service = CreditServiceStub(purchase: nil)
        let store = CreditStoreStub(outcome: .pending)
        let manager = AccountCreditPurchaseManager(service: service, store: store)

        await manager.prepare(accountID: accountID)
        let purchased = await manager.purchase(productID: productID, accountID: accountID)

        XCTAssertFalse(purchased)
        XCTAssertEqual(manager.state, .pending)
        manager.clearTransientState()
        XCTAssertEqual(manager.state, .idle)
    }

    func testPurchaseHistoryLoadsServerPagesAndRemovesDuplicates() async {
        let accountID = UUID()
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerRecord = AccountCreditPurchaseRecord(
            transactionID: "2",
            productID: "3000tks",
            creditsGranted: 3_000,
            balanceAfter: 4_000,
            purchasedAt: newerDate,
            status: .credited
        )
        let olderRecord = AccountCreditPurchaseRecord(
            transactionID: "1",
            productID: "500tks",
            creditsGranted: 500,
            balanceAfter: 1_000,
            purchasedAt: olderDate,
            status: .credited
        )
        let service = CreditServiceStub(
            purchase: nil,
            historyPages: [
                AccountCreditPurchaseHistoryPage(
                    items: [newerRecord],
                    nextCursor: "next"
                ),
                AccountCreditPurchaseHistoryPage(
                    items: [newerRecord, olderRecord],
                    nextCursor: nil
                )
            ]
        )
        let manager = AccountCreditPurchaseManager(
            service: service,
            store: CreditStoreStub(outcome: .pending)
        )

        await manager.prepare(accountID: accountID)
        await manager.loadPurchaseHistory(accountID: accountID)
        XCTAssertEqual(manager.historyPhase, .loaded([newerRecord]))

        await manager.loadNextPurchaseHistoryPage(accountID: accountID)

        XCTAssertEqual(manager.historyPhase, .loaded([newerRecord, olderRecord]))
        let requests = await service.historyRequests()
        XCTAssertEqual(requests, ["50:<nil>", "50:next"])
    }

    func testUnknownCatalogProductCannotStartPurchase() async {
        let accountID = UUID()
        let service = CreditServiceStub(purchase: nil)
        let store = CreditStoreStub(outcome: .pending)
        let manager = AccountCreditPurchaseManager(service: service, store: store)

        await manager.prepare(accountID: accountID)
        let purchased = await manager.purchase(productID: "unknown", accountID: accountID)

        XCTAssertFalse(purchased)
        XCTAssertEqual(
            manager.state,
            .failed(messageKey: "account.storekit.error.productUnavailable")
        )
    }

    private let productID = "3000tks"
    private let signedTransaction = String(repeating: "s", count: 100)
}

private actor CreditServiceStub: AccountCenterServicing {
    private let purchase: AccountCreditPurchase?
    private let historyPages: [AccountCreditPurchaseHistoryPage]
    private var submissions: [String] = []
    private var historyPageIndex = 0
    private var recordedHistoryRequests: [String] = []

    init(
        purchase: AccountCreditPurchase?,
        historyPages: [AccountCreditPurchaseHistoryPage] = []
    ) {
        self.purchase = purchase
        self.historyPages = historyPages
    }

    func loadAccountCenter() async throws -> AccountCenterSnapshot {
        throw AccountIntegrationError.unavailable
    }

    func createReferralCode() async throws -> String {
        throw AccountIntegrationError.unavailable
    }

    func redeemReferral(code: String) async throws {
        throw AccountIntegrationError.unavailable
    }

    func loadCreditProducts() async throws -> [AccountCreditProduct] {
        [
            AccountCreditProduct(productID: "3000tks", credits: 3_000),
            AccountCreditProduct(productID: "1500tks", credits: 1_500),
            AccountCreditProduct(productID: "500tks", credits: 500)
        ]
    }

    func submitCreditTransaction(_ signedTransaction: String) async throws -> AccountCreditPurchase {
        submissions.append(signedTransaction)
        guard let purchase else { throw AccountIntegrationError.unavailable }
        return purchase
    }

    func loadCreditPurchaseHistory(
        limit: Int,
        cursor: String?
    ) async throws -> AccountCreditPurchaseHistoryPage {
        recordedHistoryRequests.append("\(limit):\(cursor ?? "<nil>")")
        guard historyPageIndex < historyPages.count else {
            throw AccountIntegrationError.unavailable
        }
        defer { historyPageIndex += 1 }
        return historyPages[historyPageIndex]
    }

    func submittedTransactions() -> [String] {
        submissions
    }

    func historyRequests() -> [String] {
        recordedHistoryRequests
    }
}

@MainActor
private final class CreditStoreStub: AccountCreditStore {
    private let outcome: AccountStorePurchaseOutcome

    init(outcome: AccountStorePurchaseOutcome) {
        self.outcome = outcome
    }

    func product(for productID: String) async throws -> AccountStoreProduct? {
        let displayPrice: String
        switch productID {
        case "500tks":
            displayPrice = "$0.99"
        case "1500tks":
            displayPrice = "$1.99"
        default:
            displayPrice = "$2.99"
        }
        return AccountStoreProduct(
            id: productID,
            displayPrice: displayPrice
        )
    }

    func purchase(productID: String, accountID: UUID) async throws -> AccountStorePurchaseOutcome {
        outcome
    }

    func unfinishedTransactions() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }

    func transactionUpdates() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }

    func allTransactions() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }
}

private actor FinishRecorder {
    private var finishedCount = 0

    func record() {
        finishedCount += 1
    }

    func count() -> Int {
        finishedCount
    }
}
