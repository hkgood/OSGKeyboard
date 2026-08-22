// AccountCenterViewModelTests.swift
// OSGKeyboardTests
//
// Pure invitation parsing and account coordinator state-machine coverage.

@testable import OSGKeyboard
import XCTest

final class AccountCenterViewModelTests: XCTestCase {
    private let validCode = "Abcdefghij_1234567890-"

    func testUniversalLinkAcceptsCanonicalInvitation() {
        let url = URL(string: "https://osglab.com/i/\(validCode)?source=share")!

        XCTAssertEqual(ReferralUniversalLink.code(from: url), validCode)
    }

    func testUniversalLinkRejectsUntrustedOrMalformedURLs() {
        let invalidURLs = [
            "http://osglab.com/i/\(validCode)",
            "https://example.com/i/\(validCode)",
            "https://osglab.com/invite/\(validCode)",
            "https://osglab.com/i/\(validCode)/extra",
            "https://osglab.com/i/short",
            "https://osglab.com/i/Abcdefghij%2F1234567890-"
        ]

        for rawURL in invalidURLs {
            XCTAssertNil(
                ReferralUniversalLink.code(from: URL(string: rawURL)!),
                "Unexpectedly accepted \(rawURL)"
            )
        }
    }

    func testReferralSummaryCountsEveryServerStatus() {
        let referrals = [
            makeReferral(status: .pending),
            makeReferral(status: .pending),
            makeReferral(status: .rewarded),
            makeReferral(status: .ineligible)
        ]

        XCTAssertEqual(
            AccountReferralSummary(referrals: referrals),
            AccountReferralSummary(pending: 2, rewarded: 1, ineligible: 1)
        )
    }

    @MainActor
    func testSignedOutInvitationIsPersistedWithoutRedeeming() async {
        let service = AccountServiceSpy(restoredSession: nil)
        let store = InMemoryPendingReferralStore()
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: store
        )

        await coordinator.restoreIfNeeded()
        let handled = coordinator.handleIncomingURL(
            URL(string: "https://osglab.com/i/\(validCode)")!
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(store.code, validCode)
        XCTAssertEqual(coordinator.pendingReferralCode, validCode)
        XCTAssertTrue(coordinator.consumeAccountCenterPresentation())
        XCTAssertFalse(coordinator.consumeAccountCenterPresentation())
        let redeemedCodes = await service.redeemedCodes()
        XCTAssertEqual(redeemedCodes, [])
    }

    @MainActor
    func testRestoredSessionRedeemsPendingCodeThenLoadsSnapshot() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let snapshot = makeSnapshot(account: account)
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: snapshot
        )
        let store = InMemoryPendingReferralStore(code: validCode)
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: store
        )

        await coordinator.restoreIfNeeded()

        XCTAssertEqual(coordinator.sessionPhase, .signedIn(account))
        XCTAssertEqual(coordinator.snapshotPhase, .loaded(snapshot))
        XCTAssertNil(store.code)
        XCTAssertNil(coordinator.pendingReferralCode)
        let redeemedCodes = await service.redeemedCodes()
        let loadCount = await service.loadCount()
        XCTAssertEqual(redeemedCodes, [validCode])
        XCTAssertEqual(loadCount, 1)
    }

    @MainActor
    func testRestoreReplayCallsServiceOnlyOnce() async {
        let service = AccountServiceSpy(restoredSession: nil)
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )

        await coordinator.restoreIfNeeded()
        await coordinator.restoreIfNeeded()

        let restoreCount = await service.restoreCount()
        XCTAssertEqual(restoreCount, 1)
    }

    @MainActor
    func testFreshAccountSnapshotDoesNotReloadWhenEnteringAccountPages() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let clock = MutableAccountClock(now: Date(timeIntervalSince1970: 1_000))
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account)
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore(),
            now: { clock.now }
        )
        await coordinator.restoreIfNeeded()

        await coordinator.refreshAccountData()
        await coordinator.refreshAccountData()

        let loadCount = await service.loadCount()
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(coordinator.lastAccountRefreshAt, clock.now)
    }

    @MainActor
    func testStaleAccountSnapshotReloadsForEveryPage() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let original = makeSnapshot(account: account)
        let latestCredits = AccountCreditSummary(balance: 750, usedCredits: 250)
        let latest = AccountCenterSnapshot(
            account: account,
            credits: latestCredits,
            referrals: [
                AccountReferral(
                    id: UUID(),
                    status: .rewarded,
                    createdAtEpochSeconds: 1_700_000_100,
                    rewardCredits: 1_000
                )
            ]
        )
        let clock = MutableAccountClock(now: Date(timeIntervalSince1970: 1_000))
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: original,
            refreshedSnapshot: latest
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore(),
            now: { clock.now }
        )
        await coordinator.restoreIfNeeded()
        clock.now = clock.now.addingTimeInterval(601)

        await coordinator.refreshAccountData()

        XCTAssertEqual(coordinator.snapshotPhase, .loaded(latest))
        XCTAssertEqual(coordinator.lastAccountRefreshAt, clock.now)
        let loadCount = await service.loadCount()
        let receivedCachedSnapshot = await service.lastReceivedCachedSnapshot()
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(receivedCachedSnapshot, original)
    }

    @MainActor
    func testForcedRefreshBypassesFreshnessWindow() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let original = makeSnapshot(account: account)
        let latest = AccountCenterSnapshot(
            account: account,
            credits: AccountCreditSummary(balance: 500, usedCredits: 500),
            referrals: original.referrals
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: original,
            refreshedSnapshot: latest
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()

        await coordinator.refreshAccountData(force: true)

        XCTAssertEqual(coordinator.snapshotPhase, .loaded(latest))
        let loadCount = await service.loadCount()
        XCTAssertEqual(loadCount, 2)
    }

    @MainActor
    func testConcurrentStaleAccountChecksShareOneRequest() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let clock = MutableAccountClock(now: Date(timeIntervalSince1970: 1_000))
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            accountLoadDelayNanoseconds: 20_000_000
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore(),
            now: { clock.now }
        )
        await coordinator.restoreIfNeeded()
        clock.now = clock.now.addingTimeInterval(601)

        async let first: Void = coordinator.refreshAccountData()
        async let second: Void = coordinator.refreshAccountData()
        _ = await (first, second)

        let loadCount = await service.loadCount()
        XCTAssertEqual(loadCount, 2)
    }

    @MainActor
    func testFailedAccountRefreshKeepsLastSuccessfulSnapshotAndTime() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let snapshot = makeSnapshot(account: account)
        let initialRefreshAt = Date(timeIntervalSince1970: 1_000)
        let clock = MutableAccountClock(now: initialRefreshAt)
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: snapshot,
            shouldFailAccountRefresh: true
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore(),
            now: { clock.now }
        )
        await coordinator.restoreIfNeeded()
        clock.now = clock.now.addingTimeInterval(601)

        await coordinator.refreshAccountData()

        XCTAssertEqual(coordinator.snapshotPhase, .loaded(snapshot))
        XCTAssertEqual(coordinator.lastAccountRefreshAt, initialRefreshAt)
        XCTAssertEqual(
            coordinator.accountRefreshErrorKey,
            "account.error.load"
        )
    }

    @MainActor
    func testFailedRedemptionKeepsCodeForRetry() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            shouldFailRedemption: true
        )
        let store = InMemoryPendingReferralStore(code: validCode)
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: store
        )

        await coordinator.restoreIfNeeded()

        XCTAssertEqual(store.code, validCode)
        XCTAssertEqual(coordinator.pendingReferralCode, validCode)
        XCTAssertEqual(coordinator.operationErrorKey, "account.error.redeemReferral")
    }

    @MainActor
    func testSignOutClearsRemoteAccountStateOnly() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            shouldFailRedemption: true
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()

        await coordinator.signOut()

        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
        XCTAssertEqual(coordinator.snapshotPhase, .idle)
        let signOutCount = await service.signOutCount()
        XCTAssertEqual(signOutCount, 1)
    }

    @MainActor
    func testConcurrentSignOutRequestsCollapseToOneMutation() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            signOutDelayNanoseconds: 20_000_000
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()

        let first = Task { await coordinator.signOut() }
        while coordinator.operation != .signingOut {
            await Task.yield()
        }
        let second = Task { await coordinator.signOut() }
        await first.value
        await second.value

        let signOutCount = await service.signOutCount()
        XCTAssertEqual(signOutCount, 1)
    }

    @MainActor
    func testSuccessfulDeletionClearsAccountSnapshotAndPendingReferral() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000,
            displayName: "Rocky"
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account)
        )
        let pending = InMemoryPendingReferralStore(code: "ValidInvite_1234567890")
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: pending
        )
        await coordinator.restoreIfNeeded()

        await coordinator.deleteAccount(
            with: AppleAuthorizationPayload(
                identityToken: "identity",
                authorizationCode: "authorization",
                nonce: "nonce"
            )
        )

        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
        XCTAssertEqual(coordinator.snapshotPhase, .idle)
        XCTAssertNil(coordinator.pendingReferralCode)
        XCTAssertNil(pending.code)
        let deleteCount = await service.deleteCount()
        XCTAssertEqual(deleteCount, 1)
    }

    @MainActor
    func testExpiredSessionEventClearsSignedInAccountState() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account)
        )
        let eventSource = AccountSessionEventSourceStub()
        var signedOutCallbackCount = 0
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                sessionEventSource: eventSource,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore(),
            onAccountSignedOut: {
                signedOutCallbackCount += 1
            }
        )
        await coordinator.restoreIfNeeded()
        XCTAssertTrue(coordinator.isSignedIn)

        eventSource.expire()
        for _ in 0..<100 where coordinator.isSignedIn {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
        XCTAssertEqual(coordinator.snapshotPhase, .idle)
        XCTAssertEqual(coordinator.operationErrorKey, "account.error.sessionExpired")
        XCTAssertEqual(coordinator.creditPurchases.catalogPhase, .idle)
        XCTAssertEqual(signedOutCallbackCount, 1)
        let managedGatewayClearCount = await service.managedGatewayClearCount()
        XCTAssertEqual(managedGatewayClearCount, 1)
    }

    private func makeReferral(status: AccountReferralStatus) -> AccountReferral {
        AccountReferral(
            id: UUID(),
            status: status,
            createdAtEpochSeconds: nil,
            rewardCredits: nil
        )
    }

    private func makeSnapshot(account: AccountSession) -> AccountCenterSnapshot {
        AccountCenterSnapshot(
            account: account,
            credits: AccountCreditSummary(
                balance: 9_223_372_036_854_775_000,
                usedCredits: 1_234
            ),
            referrals: []
        )
    }
}

@MainActor
private final class InMemoryPendingReferralStore: PendingReferralCodeStoring {
    private(set) var code: String?

    init(code: String? = nil) {
        self.code = code
    }

    func save(_ code: String) {
        self.code = code
    }

    func clear() {
        code = nil
    }
}

@MainActor
private final class MutableAccountClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class AccountSessionEventSourceStub: AccountSessionEventSourcing {
    private let stream: AsyncStream<AccountSessionEvent>
    private let continuation: AsyncStream<AccountSessionEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func events() async -> AsyncStream<AccountSessionEvent> {
        stream
    }

    func expire() {
        continuation.yield(.expired)
    }
}

private actor AccountServiceSpy: AccountSessionServicing, AccountCenterServicing {
    private let restored: AccountSession?
    private let centerSnapshot: AccountCenterSnapshot?
    private let refreshedSnapshot: AccountCenterSnapshot?
    private let shouldFailRedemption: Bool
    private let shouldFailAccountRefresh: Bool
    private let signOutDelayNanoseconds: UInt64
    private let accountLoadDelayNanoseconds: UInt64
    private var redeemed: [String] = []
    private var centerLoadCount = 0
    private var logoutCount = 0
    private var accountDeleteCount = 0
    private var sessionRestoreCount = 0
    private var gatewayClearCount = 0
    private var receivedCachedSnapshot: AccountCenterSnapshot?

    init(
        restoredSession: AccountSession?,
        snapshot: AccountCenterSnapshot? = nil,
        refreshedSnapshot: AccountCenterSnapshot? = nil,
        shouldFailRedemption: Bool = false,
        shouldFailAccountRefresh: Bool = false,
        signOutDelayNanoseconds: UInt64 = 0,
        accountLoadDelayNanoseconds: UInt64 = 0
    ) {
        restored = restoredSession
        centerSnapshot = snapshot
        self.refreshedSnapshot = refreshedSnapshot
        self.shouldFailRedemption = shouldFailRedemption
        self.shouldFailAccountRefresh = shouldFailAccountRefresh
        self.signOutDelayNanoseconds = signOutDelayNanoseconds
        self.accountLoadDelayNanoseconds = accountLoadDelayNanoseconds
    }

    func restoreSession() async throws -> AccountSession? {
        sessionRestoreCount += 1
        return restored
    }

    func signIn(with payload: AppleAuthorizationPayload) async throws -> AccountSession {
        guard let restored else { throw AccountIntegrationError.unavailable }
        return restored
    }

    func signOut() async throws {
        if signOutDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: signOutDelayNanoseconds)
        }
        logoutCount += 1
    }

    func deleteAccount(with payload: AppleAuthorizationPayload) async throws {
        accountDeleteCount += 1
    }

    func clearManagedGateway() async {
        gatewayClearCount += 1
    }

    func loadAccountCenter() async throws -> AccountCenterSnapshot {
        try await loadAccountCenter(cachedSnapshot: nil)
    }

    func loadAccountCenter(
        cachedSnapshot: AccountCenterSnapshot?
    ) async throws -> AccountCenterSnapshot {
        receivedCachedSnapshot = cachedSnapshot
        centerLoadCount += 1
        if centerLoadCount > 1, accountLoadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: accountLoadDelayNanoseconds)
        }
        if centerLoadCount > 1, shouldFailAccountRefresh {
            throw AccountServiceSpyError.failed
        }
        if centerLoadCount > 1, let refreshedSnapshot {
            return refreshedSnapshot
        }
        guard let centerSnapshot else { throw AccountIntegrationError.unavailable }
        return centerSnapshot
    }

    func redeemReferral(code: String) async throws {
        if shouldFailRedemption {
            throw AccountServiceSpyError.failed
        }
        redeemed.append(code)
    }

    func redeemedCodes() -> [String] {
        redeemed
    }

    func loadCount() -> Int {
        centerLoadCount
    }

    func lastReceivedCachedSnapshot() -> AccountCenterSnapshot? {
        receivedCachedSnapshot
    }

    func signOutCount() -> Int {
        logoutCount
    }

    func restoreCount() -> Int {
        sessionRestoreCount
    }

    func deleteCount() -> Int {
        accountDeleteCount
    }

    func managedGatewayClearCount() -> Int {
        gatewayClearCount
    }
}

private enum AccountServiceSpyError: Error, Sendable {
    case failed
}
