// AccountAPIClientTests.swift
// OSGKeyboardTests
//
// Hermetic tests for session rotation, retry limits, and stable API errors.

@testable import OSGKeyboardHostSupport
import XCTest

final class AccountAPIClientTests: XCTestCase {
    func testAppleSignInDecodesEnvelopeAndStoresWholeSession() async throws {
        let expected = makeAccountSession()
        let transport = QueueAccountTransport([
            .init(statusCode: 200, body: try sessionEnvelopeData(expected))
        ])
        let store = InMemoryAccountSecurityStore()
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        let result = try await client.signInWithApple(
            AppleSignInRequest(
                identityToken: "identity",
                authorizationCode: "authorization",
                nonce: "raw-nonce",
                deviceCheckToken: "device-token",
                appAttest: nil
            )
        )

        XCTAssertEqual(result, expected)
        let stored = await store.session
        XCTAssertEqual(stored, expected)
        let requests = await transport.requests
        XCTAssertEqual(requests.single?.url?.path, "/v1/auth/apple")
        XCTAssertNil(requests.single?.value(forHTTPHeaderField: "Authorization"))
    }

    func testNicknameUpdateUsesAuthenticatedPatch() async throws {
        let session = makeAccountSession()
        let body = Data(
            """
            {"data":{"id":"\(session.accountId.uuidString)","createdAtEpochSeconds":1,"displayName":"OSG 用户"}}
            """.utf8
        )
        let transport = QueueAccountTransport([.init(statusCode: 200, body: body)])
        let store = InMemoryAccountSecurityStore(session: session)
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        let account = try await client.updateAccount(displayName: "OSG 用户")

        let requests = await transport.requests
        XCTAssertEqual(account.displayName, "OSG 用户")
        XCTAssertEqual(requests.single?.httpMethod, "PATCH")
        XCTAssertEqual(requests.single?.url?.path, "/v1/account")
        XCTAssertEqual(String(data: requests.single?.httpBody ?? Data(), encoding: .utf8), """
        {"displayName":"OSG 用户"}
        """)
    }

    func testUnauthorizedRequestRefreshesAndRetriesExactlyOnce() async throws {
        let old = makeAccountSession()
        let replacement = makeAccountSession(
            accessToken: "access-new",
            refreshToken: "refresh-new"
        )
        let transport = QueueAccountTransport([
            .init(statusCode: 401, body: apiErrorData(code: "unauthorized", message: "expired")),
            .init(statusCode: 200, body: try sessionEnvelopeData(replacement)),
            .init(statusCode: 401, body: apiErrorData(code: "unauthorized", message: "still denied"))
        ])
        let store = InMemoryAccountSecurityStore(session: old)
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        do {
            _ = try await client.account()
            XCTFail("Expected the single retry to fail")
        } catch let error as AccountAPIError {
            XCTAssertEqual(error, .unauthorized("still denied"))
        }

        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url?.path), [
            "/v1/account",
            "/v1/auth/refresh",
            "/v1/account"
        ])
        XCTAssertEqual(
            requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-new"
        )
        let stored = await store.session
        let clearCount = await store.clearSessionCount
        XCTAssertNil(stored)
        XCTAssertEqual(clearCount, 1)
    }

    func testAuthorizedAccessTokenRefreshesAnExpiringCachedSession() async throws {
        let old = makeAccountSession(accessExpiry: 1_020)
        let replacement = makeAccountSession(
            accessToken: "access-fresh",
            refreshToken: "refresh-fresh"
        )
        let transport = QueueAccountTransport([
            .init(statusCode: 200, body: try sessionEnvelopeData(replacement))
        ])
        let store = InMemoryAccountSecurityStore(session: old)
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let token = try await client.accessTokenForAuthorizedRequest()

        XCTAssertEqual(token, "access-fresh")
        let requests = await transport.requests
        XCTAssertEqual(requests.single?.url?.path, "/v1/auth/refresh")
    }

    func testConcurrentUnauthorizedRequestsMergeRefreshRotation() async throws {
        let old = makeAccountSession()
        let replacement = makeAccountSession(
            accessToken: "access-new",
            refreshToken: "refresh-new"
        )
        let transport = RefreshMergingTransport(replacementSession: replacement)
        let store = InMemoryAccountSecurityStore(session: old)
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        async let first = client.account()
        async let second = client.account()
        let (firstAccount, secondAccount) = try await (first, second)
        let accounts = [firstAccount, secondAccount]

        XCTAssertEqual(
            accounts,
            [
                OSGAccount(id: old.accountId, createdAtEpochSeconds: 1),
                OSGAccount(id: old.accountId, createdAtEpochSeconds: 1)
            ]
        )
        let refreshCount = await transport.refreshCount
        XCTAssertEqual(refreshCount, 1)
        let stored = await store.session
        XCTAssertEqual(stored, replacement)
    }

    func testRefreshTokenReuseClearsPrivateSession() async throws {
        let old = makeAccountSession()
        let replacement = makeAccountSession(accessToken: "unused", refreshToken: "unused")
        let transport = RefreshMergingTransport(
            replacementSession: replacement,
            refreshError: .init(
                statusCode: 401,
                body: apiErrorData(
                    code: "refresh_token_reuse",
                    message: "family revoked"
                )
            )
        )
        let store = InMemoryAccountSecurityStore(session: old)
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        do {
            _ = try await client.account()
            XCTFail("Expected refresh-token reuse")
        } catch let error as AccountAPIError {
            XCTAssertEqual(error, .refreshTokenReuse)
        }

        let stored = await store.session
        let clearCount = await store.clearSessionCount
        XCTAssertNil(stored)
        XCTAssertEqual(clearCount, 1)
    }

    func testLogoutClearsPrivateSessionWhenRevocationIsUnavailable() async throws {
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let transport = QueueAccountTransport([])
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        try await client.logout()

        let stored = await store.session
        let clearCount = await store.clearSessionCount
        let requests = await transport.requests
        XCTAssertNil(stored)
        XCTAssertEqual(clearCount, 1)
        XCTAssertEqual(requests.single?.url?.path, "/v1/auth/logout")
    }

    func testDeleteAccountUsesAuthenticatedDeleteAndClearsPrivateSession() async throws {
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let transport = QueueAccountTransport([
            .init(statusCode: 204, body: Data())
        ])
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        try await client.deleteAccount(
            with: DeleteAccountRequest(
                identityToken: "identity",
                authorizationCode: "authorization",
                nonce: "nonce"
            )
        )

        let requests = await transport.requests
        let stored = await store.session
        XCTAssertEqual(requests.single?.httpMethod, "DELETE")
        XCTAssertEqual(requests.single?.url?.path, "/v1/account")
        XCTAssertEqual(
            requests.single?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-old"
        )
        XCTAssertNil(stored)
    }

    func testStableServerErrorCodeMapsToTypedError() async throws {
        let transport = QueueAccountTransport([
            .init(
                statusCode: 503,
                body: apiErrorData(
                    code: "external_service_unavailable",
                    message: "Apple is temporarily unavailable"
                )
            )
        ])
        let store = InMemoryAccountSecurityStore()
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        do {
            _ = try await client.signInWithApple(
                AppleSignInRequest(
                    identityToken: "identity",
                    authorizationCode: "code",
                    nonce: "nonce",
                    deviceCheckToken: nil,
                    appAttest: nil
                )
            )
            XCTFail("Expected mapped server error")
        } catch let error as AccountAPIError {
            XCTAssertEqual(
                error,
                .externalServiceUnavailable("Apple is temporarily unavailable")
            )
        }
    }

    func testStoreKitSubmissionUsesOnlyTheClosedAuthorizedEndpoint() async throws {
        let transport = QueueAccountTransport([
            .init(statusCode: 200, body: Data("{}".utf8))
        ])
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let body = Data(#"{"signedTransaction":"header.payload.signature"}"#.utf8)

        _ = try await client.authorizedResourceData(
            .submitStoreKitTransaction,
            body: body
        )

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.single)
        XCTAssertEqual(request.url?.path, "/v1/storekit/transactions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-old"
        )
    }

    func testStoreKitHistoryUsesAuthenticatedBoundedCursorRequest() async throws {
        let transport = QueueAccountTransport([
            .init(statusCode: 200, body: Data(#"{"items":[],"nextCursor":null}"#.utf8))
        ])
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        _ = try await client.authorizedResourceData(
            .storeKitTransactions(limit: 500, cursor: "page_1-token")
        )

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.single)
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        XCTAssertEqual(request.url?.path, "/v1/storekit/transactions")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(query, ["limit": "100", "cursor": "page_1-token"])
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-old"
        )
    }

    func testCreditBalanceRequestBypassesLocalURLCache() async throws {
        let transport = QueueAccountTransport([
            .init(statusCode: 200, body: Data("{}".utf8))
        ])
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        _ = try await client.authorizedResourceData(.creditsBalance)

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.single)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cache-Control"),
            "no-cache"
        )
    }

    func testTransientCreditBalanceFailureRetriesOnce() async throws {
        let transport = QueueAccountTransport([
            .init(
                statusCode: 503,
                body: apiErrorData(
                    code: "external_service_unavailable",
                    message: "temporarily unavailable"
                )
            ),
            .init(statusCode: 200, body: Data(#"{"balance":500}"#.utf8))
        ])
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        let data = try await client.authorizedResourceData(.creditsBalance)

        XCTAssertEqual(data, Data(#"{"balance":500}"#.utf8))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/v1/credits/balance" })
    }

    func testTransientAccountFailureRetriesOnce() async throws {
        let accountID = UUID()
        let transport = QueueAccountTransport([
            .init(
                statusCode: 503,
                body: apiErrorData(
                    code: "external_service_unavailable",
                    message: "temporarily unavailable"
                )
            ),
            .init(
                statusCode: 200,
                body: Data(
                    """
                    {"data":{"id":"\(accountID.uuidString)","createdAtEpochSeconds":1}}
                    """.utf8
                )
            )
        ])
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )

        let account = try await client.account()

        XCTAssertEqual(account.id, accountID)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/v1/account" })
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
