// FlowSessionBridgeTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowSessionBridgeTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.flow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testSessionActiveSurvivesStaleHeartbeatWhileNotExpired() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 60, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))

        let staleHeartbeat = Date().timeIntervalSince1970 - 10
        defaults.set(staleHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)
        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReachable(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostStale(defaults: defaults))
    }

    func testHostStaleWhenHeartbeatVeryOld() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReachable(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
    }

    func testClearIfHostStaleRemovesZombieSession() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        FlowSessionBridge.setRecordingState(.stopped, defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        XCTAssertTrue(FlowSessionBridge.clearIfHostStale(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .idle)
    }

    func testHostStaleWhenSessionActiveButNoHeartbeat() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: FlowSessionKeys.flowSessionActive)
        defaults.set(Date().timeIntervalSince1970 + 3_600, forKey: FlowSessionKeys.flowSessionExpires)

        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.clearIfHostStale(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
    }

    func testSessionInactiveWhenExpired() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 1, defaults: defaults)
        let expired = Date().timeIntervalSince1970 - 5
        defaults.set(expired, forKey: FlowSessionKeys.flowSessionExpires)
        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReachable(defaults: defaults))
    }

    func testRecordingStateRoundTrip() {
        let defaults = makeDefaults()
        FlowSessionBridge.setRecordingState(.recording, defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .recording)

        FlowSessionBridge.setRecordingState(.stopped, defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .stopped)
    }

    func testConsumeTranscriptionResultClearsKey() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionResult("hello", defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.consumeTranscriptionResult(defaults: defaults), "hello")
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionResult(defaults: defaults))
    }

    func testConsumeTranscriptionDeliveryIncludesPolishWarning() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionResult(
            "raw text",
            polishWarning: "polish failed",
            defaults: defaults
        )
        let delivery = FlowSessionBridge.consumeTranscriptionDelivery(defaults: defaults)
        XCTAssertEqual(delivery?.text, "raw text")
        XCTAssertEqual(delivery?.polishWarning, "polish failed")
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionDelivery(defaults: defaults))
    }

    func testClearFlowStateRemovesSessionKeys() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(defaults: defaults)
        FlowSessionBridge.storeTranscriptionResult("x", defaults: defaults)
        FlowSessionBridge.clearFlowState(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.flowSessionActive))
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionResult(defaults: defaults))
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .idle)
    }

    func testRemainingSessionDurationNilWhenExpired() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 1, defaults: defaults)
        XCTAssertNotNil(FlowSessionBridge.remainingSessionDuration(defaults: defaults))

        let expired = Date().timeIntervalSince1970 - 5
        defaults.set(expired, forKey: FlowSessionKeys.flowSessionExpires)
        XCTAssertNil(FlowSessionBridge.remainingSessionDuration(defaults: defaults))
    }

    func testConsumeTranscriptionErrorIncludesKind() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionError(
            "no speech",
            kind: .noSpeech,
            defaults: defaults
        )
        let error = FlowSessionBridge.consumeTranscriptionError(defaults: defaults)
        XCTAssertEqual(error?.message, "no speech")
        XCTAssertEqual(error?.kind, .noSpeech)
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionError(defaults: defaults))
    }

    func testTranscriptionPartialRoundTrip() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionPartial("你好世界", defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.transcriptionPartial(defaults: defaults), "你好世界")
        FlowSessionBridge.storeTranscriptionResult("final", defaults: defaults)
        XCTAssertNil(FlowSessionBridge.transcriptionPartial(defaults: defaults))
    }

    func testDarwinNotificationPostsWithoutCrashing() {
        FlowSessionDarwin.postSessionChanged()
        FlowSessionDarwin.postCommandChanged()
        FlowSessionDarwin.postHostReadyChanged()
    }

    func testHostReadyRequiresExplicitContract() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 60, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))

        FlowSessionBridge.setHostReady(true, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testHostReadyFalseWhenHeartbeatStale() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))

        let staleHeartbeat = Date().timeIntervalSince1970 - 10
        defaults.set(staleHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testHeartbeatRefreshKeepsHostReadyPublished() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)

        FlowSessionBridge.writeHeartbeat(defaults: defaults)

        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testClearFlowStateClearsHostReady() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)
        FlowSessionBridge.clearFlowState(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.flowHostReady))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testFlowCommandRoundTrip() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        let command = FlowCommand(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 42,
            action: .startRecording,
            localeId: "zh-Hans",
            createdAt: 123
        )

        FlowSessionBridge.writeCommand(command, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.latestCommand(defaults: defaults), command)
    }

    func testFlowResultRoundTripPreservesUtteranceIdentity() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        let result = FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 43,
            status: .final,
            text: "hello",
            warning: "raw fallback",
            createdAt: 124
        )

        FlowSessionBridge.writeResult(result, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.latestResult(defaults: defaults), result)
        FlowSessionBridge.clearResult(defaults: defaults)
        XCTAssertNil(FlowSessionBridge.latestResult(defaults: defaults))
    }

    func testFlowAckRoundTrip() {
        let defaults = makeDefaults()
        let ack = FlowAck(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 44,
            consumedAt: 125
        )

        FlowSessionBridge.writeAck(ack, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.latestAck(defaults: defaults), ack)
    }

    func testNotReadySnapshotDoesNotRefreshHeartbeat() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        // A host stuck in a failed cold start writes not-ready snapshots on
        // every engine flap; those must NOT revive the heartbeat, or zombie
        // detection is postponed forever.
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: UUID(),
                ready: false,
                reason: .waitingForAudioProof,
                engineMode: "local",
                localeId: "zh-Hans"
            ),
            defaults: defaults
        )

        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
    }

    func testBusySnapshotStillRefreshesHeartbeat() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        let staleHeartbeat = Date().timeIntervalSince1970 - 10
        defaults.set(staleHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        // Recording/processing proves the host is alive even though the
        // snapshot is not "ready" — the heartbeat must keep flowing so the
        // keyboard does not declare a mid-utterance host dead.
        let sessionId = UUID()
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: sessionId,
                ready: false,
                reason: .recording,
                engineMode: "local",
                localeId: "zh-Hans",
                busyUtteranceId: UUID()
            ),
            defaults: defaults
        )

        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))
        // Not-ready busy snapshots must remain readable so the keyboard can
        // distinguish "host is recording" from "host is still starting".
        let snap = FlowSessionBridge.readySnapshot(defaults: defaults)
        XCTAssertEqual(snap?.reason, .recording)
        XCTAssertEqual(snap?.ready, false)
        XCTAssertEqual(snap?.sessionId, sessionId)
    }

    func testNotReadyStartingSnapshotIsRetainedWithoutRevivingHeartbeat() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: UUID(),
                ready: false,
                reason: .waitingForAudioProof,
                engineMode: "local",
                localeId: "zh-Hans"
            ),
            defaults: defaults
        )

        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
        XCTAssertEqual(
            FlowSessionBridge.readySnapshot(defaults: defaults)?.reason,
            .waitingForAudioProof
        )
    }

    func testStaleGenerationSnapshotIsNotReady() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let now = Date().timeIntervalSince1970
        FlowSessionBridge.rotateHostGeneration(defaults: defaults)
        let liveGeneration = FlowSessionBridge.currentHostGeneration(defaults: defaults)
        FlowSessionBridge.markSessionActive(duration: 60, sessionId: sessionId, defaults: defaults)
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: sessionId,
                ready: true,
                reason: .ready,
                heartbeatAt: now,
                readyAt: now,
                engineMode: "local",
                localeId: "zh-Hans",
                hostGeneration: liveGeneration
            ),
            defaults: defaults
        )
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))

        // Host relaunches (force-quit path) → new generation. The old ready
        // snapshot must be void instantly, without waiting out the 60 s
        // heartbeat-zombie window.
        FlowSessionBridge.rotateHostGeneration(defaults: defaults)
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testClearFlowStateOnHostLaunchPreservesPendingHost() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 3_600, defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)
        FlowSessionBridge.setPendingHostBundleId("com.example.host", defaults: defaults)

        FlowSessionBridge.clearFlowStateOnHostLaunch(defaults: defaults)

        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
        // The startflow scene-delegate write happens before the session
        // manager exists — launch reconciliation must not eat it.
        XCTAssertEqual(
            FlowSessionBridge.pendingHostBundleId(defaults: defaults),
            "com.example.host"
        )
    }

    func testRotateHostGenerationReturnsPreviousToken() {
        let defaults = makeDefaults()
        XCTAssertNil(FlowSessionBridge.rotateHostGeneration(defaults: defaults))
        let first = FlowSessionBridge.currentHostGeneration(defaults: defaults)
        XCTAssertNotNil(first)

        let previous = FlowSessionBridge.rotateHostGeneration(defaults: defaults)
        XCTAssertEqual(previous, first)
        XCTAssertNotEqual(FlowSessionBridge.currentHostGeneration(defaults: defaults), first)
    }

    func testReadySnapshotDrivesHostReady() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let now = Date().timeIntervalSince1970
        FlowSessionBridge.markSessionActive(duration: 60, sessionId: sessionId, defaults: defaults)
        let snapshot = FlowReadySnapshot(
            sessionId: sessionId,
            ready: true,
            reason: .ready,
            heartbeatAt: now,
            readyAt: now,
            audioProofAt: now,
            engineMode: "local",
            localeId: "zh-Hans",
            sessionExpiresAt: now + 60
        )

        FlowSessionBridge.writeReadySnapshot(snapshot, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.readySnapshot(defaults: defaults), snapshot)
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testClearFlowStateRemovesProtocolPayloads() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowSessionBridge.writeCommand(
            FlowCommand(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: 1,
                action: .startRecording,
                localeId: "en-US"
            ),
            defaults: defaults
        )
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: 1,
                status: .partial,
                text: "hello"
            ),
            defaults: defaults
        )

        FlowSessionBridge.clearFlowState(defaults: defaults)

        XCTAssertNil(FlowSessionBridge.latestCommand(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.latestResult(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.readySnapshot(defaults: defaults))
    }
}
