// FlowKeyboardPoliciesTests.swift
// OSGKeyboardTests
//
// Hermetic regression coverage for keyboard↔host Flow decision helpers.

import XCTest
@testable import OSGKeyboardShared

final class FlowKeyboardPoliciesTests: XCTestCase {

    // MARK: - Host warming

    func testHostBusyReasonIsNotPreparingSession() {
        XCTAssertTrue(FlowKeyboardHostWarming.isHostBusy(reason: .recording))
        XCTAssertTrue(FlowKeyboardHostWarming.isHostBusy(reason: .processing))
        XCTAssertTrue(FlowKeyboardHostWarming.isHostBusy(reason: .awaitingDelivery))
        XCTAssertFalse(FlowKeyboardHostWarming.isHostBusy(reason: .starting))
        XCTAssertFalse(FlowKeyboardHostWarming.isHostBusy(reason: .ready))

        let warming = FlowKeyboardHostWarming.isHostWarming(
            hostReady: false,
            hostBusy: true,
            sessionActive: true,
            hostReachable: true,
            isPendingFlowStart: false,
            withinReadyGrace: false,
            snapshotReason: .recording
        )
        XCTAssertFalse(warming, "busy must not look like preparing/starting")
    }

    func testStartingReasonWithActiveSessionIsPreparing() {
        let warming = FlowKeyboardHostWarming.isHostWarming(
            hostReady: false,
            hostBusy: false,
            sessionActive: true,
            hostReachable: false,
            isPendingFlowStart: false,
            withinReadyGrace: false,
            snapshotReason: .starting
        )
        XCTAssertTrue(warming)
    }

    func testRecentReadyGraceDoesNotForcePreparingSession() {
        // withinReadyGrace used to OR into warming and flash yellow after each
        // utterance; sticky ready must hold green instead.
        let warming = FlowKeyboardHostWarming.isHostWarming(
            hostReady: false,
            hostBusy: false,
            sessionActive: true,
            hostReachable: false,
            isPendingFlowStart: false,
            withinReadyGrace: true,
            snapshotReason: .starting
        )
        // Still warming via reason=.starting when not yet proven ready on the
        // keyboard side; grace alone must not be the trigger.
        XCTAssertTrue(warming)

        XCTAssertTrue(
            FlowKeyboardHostWarming.shouldHoldReady(
                hostReady: false,
                hostBusy: false,
                sessionActive: true,
                sessionProvenReady: true,
                isPendingFlowStart: false,
                snapshotReason: .starting
            ),
            "proven-ready session must hold green through starting flaps"
        )
        XCTAssertTrue(
            FlowKeyboardHostWarming.shouldHoldReady(
                hostReady: false,
                hostBusy: true,
                sessionActive: true,
                sessionProvenReady: true,
                isPendingFlowStart: false,
                snapshotReason: .awaitingDelivery
            ),
            "ack lag awaitingDelivery must not drop to preparingSession"
        )
        XCTAssertFalse(
            FlowKeyboardHostWarming.shouldHoldReady(
                hostReady: false,
                hostBusy: true,
                sessionActive: true,
                sessionProvenReady: true,
                isPendingFlowStart: false,
                snapshotReason: .recording
            ),
            "live recording must not be masked as sticky ready"
        )
        XCTAssertFalse(
            FlowKeyboardHostWarming.shouldHoldReady(
                hostReady: false,
                hostBusy: false,
                sessionActive: true,
                sessionProvenReady: false,
                isPendingFlowStart: true,
                snapshotReason: .starting
            ),
            "cold start pending must still show preparing"
        )
    }

    func testHeldReadySuppressesWarming() {
        let hold = FlowKeyboardHostWarming.shouldHoldReady(
            hostReady: false,
            hostBusy: false,
            sessionActive: true,
            sessionProvenReady: true,
            isPendingFlowStart: false,
            snapshotReason: .starting
        )
        XCTAssertTrue(hold)
        let warming = FlowKeyboardHostWarming.isHostWarming(
            hostReady: true, // effective ready after hold
            hostBusy: false,
            sessionActive: true,
            hostReachable: true,
            isPendingFlowStart: false,
            withinReadyGrace: true,
            snapshotReason: .starting
        )
        XCTAssertFalse(warming)
    }

    // MARK: - Adopt busy

    func testReAdoptsRecordingAfterExtensionProcessLoss() {
        let sessionId = UUID()
        let utteranceId = UUID()
        let snapshot = FlowReadySnapshot(
            sessionId: sessionId,
            ready: false,
            reason: .recording,
            engineMode: "cloud",
            localeId: "zh-Hans",
            busyUtteranceId: utteranceId,
            hostGeneration: "gen-1"
        )
        let action = FlowKeyboardAdoptBusyPolicy.decide(
            snapshot: snapshot,
            currentHostGeneration: "gen-1",
            isFlowRecording: false,
            isAwaitingFlowResult: false,
            lastConsumedUtteranceId: nil,
            lastStoppedUtteranceId: nil
        )
        XCTAssertEqual(
            action,
            .adoptRecording(sessionId: sessionId, utteranceId: utteranceId)
        )
    }

    func testIgnoresConsumedAndStoppedUtteranceIds() {
        let sessionId = UUID()
        let utteranceId = UUID()
        let snapshot = FlowReadySnapshot(
            sessionId: sessionId,
            ready: false,
            reason: .recording,
            engineMode: "cloud",
            localeId: "zh-Hans",
            busyUtteranceId: utteranceId,
            hostGeneration: "gen-1"
        )
        XCTAssertEqual(
            FlowKeyboardAdoptBusyPolicy.decide(
                snapshot: snapshot,
                currentHostGeneration: "gen-1",
                isFlowRecording: false,
                isAwaitingFlowResult: false,
                lastConsumedUtteranceId: utteranceId,
                lastStoppedUtteranceId: nil
            ),
            .none
        )
        XCTAssertEqual(
            FlowKeyboardAdoptBusyPolicy.decide(
                snapshot: snapshot,
                currentHostGeneration: "gen-1",
                isFlowRecording: false,
                isAwaitingFlowResult: false,
                lastConsumedUtteranceId: nil,
                lastStoppedUtteranceId: utteranceId
            ),
            .none
        )
    }

    func testIgnoresDeadHostGenerationSnapshot() {
        let snapshot = FlowReadySnapshot(
            sessionId: UUID(),
            ready: false,
            reason: .recording,
            engineMode: "cloud",
            localeId: "zh-Hans",
            busyUtteranceId: UUID(),
            hostGeneration: "old-gen"
        )
        XCTAssertEqual(
            FlowKeyboardAdoptBusyPolicy.decide(
                snapshot: snapshot,
                currentHostGeneration: "live-gen",
                isFlowRecording: false,
                isAwaitingFlowResult: false,
                lastConsumedUtteranceId: nil,
                lastStoppedUtteranceId: nil
            ),
            .none
        )
    }

    func testClearsStickyProcessingWhenHostNoLongerBusy() {
        let snapshot = FlowReadySnapshot(
            sessionId: UUID(),
            ready: true,
            reason: .ready,
            engineMode: "cloud",
            localeId: "zh-Hans"
        )
        XCTAssertEqual(
            FlowKeyboardAdoptBusyPolicy.decide(
                snapshot: snapshot,
                currentHostGeneration: nil,
                isFlowRecording: false,
                isAwaitingFlowResult: false,
                lastConsumedUtteranceId: nil,
                lastStoppedUtteranceId: nil
            ),
            .clearStickyProcessing
        )
    }

    // MARK: - Result matcher

    func testMatchingResultRequiresAlignedSessionAndUtterance() {
        let sessionId = UUID()
        let utteranceId = UUID()
        let result = FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            status: .final,
            text: "ok"
        )
        XCTAssertNotNil(
            FlowKeyboardResultMatcher.matchingResult(
                latest: result,
                activeSessionId: sessionId,
                currentUtteranceId: utteranceId
            )
        )
        XCTAssertNil(
            FlowKeyboardResultMatcher.matchingResult(
                latest: result,
                activeSessionId: UUID(),
                currentUtteranceId: utteranceId
            )
        )
        XCTAssertNil(
            FlowKeyboardResultMatcher.matchingResult(
                latest: result,
                activeSessionId: sessionId,
                currentUtteranceId: UUID()
            )
        )
    }

    func testTerminalFailureStatuses() {
        let base = FlowResult(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 1,
            status: .final
        )
        XCTAssertFalse(FlowKeyboardResultMatcher.isTerminalFailure(base))
        XCTAssertTrue(
            FlowKeyboardResultMatcher.isTerminalFailure(
                FlowResult(
                    sessionId: base.sessionId,
                    utteranceId: base.utteranceId,
                    commandSeq: 1,
                    status: .error
                )
            )
        )
        XCTAssertTrue(
            FlowKeyboardResultMatcher.isTerminalFailure(
                FlowResult(
                    sessionId: base.sessionId,
                    utteranceId: base.utteranceId,
                    commandSeq: 1,
                    status: .timeout
                )
            )
        )
        XCTAssertTrue(
            FlowKeyboardResultMatcher.isTerminalFailure(
                FlowResult(
                    sessionId: base.sessionId,
                    utteranceId: base.utteranceId,
                    commandSeq: 1,
                    status: .aborted
                )
            )
        )
    }

    // MARK: - Command gate

    func testIgnoresStaleSessionAndNonIncreasingSeq() {
        let sessionId = UUID()
        XCTAssertEqual(
            FlowCommandGatekeeper.decide(
                commandSessionId: UUID(),
                commandSeq: 2,
                activeSessionId: sessionId,
                lastHandledCommandSeq: 1
            ),
            .rejectWrongSession
        )
        XCTAssertEqual(
            FlowCommandGatekeeper.decide(
                commandSessionId: sessionId,
                commandSeq: 1,
                activeSessionId: sessionId,
                lastHandledCommandSeq: 1
            ),
            .rejectStaleSeq
        )
        XCTAssertEqual(
            FlowCommandGatekeeper.decide(
                commandSessionId: sessionId,
                commandSeq: 2,
                activeSessionId: sessionId,
                lastHandledCommandSeq: 1
            ),
            .accept
        )
    }

    // MARK: - Orphan reconcile

    func testClearsOrphanedRecordingStateWhenHostInactive() {
        XCTAssertEqual(
            FlowOrphanRecordingReconciler.decide(
                isHostStale: false,
                isActive: false,
                recordingState: .recording
            ),
            .clearOrphanedRecording(.recording)
        )
        XCTAssertEqual(
            FlowOrphanRecordingReconciler.decide(
                isHostStale: true,
                isActive: false,
                recordingState: .idle
            ),
            .clearZombieSession
        )
        XCTAssertEqual(
            FlowOrphanRecordingReconciler.decide(
                isHostStale: false,
                isActive: true,
                recordingState: .recording
            ),
            .none
        )
    }
}
