// AnalyticsUploadSchedulingTests.swift
// OSGKeyboardTests
//
// Foreground upload policy regression tests for batching and suspension safety.

@testable import OSGKeyboard
import XCTest

final class AnalyticsUploadSchedulingTests: XCTestCase {
    func testCountThresholdCoalescesSignalsIntoOneUpload() async throws {
        let probe = AnalyticsUploadProbe()
        let signal = AnalyticsUploadSignal(
            policy: AnalyticsUploadPolicy(
                eventThreshold: 3,
                flushInterval: .seconds(10),
                activationDelay: .zero,
                maximumBatches: 1
            )
        )
        await signal.install {
            await probe.recordUpload()
        }
        await signal.setActive(true)

        await signal.requestUpload()
        await signal.requestUpload()
        try await Task.sleep(for: .milliseconds(30))
        let countBeforeThreshold = await probe.uploadCount()
        XCTAssertEqual(countBeforeThreshold, 0)

        await signal.requestUpload()
        try await waitUntil { await probe.uploadCount() == 1 }
        let countAfterThreshold = await probe.uploadCount()
        XCTAssertEqual(countAfterThreshold, 1)
    }

    func testIntervalFlushesAQueueBelowThreshold() async throws {
        let probe = AnalyticsUploadProbe()
        let signal = AnalyticsUploadSignal(
            policy: AnalyticsUploadPolicy(
                eventThreshold: 20,
                flushInterval: .milliseconds(20),
                activationDelay: .zero,
                maximumBatches: 1
            )
        )
        await signal.install {
            await probe.recordUpload()
        }
        await signal.setActive(true)

        await signal.requestUpload()

        try await waitUntil { await probe.uploadCount() == 1 }
        let uploadCount = await probe.uploadCount()
        XCTAssertEqual(uploadCount, 1)
    }

    func testInactiveSignalDefersUntilNextActivation() async throws {
        let probe = AnalyticsUploadProbe()
        let signal = AnalyticsUploadSignal(
            policy: AnalyticsUploadPolicy(
                eventThreshold: 2,
                flushInterval: .milliseconds(20),
                activationDelay: .milliseconds(20),
                maximumBatches: 1
            )
        )
        await signal.install {
            await probe.recordUpload()
        }

        await signal.requestUpload()
        await signal.requestUpload()
        try await Task.sleep(for: .milliseconds(40))
        let inactiveUploadCount = await probe.uploadCount()
        XCTAssertEqual(inactiveUploadCount, 0)

        await signal.setActive(true)
        try await waitUntil { await probe.uploadCount() == 1 }
        let activeUploadCount = await probe.uploadCount()
        XCTAssertEqual(activeUploadCount, 1)
    }

    func testLateActionInstallationDoesNotLoseActivationUpload() async throws {
        let probe = AnalyticsUploadProbe()
        let signal = AnalyticsUploadSignal(
            policy: AnalyticsUploadPolicy(
                eventThreshold: 20,
                flushInterval: .seconds(10),
                activationDelay: .milliseconds(20),
                maximumBatches: 1
            )
        )
        await signal.setActive(true)
        await signal.requestActivationUpload()

        await signal.install {
            await probe.recordUpload()
        }

        try await waitUntil { await probe.uploadCount() == 1 }
        let uploadCount = await probe.uploadCount()
        XCTAssertEqual(uploadCount, 1)
    }

    func testPauseCancelsAndWaitsForInFlightUpload() async throws {
        let probe = AnalyticsUploadProbe()
        let signal = AnalyticsUploadSignal(
            policy: AnalyticsUploadPolicy(
                eventThreshold: 1,
                flushInterval: .seconds(10),
                activationDelay: .zero,
                maximumBatches: 1
            )
        )
        await signal.install {
            await probe.recordStarted()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                await probe.recordCancellation()
            }
        }
        await signal.setActive(true)
        await signal.requestUpload()
        try await waitUntil { await probe.didStart() }

        await signal.pauseAndWait()

        let wasCancelled = await probe.wasCancelled()
        XCTAssertTrue(wasCancelled)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for analytics upload state")
    }
}

private actor AnalyticsUploadProbe {
    private var uploads = 0
    private var started = false
    private var cancelled = false

    func recordUpload() {
        uploads += 1
    }

    func uploadCount() -> Int {
        uploads
    }

    func recordStarted() {
        started = true
    }

    func didStart() -> Bool {
        started
    }

    func recordCancellation() {
        cancelled = true
    }

    func wasCancelled() -> Bool {
        cancelled
    }
}
