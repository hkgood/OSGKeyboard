// AccountAnalyticsBearerBridge.swift
// OSGKeyboard · Main App / Mac
//
// Bridges account credentials into the analytics uploader. Extracted from
// `AnalyticsHostService.swift` (UIKit-only) so the macOS target — which
// compiles the account stack at source level — can reuse it unchanged.

#if canImport(OSGKeyboardHostSupport)
import OSGKeyboardHostSupport
#endif
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif
import Foundation

final class HostAnalyticsBearerBridge: AnalyticsBearerProviding, @unchecked Sendable {
    static let shared = HostAnalyticsBearerBridge()

    private let lock = NSLock()
    private var provider: (any AnalyticsBearerProviding)?

    func install(_ provider: any AnalyticsBearerProviding) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    func bearerToken() async throws -> String? {
        try await currentProvider()?.bearerToken()
    }

    func refreshBearerToken(
        afterUnauthorizedAccessToken failedToken: String?
    ) async throws -> String? {
        try await currentProvider()?.refreshBearerToken(
            afterUnauthorizedAccessToken: failedToken
        )
    }

    private func currentProvider() -> (any AnalyticsBearerProviding)? {
        lock.lock()
        defer { lock.unlock() }
        return provider
    }
}

struct AccountAnalyticsBearerProvider: AnalyticsBearerProviding {
    let apiClient: AccountAPIClient

    func bearerToken() async throws -> String? {
        guard try await apiClient.currentSession() != nil else { return nil }
        do {
            return try await apiClient.accessTokenForAuthorizedRequest()
        } catch let error as AccountAPIError where Self.isInvalidSession(error) {
            return nil
        }
    }

    func refreshBearerToken(
        afterUnauthorizedAccessToken failedToken: String?
    ) async throws -> String? {
        guard let failedToken, !failedToken.isEmpty else { return nil }
        do {
            return try await apiClient.refreshAccessToken(
                afterUnauthorizedAccessToken: failedToken
            )
        } catch let error as AccountAPIError where Self.isInvalidSession(error) {
            return nil
        }
    }

    private static func isInvalidSession(_ error: AccountAPIError) -> Bool {
        switch error {
        case .sessionUnavailable, .unauthorized, .refreshTokenReuse:
            return true
        default:
            return false
        }
    }
}
