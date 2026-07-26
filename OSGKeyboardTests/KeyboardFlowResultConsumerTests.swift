// KeyboardFlowResultConsumerTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class KeyboardFlowResultConsumerTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.consumer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testEvaluateFinalDelivery() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowResultDelivery.writeFinal(
            text: "hello",
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            defaults: defaults
        )
        let outcome = KeyboardFlowResultConsumer.evaluate(
            latestResult: FlowSessionBridge.latestResult(defaults: defaults),
            activeSessionId: sessionId,
            currentUtteranceId: utteranceId
        )
        if case .final(let delivery) = outcome {
            XCTAssertEqual(delivery.text, "hello")
        } else {
            XCTFail("expected final delivery")
        }
    }

    func testEvaluateTerminalError() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowResultDelivery.writeError(
            message: "no speech",
            kind: .noSpeech,
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 2,
            defaults: defaults
        )
        let outcome = KeyboardFlowResultConsumer.evaluate(
            latestResult: FlowSessionBridge.latestResult(defaults: defaults),
            activeSessionId: sessionId,
            currentUtteranceId: utteranceId
        )
        if case .terminalError(let error) = outcome {
            XCTAssertEqual(error.kind, .noSpeech)
            XCTAssertEqual(error.message, "no speech")
        } else {
            XCTFail("expected terminal error")
        }
    }

    func testEvaluateNoneWhenSessionMismatch() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowResultDelivery.writeFinal(
            text: "hello",
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            defaults: defaults
        )
        XCTAssertEqual(
            KeyboardFlowResultConsumer.evaluate(
                latestResult: FlowSessionBridge.latestResult(defaults: defaults),
                activeSessionId: UUID(),
                currentUtteranceId: utteranceId
            ),
            .none
        )
    }
}
