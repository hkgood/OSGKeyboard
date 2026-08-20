// AccountAPIClient.swift
// OSGKeyboard · HostSupport
//
// The single HTTP exit for account, auth, and integrity traffic.

import Foundation

public protocol AccountHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionAccountHTTPTransport: AccountHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AccountAPIError.invalidResponse
        }
        return (data, response)
    }
}

public actor AccountAPIClient {
    private enum Endpoint {
        case appleSignIn
        case refresh
        case logout
        case account
        case updateAccount
        case deleteAccount
        case integrityChallenge
        case attest
        case assert

        var method: String {
            switch self {
            case .account:
                return "GET"
            case .updateAccount:
                return "PATCH"
            case .deleteAccount:
                return "DELETE"
            default:
                return "POST"
            }
        }

        var path: String {
            switch self {
            case .appleSignIn:
                return "/v1/auth/apple"
            case .refresh:
                return "/v1/auth/refresh"
            case .logout:
                return "/v1/auth/logout"
            case .account, .updateAccount, .deleteAccount:
                return "/v1/account"
            case .integrityChallenge:
                return "/v1/integrity/challenges"
            case .attest:
                return "/v1/integrity/attest"
            case .assert:
                return "/v1/integrity/assert"
            }
        }
    }

    private struct RefreshOperation {
        let id: UUID
        let task: Task<AccountSession, Error>
    }

    private let baseURL: URL
    private let transport: any AccountHTTPTransport
    private let sessionVault: any AccountSessionVault
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var cachedSession: AccountSession?
    private var didLoadSession = false
    private var refreshOperation: RefreshOperation?

    public init(
        baseURL: URL = URL(string: "https://account.osglab.com")!,
        transport: any AccountHTTPTransport = URLSessionAccountHTTPTransport(),
        sessionVault: any AccountSessionVault,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.sessionVault = sessionVault
        self.now = now
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.decoder = JSONDecoder()
    }

    @discardableResult
    public func signInWithApple(_ request: AppleSignInRequest) async throws -> AccountSession {
        let data = try await perform(
            endpoint: .appleSignIn,
            body: try encode(request),
            requiresSession: false
        )
        let session = try decode(APIDataEnvelope<AccountSession>.self, from: data).data
        try await replaceSession(with: session)
        return session
    }

    public func currentSession() async throws -> AccountSession? {
        try await loadSessionIfNeeded()
    }

    public func accessTokenForAuthorizedRequest() async throws -> String {
        try await sessionForRequest().accessToken
    }

    public func refreshAccessToken(
        afterUnauthorizedAccessToken failedToken: String
    ) async throws -> String {
        try await refreshSession(afterUnauthorizedAccessToken: failedToken).accessToken
    }

    public func account() async throws -> OSGAccount {
        let data = try await perform(endpoint: .account, body: nil, requiresSession: true)
        return try decode(APIDataEnvelope<OSGAccount>.self, from: data).data
    }

    public func updateAccount(displayName: String) async throws -> OSGAccount {
        let data = try await perform(
            endpoint: .updateAccount,
            body: try encode(UpdateAccountProfileRequest(displayName: displayName)),
            requiresSession: true
        )
        return try decode(APIDataEnvelope<OSGAccount>.self, from: data).data
    }

    public func authorizedResourceData(
        _ resource: AccountAuthorizedResource,
        body: Data? = nil
    ) async throws -> Data {
        do {
            return try await performAuthorizedResource(
                resource,
                body: body
            )
        } catch {
            guard resource.method == "GET", Self.isTransient(error) else {
                throw error
            }
            try await Task.sleep(for: .milliseconds(150))
            return try await performAuthorizedResource(
                resource,
                body: body
            )
        }
    }

    private func performAuthorizedResource(
        _ resource: AccountAuthorizedResource,
        body: Data?
    ) async throws -> Data {
        let session = try await sessionForRequest()
        let firstRequest = try makeAuthorizedResourceRequest(
            resource,
            body: body,
            accessToken: session.accessToken
        )
        let firstResponse = try await send(firstRequest)
        if firstResponse.response.statusCode == 401 {
            let replacement = try await refreshSession(
                afterUnauthorizedAccessToken: session.accessToken
            )
            let retryRequest = try makeAuthorizedResourceRequest(
                resource,
                body: body,
                accessToken: replacement.accessToken
            )
            let retryResponse = try await send(retryRequest)
            if retryResponse.response.statusCode == 401 {
                try await clearSession()
            }
            return try validatedData(retryResponse)
        }
        return try validatedData(firstResponse)
    }

    public func logout() async throws {
        // Local sign-out is authoritative for the device. Revocation remains
        // best-effort so an offline server cannot leave credentials at rest.
        _ = try? await perform(endpoint: .logout, body: nil, requiresSession: true)
        try await clearSession()
    }

    func deleteAccount(with request: DeleteAccountRequest) async throws {
        _ = try await perform(
            endpoint: .deleteAccount,
            body: try encode(request),
            requiresSession: true
        )
        try await clearSession()
    }

    public func deleteAccount(
        identityToken: String,
        authorizationCode: String,
        nonce: String
    ) async throws {
        try await deleteAccount(
            with: DeleteAccountRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: nonce
            )
        )
    }

    public func issueAppAttestChallenge(
        purpose: AppAttestChallengePurpose,
        keyId: String
    ) async throws -> AppAttestChallenge {
        let data = try await perform(
            endpoint: .integrityChallenge,
            body: try encode(AppAttestChallengeRequest(purpose: purpose, keyId: keyId)),
            requiresSession: false
        )
        return try decode(AppAttestChallenge.self, from: data)
    }

    public func submitAttestation(
        challenge: AppAttestChallenge,
        keyId: String,
        attestationObject: Data
    ) async throws {
        let request = AppAttestationRequest(
            challengeId: challenge.challengeId,
            challenge: challenge.challenge,
            keyId: keyId,
            attestationObject: attestationObject.base64EncodedString()
        )
        _ = try await perform(
            endpoint: .attest,
            body: try encode(request),
            requiresSession: false
        )
    }

    @discardableResult
    public func submitAssertion(
        challenge: AppAttestChallenge,
        keyId: String,
        assertion: Data,
        clientDataHash: Data
    ) async throws -> Int64 {
        let request = AppAssertionRequest(
            challengeId: challenge.challengeId,
            challenge: challenge.challenge,
            keyId: keyId,
            assertion: assertion.base64EncodedString(),
            clientDataHash: clientDataHash.base64URLEncodedString()
        )
        let data = try await perform(
            endpoint: .assert,
            body: try encode(request),
            requiresSession: false
        )
        return try decode(AppAssertionResponse.self, from: data).counter
    }

    private func perform(
        endpoint: Endpoint,
        body: Data?,
        requiresSession: Bool
    ) async throws -> Data {
        do {
            return try await performOnce(
                endpoint: endpoint,
                body: body,
                requiresSession: requiresSession
            )
        } catch {
            guard endpoint.method == "GET", Self.isTransient(error) else {
                throw error
            }
            try await Task.sleep(for: .milliseconds(150))
            return try await performOnce(
                endpoint: endpoint,
                body: body,
                requiresSession: requiresSession
            )
        }
    }

    private func performOnce(
        endpoint: Endpoint,
        body: Data?,
        requiresSession: Bool
    ) async throws -> Data {
        let session = requiresSession ? try await sessionForRequest() : nil
        let firstRequest = try makeRequest(
            endpoint: endpoint,
            body: body,
            accessToken: session?.accessToken
        )
        let firstResponse = try await send(firstRequest)

        if requiresSession, firstResponse.response.statusCode == 401, let session {
            let replacement = try await refreshSession(afterUnauthorizedAccessToken: session.accessToken)
            let retryRequest = try makeRequest(
                endpoint: endpoint,
                body: body,
                accessToken: replacement.accessToken
            )
            let retryResponse = try await send(retryRequest)
            if retryResponse.response.statusCode == 401 {
                try await clearSession()
            }
            return try validatedData(retryResponse)
        }

        return try validatedData(firstResponse)
    }

    private static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? AccountAPIError else { return false }
        switch error {
        case .transport, .externalServiceUnavailable:
            return true
        case .server(let statusCode, _, _):
            return (500..<600).contains(statusCode)
        default:
            return false
        }
    }

    private func sessionForRequest() async throws -> AccountSession {
        guard let session = try await loadSessionIfNeeded() else {
            throw AccountAPIError.sessionUnavailable
        }
        let nowSeconds = Int64(now().timeIntervalSince1970)
        guard session.refreshTokenExpiresAtEpochSeconds > nowSeconds else {
            try await clearSession()
            throw AccountAPIError.unauthorized("The refresh token has expired.")
        }
        if session.accessTokenExpiresAtEpochSeconds <= nowSeconds + 30 {
            return try await refreshSession(afterUnauthorizedAccessToken: session.accessToken)
        }
        return session
    }

    private func refreshSession(afterUnauthorizedAccessToken failedToken: String) async throws -> AccountSession {
        guard let current = try await loadSessionIfNeeded() else {
            throw AccountAPIError.sessionUnavailable
        }
        if current.accessToken != failedToken {
            return current
        }
        if let refreshOperation {
            return try await finishRefresh(refreshOperation)
        }

        let operation = RefreshOperation(
            id: UUID(),
            task: Task {
                try await self.requestRefresh(using: current.refreshToken)
            }
        )
        refreshOperation = operation
        return try await finishRefresh(operation)
    }

    private func finishRefresh(_ operation: RefreshOperation) async throws -> AccountSession {
        do {
            let replacement = try await operation.task.value
            try await replaceSession(with: replacement)
            if refreshOperation?.id == operation.id {
                refreshOperation = nil
            }
            return replacement
        } catch {
            if refreshOperation?.id == operation.id {
                refreshOperation = nil
            }
            if shouldClearSession(afterRefreshError: error) {
                try? await clearSession()
            }
            throw error
        }
    }

    private func requestRefresh(using refreshToken: String) async throws -> AccountSession {
        let request = try makeRequest(
            endpoint: .refresh,
            body: try encode(RefreshSessionRequest(refreshToken: refreshToken)),
            accessToken: nil
        )
        let response = try await send(request)
        let data = try validatedData(response)
        return try decode(APIDataEnvelope<AccountSession>.self, from: data).data
    }

    private func shouldClearSession(afterRefreshError error: Error) -> Bool {
        guard let error = error as? AccountAPIError else { return false }
        switch error {
        case .refreshTokenReuse, .unauthorized:
            return true
        default:
            return false
        }
    }

    private func loadSessionIfNeeded() async throws -> AccountSession? {
        if didLoadSession {
            return cachedSession
        }
        do {
            cachedSession = try await sessionVault.loadSession()
            didLoadSession = true
            return cachedSession
        } catch {
            throw AccountAPIError.secureStorage
        }
    }

    private func replaceSession(with session: AccountSession) async throws {
        do {
            try await sessionVault.saveSession(session)
            cachedSession = session
            didLoadSession = true
        } catch {
            cachedSession = nil
            didLoadSession = true
            try? await sessionVault.clearSession()
            throw AccountAPIError.secureStorage
        }
    }

    private func clearSession() async throws {
        cachedSession = nil
        didLoadSession = true
        do {
            try await sessionVault.clearSession()
        } catch {
            throw AccountAPIError.secureStorage
        }
    }

    private func makeRequest(
        endpoint: Endpoint,
        body: Data?,
        accessToken: String?
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL)?.absoluteURL else {
            throw AccountAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeAuthorizedResourceRequest(
        _ resource: AccountAuthorizedResource,
        body: Data?,
        accessToken: String
    ) throws -> URLRequest {
        guard let url = URL(string: resource.path, relativeTo: baseURL)?.absoluteURL,
              url.scheme == baseURL.scheme,
              url.host == baseURL.host else {
            throw AccountAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = resource.method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if resource == .creditsBalance {
            // Credit checks must revalidate with the server instead of reusing
            // a URL cache entry whose age may exceed the UI freshness window.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        do {
            return try await transport.data(for: request)
        } catch let error as AccountAPIError {
            throw error
        } catch {
            throw AccountAPIError.transport
        }
    }

    private func validatedData(
        _ result: (data: Data, response: HTTPURLResponse)
    ) throws -> Data {
        guard (200..<300).contains(result.response.statusCode) else {
            throw mapAPIError(statusCode: result.response.statusCode, data: result.data)
        }
        return result.data
    }

    private func mapAPIError(statusCode: Int, data: Data) -> AccountAPIError {
        let payload = try? decoder.decode(APIErrorEnvelope.self, from: data).error
        let legacyMessage = try? decoder.decode(LegacyAPIErrorEnvelope.self, from: data).error
        let code = payload?.code ?? "http_error"
        let message = payload?.message
            ?? legacyMessage
            ?? "The account service request failed."
        switch code {
        case "invalid_request":
            return .invalidRequest(message)
        case "unauthorized":
            return .unauthorized(message)
        case "refresh_token_reuse":
            return .refreshTokenReuse
        case "external_service_unavailable":
            return .externalServiceUnavailable(message)
        case "conflict":
            return .conflict(message)
        case "rate_limited":
            return .rateLimited(message)
        default:
            return .server(statusCode: statusCode, code: code, message: message)
        }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw AccountAPIError.invalidRequest("The request could not be encoded.")
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AccountAPIError.decoding
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        guard value.range(of: #"^[A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        let padding = String(repeating: "=", count: (4 - value.count % 4) % 4)
        let base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + padding
        self.init(base64Encoded: base64)
    }
}
