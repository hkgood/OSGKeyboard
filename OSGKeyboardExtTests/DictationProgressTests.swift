// DictationProgressTests.swift
// OSGKeyboard · Keyboard Extension Tests
//
// Staged microphone progress fill: monotonic, never completes on its own,
// steps forward at the ASR → polish milestone, and learns polish latency.

@testable import OSGKeyboardShared
import XCTest

final class DictationProgressTests: XCTestCase {
    private let start: TimeInterval = 1_000

    private func timeline(polishingAfter seconds: TimeInterval? = nil,
                          expected: TimeInterval = 3) -> DictationProgressTimeline {
        var timeline = DictationProgressTimeline(utteranceID: UUID(), transcribingStartedAt: start)
        if let seconds {
            timeline.markPolishing(at: start + seconds, characterCount: 40, expectedSeconds: expected)
        }
        return timeline
    }

    func testTranscribingStaysBelowCeiling() {
        let ceiling = DictationProgressEstimator.transcribingCeiling
        XCTAssertLessThan(DictationProgressEstimator.fraction(for: timeline(), at: start + 3), ceiling)
        // Long waits converge onto the ceiling (exp underflows to exactly it), never past it.
        XCTAssertLessThanOrEqual(DictationProgressEstimator.fraction(for: timeline(), at: start + 60), ceiling)
        XCTAssertEqual(DictationProgressEstimator.fraction(for: timeline(), at: start), 0)
    }

    func testFractionIsMonotonicAcrossMilestone() {
        let subject = timeline(polishingAfter: 0.8)
        var previous = -1.0
        for step in 0...600 {
            let value = DictationProgressEstimator.fraction(for: subject, at: start + Double(step) * 0.05)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testPolishingStepsPastFloorAndNeverCompletes() {
        let subject = timeline(polishingAfter: 0.8)
        let afterBlend = DictationProgressEstimator.fraction(for: subject, at: start + 0.8 + 0.3)
        XCTAssertGreaterThanOrEqual(afterBlend, DictationProgressEstimator.polishingFloor)
        let muchLater = DictationProgressEstimator.fraction(for: subject, at: start + 600)
        XCTAssertLessThan(muchLater, 1)
        XCTAssertLessThanOrEqual(muchLater, DictationProgressEstimator.polishingCeiling)
    }

    func testRepeatedRawReadyKeepsFirstMilestone() {
        var subject = timeline(polishingAfter: 1)
        subject.markPolishing(at: start + 5, characterCount: 999, expectedSeconds: 30)
        XCTAssertEqual(subject.polishingStartedAt, start + 1)
        XCTAssertEqual(subject.polishCharacterCount, 40)
    }

    func testCalibrationMovesTowardObservedLatencyWithinBounds() throws {
        let suite = "DictationProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calibration = DictationPolishLatencyCalibration(defaults: defaults)

        let initial = calibration.expectedSeconds(forCharacterCount: 100)
        calibration.record(observedSeconds: 8, characterCount: 100)
        XCTAssertGreaterThan(calibration.expectedSeconds(forCharacterCount: 100), initial)

        for _ in 0..<50 { calibration.record(observedSeconds: 0.01, characterCount: 0) }
        XCTAssertEqual(
            calibration.overheadSeconds,
            DictationPolishLatencyCalibration.overheadRange.lowerBound,
            accuracy: 0.001
        )
        calibration.record(observedSeconds: -1, characterCount: 0)
        XCTAssertEqual(
            calibration.overheadSeconds,
            DictationPolishLatencyCalibration.overheadRange.lowerBound,
            accuracy: 0.001
        )
    }

    @MainActor
    func testTimelineClearsWhenProcessingEnds() {
        let state = KeyboardState()
        state.phase = .processing
        state.dictationProgress = timeline()
        state.phase = .processing
        XCTAssertNotNil(state.dictationProgress)
        state.phase = .idle
        XCTAssertNil(state.dictationProgress)
    }
}
