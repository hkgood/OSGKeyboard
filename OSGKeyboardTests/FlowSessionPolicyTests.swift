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

    func testKeepAliveModeDefaultsToLiveActivity() {
        let defaults = makeDefaults()
        XCTAssertEqual(FlowSessionPolicy.keepAliveMode(defaults: defaults), .liveActivity)
        XCTAssertTrue(FlowSessionPolicy.usesInactivityExpiry(defaults: defaults))
    }

    func testPiPSessionHasNoInactivityExpiry() {
        let defaults = makeDefaults()
        defaults.set(FlowKeepAliveMode.pictureInPicture.rawValue,
                     forKey: AppGroupConfiguration.Keys.flowKeepAliveMode)
        FlowSessionBridge.markSessionActive(sessionId: UUID(), defaults: defaults)

        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.sessionExpiresAt(defaults: defaults))

        FlowSessionBridge.touchLastActivity(defaults: defaults)
        XCTAssertNil(FlowSessionBridge.sessionExpiresAt(defaults: defaults))
    }

    func testTouchLastActivityExtendsExpiry() {
        let defaults = makeDefaults()
        defaults.set(FlowInactivityDuration.tenMinutes.rawValue, forKey: AppGroupConfiguration.Keys.flowInactivityDuration)
        FlowSessionBridge.markSessionActive(defaults: defaults)

        let staleExpiry = Date().timeIntervalSince1970 + 30
        defaults.set(staleExpiry, forKey: FlowSessionKeys.flowSessionExpires)
        FlowSessionBridge.touchLastActivity(defaults: defaults)

        let refreshed = FlowSessionBridge.sessionExpiresAt(defaults: defaults) ?? 0
        XCTAssertGreaterThan(refreshed, staleExpiry)
    }

    func testPendingHostBundleIdRoundTrip() {
        let defaults = makeDefaults()
        FlowSessionBridge.setPendingHostBundleId("com.tencent.xin", defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.pendingHostBundleId(defaults: defaults), "com.tencent.xin")
        FlowSessionBridge.clearPendingHostBundleId(defaults: defaults)
        XCTAssertNil(FlowSessionBridge.pendingHostBundleId(defaults: defaults))
    }
}
