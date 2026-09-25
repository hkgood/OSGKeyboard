// FlowPiPRecoveryPolicyTests.swift
// OSGKeyboardTests

@testable import OSGKeyboard
import XCTest

final class FlowPiPRecoveryPolicyTests: XCTestCase {

    // MARK: - Reconciliation

    func testNoSessionIntentNeverStartsRecovery() {
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.reconciliationDecision(
                wantsActiveSession: false,
                isAppForeground: true,
                isPictureInPictureActive: false
            ),
            .noSessionIntent
        )
    }

    func testActivePiPIsIdempotent() {
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.reconciliationDecision(
                wantsActiveSession: true,
                isAppForeground: true,
                isPictureInPictureActive: true
            ),
            .alreadyActive
        )
    }

    func testTakeoverWaitsWhileAppIsInBackground() {
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.reconciliationDecision(
                wantsActiveSession: true,
                isAppForeground: false,
                isPictureInPictureActive: false
            ),
            .waitForForeground
        )
    }

    func testReturningToForegroundStartsRecovery() {
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.reconciliationDecision(
                wantsActiveSession: true,
                isAppForeground: true,
                isPictureInPictureActive: false
            ),
            .startRecovery
        )
    }

    // MARK: - Bounded retry

    func testRetryPolicyUsesThreeIncreasingBoundedAttempts() {
        XCTAssertEqual(FlowPiPRecoveryPolicy.maxAttempts, 3)
        XCTAssertEqual(
            (1...FlowPiPRecoveryPolicy.maxAttempts).map {
                FlowPiPRecoveryPolicy.retryDelay(beforeAttempt: $0)
            },
            [0, 0.25, 0.6]
        )
        XCTAssertEqual(FlowPiPRecoveryPolicy.totalBudget, 5)
    }

    func testRetryTimeoutsNeverExceedRemainingBudget() {
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.hostTimeout(attempt: 1, remainingBudget: 0.4),
            0.4
        )
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.hostTimeout(attempt: 2, remainingBudget: 4),
            0.25
        )
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.activeTimeout(remainingBudget: 0.3),
            0.3
        )
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.activeTimeout(remainingBudget: 4),
            1.4
        )
        XCTAssertEqual(
            FlowPiPRecoveryPolicy.activeTimeout(remainingBudget: 0.01),
            0.01
        )
    }

    // MARK: - Late completion safety

    func testCurrentForegroundOperationCanContinue() {
        XCTAssertTrue(
            FlowPiPRecoveryPolicy.canContinue(
                operation: 7,
                currentOperation: 7,
                wantsActiveSession: true,
                isAppForeground: true,
                taskIsCancelled: false
            )
        )
    }

    func testOldGenerationCannotOverwriteNewRecovery() {
        XCTAssertFalse(
            FlowPiPRecoveryPolicy.canContinue(
                operation: 6,
                currentOperation: 7,
                wantsActiveSession: true,
                isAppForeground: true,
                taskIsCancelled: false
            )
        )
    }

    func testExplicitEndPreventsLateRecovery() {
        XCTAssertFalse(
            FlowPiPRecoveryPolicy.canContinue(
                operation: 7,
                currentOperation: 8,
                wantsActiveSession: false,
                isAppForeground: true,
                taskIsCancelled: true
            )
        )
    }

    func testBackgroundAndCancellationBothStopRecovery() {
        XCTAssertFalse(
            FlowPiPRecoveryPolicy.canContinue(
                operation: 7,
                currentOperation: 7,
                wantsActiveSession: true,
                isAppForeground: false,
                taskIsCancelled: false
            )
        )
        XCTAssertFalse(
            FlowPiPRecoveryPolicy.canContinue(
                operation: 7,
                currentOperation: 7,
                wantsActiveSession: true,
                isAppForeground: true,
                taskIsCancelled: true
            )
        )
    }
}

final class FlowPiPLossReportGateTests: XCTestCase {
    /// The backgrounded heartbeat re-evaluates a lost PiP every second. One
    /// incident must produce one report, not one per tick.
    func testRepeatedLossChecksWithinOneEpisodeReportOnce() {
        var gate = FlowPiPLossReportGate()
        XCTAssertTrue(gate.shouldReport())
        for _ in 0..<30 {
            XCTAssertFalse(gate.shouldReport())
        }
    }

    func testPiPBecomingActiveOpensANewEpisode() {
        var gate = FlowPiPLossReportGate()
        XCTAssertTrue(gate.shouldReport())
        XCTAssertFalse(gate.shouldReport())

        gate.pipBecameActive()
        XCTAssertTrue(gate.shouldReport())
    }
}

final class FlowSessionWarningReportGateTests: XCTestCase {
    /// The whole point: a toast raised by a path nobody instrumented must still
    /// produce a report.
    func testUninstrumentedWarningIsReported() {
        var gate = FlowSessionWarningReportGate()
        XCTAssertTrue(
            gate.shouldReport(
                warning: "cannot start voice session",
                lastExplicitReportAt: nil,
                now: Date()
            )
        )
    }

    /// A path that already wrote a precise report must not be double-counted.
    func testWarningIsSuppressedWhenAnExplicitReportJustLanded() {
        var gate = FlowSessionWarningReportGate()
        let now = Date()
        XCTAssertFalse(
            gate.shouldReport(
                warning: "permissions missing",
                lastExplicitReportAt: now.addingTimeInterval(-0.2),
                now: now
            )
        )
    }

    func testOlderExplicitReportDoesNotSuppressANewWarning() {
        var gate = FlowSessionWarningReportGate()
        let now = Date()
        XCTAssertTrue(
            gate.shouldReport(
                warning: "cannot start voice session",
                lastExplicitReportAt: now.addingTimeInterval(
                    -(FlowSessionWarningReportGate.duplicateGrace + 1)
                ),
                now: now
            )
        )
    }

    /// A toast that stays up must not re-report on every state republish.
    func testSameWarningReportsOnlyOncePerEpisode() {
        var gate = FlowSessionWarningReportGate()
        let now = Date()
        XCTAssertTrue(
            gate.shouldReport(warning: "same", lastExplicitReportAt: nil, now: now)
        )
        XCTAssertFalse(
            gate.shouldReport(warning: "same", lastExplicitReportAt: nil, now: now)
        )

        // Cleared and shown again is a genuinely new toast.
        gate.warningCleared()
        XCTAssertTrue(
            gate.shouldReport(warning: "same", lastExplicitReportAt: nil, now: now)
        )
    }
}
