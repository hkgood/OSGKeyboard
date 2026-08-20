// AccountCreditPurchaseManager.swift
// OSGKeyboard · Main App
//
// StoreKit credit purchases are isolated from the voluntary tip product.
// Transactions finish only after the account server verifies and records them.

import Combine
import Foundation
import OSGKeyboardHostSupport
import OSGKeyboardShared

struct AccountCreditPurchaseOption: Identifiable, Equatable {
    var id: String { productID }

    let productID: String
    let credits: Int64
    let displayPrice: String
}

@MainActor
final class AccountCreditPurchaseManager: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case purchasing(productID: String)
        case pending
        case succeeded(credits: Int64)
        case failed(messageKey: String)
    }

    enum HistoryPhase: Equatable {
        case idle
        case loading
        case loaded([AccountCreditPurchaseRecord])
        case failed(messageKey: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var options: [AccountCreditPurchaseOption] = []
    @Published private(set) var lastGrantedBalance: Int64?
    @Published private(set) var historyPhase: HistoryPhase = .idle
    @Published private(set) var isLoadingMoreHistory = false
    @Published private(set) var historyLoadMoreErrorKey: String?

    private let service: any AccountCenterServicing
    private let store: any AccountCreditStore
    private let analyticsClient: any AnalyticsClient
    private var updatesTask: Task<Void, Never>?
    private var activeAccountID: UUID?
    private var configuredProductIDs: Set<String> = []
    private var nextHistoryCursor: String?

    init(
        service: any AccountCenterServicing,
        store: any AccountCreditStore = LiveAccountCreditStore(),
        analyticsClient: any AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.service = service
        self.store = store
        self.analyticsClient = analyticsClient
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare(accountID: UUID) async {
        guard activeAccountID != accountID || options.isEmpty else { return }
        reset(for: accountID)
        state = .loading
        do {
            let catalog = try await service.loadCreditProducts()
            configuredProductIDs = Set(catalog.map(\.productID))
            var loadedOptions: [AccountCreditPurchaseOption] = []
            for creditProduct in catalog {
                guard let product = try await store.product(for: creditProduct.productID) else {
                    continue
                }
                loadedOptions.append(
                    AccountCreditPurchaseOption(
                        productID: creditProduct.productID,
                        credits: creditProduct.credits,
                        displayPrice: product.displayPrice
                    )
                )
            }
            guard !loadedOptions.isEmpty else {
                throw AccountCreditPurchaseError.productUnavailable
            }
            options = loadedOptions.sorted { $0.credits < $1.credits }
            state = .idle
            listenForUpdates(accountID: accountID)
            _ = await reconcileUnfinished(accountID: accountID)
        } catch {
            state = .failed(messageKey: Self.messageKey(for: error))
        }
    }

    @discardableResult
    func purchase(productID: String, accountID: UUID) async -> Bool {
        guard activeAccountID == accountID,
              options.contains(where: { $0.productID == productID }) else {
            state = .failed(messageKey: "account.storekit.error.productUnavailable")
            return false
        }
        state = .purchasing(productID: productID)
        analyticsClient.recordPurchaseStarted()
        do {
            switch try await store.purchase(productID: productID, accountID: accountID) {
            case .success(let verification):
                try await process(verification, accountID: accountID)
                return true
            case .pending:
                state = .pending
            case .userCancelled:
                state = .idle
                analyticsClient.recordPurchaseCancelled()
            @unknown default:
                state = .failed(messageKey: "account.storekit.error.unknown")
            }
        } catch {
            state = .failed(messageKey: Self.messageKey(for: error))
        }
        return false
    }

    func recordPurchaseViewed() {
        analyticsClient.recordPurchaseViewed()
    }

    func clearTransientState() {
        switch state {
        case .succeeded, .failed, .pending:
            state = .idle
        default:
            break
        }
    }

    func dismissSuccessMessage() {
        guard case .succeeded = state else { return }
        state = .idle
    }

    func loadPurchaseHistory(accountID: UUID, force: Bool = false) async {
        guard activeAccountID == accountID else {
            historyPhase = .loaded([])
            return
        }
        if !force, case .loaded = historyPhase {
            return
        }

        historyPhase = .loading
        historyLoadMoreErrorKey = nil
        do {
            let page = try await service.loadCreditPurchaseHistory(
                limit: 50,
                cursor: nil
            )
            guard activeAccountID == accountID else { return }
            nextHistoryCursor = page.nextCursor
            historyPhase = .loaded(page.items)
        } catch {
            guard activeAccountID == accountID else { return }
            nextHistoryCursor = nil
            historyPhase = .failed(messageKey: "account.purchaseHistory.error")
        }
    }

    func loadNextPurchaseHistoryPage(accountID: UUID) async {
        guard activeAccountID == accountID,
              !isLoadingMoreHistory,
              let cursor = nextHistoryCursor,
              case .loaded(let currentItems) = historyPhase else {
            return
        }

        isLoadingMoreHistory = true
        historyLoadMoreErrorKey = nil
        defer { isLoadingMoreHistory = false }
        do {
            let page = try await service.loadCreditPurchaseHistory(
                limit: 50,
                cursor: cursor
            )
            guard activeAccountID == accountID,
                  case .loaded = historyPhase else {
                return
            }
            let existingIDs = Set(currentItems.map(\.transactionID))
            let newItems = page.items.filter { !existingIDs.contains($0.transactionID) }
            nextHistoryCursor = page.nextCursor
            historyPhase = .loaded(currentItems + newItems)
        } catch {
            guard activeAccountID == accountID else { return }
            historyLoadMoreErrorKey = "account.purchaseHistory.loadMoreError"
        }
    }

    func reset() {
        updatesTask?.cancel()
        updatesTask = nil
        activeAccountID = nil
        options = []
        configuredProductIDs = []
        lastGrantedBalance = nil
        historyPhase = .idle
        isLoadingMoreHistory = false
        historyLoadMoreErrorKey = nil
        nextHistoryCursor = nil
        state = .idle
    }

    @discardableResult
    private func reconcileUnfinished(accountID: UUID) async -> Bool {
        var reconciled = false
        for await verification in store.unfinishedTransactions() {
            guard !Task.isCancelled else { break }
            do {
                try await process(verification, accountID: accountID)
                reconciled = true
            } catch {
                state = .failed(messageKey: Self.messageKey(for: error))
            }
        }
        return reconciled
    }

    private func listenForUpdates(accountID: UUID) {
        updatesTask?.cancel()
        let updates = store.transactionUpdates()
        updatesTask = Task { [weak self] in
            for await verification in updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                do {
                    try await self.process(verification, accountID: accountID)
                } catch {
                    self.state = .failed(messageKey: Self.messageKey(for: error))
                }
            }
        }
    }

    private func process(
        _ verification: AccountStoreVerification,
        accountID: UUID
    ) async throws {
        guard case .verified(let transaction) = verification,
              transaction.appAccountToken == accountID,
              configuredProductIDs.contains(transaction.productID) else {
            throw AccountCreditPurchaseError.verificationFailed
        }
        let result = try await service.submitCreditTransaction(transaction.signedTransaction)
        guard result.transactionID == String(transaction.id),
              result.productID == transaction.productID else {
            throw AccountCreditPurchaseError.invalidServerResponse
        }
        await transaction.finish()
        lastGrantedBalance = result.balanceAfter
        historyPhase = .idle
        nextHistoryCursor = nil
        state = .succeeded(credits: result.creditsGranted)
    }

    private func reset(for accountID: UUID) {
        updatesTask?.cancel()
        updatesTask = nil
        activeAccountID = accountID
        options = []
        configuredProductIDs = []
        lastGrantedBalance = nil
        historyPhase = .idle
        isLoadingMoreHistory = false
        historyLoadMoreErrorKey = nil
        nextHistoryCursor = nil
    }

    private static func messageKey(for error: Error) -> String {
        if let purchaseError = error as? AccountCreditPurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return "account.storekit.error.productUnavailable"
            case .verificationFailed:
                return "account.storekit.error.verification"
            case .invalidServerResponse:
                return "account.storekit.error.server"
            }
        }
        if let accountError = error as? AccountAPIError {
            switch accountError {
            case .unauthorized, .sessionUnavailable, .refreshTokenReuse:
                return "account.storekit.error.session"
            case .externalServiceUnavailable, .transport:
                return "account.storekit.error.network"
            case .conflict:
                return "account.storekit.error.conflict"
            default:
                return "account.storekit.error.server"
            }
        }
        return "account.storekit.error.unknown"
    }
}

private enum AccountCreditPurchaseError: Error {
    case productUnavailable
    case verificationFailed
    case invalidServerResponse
}
