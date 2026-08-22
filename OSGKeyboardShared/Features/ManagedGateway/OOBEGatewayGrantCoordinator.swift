// OOBEGatewayGrantCoordinator.swift
// OSGKeyboard · Shared
//
// Routes anonymous onboarding requests through a credential slot that is
// isolated from signed-in account grants.

import Foundation

public actor OOBEGatewayGrantCoordinator {
    public static let allowedScopes: Set<ManagedGatewayCapability> = [
        .polish,
        .assistant
    ]

    private let grants: GatewayGrantCoordinator
    private let store: any GatewayGrantCredentialStore
    private let now: @Sendable () -> Date
    private let practiceSession: @Sendable () -> OOBEPracticeSession?

    public init(
        baseURL: URL = GatewayGrantCoordinator.defaultBaseURL,
        store: any GatewayGrantCredentialStore = OOBEGatewayGrantKeychainStore(),
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        practiceSession: @escaping @Sendable () -> OOBEPracticeSession? = {
            KeyboardSetupBridge.activeOOBEPracticeSession
        }
    ) {
        self.store = store
        self.now = now
        self.practiceSession = practiceSession
        self.grants = GatewayGrantCoordinator(
            baseURL: baseURL,
            store: store,
            session: session,
            refreshPath: "v1/oobe/grants/refresh",
            now: now,
            accountAccessPolicy: UnrestrictedManagedGatewayAccountAccessPolicy()
        )
    }

    /// Host-only provisioning handoff after App Attest succeeds.
    public func install(_ credentials: ManagedGatewayGrantCredentials) async throws {
        guard credentials.scopes == Self.allowedScopes,
              credentials.hasUsableRefreshToken(at: now()),
              credentials.refreshExpiresAt
                <= credentials.receivedAt.addingTimeInterval(30 * 60 + 1) else {
            throw ManagedGatewayError.invalidGrant
        }
        try await store.save(credentials)
    }

    public func accessToken(
        for capability: ManagedGatewayCapability,
        feature: ManagedGatewayOOBEFeature,
        forceRefresh: Bool = false
    ) async throws -> String {
        guard Self.allowedScopes.contains(capability),
              feature.requiredCapability == capability else {
            throw ManagedGatewayError.scopeNotGranted(capability)
        }
        guard let practice = practiceSession(),
              practice.isActive(at: now()),
              practice.expectedFeature == feature else {
            try? await clearGrant()
            throw ManagedGatewayError.missingGrant
        }
        return try await grants.accessToken(
            for: capability,
            forceRefresh: forceRefresh
        )
    }

    public func clearGrant() async throws {
        try await grants.clearGrant()
    }
}
