// GatewayGrantCoordinator.swift
// OSGKeyboard · Shared
//
// Creates and rotates scope-limited gateway grants. Refresh rotation is merged
// inside this actor so concurrent extension requests never replay an old token.

import CryptoKit
import Foundation

public actor GatewayGrantCoordinator {
    public static let defaultBaseURL = URL(string: "https://account.osglab.com")!

    private let baseURL: URL
    private let store: any GatewayGrantCredentialStore
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var refreshTask: Task<ManagedGatewayGrantCredentials, Error>?

    public init(
        baseURL: URL = GatewayGrantCoordinator.defaultBaseURL,
        store: any GatewayGrantCredentialStore = GatewayGrantKeychainStore(),
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.store = store
        self.session = session
        self.now = now
    }

    /// Host-only integration point. The account access token authorizes grant
    /// creation but is used only for this request and is never persisted here.
    @discardableResult
    public func createGrant(
        accountAccessToken: String,
        scopes: Set<ManagedGatewayCapability>,
        lifetimeSeconds: Int? = nil,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> ManagedGatewayGrantCredentials {
        guard !accountAccessToken.isEmpty else { throw ManagedGatewayError.invalidGrant }
        guard !scopes.isEmpty else {
            throw ManagedGatewayError.server(
                code: "invalid_request",
                status: 400,
                requestId: nil
            )
        }

        struct Body: Encodable {
            let scopes: [ManagedGatewayCapability]
            let lifetimeSeconds: Int?
        }

        var request = URLRequest(url: endpoint("v1/gateway/grants"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accountAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(
            Body(scopes: scopes.sorted { $0.rawValue < $1.rawValue }, lifetimeSeconds: lifetimeSeconds)
        )

        let credentials = try await sendGrantRequest(request)
        guard credentials.scopes == scopes else {
            throw ManagedGatewayError.invalidGrant
        }
        try await store.save(credentials)
        return credentials
    }

    public func accessToken(
        for scope: ManagedGatewayCapability,
        forceRefresh: Bool = false
    ) async throws -> String {
        guard let credentials = try await store.load() else {
            throw ManagedGatewayError.missingGrant
        }
        guard credentials.scopes.contains(scope) else {
            throw ManagedGatewayError.scopeNotGranted(scope)
        }
        if !forceRefresh, credentials.hasUsableAccessToken(for: scope, at: now()) {
            return credentials.accessToken
        }
        guard credentials.hasUsableRefreshToken(at: now()) else {
            try? await store.delete()
            throw ManagedGatewayError.invalidGrant
        }
        return try await refresh(credentials).accessToken
    }

    public func clearGrant() async throws {
        refreshTask?.cancel()
        refreshTask = nil
        try await store.delete()
    }

    private func refresh(
        _ credentials: ManagedGatewayGrantCredentials
    ) async throws -> ManagedGatewayGrantCredentials {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task {
            try await requestRefresh(using: credentials)
        }
        refreshTask = task
        do {
            let refreshed = try await task.value
            refreshTask = nil
            return refreshed
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func requestRefresh(
        using credentials: ManagedGatewayGrantCredentials
    ) async throws -> ManagedGatewayGrantCredentials {
        struct Body: Encodable {
            let refreshToken: String
        }

        var request = URLRequest(url: endpoint("v1/gateway/grants/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            Self.refreshTokenIdempotencyKey(credentials.refreshToken),
            forHTTPHeaderField: "Idempotency-Key"
        )
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(Body(refreshToken: credentials.refreshToken))

        do {
            let refreshed = try await sendGrantRequest(request)
            guard refreshed.grantId == credentials.grantId,
                  refreshed.scopes == credentials.scopes else {
                try? await store.delete()
                throw ManagedGatewayError.invalidGrant
            }
            try await store.save(refreshed)
            return refreshed
        } catch let error as ManagedGatewayError where error == .invalidGrant {
            try? await store.delete()
            throw error
        }
    }

    private func sendGrantRequest(
        _ request: URLRequest
    ) async throws -> ManagedGatewayGrantCredentials {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.transport("non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ManagedGatewayHTTP.error(
                    data: data,
                    status: http.statusCode,
                    requestId: http.value(forHTTPHeaderField: "X-Request-ID")
                )
            }
            do {
                return try Self.gatewayDecoder()
                    .decode(ManagedGatewayGrantTokenResponse.self, from: data)
                    .credentials(receivedAt: now())
            } catch {
                throw LLMError.decoding(String(describing: error))
            }
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw LLMError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw ManagedGatewayError.timeout
        } catch let error as ManagedGatewayError {
            throw error
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport(String(describing: error))
        }
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    static func refreshTokenIdempotencyKey(_ refreshToken: String) -> String {
        let digest = SHA256.hash(data: Data(refreshToken.utf8))
        return "gateway-refresh-v1-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func gatewayDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return decoder
    }
}

enum ManagedGatewayHTTP {
    static func error(
        data: Data,
        status: Int,
        requestId: String?
    ) -> ManagedGatewayError {
        let decoded = decodeError(from: data)
        let code = decoded?.code ?? HTTPURLResponse.localizedString(forStatusCode: status)
        let resolvedRequestId = decoded?.requestId ?? requestId

        switch code.lowercased() {
        case "insufficient_credits", "insufficient_balance", "credit_balance_insufficient":
            return .insufficientCredits
        case "unauthorized", "invalid_gateway_refresh", "gateway_grant_denied", "invalid_grant":
            return .invalidGrant
        default:
            return .server(code: code, status: status, requestId: resolvedRequestId)
        }
    }

    static func decodeError(from data: Data) -> ManagedGatewayErrorResponse? {
        if let direct = try? JSONDecoder().decode(ManagedGatewayErrorResponse.self, from: data) {
            return direct
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nested = object["error"] as? [String: Any],
              let code = nested["code"] as? String,
              let message = nested["message"] as? String else {
            return nil
        }
        return ManagedGatewayErrorResponse(
            code: code,
            message: message,
            requestId: nested["requestId"] as? String ?? ""
        )
    }
}
