// FlowCaptureTailDrainTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowCaptureTailDrainTests: XCTestCase {

    private let policy = FlowCaptureTailDrainPolicy(
        silenceRMSThreshold: 0.02,
        silenceDurationSeconds: 0.2,
        maxDrainSeconds: 1.0
    )

    func testDrainFinishesAfterContinuousSilence() {
        let tracker = FlowCaptureDrainTracker()
        let start = Date().timeIntervalSince1970
        tracker.beginDrain(now: start)

        tracker.noteAudio(samples: [0.001, 0.001], policy: policy, now: start + 0.05)

        let silentAt = start + 0.1
        let decision = tracker.shouldFinish(policy: policy, now: silentAt + policy.silenceDurationSeconds)
        XCTAssertTrue(decision.finished)
        XCTAssertTrue(decision.endedBySilence)
    }

    func testDrainFinishesAtMaxDurationEvenWithoutSilence() {
        let tracker = FlowCaptureDrainTracker()
        let start = Date().timeIntervalSince1970
        tracker.beginDrain(now: start)

        tracker.noteAudio(samples: [0.5, 0.4], policy: policy, now: start + 0.05)
        tracker.noteAudio(samples: [0.45, 0.42], policy: policy, now: start + 0.4)

        let decision = tracker.shouldFinish(policy: policy, now: start + policy.maxDrainSeconds)
        XCTAssertTrue(decision.finished)
        XCTAssertFalse(decision.endedBySilence)
    }

    func testRMSDetectsAudibleSamples() {
        XCTAssertGreaterThan(
            FlowCaptureDrainTracker.rms(of: [0.2, 0.18, 0.15]),
            policy.silenceRMSThreshold
        )
        XCTAssertLessThan(
            FlowCaptureDrainTracker.rms(of: [0.001, 0.0005]),
            policy.silenceRMSThreshold
        )
    }
}
