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

struct ReferralCode: Codable, Equatable, Sendable {
    let code: String
    let inviteURL: URL
    let campaignID: String?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case code
        case inviteURL = "inviteUrl"
        case campaignID = "campaignId"
        case createdAt
    }

    init(code: String, inviteURL: URL, campaignID: String?, createdAt: Date) {
        self.code = code
        self.inviteURL = inviteURL
        self.campaignID = campaignID
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let inviteURL = try container.decode(URL.self, forKey: .inviteURL)
        let createdAtValue = try container.decode(String.self, forKey: .createdAt)
        guard ReferralUniversalLink.isValid(code: code),
              inviteURL.scheme?.lowercased() == "https",
              inviteURL.host != nil,
              let createdAt = Self.date(from: createdAtValue) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid referral code, invite URL, or creation date."
                )
            )
        }
        self.code = code
        self.inviteURL = inviteURL
        campaignID = try container.decodeIfPresent(String.self, forKey: .campaignID)
        self.createdAt = createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(inviteURL, forKey: .inviteURL)
        try container.encodeIfPresent(campaignID, forKey: .campaignID)
        try container.encode(Self.string(from: createdAt), forKey: .createdAt)
    }

    private static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: value) ?? standard.date(from: value)
    }

    private static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// The binding payload can gain server-owned fields without breaking cached
/// profiles. The client only needs to preserve it; invitation sharing uses code.
struct ReferralBinding: Codable, Equatable, Sendable {
    let fields: [String: ReferralJSONValue]

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode(
            [String: ReferralJSONValue].self
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
}

enum ReferralJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case boolean(Bool)
    case object([String: ReferralJSONValue])
    case array([ReferralJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: ReferralJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([ReferralJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported referral binding value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct ReferralProfile: Codable, Equatable, Sendable {
    let code: ReferralCode
    let binding: ReferralBinding?
}

struct AccountCenterSnapshot: Equatable, Sendable {
    let account: AccountSession
    let credits: AccountCreditSummary
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

protocol ReferralProfileServicing: Sendable {
    func loadReferralProfile() async throws -> ReferralProfile
}

struct AccountDependencies: Sendable {
    let sessionService: any AccountSessionServicing
    let centerService: any AccountCenterServicing
    let referralService: any ReferralProfileServicing

    init(
        sessionService: any AccountSessionServicing,
        centerService: any AccountCenterServicing,
        referralService: (any ReferralProfileServicing)? = nil
    ) {
        self.sessionService = sessionService
        self.centerService = centerService
        self.referralService = referralService ?? UnavailableReferralProfileService()
    }

    static let unavailable: AccountDependencies = {
        let service = UnavailableAccountService()
        return AccountDependencies(
            sessionService: service,
            centerService: service,
            referralService: UnavailableReferralProfileService()
        )
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

private struct UnavailableReferralProfileService: ReferralProfileServicing {
    func loadReferralProfile() async throws -> ReferralProfile {
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

@MainActor
protocol ReferralProfileStoring: AnyObject {
    func profile(for accountID: UUID) -> ReferralProfile?
    func save(_ profile: ReferralProfile, for accountID: UUID)
    func removeProfile(for accountID: UUID)
}

@MainActor
final class UserDefaultsReferralProfileStore: ReferralProfileStoring {
    private static let storageKeyPrefix = "account.referralProfile.v1."

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func profile(for accountID: UUID) -> ReferralProfile? {
        guard let data = defaults.data(forKey: storageKey(for: accountID)) else {
            return nil
        }
        return try? decoder.decode(ReferralProfile.self, from: data)
    }

    func save(_ profile: ReferralProfile, for accountID: UUID) {
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: storageKey(for: accountID))
    }

    func removeProfile(for accountID: UUID) {
        defaults.removeObject(forKey: storageKey(for: accountID))
    }

    private func storageKey(for accountID: UUID) -> String {
        Self.storageKeyPrefix + accountID.uuidString.lowercased()
    }
}
