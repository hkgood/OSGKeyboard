// AccountCreditStore.swift
// OSGKeyboard · Main App
//
// Isolates StoreKit so purchase orchestration remains hermetic and testable.

import Foundation
import StoreKit

struct AccountStoreProduct: Equatable, Sendable {
    let id: String
    let displayPrice: String
}

struct AccountStoreTransaction: Sendable {
    let id: UInt64
    let productID: String
    let appAccountToken: UUID?
    let purchaseDate: Date
    let signedTransaction: String

    private let finishOperation: @Sendable () async -> Void

    init(
        id: UInt64,
        productID: String,
        appAccountToken: UUID?,
        purchaseDate: Date = .distantPast,
        signedTransaction: String,
        finishOperation: @escaping @Sendable () async -> Void
    ) {
        self.id = id
        self.productID = productID
        self.appAccountToken = appAccountToken
        self.purchaseDate = purchaseDate
        self.signedTransaction = signedTransaction
        self.finishOperation = finishOperation
    }

    func finish() async {
        await finishOperation()
    }
}

enum AccountStoreVerification: Sendable {
    case verified(AccountStoreTransaction)
    case unverified
}

enum AccountStorePurchaseOutcome: Sendable {
    case success(AccountStoreVerification)
    case pending
    case userCancelled
}

@MainActor
protocol AccountCreditStore {
    func product(for productID: String) async throws -> AccountStoreProduct?
    func products(for productIDs: [String]) async throws -> [AccountStoreProduct]
    func purchase(productID: String, accountID: UUID) async throws -> AccountStorePurchaseOutcome
    func unfinishedTransactions() -> AsyncStream<AccountStoreVerification>
    func transactionUpdates() -> AsyncStream<AccountStoreVerification>
    func allTransactions() -> AsyncStream<AccountStoreVerification>
}

extension AccountCreditStore {
    func products(for productIDs: [String]) async throws -> [AccountStoreProduct] {
        var loadedProducts: [AccountStoreProduct] = []
        for productID in productIDs {
            if let product = try await product(for: productID) {
                loadedProducts.append(product)
            }
        }
        return loadedProducts
    }
}

@MainActor
final class LiveAccountCreditStore: AccountCreditStore {
    private var productsByID: [String: Product] = [:]

    func product(for productID: String) async throws -> AccountStoreProduct? {
        guard let product = try await loadProduct(for: productID) else { return nil }
        return AccountStoreProduct(id: product.id, displayPrice: product.displayPrice)
    }

    func products(for productIDs: [String]) async throws -> [AccountStoreProduct] {
        var seenIDs: Set<String> = []
        let orderedIDs = productIDs.filter { seenIDs.insert($0).inserted }
        let missingIDs = orderedIDs.filter { productsByID[$0] == nil }
        if !missingIDs.isEmpty {
            let loadedProducts = try await Product.products(for: missingIDs)
            loadedProducts.forEach { productsByID[$0.id] = $0 }
        }
        return orderedIDs.compactMap { productID in
            guard let product = productsByID[productID] else { return nil }
            return AccountStoreProduct(id: product.id, displayPrice: product.displayPrice)
        }
    }

    func purchase(productID: String, accountID: UUID) async throws -> AccountStorePurchaseOutcome {
        guard let product = try await loadProduct(for: productID) else {
            return .success(.unverified)
        }
        switch try await product.purchase(options: [.appAccountToken(accountID)]) {
        case .success(let verification):
            return .success(Self.map(verification))
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .success(.unverified)
        }
    }

    func unfinishedTransactions() -> AsyncStream<AccountStoreVerification> {
        Self.stream(from: Transaction.unfinished)
    }

    func transactionUpdates() -> AsyncStream<AccountStoreVerification> {
        Self.stream(from: Transaction.updates)
    }

    func allTransactions() -> AsyncStream<AccountStoreVerification> {
        Self.stream(from: Transaction.all)
    }

    private func loadProduct(for productID: String) async throws -> Product? {
        if let product = productsByID[productID] {
            return product
        }
        _ = try await products(for: [productID])
        return productsByID[productID]
    }

    private static func map(_ verification: VerificationResult<Transaction>) -> AccountStoreVerification {
        guard case .verified(let transaction) = verification else { return .unverified }
        return .verified(
            AccountStoreTransaction(
                id: transaction.id,
                productID: transaction.productID,
                appAccountToken: transaction.appAccountToken,
                purchaseDate: transaction.purchaseDate,
                signedTransaction: verification.jwsRepresentation,
                finishOperation: { await transaction.finish() }
            )
        )
    }

    private static func stream(
        from transactions: Transaction.Transactions
    ) -> AsyncStream<AccountStoreVerification> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in transactions {
                    guard !Task.isCancelled else { break }
                    continuation.yield(map(verification))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
