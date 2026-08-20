// AccountSessionCoordinator.swift
// OSGKeyboard · Main App
//
// Main-actor state machine for optional account features. Local and BYOK
// features never consult this coordinator and remain available when signed out.

import Combine
import Foundation

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

    private let sessionService: any AccountSessionServicing
    private let centerService: any AccountCenterServicing
    private let pendingReferralStore: any PendingReferralCodeStoring
    private let accountRefreshInterval: TimeInterval
    private let now: () -> Date
    private var didAttemptRestore = false
    private var accountRefreshTask: Task<Void, Never>?

    init(
        dependencies: AccountDependencies,
        creditStore: any AccountCreditStore = LiveAccountCreditStore(),
        pendingReferralStore: any PendingReferralCodeStoring =
            UserDefaultsPendingReferralCodeStore(),
        accountRefreshInterval: TimeInterval = 10 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        sessionService = dependencies.sessionService
        centerService = dependencies.centerService
        creditPurchases = AccountCreditPurchaseManager(
            service: dependencies.centerService,
            store: creditStore
        )
        self.pendingReferralStore = pendingReferralStore
        self.accountRefreshInterval = accountRefreshInterval
        self.now = now
        pendingReferralCode = pendingReferralStore.code
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
                sessionPhase = .signedOut
                return
            }
            sessionPhase = .signedIn(session)
            await redeemPendingReferralIfNeeded()
            await refreshAccountData(force: true)
        } catch {
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
            sessionPhase = .signedIn(session)
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

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performAccountRefresh(for: accountID)
        }
        accountRefreshTask = task
        await task.value
        accountRefreshTask = nil
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
                        referralProfile: snapshot.referralProfile,
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

        do {
            try await sessionService.signOut()
            creditPurchases.reset()
            clearAccountRefreshState()
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

        do {
            try await sessionService.deleteAccount(with: payload)
            creditPurchases.reset()
            clearAccountRefreshState()
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

    private func performAccountRefresh(for accountID: UUID) async {
        isRefreshingAccountData = true
        accountRefreshErrorKey = nil
        defer { isRefreshingAccountData = false }

        do {
            let cachedSnapshot: AccountCenterSnapshot?
            if case let .loaded(snapshot) = snapshotPhase {
                cachedSnapshot = snapshot
            } else {
                cachedSnapshot = nil
            }
            let snapshot = try await centerService.loadAccountCenter(
                cachedSnapshot: cachedSnapshot
            )
            guard self.accountID == accountID,
                  snapshot.account.accountID == accountID else {
                return
            }
            snapshotPhase = .loaded(snapshot)
            sessionPhase = .signedIn(snapshot.account)
            lastAccountRefreshAt = now()
        } catch {
            guard self.accountID == accountID else { return }
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
        lastAccountRefreshAt = nil
        isRefreshingAccountData = false
        accountRefreshErrorKey = nil
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
