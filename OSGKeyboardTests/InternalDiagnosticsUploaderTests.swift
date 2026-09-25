// InternalDiagnosticsUploaderTests.swift
// OSGKeyboard · Tests
//
// The uploader only ever runs on internal builds, so it gets very little
// organic exercise — which is exactly why its edge cases need pinning. The
// behaviours that matter: never send from an App Store build, never send the
// same report twice, and never hammer a backend route that does not exist yet.

import Foundation
@testable import OSGKeyboard
@testable import OSGKeyboardShared
import XCTest

final class InternalDiagnosticsUploaderTests: XCTestCase {
    private var directory: URL!
    private var store: FlowFailureLogStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-upload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        store = FlowFailureLogStore(
            directoryURL: directory,
            additionalReadDirectoryURLs: [],
            process: .host
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        store = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func seedMetricKitReport(kind: String = "crash") -> Bool {
        store.persistStartupFailure(
            reason: "metrickit.\(kind): exc=1 signal=9",
            context: ["source": "metricKit", "kind": kind]
        ) != nil
    }

    @discardableResult
    private func seedFlowReport() -> Bool {
        store.persistStartupFailure(
            reason: "startWatchdogTimeout",
            context: ["stage": "hostOpen"]
        ) != nil
    }

    private static let installationID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!

    private func makeUploader(
        network: AnalyticsQueueNetwork,
        isInternalBuild: Bool = true,
        isUploadEnabled: Bool = true,
        installationID: UUID? = InternalDiagnosticsUploaderTests.installationID,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> InternalDiagnosticsUploader {
        InternalDiagnosticsUploader(
            store: store,
            endpoint: URL(string: "https://example.invalid/v1/analytics/diagnostics")!,
            network: network,
            bearerProvider: nil,
            isInternalBuild: isInternalBuild,
            isUploadEnabled: { isUploadEnabled },
            installationIdentifier: { installationID },
            now: now,
            stateURL: directory.appendingPathComponent("state.json")
        )
    }

    private static func ok() -> AnalyticsQueueNetwork.Outcome {
        .response(AnalyticsHTTPResponse(statusCode: 202, headers: [:], body: Data()))
    }

    private static func status(_ code: Int) -> AnalyticsQueueNetwork.Outcome {
        .response(AnalyticsHTTPResponse(statusCode: code, headers: [:], body: Data()))
    }

    // MARK: - Gating

    func testAppStoreBuildsNeverUpload() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok()])
        let uploader = makeUploader(network: network, isInternalBuild: false)

        let status = await uploader.uploadPendingReports()

        XCTAssertEqual(status, .disabled)
        let requests = await network.requests()
        XCTAssertTrue(requests.isEmpty, "an App Store build must not make a request")
    }

    func testDisabledPreferenceStopsUpload() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok()])
        let uploader = makeUploader(network: network, isUploadEnabled: false)

        let status = await uploader.uploadPendingReports()

        XCTAssertEqual(status, .disabled)
        let requests = await network.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    // MARK: - Scope

    func testOnlyMetricKitReportsAreUploaded() async throws {
        XCTAssertTrue(seedFlowReport())
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok(), Self.ok()])
        let uploader = makeUploader(network: network)

        let status = await uploader.uploadPendingReports()

        XCTAssertEqual(status, .uploaded(count: 1))
        let requests = await network.requests()
        // Flow startup reports are a local debugging aid and were never part of
        // this decision; only the MetricKit crash data leaves the device.
        XCTAssertEqual(requests.count, 1)
    }

    func testUploadedReportIsNotSentAgain() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok(), Self.ok()])
        let uploader = makeUploader(network: network)

        _ = await uploader.uploadPendingReports()
        let second = await uploader.uploadPendingReports()

        XCTAssertEqual(second, .idle(pending: 0))
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testRequestMatchesTheAccountServiceContract() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok()])
        let uploader = makeUploader(network: network)

        _ = await uploader.uploadPendingReports()

        let requests = await network.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        // A response lost after the server committed must not create a duplicate.
        XCTAssertNotNil(request.headers["Idempotency-Key"])

        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        // The endpoint decodes strictly, so the key set has to match exactly.
        XCTAssertEqual(Set(decoded.keys), ["installationId", "channel", "reports"])
        XCTAssertEqual(decoded["channel"] as? String, "INTERNAL")
        XCTAssertEqual(
            decoded["installationId"] as? String,
            Self.installationID.uuidString.lowercased()
        )

        let reports = try XCTUnwrap(decoded["reports"] as? [[String: Any]])
        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report["kind"] as? String, "CRASH")
        XCTAssertEqual(report["process"] as? String, "APP")
        XCTAssertNotNil(report["clientReportId"] as? String)
        // `capturedAt` must be a UTC ISO-8601 instant or the server 400s.
        let capturedAt = try XCTUnwrap(report["capturedAt"] as? String)
        XCTAssertTrue(capturedAt.hasSuffix("Z"), capturedAt)
        XCTAssertTrue(
            Set(report.keys).isSubset(of: Self.serverReportKeys),
            "unexpected keys: \(Set(report.keys).subtracting(Self.serverReportKeys))"
        )
    }

    /// Mirrors `DiagnosticReportRequest` on the account service. The server sets
    /// `ignoreUnknownKeys = false`, so anything outside this set is a 400.
    private static let serverReportKeys: Set<String> = [
        "clientReportId", "kind", "process", "capturedAt",
        "exceptionType", "exceptionCode", "signal", "terminationReason",
        "hangMillis", "topBinaries", "callStackDigest",
        "appVersion", "buildNumber", "osVersion", "deviceType"
    ]

    func testHangReportsMapToTheServerEnum() async throws {
        XCTAssertTrue(seedMetricKitReport(kind: "hang"))
        let network = AnalyticsQueueNetwork([Self.ok()])
        let uploader = makeUploader(network: network)

        _ = await uploader.uploadPendingReports()

        let requests = await network.requests()
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(requests.first).body) as? [String: Any]
        )
        let reports = try XCTUnwrap(decoded["reports"] as? [[String: Any]])
        XCTAssertEqual(reports.first?["kind"] as? String, "HANG")
    }

    func testPendingReportsAreSentAsOneBatch() async throws {
        XCTAssertTrue(seedMetricKitReport())
        XCTAssertTrue(seedMetricKitReport())
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok()])
        let uploader = makeUploader(network: network)

        let status = await uploader.uploadPendingReports()

        XCTAssertEqual(status, .uploaded(count: 3))
        let requests = await network.requests()
        // One request, not one per report — the endpoint takes a batch.
        XCTAssertEqual(requests.count, 1)
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(requests.first).body) as? [String: Any]
        )
        XCTAssertEqual((decoded["reports"] as? [[String: Any]])?.count, 3)
    }

    func testAnalyticsOptOutStopsUploadInsteadOfMintingAnIdentifier() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok()])
        let uploader = makeUploader(network: network, installationID: nil)

        let status = await uploader.uploadPendingReports()

        // A tester who turned analytics off has said they do not want a stable
        // device id leaving the machine; that answer holds here too.
        XCTAssertEqual(status, .noInstallationIdentifier)
        let requests = await network.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    // MARK: - Failure handling

    func testMissingBackendRouteStopsRetrying() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.status(404), Self.ok()])
        let uploader = makeUploader(network: network)

        let first = await uploader.uploadPendingReports()
        XCTAssertEqual(first, .endpointUnavailable)

        // The route is not deployed yet. Retrying every launch would be noise
        // in their logs and would never succeed on its own.
        let second = await uploader.uploadPendingReports()
        XCTAssertEqual(second, .endpointUnavailable)
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testResetDeliveryStateAllowsRetryAfterBackendLands() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.status(404), Self.ok()])
        let uploader = makeUploader(network: network)
        _ = await uploader.uploadPendingReports()

        await uploader.resetDeliveryState()
        let status = await uploader.uploadPendingReports()

        XCTAssertEqual(status, .uploaded(count: 1))
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 2)
    }

    func testServerErrorSchedulesBackoffAndKeepsTheReport() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.status(503), Self.ok()])
        let now = Date(timeIntervalSince1970: 1_000_000)
        let uploader = makeUploader(network: network, now: { now })

        guard case .retryScheduled(let pending, let after) =
                await uploader.uploadPendingReports() else {
            return XCTFail("expected a retry to be scheduled after a 503")
        }
        XCTAssertEqual(pending, 1)
        XCTAssertGreaterThan(after, now)

        // Still inside the backoff window: no second request.
        _ = await uploader.uploadPendingReports()
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testBackoffExpiryLetsTheReportThrough() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.status(503), Self.ok()])
        nonisolated(unsafe) var clock = Date(timeIntervalSince1970: 1_000_000)
        let uploader = makeUploader(network: network, now: { clock })

        _ = await uploader.uploadPendingReports()
        clock = clock.addingTimeInterval(3_600)
        let status = await uploader.uploadPendingReports()

        XCTAssertEqual(status, .uploaded(count: 1))
    }

    func testRejectedReportIsDroppedInsteadOfBlockingTheQueue() async throws {
        XCTAssertTrue(seedMetricKitReport(kind: "crash"))
        // 422: the server understood the body and refused it. Resending the
        // identical bytes would fail identically and pin the queue forever.
        let network = AnalyticsQueueNetwork([Self.status(422), Self.ok()])
        let uploader = makeUploader(network: network)

        _ = await uploader.uploadPendingReports()
        let pending = await uploader.pendingReportCount()

        XCTAssertEqual(pending, 0)
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testNetworkFailureIsTransientAndRetries() async throws {
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([.urlError(.notConnectedToInternet), Self.ok()])
        nonisolated(unsafe) var clock = Date(timeIntervalSince1970: 1_000_000)
        let uploader = makeUploader(network: network, now: { clock })

        guard case .retryScheduled = await uploader.uploadPendingReports() else {
            return XCTFail("a dropped connection must not discard the report")
        }
        clock = clock.addingTimeInterval(3_600)
        let status = await uploader.uploadPendingReports()

        XCTAssertEqual(status, .uploaded(count: 1))
    }

    func testPendingCountIgnoresAlreadyUploadedReports() async throws {
        XCTAssertTrue(seedMetricKitReport())
        XCTAssertTrue(seedMetricKitReport())
        let network = AnalyticsQueueNetwork([Self.ok(), Self.ok()])
        let uploader = makeUploader(network: network)

        let before = await uploader.pendingReportCount()
        XCTAssertEqual(before, 2)

        _ = await uploader.uploadPendingReports()
        let after = await uploader.pendingReportCount()
        XCTAssertEqual(after, 0)
    }
}
