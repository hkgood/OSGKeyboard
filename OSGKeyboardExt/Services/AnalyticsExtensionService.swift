// AnalyticsExtensionService.swift
// OSGKeyboard · Keyboard Extension
//
// The extension only records into durable queues. The host app is the sole
// network uploader, avoiding extension-lifecycle and cross-process lock races.

import Foundation
import OSGKeyboardShared

final class AnalyticsExtensionService: Sendable {
    static let shared = AnalyticsExtensionService()

    let client: any AnalyticsClient
    let keyboardUsageRecorder: any KeyboardUsageRecording

    private init() {
        let environment = Self.environment
        let runtime = AnalyticsRuntime.keyboardExtension(
            environment: environment,
            uploadConfiguration: AnalyticsUploadConfiguration(endpoint: Self.endpoint)
        )
        let keyboardUsageRuntime = KeyboardUsageRuntime(
            environment: environment,
            analyticsRepository: runtime.repository,
            uploadConfiguration: KeyboardUsageUploadConfiguration(
                endpoint: Self.keyboardUsageEndpoint
            )
        )
        client = runtime.client
        keyboardUsageRecorder = keyboardUsageRuntime.recorder
    }

    func recordPresentation(hasFullAccess _: Bool) {
        client.recordSessionActivity()
        client.recordKeyboardActivated()
    }

    func keyboardWillDisappear() {}

    private static let endpoint = URL(
        string: "https://account.osglab.com/v1/analytics/events"
    )!

    private static let keyboardUsageEndpoint = URL(
        string: "https://account.osglab.com/v1/analytics/keyboard-usage"
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
