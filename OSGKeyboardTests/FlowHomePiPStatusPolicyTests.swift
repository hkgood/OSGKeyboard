// FlowHomePiPStatusPolicyTests.swift
// OSGKeyboardTests

@testable import OSGKeyboard
import XCTest

final class FlowHomePiPStatusPolicyTests: XCTestCase {

    func testPreparingAndRecoveringExposeAttemptProgress() {
        XCTAssertEqual(
            descriptor(for: .preparing(attempt: 1, total: 3)),
            .progress(
                localizationKey: "home.flow.preparingProgress",
                attempt: 1,
                total: 3
            )
        )
        XCTAssertEqual(
            descriptor(for: .recovering(attempt: 2, total: 3)),
            .progress(
                localizationKey: "home.flow.recoveringProgress",
                attempt: 2,
                total: 3
            )
        )
    }

    func testTakeoverAndFailureUseActionableStatuses() {
        XCTAssertEqual(
            descriptor(for: .waitingForForeground),
            .text(localizationKey: "home.flow.waitingForForeground")
        )
        XCTAssertEqual(
            descriptor(for: .failed(.systemRejected)),
            .text(localizationKey: "home.flow.recoveryFailed")
        )
    }

    func testActiveSessionDoesNotClaimReadyWithoutReadyContract() {
        XCTAssertEqual(
            FlowHomePiPStatusPolicy.descriptor(
                lifecycle: .active,
                isStarting: false,
                isRecording: false,
                isProcessing: false,
                isActive: true,
                isHostReady: false
            ),
            .text(localizationKey: "home.flow.notReady")
        )
        XCTAssertEqual(
            FlowHomePiPStatusPolicy.descriptor(
                lifecycle: .active,
                isStarting: false,
                isRecording: false,
                isProcessing: false,
                isActive: true,
                isHostReady: true
            ),
            .text(localizationKey: "home.flow.label")
        )
    }

    func testRetryAppearsOnlyForRecoverableFailureWithPermissions() {
        XCTAssertTrue(
            FlowHomePiPStatusPolicy.canRetry(
                lifecycle: .failed(.timedOut),
                needsPermissionSetup: false
            )
        )
        XCTAssertFalse(
            FlowHomePiPStatusPolicy.canRetry(
                lifecycle: .failed(.timedOut),
                needsPermissionSetup: true
            )
        )
        XCTAssertFalse(
            FlowHomePiPStatusPolicy.canRetry(
                lifecycle: .recovering(attempt: 1, total: 3),
                needsPermissionSetup: false
            )
        )
    }

    private func descriptor(
        for lifecycle: FlowPiPLifecycleState
    ) -> FlowHomePiPStatusDescriptor {
        FlowHomePiPStatusPolicy.descriptor(
            lifecycle: lifecycle,
            isStarting: false,
            isRecording: false,
            isProcessing: false,
            isActive: false,
            isHostReady: false
        )
    }
}
