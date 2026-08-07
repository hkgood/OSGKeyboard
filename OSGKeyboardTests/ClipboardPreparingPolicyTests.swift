// ClipboardPreparingPolicyTests.swift
// OSGKeyboardTests
//
// Decision-matrix coverage for clipboard prepare stuck / double-start bugs.

import XCTest
@testable import OSGKeyboardShared

final class ClipboardPreparingPolicyTests: XCTestCase {

    // MARK: - Restore (paste-alert recreate)

    func testRestoreAwaitExistingWhenStartAlreadyIssued() {
        XCTAssertEqual(
            ClipboardPreparingPolicy.restoreAction(
                hasStartIssued: true,
                phase: .idle
            ),
            .awaitExistingStart
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.restoreAction(
                hasStartIssued: true,
                phase: .error
            ),
            .awaitExistingStart
        )
    }

    func testRestorePreferVoiceOnlyWhenNoClaim() {
        XCTAssertEqual(
            ClipboardPreparingPolicy.restoreAction(
                hasStartIssued: false,
                phase: .idle
            ),
            .preferVoiceOnly,
            "Cold-start return must not auto-start recording"
        )
    }

    func testRestoreRefreshOnlyWhenAlreadyLive() {
        for phase: ClipboardPreparingPhase in [
            .requestingPermissions, .recording, .processing
        ] {
            XCTAssertEqual(
                ClipboardPreparingPolicy.restoreAction(
                    hasStartIssued: true,
                    phase: phase
                ),
                .refreshOnly
            )
        }
    }

    /// Exact device bug: Allow Paste recreates keyboard while claim exists.
    func testPasteAlertReopenMustNotPreferVoiceOnlyWhenClaimed() {
        let action = ClipboardPreparingPolicy.restoreAction(
            hasStartIssued: true,
            phase: .idle
        )
        XCTAssertNotEqual(action, .preferVoiceOnly)
        XCTAssertEqual(action, .awaitExistingStart)
    }

    func testHostGateNeverAutoRecordsAfterWarmup() {
        XCTAssertEqual(
            ClipboardPreparingPolicy.hostGateAction(micPressAction: .startRecording),
            .startRecordingNow
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.hostGateAction(micPressAction: .openHostColdStart),
            .openHostColdStart
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.hostGateAction(
                micPressAction: .waitForHostReady(recordWhenReady: true)
            ),
            .waitForHost,
            "Clipboard must ignore recordWhenReady and require a second long-press"
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.hostGateAction(micPressAction: .ignore),
            .ignore
        )
    }

    func testMicChromeGreyWhilePreparingBlueOnlyAfterConfirm() {
        XCTAssertEqual(
            ClipboardPreparingPolicy.micChrome(
                isClipboardUtterance: true,
                phase: .requestingPermissions,
                awaitingHostConfirm: true
            ),
            .preparingDisabled
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.micChrome(
                isClipboardUtterance: true,
                phase: .recording,
                awaitingHostConfirm: false
            ),
            .recordingBlue
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.micChrome(
                isClipboardUtterance: false,
                phase: .recording,
                awaitingHostConfirm: false
            ),
            .none
        )
        // Paste-acquire (idle + active flag) must not go blue.
        XCTAssertEqual(
            ClipboardPreparingPolicy.micChrome(
                isClipboardUtterance: true,
                phase: .idle,
                awaitingHostConfirm: false
            ),
            .none
        )
    }

    // MARK: - Stop while preparing

    func testTapDuringPreparingAbortsInsteadOfWaitingForever() {
        XCTAssertEqual(
            ClipboardPreparingPolicy.stopWhilePreparing(awaitingHostConfirm: true),
            .abortPreparing
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.stopWhilePreparing(awaitingHostConfirm: false),
            .requestStop
        )
    }

    // MARK: - Recover while preparing

    func testRecoverConfirmsMatchingRecordingUtterance() {
        let id = UUID()
        XCTAssertEqual(
            ClipboardPreparingPolicy.recoverWhilePreparing(
                awaitingHostConfirm: true,
                currentUtteranceId: id,
                hostBusyUtteranceId: id,
                hostReason: .recording,
                hasTerminalFailureForCurrent: false
            ),
            .confirmRecording
        )
    }

    func testRecoverAdoptsSiblingOnDoubleStart() {
        let ours = UUID()
        let sibling = UUID()
        XCTAssertEqual(
            ClipboardPreparingPolicy.recoverWhilePreparing(
                awaitingHostConfirm: true,
                currentUtteranceId: ours,
                hostBusyUtteranceId: sibling,
                hostReason: .recording,
                hasTerminalFailureForCurrent: false
            ),
            .adoptSibling(sibling)
        )
        XCTAssertEqual(
            ClipboardPreparingPolicy.recoverWhilePreparing(
                awaitingHostConfirm: true,
                currentUtteranceId: ours,
                hostBusyUtteranceId: sibling,
                hostReason: .processing,
                hasTerminalFailureForCurrent: false
            ),
            .adoptSibling(sibling)
        )
    }

    func testRecoverAbortsOnHostTerminalFailure() {
        let id = UUID()
        XCTAssertEqual(
            ClipboardPreparingPolicy.recoverWhilePreparing(
                awaitingHostConfirm: true,
                currentUtteranceId: id,
                hostBusyUtteranceId: nil,
                hostReason: nil,
                hasTerminalFailureForCurrent: true
            ),
            .abortForHostFailure
        )
    }

    func testRecoverDoesNothingWhenNotAwaiting() {
        XCTAssertEqual(
            ClipboardPreparingPolicy.recoverWhilePreparing(
                awaitingHostConfirm: false,
                currentUtteranceId: UUID(),
                hostBusyUtteranceId: UUID(),
                hostReason: .recording,
                hasTerminalFailureForCurrent: true
            ),
            .none
        )
    }

    // MARK: - Ensure single startRecording

    func testEnsureStartSkipsWhenAlreadyInFlight() {
        let id = UUID()
        XCTAssertEqual(
            ClipboardPreparingPolicy.ensureStartAction(
                issuedUtteranceId: id,
                isFlowRecording: true,
                currentUtteranceId: id,
                hostBusyUtteranceId: nil,
                hostReason: nil,
                hostReadyWithSession: true
            ),
            .alreadyInFlight
        )
    }

    func testEnsureStartAdoptsHostBusyInsteadOfSecondWrite() {
        let issued = UUID()
        let busy = UUID()
        XCTAssertEqual(
            ClipboardPreparingPolicy.ensureStartAction(
                issuedUtteranceId: issued,
                isFlowRecording: false,
                currentUtteranceId: issued,
                hostBusyUtteranceId: busy,
                hostReason: .recording,
                hostReadyWithSession: true
            ),
            .adoptBusy(busy, .recording)
        )
    }

    func testEnsureStartWritesOnceWhenHostReady() {
        let id = UUID()
        XCTAssertEqual(
            ClipboardPreparingPolicy.ensureStartAction(
                issuedUtteranceId: id,
                isFlowRecording: false,
                currentUtteranceId: id,
                hostBusyUtteranceId: nil,
                hostReason: nil,
                hostReadyWithSession: true
            ),
            .writeStart(id)
        )
    }

    func testEnsureStartWaitsWhenHostNotReady() {
        let id = UUID()
        XCTAssertEqual(
            ClipboardPreparingPolicy.ensureStartAction(
                issuedUtteranceId: id,
                isFlowRecording: false,
                currentUtteranceId: id,
                hostBusyUtteranceId: nil,
                hostReason: nil,
                hostReadyWithSession: false
            ),
            .waitForHost
        )
    }

    /// Simulate paste-alert reopen loop: claim → restore → ensure must not
    /// produce two writeStart for the same issued id across polls.
    func testDoubleStartStressMatrixTwentyRounds() {
        for round in 1...20 {
            let claim = UUID()
            // First long-press claims.
            XCTAssertTrue(claim.uuidString.isEmpty == false)

            // Restore after Allow Paste / cold-start:
            // - with claim → awaitExistingStart
            // - without claim → preferVoiceOnly (no auto-record)
            let restoreClaimed = ClipboardPreparingPolicy.restoreAction(
                hasStartIssued: true,
                phase: .idle
            )
            XCTAssertEqual(restoreClaimed, .awaitExistingStart, "round \(round)")
            let restoreWarm = ClipboardPreparingPolicy.restoreAction(
                hasStartIssued: false,
                phase: .idle
            )
            XCTAssertEqual(restoreWarm, .preferVoiceOnly, "round \(round)")

            XCTAssertEqual(
                ClipboardPreparingPolicy.hostGateAction(micPressAction: .openHostColdStart),
                .openHostColdStart,
                "round \(round)"
            )

            // First ensure writes once.
            let first = ClipboardPreparingPolicy.ensureStartAction(
                issuedUtteranceId: claim,
                isFlowRecording: false,
                currentUtteranceId: claim,
                hostBusyUtteranceId: nil,
                hostReason: nil,
                hostReadyWithSession: true
            )
            XCTAssertEqual(first, .writeStart(claim), "round \(round)")

            // Second ensure (same process or restore) must not write again.
            let second = ClipboardPreparingPolicy.ensureStartAction(
                issuedUtteranceId: claim,
                isFlowRecording: true,
                currentUtteranceId: claim,
                hostBusyUtteranceId: nil,
                hostReason: nil,
                hostReadyWithSession: true
            )
            XCTAssertEqual(second, .alreadyInFlight, "round \(round)")

            // Sibling double-start on host → adopt, never another write.
            let sibling = UUID()
            let adopt = ClipboardPreparingPolicy.ensureStartAction(
                issuedUtteranceId: claim,
                isFlowRecording: false,
                currentUtteranceId: claim,
                hostBusyUtteranceId: sibling,
                hostReason: .recording,
                hostReadyWithSession: true
            )
            XCTAssertEqual(adopt, .adoptBusy(sibling, .recording), "round \(round)")

            // Mic-not-ready failure while preparing → abort.
            XCTAssertEqual(
                ClipboardPreparingPolicy.recoverWhilePreparing(
                    awaitingHostConfirm: true,
                    currentUtteranceId: claim,
                    hostBusyUtteranceId: nil,
                    hostReason: nil,
                    hasTerminalFailureForCurrent: true
                ),
                .abortForHostFailure,
                "round \(round)"
            )

            // User tap while preparing cancels.
            XCTAssertEqual(
                ClipboardPreparingPolicy.stopWhilePreparing(awaitingHostConfirm: true),
                .abortPreparing,
                "round \(round)"
            )
        }
    }
}
