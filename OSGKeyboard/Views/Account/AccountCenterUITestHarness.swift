// AccountCenterUITestHarness.swift
// OSGKeyboard · Main App
//
// Deterministic account and StoreKit UI integration harness. It exercises the
// production coordinator and views while keeping Apple and backend services
// outside XCUITest.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

@MainActor
struct AccountCenterUITestHarness: View {
    @StateObject private var coordinator: AccountSessionCoordinator

    init() {
        let service = AccountCenterUITestService()
        let store = AccountCenterUITestCreditStore(accountID: service.account.accountID)
        _coordinator = StateObject(
            wrappedValue: AccountSessionCoordinator(
                dependencies: AccountDependencies(
                    sessionService: service,
                    centerService: service
                ),
                creditStore: store
            )
        )
    }

    var body: some View {
        ThemedRoot {
            NavigationStack {
                AccountCenterView()
                    .environmentObject(coordinator)
            }
        }
        .task {
            await coordinator.restoreIfNeeded()
        }
    }
}

@MainActor
struct ManagedCloudConsentUITestHarness: View {
    @ObservedObject private var config = ProviderConfig.shared
    @StateObject private var coordinator: AccountSessionCoordinator

    init() {
        let service = AccountCenterUITestService()
        let configuration = ProviderConfig.shared
        configuration.hasAcknowledgedCloudSharing = false
        configuration.credentialSource = .byok
        _coordinator = StateObject(
            wrappedValue: AccountSessionCoordinator(
                dependencies: AccountDependencies(
                    sessionService: service,
                    centerService: service
                ),
                creditStore: AccountCenterUITestCreditStore(
                    accountID: service.account.accountID
                )
            )
        )
    }

    var body: some View {
        ThemedRoot {
            NavigationStack {
                ScrollView {
                    EnginePickerSection(config: config)
                        .environmentObject(coordinator)
                        .padding()
                }
                .navigationTitle("settings.aiService.title")
            }
        }
        .task {
            await coordinator.restoreIfNeeded()
        }
    }
}

private actor AccountCenterUITestService: AccountSessionServicing, AccountCenterServicing {
    nonisolated let account = AccountSession(
        accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000200")!,
        createdAtEpochSeconds: 1_700_000_000,
        displayName: "UI Test Account"
    )

    func restoreSession() async throws -> AccountSession? {
        account
    }

    func signIn(with payload: AppleAuthorizationPayload) async throws -> AccountSession {
        _ = payload
        return account
    }

    func signOut() async throws {}

    func deleteAccount(with payload: AppleAuthorizationPayload) async throws {
        _ = payload
    }

    func loadAccountCenter() async throws -> AccountCenterSnapshot {
        AccountCenterSnapshot(
            account: account,
            credits: AccountCreditSummary(balance: 1_500, usedCredits: 500),
            referralProfile: AccountReferralProfile(code: nil, boundCode: nil),
            referrals: []
        )
    }

    func updateDisplayName(_ displayName: String) async throws -> AccountSession {
        AccountSession(
            accountID: account.accountID,
            createdAtEpochSeconds: account.createdAtEpochSeconds,
            displayName: displayName
        )
    }

    func createReferralCode() async throws -> String {
        "UITestInvite_1234567890"
    }

    func redeemReferral(code: String) async throws {
        _ = code
    }

    func loadCreditProducts() async throws -> [AccountCreditProduct] {
        [
            AccountCreditProduct(productID: "500tks", credits: 500),
            AccountCreditProduct(productID: "1500tks", credits: 1_500),
            AccountCreditProduct(productID: "3000tks", credits: 3_000)
        ]
    }

    func submitCreditTransaction(_ signedTransaction: String) async throws -> AccountCreditPurchase {
        _ = signedTransaction
        return AccountCreditPurchase(
            transactionID: "2000000000200",
            productID: "500tks",
            creditsGranted: 500,
            balanceAfter: 2_000,
            replayed: false
        )
    }

    func loadCreditPurchaseHistory(
        limit: Int,
        cursor: String?
    ) async throws -> AccountCreditPurchaseHistoryPage {
        _ = limit
        _ = cursor
        return AccountCreditPurchaseHistoryPage(
            items: [
                AccountCreditPurchaseRecord(
                    transactionID: "2000000000199",
                    productID: "1500tks",
                    creditsGranted: 1_500,
                    balanceAfter: 1_500,
                    purchasedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    status: .credited
                )
            ],
            nextCursor: nil
        )
    }
}

@MainActor
private final class AccountCenterUITestCreditStore: AccountCreditStore {
    private let accountID: UUID
    private var transactions: [AccountStoreVerification]

    init(accountID: UUID) {
        self.accountID = accountID
        transactions = [
            .verified(
                AccountStoreTransaction(
                    id: 2_000_000_000_199,
                    productID: "1500tks",
                    appAccountToken: accountID,
                    purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
                    signedTransaction: String(repeating: "h", count: 100),
                    finishOperation: {}
                )
            )
        ]
    }

    func product(for productID: String) async throws -> AccountStoreProduct? {
        let price: String
        switch productID {
        case "500tks":
            price = "$0.99"
        case "1500tks":
            price = "$1.99"
        case "3000tks":
            price = "$2.99"
        default:
            return nil
        }
        return AccountStoreProduct(id: productID, displayPrice: price)
    }

    func purchase(
        productID: String,
        accountID: UUID
    ) async throws -> AccountStorePurchaseOutcome {
        guard productID == "500tks", accountID == self.accountID else {
            return .success(.unverified)
        }
        let transaction = AccountStoreTransaction(
            id: 2_000_000_000_200,
            productID: productID,
            appAccountToken: accountID,
            purchaseDate: Date(),
            signedTransaction: String(repeating: "p", count: 100),
            finishOperation: {}
        )
        let verification = AccountStoreVerification.verified(transaction)
        transactions.append(verification)
        return .success(verification)
    }

    func unfinishedTransactions() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }

    func transactionUpdates() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }

    func allTransactions() -> AsyncStream<AccountStoreVerification> {
        let values = transactions
        return AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
#endif
