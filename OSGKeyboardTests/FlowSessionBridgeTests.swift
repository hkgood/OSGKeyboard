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
}
