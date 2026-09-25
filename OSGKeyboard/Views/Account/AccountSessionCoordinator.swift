// AccountSessionCoordinator.swift
// OSGKeyboard · Main App
//
// Main-actor state machine for optional account features. Local and BYOK
// features never consult this coordinator and remain available when signed out.

import AuthenticationServices
import Combine
import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

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
    /// Machine-readable code for `operationErrorKey` (see `AccountDiagnostic`).
    /// The localized key alone says "sign-in failed"; this says *why*, which is
    /// the difference between a bug report we can act on and one we cannot.
    @Published private(set) var operationErrorDetail: String?
    @Published private(set) var pendingReferralCode: String?
    @Published private(set) var shouldPresentAccountCenter = false
    @Published private(set) var lastAccountRefreshAt: Date?
    @Published private(set) var isRefreshingAccountData = false
    @Published private(set) var accountRefreshErrorKey: String?

    let creditPurchases: AccountCreditPurchaseManager
    let referralProfile: ReferralProfileViewModel

    private let sessionService: any AccountSessionServicing
    private let centerService: any AccountCenterServicing
    /// False on macOS: a Developer ID build cannot use StoreKit, so starting a
    /// purchase session there would fetch a product catalog and open a
    /// `Transaction` listener for a store that can never complete a purchase.
    /// Credits are still spent normally — only buying is unavailable.
    private let arePurchasesAvailable: Bool
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
    private var pendingForcedAccountRefresh = false
    private var sessionEventsTask: Task<Void, Never>?
    private var appleCredentialRevocationCancellable: AnyCancellable?
    private var sessionRevision: UInt64 = 0

    init(
        dependencies: AccountDependencies,
        creditStore: any AccountCreditStore = LiveAccountCreditStore(),
        pendingReferralStore: any PendingReferralCodeStoring =
            UserDefaultsPendingReferralCodeStore(),
        referralProfileStore: any ReferralProfileStoring =
            UserDefaultsReferralProfileStore(),
        accountRefreshInterval: TimeInterval = 10 * 60,
        arePurchasesAvailable: Bool = true,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default,
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
        self.arePurchasesAvailable = arePurchasesAvailable
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
        appleCredentialRevocationCancellable = notificationCenter
            .publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.handleAppleCredentialRevocation(
                        errorKey: "account.error.sessionExpired"
                    )
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
        operationErrorDetail = nil

        do {
            guard let session = try await sessionService.restoreSession() else {
                await sessionService.clearManagedGateway()
                await onAccountSignedOut()
                sessionPhase = .signedOut
                return
            }
            await onAccountAuthenticated(session.accountID)
            advanceSessionRevision()
            sessionPhase = .signedIn(session)
            if arePurchasesAvailable {
                creditPurchases.startSession(accountID: session.accountID)
            }
            referralProfile.startSession(accountID: session.accountID)
            await redeemPendingReferralIfNeeded()
            await refreshAccountData(force: true)
        } catch {
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.restore"
            )
            if error as? AccountIntegrationError == .unavailable {
                await sessionService.clearManagedGateway()
                await onAccountSignedOut()
                sessionPhase = .signedOut
            } else {
                // Keychain protection and transport availability can be
                // transient during launch. Keep the restoring state and allow
                // the next foreground activation to retry instead of turning
                // a retained, valid session into a signed-out session.
                didAttemptRestore = false
            }
        }
    }

    func validateAppleCredentialState() async {
        guard isSignedIn else { return }
        switch await sessionService.appleCredentialState() {
        case .authorized, .unknown:
            return
        case .revoked:
            await handleAppleCredentialRevocation(
                errorKey: "account.error.sessionExpired"
            )
        case .reauthenticationRequired:
            await handleAppleCredentialRevocation(
                errorKey: "account.error.appleReauthenticationRequired"
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
        operationErrorDetail = nil
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
        operationErrorDetail = nil
        defer { operation = nil }

        do {
            let session = try await sessionService.signIn(with: payload)
            await onAccountAuthenticated(session.accountID)
            advanceSessionRevision()
            sessionPhase = .signedIn(session)
            if arePurchasesAvailable {
                creditPurchases.startSession(accountID: session.accountID)
            }
            referralProfile.startSession(accountID: session.accountID)
            await redeemPendingReferralIfNeeded()
            await refreshAccountData(force: true)
        } catch {
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.signIn"
            )
            operationErrorDetail = AccountDiagnostic.code(for: error)
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
            if force {
                pendingForcedAccountRefresh = true
            }
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
        let shouldRunForcedRefresh = pendingForcedAccountRefresh
        pendingForcedAccountRefresh = false
        if shouldRunForcedRefresh, self.accountID != nil {
            await refreshAccountData(force: true)
        }
    }

    func updateDisplayName(_ displayName: String) async -> Bool {
        guard operation == nil, let expectedAccountID = accountID else { return false }
        let expectedRevision = sessionRevision
        operation = .updatingProfile
        operationErrorKey = nil
        operationErrorDetail = nil
        defer { operation = nil }

        do {
            let account = try await centerService.updateDisplayName(displayName)
            guard sessionRevision == expectedRevision,
                  accountID == expectedAccountID,
                  account.accountID == expectedAccountID else {
                return false
            }
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
            guard sessionRevision == expectedRevision,
                  accountID == expectedAccountID else {
                return false
            }
            operationErrorKey = errorMessageKey(
                for: error,
                fallback: "account.error.updateProfile"
            )
            return false
        }
    }

    func prepareManagedGateway() async -> Bool {
        guard operation == nil, let expectedAccountID = accountID else { return false }
        let expectedRevision = sessionRevision
        operation = .preparingManagedGateway
        operationErrorKey = nil
        operationErrorDetail = nil
        defer { operation = nil }
        do {
            try await sessionService.prepareManagedGateway()
            guard sessionRevision == expectedRevision,
                  accountID == expectedAccountID else {
                await sessionService.clearManagedGateway()
                return false
            }
            return true
        } catch {
            guard sessionRevision == expectedRevision,
                  accountID == expectedAccountID else {
                return false
            }
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
        operationErrorDetail = nil
        defer { operation = nil }
        referralProfile.cancelRefresh()

        do {
            try await sessionService.signOut()
            await onAccountSignedOut()
            advanceSessionRevision()
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
        operationErrorDetail = nil
        defer { operation = nil }
        referralProfile.cancelRefresh()

        do {
            try await sessionService.deleteAccount(with: payload)
            await onAccountDeleted()
            await onAccountSignedOut()
            advanceSessionRevision()
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

    func recordAppleAuthorizationFailure(detail: String = "apple-authorization") {
        operationErrorKey = "account.error.appleAuthorization"
        operationErrorDetail = detail
    }

    func dismissOperationError() {
        operationErrorKey = nil
        operationErrorDetail = nil
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
        pendingForcedAccountRefresh = false
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
            await expireSession(
                errorKey: "account.error.sessionExpired",
                signsOutService: false
            )
        }
    }

    private func handleAppleCredentialRevocation(errorKey: String) async {
        guard operation != .signingOut,
              operation != .deletingAccount else {
            return
        }
        await expireSession(errorKey: errorKey, signsOutService: true)
    }

    private func expireSession(
        errorKey: String,
        signsOutService: Bool
    ) async {
        guard isSignedIn else { return }
        advanceSessionRevision()
        if signsOutService {
            do {
                try await sessionService.signOut()
            } catch {
                operationErrorKey = "account.error.signOut"
                return
            }
        }
        await sessionService.clearManagedGateway()
        await onAccountSignedOut()
        creditPurchases.endSession()
        clearAccountRefreshState()
        referralProfile.endSession()
        operation = nil
        sessionPhase = .signedOut
        snapshotPhase = .idle
        operationErrorKey = errorKey
    }

    private func advanceSessionRevision() {
        sessionRevision &+= 1
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
