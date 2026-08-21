// AnalyticsHostService.swift
// OSGKeyboard · Main App
//
// Host-only analytics lifecycle. The shared module owns the wire contract,
// SQLite queue and uploader; this type only connects iOS lifecycle signals.

import BackgroundTasks
import Foundation
import Network
import OSGKeyboardHostSupport
import OSGKeyboardShared
import OSLog
import UIKit

final class HostAnalyticsBearerBridge: AnalyticsBearerProviding, @unchecked Sendable {
    static let shared = HostAnalyticsBearerBridge()

    private let lock = NSLock()
    private var provider: (any AnalyticsBearerProviding)?

    func install(_ provider: any AnalyticsBearerProviding) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    func bearerToken() async throws -> String? {
        try await currentProvider()?.bearerToken()
    }

    func refreshBearerToken(
        afterUnauthorizedAccessToken failedToken: String?
    ) async throws -> String? {
        try await currentProvider()?.refreshBearerToken(
            afterUnauthorizedAccessToken: failedToken
        )
    }

    private func currentProvider() -> (any AnalyticsBearerProviding)? {
        lock.lock()
        defer { lock.unlock() }
        return provider
    }
}

struct AccountAnalyticsBearerProvider: AnalyticsBearerProviding {
    let apiClient: AccountAPIClient

    func bearerToken() async throws -> String? {
        guard try await apiClient.currentSession() != nil else { return nil }
        return try await apiClient.accessTokenForAuthorizedRequest()
    }

    func refreshBearerToken(
        afterUnauthorizedAccessToken failedToken: String?
    ) async throws -> String? {
        guard let failedToken, !failedToken.isEmpty else { return nil }
        return try await apiClient.refreshAccessToken(
            afterUnauthorizedAccessToken: failedToken
        )
    }
}

struct HostAnalyticsLogger: AnalyticsLogging {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.osgkeyboard.ios",
        category: "analytics"
    )

    func log(_ entry: AnalyticsUploadLogEntry) {
        let statusCode = entry.statusCode ?? 0
        let errorCategory = entry.errorCategory?.rawValue ?? "none"
        logger.info(
            "outcome=\(entry.outcome.rawValue, privacy: .public) count=\(entry.eventCount, privacy: .public) status=\(statusCode, privacy: .public) attempt=\(entry.attempt, privacy: .public) error=\(errorCategory, privacy: .public)"
        )
    }
}

@MainActor
final class AnalyticsHostService: ObservableObject {
    private enum RequestedDatabaseAccess {
        case uninitialized
        case foreground
        case suspended
    }

    static let shared = AnalyticsHostService()
    static let backgroundTaskIdentifier = "com.osgkeyboard.ios.analytics-sync"

    @Published private(set) var isEnabled = true

    let client: any AnalyticsClient

    private let runtime: AnalyticsRuntime
    private let uploadSignal: AnalyticsUploadSignal
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(
        label: "com.osgkeyboard.analytics.network",
        qos: .utility
    )
    private var isMonitoringNetwork = false
    private var requestedDatabaseAccess = RequestedDatabaseAccess.uninitialized
    private var databaseTransitionTask: Task<Void, Never>?
    private var databaseTransitionGeneration = 0
    private var firstOpenAcquisitionChannel = AnalyticsAcquisitionChannel.unknown
    private var pendingAuthenticatedAccountID: UUID?
    private var hasPendingAccountDeletion = false
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    init(
        bearerProvider: any AnalyticsBearerProviding = HostAnalyticsBearerBridge.shared,
        network: any AnalyticsNetworking = URLSessionAnalyticsNetwork(),
        uploadPolicy: AnalyticsUploadPolicy = .mobileDefault
    ) {
        let signal = AnalyticsUploadSignal(policy: uploadPolicy)
        uploadSignal = signal
        let environment = Self.environment
        let runtime = AnalyticsRuntime.mainApp(
            environment: environment,
            uploadConfiguration: AnalyticsUploadConfiguration(endpoint: Self.endpoint),
            network: network,
            bearerProvider: bearerProvider,
            trigger: signal,
            logger: HostAnalyticsLogger()
        )
        self.runtime = runtime
        client = runtime.client

        Task {
            await signal.install {
                guard !Task.isCancelled else { return }
                await runtime.uploadCoordinator.uploadAvailableEvents(
                    maximumBatches: uploadPolicy.maximumBatches
                )
            }
        }
    }

    func prepare(firstOpenAcquisitionChannel: AnalyticsAcquisitionChannel) {
        self.firstOpenAcquisitionChannel = firstOpenAcquisitionChannel
        startNetworkMonitoringIfNeeded()
    }

    func appDidBecomeActive() {
        requestForegroundDatabaseAccess()
    }

    func appWillResignActive() {
        requestSuspendedDatabaseAccess()
    }

    func appDidEnterBackground() {
        Self.scheduleBackgroundRefresh()
        requestSuspendedDatabaseAccess()
        guard backgroundTaskIdentifier == .invalid else { return }

        var identifier: UIBackgroundTaskIdentifier = .invalid
        identifier = UIApplication.shared.beginBackgroundTask(
            withName: "analytics-quiescence"
        ) { [weak self] in
            Task { @MainActor in
                self?.finishBackgroundTask(identifier)
            }
        }
        guard identifier != .invalid else { return }
        backgroundTaskIdentifier = identifier

        let transitionTask = databaseTransitionTask
        Task { [weak self] in
            await transitionTask?.value
            await MainActor.run {
                self?.finishBackgroundTask(identifier)
            }
        }
    }

    func observeAuthenticatedAccount(_ accountID: UUID) async {
        pendingAuthenticatedAccountID = accountID
        let transitionTask = databaseTransitionTask
        await transitionTask?.value
        await processDeferredAccountWork()
    }

    func handleAccountDeletion() async {
        hasPendingAccountDeletion = true
        let transitionTask = databaseTransitionTask
        await transitionTask?.value
        await processDeferredAccountWork()
    }

    func setEnabled(_ enabled: Bool) {
        Task {
            await runtime.setEnabled(enabled)
            let current = await runtime.isEnabled()
            await MainActor.run {
                self.isEnabled = current
            }
            if current {
                await uploadSignal.requestActivationUpload()
            }
        }
    }

    func refreshEnabledState() {
        Task {
            let current = await runtime.isEnabled()
            await MainActor.run {
                self.isEnabled = current
            }
        }
    }

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let operation = Task {
                let success = await AnalyticsHostService.shared
                    .performBackgroundRefresh()
                refreshTask.setTaskCompleted(success: success)
                if success {
                    scheduleBackgroundRefresh()
                }
            }
            refreshTask.expirationHandler = {
                operation.cancel()
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func startNetworkMonitoringIfNeeded() {
        guard !isMonitoringNetwork else { return }
        isMonitoringNetwork = true
        pathMonitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task {
                await AnalyticsHostService.shared.uploadSignal
                    .requestActivationUpload()
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func requestForegroundDatabaseAccess() {
        guard requestedDatabaseAccess != .foreground else { return }
        requestedDatabaseAccess = .foreground
        databaseTransitionGeneration += 1
        let generation = databaseTransitionGeneration
        let previous = databaseTransitionTask
        let runtime = runtime
        let signal = uploadSignal
        let client = client
        let acquisitionChannel = firstOpenAcquisitionChannel
        let task = Task { [weak self] in
            await previous?.value
            await runtime.repository.resumeDatabaseAccess()
            await runtime.prepare(
                firstOpenAcquisitionChannel: acquisitionChannel
            )
            let enabled = await runtime.isEnabled()
            await self?.processDeferredAccountWork()
            await signal.setActive(true)
            client.recordSessionActivity()
            await signal.requestActivationUpload()
            await MainActor.run {
                guard let self else { return }
                self.isEnabled = enabled
                self.finishDatabaseTransition(generation: generation)
            }
        }
        databaseTransitionTask = task
    }

    private func requestSuspendedDatabaseAccess() {
        guard requestedDatabaseAccess != .suspended else { return }
        requestedDatabaseAccess = .suspended
        databaseTransitionGeneration += 1
        let generation = databaseTransitionGeneration
        let previous = databaseTransitionTask
        let runtime = runtime
        let signal = uploadSignal
        let task = Task { [weak self] in
            await previous?.value
            await signal.pauseAndWait()
            await runtime.repository.suspendDatabaseAccess()
            await MainActor.run {
                self?.finishDatabaseTransition(generation: generation)
            }
        }
        databaseTransitionTask = task
    }

    private func processDeferredAccountWork() async {
        guard requestedDatabaseAccess == .foreground else { return }

        if hasPendingAccountDeletion {
            await runtime.handleAccountDeletion()
            hasPendingAccountDeletion = false
        }

        guard let accountID = pendingAuthenticatedAccountID else { return }
        let observation = await runtime.observeAccount(
            stableIdentifier: accountID.uuidString
        )
        guard requestedDatabaseAccess == .foreground else { return }
        if case .unavailable = observation {
            return
        }
        pendingAuthenticatedAccountID = nil
        await uploadSignal.requestActivationUpload()
    }

    private func performBackgroundRefresh() async -> Bool {
        let transitionTask = databaseTransitionTask
        await transitionTask?.value
        guard !Task.isCancelled else { return false }

        await runtime.repository.resumeDatabaseAccess()

        await runtime.uploadCoordinator.uploadAvailableEvents(maximumBatches: 1)
        let success = !Task.isCancelled

        if requestedDatabaseAccess != .foreground {
            await runtime.repository.suspendDatabaseAccess()
            // A foreground transition may race the final close while this
            // actor is re-entrant. Re-open if it won during the suspension.
            if requestedDatabaseAccess == .foreground {
                await runtime.repository.resumeDatabaseAccess()
            }
        }
        return success
    }

    private func finishDatabaseTransition(generation: Int) {
        guard databaseTransitionGeneration == generation else { return }
        databaseTransitionTask = nil
    }

    private func finishBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid,
              backgroundTaskIdentifier == identifier else {
            return
        }
        UIApplication.shared.endBackgroundTask(identifier)
        backgroundTaskIdentifier = .invalid
    }

    private static let endpoint = URL(
        string: "https://account.osglab.com/v1/analytics/events"
    )!

    private static var environment: AnalyticsEnvironment {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return AnalyticsEnvironment(
            appVersion: appVersion,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }
}
