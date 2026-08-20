// FlowUtteranceEndCoordinatorTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class FlowUtteranceEndCoordinatorTests: XCTestCase {

    func testAwaitTailCaptureRunsPostRollAfterSilenceDrain() async {
        let policy = FlowCaptureTailDrainPolicy(
            silenceRMSThreshold: 0.02,
            silenceDurationSeconds: 0.05,
            maxDrainSeconds: 1.0,
            postRollSeconds: 0.08
        )
        let tracker = FlowCaptureDrainTracker()
        let start = Date().timeIntervalSince1970
        tracker.beginDrain(now: start)

        let timing = await FlowUtteranceEndCoordinator.awaitTailCapture(
            tracker: tracker,
            policy: policy,
            pollIntervalNs: 5_000_000
        )

        XCTAssertTrue(timing.endedBySilence)
        XCTAssertGreaterThanOrEqual(timing.postRollDurationSeconds, 0.07)
    }

    func testIOSFlowPresetUsesLongerSilenceAndPostRoll() {
        XCTAssertEqual(FlowCaptureTailDrainPolicy.iosFlow.silenceDurationSeconds, 0.35)
        XCTAssertEqual(FlowCaptureTailDrainPolicy.iosFlow.postRollSeconds, 0.15)
        XCTAssertEqual(FlowCaptureTailDrainPolicy.flowDefault, FlowCaptureTailDrainPolicy.iosFlow)
    }
}
