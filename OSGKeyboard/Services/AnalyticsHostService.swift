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

actor AnalyticsUploadSignal: AnalyticsUploadTriggering {
    typealias Action = @Sendable () async -> Void

    private var action: Action?
    private var isScheduled = false
    private let debounce: Duration

    init(debounce: Duration = .milliseconds(250)) {
        self.debounce = debounce
    }

    func install(_ action: @escaping Action) {
        self.action = action
    }

    func requestUpload() {
        guard !isScheduled, let action else { return }
        isScheduled = true
        Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else {
                uploadFinished()
                return
            }
            await action()
            uploadFinished()
        }
    }

    private func uploadFinished() {
        isScheduled = false
    }
}

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
    private var foregroundUploadTask: Task<Void, Never>?

    init(
        bearerProvider: any AnalyticsBearerProviding = HostAnalyticsBearerBridge.shared,
        network: any AnalyticsNetworking = URLSessionAnalyticsNetwork()
    ) {
        let signal = AnalyticsUploadSignal()
        uploadSignal = signal
        let runtime = AnalyticsRuntime.mainApp(
            environment: Self.environment,
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
                await runtime.uploadCoordinator.uploadAvailableEvents(maximumBatches: 4)
            }
        }
    }

    func prepare(firstOpenAcquisitionChannel: AnalyticsAcquisitionChannel) {
        startNetworkMonitoringIfNeeded()
        Task {
            await runtime.prepare(
                firstOpenAcquisitionChannel: firstOpenAcquisitionChannel
            )
            let enabled = await runtime.isEnabled()
            await MainActor.run {
                self.isEnabled = enabled
            }
            client.recordSessionActivity()
            await runtime.uploadCoordinator.uploadAvailableEvents(maximumBatches: 8)
        }
    }

    func appDidBecomeActive() {
        client.recordSessionActivity()
        requestImmediateUpload(maximumBatches: 8)
    }

    func appDidEnterBackground() {
        Self.scheduleBackgroundRefresh()
        let identifier = UIApplication.shared.beginBackgroundTask(
            withName: "analytics-sync"
        )
        guard identifier != .invalid else { return }
        let task = Task {
            await runtime.uploadCoordinator.uploadAvailableEvents(maximumBatches: 2)
            await MainActor.run {
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }
        foregroundUploadTask = task
    }

    func observeAuthenticatedAccount(_ accountID: UUID) async {
        _ = await runtime.observeAccount(stableIdentifier: accountID.uuidString)
        await runtime.uploadCoordinator.uploadAvailableEvents(maximumBatches: 8)
    }

    func handleAccountDeletion() async {
        await runtime.handleAccountDeletion()
    }

    func setEnabled(_ enabled: Bool) {
        Task {
            await runtime.setEnabled(enabled)
            let current = await runtime.isEnabled()
            await MainActor.run {
                self.isEnabled = current
            }
            if current {
                await runtime.uploadCoordinator.uploadAvailableEvents(maximumBatches: 4)
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

    func requestImmediateUpload(maximumBatches: Int = 4) {
        foregroundUploadTask?.cancel()
        foregroundUploadTask = Task {
            await runtime.uploadCoordinator.uploadAvailableEvents(
                maximumBatches: maximumBatches
            )
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
                await AnalyticsHostService.shared.runtime.uploadCoordinator
                    .uploadAvailableEvents(maximumBatches: 4)
                refreshTask.setTaskCompleted(success: !Task.isCancelled)
                scheduleBackgroundRefresh()
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
            Task { @MainActor in
                AnalyticsHostService.shared.requestImmediateUpload(maximumBatches: 8)
            }
        }
        pathMonitor.start(queue: monitorQueue)
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
