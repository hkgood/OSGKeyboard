// TipPurchaseManager.swift
// OSGKeyboard · Shared
//
// Optional ¥30 consumable tip via StoreKit 2. Voluntary support only —
// no feature gates, no App Group sync, no restore (Apple consumable rules).

import Foundation
import Combine
import StoreKit

public enum TipPurchaseState: Equatable {
    case idle
    case loading
    case purchasing
    case succeeded
    case failed(String)
}

@MainActor
public final class TipPurchaseManager: ObservableObject {
    public static let shared = TipPurchaseManager()

    @Published public private(set) var product: Product?
    @Published public private(set) var purchaseState: TipPurchaseState = .idle
    @Published public private(set) var supportCount: Int

    private var transactionUpdatesTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        supportCount = defaults.integer(forKey: TipProduct.supportCountDefaultsKey)
        transactionUpdatesTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        Task { await loadProducts() }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    /// Loads the tip product from the App Store / StoreKit Test configuration.
    public func loadProducts() async {
        guard purchaseState != .purchasing else { return }
        purchaseState = .loading
        do {
            let products = try await Product.products(for: TipProduct.allProductIDs)
            product = products.first(where: { $0.id == TipProduct.supportID })
            purchaseState = product == nil
                ? .failed(SharedL10n.string("tip.error.productUnavailable"))
                : .idle
        } catch {
            product = nil
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Starts the StoreKit purchase sheet for the support tip.
    public func purchase() async {
        guard let product else {
            purchaseState = .failed(SharedL10n.string("tip.error.productUnavailable"))
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await handleCompletedTip(transaction)
                purchaseState = .succeeded
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .failed(SharedL10n.string("tip.error.pending"))
            @unknown default:
                purchaseState = .failed(SharedL10n.string("tip.error.unknown"))
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Clears transient success / failure state after the UI acknowledges it.
    public func acknowledgePurchaseState() {
        switch purchaseState {
        case .succeeded, .failed:
            purchaseState = .idle
        default:
            break
        }
    }

    private func listenForTransactionUpdates() async {
        for await update in Transaction.updates {
            guard let transaction = try? Self.verified(update),
                  transaction.productID == TipProduct.supportID else { continue }
            await handleCompletedTip(transaction)
        }
    }

    private func handleCompletedTip(_ transaction: Transaction) async {
        await transaction.finish()
        recordSupportPurchase()
    }

    private func recordSupportPurchase() {
        supportCount += 1
        UserDefaults.standard.set(supportCount, forKey: TipProduct.supportCountDefaultsKey)
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw TipPurchaseError.failedVerification
        }
    }
}

private enum TipPurchaseError: Error {
    case failedVerification
}
