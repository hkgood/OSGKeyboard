// AccountSessionCoordinator.swift
// OSGKeyboard · Main App
//
// Main-actor state machine for optional account features. Local and BYOK
// features never consult this coordinator and remain available when signed out.

import Combine
import Foundation
import OSGKeyboardShared

@MainActor
final class AccountSessionCoordinator: ObservableObject {
    enum SessionPhase: Equatable {
        case restoring
        case signedOut
        case signedIn(AccountSession)
    }

    enum SnapshotPhase: Equatable {
        case idle
        case loading
        case loaded(AccountCenterSnapshot)
        case failed(messageKey: String)
    }

    enum Operation: Equatable {
        case signingIn
        case signingOut
        case redeemingReferral
        case preparingManagedGateway
        case updatingProfile
        case deletingAccount
    }

    @Published private(set) var sessionPhase: SessionPhase = .restoring
    @Published private(set) var snapshotPhase: SnapshotPhase = .idle
    @Published private(set) var operation: Operation?
    @Published private(set) var operationErrorKey: String?
    @Published private(set) var pendingReferralCode: String?
    @Published private(set) var shouldPresentAccountCenter = false
    @Published private(set) var lastAccountRefreshAt: Date?
    @Published private(set) var isRefreshingAccountData = false
    @Published private(set) var accountRefreshErrorKey: String?

    let creditPurchases: AccountCreditPurchaseManager
    let referralProfile: ReferralProfileViewModel

    private let sessionService: any AccountSessionServicing
    private let centerService: any AccountCenterServicing
    private let pendingReferralStore: any PendingReferralCodeStoring
    private let analyticsClient: any AnalyticsClient
    private let onAccountAuthenticated: (UUID) async -> Void
    private let onAccountSignedOut: () async -> Void
    private let onAccountDeleted: () async -> Void
    private let accountRefreshInterval: TimeInterval
    private let now: () -> Date
    private var didAttemptRestore = false
    private var accountRefreshTask: Task<Void, Never>?
    private var accountRefreshRequestID: UUID?
    private var sessionEventsTask: Task<Void, Never>?

    init(
        dependencies: AccountDependencies,
        creditStore: any AccountCreditStore = LiveAccountCreditStore(),
        pendingReferralStore: any PendingReferralCodeStoring =
            UserDefaultsPendingReferralCodeStore(),
        referralProfileStore: any ReferralProfileStoring =
            UserDefaultsReferralProfileStore(),
        accountRefreshInterval: TimeInterval = 10 * 60,
        now: @escaping () -> Date = Date.init,
        analyticsClient: any AnalyticsClient = NoopAnalyticsClient(),
        onAccountAuthenticated: @escaping (UUID) async -> Void = { _ in },
        onAccountSignedOut: @escaping () async -> Void = {},
        onAccountDeleted: @escaping () async -> Void = {}
    ) {
        sessionService = dependencies.sessionService
        centerService = dependencies.centerService
        creditPurchases = AccountCreditPurchaseManager(
            service: dependencies.centerService,
            store: creditStore,
            analyticsClient: analyticsClient
        )
        referralProfile = ReferralProfileViewModel(
            service: dependencies.referralService,
            store: referralProfileStore
        )
        self.pendingReferralStore = pendingReferralStore
        self.analyticsClient = analyticsClient
        self.onAccountAuthenticated = onAccountAuthenticated
        self.onAccountSignedOut = onAccountSignedOut
        self.onAccountDeleted = onAccountDeleted
        self.accountRefreshInterval = accountRefreshInterval
        self.now = now
        pendingReferralCode = pendingReferralStore.code
        let sessionEventSource = dependencies.sessionEventSource
        sessionEventsTask = Task { @MainActor [weak self] in
            let events = await sessionEventSource.events()
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.handleSessionEvent(event)
            }
        }
    }

    deinit {
        accountRefreshTask?.cancel()
        sessionEventsTask?.cancel()
    }

    var isSignedIn: Bool {
        if case .signedIn = sessionPhase {
            return true
        }
        return false
    }

    var accountID: UUID? {
        guard case let .signedIn(session) = sessionPhase else { return nil }
        return session.accountID
    }

    func restoreIfNeeded() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        sessionPhase = .restoring
        operationErrorKey = nil

        do {
            guard let session = try await sessionService.restoreSession() else {
                await sessionService.clearManagedGateway()
                await onAccountSignedOut()
                sessionPhase = .signedOut
                return
            }
            await onAccountAuthenticated(session.accountID)
            sessionPhase = .signedIn(session)
            creditPurchases.startSession(accountID: session.accountID)
            referralProfile.startSession(accountID: session.accountID)
            await redeemPendingReferralIfNeeded()
            await refreshAccountData(force: true)
        } catch {
            await sessionService.clearManagedGateway()
            await onAccountSignedOut()
            sessionPhase = .signedOut
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.restore"
            )
        }
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let code = ReferralUniversalLink.code(from: url) else { return false }

        pendingReferralStore.save(code)
        pendingReferralCode = code
        shouldPresentAccountCenter = true
        operationErrorKey = nil
        analyticsClient.recordInviteOpened()

        if isSignedIn {
            Task {
                await redeemPendingReferralIfNeeded()
                await refreshAccountData(force: true)
            }
        }
        return true
    }

    func consumeAccountCenterPresentation() -> Bool {
        guard shouldPresentAccountCenter else { return false }
        shouldPresentAccountCenter = false
        return true
    }

    func signIn(with payload: AppleAuthorizationPayload) async {
        guard operation == nil else { return }
        operation = .signingIn
        operationErrorKey = nil
        defer { operation = nil }

        do {
            let session = try await sessionService.signIn(with: payload)
            await onAccountAuthenticated(session.accountID)
            sessionPhase = .signedIn(session)
            creditPurchases.startSession(accountID: session.accountID)
            referralProfile.startSession(accountID: session.accountID)
            await redeemPendingReferralIfNeeded()
            await refreshAccountData(force: true)
        } catch {
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.signIn"
            )
        }
    }

    /// Owns the single account snapshot consumed by Settings and Account Center.
    /// Page entry uses the freshness window; explicit user actions force refresh.
    func refreshAccountData(force: Bool = false) async {
        guard let accountID else {
            snapshotPhase = .idle
            return
        }
        if let accountRefreshTask {
            await accountRefreshTask.value
            return
        }
        if !force,
           case .loaded = snapshotPhase,
           let lastAccountRefreshAt,
           now().timeIntervalSince(lastAccountRefreshAt) < accountRefreshInterval {
            return
        }
        // Keep the current snapshot visible while refreshing in the background.
        if case .loaded = snapshotPhase {
            // No state transition is needed for an existing snapshot.
        } else {
            snapshotPhase = .loading
        }

        let requestID = UUID()
        accountRefreshRequestID = requestID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performAccountRefresh(
                for: accountID,
                requestID: requestID
            )
        }
        accountRefreshTask = task
        await task.value
        finishAccountRefresh(requestID: requestID)
    }

    func updateDisplayName(_ displayName: String) async -> Bool {
        guard operation == nil, isSignedIn else { return false }
        operation = .updatingProfile
        operationErrorKey = nil
        defer { operation = nil }

        do {
            let account = try await centerService.updateDisplayName(displayName)
            sessionPhase = .signedIn(account)
            if case let .loaded(snapshot) = snapshotPhase {
                snapshotPhase = .loaded(
                    AccountCenterSnapshot(
                        account: account,
                        credits: snapshot.credits,
                        referrals: snapshot.referrals
                    )
                )
            }
            return true
        } catch {
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.updateProfile"
            )
            return false
        }
    }

    func prepareManagedGateway() async -> Bool {
        guard operation == nil, isSignedIn else { return false }
        operation = .preparingManagedGateway
        operationErrorKey = nil
        defer { operation = nil }
        do {
            try await sessionService.prepareManagedGateway()
            return true
        } catch {
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.managedGateway"
            )
            return false
        }
    }

    func clearManagedGateway() async {
        await sessionService.clearManagedGateway()
    }

    func signOut() async {
        guard operation == nil, isSignedIn else { return }
        operation = .signingOut
        operationErrorKey = nil
        defer { operation = nil }
        referralProfile.cancelRefresh()

        do {
            try await sessionService.signOut()
            await onAccountSignedOut()
            creditPurchases.endSession()
            clearAccountRefreshState()
            referralProfile.endSession()
            sessionPhase = .signedOut
            snapshotPhase = .idle
        } catch {
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.signOut"
            )
        }
    }

    func deleteAccount(with payload: AppleAuthorizationPayload) async {
        guard operation == nil, isSignedIn else { return }
        operation = .deletingAccount
        operationErrorKey = nil
        defer { operation = nil }
        referralProfile.cancelRefresh()

        do {
            try await sessionService.deleteAccount(with: payload)
            await onAccountDeleted()
            await onAccountSignedOut()
            creditPurchases.endSession()
            clearAccountRefreshState()
            referralProfile.endSession(removeCache: true)
            sessionPhase = .signedOut
            snapshotPhase = .idle
            pendingReferralStore.clear()
            pendingReferralCode = nil
        } catch {
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.delete"
            )
        }
    }

    func recordAppleAuthorizationFailure() {
        operationErrorKey = "account.error.appleAuthorization"
    }

    func dismissOperationError() {
        operationErrorKey = nil
    }

    private func performAccountRefresh(for accountID: UUID, requestID: UUID) async {
        isRefreshingAccountData = true
        accountRefreshErrorKey = nil

        do {
            try Task.checkCancellation()
            let cachedSnapshot: AccountCenterSnapshot?
            if case let .loaded(snapshot) = snapshotPhase {
                cachedSnapshot = snapshot
            } else {
                cachedSnapshot = nil
            }
            let snapshot = try await centerService.loadAccountCenter(
                cachedSnapshot: cachedSnapshot
            )
            try Task.checkCancellation()
            guard self.accountID == accountID,
                  accountRefreshRequestID == requestID,
                  snapshot.account.accountID == accountID else {
                return
            }
            snapshotPhase = .loaded(snapshot)
            sessionPhase = .signedIn(snapshot.account)
            lastAccountRefreshAt = now()
        } catch is CancellationError {
            return
        } catch {
            guard self.accountID == accountID,
                  accountRefreshRequestID == requestID else {
                return
            }
            let messageKey = errorMessageKey(
                for: error,
                fallback: "account.error.load"
            )
            accountRefreshErrorKey = messageKey
            if case .loaded = snapshotPhase {
                return
            }
            snapshotPhase = .failed(messageKey: messageKey)
        }
    }

    private func clearAccountRefreshState() {
        accountRefreshTask?.cancel()
        accountRefreshTask = nil
        accountRefreshRequestID = nil
        lastAccountRefreshAt = nil
        isRefreshingAccountData = false
        accountRefreshErrorKey = nil
    }

    private func finishAccountRefresh(requestID: UUID) {
        guard accountRefreshRequestID == requestID else { return }
        accountRefreshTask = nil
        accountRefreshRequestID = nil
        isRefreshingAccountData = false
    }

    private func handleSessionEvent(_ event: AccountSessionEvent) async {
        switch event {
        case .expired:
            guard isSignedIn else { return }
            await sessionService.clearManagedGateway()
            await onAccountSignedOut()
            creditPurchases.endSession()
            clearAccountRefreshState()
            referralProfile.endSession()
            sessionPhase = .signedOut
            snapshotPhase = .idle
            operationErrorKey = "account.error.sessionExpired"
        }
    }

    private func redeemPendingReferralIfNeeded() async {
        guard isSignedIn, let code = pendingReferralStore.code else { return }

        operation = .redeemingReferral
        do {
            try await centerService.redeemReferral(code: code)
            pendingReferralStore.clear()
            pendingReferralCode = nil
        } catch {
            pendingReferralCode = code
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.redeemReferral"
            )
        }
        operation = nil
    }

    private func errorMessageKey(for error: Error, fallback: String) -> String {
        if error as? AccountIntegrationError == .unavailable {
            return "account.error.unavailable"
        }
        return fallback
    }
}
