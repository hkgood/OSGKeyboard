// AccountCenterViewModelTests.swift
// OSGKeyboardTests
//
// Pure invitation parsing and account coordinator state-machine coverage.

import AuthenticationServices
@testable import OSGKeyboard
@testable import OSGKeyboardHostSupport
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

    func testPastedInputAcceptsCodeLinkAndChatMessage() {
        let inputs = [
            validCode,
            "  \(validCode)\n",
            "https://osglab.com/i/\(validCode)",
            "https://osglab.com/i/\(validCode)?source=poster",
            "快来试试 OSGKeyboard：https://osglab.com/i/\(validCode)",
            "邀请你加入https://osglab.com/i/\(validCode)，一起领积分",
            "Join me: <https://osglab.com/i/\(validCode)>"
        ]

        for input in inputs {
            XCTAssertEqual(
                ReferralUniversalLink.code(fromUserInput: input),
                validCode,
                "Failed to extract from \(input)"
            )
        }
    }

    func testPastedInputRejectsForeignLinksAndPlainText() {
        let inputs = [
            "",
            "hello",
            "https://example.com/i/\(validCode)",
            "http://osglab.com/i/\(validCode)",
            "https://osglab.com/i/short",
            String(validCode.dropLast())
        ]

        for input in inputs {
            XCTAssertNil(
                ReferralUniversalLink.code(fromUserInput: input),
                "Unexpectedly accepted \(input)"
            )
        }
    }

    func testTypedInputAcceptsShortCodeInAnyCaseWithOrWithoutHyphen() {
        let inputs = [
            "K7M2Q9XA",
            "k7m2-q9xa",
            "  K7M2-Q9XA \n",
            "邀请码K7M2-Q9XA",
            "我的邀请码：K7M2-Q9XA，快来"
        ]

        for input in inputs {
            XCTAssertEqual(
                ReferralUniversalLink.code(fromUserInput: input),
                "K7M2Q9XA",
                "Failed to extract from \(input)"
            )
        }
    }

    func testTypedInputRejectsAmbiguousOrMalformedShortCodes() {
        let inputs = [
            "K7M2Q9X",
            "K7M2Q9XAB",
            "K7M-2Q9XA",
            "K0M2Q9XA",
            "KOM2Q9XA",
            "K1M2Q9XA",
            "KLM2Q9XA"
        ]

        for input in inputs {
            XCTAssertNil(
                ReferralUniversalLink.code(fromUserInput: input),
                "Unexpectedly accepted \(input)"
            )
        }
    }

    func testInvitationLinkWinsOverShortCodeLikeWordsInTheSameMessage() {
        // "HEXAGRAM" uses only short-code characters.
        let input = "HEXAGRAM https://osglab.com/i/\(validCode)"

        XCTAssertEqual(ReferralUniversalLink.code(fromUserInput: input), validCode)
    }

    func testShortCodeDisplayAddsHyphen() {
        XCTAssertEqual(ReferralShortCode.display("K7M2Q9XA"), "K7M2-Q9XA")
        XCTAssertEqual(ReferralShortCode.display("bogus"), "bogus")
    }

    @MainActor
    func testPendingStoreKeepsShortCodesForRedemptionAfterSignIn() throws {
        let suiteName = "PendingReferralShortCode.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPendingReferralCodeStore(defaults: defaults)

        store.save("K7M2Q9XA")

        XCTAssertEqual(store.code, "K7M2Q9XA")
    }

    func testBindingWindowFollowsServerDeadlineWhenPresent() throws {
        let account = AccountSession(accountID: UUID(), createdAtEpochSeconds: 1_700_000_000)
        let deadline = Date(timeIntervalSince1970: 1_700_003_600)
        let profile = ReferralProfile(
            code: try makeReferralCode(),
            binding: nil,
            bindingDeadline: deadline
        )

        XCTAssertTrue(ReferralBindingWindow.isOpen(for: account, profile: profile, now: deadline))
        XCTAssertFalse(ReferralBindingWindow.isOpen(
            for: account,
            profile: profile,
            now: deadline.addingTimeInterval(1)
        ))
    }

    func testBindingWindowFallsBackToSevenDaysWithoutServerDeadline() throws {
        let account = AccountSession(accountID: UUID(), createdAtEpochSeconds: 1_700_000_000)
        let profile = ReferralProfile(code: try makeReferralCode(), binding: nil)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(ReferralBindingWindow.isOpen(
            for: account,
            profile: profile,
            now: start.addingTimeInterval(6 * 24 * 60 * 60)
        ))
    }

    func testBindingWindowClosesOnceBound() throws {
        let account = AccountSession(accountID: UUID(), createdAtEpochSeconds: 1_700_000_000)
        let binding = try JSONDecoder().decode(
            ReferralBinding.self,
            from: Data(#"{"inviterUserId":"x"}"#.utf8)
        )
        let profile = ReferralProfile(
            code: try makeReferralCode(),
            binding: binding,
            bindingDeadline: .distantFuture
        )

        XCTAssertFalse(ReferralBindingWindow.isOpen(
            for: account,
            profile: profile,
            now: Date(timeIntervalSince1970: 1_700_000_001)
        ))
    }

    private func makeReferralCode() throws -> ReferralCode {
        ReferralCode(
            code: validCode,
            inviteURL: try XCTUnwrap(URL(string: "https://osglab.com/i/\(validCode)")),
            campaignID: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            shortCode: "K7M2Q9XA"
        )
    }

    func testBindingWindowClosesSevenDaysAfterRegistration() {
        let registeredAt: Int64 = 1_700_000_000
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: registeredAt
        )
        let start = Date(timeIntervalSince1970: TimeInterval(registeredAt))

        XCTAssertTrue(ReferralBindingWindow.isOpen(
            for: account,
            now: start.addingTimeInterval(6 * 24 * 60 * 60)
        ))
        XCTAssertFalse(ReferralBindingWindow.isOpen(
            for: account,
            now: start.addingTimeInterval(7 * 24 * 60 * 60)
        ))
        XCTAssertFalse(ReferralBindingWindow.isOpen(
            for: AccountSession(accountID: UUID(), createdAtEpochSeconds: 0),
            now: start
        ))
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
        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
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
    func testTransientRestoreFailureCanRetryWithoutSigningOut() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            restoreFailureCount: 1
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )

        await coordinator.restoreIfNeeded()

        XCTAssertEqual(coordinator.sessionPhase, .restoring)
        XCTAssertEqual(coordinator.operationErrorKey, "account.error.restore")
        let firstClearCount = await service.managedGatewayClearCount()
        XCTAssertEqual(firstClearCount, 0)

        await coordinator.restoreIfNeeded()

        XCTAssertEqual(coordinator.sessionPhase, .signedIn(account))
        XCTAssertNil(coordinator.operationErrorKey)
        let restoreCount = await service.restoreCount()
        XCTAssertEqual(restoreCount, 2)
    }

    @MainActor
    func testSignInOperationRemainsVisibleUntilAuthenticationCompletes() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: nil,
            signInSession: account,
            snapshot: makeSnapshot(account: account),
            signInDelayNanoseconds: 20_000_000
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()

        let signIn = Task {
            await coordinator.signIn(
                with: AppleAuthorizationPayload(
                    identityToken: "identity",
                    authorizationCode: "authorization",
                    nonce: "nonce",
                    userIdentifier: "apple-user"
                )
            )
        }
        while coordinator.operation != .signingIn {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.operation, .signingIn)
        XCTAssertEqual(coordinator.sessionPhase, .signedOut)

        await signIn.value

        XCTAssertNil(coordinator.operation)
        XCTAssertEqual(coordinator.sessionPhase, .signedIn(account))
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
    func testForcedRefreshQueuedDuringInFlightRefreshRunsAfterward() async {
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

        let staleRefresh = Task { await coordinator.refreshAccountData() }
        while !coordinator.isRefreshingAccountData {
            await Task.yield()
        }
        await coordinator.refreshAccountData(force: true)
        await staleRefresh.value

        let loadCount = await service.loadCount()
        XCTAssertEqual(loadCount, 3)
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
    func testPermanentRedemptionRejectionsDropTheStoredCode() async {
        let cases: [(AccountAPIError, String)] = [
            (
                .server(statusCode: 404, code: "http_error", message: "Referral code does not exist"),
                "account.referral.redeem.error.invalid"
            ),
            (
                .server(statusCode: 422, code: "http_error", message: "Referral binding window has expired"),
                "account.referral.redeem.error.expired"
            ),
            (
                .server(statusCode: 409, code: "http_error", message: "Self-referral is not allowed"),
                "account.referral.redeem.error.self"
            ),
            (
                .server(
                    statusCode: 409,
                    code: "http_error",
                    message: "This account is already bound to another inviter"
                ),
                "account.referral.redeem.error.alreadyBound"
            ),
            (
                .conflict("This account is not eligible for referral rewards"),
                "account.referral.redeem.error.ineligible"
            )
        ]

        for (error, expectedKey) in cases {
            let account = AccountSession(
                accountID: UUID(),
                createdAtEpochSeconds: 1_700_000_000
            )
            let service = AccountServiceSpy(
                restoredSession: account,
                snapshot: makeSnapshot(account: account),
                redemptionError: error
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

            XCTAssertNil(store.code, "Kept code after \(error)")
            XCTAssertNil(coordinator.pendingReferralCode)
            XCTAssertEqual(coordinator.operationErrorKey, expectedKey)
        }
    }

    @MainActor
    func testPastedInvitationWhileSignedOutIsSavedForSignIn() async {
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

        let invalid = await coordinator.submitReferralInput("not an invitation")
        let saved = await coordinator.submitReferralInput(
            "Join me https://osglab.com/i/\(validCode)"
        )

        XCTAssertEqual(invalid, .invalidInput)
        XCTAssertEqual(saved, .savedForSignIn)
        XCTAssertEqual(store.code, validCode)
        XCTAssertEqual(coordinator.pendingReferralCode, validCode)
        XCTAssertFalse(coordinator.consumeAccountCenterPresentation())
        let redeemedCodes = await service.redeemedCodes()
        XCTAssertEqual(redeemedCodes, [])
    }

    @MainActor
    func testPastedInvitationWhileSignedInRedeemsImmediately() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account)
        )
        let store = InMemoryPendingReferralStore()
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: store
        )
        await coordinator.restoreIfNeeded()

        let outcome = await coordinator.submitReferralInput(validCode)

        XCTAssertEqual(outcome, .redeemed)
        XCTAssertNil(store.code)
        XCTAssertNil(coordinator.pendingReferralCode)
        XCTAssertNil(coordinator.operationErrorKey)
        let redeemedCodes = await service.redeemedCodes()
        XCTAssertEqual(redeemedCodes, [validCode])
    }

    @MainActor
    func testPastedInvitationRejectionIsReturnedInsteadOfAlerting() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            redemptionError: .server(
                statusCode: 422,
                code: "http_error",
                message: "Referral binding window has expired"
            )
        )
        let store = InMemoryPendingReferralStore()
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: store
        )
        await coordinator.restoreIfNeeded()

        let outcome = await coordinator.submitReferralInput(validCode)

        XCTAssertEqual(outcome, .failed(messageKey: "account.referral.redeem.error.expired"))
        XCTAssertNil(store.code)
        XCTAssertNil(coordinator.operationErrorKey)
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
                nonce: "nonce",
                userIdentifier: "apple-user"
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

    @MainActor
    func testRevokedAppleCredentialClearsSignedInAccountState() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            appleCredentialState: .revoked
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()
        XCTAssertTrue(coordinator.isSignedIn)

        await coordinator.validateAppleCredentialState()

        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
        XCTAssertEqual(coordinator.snapshotPhase, .idle)
        XCTAssertEqual(coordinator.operationErrorKey, "account.error.sessionExpired")
        let signOutCount = await service.signOutCount()
        XCTAssertEqual(signOutCount, 1)
    }

    @MainActor
    func testMissingAppleIdentifierRequiresOneTimeReauthentication() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            appleCredentialState: .reauthenticationRequired
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()

        await coordinator.validateAppleCredentialState()

        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
        XCTAssertEqual(
            coordinator.operationErrorKey,
            "account.error.appleReauthenticationRequired"
        )
    }

    @MainActor
    func testRevocationSignOutFailureKeepsSessionForRetry() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            shouldFailSignOut: true,
            appleCredentialState: .revoked
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()

        await coordinator.validateAppleCredentialState()

        XCTAssertEqual(coordinator.sessionPhase, .signedIn(account))
        XCTAssertEqual(coordinator.operationErrorKey, "account.error.signOut")
    }

    @MainActor
    func testCredentialRevocationNotificationClearsSignedInState() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000
        )
        let center = NotificationCenter()
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
            notificationCenter: center
        )
        await coordinator.restoreIfNeeded()

        center.post(
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        for _ in 0..<100 where coordinator.isSignedIn {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
        XCTAssertEqual(coordinator.operationErrorKey, "account.error.sessionExpired")
    }

    @MainActor
    func testRevocationPreventsInFlightProfileUpdateFromRestoringSession() async {
        let account = AccountSession(
            accountID: UUID(),
            createdAtEpochSeconds: 1_700_000_000,
            displayName: "Before"
        )
        let service = AccountServiceSpy(
            restoredSession: account,
            snapshot: makeSnapshot(account: account),
            profileUpdateDelayNanoseconds: 20_000_000,
            appleCredentialState: .revoked
        )
        let coordinator = AccountSessionCoordinator(
            dependencies: AccountDependencies(
                sessionService: service,
                centerService: service
            ),
            pendingReferralStore: InMemoryPendingReferralStore()
        )
        await coordinator.restoreIfNeeded()

        let update = Task { await coordinator.updateDisplayName("After") }
        while coordinator.operation != .updatingProfile {
            await Task.yield()
        }
        await coordinator.validateAppleCredentialState()
        let didUpdate = await update.value

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(coordinator.sessionPhase, .signedOut)
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
    private let signedInAccount: AccountSession?
    private let centerSnapshot: AccountCenterSnapshot?
    private let refreshedSnapshot: AccountCenterSnapshot?
    private let shouldFailRedemption: Bool
    private let redemptionError: AccountAPIError?
    private let shouldFailAccountRefresh: Bool
    private let shouldFailSignOut: Bool
    private let signOutDelayNanoseconds: UInt64
    private let signInDelayNanoseconds: UInt64
    private let accountLoadDelayNanoseconds: UInt64
    private let profileUpdateDelayNanoseconds: UInt64
    private var remainingRestoreFailures: Int
    private let storedAppleCredentialState: AccountAppleCredentialState
    private var redeemed: [String] = []
    private var centerLoadCount = 0
    private var logoutCount = 0
    private var accountDeleteCount = 0
    private var sessionRestoreCount = 0
    private var gatewayClearCount = 0
    private var receivedCachedSnapshot: AccountCenterSnapshot?

    init(
        restoredSession: AccountSession?,
        signInSession: AccountSession? = nil,
        snapshot: AccountCenterSnapshot? = nil,
        refreshedSnapshot: AccountCenterSnapshot? = nil,
        shouldFailRedemption: Bool = false,
        redemptionError: AccountAPIError? = nil,
        shouldFailAccountRefresh: Bool = false,
        shouldFailSignOut: Bool = false,
        signOutDelayNanoseconds: UInt64 = 0,
        signInDelayNanoseconds: UInt64 = 0,
        restoreFailureCount: Int = 0,
        accountLoadDelayNanoseconds: UInt64 = 0,
        profileUpdateDelayNanoseconds: UInt64 = 0,
        appleCredentialState: AccountAppleCredentialState = .unknown
    ) {
        restored = restoredSession
        signedInAccount = signInSession ?? restoredSession
        centerSnapshot = snapshot
        self.refreshedSnapshot = refreshedSnapshot
        self.shouldFailRedemption = shouldFailRedemption
        self.redemptionError = redemptionError
        self.shouldFailAccountRefresh = shouldFailAccountRefresh
        self.shouldFailSignOut = shouldFailSignOut
        self.signOutDelayNanoseconds = signOutDelayNanoseconds
        self.signInDelayNanoseconds = signInDelayNanoseconds
        remainingRestoreFailures = restoreFailureCount
        self.accountLoadDelayNanoseconds = accountLoadDelayNanoseconds
        self.profileUpdateDelayNanoseconds = profileUpdateDelayNanoseconds
        self.storedAppleCredentialState = appleCredentialState
    }

    func restoreSession() async throws -> AccountSession? {
        sessionRestoreCount += 1
        if remainingRestoreFailures > 0 {
            remainingRestoreFailures -= 1
            throw AccountServiceSpyError.failed
        }
        return restored
    }

    func signIn(with payload: AppleAuthorizationPayload) async throws -> AccountSession {
        if signInDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: signInDelayNanoseconds)
        }
        guard let signedInAccount else { throw AccountIntegrationError.unavailable }
        return signedInAccount
    }

    func signOut() async throws {
        if signOutDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: signOutDelayNanoseconds)
        }
        logoutCount += 1
        if shouldFailSignOut {
            throw AccountServiceSpyError.failed
        }
    }

    func deleteAccount(with payload: AppleAuthorizationPayload) async throws {
        accountDeleteCount += 1
    }

    func appleCredentialState() async -> AccountAppleCredentialState {
        storedAppleCredentialState
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

    func updateDisplayName(_ displayName: String) async throws -> AccountSession {
        if profileUpdateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: profileUpdateDelayNanoseconds)
        }
        guard let signedInAccount else {
            throw AccountIntegrationError.unavailable
        }
        return AccountSession(
            accountID: signedInAccount.accountID,
            createdAtEpochSeconds: signedInAccount.createdAtEpochSeconds,
            displayName: displayName
        )
    }

    func redeemReferral(code: String) async throws {
        if shouldFailRedemption {
            throw AccountServiceSpyError.failed
        }
        if let redemptionError {
            throw redemptionError
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
