// FlowSessionPolicyTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowSessionPolicyTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testSkipAppSwitchDefaultsToTrue() {
        let defaults = makeDefaults()
        XCTAssertTrue(FlowSessionPolicy.skipAppSwitch(defaults: defaults))
    }

    func testInactivityDurationDefaultsToFiveMinutes() {
        let defaults = makeDefaults()
        XCTAssertEqual(FlowSessionPolicy.inactivityDuration(defaults: defaults), .fiveMinutes)
        XCTAssertEqual(FlowSessionPolicy.sessionDuration(defaults: defaults), 5 * 60)
    }

    func testShortInactivityDurations() {
        XCTAssertEqual(FlowInactivityDuration.oneMinute.timeInterval, 60)
        XCTAssertEqual(FlowInactivityDuration.fiveMinutes.timeInterval, 5 * 60)
        XCTAssertEqual(FlowInactivityDuration.tenMinutes.timeInterval, 10 * 60)
    }

    func testPiPSessionHasNoInactivityExpiry() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(sessionId: UUID(), defaults: defaults)

        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: FlowSessionKeys.flowSessionExpires))
    }

    func testLegacyExpiryDoesNotInvalidatePersistentSession() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        defaults.set(Date().timeIntervalSince1970 - 30, forKey: FlowSessionKeys.flowSessionExpires)

        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
    }

    func testPendingHostBundleIdRoundTrip() {
        let defaults = makeDefaults()
        FlowSessionBridge.setPendingHostBundleId("com.tencent.xin", defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.pendingHostBundleId(defaults: defaults), "com.tencent.xin")
        FlowSessionBridge.clearPendingHostBundleId(defaults: defaults)
        XCTAssertNil(FlowSessionBridge.pendingHostBundleId(defaults: defaults))
    }
}
