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
#if canImport(OSGKeyboardHostSupport)
import OSGKeyboardHostSupport
#endif

@MainActor
final class AccountSessionCoordinator: ObservableObject {
    /// Result of an invitation the user typed or pasted instead of opening a link.
    enum ReferralInputOutcome: Equatable {
        case invalidInput
        case savedForSignIn
        case redeemed
        case failed(messageKey: String)
    }

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

        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        await adoptPendingDebugSessionHandoff()
        #endif

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

        stagePendingReferral(code)
        shouldPresentAccountCenter = true
        analyticsClient.recordInviteOpened()

        if isSignedIn {
            Task {
                await redeemPendingReferralIfNeeded()
                await refreshAccountData(force: true)
            }
        }
        return true
    }

    /// Manual path for invitations that never reached the app as a Universal
    /// Link — typically a friend who scanned a poster, installed from the App
    /// Store, and typed the short code (or pasted the link). The outcome is
    /// returned to the caller instead of `operationErrorKey` so the code-entry
    /// sheet can explain it inline rather than through the global alert.
    func submitReferralInput(_ text: String) async -> ReferralInputOutcome {
        guard let code = ReferralUniversalLink.code(fromUserInput: text) else {
            return .invalidInput
        }
        stagePendingReferral(code)
        guard isSignedIn else { return .savedForSignIn }

        if let messageKey = await redeemPendingReferral() {
            return .failed(messageKey: messageKey)
        }
        await referralProfile.refresh()
        await refreshAccountData(force: true)
        return .redeemed
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
        errorKey: String?,
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

    #if DEBUG
    /// Signs this app out without a server logout and writes the session to
    /// `directory`: the AirDrop file on a device, or the Simulator's own
    /// import location to park it (`debugResumeParkedSession()` brings it back).
    func debugRelinquishSession(writingTo directory: URL) async throws -> URL {
        guard isSignedIn, operation == nil else {
            throw AccountAPIError.sessionUnavailable
        }
        guard let handoff = sessionService as? any DebugAccountSessionHandingOff else {
            throw DebugAccountSessionHandoff.HandoffError.unsupportedService
        }
        let session = try await handoff.debugRelinquishSession()
        await expireSession(errorKey: nil, signsOutService: false)
        return try DebugAccountSessionHandoff.writeExportFile(session, directory: directory)
    }

    #if os(iOS) && targetEnvironment(simulator)
    /// Re-runs restore, which adopts the parked handoff file first.
    func debugResumeParkedSession() async {
        guard !isSignedIn, operation == nil else { return }
        didAttemptRestore = false
        await restoreIfNeeded()
    }
    #endif

    private func adoptPendingDebugSessionHandoff() async {
        guard let handoff = sessionService as? any DebugAccountSessionHandingOff,
              let session = DebugAccountSessionHandoff.consumePendingImport() else {
            return
        }
        do {
            try await handoff.debugAdoptSession(session)
            OSGDiag.log("debug session handoff adopted", category: "account")
        } catch {
            OSGDiag.log(
                "debug session handoff failed error=\(AccountDiagnostic.code(for: error))",
                category: "account"
            )
        }
    }
    #endif

    private func stagePendingReferral(_ code: String) {
        pendingReferralStore.save(code)
        pendingReferralCode = code
        operationErrorKey = nil
        operationErrorDetail = nil
    }

    private func redeemPendingReferralIfNeeded() async {
        if let messageKey = await redeemPendingReferral() {
            operationErrorKey = messageKey
        }
    }

    /// Returns nil on success (or when nothing is pending), otherwise the
    /// message key. Rejections the server will repeat forever drop the stored
    /// code; transient failures keep it for the next sign-in or launch.
    private func redeemPendingReferral() async -> String? {
        guard isSignedIn, let code = pendingReferralStore.code else { return nil }

        operation = .redeemingReferral
        defer { operation = nil }
        do {
            try await centerService.redeemReferral(code: code)
            pendingReferralStore.clear()
            pendingReferralCode = nil
            return nil
        } catch {
            let failure = Self.referralRedemptionFailure(for: error)
            if failure.isPermanent {
                pendingReferralStore.clear()
                pendingReferralCode = nil
            } else {
                pendingReferralCode = code
            }
            return failure.messageKey
        }
    }

    private static func referralRedemptionFailure(
        for error: Error
    ) -> (messageKey: String, isPermanent: Bool) {
        if error as? AccountIntegrationError == .unavailable {
            return ("account.error.unavailable", false)
        }
        guard let apiError = error as? AccountAPIError else {
            return ("account.error.redeemReferral", false)
        }
        // Referral routes answer with a bare `{"error": message}` body, so most
        // rejections arrive as `.server` and are told apart by status code.
        switch apiError {
        case .invalidRequest:
            return ("account.referral.redeem.error.invalid", true)
        case .conflict(let message):
            return (conflictMessageKey(for: message), true)
        case let .server(statusCode, _, message):
            switch statusCode {
            case 400, 404:
                return ("account.referral.redeem.error.invalid", true)
            case 409:
                return (conflictMessageKey(for: message), true)
            case 422:
                return ("account.referral.redeem.error.expired", true)
            default:
                return ("account.error.redeemReferral", false)
            }
        default:
            return ("account.error.redeemReferral", false)
        }
    }

    private static func conflictMessageKey(for message: String) -> String {
        if message.localizedCaseInsensitiveContains("self-referral") {
            return "account.referral.redeem.error.self"
        }
        if message.localizedCaseInsensitiveContains("already bound") {
            return "account.referral.redeem.error.alreadyBound"
        }
        return "account.referral.redeem.error.ineligible"
    }

    private func errorMessageKey(for error: Error, fallback: String) -> String {
        if error as? AccountIntegrationError == .unavailable {
            return "account.error.unavailable"
        }
        return fallback
    }
}
