// FlowReliabilityTests.swift
// OSGKeyboardTests
//
// Regression coverage for durable cross-process delivery and bounded fallback.

import Foundation
import AVFoundation
import XCTest
@testable import OSGKeyboard
@testable import OSGKeyboardShared
@testable import OSGKeyboardHostSupport

final class FlowReliabilityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.tests.flow-reliability.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCommandJournalPreservesRapidStartAndStop() {
        let sessionId = UUID()
        let utteranceId = UUID()
        let start = FlowCommand(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 100,
            action: .startRecording,
            localeId: "zh-Hans"
        )
        let stop = FlowCommand(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 101,
            action: .stopRecording,
            localeId: "zh-Hans"
        )

        FlowSessionBridge.writeCommand(start, defaults: defaults)
        FlowSessionBridge.writeCommand(stop, defaults: defaults)

        XCTAssertEqual(
            FlowSessionBridge.commands(after: 0, defaults: defaults),
            [start, stop]
        )
    }

    func testAbortInvalidatesInFlightUtteranceStart() {
        let utteranceId = UUID()
        let token = FlowUtteranceStartToken(
            generation: 10,
            utteranceId: utteranceId
        )

        XCTAssertTrue(
            FlowUtteranceLifecyclePolicy.canContinueStart(
                token: token,
                currentGeneration: 10,
                currentUtteranceId: utteranceId,
                terminalUtteranceIds: []
            )
        )
        XCTAssertFalse(
            FlowUtteranceLifecyclePolicy.canContinueStart(
                token: token,
                currentGeneration: 11,
                currentUtteranceId: nil,
                terminalUtteranceIds: [utteranceId]
            )
        )
    }

    func testTerminalUtteranceCannotBeResurrectedByLateStart() {
        let utteranceId = UUID()
        let token = FlowUtteranceStartToken(
            generation: 10,
            utteranceId: utteranceId
        )

        XCTAssertFalse(
            FlowUtteranceLifecyclePolicy.canContinueStart(
                token: token,
                currentGeneration: 10,
                currentUtteranceId: utteranceId,
                terminalUtteranceIds: [utteranceId]
            )
        )
    }

    func testTerminalResultCannotBeDowngradedByLatePartial() {
        let sessionId = UUID()
        let utteranceId = UUID()
        let final = FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            status: .final,
            text: "最终文本",
            rawText: "原始文本",
            revision: 10
        )
        let stalePartial = FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            status: .partial,
            text: "迟到片段",
            revision: 11
        )

        FlowSessionBridge.writeResult(final, defaults: defaults)
        FlowSessionBridge.writeResult(stalePartial, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.latestResult(defaults: defaults), final)
    }

    func testPendingUtteranceSurvivesCoordinatorRecreation() {
        let utteranceId = UUID()

        FlowSessionBridge.setPendingKeyboardUtteranceId(utteranceId, defaults: defaults)

        XCTAssertEqual(
            FlowSessionBridge.pendingKeyboardUtteranceId(defaults: defaults),
            utteranceId
        )
    }

    func testResultMatcherRejectsPreviousHostGeneration() {
        let sessionId = UUID()
        let utteranceId = UUID()
        let result = FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            status: .final,
            text: "旧结果",
            hostGeneration: "old"
        )

        XCTAssertNil(
            FlowKeyboardResultMatcher.matchingResult(
                latest: result,
                activeSessionId: sessionId,
                currentUtteranceId: utteranceId,
                currentHostGeneration: "new"
            )
        )
    }

    func testDynamicBudgetsBoundWorstCaseDelivery() {
        XCTAssertEqual(FlowSessionKeys.polishTimeout(forCharacterCount: 80), 10)
        XCTAssertEqual(FlowSessionKeys.polishTimeout(forCharacterCount: 300), 20)
        XCTAssertEqual(FlowSessionKeys.polishTimeout(forCharacterCount: 900), 35)
        XCTAssertLessThanOrEqual(FlowSessionKeys.keyboardResultTimeout(engineMode: "cloud"), 65)
    }

    func testHardTimeoutDoesNotWaitForNonCooperativeOperation() async {
        let started = Date()

        do {
            _ = try await HardTimeout.run(seconds: 0.05) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                        continuation.resume(returning: "late")
                    }
                }
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
    }

    func testAudioRoutePolicyRebuildsHFPTransitions() {
        XCTAssertTrue(
            FlowAudioRouteRecoveryPolicy.shouldRebuild(
                reasonRaw: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue,
                formatIsStable: false,
                engineIsRunning: true
            )
        )
        XCTAssertFalse(
            FlowAudioRouteRecoveryPolicy.shouldRebuild(
                reasonRaw: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue,
                formatIsStable: true,
                engineIsRunning: true
            )
        )
        XCTAssertTrue(
            FlowAudioRouteRecoveryPolicy.shouldRebuild(
                reasonRaw: AVAudioSession.RouteChangeReason.categoryChange.rawValue,
                formatIsStable: false,
                engineIsRunning: true
            )
        )
        XCTAssertFalse(
            FlowAudioRouteRecoveryPolicy.shouldRebuild(
                reasonRaw: AVAudioSession.RouteChangeReason.categoryChange.rawValue,
                formatIsStable: true,
                engineIsRunning: true
            )
        )
        XCTAssertTrue(
            FlowAudioRouteRecoveryPolicy.shouldRebuild(
                reasonRaw: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue,
                formatIsStable: true,
                engineIsRunning: false
            )
        )
    }

    func testCaptureVoiceProcessingUsesSpeechOrientedSessionMode() {
        XCTAssertEqual(FlowCaptureVoiceProcessing.captureMode, .voiceChat)
        XCTAssertTrue(
            FlowCaptureVoiceProcessing.captureOptions.contains(.allowBluetoothHFP)
        )
        XCTAssertTrue(
            FlowCaptureVoiceProcessing.captureOptions.contains(.defaultToSpeaker)
        )
    }
}
