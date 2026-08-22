// AccountModels.swift
// OSGKeyboard · HostSupport
//
// Wire models for the host-private OSG account protocol.

import Foundation

public struct AccountSession: Codable, Equatable, Sendable {
    public let accountId: UUID
    public let tokenType: String
    public let accessToken: String
    public let accessTokenExpiresAtEpochSeconds: Int64
    public let refreshToken: String
    public let refreshTokenExpiresAtEpochSeconds: Int64

    public init(
        accountId: UUID,
        tokenType: String,
        accessToken: String,
        accessTokenExpiresAtEpochSeconds: Int64,
        refreshToken: String,
        refreshTokenExpiresAtEpochSeconds: Int64
    ) {
        self.accountId = accountId
        self.tokenType = tokenType
        self.accessToken = accessToken
        self.accessTokenExpiresAtEpochSeconds = accessTokenExpiresAtEpochSeconds
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAtEpochSeconds = refreshTokenExpiresAtEpochSeconds
    }
}

public struct OSGAccount: Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAtEpochSeconds: Int64
    public let displayName: String?

    public init(id: UUID, createdAtEpochSeconds: Int64, displayName: String? = nil) {
        self.id = id
        self.createdAtEpochSeconds = createdAtEpochSeconds
        self.displayName = displayName
    }
}

struct UpdateAccountProfileRequest: Codable, Equatable, Sendable {
    let displayName: String
}

/// Exact authenticated resources exposed to the host account center. Keeping
/// this closed prevents callers from forwarding account tokens to arbitrary
/// paths or origins.
public enum AccountAuthorizedResource: Sendable, Equatable {
    case creditsBalance
    case referralProfile
    case referralCampaigns
    case referrals(limit: Int)
    case redeemReferral
    case storeKitProducts
    case storeKitTransactions(limit: Int, cursor: String?)
    case submitStoreKitTransaction
    case revokeGatewayGrant(UUID)

    var method: String {
        switch self {
        case .redeemReferral, .submitStoreKitTransaction:
            return "POST"
        case .revokeGatewayGrant:
            return "DELETE"
        default:
            return "GET"
        }
    }

    var path: String {
        switch self {
        case .creditsBalance:
            return "/v1/credits/balance"
        case .referralProfile:
            return "/v1/referrals/me"
        case .referralCampaigns:
            return "/v1/referrals/campaigns"
        case .referrals(let limit):
            return "/v1/referrals?limit=\(min(max(limit, 1), 100))"
        case .redeemReferral:
            return "/v1/referrals/redeem"
        case .storeKitProducts:
            return "/v1/storekit/products"
        case .storeKitTransactions(let limit, let cursor):
            let boundedLimit = min(max(limit, 1), 100)
            var components = URLComponents()
            components.path = "/v1/storekit/transactions"
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(boundedLimit))
            ]
            if let cursor {
                components.queryItems?.append(
                    URLQueryItem(name: "cursor", value: cursor)
                )
            }
            return components.string
                ?? "/v1/storekit/transactions?limit=\(boundedLimit)"
        case .submitStoreKitTransaction:
            return "/v1/storekit/transactions"
        case .revokeGatewayGrant(let grantId):
            return "/v1/gateway/grants/\(grantId.uuidString.lowercased())"
        }
    }
}

public struct AppleSignInCredential: Equatable, Sendable {
    public let identityToken: String
    public let authorizationCode: String

    public init(identityToken: String, authorizationCode: String) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
    }
}

public struct AppleSignInNonce: Equatable, Sendable {
    public let rawValue: String
    public let sha256Hex: String

    public init(rawValue: String, sha256Hex: String) {
        self.rawValue = rawValue
        self.sha256Hex = sha256Hex
    }
}

public struct AppleSignInRequest: Codable, Equatable, Sendable {
    public let identityToken: String
    public let authorizationCode: String
    public let nonce: String
    public let displayName: String?
    public let deviceCheckToken: String?
    public let appAttest: AppAttestAssertion?

    public init(
        identityToken: String,
        authorizationCode: String,
        nonce: String,
        displayName: String? = nil,
        deviceCheckToken: String?,
        appAttest: AppAttestAssertion?
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.nonce = nonce
        self.displayName = displayName
        self.deviceCheckToken = deviceCheckToken
        self.appAttest = appAttest
    }
}

public struct AppAttestAssertion: Codable, Equatable, Sendable {
    public let keyId: String
    public let challengeId: UUID
    public let challenge: String
    public let assertion: String

    public init(keyId: String, challengeId: UUID, challenge: String, assertion: String) {
        self.keyId = keyId
        self.challengeId = challengeId
        self.challenge = challenge
        self.assertion = assertion
    }
}

/// Anonymous OOBE grant request. It intentionally contains no account session,
/// requested scopes, or mutable feature claim; the server fixes policy to
/// `polish` + `ai` after validating App Attest.
public struct OOBEGrantRequest: Codable, Equatable, Sendable {
    public let installationId: UUID
    public let keyId: String
    public let challengeId: UUID
    public let challenge: String
    public let assertion: String

    public init(
        installationId: UUID,
        keyId: String,
        challengeId: UUID,
        challenge: String,
        assertion: String
    ) {
        self.installationId = installationId
        self.keyId = keyId
        self.challengeId = challengeId
        self.challenge = challenge
        self.assertion = assertion
    }
}

public enum AppAttestChallengePurpose: String, Codable, Sendable {
    case attestation
    case assertion
}

public struct AppAttestChallenge: Codable, Equatable, Sendable {
    public let challengeId: UUID
    public let challenge: String
    public let expiresAtEpochSeconds: Int64

    public init(challengeId: UUID, challenge: String, expiresAtEpochSeconds: Int64) {
        self.challengeId = challengeId
        self.challenge = challenge
        self.expiresAtEpochSeconds = expiresAtEpochSeconds
    }
}

public struct AppAttestKeyState: Codable, Equatable, Sendable {
    public let keyId: String
    public let isRegistered: Bool

    public init(keyId: String, isRegistered: Bool) {
        self.keyId = keyId
        self.isRegistered = isRegistered
    }
}

public protocol AccountSessionVault: Sendable {
    func loadSession() async throws -> AccountSession?
    func saveSession(_ session: AccountSession) async throws
    func clearSession() async throws
}

public protocol AppAttestKeyStateStoring: Sendable {
    func loadAppAttestKeyState() async throws -> AppAttestKeyState?
    func saveAppAttestKeyState(_ state: AppAttestKeyState) async throws
    func clearAppAttestKeyState() async throws
}

public protocol OOBEInstallationIDStoring: Sendable {
    func oobeInstallationID() async throws -> UUID
}

public enum AccountAPIError: Error, Equatable, Sendable {
    case invalidRequest(String)
    case unauthorized(String)
    case refreshTokenReuse
    case externalServiceUnavailable(String)
    case conflict(String)
    case rateLimited(String)
    case server(statusCode: Int, code: String, message: String)
    case transport
    case invalidResponse
    case decoding
    case secureStorage
    case sessionUnavailable
    case appleAuthorization
    case integrityUnavailable
}

public enum AccountSessionInvalidation: Sendable {
    case expired
}

extension AccountAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message),
             .unauthorized(let message),
             .externalServiceUnavailable(let message),
             .conflict(let message),
             .rateLimited(let message):
            return message
        case .refreshTokenReuse:
            return "The session was revoked because refresh-token reuse was detected."
        case .server(_, _, let message):
            return message
        case .transport:
            return "The account service could not be reached."
        case .invalidResponse:
            return "The account service returned an invalid response."
        case .decoding:
            return "The account service response could not be decoded."
        case .secureStorage:
            return "The private account session could not be stored securely."
        case .sessionUnavailable:
            return "No account session is available."
        case .appleAuthorization:
            return "Sign in with Apple did not return valid credentials."
        case .integrityUnavailable:
            return "Device integrity verification is unavailable."
        }
    }
}

struct APIDataEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let data: Value
}

struct APIErrorEnvelope: Codable, Sendable {
    let error: APIErrorPayload
}

struct APIErrorPayload: Codable, Sendable {
    let code: String
    let message: String
}

struct LegacyAPIErrorEnvelope: Codable, Sendable {
    let error: String
}

struct RefreshSessionRequest: Codable, Sendable {
    let refreshToken: String
}

struct DeleteAccountRequest: Codable, Sendable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
}

struct AppAttestChallengeRequest: Codable, Sendable {
    let purpose: AppAttestChallengePurpose
    let keyId: String
}

struct AppAttestationRequest: Codable, Sendable {
    let challengeId: UUID
    let challenge: String
    let keyId: String
    let attestationObject: String
}

struct AppAssertionRequest: Codable, Sendable {
    let challengeId: UUID
    let challenge: String
    let keyId: String
    let assertion: String
    let clientDataHash: String
}

struct AppAssertionResponse: Codable, Sendable {
    let counter: Int64
}
