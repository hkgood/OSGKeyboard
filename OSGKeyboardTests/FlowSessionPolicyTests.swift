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

    func testInactivityDurationDefaultsToThirtyMinutes() {
        let defaults = makeDefaults()
        XCTAssertEqual(FlowSessionPolicy.inactivityDuration(defaults: defaults), .thirtyMinutes)
        XCTAssertEqual(FlowSessionPolicy.sessionDuration(defaults: defaults), 30 * 60)
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
