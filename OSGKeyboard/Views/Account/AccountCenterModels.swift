// AccountCenterModels.swift
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
    /// 8-character alias friends can type; nil until the server assigns one.
    let shortCode: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case inviteURL = "inviteUrl"
        case campaignID = "campaignId"
        case createdAt
        case shortCode
    }

    init(
        code: String,
        inviteURL: URL,
        campaignID: String?,
        createdAt: Date,
        shortCode: String? = nil
    ) {
        self.code = code
        self.inviteURL = inviteURL
        self.campaignID = campaignID
        self.createdAt = createdAt
        self.shortCode = shortCode.flatMap(ReferralShortCode.normalize)
    }

    /// `XXXX-XXXX` form for posters and share sheets.
    var displayShortCode: String? {
        shortCode.map(ReferralShortCode.display)
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
        // A malformed alias only hides the short code; the link still works.
        shortCode = (try? container.decodeIfPresent(String.self, forKey: .shortCode))
            .flatMap { $0 }
            .flatMap(ReferralShortCode.normalize)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(inviteURL, forKey: .inviteURL)
        try container.encodeIfPresent(campaignID, forKey: .campaignID)
        try container.encode(Self.string(from: createdAt), forKey: .createdAt)
        try container.encodeIfPresent(shortCode, forKey: .shortCode)
    }

    static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: value) ?? standard.date(from: value)
    }

    static func string(from date: Date) -> String {
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
    /// Last moment this account may still bind an inviter. The server omits it
    /// once bound or when no campaign is active; older servers never send it.
    let bindingDeadline: Date?

    private enum CodingKeys: String, CodingKey {
        case code
        case binding
        case bindingDeadline
    }

    init(code: ReferralCode, binding: ReferralBinding?, bindingDeadline: Date? = nil) {
        self.code = code
        self.binding = binding
        self.bindingDeadline = bindingDeadline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(ReferralCode.self, forKey: .code)
        binding = try container.decodeIfPresent(ReferralBinding.self, forKey: .binding)
        bindingDeadline = (try? container.decodeIfPresent(String.self, forKey: .bindingDeadline))
            .flatMap { $0 }
            .flatMap(ReferralCode.date(from:))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(binding, forKey: .binding)
        try container.encodeIfPresent(
            bindingDeadline.map(ReferralCode.string(from:)),
            forKey: .bindingDeadline
        )
    }
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
    let userIdentifier: String

    init(
        identityToken: String,
        authorizationCode: String,
        nonce: String,
        displayName: String? = nil,
        userIdentifier: String
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.nonce = nonce
        self.displayName = displayName
        self.userIdentifier = userIdentifier
    }
}

enum AccountAppleCredentialState: Equatable, Sendable {
    case authorized
    case revoked
    case reauthenticationRequired
    case unknown
}

protocol AccountSessionServicing: Sendable {
    func restoreSession() async throws -> AccountSession?
    func signIn(with payload: AppleAuthorizationPayload) async throws -> AccountSession
    func signOut() async throws
    func deleteAccount(with payload: AppleAuthorizationPayload) async throws
    func appleCredentialState() async -> AccountAppleCredentialState
    func prepareManagedGateway() async throws
    func clearManagedGateway() async
}

enum AccountSessionEvent: Sendable {
    case expired
}

protocol AccountSessionEventSourcing: Sendable {
    func events() async -> AsyncStream<AccountSessionEvent>
}

extension AccountSessionServicing {
    func appleCredentialState() async -> AccountAppleCredentialState {
        .unknown
    }

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
    let sessionEventSource: any AccountSessionEventSourcing
    let centerService: any AccountCenterServicing
    let referralService: any ReferralProfileServicing

    init(
        sessionService: any AccountSessionServicing,
        sessionEventSource: (any AccountSessionEventSourcing)? = nil,
        centerService: any AccountCenterServicing,
        referralService: (any ReferralProfileServicing)? = nil
    ) {
        self.sessionService = sessionService
        self.sessionEventSource = sessionEventSource ?? UnavailableAccountSessionEventSource()
        self.centerService = centerService
        self.referralService = referralService ?? UnavailableReferralProfileService()
    }

    static let unavailable: AccountDependencies = {
        let service = UnavailableAccountService()
        return AccountDependencies(
            sessionService: service,
            sessionEventSource: UnavailableAccountSessionEventSource(),
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

private struct UnavailableAccountSessionEventSource: AccountSessionEventSourcing {
    func events() async -> AsyncStream<AccountSessionEvent> {
        AsyncStream { $0.finish() }
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

    /// Extracts a code from typed or pasted text: a short code, a bare long
    /// code, an invitation link, or a chat message that contains one of them.
    /// Links are matched with the same host and path rules as Universal Links,
    /// so arbitrary URLs never qualify. Short codes are returned normalized
    /// (uppercase, no hyphen); the server resolves them to the long code.
    static func code(fromUserInput text: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "，。；：、！？「」『』“”‘’<>()（）【】《》"))
        let tokens = text
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        for token in tokens {
            if isValid(code: token) {
                return token
            }
            // Chat apps often glue the link to the preceding sentence.
            let link = token.range(of: "https://", options: .caseInsensitive)
                .map { String(token[$0.lowerBound...]) } ?? token
            if let url = URL(string: link), let code = code(from: url) {
                return code
            }
        }
        // Short codes go last: an 8-letter word in a pasted message must not
        // shadow the link that message carries.
        return ReferralShortCode.firstMatch(in: text)
    }

    /// Anything the bind endpoint accepts: a long code or a normalized short code.
    static func isRedeemable(code: String) -> Bool {
        isValid(code: code) || ReferralShortCode.isCanonical(code)
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

/// 8-character typeable alias of a referral code. Mirrors the server's
/// `ReferralShortCode`: the alphabet drops 0/O and 1/I/L so a code read aloud
/// or copied from a poster cannot be mistyped into another valid code.
enum ReferralShortCode {
    static let length = 8
    static let alphabet: Set<Character> = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    static func isCanonical(_ value: String) -> Bool {
        value.count == length && value.allSatisfy(alphabet.contains)
    }

    /// Accepts `K7M2Q9XA` or `k7m2-q9xa`; returns the stored uppercase form.
    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.count == length + 1, value[value.index(value.startIndex, offsetBy: 4)] == "-" {
            value.remove(at: value.index(value.startIndex, offsetBy: 4))
        }
        return isCanonical(value) ? value : nil
    }

    static func display(_ value: String) -> String {
        guard isCanonical(value) else { return value }
        return "\(value.prefix(4))-\(value.suffix(4))"
    }

    /// Finds a short code inside free text such as "邀请码 K7M2-Q9XA" or a
    /// Chinese sentence glued to the code, which whitespace splitting misses.
    static func firstMatch(in text: String) -> String? {
        // Runs of code-like ASCII; anything else (spaces, CJK, punctuation)
        // separates them, so a run is exactly one candidate. "_" stays inside
        // a run so a fragment of a long code never reads as a short code.
        let runs = text.split { character in
            !(character.isASCII
                && (character.isLetter || character.isNumber || character == "-" || character == "_"))
        }
        return runs.lazy.compactMap { normalize(String($0)) }.first
    }
}

/// When a signed-in account may still bind an inviter. Prefers the server's
/// `bindingDeadline`, which reflects the active campaign; without it, falls
/// back to the default `REFERRAL_BINDING_DAYS`. The server stays
/// authoritative, so a mismatch still surfaces as a redemption error.
enum ReferralBindingWindow {
    static let duration: TimeInterval = 7 * 24 * 60 * 60

    static func isOpen(for account: AccountSession, now: Date = Date()) -> Bool {
        // Zero means the account record has not loaded yet.
        guard account.createdAtEpochSeconds > 0 else { return false }
        let registeredAt = Date(timeIntervalSince1970: TimeInterval(account.createdAtEpochSeconds))
        return now.timeIntervalSince(registeredAt) < duration
    }

    /// Open only while unbound and before the deadline the server reported.
    static func isOpen(
        for account: AccountSession,
        profile: ReferralProfile,
        now: Date = Date()
    ) -> Bool {
        guard profile.binding == nil else { return false }
        if let deadline = profile.bindingDeadline {
            return now <= deadline
        }
        return isOpen(for: account, now: now)
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
              ReferralUniversalLink.isRedeemable(code: value)
        else {
            return nil
        }
        return value
    }

    func save(_ code: String) {
        guard ReferralUniversalLink.isRedeemable(code: code) else { return }
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
