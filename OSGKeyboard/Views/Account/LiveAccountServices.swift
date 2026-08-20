// LiveAccountServices.swift
// OSGKeyboard · Main App
//
// Adapts the host-private account protocol to the account-center UI. Account
// sessions never enter App Group storage; only scope-limited gateway grants do.

import Foundation
import OSGKeyboardHostSupport
import OSGKeyboardShared

@MainActor
enum LiveAccountDependencyFactory {
    static func make(bundle: Bundle = .main) -> AccountDependencies {
        guard let accessGroup = bundle.object(
            forInfoDictionaryKey: "OSGPrivateKeychainAccessGroup"
        ) as? String,
        let descriptor = try? HostPrivateAccountKeychainDescriptor(
            accessGroup: accessGroup
        ) else {
            return .unavailable
        }

        let sessionVault = HostPrivateAccountKeychain(descriptor: descriptor)
        let apiClient = AccountAPIClient(sessionVault: sessionVault)
        let integrity = DeviceIntegrityCoordinator(
            apiClient: apiClient,
            keyStateStore: sessionVault
        )
        let grantStore = GatewayGrantKeychainStore()
        let grants = GatewayGrantCoordinator(store: grantStore)
        let service = LiveAccountService(
            apiClient: apiClient,
            integrity: integrity,
            grants: grants,
            grantStore: grantStore,
            configuration: AppGroupStore()
        )
        return AccountDependencies(sessionService: service, centerService: service)
    }
}

actor AccountCenterSnapshotLoader {
    private let apiClient: AccountAPIClient
    private let decoder = JSONDecoder()

    init(apiClient: AccountAPIClient) {
        self.apiClient = apiClient
    }

    func load(
        cachedSnapshot: AccountCenterSnapshot?
    ) async throws -> AccountCenterSnapshot {
        async let account = apiClient.account()
        async let balance = resource(CreditBalanceDTO.self, .creditsBalance)
        async let profile = optionalResource(
            ReferralProfileDTO.self,
            .referralProfile,
            diagnosticName: "referral-profile"
        )
        async let referrals = optionalResource(
            [ReferralBindingDTO].self,
            .referrals(limit: 50),
            diagnosticName: "referrals"
        )
        async let campaigns = optionalResource(
            [ReferralCampaignDTO].self,
            .referralCampaigns,
            diagnosticName: "referral-campaigns"
        )

        let core: (OSGAccount, CreditBalanceDTO)
        do {
            core = try await (account, balance)
        } catch {
            OSGDiag.log(
                "account refresh core failed error=\(AccountDiagnostic.code(for: error))",
                category: "account"
            )
            throw error
        }
        let optionalValues = await (profile, referrals, campaigns)
        let invitationCode = await resolvedInvitationCode(
            profile: optionalValues.0,
            cachedProfile: cachedSnapshot?.referralProfile
        )
        let campaign = optionalValues.2?.first {
            $0.id == optionalValues.0?.code?.campaignId
        } ?? optionalValues.2?.first
        let referralProfile = if optionalValues.0 == nil,
                                 let cachedProfile = cachedSnapshot?.referralProfile {
            cachedProfile
        } else {
            AccountReferralProfile(
                code: invitationCode,
                boundCode: cachedSnapshot?.referralProfile.boundCode,
                inviterRewardCredits: campaign?.inviterRewardCredits
                    ?? cachedSnapshot?.referralProfile.inviterRewardCredits,
                inviteeRewardCredits: campaign?.inviteeRewardCredits
                    ?? cachedSnapshot?.referralProfile.inviteeRewardCredits
            )
        }
        let loadedReferrals = optionalValues.1?.map {
            AccountReferral(
                id: UUID(),
                status: Self.referralStatus($0.rewardStatus),
                createdAtEpochSeconds: Self.epochSeconds($0.boundAt),
                rewardCredits: nil
            )
        } ?? cachedSnapshot?.referrals ?? []

        return AccountCenterSnapshot(
            account: AccountSession(
                accountID: core.0.id,
                createdAtEpochSeconds: core.0.createdAtEpochSeconds,
                displayName: core.0.displayName
            ),
            credits: AccountCreditSummary(
                balance: core.1.balance,
                usedCredits: core.1.lifetimeUsed ?? 0
            ),
            referralProfile: referralProfile,
            referrals: loadedReferrals
        )
    }

    private func resource<Value: Decodable & Sendable>(
        _ type: Value.Type,
        _ resource: AccountAuthorizedResource
    ) async throws -> Value {
        let data = try await apiClient.authorizedResourceData(resource)
        return try decoder.decode(type, from: data)
    }

    private func optionalResource<Value: Decodable & Sendable>(
        _ type: Value.Type,
        _ resource: AccountAuthorizedResource,
        diagnosticName: String
    ) async -> Value? {
        do {
            return try await self.resource(type, resource)
        } catch {
            OSGDiag.log(
                "account refresh optional=\(diagnosticName) fallback=cache "
                    + "error=\(AccountDiagnostic.code(for: error))",
                category: "account"
            )
            return nil
        }
    }

    private func resolvedInvitationCode(
        profile: ReferralProfileDTO?,
        cachedProfile: AccountReferralProfile?
    ) async -> String? {
        if let code = profile?.code?.code ?? cachedProfile?.code {
            return code
        }
        do {
            let data = try await apiClient.authorizedResourceData(.createReferralCode)
            return try decoder.decode(ReferralCodeDTO.self, from: data).code
        } catch {
            OSGDiag.log(
                "account refresh optional=referral-code fallback=cache "
                    + "error=\(AccountDiagnostic.code(for: error))",
                category: "account"
            )
            return cachedProfile?.code
        }
    }

    private static func referralStatus(_ value: String) -> AccountReferralStatus {
        switch value.uppercased() {
        case "REWARDED":
            return .rewarded
        case "INELIGIBLE_BUDGET":
            return .ineligible
        default:
            return .pending
        }
    }

    private static func epochSeconds(_ value: String) -> Int64? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        let date = fractional.date(from: value) ?? standard.date(from: value)
        return date.map { Int64($0.timeIntervalSince1970) }
    }
}

private actor LiveAccountService: AccountSessionServicing, AccountCenterServicing {
    private let apiClient: AccountAPIClient
    private let accountCenterLoader: AccountCenterSnapshotLoader
    private let integrity: DeviceIntegrityCoordinator
    private let grants: GatewayGrantCoordinator
    private let grantStore: any GatewayGrantCredentialStore
    private let configuration: AppGroupStore
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        apiClient: AccountAPIClient,
        integrity: DeviceIntegrityCoordinator,
        grants: GatewayGrantCoordinator,
        grantStore: any GatewayGrantCredentialStore,
        configuration: AppGroupStore
    ) {
        self.apiClient = apiClient
        accountCenterLoader = AccountCenterSnapshotLoader(apiClient: apiClient)
        self.integrity = integrity
        self.grants = grants
        self.grantStore = grantStore
        self.configuration = configuration
    }

    func restoreSession() async throws -> AccountSession? {
        guard let cachedSession = try await apiClient.currentSession() else { return nil }
        let account: OSGAccount?
        do {
            account = try await apiClient.account()
        } catch let error as AccountAPIError {
            switch error {
            case .sessionUnavailable, .unauthorized, .refreshTokenReuse:
                return nil
            default:
                account = nil
            }
        } catch {
            account = nil
        }
        let session = try await apiClient.currentSession() ?? cachedSession
        await synchronizeManagedGrant()
        return uiSession(
            session,
            createdAtEpochSeconds: account?.createdAtEpochSeconds ?? 0,
            displayName: account?.displayName
        )
    }

    func signIn(with payload: AppleAuthorizationPayload) async throws -> AccountSession {
        let credential = AppleSignInCredential(
            identityToken: payload.identityToken,
            authorizationCode: payload.authorizationCode
        )
        let evidence: DeviceIntegrityEvidence
        do {
            evidence = try await integrity.evidenceForAppleSignIn(
                credential: credential,
                rawNonce: payload.nonce
            )
        } catch {
            OSGDiag.log(
                "signIn failed stage=integrity error=\(AccountDiagnostic.code(for: error))",
                category: "account"
            )
            throw error
        }
        OSGDiag.log(
            "signIn integrity ready deviceCheck=\(evidence.deviceCheckToken == nil ? 0 : 1) "
                + "appAttest=\(evidence.appAttest == nil ? 0 : 1)",
            category: "account"
        )
        let session: OSGKeyboardHostSupport.AccountSession
        do {
            session = try await apiClient.signInWithApple(
                AppleSignInRequest(
                    identityToken: payload.identityToken,
                    authorizationCode: payload.authorizationCode,
                    nonce: payload.nonce,
                    displayName: payload.displayName,
                    deviceCheckToken: evidence.deviceCheckToken,
                    appAttest: evidence.appAttest
                )
            )
        } catch {
            OSGDiag.log(
                "signIn failed stage=session error=\(AccountDiagnostic.code(for: error))",
                category: "account"
            )
            throw error
        }
        await synchronizeManagedGrant()
        let account: OSGAccount
        do {
            account = try await apiClient.account()
        } catch {
            OSGDiag.log(
                "signIn failed stage=account error=\(AccountDiagnostic.code(for: error))",
                category: "account"
            )
            throw error
        }
        OSGDiag.log("signIn completed", category: "account")
        return uiSession(
            session,
            createdAtEpochSeconds: account.createdAtEpochSeconds,
            displayName: account.displayName
        )
    }

    func signOut() async throws {
        await revokeManagedGrantIfPossible()
        do {
            try await apiClient.logout()
        } catch {
            try? await grants.clearGrant()
            configuration.setCredentialSource(.byok)
            throw error
        }
        try? await grants.clearGrant()
        configuration.setCredentialSource(.byok)
    }

    func deleteAccount(with payload: AppleAuthorizationPayload) async throws {
        try await apiClient.deleteAccount(
            identityToken: payload.identityToken,
            authorizationCode: payload.authorizationCode,
            nonce: payload.nonce
        )
        try? await grants.clearGrant()
        await integrity.clearLocalKeyState()
        configuration.setCredentialSource(.byok)
    }

    func prepareManagedGateway() async throws {
        guard try await apiClient.currentSession() != nil else {
            throw AccountAPIError.sessionUnavailable
        }
        try await ensureManagedGrant()
    }

    func clearManagedGateway() async {
        await revokeManagedGrantIfPossible()
    }

    func loadAccountCenter() async throws -> AccountCenterSnapshot {
        try await accountCenterLoader.load(cachedSnapshot: nil)
    }

    func loadAccountCenter(
        cachedSnapshot: AccountCenterSnapshot?
    ) async throws -> AccountCenterSnapshot {
        try await accountCenterLoader.load(cachedSnapshot: cachedSnapshot)
    }

    func updateDisplayName(_ displayName: String) async throws -> AccountSession {
        let account = try await apiClient.updateAccount(displayName: displayName)
        return AccountSession(
            accountID: account.id,
            createdAtEpochSeconds: account.createdAtEpochSeconds,
            displayName: account.displayName
        )
    }

    func createReferralCode() async throws -> String {
        let data = try await apiClient.authorizedResourceData(.createReferralCode)
        return try decoder.decode(ReferralCodeDTO.self, from: data).code
    }

    func redeemReferral(code: String) async throws {
        struct Request: Encodable { let code: String }
        let body = try encoder.encode(Request(code: code))
        _ = try await apiClient.authorizedResourceData(.redeemReferral, body: body)
    }

    func loadCreditProducts() async throws -> [AccountCreditProduct] {
        let products = try await resource([StoreKitProductDTO].self, .storeKitProducts)
        return products.map {
            AccountCreditProduct(productID: $0.productId, credits: $0.credits)
        }
    }

    func submitCreditTransaction(_ signedTransaction: String) async throws -> AccountCreditPurchase {
        let request = StoreKitTransactionRequestDTO(signedTransaction: signedTransaction)
        let data = try await apiClient.authorizedResourceData(
            .submitStoreKitTransaction,
            body: try encoder.encode(request)
        )
        let purchase = try decoder.decode(StoreKitPurchaseDTO.self, from: data)
        return AccountCreditPurchase(
            transactionID: purchase.transactionId,
            productID: purchase.productId,
            creditsGranted: purchase.creditsGranted,
            balanceAfter: purchase.balanceAfter,
            replayed: purchase.replayed
        )
    }

    func loadCreditPurchaseHistory(
        limit: Int,
        cursor: String?
    ) async throws -> AccountCreditPurchaseHistoryPage {
        let data = try await apiClient.authorizedResourceData(
            .storeKitTransactions(limit: limit, cursor: cursor)
        )
        let response = try decoder.decode(
            StoreKitTransactionHistoryResponseDTO.self,
            from: data
        )
        let items = try response.items.map { item in
            guard let purchasedAt = Self.storeKitPurchaseDate(item.purchasedAt),
                  let status = AccountCreditPurchaseStatus(rawValue: item.status) else {
                throw AccountAPIError.decoding
            }
            return AccountCreditPurchaseRecord(
                transactionID: item.transactionId,
                productID: item.productId,
                creditsGranted: item.creditsGranted,
                balanceAfter: item.balanceAfter,
                purchasedAt: purchasedAt,
                status: status
            )
        }
        return AccountCreditPurchaseHistoryPage(
            items: items,
            nextCursor: response.nextCursor
        )
    }

    private func resource<Value: Decodable & Sendable>(
        _ type: Value.Type,
        _ resource: AccountAuthorizedResource
    ) async throws -> Value {
        let data = try await apiClient.authorizedResourceData(resource)
        return try decoder.decode(type, from: data)
    }

    private static func storeKitPurchaseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: value) ?? standard.date(from: value)
    }

    private func synchronizeManagedGrant() async {
        if configuration.credentialSource == .managed {
            do {
                try await ensureManagedGrant()
            } catch {
                // Keep the user's explicit billing choice. A transient grant,
                // network, or balance failure must surface as a managed-service
                // error instead of silently switching requests to a BYOK key.
                OSGDiag.log(
                    "managedGrant synchronization failed "
                        + "errorCategory=\(String(reflecting: type(of: error)))",
                    category: "account"
                )
            }
        } else {
            try? await grants.clearGrant()
        }
    }

    private func ensureManagedGrant() async throws {
        let expected = ManagedGatewayScopePolicy.scopes(
            engineMode: configuration.engineMode
        )
        if let existing = try await grantStore.load(),
           existing.scopes == expected,
           existing.hasUsableRefreshToken() {
            _ = try await grants.accessToken(for: .polish)
            return
        }
        await revokeManagedGrantIfPossible()
        let idempotencyKey = UUID().uuidString
        let accessToken = try await apiClient.accessTokenForAuthorizedRequest()
        do {
            _ = try await grants.createGrant(
                accountAccessToken: accessToken,
                scopes: expected,
                idempotencyKey: idempotencyKey
            )
        } catch ManagedGatewayError.invalidGrant {
            let replacement = try await apiClient.refreshAccessToken(
                afterUnauthorizedAccessToken: accessToken
            )
            _ = try await grants.createGrant(
                accountAccessToken: replacement,
                scopes: expected,
                idempotencyKey: idempotencyKey
            )
        }
    }

    private func revokeManagedGrantIfPossible() async {
        if let existing = try? await grantStore.load(),
           let grantId = UUID(uuidString: existing.grantId) {
            _ = try? await apiClient.authorizedResourceData(
                .revokeGatewayGrant(grantId)
            )
        }
        try? await grants.clearGrant()
    }

    private func uiSession(
        _ session: OSGKeyboardHostSupport.AccountSession,
        createdAtEpochSeconds: Int64,
        displayName: String?
    ) -> AccountSession {
        AccountSession(
            accountID: session.accountId,
            createdAtEpochSeconds: createdAtEpochSeconds,
            displayName: displayName
        )
    }

}

private enum AccountDiagnostic {
    static func code(for error: Error) -> String {
        guard let error = error as? AccountAPIError else {
            return String(describing: type(of: error))
        }
        switch error {
        case .invalidRequest(let message):
            return invalidRequestCode(for: message)
        case .unauthorized:
            return "unauthorized"
        case .refreshTokenReuse:
            return "refresh-token-reuse"
        case .externalServiceUnavailable(let message):
            return unavailableServiceCode(for: message)
        case .conflict:
            return "conflict"
        case .rateLimited:
            return "rate-limited"
        case let .server(statusCode, code, _):
            return "server-\(statusCode)-\(code)"
        case .transport:
            return "transport"
        case .invalidResponse:
            return "invalid-response"
        case .decoding:
            return "decoding"
        case .secureStorage:
            return "secure-storage"
        case .sessionUnavailable:
            return "session-unavailable"
        case .appleAuthorization:
            return "apple-authorization"
        case .integrityUnavailable:
            return "integrity-unavailable"
        }
    }

    private static func invalidRequestCode(for message: String) -> String {
        switch message {
        case "DeviceCheck verification failed":
            return "device-check-rejected"
        case "App Attest verification failed":
            return "app-attest-rejected"
        case "identityToken exceeds the maximum length":
            return "identity-token-too-large"
        case "authorizationCode exceeds the maximum length":
            return "authorization-code-too-large"
        case "nonce exceeds the maximum length":
            return "nonce-too-large"
        default:
            return "invalid-request"
        }
    }

    private static func unavailableServiceCode(for message: String) -> String {
        switch message {
        case "DeviceCheck is temporarily unavailable":
            return "device-check-unavailable"
        case "App Attest is temporarily unavailable":
            return "app-attest-unavailable"
        case "Apple identity verification is temporarily unavailable":
            return "apple-identity-unavailable"
        case "Apple token service is temporarily unavailable":
            return "apple-token-service-unavailable"
        default:
            return "external-service-unavailable"
        }
    }
}

private struct CreditBalanceDTO: Decodable, Sendable {
    let balance: Int64
    let lifetimeUsed: Int64?
}

private struct ReferralCodeDTO: Decodable, Sendable {
    let code: String
    let campaignId: String?
}

private struct ReferralProfileDTO: Decodable, Sendable {
    let code: ReferralCodeDTO?
}

private struct ReferralCampaignDTO: Decodable, Sendable {
    let id: String
    let inviterRewardCredits: Int64
    let inviteeRewardCredits: Int64
}

private struct ReferralBindingDTO: Decodable, Sendable {
    let boundAt: String
    let rewardStatus: String
}

private struct StoreKitProductDTO: Decodable, Sendable {
    let productId: String
    let credits: Int64
}

private struct StoreKitTransactionRequestDTO: Encodable, Sendable {
    let signedTransaction: String
}

private struct StoreKitPurchaseDTO: Decodable, Sendable {
    let transactionId: String
    let productId: String
    let creditsGranted: Int64
    let balanceAfter: Int64
    let replayed: Bool
}

private struct StoreKitTransactionHistoryResponseDTO: Decodable, Sendable {
    let items: [StoreKitTransactionHistoryItemDTO]
    let nextCursor: String?
}

private struct StoreKitTransactionHistoryItemDTO: Decodable, Sendable {
    let transactionId: String
    let productId: String
    let creditsGranted: Int64
    let balanceAfter: Int64
    let purchasedAt: String
    let status: String
}
