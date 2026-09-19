// InternalDiagnosticsUploader.swift
// OSGKeyboard · Main App
//
// Uploads MetricKit crash / hang diagnostics to the account service — from
// INTERNAL BUILDS ONLY (local Debug and TestFlight).
//
// Why internal-only, deliberately:
//   • TestFlight already collects ordinary crashes through Apple, but NOT
//     keyboard-extension memory kills — the system does not classify those as
//     crashes, so they never reach App Store Connect. MetricKit is the only
//     way to see them, and there is no API to push MetricKit payloads into
//     TestFlight, so they have to go to our own endpoint.
//   • Restricting the upload to internal builds means no App Store user's
//     device sends anything, which keeps this out of the production privacy
//     review while still answering "why did the keyboard disappear?" during
//     the beta.
//
// Payloads carry crash metadata only — exception type, signal, termination
// reason, binary names, a truncated call stack — never audio, transcripts,
// clipboard content, prompts, or API keys. `FlowFailureLogStore` redacts the
// reason and context values before they are ever written to disk.

import Foundation
import OSGKeyboardShared

/// Host-only preference controlling internal diagnostics upload. Stored in
/// `UserDefaults.standard` (not the App Group) because only the containing app
/// ever uploads — the keyboard extension has no network role here.
enum InternalDiagnosticsUploadPreference {
    static let storageKey = "internalDiagnosticsUploadEnabled"

    /// Defaults to ON for internal builds: a beta tester who never finds the
    /// toggle should still produce the data the beta exists to gather. App
    /// Store builds ignore this entirely — see `InternalDiagnosticsUploader`.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: storageKey)
    }
}

/// Outcome of one upload sweep. Surfaced in the internal diagnostics screen so
/// a tester can tell "nothing to send" from "the backend isn't there yet".
enum InternalDiagnosticsUploadStatus: Equatable, Sendable {
    case disabled
    /// Analytics are switched off, so there is no installation identifier to
    /// attach and nothing is sent.
    case noInstallationIdentifier
    case idle(pending: Int)
    case uploaded(count: Int)
    case endpointUnavailable
    case retryScheduled(pending: Int, after: Date)
    case failed(statusCode: Int?)
}

actor InternalDiagnosticsUploader {
    static let shared = InternalDiagnosticsUploader()

    /// Endpoint follows the existing account-service convention
    /// (`/v1/analytics/events`, `/v1/analytics/keyboard-usage`). Change this one
    /// constant if the backend lands on a different route.
    static let defaultEndpoint = URL(
        string: "https://account.osglab.com/v1/analytics/diagnostics"
    )!

    /// Reports sent per sweep. Crash payloads are far larger than analytics
    /// events, and a tester returning from a crash loop should not spend their
    /// launch uploading.
    private static let maximumReportsPerSweep = 5
    /// Remembered IDs are only needed long enough to outlive the store's own
    /// 40-report / 14-day retention.
    private static let maximumRememberedIDs = 200
    private static let baseRetryDelay: TimeInterval = 60
    private static let maximumRetryDelay: TimeInterval = 6 * 60 * 60

    private struct UploadState: Codable {
        var uploadedReportIDs: [UUID] = []
        var consecutiveFailures: Int = 0
        var nextAttemptAfter: Date?
        /// Set when the backend answers 404/410. The route does not exist yet;
        /// retrying every launch would be pure noise against their logs.
        var endpointUnavailable: Bool = false
    }

    private let store: FlowFailureLogStore
    private let endpoint: URL
    private let network: any AnalyticsNetworking
    private let bearerProvider: (any AnalyticsBearerProviding)?
    private let isInternalBuild: Bool
    private let isUploadEnabled: @Sendable () -> Bool
    private let installationIdentifier: @Sendable () async -> UUID?
    private let now: @Sendable () -> Date
    private let stateURL: URL?

    private var state = UploadState()
    private var didLoadState = false
    private var sweepInProgress = false

    private(set) var lastStatus: InternalDiagnosticsUploadStatus = .idle(pending: 0)

    init(
        store: FlowFailureLogStore = .shared,
        endpoint: URL = InternalDiagnosticsUploader.defaultEndpoint,
        network: any AnalyticsNetworking = URLSessionAnalyticsNetwork(),
        bearerProvider: (any AnalyticsBearerProviding)? = HostAnalyticsBearerBridge.shared,
        isInternalBuild: Bool = AppDistributionChannel.allowsInternalTools,
        isUploadEnabled: @escaping @Sendable () -> Bool = {
            InternalDiagnosticsUploadPreference.isEnabled
        },
        installationIdentifier: @escaping @Sendable () async -> UUID? = {
            await AnalyticsHostService.shared.installationIdentifierIfEnabled()
        },
        now: @escaping @Sendable () -> Date = Date.init,
        stateURL: URL? = InternalDiagnosticsUploader.defaultStateURL()
    ) {
        self.store = store
        self.endpoint = endpoint
        self.network = network
        self.bearerProvider = bearerProvider
        self.isInternalBuild = isInternalBuild
        self.isUploadEnabled = isUploadEnabled
        self.installationIdentifier = installationIdentifier
        self.now = now
        self.stateURL = stateURL
    }

    static func defaultStateURL() -> URL? {
        FlowFailureLogStore.defaultDirectoryURL()
            .appendingPathComponent("diagnostics-upload-state.json", isDirectory: false)
    }

    /// Safe to call on every launch and every foreground. Returns the status so
    /// the caller does not have to poll for it.
    @discardableResult
    func uploadPendingReports() async -> InternalDiagnosticsUploadStatus {
        guard isInternalBuild, isUploadEnabled() else {
            lastStatus = .disabled
            return .disabled
        }
        guard endpoint.scheme?.lowercased() == "https" else {
            lastStatus = .endpointUnavailable
            return .endpointUnavailable
        }
        guard !sweepInProgress else { return lastStatus }
        sweepInProgress = true
        defer { sweepInProgress = false }

        loadStateIfNeeded()
        if state.endpointUnavailable {
            lastStatus = .endpointUnavailable
            return .endpointUnavailable
        }

        let pending = pendingReports()
        guard !pending.isEmpty else {
            lastStatus = .idle(pending: 0)
            return lastStatus
        }
        if let nextAttempt = state.nextAttemptAfter, now() < nextAttempt {
            lastStatus = .retryScheduled(pending: pending.count, after: nextAttempt)
            return lastStatus
        }

        guard let installationID = await installationIdentifier() else {
            lastStatus = .noInstallationIdentifier
            return lastStatus
        }

        let batch = Array(pending.prefix(Self.maximumReportsPerSweep))
        var token = try? await bearerProvider?.bearerToken()
        var outcome = await send(batch.map(\.report), installationID: installationID, token: token)
        if case .unauthorized = outcome {
            // One refresh, then treat a second 401 as an ordinary failure so a
            // broken session cannot spin here.
            token = try? await bearerProvider?
                .refreshBearerToken(afterUnauthorizedAccessToken: token)
            outcome = await send(batch.map(\.report), installationID: installationID, token: token)
        }

        switch outcome {
        case .success:
            batch.forEach { remember($0.report.reportID) }
            state.consecutiveFailures = 0
            state.nextAttemptAfter = nil
            persistState()
            lastStatus = .uploaded(count: batch.count)
            OSGDiag.log("diagnosticsUpload sweep uploaded=\(batch.count)", category: "diagnostics")
            return lastStatus
        case .endpointMissing:
            state.endpointUnavailable = true
            persistState()
            lastStatus = .endpointUnavailable
            return lastStatus
        case .rejected(let statusCode):
            // The server understood the body and refused it. Resending the same
            // bytes would fail identically, so drop the batch rather than pin
            // the queue behind it forever.
            batch.forEach { remember($0.report.reportID) }
            persistState()
            OSGDiag.log(
                "diagnosticsUpload rejected status=\(statusCode) dropped=\(batch.count)",
                category: "diagnostics"
            )
            lastStatus = .idle(pending: pendingReports().count)
            return lastStatus
        case .unauthorized:
            return finishWithFailure(statusCode: 401)
        case .transient(let statusCode):
            return finishWithFailure(statusCode: statusCode)
        }
    }

    /// Count of MetricKit reports still waiting, for the internal status row.
    func pendingReportCount() -> Int {
        loadStateIfNeeded()
        return pendingReports().count
    }

    /// Clears the circuit breaker and backoff so a tester can retry immediately
    /// once the backend route is deployed.
    func resetDeliveryState() {
        loadStateIfNeeded()
        state.endpointUnavailable = false
        state.consecutiveFailures = 0
        state.nextAttemptAfter = nil
        persistState()
        lastStatus = .idle(pending: pendingReports().count)
    }

    // MARK: - Sending

    private enum SendOutcome {
        case success
        case unauthorized
        case endpointMissing
        case rejected(statusCode: Int)
        case transient(statusCode: Int?)
    }

    private func send(
        _ reports: [FlowStartupFailureReport],
        installationID: UUID,
        token: String?
    ) async -> SendOutcome {
        guard !reports.isEmpty,
              let body = encodeBody(for: reports, installationID: installationID) else {
            // Nothing a retry can fix.
            return .rejected(statusCode: 0)
        }
        var headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            // Lets the backend dedupe if a response is lost after it committed.
            // The server keys idempotency per report as well, so this is a
            // belt-and-braces hint for proxies rather than the guarantee.
            "Idempotency-Key": reports[0].reportID.uuidString.lowercased()
        ]
        if let token, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }

        do {
            let response = try await network.send(
                AnalyticsHTTPRequest(url: endpoint, headers: headers, body: body)
            )
            switch response.statusCode {
            case 200..<300:
                return .success
            case 401, 403:
                return .unauthorized
            case 404, 410:
                return .endpointMissing
            case 408, 429:
                return .transient(statusCode: response.statusCode)
            case 400..<500:
                return .rejected(statusCode: response.statusCode)
            default:
                return .transient(statusCode: response.statusCode)
            }
        } catch {
            return .transient(statusCode: nil)
        }
    }

    private func encodeBody(
        for reports: [FlowStartupFailureReport],
        installationID: UUID
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = DiagnosticsUploadRequest(
            installationId: installationID.uuidString.lowercased(),
            channel: "INTERNAL",
            reports: reports.map(DiagnosticsUploadReport.init(report:))
        )
        return try? encoder.encode(payload)
    }

    /// Mirrors `POST /v1/analytics/diagnostics` on the account service. That
    /// endpoint decodes strictly (`ignoreUnknownKeys = false`), so adding a
    /// field here without shipping the server first turns every upload into a
    /// 400 — keep the two in lockstep.
    private struct DiagnosticsUploadRequest: Encodable {
        let installationId: String
        let channel: String
        let reports: [DiagnosticsUploadReport]
    }

    private struct DiagnosticsUploadReport: Encodable {
        let clientReportId: String
        let kind: String
        let process: String
        let capturedAt: String
        let exceptionType: String?
        let exceptionCode: String?
        let signal: String?
        let terminationReason: String?
        let hangMillis: Int64?
        let topBinaries: String?
        let callStackDigest: String?
        let appVersion: String?
        let buildNumber: String?
        let osVersion: String?
        let deviceType: String?

        init(report: FlowStartupFailureReport) {
            let context = report.context
            clientReportId = report.reportID.uuidString.lowercased()
            kind = Self.wireKind(context["kind"])
            process = report.process == .keyboard ? "KEYBOARD" : "APP"
            capturedAt = report.capturedAt.formatted(.iso8601)
            exceptionType = context["exceptionType"]
            exceptionCode = context["exceptionCode"]
            signal = context["signal"]
            terminationReason = context["terminationReason"]
            hangMillis = context["hangMillis"].flatMap(Int64.init)
            topBinaries = context["topBinaries"]
            callStackDigest = context["callStackDigest"]
            appVersion = report.appVersion
            buildNumber = report.buildNumber
            // MetricKit's own OS version is more precise than the host's, and
            // was already normalised when the report was captured.
            osVersion = context["osVersion"]
            deviceType = context["deviceType"]
        }

        /// The stored reports use the MetricKit-shaped names; the wire uses the
        /// server's SCREAMING_SNAKE enum.
        private static func wireKind(_ value: String?) -> String {
            switch value {
            case "hang": return "HANG"
            case "cpuException": return "CPU_EXCEPTION"
            case "diskWriteException": return "DISK_WRITE_EXCEPTION"
            default: return "CRASH"
            }
        }
    }

    // MARK: - State

    private func pendingReports() -> [(url: URL, report: FlowStartupFailureReport)] {
        let sent = Set(state.uploadedReportIDs)
        return store.reportsWithURLs().filter { entry in
            entry.report.context["source"] == "metricKit"
                && !sent.contains(entry.report.reportID)
        }
    }

    private func remember(_ reportID: UUID) {
        state.uploadedReportIDs.append(reportID)
        if state.uploadedReportIDs.count > Self.maximumRememberedIDs {
            state.uploadedReportIDs.removeFirst(
                state.uploadedReportIDs.count - Self.maximumRememberedIDs
            )
        }
    }

    private func finishWithFailure(statusCode: Int?) -> InternalDiagnosticsUploadStatus {
        state.consecutiveFailures += 1
        let delay = min(
            Self.baseRetryDelay * pow(2, Double(state.consecutiveFailures - 1)),
            Self.maximumRetryDelay
        )
        let nextAttempt = now().addingTimeInterval(delay)
        state.nextAttemptAfter = nextAttempt
        persistState()
        OSGDiag.log(
            "diagnosticsUpload deferred status=\(statusCode.map(String.init) ?? "none") "
                + "failures=\(state.consecutiveFailures)",
            category: "diagnostics"
        )
        lastStatus = .retryScheduled(pending: pendingReports().count, after: nextAttempt)
        return lastStatus
    }

    private func loadStateIfNeeded() {
        guard !didLoadState else { return }
        didLoadState = true
        guard let stateURL, let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        state = (try? decoder.decode(UploadState.self, from: data)) ?? UploadState()
    }

    private func persistState() {
        guard let stateURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: stateURL.path
        )
    }
}
