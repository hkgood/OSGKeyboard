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

    func testSessionActiveRequiresFreshHeartbeat() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActive(duration: 60, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))

        let staleHeartbeat = Date().timeIntervalSince1970 - 10
        defaults.set(staleHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)
        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
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

    func testDarwinNotificationPostsWithoutCrashing() {
        FlowSessionDarwin.postSessionChanged()
    }
}
