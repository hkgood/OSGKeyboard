// ManagedGatewayModels.swift
// OSGKeyboard · Shared
//
// Scope-limited credentials and transport models for the managed gateway.

import Foundation

public enum ManagedGatewayCapability: String, Codable, CaseIterable, Sendable {
    case polish
    case assistant = "ai"
    case agent
    case asr
}

/// Stable task contract shared with the account gateway. The app identifies
/// user intent; the server remains authoritative for model and feature policy.
public enum ManagedGatewayTaskKind: String, Codable, CaseIterable, Sendable {
    case dictationPolish = "dictation_polish"
    case translation
    case editLastInput = "edit_last_input"
    case aiQuestion = "ai_question"
    case clipboardTransform = "clipboard_transform"
    case customSkill = "custom_skill"
    case agentPlanning = "agent_planning"
}

/// Optional server-audited purpose. A purpose may affect billing only when the
/// authenticated gateway independently verifies its eligibility.
public enum ManagedGatewayRequestPurpose: String, Codable, Sendable {
    case oobe
}

public struct ManagedGatewayGrantCredentials: Codable, Equatable, Sendable {
    public static let maximumAccessLifetime: TimeInterval = 5 * 60

    public let grantId: String
    public let scopes: Set<ManagedGatewayCapability>
    public let accessToken: String
    public let accessExpiresAt: Date
    public let refreshToken: String
    public let refreshExpiresAt: Date
    public let receivedAt: Date

    public init(
        grantId: String,
        scopes: Set<ManagedGatewayCapability>,
        accessToken: String,
        accessExpiresAt: Date,
        refreshToken: String,
        refreshExpiresAt: Date,
        receivedAt: Date = Date()
    ) {
        self.grantId = grantId
        self.scopes = scopes
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
        self.refreshExpiresAt = refreshExpiresAt
        self.receivedAt = receivedAt
    }

    /// Never trust an unexpectedly long access expiry. The gateway contract
    /// deliberately limits extension-readable bearer credentials to five minutes.
    public var effectiveAccessExpiresAt: Date {
        min(accessExpiresAt, receivedAt.addingTimeInterval(Self.maximumAccessLifetime))
    }

    public func hasUsableAccessToken(
        for scope: ManagedGatewayCapability,
        at now: Date = Date(),
        refreshLeeway: TimeInterval = 30
    ) -> Bool {
        scopes.contains(scope)
            && !accessToken.isEmpty
            && effectiveAccessExpiresAt.timeIntervalSince(now) > refreshLeeway
    }

    public func hasUsableRefreshToken(at now: Date = Date()) -> Bool {
        !refreshToken.isEmpty && refreshExpiresAt > now
    }
}

public enum ManagedGatewayError: Error, LocalizedError, Equatable, Sendable {
    case missingGrant
    case scopeNotGranted(ManagedGatewayCapability)
    case invalidGrant
    case insufficientCredits
    case timeout
    case server(code: String, status: Int, requestId: String?)

    public var errorDescription: String? {
        switch self {
        case .missingGrant:
            return SharedL10n.string("managed.error.grantUnavailable")
        case .scopeNotGranted(let scope):
            return SharedL10n.format(
                "managed.error.scopeNotGranted",
                language: nil,
                scope.rawValue
            )
        case .invalidGrant:
            return SharedL10n.string("managed.error.grantRejected")
        case .insufficientCredits:
            return SharedL10n.string("managed.error.insufficientCredits")
        case .timeout:
            return SharedL10n.string("managed.error.timeout")
        case .server(let code, let status, _):
            return SharedL10n.format(
                "managed.error.server",
                language: nil,
                code,
                status
            )
        }
    }
}

struct ManagedGatewayGrantTokenResponse: Decodable {
    let grantId: String
    let scopes: Set<ManagedGatewayCapability>
    let accessToken: String
    let accessExpiresAt: Date
    let refreshToken: String
    let refreshExpiresAt: Date

    func credentials(receivedAt: Date) -> ManagedGatewayGrantCredentials {
        ManagedGatewayGrantCredentials(
            grantId: grantId,
            scopes: scopes,
            accessToken: accessToken,
            accessExpiresAt: accessExpiresAt,
            refreshToken: refreshToken,
            refreshExpiresAt: refreshExpiresAt,
            receivedAt: receivedAt
        )
    }
}

struct ManagedGatewayErrorResponse: Decodable, Sendable {
    let code: String
    let message: String
    let requestId: String
}

struct ManagedGatewayTextRequest: Encodable, Sendable {
    let input: String
    let context: String?
    let maxOutputTokens: Int
    let temperature: Double
    let stream: Bool
    let taskKind: ManagedGatewayTaskKind
    let requestPurpose: ManagedGatewayRequestPurpose?
}
