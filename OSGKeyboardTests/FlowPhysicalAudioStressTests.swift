// FlowPhysicalAudioStressTests.swift
// OSGKeyboardTests
//
// Physical-device release gate for the PiP playback ↔ capture transition.
// Excluded from PR presets because Simulator cannot model Bluetooth HFP.

import AVFoundation
import XCTest
@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared

final class FlowPhysicalAudioStressTests: XCTestCase {
    @MainActor
    func testFiftyCapturePlaybackCyclesRemainStable() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Bluetooth HFP stress requires a physical iPhone")
        #else
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw XCTSkip("Grant microphone permission to OSGKeyboard first")
        }

        let capture = FlowContinuousCapture()
        let initialRSS = OSGDiag.memoryMB()

        for iteration in 1...50 {
            try await capture.start()
            let receivedFrame = await capture.awaitAudioFlowing(timeout: 2)
            XCTAssertTrue(receivedFrame, "No microphone frame in iteration \(iteration)")
            XCTAssertTrue(capture.engineIsLive, "Engine not live in iteration \(iteration)")

            capture.stop(releaseSession: false)
            let playbackReady = await FlowAudioSessionCoordinator.shared.activatePlayback()
            XCTAssertTrue(playbackReady, "PiP playback restore failed in iteration \(iteration)")
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(capture.engineActivationCount, 50)
        XCTAssertEqual(
            capture.routeRecoveryCount,
            0,
            "Stable routeConfigurationChange notifications must not rebuild the engine"
        )

        let growth = OSGDiag.memoryMB() - initialRSS
        XCTAssertLessThan(
            growth,
            80,
            "Fifty audio cycles retained \(String(format: "%.1f", growth)) MB"
        )
        FlowAudioSessionCoordinator.shared.deactivate()
        #endif
    }
}
