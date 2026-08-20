// ReferralProfileViewModel.swift
// OSGKeyboard · Main App
//
// Account-scoped invitation state. The server profile is authoritative while
// the local cache keeps the permanent invitation link visible when offline.

import Foundation
import OSGKeyboardHostSupport

@MainActor
final class ReferralProfileViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(ReferralProfile)
        case failed(messageKey: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshErrorKey: String?

    private let service: any ReferralProfileServicing
    private let store: any ReferralProfileStoring

    private var accountID: UUID?
    private var requestID: UUID?
    private var refreshTask: Task<Void, Never>?

    init(
        service: any ReferralProfileServicing,
        store: any ReferralProfileStoring = UserDefaultsReferralProfileStore()
    ) {
        self.service = service
        self.store = store
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Starts one automatic load for this signed-in account session. Repeated
    /// view appearances are ignored; ending or changing the session cancels it.
    func startSession(accountID: UUID) {
        guard self.accountID != accountID else { return }

        cancelCurrentRequest()
        self.accountID = accountID
        refreshErrorKey = nil
        if let cachedProfile = store.profile(for: accountID) {
            state = .loaded(cachedProfile)
        } else {
            state = .loading
        }
        beginRefresh()
    }

    func endSession(removeCache: Bool = false) {
        let previousAccountID = accountID
        cancelCurrentRequest()
        accountID = nil
        state = .idle
        refreshErrorKey = nil
        if removeCache, let previousAccountID {
            store.removeProfile(for: previousAccountID)
        }
    }

    func cancelRefresh() {
        guard let accountID else { return }
        cancelCurrentRequest()
        if case .loaded = state {
            // Preserve the visible server profile.
        } else if let cachedProfile = store.profile(for: accountID) {
            state = .loaded(cachedProfile)
        } else {
            state = .idle
        }
        refreshErrorKey = nil
    }

    func refresh() async {
        guard accountID != nil else {
            state = .idle
            return
        }
        if let refreshTask {
            await refreshTask.value
            return
        }
        beginRefresh()
        await refreshTask?.value
    }

    private func beginRefresh() {
        guard refreshTask == nil, let accountID else { return }

        let id = UUID()
        requestID = id
        refreshErrorKey = nil
        isRefreshing = true
        if case .loaded = state {
            // Keep a cached or previously loaded profile visible while refreshing.
        } else {
            state = .loading
        }

        refreshTask = Task { @MainActor [weak self] in
            await self?.performRefresh(accountID: accountID, requestID: id)
        }
    }

    private func performRefresh(accountID: UUID, requestID: UUID) async {
        let previousProfile: ReferralProfile? = if case let .loaded(profile) = state {
            profile
        } else {
            nil
        }

        defer {
            if self.requestID == requestID {
                isRefreshing = false
                refreshTask = nil
                self.requestID = nil
            }
        }

        do {
            try Task.checkCancellation()
            let profile = try await service.loadReferralProfile()
            try Task.checkCancellation()
            guard self.accountID == accountID, self.requestID == requestID else {
                return
            }
            store.save(profile, for: accountID)
            state = .loaded(profile)
            refreshErrorKey = nil
        } catch is CancellationError {
            guard self.accountID == accountID, self.requestID == requestID else {
                return
            }
            state = previousProfile.map(State.loaded) ?? .idle
            refreshErrorKey = nil
        } catch {
            guard self.accountID == accountID, self.requestID == requestID else {
                return
            }
            let messageKey = Self.errorMessageKey(for: error)
            refreshErrorKey = messageKey
            if let previousProfile {
                state = .loaded(previousProfile)
            } else {
                state = .failed(messageKey: messageKey)
            }
        }
    }

    private func cancelCurrentRequest() {
        refreshTask?.cancel()
        refreshTask = nil
        requestID = nil
        isRefreshing = false
    }

    private static func errorMessageKey(for error: Error) -> String {
        guard let error = error as? AccountAPIError else {
            return error as? AccountIntegrationError == .unavailable
                ? "account.error.unavailable"
                : "account.referral.error.load"
        }
        switch error {
        case .unauthorized, .refreshTokenReuse, .sessionUnavailable:
            return "account.referral.error.session"
        case .transport:
            return "account.referral.error.network"
        case .externalServiceUnavailable:
            return "account.referral.error.unavailable"
        case .conflict:
            return "account.referral.error.conflict"
        case .server(let statusCode, _, _):
            switch statusCode {
            case 401:
                return "account.referral.error.session"
            case 404:
                return "account.referral.error.notFound"
            case 409:
                return "account.referral.error.conflict"
            case 500..<600:
                return "account.referral.error.unavailable"
            default:
                return "account.referral.error.load"
            }
        default:
            return "account.referral.error.load"
        }
    }
}
