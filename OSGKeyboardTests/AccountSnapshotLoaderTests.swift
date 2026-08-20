// AccountSnapshotLoaderTests.swift
// OSGKeyboardTests
//
// Resilient account aggregation keeps cached optional data when a secondary
// endpoint is temporarily unavailable.

@testable import OSGKeyboard
@testable import OSGKeyboardHostSupport
import XCTest

final class AccountSnapshotLoaderTests: XCTestCase {
    @MainActor
    func testOptionalReferralFailuresUseCachedAccountData() async throws {
        let account = OSGKeyboard.AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let cachedReferral = AccountReferral(
            id: UUID(),
            status: .rewarded,
            createdAtEpochSeconds: 1_700_000_100,
            rewardCredits: 1_000
        )
        let cached = AccountCenterSnapshot(
            account: account,
            credits: AccountCreditSummary(balance: 1_000, usedCredits: 0),
            referralProfile: AccountReferralProfile(
                code: "CachedCode_1234567890",
                boundCode: nil,
                inviterRewardCredits: 1_000,
                inviteeRewardCredits: 1_000
            ),
            referrals: [cachedReferral]
        )
        let transport = AccountCenterRoutingTransport(accountID: account.accountID)
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: InMemoryAccountSecurityStore(
                session: makeAccountSession()
            )
        )
        let loader = AccountCenterSnapshotLoader(apiClient: client)

        let refreshed = try await loader.load(cachedSnapshot: cached)

        XCTAssertEqual(
            refreshed.credits,
            AccountCreditSummary(balance: 750, usedCredits: 250)
        )
        XCTAssertEqual(refreshed.referralProfile, cached.referralProfile)
        XCTAssertEqual(refreshed.referrals, cached.referrals)
        let requests = await transport.requests
        XCTAssertEqual(
            requests.count { $0.url?.path == "/v1/referrals/me" },
            2
        )
        XCTAssertEqual(
            requests.count { $0.url?.path == "/v1/referrals" },
            2
        )
    }
}

private actor AccountCenterRoutingTransport: AccountHTTPTransport {
    let accountID: UUID
    private(set) var requests: [URLRequest] = []

    init(accountID: UUID) {
        self.accountID = accountID
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response: QueueAccountTransport.Stub
        switch request.url?.path {
        case "/v1/account":
            response = .init(
                statusCode: 200,
                body: Data(
                    """
                    {"data":{"id":"\(accountID.uuidString)","createdAtEpochSeconds":1700000000}}
                    """.utf8
                )
            )
        case "/v1/credits/balance":
            response = .init(
                statusCode: 200,
                body: Data(#"{"balance":750,"lifetimeUsed":250}"#.utf8)
            )
        case "/v1/referrals/me", "/v1/referrals":
            response = .init(
                statusCode: 503,
                body: apiErrorData(
                    code: "external_service_unavailable",
                    message: "temporarily unavailable"
                )
            )
        case "/v1/referrals/campaigns":
            response = .init(statusCode: 200, body: Data("[]".utf8))
        default:
            throw AccountAPIError.transport
        }
        return (
            response.body,
            makeHTTPResponse(request: request, statusCode: response.statusCode)
        )
    }
}
