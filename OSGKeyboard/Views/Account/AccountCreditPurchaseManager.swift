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
        case purchasing(productID: String)
        case pending
        case succeeded(credits: Int64)
        case failed(messageKey: String)
    }

    enum CatalogPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed(messageKey: String)
    }

    enum HistoryPhase: Equatable {
        case idle
        case loading
        case loaded([AccountCreditPurchaseRecord])
        case failed(messageKey: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var catalogPhase: CatalogPhase = .idle
    @Published private(set) var options: [AccountCreditPurchaseOption] = []
    @Published private(set) var isRefreshingCatalog = false
    @Published private(set) var catalogRefreshErrorKey: String?
    @Published private(set) var lastGrantedBalance: Int64?
    @Published private(set) var historyPhase: HistoryPhase = .idle
    @Published private(set) var isLoadingMoreHistory = false
    @Published private(set) var historyLoadMoreErrorKey: String?

    private let service: any AccountCenterServicing
    private let store: any AccountCreditStore
    private let analyticsClient: any AnalyticsClient
    private let successMessageDuration: Duration
    private var prepareTask: Task<Void, Never>?
    private var prepareRequestID: UUID?
    private var updatesTask: Task<Void, Never>?
    private var successDismissTask: Task<Void, Never>?
    private var activeAccountID: UUID?
    private var sessionID: UUID?
    private var pendingProductID: String?
    private var configuredProductIDs: Set<String> = []
    private var nextHistoryCursor: String?

    init(
        service: any AccountCenterServicing,
        store: any AccountCreditStore = LiveAccountCreditStore(),
        analyticsClient: any AnalyticsClient = NoopAnalyticsClient(),
        successMessageDuration: Duration = .seconds(4)
    ) {
        self.service = service
        self.store = store
        self.analyticsClient = analyticsClient
        self.successMessageDuration = successMessageDuration
    }

    deinit {
        prepareTask?.cancel()
        updatesTask?.cancel()
        successDismissTask?.cancel()
    }

    /// Starts one non-blocking StoreKit preparation for a signed-in account.
    /// Repeated calls for the same account preserve the current session state.
    func startSession(accountID: UUID) {
        guard activeAccountID != accountID else { return }
        reset(for: accountID)
        beginPrepare(accountID: accountID)
    }

    func endSession() {
        reset()
    }

    func prepare(accountID: UUID, force: Bool = false) async {
        if activeAccountID != accountID {
            startSession(accountID: accountID)
        }
        if let prepareTask {
            await prepareTask.value
            return
        }
        if !force, catalogPhase == .loaded, !options.isEmpty {
            return
        }
        beginPrepare(accountID: accountID)
        await prepareTask?.value
    }

    func refreshCatalog(accountID: UUID) async {
        await prepare(accountID: accountID, force: true)
    }

    private func beginPrepare(accountID: UUID) {
        guard activeAccountID == accountID, prepareTask == nil, let sessionID else { return }
        let requestID = UUID()
        prepareRequestID = requestID
        catalogRefreshErrorKey = nil
        isRefreshingCatalog = true
        if options.isEmpty {
            catalogPhase = .loading
        }
        prepareTask = Task { @MainActor [weak self] in
            await self?.performPrepare(
                accountID: accountID,
                sessionID: sessionID,
                requestID: requestID
            )
        }
    }

    private func performPrepare(
        accountID: UUID,
        sessionID: UUID,
        requestID: UUID
    ) async {
        defer { finishPrepare(requestID: requestID) }
        do {
            try Task.checkCancellation()
            let catalog = try await service.loadCreditProducts()
            try Task.checkCancellation()
            guard isCurrentSession(
                accountID: accountID,
                sessionID: sessionID,
                requestID: requestID
            ) else {
                return
            }

            let products = try await loadProductsWithRetry(
                productIDs: catalog.map(\.productID)
            )
            try Task.checkCancellation()
            guard isCurrentSession(
                accountID: accountID,
                sessionID: sessionID,
                requestID: requestID
            ) else {
                return
            }

            let productsByID = products.reduce(into: [String: AccountStoreProduct]()) {
                $0[$1.id] = $1
            }
            let loadedOptions: [AccountCreditPurchaseOption] = catalog.compactMap { creditProduct in
                guard let product = productsByID[creditProduct.productID] else { return nil }
                return AccountCreditPurchaseOption(
                    productID: creditProduct.productID,
                    credits: creditProduct.credits,
                    displayPrice: product.displayPrice
                )
            }
            guard !loadedOptions.isEmpty else {
                throw AccountCreditPurchaseError.productUnavailable
            }
            configuredProductIDs = Set(catalog.map(\.productID))
            options = loadedOptions.sorted { $0.credits < $1.credits }
            catalogPhase = .loaded
            catalogRefreshErrorKey = nil
            listenForUpdates(accountID: accountID, sessionID: sessionID)
            _ = await reconcileUnfinished(accountID: accountID, sessionID: sessionID)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(
                accountID: accountID,
                sessionID: sessionID,
                requestID: requestID
            ) else {
                return
            }
            let messageKey = Self.messageKey(for: error)
            catalogRefreshErrorKey = messageKey
            catalogPhase = options.isEmpty
                ? .failed(messageKey: messageKey)
                : .loaded
        }
    }

    @discardableResult
    func purchase(productID: String, accountID: UUID) async -> Bool {
        guard activeAccountID == accountID,
              let sessionID,
              options.contains(where: { $0.productID == productID }) else {
            state = .failed(messageKey: "account.storekit.error.productUnavailable")
            return false
        }
        state = .purchasing(productID: productID)
        pendingProductID = nil
        cancelSuccessDismissal()
        analyticsClient.recordPurchaseStarted()
        do {
            switch try await store.purchase(productID: productID, accountID: accountID) {
            case .success(let verification):
                let result = try await process(
                    verification,
                    accountID: accountID,
                    sessionID: sessionID
                )
                presentSuccess(credits: result.creditsGranted)
                return true
            case .pending:
                pendingProductID = productID
                state = .pending
            case .userCancelled:
                pendingProductID = nil
                state = .idle
                analyticsClient.recordPurchaseCancelled()
            @unknown default:
                pendingProductID = nil
                state = .failed(messageKey: "account.storekit.error.unknown")
            }
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrentSession(accountID: accountID, sessionID: sessionID) else {
                return false
            }
            pendingProductID = nil
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
            pendingProductID = nil
            cancelSuccessDismissal()
            state = .idle
        default:
            break
        }
    }

    func dismissSuccessMessage() {
        guard case .succeeded = state else { return }
        cancelSuccessDismissal()
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
        prepareTask?.cancel()
        prepareTask = nil
        prepareRequestID = nil
        updatesTask?.cancel()
        updatesTask = nil
        successDismissTask?.cancel()
        successDismissTask = nil
        activeAccountID = nil
        sessionID = nil
        pendingProductID = nil
        catalogPhase = .idle
        options = []
        isRefreshingCatalog = false
        catalogRefreshErrorKey = nil
        configuredProductIDs = []
        lastGrantedBalance = nil
        historyPhase = .idle
        isLoadingMoreHistory = false
        historyLoadMoreErrorKey = nil
        nextHistoryCursor = nil
        state = .idle
    }

    @discardableResult
    private func reconcileUnfinished(accountID: UUID, sessionID: UUID) async -> Bool {
        var reconciled = false
        for await verification in store.unfinishedTransactions() {
            guard !Task.isCancelled else { break }
            guard isCurrentSession(accountID: accountID, sessionID: sessionID) else {
                break
            }
            do {
                _ = try await process(
                    verification,
                    accountID: accountID,
                    sessionID: sessionID
                )
                reconciled = true
            } catch is CancellationError {
                break
            } catch {
                // Historical recovery is background maintenance; it must not
                // replace the current purchase action with stale UI feedback.
                continue
            }
        }
        return reconciled
    }

    private func listenForUpdates(accountID: UUID, sessionID: UUID) {
        updatesTask?.cancel()
        let updates = store.transactionUpdates()
        updatesTask = Task { [weak self] in
            for await verification in updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.isCurrentSession(
                    accountID: accountID,
                    sessionID: sessionID
                ) else {
                    return
                }
                do {
                    let result = try await self.process(
                        verification,
                        accountID: accountID,
                        sessionID: sessionID
                    )
                    if self.pendingProductID == result.productID {
                        self.pendingProductID = nil
                        self.presentSuccess(credits: result.creditsGranted)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.isCurrentSession(
                        accountID: accountID,
                        sessionID: sessionID
                    ), self.pendingProductID != nil else {
                        continue
                    }
                    self.pendingProductID = nil
                    self.state = .failed(messageKey: Self.messageKey(for: error))
                }
            }
        }
    }

    private func process(
        _ verification: AccountStoreVerification,
        accountID: UUID,
        sessionID: UUID
    ) async throws -> AccountCreditPurchase {
        guard isCurrentSession(accountID: accountID, sessionID: sessionID),
              case .verified(let transaction) = verification,
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
        guard isCurrentSession(accountID: accountID, sessionID: sessionID) else {
            throw CancellationError()
        }
        lastGrantedBalance = result.balanceAfter
        historyPhase = .idle
        nextHistoryCursor = nil
        return result
    }

    private func reset(for accountID: UUID) {
        prepareTask?.cancel()
        prepareTask = nil
        prepareRequestID = nil
        updatesTask?.cancel()
        updatesTask = nil
        successDismissTask?.cancel()
        successDismissTask = nil
        activeAccountID = accountID
        sessionID = UUID()
        pendingProductID = nil
        catalogPhase = .idle
        options = []
        isRefreshingCatalog = false
        catalogRefreshErrorKey = nil
        configuredProductIDs = []
        lastGrantedBalance = nil
        historyPhase = .idle
        isLoadingMoreHistory = false
        historyLoadMoreErrorKey = nil
        nextHistoryCursor = nil
        state = .idle
    }

    /// Success is acknowledgement of the current purchase action, not durable
    /// transaction history. Expire it even when a retained tab never disappears.
    private func presentSuccess(credits: Int64) {
        cancelSuccessDismissal()
        state = .succeeded(credits: credits)
        let expectedSessionID = sessionID
        let duration = successMessageDuration
        successDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self,
                  self.sessionID == expectedSessionID,
                  self.state == .succeeded(credits: credits) else {
                return
            }
            self.state = .idle
            self.successDismissTask = nil
        }
    }

    private func cancelSuccessDismissal() {
        successDismissTask?.cancel()
        successDismissTask = nil
    }

    private func finishPrepare(requestID: UUID) {
        guard prepareRequestID == requestID else { return }
        prepareTask = nil
        prepareRequestID = nil
        isRefreshingCatalog = false
    }

    private func isCurrentSession(
        accountID: UUID,
        sessionID: UUID,
        requestID: UUID? = nil
    ) -> Bool {
        guard activeAccountID == accountID, self.sessionID == sessionID else {
            return false
        }
        if let requestID {
            return prepareRequestID == requestID
        }
        return true
    }

    private func loadProductsWithRetry(
        productIDs: [String]
    ) async throws -> [AccountStoreProduct] {
        let expectedIDs = Set(productIDs)
        var lastLoaded: [AccountStoreProduct] = []
        var lastError: Error?
        let retryDelays: [Duration] = [.zero, .milliseconds(200), .milliseconds(600)]

        for delay in retryDelays {
            if delay != .zero {
                try await Task.sleep(for: delay)
            }
            try Task.checkCancellation()
            do {
                let loaded = try await store.products(for: productIDs)
                lastLoaded = loaded
                if Set(loaded.map(\.id)).isSuperset(of: expectedIDs) {
                    return loaded
                }
            } catch {
                lastError = error
            }
        }

        if !lastLoaded.isEmpty {
            return lastLoaded
        }
        if let lastError {
            throw lastError
        }
        return []
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
