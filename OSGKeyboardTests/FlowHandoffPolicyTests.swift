// FlowHandoffPolicyTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowHandoffPolicyTests: XCTestCase {

    // MARK: - shouldTreatHostAsAlive / shouldOpenHostColdStart

    func testAliveWhenSessionActiveAndReachable() {
        XCTAssertTrue(
            FlowHandoffPolicy.shouldTreatHostAsAlive(
                sessionActive: true,
                hostReachable: true,
                hostStale: false,
                withinReadyGrace: false
            )
        )
        XCTAssertFalse(
            FlowHandoffPolicy.shouldOpenHostColdStart(
                sessionActive: true,
                hostReachable: true,
                hostStale: false,
                withinReadyGrace: false
            )
        )
    }

    func testAliveWhenSessionActiveWithinReadyGrace() {
        // Finalize race: ready flap but we were ready moments ago.
        XCTAssertTrue(
            FlowHandoffPolicy.shouldTreatHostAsAlive(
                sessionActive: true,
                hostReachable: false,
                hostStale: false,
                withinReadyGrace: true
            )
        )
        XCTAssertFalse(
            FlowHandoffPolicy.shouldOpenHostColdStart(
                sessionActive: true,
                hostReachable: false,
                hostStale: false,
                withinReadyGrace: true
            )
        )
    }

    func testAliveWhenSessionActiveEvenIfHeartbeatBrieflyStale() {
        // Session flag still valid and not zombie → wait, do not jump.
        XCTAssertTrue(
            FlowHandoffPolicy.shouldTreatHostAsAlive(
                sessionActive: true,
                hostReachable: false,
                hostStale: false,
                withinReadyGrace: false
            )
        )
        XCTAssertFalse(
            FlowHandoffPolicy.shouldOpenHostColdStart(
                sessionActive: true,
                hostReachable: false,
                hostStale: false,
                withinReadyGrace: false
            )
        )
    }

    func testDeadWhenHostStale() {
        XCTAssertFalse(
            FlowHandoffPolicy.shouldTreatHostAsAlive(
                sessionActive: true,
                hostReachable: false,
                hostStale: true,
                withinReadyGrace: true
            )
        )
        XCTAssertTrue(
            FlowHandoffPolicy.shouldOpenHostColdStart(
                sessionActive: true,
                hostReachable: false,
                hostStale: true,
                withinReadyGrace: true
            )
        )
    }

    func testDeadWhenNoSession() {
        XCTAssertFalse(
            FlowHandoffPolicy.shouldTreatHostAsAlive(
                sessionActive: false,
                hostReachable: false,
                hostStale: false,
                withinReadyGrace: false
            )
        )
        XCTAssertTrue(
            FlowHandoffPolicy.shouldOpenHostColdStart(
                sessionActive: false,
                hostReachable: false,
                hostStale: false,
                withinReadyGrace: false
            )
        )
    }

    // MARK: - micPressAction

    func testMicPressReadyStartsRecording() {
        let action = FlowHandoffPolicy.micPressAction(
            availability: .ready,
            sessionActive: true,
            hostReachable: true,
            hostStale: false,
            withinReadyGrace: false
        )
        XCTAssertEqual(action, .startRecording)
    }

    func testMicPressPreparingSessionWaitsAndRecords() {
        // 0.5.2 regression: preparingSession must NOT open cold start.
        let action = FlowHandoffPolicy.micPressAction(
            availability: .unavailable(.preparingSession),
            sessionActive: true,
            hostReachable: true,
            hostStale: false,
            withinReadyGrace: false
        )
        XCTAssertEqual(action, .waitForHostReady(recordWhenReady: true))
    }

    func testMicPressHostNotReadyWithLiveSessionWaits() {
        // User log scenario: finalize just completed, stale ready=false frame.
        let action = FlowHandoffPolicy.micPressAction(
            availability: .unavailable(.hostNotReady),
            sessionActive: true,
            hostReachable: true,
            hostStale: false,
            withinReadyGrace: true
        )
        XCTAssertEqual(action, .waitForHostReady(recordWhenReady: true))
    }

    func testMicPressHostNotReadyWithActiveSessionNoGraceStillWaits() {
        let action = FlowHandoffPolicy.micPressAction(
            availability: .unavailable(.hostNotReady),
            sessionActive: true,
            hostReachable: false,
            hostStale: false,
            withinReadyGrace: false
        )
        XCTAssertEqual(action, .waitForHostReady(recordWhenReady: true))
    }

    func testMicPressHostNotReadyWhenDeadOpensColdStart() {
        let action = FlowHandoffPolicy.micPressAction(
            availability: .unavailable(.hostNotReady),
            sessionActive: false,
            hostReachable: false,
            hostStale: false,
            withinReadyGrace: false
        )
        XCTAssertEqual(action, .openHostColdStart)
    }

    func testMicPressHostNotReadyWhenStaleOpensColdStart() {
        let action = FlowHandoffPolicy.micPressAction(
            availability: .unavailable(.hostNotReady),
            sessionActive: true,
            hostReachable: false,
            hostStale: true,
            withinReadyGrace: false
        )
        XCTAssertEqual(action, .openHostColdStart)
    }

    func testMicPressBusyPhasesIgnored() {
        XCTAssertEqual(
            FlowHandoffPolicy.micPressAction(
                availability: .recording,
                sessionActive: true,
                hostReachable: true,
                hostStale: false,
                withinReadyGrace: false
            ),
            .ignore
        )
        XCTAssertEqual(
            FlowHandoffPolicy.micPressAction(
                availability: .processing,
                sessionActive: true,
                hostReachable: true,
                hostStale: false,
                withinReadyGrace: false
            ),
            .ignore
        )
    }

    // MARK: - coldStartOverlayDecision

    func testOverlaySilencedWhenAlreadyReady() {
        // User log: active=true hostReady=true coldStart=true → must silence.
        XCTAssertEqual(
            FlowHandoffPolicy.coldStartOverlayDecision(
                sessionIsActive: true,
                hostIsReady: true,
                isUtteranceBusy: false
            ),
            .silence
        )
    }

    func testOverlaySilencedWhenUtteranceBusy() {
        XCTAssertEqual(
            FlowHandoffPolicy.coldStartOverlayDecision(
                sessionIsActive: true,
                hostIsReady: false,
                isUtteranceBusy: true
            ),
            .silence
        )
    }

    func testOverlayPresentedForTrueColdStart() {
        XCTAssertEqual(
            FlowHandoffPolicy.coldStartOverlayDecision(
                sessionIsActive: false,
                hostIsReady: false,
                isUtteranceBusy: false
            ),
            .present
        )
    }

    func testOverlayPresentedWhenActiveButNeedsRecovery() {
        // Engine hiccup: session up, not ready, not busy → preparing UI OK.
        XCTAssertEqual(
            FlowHandoffPolicy.coldStartOverlayDecision(
                sessionIsActive: true,
                hostIsReady: false,
                isUtteranceBusy: false
            ),
            .present
        )
    }

    // MARK: - debouncer + proactive launch flag

    func testProactiveAutoLaunchDisabled() {
        XCTAssertFalse(FlowHandoffPolicy.allowsProactiveHostAutoLaunch)
    }

    func testDebouncerIgnoresSingleDeadSample() {
        var debouncer = FlowColdStartDebouncer()
        XCTAssertFalse(debouncer.observe(hostTrulyDead: true))
        XCTAssertEqual(debouncer.consecutiveDeadSamples, 1)
        XCTAssertTrue(debouncer.observe(hostTrulyDead: true))
        XCTAssertEqual(debouncer.consecutiveDeadSamples, 2)
    }

    func testDebouncerResetsOnAliveSample() {
        var debouncer = FlowColdStartDebouncer()
        XCTAssertFalse(debouncer.observe(hostTrulyDead: true))
        XCTAssertFalse(debouncer.observe(hostTrulyDead: false))
        XCTAssertEqual(debouncer.consecutiveDeadSamples, 0)
        XCTAssertFalse(debouncer.observe(hostTrulyDead: true))
    }

    func testDebouncerReset() {
        var debouncer = FlowColdStartDebouncer()
        _ = debouncer.observe(hostTrulyDead: true)
        debouncer.reset()
        XCTAssertEqual(debouncer.consecutiveDeadSamples, 0)
    }

    /// Mirrors the user log: session still active after finalize, ready flap
    /// must not justify startflow even when availability reads hostNotReady.
    func testFinalizeRaceDoesNotOpenColdStart() {
        let suite = "group.com.osgkeyboard.shared.tests.handoff.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let sessionId = UUID()
        FlowSessionBridge.markSessionActive(duration: 1_800, sessionId: sessionId, defaults: defaults)
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: sessionId,
                ready: false,
                reason: .processing,
                engineMode: "local",
                localeId: "zh-Hans",
                busyUtteranceId: UUID(),
                sessionExpiresAt: FlowSessionBridge.sessionExpiresAt(defaults: defaults),
                hostGeneration: FlowSessionBridge.currentHostGeneration(defaults: defaults)
            ),
            defaults: defaults
        )

        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))

        let action = FlowHandoffPolicy.micPressAction(
            availability: .unavailable(.hostNotReady),
            sessionActive: FlowSessionBridge.isSessionActive(defaults: defaults),
            hostReachable: FlowSessionBridge.isHostReachable(defaults: defaults),
            hostStale: FlowSessionBridge.isHostStale(defaults: defaults),
            withinReadyGrace: true
        )
        XCTAssertEqual(action, .waitForHostReady(recordWhenReady: true))

        XCTAssertEqual(
            FlowHandoffPolicy.coldStartOverlayDecision(
                sessionIsActive: true,
                hostIsReady: true,
                isUtteranceBusy: false
            ),
            .silence
        )
    }
}
