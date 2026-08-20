// AccountModels.swift
// OSGKeyboard · Main App
//
// Account-center domain models and narrow service boundaries. Transport DTOs
// stay in the eventual auth/network adapter so this UI is not coupled to it.

import Foundation

extension Notification.Name {
    static let osgOpenAccountDeepLink = Notification.Name("osg.OpenAccountDeepLink")
}

struct AccountSession: Equatable, Sendable {
    let accountID: UUID
    let createdAtEpochSeconds: Int64
    let displayName: String?

    init(accountID: UUID, createdAtEpochSeconds: Int64, displayName: String? = nil) {
        self.accountID = accountID
        self.createdAtEpochSeconds = createdAtEpochSeconds
        self.displayName = displayName
    }
}

struct AccountCreditSummary: Equatable, Sendable {
    let balance: Int64
    let usedCredits: Int64
}

struct AccountCreditProduct: Identifiable, Equatable, Sendable {
    var id: String { productID }

    let productID: String
    let credits: Int64
}

struct AccountCreditPurchase: Equatable, Sendable {
    let transactionID: String
    let productID: String
    let creditsGranted: Int64
    let balanceAfter: Int64
    let replayed: Bool
}

enum AccountCreditPurchaseStatus: String, Equatable, Sendable {
    case credited
}

struct AccountCreditPurchaseRecord: Identifiable, Equatable, Sendable {
    var id: String { transactionID }

    let transactionID: String
    let productID: String
    let creditsGranted: Int64
    let balanceAfter: Int64
    let purchasedAt: Date
    let status: AccountCreditPurchaseStatus
}

struct AccountCreditPurchaseHistoryPage: Equatable, Sendable {
    let items: [AccountCreditPurchaseRecord]
    let nextCursor: String?
}

enum AccountReferralStatus: String, CaseIterable, Equatable, Sendable {
    case pending
    case rewarded
    case ineligible
}

struct AccountReferral: Identifiable, Equatable, Sendable {
    let id: UUID
    let status: AccountReferralStatus
    let createdAtEpochSeconds: Int64?
    let rewardCredits: Int64?
}

struct AccountReferralProfile: Equatable, Sendable {
    let code: String?
    let boundCode: String?
    let inviterRewardCredits: Int64?
    let inviteeRewardCredits: Int64?

    init(
        code: String?,
        boundCode: String?,
        inviterRewardCredits: Int64? = nil,
        inviteeRewardCredits: Int64? = nil
    ) {
        self.code = code
        self.boundCode = boundCode
        self.inviterRewardCredits = inviterRewardCredits
        self.inviteeRewardCredits = inviteeRewardCredits
    }
}

struct AccountCenterSnapshot: Equatable, Sendable {
    let account: AccountSession
    let credits: AccountCreditSummary
    let referralProfile: AccountReferralProfile
    let referrals: [AccountReferral]
}

struct AccountReferralSummary: Equatable, Sendable {
    let pending: Int
    let rewarded: Int
    let ineligible: Int

    init(pending: Int, rewarded: Int, ineligible: Int) {
        self.pending = pending
        self.rewarded = rewarded
        self.ineligible = ineligible
    }

    init(referrals: [AccountReferral]) {
        pending = referrals.count { $0.status == .pending }
        rewarded = referrals.count { $0.status == .rewarded }
        ineligible = referrals.count { $0.status == .ineligible }
    }
}

struct AppleAuthorizationPayload: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    let displayName: String?

    init(
        identityToken: String,
        authorizationCode: String,
        nonce: String,
        displayName: String? = nil
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.nonce = nonce
        self.displayName = displayName
    }
}

protocol AccountSessionServicing: Sendable {
    func restoreSession() async throws -> AccountSession?
    func signIn(with payload: AppleAuthorizationPayload) async throws -> AccountSession
    func signOut() async throws
    func deleteAccount(with payload: AppleAuthorizationPayload) async throws
    func prepareManagedGateway() async throws
    func clearManagedGateway() async
}

extension AccountSessionServicing {
    func prepareManagedGateway() async throws {}
    func clearManagedGateway() async {}
}

protocol AccountCenterServicing: Sendable {
    func loadAccountCenter() async throws -> AccountCenterSnapshot
    func loadAccountCenter(
        cachedSnapshot: AccountCenterSnapshot?
    ) async throws -> AccountCenterSnapshot
    func updateDisplayName(_ displayName: String) async throws -> AccountSession
    func createReferralCode() async throws -> String
    func redeemReferral(code: String) async throws
    func loadCreditProducts() async throws -> [AccountCreditProduct]
    func submitCreditTransaction(_ signedTransaction: String) async throws -> AccountCreditPurchase
    func loadCreditPurchaseHistory(
        limit: Int,
        cursor: String?
    ) async throws -> AccountCreditPurchaseHistoryPage
}

extension AccountCenterServicing {
    func loadAccountCenter(
        cachedSnapshot: AccountCenterSnapshot?
    ) async throws -> AccountCenterSnapshot {
        try await loadAccountCenter()
    }

    func updateDisplayName(_ displayName: String) async throws -> AccountSession {
        throw AccountIntegrationError.unavailable
    }

    func loadCreditProducts() async throws -> [AccountCreditProduct] {
        throw AccountIntegrationError.unavailable
    }

    func submitCreditTransaction(_ signedTransaction: String) async throws -> AccountCreditPurchase {
        throw AccountIntegrationError.unavailable
    }

    func loadCreditPurchaseHistory(
        limit: Int,
        cursor: String?
    ) async throws -> AccountCreditPurchaseHistoryPage {
        throw AccountIntegrationError.unavailable
    }
}

struct AccountDependencies: Sendable {
    let sessionService: any AccountSessionServicing
    let centerService: any AccountCenterServicing

    static let unavailable: AccountDependencies = {
        let service = UnavailableAccountService()
        return AccountDependencies(sessionService: service, centerService: service)
    }()
}

enum AccountIntegrationError: Error, Equatable, Sendable {
    case unavailable
}

private struct UnavailableAccountService: AccountSessionServicing, AccountCenterServicing {
    func restoreSession() async throws -> AccountSession? {
        nil
    }

    func signIn(with payload: AppleAuthorizationPayload) async throws -> AccountSession {
        throw AccountIntegrationError.unavailable
    }

    func signOut() async throws {}

    func deleteAccount(with payload: AppleAuthorizationPayload) async throws {
        throw AccountIntegrationError.unavailable
    }

    func prepareManagedGateway() async throws {
        throw AccountIntegrationError.unavailable
    }

    func clearManagedGateway() async {}

    func loadAccountCenter() async throws -> AccountCenterSnapshot {
        throw AccountIntegrationError.unavailable
    }

    func updateDisplayName(_ displayName: String) async throws -> AccountSession {
        throw AccountIntegrationError.unavailable
    }

    func createReferralCode() async throws -> String {
        throw AccountIntegrationError.unavailable
    }

    func redeemReferral(code: String) async throws {
        throw AccountIntegrationError.unavailable
    }

    func loadCreditProducts() async throws -> [AccountCreditProduct] {
        throw AccountIntegrationError.unavailable
    }

    func submitCreditTransaction(_ signedTransaction: String) async throws -> AccountCreditPurchase {
        throw AccountIntegrationError.unavailable
    }
}

enum ReferralUniversalLink {
    static let host = "osglab.com"
    static let codeLength = 22

    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host
        else {
            return nil
        }

        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "i" else { return nil }

        let code = String(components[1])
        guard isValid(code: code) else { return nil }
        return code
    }

    static func isValid(code: String) -> Bool {
        guard code.utf8.count == codeLength else { return false }
        return code.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 45
                || byte == 95
        }
    }

    static func invitationURL(for code: String) -> URL? {
        guard isValid(code: code) else { return nil }
        return URL(string: "https://\(host)/i/\(code)")
    }
}

@MainActor
protocol PendingReferralCodeStoring: AnyObject {
    var code: String? { get }
    func save(_ code: String)
    func clear()
}

@MainActor
final class UserDefaultsPendingReferralCodeStore: PendingReferralCodeStoring {
    private static let storageKey = "account.pendingReferralCode.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var code: String? {
        guard let value = defaults.string(forKey: Self.storageKey),
              ReferralUniversalLink.isValid(code: value)
        else {
            return nil
        }
        return value
    }

    func save(_ code: String) {
        guard ReferralUniversalLink.isValid(code: code) else { return }
        defaults.set(code, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
