// AnalyticsExtensionService.swift
// OSGKeyboard · Keyboard Extension
//
// The extension records into the shared SQLite queue and only attempts one
// short anonymous batch when Full Access permits network use.

import Foundation
import OSGKeyboardShared
import OSLog

private actor ExtensionAnalyticsUploadSignal: AnalyticsUploadTriggering {
    typealias Action = @Sendable () async -> Void

    private var action: Action?
    private var canUpload = false
    private var isUploading = false

    func install(_ action: @escaping Action) {
        self.action = action
    }

    func setCanUpload(_ canUpload: Bool) {
        self.canUpload = canUpload
    }

    func requestUpload() {
        guard canUpload, !isUploading, let action else { return }
        isUploading = true
        Task {
            await action()
            uploadFinished()
        }
    }

    private func uploadFinished() {
        isUploading = false
    }
}

private struct ExtensionAnalyticsLogger: AnalyticsLogging {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.osgkeyboard.ios.keyboard",
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

final class AnalyticsExtensionService: Sendable {
    static let shared = AnalyticsExtensionService()

    let client: any AnalyticsClient

    private let runtime: AnalyticsRuntime
    private let uploadSignal: ExtensionAnalyticsUploadSignal

    private init() {
        let signal = ExtensionAnalyticsUploadSignal()
        uploadSignal = signal
        let runtime = AnalyticsRuntime.keyboardExtension(
            environment: Self.environment,
            uploadConfiguration: AnalyticsUploadConfiguration(endpoint: Self.endpoint),
            trigger: signal,
            logger: ExtensionAnalyticsLogger()
        )
        self.runtime = runtime
        client = runtime.client

        Task {
            await signal.install {
                await runtime.uploadCoordinator.uploadAvailableEvents(maximumBatches: 1)
            }
        }
    }

    func recordPresentation(hasFullAccess: Bool) {
        Task {
            await uploadSignal.setCanUpload(hasFullAccess)
            client.recordSessionActivity()
            client.recordKeyboardActivated()
        }
    }

    func keyboardWillDisappear() {
        Task {
            await uploadSignal.setCanUpload(false)
        }
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
