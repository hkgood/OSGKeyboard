// ReferralProfileTests.swift
// OSGKeyboardTests
//
// Server-owned invitation decoding, transport, cache, and state-machine coverage.

@testable import OSGKeyboard
@testable import OSGKeyboardHostSupport
import XCTest

final class ReferralProfileTests: XCTestCase {
    private let accountA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let accountB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    func testReferralProfileDecodesServerInviteURLAndOptionalBinding() throws {
        let inviteURL = "https://osglab.com/i/Abcdefghij_1234567890-?source=server"
        let data = Data(
            """
            {
              "code": {
                "code": "Abcdefghij_1234567890-",
                "inviteUrl": "\(inviteURL)",
                "campaignId": null,
                "createdAt": "2026-08-20T12:34:56.123Z"
              },
              "binding": {
                "boundAt": "2026-08-20T12:35:00Z",
                "rewardStatus": "PENDING",
                "serverOwnedField": 42
              }
            }
            """.utf8
        )

        let profile = try JSONDecoder().decode(ReferralProfile.self, from: data)

        XCTAssertEqual(profile.code.code, "Abcdefghij_1234567890-")
        XCTAssertEqual(profile.code.inviteURL.absoluteString, inviteURL)
        XCTAssertNil(profile.code.campaignID)
        XCTAssertNotNil(profile.binding)
    }

    func testLiveReferralServiceUsesAuthenticatedGETWithBoundedTimeout() async throws {
        let session = makeAccountSession()
        let body = referralProfileData(inviteSuffix: "?source=transport")
        let transport = QueueAccountTransport([
            .init(statusCode: 200, body: body)
        ])
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: InMemoryAccountSecurityStore(session: session)
        )
        let service = LiveReferralProfileService(apiClient: client)

        let profile = try await service.loadReferralProfile()

        XCTAssertEqual(
            profile.code.inviteURL.absoluteString,
            "https://osglab.com/i/Abcdefghij_1234567890-?source=transport"
        )
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.single)
        XCTAssertEqual(request.url?.path, "/v1/referrals/me")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer \(session.accessToken)"
        )
        XCTAssertFalse(requests.contains { $0.url?.path == "/v1/referrals/code" })
    }

    func testReferralServiceDecodesLegacyStringErrorResponse() async {
        let transport = QueueAccountTransport([
            .init(statusCode: 404, body: Data(#"{"error":"missing"}"#.utf8))
        ])
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: InMemoryAccountSecurityStore(session: makeAccountSession())
        )
        let service = LiveReferralProfileService(apiClient: client)

        do {
            _ = try await service.loadReferralProfile()
            XCTFail("Expected a not-found error.")
        } catch let error as AccountAPIError {
            XCTAssertEqual(
                error,
                .server(statusCode: 404, code: "http_error", message: "missing")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testSuccessfulRefreshAlwaysExitsLoading() async {
        let profile = makeProfile(inviteSuffix: "?version=fresh")
        let service = ReferralProfileServiceSpy(profiles: [profile])
        let viewModel = makeViewModel(service: service)

        viewModel.startSession(accountID: accountA)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded(profile))
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertNil(viewModel.refreshErrorKey)
    }

    @MainActor
    func testFailedRefreshAlwaysExitsLoadingAndShowsRetryState() async {
        let service = ReferralProfileServiceSpy(error: .transport)
        let viewModel = makeViewModel(service: service)

        viewModel.startSession(accountID: accountA)
        await viewModel.refresh()

        XCTAssertEqual(
            viewModel.state,
            .failed(messageKey: "account.referral.error.network")
        )
        XCTAssertFalse(viewModel.isRefreshing)
    }

    @MainActor
    func testManualRetryLoadsProfileAfterInitialFailure() async {
        let profile = makeProfile(inviteSuffix: "?retry=success")
        let service = RetryReferralProfileService(profile: profile)
        let viewModel = ReferralProfileViewModel(
            service: service,
            store: InMemoryReferralProfileStore()
        )

        viewModel.startSession(accountID: accountA)
        await viewModel.refresh()
        XCTAssertEqual(
            viewModel.state,
            .failed(messageKey: "account.referral.error.network")
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded(profile))
        XCTAssertFalse(viewModel.isRefreshing)
    }

    @MainActor
    func testHTTPFailuresMapToFiniteRetryStates() async {
        let cases: [(AccountAPIError, String)] = [
            (
                .server(statusCode: 401, code: "http_error", message: "unauthorized"),
                "account.referral.error.session"
            ),
            (
                .server(statusCode: 404, code: "http_error", message: "missing"),
                "account.referral.error.notFound"
            ),
            (
                .conflict("already bound"),
                "account.referral.error.conflict"
            ),
            (
                .server(statusCode: 503, code: "http_error", message: "unavailable"),
                "account.referral.error.unavailable"
            )
        ]

        for (error, expectedKey) in cases {
            let viewModel = makeViewModel(
                service: ReferralProfileServiceSpy(error: error)
            )
            viewModel.startSession(accountID: accountA)
            await viewModel.refresh()
            XCTAssertEqual(viewModel.state, .failed(messageKey: expectedKey))
            XCTAssertFalse(viewModel.isRefreshing)
        }
    }

    @MainActor
    func testCancellationCannotLeaveViewModelLoading() async {
        let service = ReferralProfileServiceSpy(
            profiles: [makeProfile()],
            delaysNanoseconds: [2_000_000_000]
        )
        let viewModel = makeViewModel(service: service)

        viewModel.startSession(accountID: accountA)
        viewModel.endSession()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertNil(viewModel.refreshErrorKey)
    }

    @MainActor
    func testRepeatedSessionStartSharesOneAutomaticRequest() async {
        let service = ReferralProfileServiceSpy(
            profiles: [makeProfile()],
            delaysNanoseconds: [20_000_000]
        )
        let viewModel = makeViewModel(service: service)

        viewModel.startSession(accountID: accountA)
        viewModel.startSession(accountID: accountA)
        await viewModel.refresh()

        let loadCount = await service.loadCount()
        XCTAssertEqual(loadCount, 1)
    }

    @MainActor
    func testAccountSwitchRejectsStalePreviousAccountResponse() async {
        let profileA = makeProfile(inviteSuffix: "?account=A")
        let profileB = makeProfile(inviteSuffix: "?account=B")
        let service = ReferralProfileServiceSpy(
            profiles: [profileA, profileB],
            delaysNanoseconds: [150_000_000, 0],
            ignoresCancellationAt: [0]
        )
        let store = InMemoryReferralProfileStore()
        let viewModel = ReferralProfileViewModel(service: service, store: store)

        viewModel.startSession(accountID: accountA)
        await waitUntil { await service.loadCount() == 1 }
        viewModel.startSession(accountID: accountB)
        await viewModel.refresh()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(viewModel.state, .loaded(profileB))
        XCTAssertNil(store.profile(for: accountA))
        XCTAssertEqual(store.profile(for: accountB), profileB)
    }

    @MainActor
    func testCachedProfileDisplaysBeforeBackgroundRefresh() async {
        let cached = makeProfile(inviteSuffix: "?version=cached")
        let refreshed = makeProfile(inviteSuffix: "?version=server")
        let store = InMemoryReferralProfileStore(profiles: [accountA: cached])
        let service = ReferralProfileServiceSpy(
            profiles: [refreshed],
            delaysNanoseconds: [50_000_000]
        )
        let viewModel = ReferralProfileViewModel(service: service, store: store)

        viewModel.startSession(accountID: accountA)

        XCTAssertEqual(viewModel.state, .loaded(cached))
        XCTAssertTrue(viewModel.isRefreshing)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.state, .loaded(refreshed))
        XCTAssertEqual(store.profile(for: accountA), refreshed)
    }

    @MainActor
    func testCachedProfileRemainsVisibleWhenBackgroundRefreshFails() async {
        let cached = makeProfile(inviteSuffix: "?version=cached")
        let store = InMemoryReferralProfileStore(profiles: [accountA: cached])
        let service = ReferralProfileServiceSpy(error: .transport)
        let viewModel = ReferralProfileViewModel(service: service, store: store)

        viewModel.startSession(accountID: accountA)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded(cached))
        XCTAssertEqual(viewModel.refreshErrorKey, "account.referral.error.network")
        XCTAssertFalse(viewModel.isRefreshing)
    }

    @MainActor
    func testProfileCacheIsIsolatedByAccountAndSurvivesSessionEnd() async {
        let profileA = makeProfile(inviteSuffix: "?account=A")
        let profileB = makeProfile(inviteSuffix: "?account=B")
        let store = InMemoryReferralProfileStore(
            profiles: [accountA: profileA, accountB: profileB]
        )
        let viewModel = ReferralProfileViewModel(
            service: ReferralProfileServiceSpy(profiles: [profileA]),
            store: store
        )

        viewModel.startSession(accountID: accountA)
        viewModel.endSession()

        XCTAssertEqual(store.profile(for: accountA), profileA)
        XCTAssertEqual(store.profile(for: accountB), profileB)
    }

    @MainActor
    func testSignInStartsReferralLoadWithoutWaitingForIt() async {
        let account = OSGKeyboard.AccountSession(
            accountID: accountA,
            createdAtEpochSeconds: 1_700_000_000
        )
        let accountService = SignInAccountService(account: account)
        let referralService = ReferralProfileServiceSpy(
            profiles: [makeProfile()],
            delaysNanoseconds: [2_000_000_000]
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: accountService,
                centerService: accountService,
                referralService: referralService
            ),
            pendingReferralStore: InMemoryPendingReferralStore(),
            referralProfileStore: InMemoryReferralProfileStore()
        )
        let clock = ContinuousClock()
        let start = clock.now

        await coordinator.signIn(
            with: AppleAuthorizationPayload(
                identityToken: "identity",
                authorizationCode: "authorization",
                nonce: "nonce"
            )
        )

        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
        XCTAssertEqual(
            coordinator.sessionPhase,
            AccountSessionCoordinator.SessionPhase.signedIn(account)
        )
        XCTAssertEqual(
            coordinator.referralProfile.state,
            ReferralProfileViewModel.State.loading
        )
        coordinator.referralProfile.endSession()
    }

    @MainActor
    func testShareSourcePreservesExactServerInviteURL() {
        let profile = makeProfile(inviteSuffix: "?source=server%20owned#invite")

        XCTAssertEqual(
            profile.code.inviteURL.absoluteString,
            "https://osglab.com/i/Abcdefghij_1234567890-?source=server%20owned#invite"
        )
    }

    @MainActor
    private func makeViewModel(
        service: ReferralProfileServiceSpy
    ) -> ReferralProfileViewModel {
        ReferralProfileViewModel(
            service: service,
            store: InMemoryReferralProfileStore()
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping () async -> Bool
    ) async {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Condition was not met before timeout.")
    }

    private func makeProfile(inviteSuffix: String = "") -> ReferralProfile {
        ReferralProfile(
            code: ReferralCode(
                code: "Abcdefghij_1234567890-",
                inviteURL: URL(
                    string: "https://osglab.com/i/Abcdefghij_1234567890-\(inviteSuffix)"
                )!,
                campaignID: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            binding: nil
        )
    }

    private func referralProfileData(inviteSuffix: String = "") -> Data {
        Data(
            """
            {
              "code": {
                "code": "Abcdefghij_1234567890-",
                "inviteUrl": "https://osglab.com/i/Abcdefghij_1234567890-\(inviteSuffix)",
                "campaignId": null,
                "createdAt": "2026-08-20T12:34:56Z"
              },
              "binding": null
            }
            """.utf8
        )
    }
}

private actor ReferralProfileServiceSpy: ReferralProfileServicing {
    private let profiles: [ReferralProfile]
    private let error: AccountAPIError?
    private let delaysNanoseconds: [UInt64]
    private let ignoresCancellationAt: Set<Int>
    private var count = 0

    init(
        profiles: [ReferralProfile] = [],
        error: AccountAPIError? = nil,
        delaysNanoseconds: [UInt64] = [],
        ignoresCancellationAt: Set<Int> = []
    ) {
        self.profiles = profiles
        self.error = error
        self.delaysNanoseconds = delaysNanoseconds
        self.ignoresCancellationAt = ignoresCancellationAt
    }

    func loadReferralProfile() async throws -> ReferralProfile {
        let index = count
        count += 1
        let delay = index < delaysNanoseconds.count ? delaysNanoseconds[index] : 0
        if delay > 0 {
            if ignoresCancellationAt.contains(index) {
                try? await Task.sleep(nanoseconds: delay)
            } else {
                try await Task.sleep(nanoseconds: delay)
            }
        }
        if let error {
            throw error
        }
        guard !profiles.isEmpty else {
            throw AccountIntegrationError.unavailable
        }
        return profiles[min(index, profiles.count - 1)]
    }

    func loadCount() -> Int {
        count
    }
}

private actor RetryReferralProfileService: ReferralProfileServicing {
    private let profile: ReferralProfile
    private var callCount = 0

    init(profile: ReferralProfile) {
        self.profile = profile
    }

    func loadReferralProfile() async throws -> ReferralProfile {
        callCount += 1
        if callCount == 1 {
            throw AccountAPIError.transport
        }
        return profile
    }
}

@MainActor
private final class InMemoryReferralProfileStore: ReferralProfileStoring {
    private var profiles: [UUID: ReferralProfile]

    init(profiles: [UUID: ReferralProfile] = [:]) {
        self.profiles = profiles
    }

    func profile(for accountID: UUID) -> ReferralProfile? {
        profiles[accountID]
    }

    func save(_ profile: ReferralProfile, for accountID: UUID) {
        profiles[accountID] = profile
    }

    func removeProfile(for accountID: UUID) {
        profiles.removeValue(forKey: accountID)
    }
}

@MainActor
private final class InMemoryPendingReferralStore: PendingReferralCodeStoring {
    private(set) var code: String?

    func save(_ code: String) {
        self.code = code
    }

    func clear() {
        code = nil
    }
}

private actor SignInAccountService: AccountSessionServicing, AccountCenterServicing {
    let account: OSGKeyboard.AccountSession

    init(account: OSGKeyboard.AccountSession) {
        self.account = account
    }

    func restoreSession() async throws -> OSGKeyboard.AccountSession? {
        nil
    }

    func signIn(
        with payload: AppleAuthorizationPayload
    ) async throws -> OSGKeyboard.AccountSession {
        account
    }

    func signOut() async throws {}

    func deleteAccount(with payload: AppleAuthorizationPayload) async throws {}

    func loadAccountCenter() async throws -> AccountCenterSnapshot {
        AccountCenterSnapshot(
            account: account,
            credits: AccountCreditSummary(balance: 0, usedCredits: 0),
            referrals: []
        )
    }

    func redeemReferral(code: String) async throws {}
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
