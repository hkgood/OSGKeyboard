// RecordButtonGesturePolicyTests.swift
// OSGKeyboard · Tests

@testable import OSGKeyboardShared
import XCTest

final class RecordButtonGesturePolicyTests: XCTestCase {
    // MARK: - Hold

    func testHoldOnIdleStartsEditAndOwnsThePress() {
        let action = RecordButtonGesturePolicy.holdAction(
            phase: .idleReady,
            isEnabled: true,
            supportsEditLongPress: true
        )
        XCTAssertEqual(action, .beginEditLastInput)
        XCTAssertTrue(RecordButtonGesturePolicy.consumesPress(action))
    }

    func testHoldWithoutEditActionLeavesThePressToTheTap() {
        let action = RecordButtonGesturePolicy.holdAction(
            phase: .idleReady,
            isEnabled: true,
            supportsEditLongPress: false
        )
        XCTAssertEqual(action, .none)
        XCTAssertFalse(RecordButtonGesturePolicy.consumesPress(action))
        // Release still starts plain dictation, so the hold is not a dead key.
        XCTAssertEqual(
            RecordButtonGesturePolicy.tapAction(phase: .idleReady, isEnabled: true),
            .toggle
        )
    }

    func testHoldWhileRecordingStops() {
        let action = RecordButtonGesturePolicy.holdAction(
            phase: .recording,
            isEnabled: true,
            supportsEditLongPress: true
        )
        XCTAssertEqual(action, .toggle)
        XCTAssertTrue(RecordButtonGesturePolicy.consumesPress(action))
    }

    /// The press that opened an edit round is still down when the phase
    /// reaches `.preparing`; a hold there must not end the round it started.
    func testHoldWhilePreparingNeverActsOnItsOwn() {
        let action = RecordButtonGesturePolicy.holdAction(
            phase: .preparing,
            isEnabled: true,
            supportsEditLongPress: true
        )
        XCTAssertEqual(action, .none)
        XCTAssertFalse(RecordButtonGesturePolicy.consumesPress(action))
    }

    func testHoldWhileProcessingIsInert() {
        XCTAssertEqual(
            RecordButtonGesturePolicy.holdAction(
                phase: .processing,
                isEnabled: true,
                supportsEditLongPress: true
            ),
            .none
        )
    }

    // MARK: - Tap

    func testTapCancelsWhilePreparingAndStopsWhileRecording() {
        XCTAssertEqual(RecordButtonGesturePolicy.tapAction(phase: .preparing, isEnabled: true), .toggle)
        XCTAssertEqual(RecordButtonGesturePolicy.tapAction(phase: .recording, isEnabled: true), .toggle)
    }

    func testTapWhileProcessingIsInert() {
        XCTAssertEqual(RecordButtonGesturePolicy.tapAction(phase: .processing, isEnabled: true), .none)
    }

    /// The unavailable mic must stay tappable so the user can reach the reason.
    func testTapOnUnavailableMicStillReportsThrough() {
        XCTAssertEqual(
            RecordButtonGesturePolicy.tapAction(phase: .idleUnavailable, isEnabled: false),
            .toggle
        )
    }

    func testDisabledMicSwallowsTapsInLivePhases() {
        XCTAssertEqual(RecordButtonGesturePolicy.tapAction(phase: .recording, isEnabled: false), .none)
        XCTAssertEqual(RecordButtonGesturePolicy.tapAction(phase: .preparing, isEnabled: false), .none)
    }

    // MARK: - One press, one action

    /// Full edit round: hold arms, phase advances under the finger, and the
    /// release must stay swallowed no matter which phase it lands in.
    func testSinglePressProducesExactlyOneActionAcrossPhaseFlips() {
        let hold = RecordButtonGesturePolicy.holdAction(
            phase: .idleReady,
            isEnabled: true,
            supportsEditLongPress: true
        )
        XCTAssertEqual(hold, .beginEditLastInput)

        var armed = RecordButtonGesturePolicy.consumesPress(hold)
        XCTAssertTrue(armed)

        for landingPhase in [RecordButton.Phase.preparing, .recording] {
            // Release handling: an armed press is consumed, never replayed.
            var delivered: RecordButtonGestureAction = .none
            if armed {
                armed = false
            } else {
                delivered = RecordButtonGesturePolicy.tapAction(
                    phase: landingPhase,
                    isEnabled: true
                )
            }
            XCTAssertEqual(delivered, .none, "release in \(landingPhase) must not act")
            armed = true
        }
    }
}
